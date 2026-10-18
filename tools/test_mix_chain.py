#!/usr/bin/env python3
"""Real local Xray MixConfigBuilder integration test.

This deliberately tests the compiled topology, rather than printing labels.  Run
as root (the DNS fixture binds TCP/53), for example::

    sudo python3 tools/test_mix_chain.py --xray /tmp/xray-mix-test/xray \
      --dart /tmp/flutter/bin/cache/dart-sdk/bin/dart
"""
import argparse
import json
import os
import select
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise EOFError("short SOCKS frame")
        data += chunk
    return data


def relay(a, b):
    a.settimeout(None); b.settimeout(None)
    try:
        while True:
            ready, _, _ = select.select([a, b], [], [], 5)
            if not ready:
                return
            for src in ready:
                data = src.recv(65536)
                if not data:
                    return
                (b if src is a else a).sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try: s.close()
            except OSError: pass


class Relay:
    """A SOCKS5 relay whose CONNECT log is the topology oracle."""
    def __init__(self):
        self.sock = socket.socket(); self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0)); self.sock.listen(64)
        self.port = self.sock.getsockname()[1]
        self.stop = threading.Event(); self.blocked = False
        self.logs = []; self._active = set(); self._lock = threading.Lock()
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while not self.stop.is_set():
            try: c, _ = self.sock.accept()
            except OSError: break
            with self._lock: self._active.add(c)
            threading.Thread(target=self._client, args=(c,), daemon=True).start()

    def _client(self, c):
        try:
            c.settimeout(10)
            if self.blocked:
                return
            _, n = recv_exact(c, 2); recv_exact(c, n); c.sendall(b"\x05\x00")
            head = recv_exact(c, 4); cmd, atyp = head[1], head[3]
            if atyp == 1: dst = socket.inet_ntoa(recv_exact(c, 4))
            elif atyp == 3:
                n = recv_exact(c, 1)[0]; dst = recv_exact(c, n).decode()
            elif atyp == 4: dst = socket.inet_ntop(socket.AF_INET6, recv_exact(c, 16))
            else: raise ValueError("bad SOCKS address type")
            port = struct.unpack("!H", recv_exact(c, 2))[0]
            self.logs.append((cmd, dst, port, time.monotonic()))
            if cmd != 1:
                c.sendall(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00"); return
            if dst == "target.test": dst = "127.0.0.1"
            upstream = socket.create_connection((dst, port), 10)
            try:
                c.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
                relay(c, upstream)
            finally:
                try: upstream.close()
                except OSError: pass
        except (OSError, EOFError, ValueError):
            pass
        finally:
            with self._lock: self._active.discard(c)
            try: c.close()
            except OSError: pass

    def reset_connections(self):
        with self._lock: active = list(self._active)
        for c in active:
            try: c.shutdown(socket.SHUT_RDWR)
            except OSError: pass
            try: c.close()
            except OSError: pass

    def block(self):
        self.blocked = True
        self.reset_connections()

    def close(self):
        self.stop.set(); self.blocked = True; self.reset_connections()
        try: self.sock.close()
        except OSError: pass


class Fixture:
    def __init__(self):
        self.target = socket.socket(); self.target.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.target.bind(("127.0.0.1", 0)); self.target.listen(32); self.http_port = self.target.getsockname()[1]
        self.http_stop = threading.Event(); self.http_hits = 0
        threading.Thread(target=self._http, daemon=True).start()
        self.dns = socket.socket(); self.dns.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            self.dns.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        try: self.dns.bind(("127.0.0.1", 53))
        except PermissionError as e: raise SystemExit("DNS fixture needs TCP/53; rerun with sudo python3") from e
        self.dns.listen(32); self.dns.settimeout(.5); self.dns_stop = threading.Event(); self.dns_queries = []
        threading.Thread(target=self._dns_accept, daemon=True).start()

    def _http(self):
        while not self.http_stop.is_set():
            try: c, _ = self.target.accept()
            except OSError: break
            self.http_hits += 1
            threading.Thread(target=self._http_client, args=(c,), daemon=True).start()

    def _http_client(self, c):
        try:
            c.settimeout(5); c.recv(4096)
            c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\nMIX-OK-123")
        except OSError: pass
        finally: c.close()

    def _dns_accept(self):
        while not self.dns_stop.is_set():
            try: c, _ = self.dns.accept()
            except socket.timeout: continue
            except OSError: break
            threading.Thread(target=self._dns_client, args=(c,), daemon=True).start()

    def _dns_client(self, c):
        try:
            c.settimeout(5)
            while not self.dns_stop.is_set():
                hdr = c.recv(2)
                if not hdr: return
                q = recv_exact(c, struct.unpack("!H", hdr)[0]); self.dns_queries.append(q)
                answer = dns_reply(q)
                if answer: c.sendall(struct.pack("!H", len(answer)) + answer)
        except (OSError, EOFError, socket.timeout): pass
        finally: c.close()

    def close(self):
        self.http_stop.set(); self.dns_stop.set()
        for s in (self.target, self.dns):
            try: s.close()
            except OSError: pass


def dns_reply(q):
    if len(q) < 12: return None
    end = 12
    while end < len(q) and q[end]: end += q[end] + 1
    if end + 5 > len(q): return None
    question = q[12:end + 5]
    qtype = struct.unpack("!H", q[end + 1:end + 3])[0]
    if qtype != 1:
        return q[:2] + b"\x81\x80\x00\x01\x00\x00\x00\x00\x00\x00" + question
    return q[:2] + b"\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00" + question + b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x1e\x00\x04\x7f\x00\x00\x01"


def dns_query(ident, label, qtype=1):
    name = bytes([len(label)]) + label.encode() + b"\x04test\x00"
    return ident + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00" + name + struct.pack("!HH", qtype, 1)


def send_dns(port, ident, label, timeout=5, qtype=1):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(timeout)
    try:
        s.sendto(dns_query(ident, label, qtype), ("127.0.0.1", port)); return s.recvfrom(2048)[0]
    finally: s.close()


def make_config(ports, dns, out, dart, dns_prefixes):
    helper = ROOT / "tools/.mix_builder_runner.dart"
    hops = []
    for i, port in enumerate(ports):
        if i in dns_prefixes: hops.append(f"const MixHop(protocol:'direct_dns',serverId:'{dns}')")
        hops.append(f"MixHop(protocol:'proxy',serverId:'p{port}')")
    if len(ports) in dns_prefixes: hops.append(f"const MixHop(protocol:'direct_dns',serverId:'{dns}')")
    helper.write_text(f"""import 'dart:io';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/models/dns_server.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/services/mix_config_builder.dart';
void main() {{ final ps={ports!r}.map((p)=>ProxyServer(id:'p$p',remark:'local',link:'socks5://127.0.0.1:$p',protocol:'socks5',address:'127.0.0.1',port:p)).toList(); final s=MixStrategy(id:'t',name:'local',hops:[{', '.join(hops)}]); File('{out}').writeAsStringSync(MixConfigBuilder.build(strategy:s,xrayServers:const [],proxyServers:ps,dnsServers:[DnsServer(name:'local',primaryDns:'{dns}',description:'local',country:'local')])); }}
""")
    try: subprocess.run([dart, "run", str(helper)], cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    finally: helper.unlink(missing_ok=True)


def start_xray(xray, cfg):
    p = subprocess.Popen([str(xray), "-c", str(cfg)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(1)
    if p.poll() is not None:
        err = p.stderr.read(); raise AssertionError(f"xray failed to start: {err[-1000:]}")
    return p


def restart_xray(proc, xray, cfg, relays):
    proc.terminate()
    try: proc.wait(timeout=5)
    except subprocess.TimeoutExpired: proc.kill(); proc.wait()
    for r in relays: r.reset_connections()
    return start_xray(xray, cfg)


def assert_log_delta(relays, before, expected, kind):
    delta = [r.logs[before[i]:] for i, r in enumerate(relays)]
    touched = [bool(x) for x in delta]
    assert touched == expected, f"{kind}: expected relay traversal {expected}, got {touched}; delta={delta}"
    assert all(any(x[0] == 1 for x in d) for d in delta if d), f"{kind}: missing CONNECT in {delta}"
    return delta


def http_probe(url):
    return subprocess.run(["curl", "--silent", "--show-error", "--max-time", "12", "--socks5-hostname", "127.0.0.1:10808", url], text=True, capture_output=True)


def run_case(position, blocks, xray, dart):
    repeated = position == "repeated"
    tunnels = blocks - (3 if repeated else 1)
    assert tunnels >= 1
    prefixes = [0, tunnels // 2, tunnels] if repeated else [{"beginning": 0, "middle": tunnels // 2, "end": tunnels}[position]]
    relays = [Relay() for _ in range(tunnels)]; fixture = Fixture(); proc = None
    try:
        with tempfile.TemporaryDirectory(prefix="mix-chain-") as td:
            cfg = Path(td) / "config.json"; make_config([r.port for r in relays], "127.0.0.1", cfg, dart, prefixes)
            c = json.loads(cfg.read_text()); inbounds = c.setdefault("inbounds", [])
            policy_ports = []
            probe_prefixes = prefixes[-1:] if repeated else prefixes
            for i, prefix in enumerate(probe_prefixes):
                s = socket.socket(); s.bind(("127.0.0.1", 0)); policy_ports.append(s.getsockname()[1]); s.close()
                tag = "mix-dns" if repeated or i == len(probe_prefixes) - 1 else f"mix-dns-policy-{i}"
                inbounds.append({"tag": f"dns-test-{i}", "listen": "127.0.0.1", "port": policy_ports[-1], "protocol": "dokodemo-door", "settings": {"address": "203.0.113.53", "port": 53, "network": "udp"}})
                c.setdefault("routing", {}).setdefault("rules", []).insert(0, {"type": "field", "inboundTag": [f"dns-test-{i}"], "outboundTag": tag})
            cfg.write_text(json.dumps(c)); proc = start_xray(xray, cfg)
            url = f"http://target.test:{fixture.http_port}/"
            before = [len(r.logs) for r in relays]; hr = http_probe(url)
            assert hr.returncode == 0 and hr.stdout == "MIX-OK-123", f"{position}: HTTP failed: {hr.stderr}"
            assert_log_delta(relays, before, [True] * tunnels, "HTTP")
            dns_ok = []
            for i, prefix in enumerate(probe_prefixes):
                before = [len(r.logs) for r in relays]
                ans = send_dns(policy_ports[i], bytes([0x50, i + 1]), f"mix{i}{time.time_ns()}")
                ok = ans[:2] == bytes([0x50, i + 1]) and ans[2] & 0x80 and not ans[3] & 0x0f and b"\x7f\x00\x00\x01" in ans
                assert ok, f"{position}: DNS policy {i} returned no valid answer"
                assert_log_delta(relays, before, [j < prefix for j in range(tunnels)], f"DNS-prefix-{prefix}")
                dns_ok.append(ok)
                if repeated:
                    before_queries = len(fixture.dns_queries); before = [len(r.logs) for r in relays]
                    txt = send_dns(policy_ports[i], b"\x60\x01", f"txt{time.time_ns()}", qtype=16)
                    assert txt[:2] == b"\x60\x01" and txt[2] & 0x80 and not (txt[3] & 0x0f) and txt[6:8] == b"\x00\x00", "repeated TXT/non-A forwarding failed"
                    assert len(fixture.dns_queries) > before_queries, "repeated TXT query did not reach DNS fixture"
                    assert_log_delta(relays, before, [j < prefix for j in range(tunnels)], "DNS-TXT-prefix")
            # Drop once after the DNS boundary (DNS-before-drop must succeed), and
            # once inside the DNS prefix where applicable (DNS-containing-drop fails).
            drop_tests = []
            if any(prefix < tunnels for prefix in probe_prefixes): drop_tests.append(("before", max(p for p in probe_prefixes if p < tunnels)))
            if any(prefix > 0 for prefix in probe_prefixes): drop_tests.append(("containing", min(p for p in probe_prefixes if p > 0) - 1))
            for label, drop in drop_tests:
                relays[drop].block(); proc = restart_xray(proc, xray, cfg, relays)
                selected = (max(p for p in probe_prefixes if p < tunnels) if label == "before" else min(p for p in probe_prefixes if p > 0))
                i = probe_prefixes.index(selected); before = [len(r.logs) for r in relays]
                dns_queries_before = len(fixture.dns_queries)
                ans = None
                try: ans = send_dns(policy_ports[i], bytes([0x70, len(drop_tests)]), f"drop{label}{time.time_ns()}", timeout=2)
                except (socket.timeout, OSError): pass
                if label == "before":
                    assert ans is not None and ans[2] & 0x80 and len(fixture.dns_queries) > dns_queries_before, f"DNS-before-drop did not succeed (drop={drop})"
                else:
                    assert ans is None or not (ans[2] & 0x80), f"DNS-containing-drop unexpectedly succeeded (drop={drop})"
                    assert len(fixture.dns_queries) == dns_queries_before, f"DNS-containing-drop issued a new query (drop={drop})"
                hr2 = http_probe(url); assert hr2.returncode != 0, f"HTTP unexpectedly survived dropped relay {drop}"
            print(f"[{position}] blocks={blocks} tunnels={tunnels} dns-prefixes={prefixes}: HTTP=PASS DNS=PASS CONNECT-log=PASS drop-restart=PASS DNS-after-drop=PASS HTTP-after-drop=PASS")
            print(f"[{position}] actual dns-queries={len(fixture.dns_queries)} relay-connects={[sum(x[0] == 1 for x in r.logs) for r in relays]}")
            return True
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait()
        fixture.close(); [r.close() for r in relays]


def main():
    ap = argparse.ArgumentParser(description="Run real local Xray Mix DNS/HTTP integration scenarios.")
    ap.add_argument("--xray", default="/tmp/xray-mix-test/xray")
    ap.add_argument("--dart", default=os.environ.get("DART") or shutil.which("dart"))
    ap.add_argument("--dns-position", choices=("beginning", "middle", "end", "repeated", "all"), default="all")
    ap.add_argument("--blocks", type=int, default=50, help="total Mix blocks (maximum 50)")
    args = ap.parse_args()
    if os.geteuid() != 0: ap.error("binds fixture TCP/53; run with sudo python3")
    if not args.dart: ap.error("Dart SDK not found; supply --dart /tmp/flutter/bin/cache/dart-sdk/bin/dart")
    if not 2 <= args.blocks <= 50: ap.error("--blocks must be between 2 and 50")
    dart = Path(args.dart).resolve(); cached = dart.parent / "cache/dart-sdk/bin/dart"
    if cached.is_file(): dart = cached
    xray = Path(args.xray)
    if not xray.is_file() or not os.access(xray, os.X_OK): ap.error(f"Xray executable not found: {xray}")
    positions = ["beginning", "middle", "end", "repeated"] if args.dns_position == "all" else [args.dns_position]
    if "repeated" in positions and args.blocks < 6: ap.error("repeated requires at least 6 blocks for distinct beginning/middle/end boundaries")
    failures = 0
    for position in positions:
        try:
            run_case(position, args.blocks, xray, str(dart))
        except (AssertionError, OSError, subprocess.SubprocessError) as exc:
            failures += 1
            print(f"[{position}] FAIL actual assertion/error: {exc}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
