#!/usr/bin/env python3
"""Validate repeated native Psiphon packet stages using Psiphon's own servers.

Uses the production Rust packet bridge, private per-stage storage and raw-IP
socketpairs. No external relay or personal server is required. This is a Linux
core integration proof, not an Android device test or a guarantee for all regions.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from test_mix_live_psiphon_packet import dns_query, free_port, stop, trace, wait_port
from test_mix_live_psiphon_packet_reverse import _wait_tunnel

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--psiphon", default="/tmp/psiphon-run/psiphon-tunnel-core-x86_64")
    parser.add_argument("--native-lib", default=str(ROOT / "core/aether/target/debug/libaether.so"))
    parser.add_argument("--stages", type=int, default=2)
    parser.add_argument("--timeout", type=float, default=100)
    parser.add_argument("--keep-temp", action="store_true")
    args = parser.parse_args()
    if not 2 <= args.stages <= 50:
        parser.error("--stages must be between 2 and 50")
    if not 1 <= args.timeout <= 180:
        parser.error("--timeout must be between 1 and 180 seconds per stage")
    for name in (args.psiphon, args.native_lib):
        if not Path(name).is_file():
            parser.error(f"required file missing: {name}")
    if not os.access(args.psiphon, os.X_OK):
        parser.error("Psiphon binary must be executable")

    directory = Path(tempfile.mkdtemp(prefix="mix-live-psiphon-repeat-"))
    directory.chmod(0o700)
    processes, handles, sockets, logs = [], [], [], []
    native = ctypes.CDLL(str(Path(args.native_lib).resolve()))
    native.aether_mix_packet_create.argtypes = [ctypes.c_char_p, ctypes.c_int]
    native.aether_mix_packet_create.restype = ctypes.c_longlong
    native.aether_mix_packet_is_ready.argtypes = [ctypes.c_longlong]
    native.aether_mix_packet_is_ready.restype = ctypes.c_int
    native.aether_mix_packet_stop.argtypes = [ctypes.c_longlong]
    bootstrap = json.loads((ROOT / "android/app/src/main/assets/mix_psiphon_bootstrap.json").read_text())
    results = []
    try:
        previous = None
        for index in range(args.stages):
            stage = directory / f"stage-{index}"
            stage.mkdir(mode=0o700)
            root = stage / "data"
            root.mkdir(mode=0o700)
            left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
            sockets.extend((left, right))
            port = free_port()
            config = dict(bootstrap, ClientPlatform="Linux", DataRootDirectory=str(root),
                          PacketTunnelTunFileDescriptor=right.fileno(), TunnelPoolSize=1,
                          DisableLocalSocksProxy=True, DisableLocalHTTPProxy=True,
                          LocalSocksProxyPort=0, LocalHttpProxyPort=0, DisableTunnels=False,
                          EnableLightProxyFallback=False, EnablePersonalLightProxyTunnels=False,
                          EmitDiagnosticNotices=True)
            if previous is not None:
                config["UpstreamProxyURL"] = f"socks5://127.0.0.1:{previous}"
            config_path = stage / "psiphon.json"
            config_path.write_text(json.dumps(config))
            config_path.chmod(0o600)
            notices = stage / "notices.log"
            notices.touch(mode=0o600)
            log = (stage / "process.log").open("w")
            logs.append(log)
            process = subprocess.Popen([args.psiphon, "-config", str(config_path),
                                        "-dataRootDirectory", str(root), "-notices", str(notices)],
                                       pass_fds=(right.fileno(),), stdout=log, stderr=subprocess.STDOUT)
            processes.append(process)
            right.close()
            packet_config = json.dumps(dict(ipv4="10.0.0.3", ipv6="fd00::3", mtu=1500,
                                            listen=f"127.0.0.1:{port}", dns=["10.0.0.2:53"])).encode()
            handle = native.aether_mix_packet_create(packet_config, left.fileno())
            if handle <= 0:
                raise RuntimeError(f"stage {index}: native packet bridge rejected FD/config")
            handles.append(handle)
            deadline = time.monotonic() + 10
            while not native.aether_mix_packet_is_ready(handle):
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"stage {index}: packet bridge not ready")
                time.sleep(.05)
            wait_port(port, process, 10)
            _wait_tunnel(process, notices, args.timeout)
            # Each prefix must actually carry TCP and UDP; readiness notices alone
            # do not prove a functioning packet tunnel.
            for _ in range(2):
                response = trace(port)
                if "warp=off" not in response.splitlines():
                    raise AssertionError(f"stage {index}: unexpected WARP egress")
            dns_bytes = dns_query(port)
            results.append(dict(stage=index, tcp_probes=2, udp_dns_bytes=dns_bytes))
            previous = port
            print(f"stage {index + 1}/{args.stages}: real TCP and UDP passed", flush=True)
        # Keep the inner engines and SOCKS listeners running, cut only stage 0.
        stop(processes[0])
        cut = subprocess.run(["curl", "--silent", "--show-error", "--max-time", "8",
                              "--socks5-hostname", f"127.0.0.1:{previous}",
                              "https://www.cloudflare.com/cdn-cgi/trace"], capture_output=True)
        if cut.returncode == 0:
            raise AssertionError("nested Psiphon bypassed stopped first stage")
        print(json.dumps(dict(status="PASS", direction="→".join(["Psiphon"] * args.stages),
                              stages=results, first_stage_cut="fail-closed", external_relay=False)), flush=True)
    finally:
        for process in reversed(processes):
            stop(process)
        for handle in reversed(handles):
            native.aether_mix_packet_stop(handle)
        for endpoint in sockets:
            endpoint.close()
        for log in logs:
            log.close()
        if args.keep_temp:
            print(f"kept temp: {directory}", file=sys.stderr)
        else:
            shutil.rmtree(directory, ignore_errors=True)


if __name__ == "__main__":
    main()
