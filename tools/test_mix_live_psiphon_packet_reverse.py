#!/usr/bin/env python3
"""Live no-relay reverse WARP -> Psiphon raw packet proof."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from test_mix_live_psiphon_packet import free_port, trace, dns_query, wait_port, stop
from test_mix_live_http_warp import WORKER, run_exporter

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "android/app/src/main/assets/mix_psiphon_bootstrap.json"
DEFAULT_PSI = "/tmp/psiphon-run/psiphon-tunnel-core-x86_64"
DEFAULT_ACCOUNT = "/tmp/mix-live-warp/account.toml"


def _trace_ip(text: str) -> str:
    return next((x[3:].strip() for x in text.splitlines() if x.startswith("ip=")), "")


def _wait_tunnel(proc: subprocess.Popen, notice_file: Path, timeout: float) -> None:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if proc.poll() is not None:
            raise RuntimeError(f"Psiphon exited before Tunnels=1: {notice_file.read_text(errors='replace')[-3000:]}")
        for line in notice_file.read_text(errors="replace").splitlines():
            try:
                n = json.loads(line)
            except json.JSONDecodeError:
                continue
            if n.get("noticeType") == "Tunnels" and isinstance(n.get("data"), dict) and n["data"].get("count") == 1:
                return
        time.sleep(.25)
    raise TimeoutError("Psiphon did not report Tunnels data.count 1")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--psiphon", default=DEFAULT_PSI)
    ap.add_argument("--classpath", default="/tmp/mix-routing-classpath")
    ap.add_argument("--native-lib", default=str(ROOT / "core/aether/target/debug/libaether.so"))
    ap.add_argument("--account", default=DEFAULT_ACCOUNT)
    ap.add_argument("--timeout", type=float, default=100.0)
    ap.add_argument("--keep-temp", action="store_true")
    a = ap.parse_args()
    a.timeout = min(a.timeout, 100.0)
    psi, cp_file, native, account = map(Path, (a.psiphon, a.classpath, a.native_lib, a.account))
    for p in (psi, native, account, cp_file, BOOTSTRAP):
        if not p.is_file():
            ap.error(f"required file not found: {p}")
    if not os.access(psi, os.X_OK):
        ap.error(f"Psiphon binary is not executable: {psi}")

    td = Path(tempfile.mkdtemp(prefix="mix-live-psiphon-packet-reverse-")); td.chmod(0o700)
    before = hashlib.sha256(account.read_bytes()).digest()
    processes: list[subprocess.Popen] = []
    warp = ps = None; hid = 0; left = right = None
    try:
        # The copied identity is private and is the only account path supplied to WARP.
        account_copy = td / "aether-warp.toml"
        shutil.copyfile(account, account_copy); account_copy.chmod(0o600)
        root = td / "psiphon-root"; root.mkdir(mode=0o700)
        cp = str(ROOT / "build/app/tmp/kotlin-classes/debug") + os.pathsep + cp_file.read_text().strip() + os.pathsep + str(td)
        warp_port = free_port()
        warp_input = {"config_path": "__APP_FILES__/aether-warp.toml", "wireguard_config_path": "__APP_FILES__/aether-warp.toml", "protocol": "wg", "forced_peer": "162.159.192.1:2408", "wireguard_data_check": True, "log_level": "error", "upstreamSupportsUdp": True}
        warp_cfg = td / "warp.json"
        warp_cfg.write_text(json.dumps(run_exporter(cp, td, warp_input, warp_port, ""))); warp_cfg.chmod(0o600)
        warp_log = (td / "warp.log").open("w")
        warp = subprocess.Popen([sys.executable, "-c", WORKER, str(native), str(warp_cfg)], stdout=warp_log, stderr=subprocess.STDOUT, text=True)
        processes.append(warp); wait_port(warp_port, warp, timeout=min(35.0, a.timeout))
        good = 0; end = time.monotonic() + min(45.0, a.timeout)
        outer = ""
        while time.monotonic() < end and good < 2:
            try: out = trace(warp_port)
            except Exception: good = 0; time.sleep(.5); continue
            if "warp=on" in out.splitlines(): good += 1; outer = _trace_ip(out)
            else: good = 0
        if good < 2 or not outer:
            raise AssertionError("direct native WARP did not return warp=on twice with an outer IP")

        # Psiphon receives complete raw IP datagrams, not its legacy local SOCKS/TCP mode.
        left, right = socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM); right.set_inheritable(True)
        packet_listen = free_port()
        cfg = json.loads(BOOTSTRAP.read_text())
        cfg.update({"ClientVersion": "1", "ClientPlatform": "Linux", "DataRootDirectory": str(root), "PacketTunnelTunFileDescriptor": right.fileno(), "TunnelPoolSize": 1, "DisableLocalSocksProxy": True, "DisableLocalHTTPProxy": True, "LocalSocksProxyPort": 0, "LocalHttpProxyPort": 0, "DisableTunnels": False, "EnableLightProxyFallback": False, "EnablePersonalLightProxyTunnels": False, "UpstreamProxyURL": f"socks5://127.0.0.1:{warp_port}", "EmitDiagnosticNotices": True})
        psi_cfg = td / "psiphon.json"; psi_cfg.write_text(json.dumps(cfg)); psi_cfg.chmod(0o600)
        notices = td / "psiphon-notices.log"; notices.touch(mode=0o600); notices.chmod(0o600)
        stdout_log = (td / "psiphon-stdout.log").open("w")
        ps = subprocess.Popen([str(psi), "-config", str(psi_cfg), "-dataRootDirectory", str(root), "-notices", str(notices)], pass_fds=(right.fileno(),), stdout=stdout_log, stderr=subprocess.STDOUT, text=True)
        processes.append(ps); right.close(); right = None

        lib = ctypes.CDLL(str(native)); lib.aether_mix_packet_create.argtypes = [ctypes.c_char_p, ctypes.c_int]; lib.aether_mix_packet_create.restype = ctypes.c_longlong
        lib.aether_mix_packet_is_ready.argtypes = [ctypes.c_longlong]; lib.aether_mix_packet_is_ready.restype = ctypes.c_int
        lib.aether_mix_packet_stop.argtypes = [ctypes.c_longlong]
        packet_cfg = json.dumps({"ipv4": "10.0.0.3", "ipv6": "fd00::3", "mtu": 1500, "listen": f"127.0.0.1:{packet_listen}"}).encode()
        hid = lib.aether_mix_packet_create(packet_cfg, left.fileno())
        if hid < 1: raise RuntimeError("aether_mix_packet_create rejected raw packet socket")
        ready_end = time.monotonic() + min(25.0, a.timeout)
        while time.monotonic() < ready_end and not lib.aether_mix_packet_is_ready(hid):
            if ps.poll() is not None: raise RuntimeError("Psiphon exited while packet stack started")
            time.sleep(.1)
        if not lib.aether_mix_packet_is_ready(hid): raise TimeoutError("native raw packet stack not ready")
        wait_port(packet_listen, timeout=10)
        _wait_tunnel(ps, notices, min(45.0, a.timeout))

        inner = trace(packet_listen)
        if "warp=off" not in inner.splitlines(): raise AssertionError("Psiphon TCP probe did not prove warp=off")
        psi_ip = _trace_ip(inner)
        if not psi_ip or psi_ip == outer: raise AssertionError(f"Psiphon egress IP is not distinct from outer WARP ({outer!r})")
        dns_bytes = dns_query(packet_listen)

        stop(warp); warp = None
        cut = subprocess.run(["curl", "--silent", "--show-error", "--max-time", "8", "--socks5-hostname", f"127.0.0.1:{packet_listen}", "https://www.cloudflare.com/cdn-cgi/trace"], capture_output=True, text=True, timeout=12)
        if cut.returncode == 0: raise AssertionError("Psiphon packet traffic bypassed stopped outer WARP")
        print(json.dumps({"status": "PASS", "direction": "WARP→Psiphon", "outer_warp": "on_twice", "inner_warp": "off", "distinct_exit_ip": True, "tcp": "Cloudflare trace", "udp_dns_bytes": dns_bytes, "tunnels": 1, "outer_cut": "fail-closed", "bounded_error": cut.stderr[-300:]}, sort_keys=True), flush=True)
    finally:
        if warp: stop(warp)
        if ps: stop(ps)
        if hid:
            try: lib.aether_mix_packet_stop(hid)
            except Exception: pass
        for s in (left, right):
            try:
                if s: s.close()
            except Exception: pass
        for p in reversed(processes): stop(p)
        try: stdout_log.close()
        except Exception: pass
        try: warp_log.close()
        except Exception: pass
        if hashlib.sha256(account.read_bytes()).digest() != before: raise AssertionError("WARP account fixture was modified")
        if a.keep_temp: print(f"kept private temp: {td}", file=sys.stderr)
        else: shutil.rmtree(td, ignore_errors=True)


if __name__ == "__main__":
    try: main()
    except Exception as e: print(f"FAIL: {e}", file=sys.stderr); raise
