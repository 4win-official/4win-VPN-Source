#!/usr/bin/env python3
"""Cold-start desktop core smoke test with remote discovery disabled.

Uses the exact verified Android seed and IDs, in independent fresh datastores.
Covers SOCKS/HTTPS and Mix's native packet stack/UDP DNS/HTTPS. No Android device,
VPN permission, mobile underlay or owner-network claim is implied. No build runs.
Requires an existing Psiphon console binary, libaether and Python cryptography.
Raw SDK notices stay in a temporary directory and are deleted; endpoints are not
printed. Public probe traffic is limited to example.com and its DNS lookup.
"""
from __future__ import annotations

import argparse
import ctypes
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import zlib

from update_psiphon_bootstrap import verify_package
from test_mix_live_psiphon_packet import dns_query, free_port, stop

ROOT = Path(__file__).resolve().parents[1]


def connected(notices: Path) -> bool:
    for line in notices.read_text(errors="replace").splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if item.get("noticeType") == "Tunnels" and item.get("data", {}).get("count", 0) > 0:
            return True
    return False


def run(args: argparse.Namespace, mode: str, entries: str, bootstrap: dict) -> None:
    with tempfile.TemporaryDirectory(prefix=f"psiphon-seed-{mode}-") as directory:
        root = Path(directory)
        (root / "data").mkdir()  # Android's SDK prepares its data root itself.
        seed = root / "entries.dat"
        seed.write_text(entries)
        port = free_port()
        config = dict(bootstrap, DataRootDirectory=str(root / "data"),
                      DisableRemoteServerListFetcher=True, EmitDiagnosticNotices=False,
                      EstablishTunnelTimeoutSeconds=int(args.timeout),
                      LocalSocksProxyPort=port, LocalHttpProxyPort=0,
                      DisableLocalHTTPProxy=True)
        left = right = native = None
        handle = 0
        process = None
        try:
            if mode == "packet":
                left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM)
                config.update(PacketTunnelTunFileDescriptor=right.fileno(), TunnelPoolSize=1,
                              DisableLocalSocksProxy=True, LocalSocksProxyPort=0,
                              DisableTunnels=False, EnableLightProxyFallback=False,
                              EnablePersonalLightProxyTunnels=False)
                native = ctypes.CDLL(str(args.native_lib.resolve()))
                native.aether_mix_packet_create.argtypes = [ctypes.c_char_p, ctypes.c_int]
                native.aether_mix_packet_create.restype = ctypes.c_longlong
                native.aether_mix_packet_is_ready.argtypes = [ctypes.c_longlong]
                native.aether_mix_packet_is_ready.restype = ctypes.c_int
                native.aether_mix_packet_stop.argtypes = [ctypes.c_longlong]
                stack_config = dict(ipv4="10.0.0.3", ipv6="fd00::3", mtu=1500,
                                    listen=f"127.0.0.1:{port}", dns=["10.0.0.2:53"])
                handle = native.aether_mix_packet_create(json.dumps(stack_config).encode(), left.fileno())
                if handle < 1:
                    raise RuntimeError("native packet stack rejected startup")
            config_file = root / "config.json"
            config_file.write_text(json.dumps(config))
            notices = root / "notices.log"
            with notices.open("w") as log:
                process = subprocess.Popen([str(args.psiphon.resolve()), "-config", str(config_file),
                                            "-serverList", str(seed)], stdout=log, stderr=log,
                                           pass_fds=(right.fileno(),) if right else ())
            deadline = time.monotonic() + args.timeout
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f"core exited ({process.returncode}); raw notices withheld")
                if connected(notices) and (not native or native.aether_mix_packet_is_ready(handle)):
                    break
                time.sleep(.25)
            else:
                raise TimeoutError("no ready tunnel before deadline; raw notices withheld")
            result = subprocess.run(["curl", "--silent", "--show-error", "--max-time", "25",
                                     "--socks5-hostname", f"127.0.0.1:{port}",
                                     "--output", "/dev/null", "--write-out", "%{http_code}",
                                     "https://example.com/"], capture_output=True, text=True)
            if result.returncode or result.stdout != "200":
                raise RuntimeError(f"HTTPS probe failed (curl={result.returncode}); diagnostics withheld")
            if mode == "packet":
                dns_query(port)
            print(f"PASS {mode}: fresh datastore, remote discovery disabled, embedded import, tunnel, HTTPS 200"
                  + (", UDP DNS answer" if mode == "packet" else ""), flush=True)
        finally:
            stop(process)
            if native and handle > 0:
                native.aether_mix_packet_stop(handle)
            for endpoint in (left, right):
                if endpoint:
                    endpoint.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--psiphon", type=Path, required=True)
    parser.add_argument("--native-lib", type=Path, default=ROOT / "core/aether/target/debug/libaether.so")
    parser.add_argument("--mode", choices=("standalone", "packet", "both"), default="both")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    if not args.psiphon.is_file() or args.timeout <= 0:
        parser.error("an existing console binary and positive timeout are required")
    if args.mode != "standalone" and not args.native_lib.is_file():
        parser.error("packet mode requires an existing native library; this test never builds one")
    assets = ROOT / "android/app/src/main/assets"
    bootstrap = json.loads((assets / "mix_psiphon_bootstrap.json").read_text())
    blob = (assets / "psiphon_server_list.bin").read_bytes()
    count, _ = verify_package(blob, bootstrap["RemoteServerListSignaturePublicKey"])
    entries = json.loads(zlib.decompress(blob))["data"]
    print(f"Verified signed seed: {count} entries; testing desktop core only", flush=True)
    for mode in ("standalone", "packet") if args.mode == "both" else (args.mode,):
        run(args, mode, entries, bootstrap)


if __name__ == "__main__":
    main()
