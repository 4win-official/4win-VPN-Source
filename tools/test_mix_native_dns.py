#!/usr/bin/env python3
"""Native MixRouting sidecar/resolver integration test.

This compiles a temporary Java bridge against MixRouting, starts the emitted
Xray sidecar plus one Xray resolver per direct_dns stage, and exercises only
loopback fixtures.  Run as root because the resolver fixtures listen on TCP/53
on distinct loopback addresses::

  sudo python3 tools/test_mix_native_dns.py --classpath "$(cat /tmp/mix-routing-classpath)" \
      --xray /tmp/xray-mix-test/xray
"""
import argparse, json, os, select, socket, struct, subprocess, tempfile, threading, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIMEOUT = 12


def recv_exact(s, n):
    out = b""
    while len(out) < n:
        b = s.recv(n - len(out))
        if not b: raise EOFError("short frame")
        out += b
    return out


def relay(a, b):
    try:
        a.settimeout(None); b.settimeout(None)
        while True:
            ready, _, _ = select.select((a, b), (), (), 10)
            if not ready: return
            for src in ready:
                data = src.recv(65536)
                if not data: return
                (b if src is a else a).sendall(data)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try: s.close()
            except OSError: pass


class Relay:
    def __init__(self):
        self.s = socket.socket(); self.s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.s.bind(("127.0.0.1", 0)); self.s.listen(32); self.port = self.s.getsockname()[1]
        self.stop = threading.Event(); self.logs = []; self.active = set(); self.lock = threading.Lock()
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while not self.stop.is_set():
            try: c, _ = self.s.accept()
            except OSError: break
            with self.lock: self.active.add(c)
            threading.Thread(target=self.client, args=(c,), daemon=True).start()

    def client(self, c):
        try:
            c.settimeout(TIMEOUT); _, n = recv_exact(c, 2); recv_exact(c, n); c.sendall(b"\x05\x00")
            h = recv_exact(c, 4); cmd, atyp = h[1], h[3]
            if atyp == 1: dst = socket.inet_ntoa(recv_exact(c, 4))
            elif atyp == 3:
                n = recv_exact(c, 1)[0]; dst = recv_exact(c, n).decode()
            elif atyp == 4: dst = socket.inet_ntop(socket.AF_INET6, recv_exact(c, 16))
            else: return
            port = struct.unpack("!H", recv_exact(c, 2))[0]; self.logs.append((cmd, dst, port))
            if cmd != 1: return
            if dst == "target.test": dst = "127.0.0.1"
            u = socket.create_connection((dst, port), TIMEOUT); c.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
            relay(c, u)
        except (OSError, EOFError, ValueError):
            pass
        finally:
            with self.lock: self.active.discard(c)
            try: c.close()
            except OSError: pass

    def close(self):
        self.stop.set()
        with self.lock: active = list(self.active)
        for c in active:
            try: c.shutdown(socket.SHUT_RDWR)
            except OSError: pass
        try: self.s.close()
        except OSError: pass


class TcpDns:
    def __init__(self, address):
        self.s = socket.socket(); self.s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.s.bind((address, 53)); self.s.listen(32); self.s.settimeout(.3); self.address = address
        self.stop = threading.Event(); self.queries = []; threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while not self.stop.is_set():
            try: c, _ = self.s.accept()
            except socket.timeout: continue
            except OSError: break
            threading.Thread(target=self.client, args=(c,), daemon=True).start()

    def client(self, c):
        try:
            c.settimeout(TIMEOUT)
            while not self.stop.is_set():
                h = c.recv(2)
                if not h: return
                q = recv_exact(c, struct.unpack("!H", h)[0]); self.queries.append(q)
                c.sendall(struct.pack("!H", len(dns_reply(q))) + dns_reply(q))
        except (OSError, EOFError, socket.timeout): pass
        finally: c.close()

    def close(self):
        self.stop.set()
        try: self.s.close()
        except OSError: pass


def dns_reply(q):
    if len(q) < 12: raise ValueError("bad DNS query")
    end = 12
    while end < len(q) and q[end]: end += q[end] + 1
    question = q[12:end + 5]
    return q[:2] + b"\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00" + question + b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x1e\x00\x04\x7f\x00\x00\x01"


def dns_query(ident, label):
    name = bytes([len(label)]) + label.encode() + b"\x04test\x00"
    return ident + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00" + name + struct.pack("!HH", 1, 1)


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


def socks_dns(port, ident):
    s = socket.create_connection(("127.0.0.1", port), TIMEOUT)
    try:
        s.sendall(b"\x05\x01\x00"); assert recv_exact(s, 2) == b"\x05\x00"
        s.sendall(b"\x05\x01\x00\x01\xcb\x00\x71\x35\x00\x35")
        assert recv_exact(s, 10)[1] == 0
        q = dns_query(ident, "q" + ident.hex()); s.sendall(struct.pack("!H", len(q)) + q)
        answer = recv_exact(s, struct.unpack("!H", recv_exact(s, 2))[0])
        assert answer[:2] == ident and answer[2] & 0x80 and b"\x7f\x00\x00\x01" in answer
    finally: s.close()


def compile_exporter(cp, td):
    src = Path(td) / "ExportMixRouting.java"
    src.write_text('''import java.nio.file.*; import java.util.*; import org.json.*; import com.forwin.vpn.mix.MixRouting;
public class ExportMixRouting { static Map<Integer,Integer> m(JSONObject o){Map<Integer,Integer> r=new HashMap<>();if(o!=null)for(String k:o.keySet())r.put(Integer.parseInt(k),o.getInt(k));return r;}
public static void main(String[] a)throws Exception{JSONObject s=new JSONObject(Files.readString(Path.of(a[0])));JSONArray h=s.getJSONObject("plan").getJSONArray("hops");List<Integer> p=new ArrayList<>();for(Object x:s.getJSONArray("ports"))p.add((Integer)x);Map<Integer,Integer>d=m(s.optJSONObject("dnsPorts")),w=m(s.optJSONObject("workers")),r=m(s.optJSONObject("rawPorts"));JSONObject out=new JSONObject().put("sidecar",MixRouting.INSTANCE.sidecar(s.getJSONObject("plan"),p,w,d,r));JSONObject rs=new JSONObject();for(Integer i:d.keySet())rs.put(i.toString(),MixRouting.INSTANCE.resolver(h.getJSONObject(i).getString("address"),d.get(i),i==0?null:r.get(i-1)));System.out.print(out.put("resolvers",rs));}}
''')
    subprocess.run(["javac", "-cp", cp, "-d", str(td), str(src)], check=True)
    return f"{td}:{cp}"


def export(java_cp, td, hops, ports, dns_ports, raw_ports):
    spec = {"plan": {"hops": hops}, "ports": ports, "workers": {}, "dnsPorts": dns_ports, "rawPorts": raw_ports}
    p = Path(td) / "spec.json"; p.write_text(json.dumps(spec))
    return json.loads(subprocess.check_output(["java", "-cp", java_cp, "ExportMixRouting", str(p)], text=True))


def run_case(name, protocols, xray, java_cp, td):
    relays = [Relay() for p in protocols if p == "proxy"]
    dns = {}; hops = []; relay_i = 0
    case_subnet = {"dns-three-consecutive": 20, "dns-before": 24, "dns-middle": 28, "dns-after": 32}[name]
    for i, p in enumerate(protocols):
        if p == "dns":
            address = f"127.0.{case_subnet + len(dns)}.1"; dns[i] = TcpDns(address)
            hops.append({"protocol": "direct_dns", "address": address})
        else:
            r = relays[relay_i]; relay_i += 1
            hops.append({"protocol": "proxy", "outbound": {"protocol": "socks", "settings": {"servers": [{"address": "127.0.0.1", "port": r.port}]}}})
    prefix = [free_port() for _ in protocols]; dns_ports = {i: free_port() for i in dns}; raw = {i - 1: free_port() for i in dns if i > 0}
    bundle = export(java_cp, td, hops, prefix, dns_ports, raw); procs = []; logs = []
    target = socket.socket(); target.bind(("127.0.0.1", 0)); target.listen(8); target_port = target.getsockname()[1]; stop = threading.Event()
    def http():
        while not stop.is_set():
            try: c, _ = target.accept()
            except OSError: break
            threading.Thread(target=lambda: (c.recv(4096), c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\nMIX-OK-123"), c.close()), daemon=True).start()
    threading.Thread(target=http, daemon=True).start()
    try:
        configs = [("sidecar", bundle["sidecar"])] + [(str(i), bundle["resolvers"][str(i)]) for i in dns]
        for key, config in configs:
            path = Path(td) / f"{name}-{key}.json"; path.write_text(json.dumps(config)); log = open(Path(td) / f"{name}-{key}.log", "w"); logs.append(log)
            p = subprocess.Popen([str(xray), "-c", str(path)], stdout=log, stderr=log); procs.append(p)
        deadline = time.time() + 3
        while time.time() < deadline:
            if any(p.poll() is not None for p in procs): break
            try:
                if all(socket.create_connection(("127.0.0.1", p), .1) for p in prefix + list(dns_ports.values())): break
            except OSError:
                time.sleep(.1)
        if any(p.poll() is not None for p in procs): raise RuntimeError(f"{name}: Xray exited early")
        http_result = subprocess.run(["curl", "-sS", "--max-time", str(TIMEOUT), "--socks5-hostname", f"127.0.0.1:{prefix[-1]}", f"http://127.0.0.1:{target_port}/"], text=True, capture_output=True)
        if relays and (http_result.returncode or http_result.stdout != "MIX-OK-123"): raise AssertionError(f"{name}: HTTP failed: {http_result.stderr}")
        for j, stage in enumerate(dns):
            before = [len(r.logs) for r in relays]; before_dns = {i: len(v.queries) for i, v in dns.items()}
            socks_dns(prefix[stage], bytes([0x70, j + 1])); changes = [len(r.logs) - n for r, n in zip(relays, before)]
            expected = sum(p == "proxy" for p in protocols[:stage])
            if changes[:expected] == [] and expected: raise AssertionError(f"{name}: DNS stage {stage} did not traverse prefix")
            if any(changes[k] == 0 for k in range(expected)) or any(changes[k] for k in range(expected, len(changes))): raise AssertionError(f"{name}: DNS traversal {changes}, expected first {expected}")
            if any(len(v.queries) - before_dns[i] != (1 if i == stage else 0) for i, v in dns.items()): raise AssertionError(f"{name}: resolver selection/count mismatch")
        print(f"[{name}] PASS HTTP={'PASS' if not relays or http_result.stdout == 'MIX-OK-123' else 'FAIL'} DNS queries=" + str({i: len(v.queries) for i, v in dns.items()}) + " relay CONNECTs=" + str([len(r.logs) for r in relays]), flush=True)
    finally:
        for p in reversed(procs):
            if p.poll() is None:
                p.terminate()
                try: p.wait(4)
                except subprocess.TimeoutExpired: p.kill(); p.wait()
        for f in logs: f.close()
        stop.set(); target.close()
        for v in dns.values(): v.close()
        for r in relays: r.close()


def check_limits(java_cp, td):
    hops = [{"protocol": "direct_dns", "address": "127.0.99.1"} for _ in range(50)]
    p = [free_port() for _ in hops]; d = {i: free_port() for i in range(50)}; raw = {i: free_port() for i in range(49)}
    export(java_cp, td, hops, p, d, raw)
    try:
        export(java_cp, td, hops + [{"protocol": "direct_dns", "address": "127.0.99.1"}], p + [free_port()], {**d, 50: free_port()}, {**raw, 49: free_port()})
    except subprocess.CalledProcessError:
        print("[limits] PASS 50 accepted, 51 rejected", flush=True); return
    raise AssertionError("51 Mix blocks unexpectedly accepted")


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--classpath", required=True); ap.add_argument("--xray", required=True); args = ap.parse_args()
    if os.geteuid() != 0: ap.error("run as root: DNS fixtures bind TCP/53")
    xray = Path(args.xray)
    if not xray.is_file() or not os.access(xray, os.X_OK): ap.error(f"Xray executable not found: {xray}")
    failures = 0
    with tempfile.TemporaryDirectory(prefix="mix-native-dns-") as td:
        try:
            java_cp = compile_exporter(args.classpath, td)
            run_case("dns-three-consecutive", ["dns", "dns", "dns"], xray, java_cp, td)
            run_case("dns-before", ["dns", "proxy", "proxy"], xray, java_cp, td)
            run_case("dns-middle", ["proxy", "dns", "proxy"], xray, java_cp, td)
            run_case("dns-after", ["proxy", "proxy", "dns"], xray, java_cp, td)
            check_limits(java_cp, td)
        except (AssertionError, OSError, subprocess.SubprocessError, RuntimeError) as e:
            failures += 1; print("FAIL:", e)
    return failures

if __name__ == "__main__": raise SystemExit(main())
