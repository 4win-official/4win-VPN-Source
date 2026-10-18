#!/usr/bin/env python3
"""End-to-end test for two Kotlin MixUdpRelay wrappers over real Xray HTTP hops."""
from __future__ import annotations
import argparse, json, os, pathlib, select, socket, ssl, struct, subprocess, sys, tempfile, time, threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"

def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0)); return s.getsockname()[1]

def exact(s, n):
    b = bytearray()
    while len(b) < n:
        x = s.recv(n-len(b))
        if not x: raise RuntimeError("short socket read")
        b += x
    return bytes(b)

def socks_reply(s):
    h = exact(s, 4)
    if h[1] != 0: raise RuntimeError(f"SOCKS failure {h[1]}")
    if h[3] == 1: n = 4
    elif h[3] == 4: n = 16
    elif h[3] == 3: n = exact(s, 1)[0]
    else: raise RuntimeError("bad SOCKS ATYP")
    exact(s, n + 2)

def socks_connect(port, host, dst):
    s = socket.create_connection(("127.0.0.1", port), 5); s.settimeout(5)
    s.sendall(b"\x05\x01\x00"); assert exact(s, 2) == b"\x05\x00"
    name = host.encode(); s.sendall(b"\x05\x01\x00\x03" + bytes([len(name)]) + name + struct.pack("!H", dst))
    socks_reply(s); return s

def udp_associate(port):
    c = socket.create_connection(("127.0.0.1", port), 5); c.settimeout(5)
    c.sendall(b"\x05\x01\x00"); assert exact(c, 2) == b"\x05\x00"
    c.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
    h = exact(c, 4)
    if h[1] != 0: raise RuntimeError(f"UDP ASSOCIATE failure {h[1]}")
    if h[3] == 1: host = socket.inet_ntoa(exact(c, 4))
    elif h[3] == 4: host = "127.0.0.1"; exact(c, 16)
    elif h[3] == 3: host = "127.0.0.1"; exact(c, exact(c, 1)[0])
    else: raise RuntimeError("bad UDP bind ATYP")
    p = struct.unpack("!H", exact(c, 2))[0]
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.settimeout(4)
    return c, u, (host, p)

def frame(addr, payload):
    return b"\0\0\0\1" + socket.inet_aton(addr[0]) + struct.pack("!H", addr[1]) + payload

def wait_port(port, proc=None, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if proc and proc.poll() is not None:
            raise RuntimeError(f"process exited {proc.returncode}: {proc.stderr.read()[-4000:] if proc.stderr else ''}")
        try:
            with socket.create_connection(("127.0.0.1", port), .2): return
        except OSError: time.sleep(.05)
    raise TimeoutError(f"port {port} did not listen")

def wait_ready(proc, timeout=15):
    end = time.monotonic() + timeout; buf = ""
    while time.monotonic() < end:
        if proc.poll() is not None:
            out = (proc.stdout.read() if proc.stdout else "") + (proc.stderr.read() if proc.stderr else "")
            raise RuntimeError(f"bridge exited {proc.returncode}: {out[-4000:]}")
        if proc.stdout:
            r, _, _ = select.select([proc.stdout], [], [], .2)
            if r:
                line = proc.stdout.readline(); buf += line
                if "READY" in line: return
    raise TimeoutError(f"bridge READY timeout; output={buf!r}")

def terminate(p, timeout=5):
    if not p or p.poll() is not None: return
    p.terminate()
    try: p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait(timeout=timeout)


def fake_socks_underlay(port, relay_port):
    """Tiny real SOCKS5 underlay used only by the isolated half-close check."""
    server = socket.socket(); server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port)); server.listen(16); server.settimeout(.2)
    live = set(); stop = threading.Event()
    def copy(src, dst):
        try:
            while True:
                data = src.recv(65536)
                if not data: break
                dst.sendall(data)
        except (OSError, ConnectionError): pass
        finally:
            try: dst.shutdown(socket.SHUT_WR)
            except OSError: pass
    def session(c):
        live.add(c); remote = None
        try:
            c.settimeout(5); assert exact(c, 1) == b"\x05"
            n = exact(c, 1)[0]; methods = exact(c, n)
            if 0 not in methods: c.sendall(b"\x05\xff"); return
            c.sendall(b"\x05\x00"); assert exact(c, 3)[:2] == b"\x05\x01"
            atyp = exact(c, 1)[0]
            if atyp == 1: host = socket.inet_ntoa(exact(c, 4))
            elif atyp == 3:
                host = exact(c, exact(c, 1)[0]).decode("idna")
            elif atyp == 4: host = socket.inet_ntop(socket.AF_INET6, exact(c, 16))
            else: return
            dst = struct.unpack("!H", exact(c, 2))[0]
            if host in ("127.0.0.1", "localhost", "::1"): host = "127.0.0.1"
            remote = socket.create_connection((host, dst), 5)
            c.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01" + struct.pack("!H", remote.getsockname()[1]))
            c.settimeout(None); remote.settimeout(None)
            a=threading.Thread(target=copy,args=(c,remote),daemon=True); b=threading.Thread(target=copy,args=(remote,c),daemon=True)
            a.start(); b.start(); a.join(); b.join()
        except (Exception,):
            try: c.sendall(b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00")
            except OSError: pass
        finally:
            for x in (remote,c):
                if x:
                    try: x.close()
                    except OSError: pass
            live.discard(c)
    def accept_loop():
        while not stop.is_set():
            try: c,_=server.accept()
            except socket.timeout: continue
            except OSError: break
            threading.Thread(target=session,args=(c,),daemon=True).start()
    t=threading.Thread(target=accept_loop,daemon=True); t.start()
    def close():
        stop.set(); server.close()
        for c in list(live):
            try: c.close()
            except OSError: pass
        t.join(timeout=1)
    return close

def java_harness(cp, out):
    src = out / "BridgeHarness.java"
    src.write_text(r'''package com.forwin.vpn.mix;
import java.io.*; import java.nio.file.*; import java.security.*; import java.security.cert.*; import java.util.*; import javax.net.ssl.*; import org.json.*;
public final class BridgeHarness {
 static SSLContext context(String cert) throws Exception { CertificateFactory f=CertificateFactory.getInstance("X.509"); X509Certificate c=(X509Certificate)f.generateCertificate(new FileInputStream(cert)); KeyStore k=KeyStore.getInstance(KeyStore.getDefaultType()); k.load(null,null); k.setCertificateEntry("relay",c); TrustManagerFactory t=TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()); t.init(k); SSLContext x=SSLContext.getInstance("TLS"); x.init(null,t.getTrustManagers(),new SecureRandom()); return x; }
 public static void main(String[] a) throws Exception {
  int p0=Integer.parseInt(a[0]),p1=Integer.parseInt(a[1]),u0=Integer.parseInt(a[2]),u1=Integer.parseInt(a[3]),r0=Integer.parseInt(a[4]),r1=Integer.parseInt(a[5]),relay=Integer.parseInt(a[6]),http=Integer.parseInt(a[7]); String token=a[8],name=a[9],cert=a[10],cfg=a[11];
  SSLContext sc=context(cert); MixUdpRelay.Config mc=new MixUdpRelay.Config("127.0.0.1",relay,token,name);
  if(a.length>12 && a[12].equals("raw-single")) { MixUdpRelay one=new MixUdpRelay(mc,r0,u0,sc); try { one.start(); System.out.println("READY"); System.out.flush(); while(System.in.read()!=-1){} } finally { one.close(); } return; }
  JSONObject out=new JSONObject().put("protocol","http").put("settings",new JSONObject().put("servers",new JSONArray().put(new JSONObject().put("address","127.0.0.1").put("port",http))));
  JSONObject plan=new JSONObject().put("hops",new JSONArray().put(new JSONObject().put("protocol","xray").put("outbound",out)).put(new JSONObject().put("protocol","xray").put("outbound",out)));
  JSONObject side=MixRouting.INSTANCE.sidecar(plan,Arrays.asList(p0,p1),Collections.emptyMap(),Collections.emptyMap(),Collections.emptyMap(),new HashMap<Integer,Integer>(){{put(0,r0);put(1,r1);}},new HashMap<Integer,Integer>(){{put(0,u0);put(1,u1);}});
  Files.writeString(Path.of(cfg),side.toString()); if(a.length>12 && a[12].equals("config-only")) return;
  MixUdpRelay b0=new MixUdpRelay(mc,r0,u0,sc); MixUdpRelay b1=null;
  try { b0.start(); b1=new MixUdpRelay(new MixUdpRelay.Config("127.0.0.1",relay,token,name),r1,u1,sc); b1.start(); System.out.println("READY"); System.out.flush(); while(System.in.read()!=-1){} }
  finally { if(b1!=null)b1.close(); b0.close(); }
 }
}''')
    q = subprocess.run(["javac","-cp",cp,"-d",str(out),str(src)],capture_output=True,text=True)
    if q.returncode: raise RuntimeError("javac failed: "+q.stderr)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--classpath",default="/tmp/mix-routing-classpath"); ap.add_argument("--xray",default="/tmp/xray-mix-test/xray"); ap.add_argument("--timeout",type=float,default=50); ap.add_argument("--keep-temp",action="store_true"); a=ap.parse_args()
    cp=pathlib.Path(a.classpath).read_text().strip(); xray=pathlib.Path(a.xray)
    if not xray.is_file() or not os.access(xray,os.X_OK): raise SystemExit(f"xray executable not found: {xray}")
    token="bridge-test-token-0123456789abcdef"; td=pathlib.Path(tempfile.mkdtemp(prefix="mix-udp-bridge-")); d=td
    cert,key=d/"cert.pem",d/"key.pem"; san=d/"san.cnf"; san.write_text("[req]\ndistinguished_name=dn\nreq_extensions=reqext\n[dn]\n[reqext]\nsubjectAltName=DNS:localhost\n")
    subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-days","1","-subj","/CN=localhost","-config",str(san),"-extensions","reqext","-keyout",str(key),"-out",str(cert)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    http, relay, p0,p1,u0,u1,r0,r1=[free_port() for _ in range(8)]; http_log=d/"http-access.log"; side_log=d/"sidecar.log"; side_cfg=d/"sidecar.json"; hcp=cp+os.pathsep+str(d)
    java_harness(hcp,d)
    proxy_cfg={"log":{"access":str(http_log),"loglevel":"info"},"inbounds":[{"listen":"127.0.0.1","port":http,"protocol":"http","settings":{}}],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
    proxy_path=d/"http.json"; proxy_path.write_text(json.dumps(proxy_cfg))
    procs=[]; relayp=xproc=bridge=None
    try:
        env=os.environ.copy(); env["MIX_RELAY_TOKEN"]=token
        relayp=subprocess.Popen([sys.executable,str(TOOLS/"mix_udp_relay.py"),"--host","127.0.0.1","--port",str(relay),"--cert",str(cert),"--key",str(key),"--allow-private"],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True); procs.append(relayp); wait_port(relay,relayp)
        cfg_only=subprocess.run(["java","-cp",hcp,"com.forwin.vpn.mix.BridgeHarness",str(p0),str(p1),str(u0),str(u1),str(r0),str(r1),str(relay),str(http),token,"localhost",str(cert),str(side_cfg),"config-only"],capture_output=True,text=True,timeout=10); cfg_only.check_returncode()
        side=json.loads(side_cfg.read_text()); side["log"]={"access":str(side_log),"loglevel":"info"}; side_cfg.write_text(json.dumps(side))
        # HTTP proxy is a separate real Xray process; sidecar is another real Xray process.
        proxy=subprocess.Popen([str(xray),"-c",str(proxy_path)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True); procs.append(proxy); wait_port(http,proxy)
        xproc=subprocess.Popen([str(xray),"-c",str(side_cfg)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True); procs.append(xproc); wait_port(u0,xproc); wait_port(u1,xproc); wait_port(p0,xproc); wait_port(p1,xproc)
        bridge=subprocess.Popen(["java","-cp",hcp,"com.forwin.vpn.mix.BridgeHarness",str(p0),str(p1),str(u0),str(u1),str(r0),str(r1),str(relay),str(http),token,"localhost",str(cert),str(side_cfg)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True); procs.append(bridge); wait_ready(bridge)
        # Two genuinely independent peers and two associations held concurrently.
        peers=[]
        for label in (b"one",b"two"):
            e=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); e.bind(("127.0.0.1",0)); e.settimeout(.2); peers.append(e)
        stop=threading.Event()
        def echo(e):
            while not stop.is_set():
                try: data,src=e.recvfrom(65535); e.sendto(b"echo:"+data,src)
                except (socket.timeout,OSError): pass
        threads=[threading.Thread(target=echo,args=(e,),daemon=True) for e in peers]
        for t in threads:t.start()
        assocs=[udp_associate(p1) for _ in peers]
        for (c,u,b),e,payload in zip(assocs,peers,(b"one",b"two")):
            u.sendto(frame(("127.0.0.1",e.getsockname()[1]),payload),b)
        for (c,u,b),payload in zip(assocs,(b"one",b"two")):
            got,_=u.recvfrom(65535); assert got[10:]==b"echo:"+payload,got
        # Ordinary TCP must traverse both HTTP-wrapped stages as well.
        ts=socket.socket(); ts.bind(("127.0.0.1",0)); ts.listen(1); tp=ts.getsockname()[1]
        def tcp_echo():
            c,_=ts.accept(); c.sendall(c.recv(64)); c.close()
        threading.Thread(target=tcp_echo,daemon=True).start(); c=socks_connect(p1,"127.0.0.1",tp); c.sendall(b"tcp"); assert exact(c,3)==b"tcp"; c.close(); ts.close()
        access=http_log.read_text(errors="replace"); assert str(relay) in access and str(tp) in access, "HTTP access log lacks relay/TCP destinations"
        # Xray's HTTP prefix closes TCP on EOF, so test half-close independently
        # through a real MixUdpRelay and a tiny real SOCKS5 underlay instead.
        iso_r, iso_u = free_port(), free_port()
        close_underlay = fake_socks_underlay(iso_u, relay)
        half=socket.socket(); half.bind(("127.0.0.1",0)); half.listen(1)
        def half_echo():
            conn,_=half.accept()
            with conn:
                request=b""
                while True:
                    chunk=conn.recv(64)
                    if not chunk: break
                    request+=chunk
                time.sleep(.1); conn.sendall(b"reply:"+request)
        ht=threading.Thread(target=half_echo,daemon=True); ht.start()
        isolated=subprocess.Popen(["java","-cp",hcp,"com.forwin.vpn.mix.BridgeHarness",str(free_port()),str(free_port()),str(iso_u),str(free_port()),str(iso_r),str(free_port()),str(relay),str(http),token,"localhost",str(cert),str(d/"raw.json"),"raw-single"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True); procs.append(isolated); wait_ready(isolated)
        c=socks_connect(iso_r,"127.0.0.1",half.getsockname()[1]); c.sendall(b"half"); c.shutdown(socket.SHUT_WR); assert exact(c,10)==b"reply:half"
        c.close(); half.close(); ht.join(timeout=2); terminate(isolated); close_underlay(); close_underlay=None
        # Bad credentials/name fail during bridge.start, before READY.
        for badtoken,badname in (("wrong-token-0123456789012345678901","localhost"),(token,"not-localhost")):
            q=subprocess.Popen(["java","-cp",hcp,"com.forwin.vpn.mix.BridgeHarness",str(p0),str(p1),str(u0),str(u1),str(free_port()),str(free_port()),str(relay),str(http),badtoken,badname,str(cert),str(d/"bad.json")],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                q.wait(timeout=8); assert q.returncode!=0 and "READY" not in q.stdout.read()
            finally: terminate(q)
        # Cut only the HTTP proxy. Existing associations must fail closed; direct echo remains healthy.
        terminate(proxy); time.sleep(.5)
        for c,u,b in assocs:
            u.sendto(frame(("127.0.0.1",peers[0].getsockname()[1]),b"after-cut"),b); u.settimeout(2)
            try: u.recvfrom(65535); raise AssertionError("UDP survived HTTP proxy cut")
            except socket.timeout: pass
        direct=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); direct.settimeout(2); direct.sendto(b"direct",peers[0].getsockname()); got,_=direct.recvfrom(64); assert got==b"echo:direct"; direct.close()
        for c,u,b in assocs: u.close(); c.close()
        stop.set(); [e.close() for e in peers]
        print("PASS: two real Xray HTTP stages, Kotlin bridges, concurrent UDP peers, TCP, auth/TLS fail-closed, and HTTP cut",flush=True)
    finally:
        if close_underlay: close_underlay()
        for p in reversed(procs): terminate(p)
        if a.keep_temp: print(f"kept temp: {d}",file=sys.stderr)
        else: import shutil; shutil.rmtree(d,ignore_errors=True)

if __name__=="__main__":
    try: main()
    except Exception as e: print(f"FAIL: {e}",file=sys.stderr); raise
