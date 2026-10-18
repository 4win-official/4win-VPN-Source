#!/usr/bin/env python3
"""Local MixConfigBuilder integration test.

Uses three local SOCKS5 relays, a local HTTP target, and a local DNS server.
The Xray binary is downloaded from the official XTLS/Xray-core release only
when --xray is absent. No credentials or external services are used.
"""
import argparse, json, os, shutil, socket, struct, subprocess, tempfile, threading, time, urllib.request, zipfile
from pathlib import Path

RELEASE = "v26.3.27"
XRAY_URL = f"https://github.com/XTLS/Xray-core/releases/download/{RELEASE}/Xray-linux-64.zip"
ROOT = Path(__file__).resolve().parents[1]

class Server:
    def __init__(self, port=0):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM); self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); self.sock.bind(("127.0.0.1", port)); self.sock.listen(64); self.port = self.sock.getsockname()[1]; self.stop = threading.Event(); self.blocked=False; self.logs=[]
        self.t = threading.Thread(target=self.accept, daemon=True); self.t.start()
    def accept(self):
        while not self.stop.is_set():
            try: c,a=self.sock.accept()
            except OSError: break
            threading.Thread(target=self.client,args=(c,),daemon=True).start()
    def client(self,c):
        try:
            if self.blocked: c.close(); return
            c.settimeout(10)
            ver, n = recv_exact(c, 2); c.recv(n); c.sendall(b"\x05\x00")
            h=recv_exact(c,4); cmd=h[1]; atyp=h[3]
            if atyp==1: dst=socket.inet_ntoa(recv_exact(c,4))
            elif atyp==3: dst=recv_exact(c,recv_exact(c,1)[0]).decode()
            elif atyp==4: dst=socket.inet_ntop(socket.AF_INET6,recv_exact(c,16))
            else: raise ValueError('bad SOCKS address type')
            port=struct.unpack("!H",recv_exact(c,2))[0]; self.logs.append((cmd,dst,port))
            if cmd==1:
                if dst == 'target.test': dst = '127.0.0.1'  # synthetic exit-side resolution; no external DNS
                u=socket.create_connection((dst,port),10); c.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00"); relay(c,u)
            elif cmd==3:
                us=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); us.bind(("127.0.0.1",0)); us.settimeout(10); up=us.getsockname()[1]; c.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01"+struct.pack("!H",up)); a=c.getpeername();
                while True:
                    p,addr=us.recvfrom(65535); x=p[3]; i=4
                    if x==1: host=socket.inet_ntoa(p[i:i+4]); i+=4
                    elif x==3: n=p[i]; i+=1; host=p[i:i+n].decode(); i+=n
                    else: host=socket.inet_ntop(socket.AF_INET6,p[i:i+16]); i+=16
                    port=struct.unpack("!H",p[i:i+2])[0]; self.logs.append((3,host,port)); us.sendto(p, (host,port));
                    try: q,_=us.recvfrom(65535); us.sendto(q,a)
                    except socket.timeout: pass
            else: c.close()
        except Exception: c.close()
    def close(self): self.blocked=True; self.stop.set(); self.sock.close()

def recv_exact(sock, n):
    data=b''
    while len(data)<n:
        chunk=sock.recv(n-len(data))
        if not chunk: raise EOFError('short SOCKS frame')
        data += chunk
    return data

def relay(a,b):
    a.settimeout(None); b.settimeout(None)
    try:
        while True:
            r,_,_=select.select([a,b],[],[],10)
            if not r: break
            for x in r:
                d=x.recv(65536)
                if not d: return
                (b if x is a else a).sendall(d)
    except Exception: pass
    finally: a.close(); b.close()

# local HTTP and TCP DNS services
def http_server(sock, stop, count):
    while not stop.is_set():
        try: c,_=sock.accept()
        except OSError: break
        count.append(1)
        threading.Thread(target=lambda: (c.recv(4096), c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\nConnection: close\r\n\r\nMIX-OK-123"), c.close()),daemon=True).start()
def dns_reply(q):
    if len(q)<12: return None
    ident=q[:2]; flags=b"\x81\x80"; counts=b"\x00\x01\x00\x01\x00\x00\x00\x00"; end=12
    while end<len(q) and q[end]!=0: end+=q[end]+1
    if end+5>len(q): return None
    question=q[12:end+5]
    return ident+flags+counts+question+b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x1e\x00\x04\x7f\x00\x00\x01"

def dns_server(sock, stop, count, connections):
    while not stop.is_set():
        try: c,_=sock.accept()
        except socket.timeout: continue
        connections.append(1)
        threading.Thread(target=dns_client,args=(c,stop,count),daemon=True).start()

def dns_client(c, stop, count):
    try:
        c.settimeout(5)
        while not stop.is_set():
            hdr=c.recv(2)
            if not hdr: return
            n=struct.unpack('!H',hdr)[0]; q=recv_exact(c,n); count.append(q)
            answer=dns_reply(q)
            if answer: c.sendall(struct.pack('!H',len(answer))+answer)
    except (OSError, EOFError, socket.timeout): pass
    finally: c.close()

def make_config(ports, dns, out, dart):
    helper=ROOT/"tools/.mix_builder_runner.dart"
    helper.write_text(f'''import 'dart:io';\nimport 'package:vpn_swift/models/proxy_server.dart';\nimport 'package:vpn_swift/models/dns_server.dart';\nimport 'package:vpn_swift/models/mix_strategy.dart';\nimport 'package:vpn_swift/services/mix_config_builder.dart';\nvoid main() {{ final ps={ports!r}.map((p)=>ProxyServer(id:'p$p',remark:'local',link:'socks5://127.0.0.1:$p',protocol:'socks5',address:'127.0.0.1',port:p)).toList(); final s=MixStrategy(id:'t',name:'local',hops:ps.map((p)=>MixHop(protocol:'proxy',serverId:p.id)).toList()..add(const MixHop(protocol:'direct_dns',serverId:'{dns}'))); File('{out}').writeAsStringSync(MixConfigBuilder.build(strategy:s,xrayServers:const [],proxyServers:ps,dnsServers:[DnsServer(name:'local',primaryDns:'{dns}',description:'local',country:'local')])); }}\n''')
    try: subprocess.run([dart,"run","tools/.mix_builder_runner.dart"],cwd=ROOT,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    finally: helper.unlink(missing_ok=True)

def dns_query(ident):
    # A IN query for chain.test, with a deterministic transaction ID.
    return ident+b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00"+b"\x05chain\x04test\x00\x00\x01\x00\x01"

def send_dns(port, ident, timeout=4):
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(timeout)
    try:
        s.sendto(dns_query(ident),('127.0.0.1',port)); return s.recvfrom(2048)[0]
    finally: s.close()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--xray', default='/tmp/xray-mix-test/xray')
    ap.add_argument('--dart', default=os.environ.get('DART') or shutil.which('dart'))
    args=ap.parse_args()
    if not args.dart:
        ap.error('Dart SDK not found: put dart on PATH or supply --dart /path/to/dart')
    dart=Path(args.dart).resolve()
    cached=dart.parent/'cache/dart-sdk/bin/dart'
    if cached.is_file(): dart=cached  # Avoid Flutter wrapper cache writes when run with sudo.
    dart=str(dart)

    xray=Path(args.xray)
    if not xray.exists():
        xray.parent.mkdir(parents=True,exist_ok=True); z=xray.parent/'x.zip'; urllib.request.urlretrieve(XRAY_URL,z); zipfile.ZipFile(z).extract('xray',xray.parent); xray.chmod(0o755)
    relays=[Server() for _ in range(3)]; target=socket.socket(); target.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); target.bind(('127.0.0.1',0)); target.listen(10); target_port=target.getsockname()[1]; http_count=[]; ht=threading.Thread(target=http_server,args=(target,threading.Event(),http_count),daemon=True); ht.start()
    dns_stop=threading.Event(); dns=socket.socket(socket.AF_INET,socket.SOCK_STREAM); dns.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); dns.bind(('127.0.0.1',53)); dns.listen(16); dns.settimeout(.5); dns_count=[]; dns_connections=[]; dt=threading.Thread(target=dns_server,args=(dns,dns_stop,dns_count,dns_connections),daemon=True); dt.start()
    # Reserve an ephemeral UDP port for the synthetic app-facing Xray inbound.
    probe=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); probe.bind(('127.0.0.1',0)); inbound_port=probe.getsockname()[1]; probe.close()
    with tempfile.TemporaryDirectory(prefix='mix-chain-') as td:
        cfg=Path(td)/'config.json'; make_config([r.port for r in relays], '127.0.0.1', cfg, dart)
        c=json.loads(cfg.read_text()); c.setdefault('inbounds',[]).append({'tag':'dns-in','listen':'127.0.0.1','port':inbound_port,'protocol':'dokodemo-door','settings':{'address':'203.0.113.53','port':53,'network':'udp'}}); cfg.write_text(json.dumps(c)); tags=[o['tag'] for o in c['outbounds']]; assert tags==['proxy','mix-hop-0','mix-hop-1','mix-dns'],tags
        assert c['outbounds'][0]['streamSettings']['sockopt']['dialerProxy']=='mix-hop-1'; assert c['outbounds'][2]['streamSettings']['sockopt']['dialerProxy']=='mix-hop-0'; assert 'direct' not in tags and 'fallbacks' not in json.dumps(c)
        p=Path(td)/'xray.log'; proc=subprocess.Popen([str(xray),'-c',str(cfg)],stdout=subprocess.DEVNULL,stderr=open(p,'w')); time.sleep(1)
        try:
            u=f'http://target.test:{target_port}/'; r=subprocess.run(['curl','--silent','--show-error','--max-time','8','--socks5-hostname','127.0.0.1:10808',u],text=True,capture_output=True)
            ok=r.returncode==0 and r.stdout=='MIX-OK-123'
            dns_ident=b'\x42\x17'; dns_ok=False; dns_error=''; relay_log_before=[len(x.logs) for x in relays]
            try:
                ans=send_dns(inbound_port,dns_ident); dns_ok=(ans[:2]==dns_ident and ans[2]&0x80 and not ans[3]&0x0f and b'\x7f\x00\x00\x01' in ans)
                if not dns_ok: dns_error=f'bad reply {ans.hex()}'
            except Exception as e: dns_error=repr(e)
            relay_dns_ok=all(len(relay.logs)>old for relay,old in zip(relays,relay_log_before)) and any(cmd==1 and dst=='127.0.0.1' and port==53 for cmd,dst,port in relays[-1].logs[relay_log_before[-1]:])
            print(f'Xray {subprocess.check_output([str(xray),"version"],text=True).splitlines()[0]}'); print('HTTP chain:', 'PASS' if ok else f'FAIL ({r.stderr.strip()})'); print('DNS UDP->TCP chain:', 'PASS' if dns_ok and relay_dns_ok and len(dns_count)==1 and len(dns_connections)==1 else f'FAIL ({dns_error or "missing hop/fixture evidence"})'); print('relay CONNECT logs:', [x.logs for x in relays]); print('HTTP target accepts:',len(http_count)); print('TCP DNS connections/queries:',len(dns_connections),len(dns_count)); print('Xray log tail:', p.read_text()[-800:])
            # A dropped intermediate must fail; no direct fallback is allowed.
            proc.terminate(); proc.wait(timeout=5); relays[1].close(); before_dns=len(dns_count); proc=subprocess.Popen([str(xray),'-c',str(cfg)],stdout=subprocess.DEVNULL,stderr=open(p,'a')); time.sleep(.5)
            dropped_dns_failed=False
            try: send_dns(inbound_port,b'\x42\x18',timeout=2)
            except (socket.timeout,OSError): dropped_dns_failed=True
            time.sleep(.3); dropped_dns_failed = dropped_dns_failed and len(dns_count)==before_dns
            r2=subprocess.run(['curl','--silent','--show-error','--max-time','3','--socks5-hostname','127.0.0.1:10808',u],text=True,capture_output=True); print('Dropped hop2 DNS fails/no new TCP query:', 'PASS' if dropped_dns_failed else 'FAIL'); print('Dropped hop2 HTTP fails:', 'PASS' if r2.returncode!=0 else 'FAIL (unexpected direct fallback)')
            dns_out=next(o for o in c['outbounds'] if o['tag']=='mix-dns'); print('Config routing:', tags, 'DNS outbound:', dns_out); print('Config:',cfg)
            if not ok or not dns_ok or not relay_dns_ok or len(dns_count)!=1 or len(dns_connections)!=1 or not dropped_dns_failed or r2.returncode==0: return 1
            return 0
        finally:
            if proc.poll() is None:
                proc.terminate()
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired: proc.kill(); proc.wait()
            dns_stop.set(); dns.close(); target.close(); [r.close() for r in relays]
if __name__=='__main__':
    import select
    raise SystemExit(main())
