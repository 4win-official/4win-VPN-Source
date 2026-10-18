#!/usr/bin/env python3
"""Opt-in live HTTP stages -> Kotlin Mix bridge -> native WARP integration test."""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Reuse the established relay/JVM lifecycle helpers verbatim.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_mix_udp_bridge import free_port, java_harness, terminate, wait_port, wait_ready

ROOT = Path(__file__).resolve().parents[1]
WORKER = """\
import ctypes, json, signal, sys
lib = ctypes.CDLL(sys.argv[1])
lib.aether_start_json.argtypes = [ctypes.c_char_p]
lib.aether_start_json.restype = ctypes.c_int
lib.aether_stop.argtypes = []
def stop(*_):
    try: lib.aether_stop()
    finally: raise SystemExit(0)
signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
print('STARTED', flush=True)
rc = lib.aether_start_json(open(sys.argv[2], 'rb').read())
print('NATIVE_RETURN ' + str(rc), flush=True)
sys.exit(1 if rc else 0)
"""


def run_exporter(cp: str, root: Path, warp: dict, listen: int, upstream: str) -> dict:
    src = root / "WarpExporter.java"
    src.write_text(r'''import java.nio.file.*; import org.json.*; import com.forwin.vpn.mix.MixWarpConfig;
public final class WarpExporter {
 public static void main(String[] a) throws Exception {
  JSONObject c = new JSONObject(Files.readString(Path.of(a[0])));
  System.out.print(MixWarpConfig.INSTANCE.build(c, a[1], Integer.parseInt(a[2]), a[3]).toString());
 }
}''')
    q = subprocess.run(["javac", "-cp", cp, "-d", str(root), str(src)], capture_output=True, text=True)
    if q.returncode:
        raise RuntimeError("javac failed: " + q.stderr[-4000:])
    cfg = root / "warp-input.json"
    cfg.write_text(json.dumps(warp))
    return json.loads(subprocess.check_output([
        "java", "-cp", str(root) + os.pathsep + cp, "WarpExporter",
        str(cfg), str(root), str(listen), upstream,
    ], text=True))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--classpath", default="/tmp/mix-routing-classpath")
    ap.add_argument("--xray", default="/tmp/xray-mix-test/xray")
    ap.add_argument("--native-lib", default=str(ROOT / "core/aether/target/debug/libaether.so"))
    ap.add_argument("--account", required=True)
    ap.add_argument("--keep-temp", action="store_true")
    ap.add_argument("--timeout", type=float, default=90.0)
    ap.add_argument("--native-worker", nargs=2, metavar=("LIB", "CONFIG"), help=argparse.SUPPRESS)
    a = ap.parse_args()
    if a.native_worker:
        os.execv(sys.executable, [sys.executable, "-c", WORKER, *a.native_worker])

    cp_file = Path(a.classpath)
    xray = Path(a.xray)
    native_lib = Path(a.native_lib)
    account = Path(a.account).resolve()
    if not account.is_file():
        ap.error("--account must be an existing Aether WARP identity")
    if not xray.is_file() or not os.access(xray, os.X_OK):
        ap.error(f"xray executable not found: {xray}")
    if not native_lib.is_file():
        ap.error(f"native library not found: {native_lib}")
    cp = cp_file.read_text().strip()
    td = Path(tempfile.mkdtemp(prefix="mix-live-http-warp-"))
    processes: list[subprocess.Popen] = []
    native_proc = bridge = proxy = sidecar = relay = None
    account_copy = td / "aether-warp.toml"
    try:
        shutil.copyfile(account, account_copy)
        account_copy.chmod(0o600)
        before = hashlib.sha256(account.read_bytes()).digest()
        token = "bridge-test-token-0123456789abcdef"
        http, relay_port, first_prefix, second_prefix, u0, u1, r0, r1, native_port = [free_port() for _ in range(9)]
        cert, key, san = td / "cert.pem", td / "key.pem", td / "san.cnf"
        san.write_text("[req]\ndistinguished_name=dn\nreq_extensions=reqext\n[dn]\n[reqext]\nsubjectAltName=DNS:localhost\n")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=localhost", "-config", str(san), "-extensions", "reqext", "-keyout", str(key), "-out", str(cert)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        hcp = cp + os.pathsep + str(td)
        java_harness(hcp, td)

        http_cfg = {"log": {"access": str(td / "http-access.log"), "loglevel": "info"}, "inbounds": [{"listen": "127.0.0.1", "port": http, "protocol": "http", "settings": {}}], "outbounds": [{"protocol": "freedom", "tag": "direct"}]}
        http_path = td / "http.json"; http_path.write_text(json.dumps(http_cfg))
        plan = {"hops": [{"protocol": "xray", "outbound": {"protocol": "http", "settings": {"servers": [{"address": "127.0.0.1", "port": http}]}}}, {"protocol": "xray", "outbound": {"protocol": "http", "settings": {"servers": [{"address": "127.0.0.1", "port": http}]}}}]}
        side_path = td / "sidecar.json"
        q = subprocess.run(["java", "-cp", hcp, "com.forwin.vpn.mix.BridgeHarness", str(first_prefix), str(second_prefix), str(u0), str(u1), str(r0), str(r1), str(relay_port), str(http), token, "localhost", str(cert), str(side_path), "config-only"], capture_output=True, text=True, timeout=10)
        q.check_returncode()
        side = json.loads(side_path.read_text()); side["log"] = {"access": str(td / "sidecar-access.log"), "loglevel": "info"}; side_path.write_text(json.dumps(side))

        warp_input = {"config_path": "__APP_FILES__/aether-warp.toml", "wireguard_config_path": "__APP_FILES__/aether-warp.toml", "protocol": "wg", "forced_peer": "162.159.192.1:2408", "wireguard_data_check": True, "log_level": "error", "upstreamSupportsUdp": True}
        warp = run_exporter(hcp, td, warp_input, native_port, f"socks5://127.0.0.1:{second_prefix}")
        assert "upstreamSupportsUdp" not in warp and warp["upstream_proxy"].endswith(str(second_prefix))
        warp_path = td / "warp.json"; warp_path.write_text(json.dumps(warp))

        env = os.environ.copy(); env["MIX_RELAY_TOKEN"] = token
        relay = subprocess.Popen([sys.executable, str(ROOT / "tools/mix_udp_relay.py"), "--host", "127.0.0.1", "--port", str(relay_port), "--cert", str(cert), "--key", str(key), "--allow-private"], env=env, stdout=(td / "relay.log").open("w"), stderr=subprocess.STDOUT, text=True); processes.append(relay); wait_port(relay_port, relay)
        proxy = subprocess.Popen([str(xray), "-c", str(http_path)], stdout=(td / "http-xray.log").open("w"), stderr=subprocess.STDOUT, text=True); processes.append(proxy); wait_port(http, proxy)
        sidecar = subprocess.Popen([str(xray), "-c", str(side_path)], stdout=(td / "sidecar-xray.log").open("w"), stderr=subprocess.STDOUT, text=True); processes.append(sidecar)
        for p in (first_prefix, second_prefix, u0, u1): wait_port(p, sidecar)
        bridge = subprocess.Popen(["java", "-cp", hcp, "com.forwin.vpn.mix.BridgeHarness", str(first_prefix), str(second_prefix), str(u0), str(u1), str(r0), str(r1), str(relay_port), str(http), token, "localhost", str(cert), str(side_path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True); processes.append(bridge); wait_ready(bridge)

        native_proc = subprocess.Popen([sys.executable, "-c", WORKER, str(native_lib), str(warp_path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True); processes.append(native_proc)
        wait_port(native_port, native_proc, timeout=min(30.0, a.timeout))
        def probe(seconds=8):
            return subprocess.run(["curl", "--silent", "--show-error", "--max-time", str(seconds), "--socks5-hostname", f"127.0.0.1:{native_port}", "https://www.cloudflare.com/cdn-cgi/trace"], capture_output=True, text=True)
        deadline = time.monotonic() + a.timeout
        successes = 0
        while time.monotonic() < deadline and successes < 2:
            if native_proc.poll() is not None: raise RuntimeError("native WARP exited before live readiness")
            r = probe(8)
            if r.returncode == 0 and "warp=on" in r.stdout.splitlines(): successes += 1
            else: successes = 0
            if successes < 2: time.sleep(1)
        if successes < 2: raise AssertionError("live HTTP stages -> WARP did not produce warp=on twice")
        if not all(p.poll() is None for p in (relay, sidecar, bridge, native_proc)): raise AssertionError("relay/sidecar/bridge/native stopped after success")
        terminate(proxy); time.sleep(1)
        failed = probe(8)
        if failed.returncode == 0: raise AssertionError("traffic bypassed cut HTTP proxy")
        if not all(p.poll() is None for p in (relay, sidecar, bridge)): raise AssertionError("relay/sidecar/bridge stopped during fail-closed check")
        if hashlib.sha256(account.read_bytes()).digest() != before: raise AssertionError("account fixture was modified")
        print("PASS live HTTP stages -> Kotlin bridge -> native WARP: Cloudflare warp=on twice; fail-closed after HTTP cut", flush=True)
    finally:
        for p in reversed(processes): terminate(p, timeout=5)
        if a.keep_temp:
            print(f"kept temp (contains copied account, mode 600): {td}", file=sys.stderr)
        else:
            shutil.rmtree(td, ignore_errors=True)


if __name__ == "__main__":
    try: main()
    except Exception as e:
        print(f"FAIL: {e}", file=sys.stderr); raise
