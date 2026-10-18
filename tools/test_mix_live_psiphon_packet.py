#!/usr/bin/env python3
"""Live no-relay Psiphon packet-tunnel <-> native Mix packet proof.

The test deliberately uses Unix SOCK_DGRAM as the packet interface: Psiphon's
TunFileDescriptor and aether_mix_packet_* both exchange complete IP datagrams.
"""
from __future__ import annotations
import argparse, ctypes, hashlib, json, os, shutil, socket, struct, subprocess, sys, tempfile, time
from pathlib import Path
from test_mix_live_http_warp import WORKER, run_exporter

ROOT = Path(__file__).resolve().parents[1]
DIAGNOSTIC_WORKER = WORKER.replace("print('STARTED', flush=True)", """
CALLBACK = ctypes.CFUNCTYPE(None, ctypes.c_char_p)
def event(raw):
    try:
        item = json.loads(raw)
        if item.get('type') == 'status':
            print('STATUS', json.dumps(item), flush=True)
        elif item.get('type') == 'log' and '[wg]' in item.get('message', ''):
            print(item['message'], flush=True)
    except Exception:
        pass
callback = CALLBACK(event)
lib.aether_set_event_callback.argtypes = [CALLBACK]
lib.aether_set_event_callback(callback)
print('STARTED', flush=True)
""")

def free_port():
    s=socket.socket(); s.bind(("127.0.0.1",0)); p=s.getsockname()[1]; s.close(); return p

def exact(s,n):
    b=b''
    while len(b)<n:
        x=s.recv(n-len(b))
        if not x: raise RuntimeError("short SOCKS response")
        b+=x
    return b

def socks_reply(s):
    h=exact(s,4)
    if h[1]: raise RuntimeError(f"SOCKS reply {h[1]}")
    n=4 if h[3]==1 else (16 if h[3]==4 else (exact(s,1)[0] if h[3]==3 else None))
    if n is None: raise RuntimeError("bad SOCKS address type")
    exact(s,n+2)

def socks_connect(port,host,dport):
    s=socket.create_connection(("127.0.0.1",port),5); s.settimeout(8)
    s.sendall(b'\x05\x01\x00'); assert exact(s,2)==b'\x05\x00'
    h=host.encode(); s.sendall(b'\x05\x01\x00\x03'+bytes([len(h)])+h+struct.pack('!H',dport)); socks_reply(s); return s

def udp_associate(port):
    c=socket.create_connection(("127.0.0.1",port),5); c.settimeout(8)
    c.sendall(b'\x05\x01\x00'); assert exact(c,2)==b'\x05\x00'
    c.sendall(b'\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00'); h=exact(c,4)
    if h[1]: raise RuntimeError(f"SOCKS UDP ASSOCIATE reply {h[1]}")
    n=4 if h[3]==1 else (16 if h[3]==4 else (exact(c,1)[0] if h[3]==3 else None))
    if n is None: raise RuntimeError('bad UDP bind address type')
    exact(c,n)
    # SOCKS servers commonly return 0.0.0.0; send to loopback and returned port.
    p=struct.unpack('!H',exact(c,2))[0]; u=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); u.settimeout(8)
    return c,u,("127.0.0.1",p)

def dns_query(port, resolver='10.0.0.2'):
    c,u,b=udp_associate(port); tid=os.urandom(2); q=tid+b'\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00'+b'\x07example\x03com\x00\x00\x01\x00\x01'
    # Psiphon's documented transparent resolver. Public resolver replies may
    # be rewritten to this address, so directly querying their IPs is unreliable.
    u.sendto(b'\x00\x00\x00\x01'+socket.inet_aton(resolver)+struct.pack('!H',53)+q,b)
    x,_=u.recvfrom(4096); c.close(); u.close()
    if len(x)<22 or x[10:12]!=tid: raise RuntimeError('invalid DNS response through packet SOCKS')
    flags, questions, answers = struct.unpack('!HHH',x[12:18])
    if not flags & 0x8000 or flags & 0xF or questions != 1 or answers < 1:
        raise RuntimeError('DNS through packet SOCKS did not return a successful answer')
    return len(x)

def trace(port):
    r=subprocess.run(['curl','--silent','--show-error','--max-time','12','--socks5-hostname',f'127.0.0.1:{port}','https://www.cloudflare.com/cdn-cgi/trace'],capture_output=True,text=True)
    if r.returncode or 'warp=' not in r.stdout: raise RuntimeError(f'Cloudflare TCP probe failed rc={r.returncode}: {r.stderr[-500:]}')
    return r.stdout.strip()

def wait_port(p,proc=None,timeout=20):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        if proc and proc.poll() is not None: raise RuntimeError(f'process exited {proc.returncode}: {proc.stderr.read()[-3000:] if proc.stderr else ""}')
        try:
            s=socket.create_connection(('127.0.0.1',p),.25); s.close(); return
        except OSError: time.sleep(.1)
    raise TimeoutError(f'port {p} did not listen')

def stop(p):
    if not p or p.poll() is not None:return
    p.terminate()
    try:p.wait(8)
    except subprocess.TimeoutExpired:p.kill();p.wait(3)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--psiphon',default='/tmp/psiphon-run/psiphon-tunnel-core-x86_64'); ap.add_argument('--server-list',default=''); ap.add_argument('--native-lib',default=str(ROOT/'core/aether/target/debug/libaether.so')); ap.add_argument('--classpath',default='/tmp/mix-routing-classpath'); ap.add_argument('--account',default='/tmp/mix-live-warp/account.toml'); ap.add_argument('--timeout',type=float,default=180); ap.add_argument('--keep-temp',action='store_true'); ap.add_argument('--region',default=''); ap.add_argument('--peer',default='162.159.192.1:2408')
    ap.add_argument('--fresh-warp', action='store_true', help='Provision a new private WARP identity through Psiphon instead of using the account copy')
    a=ap.parse_args()
    psi=Path(a.psiphon); libp=Path(a.native_lib); account=Path(a.account)
    server_list=Path(a.server_list) if a.server_list else None
    for p in (psi,libp,account):
        if not p.is_file(): raise FileNotFoundError(p)
    td=Path(tempfile.mkdtemp(prefix='mix-psiphon-packet-')); td.chmod(0o700); procs=[]; native=None; ps=None; h=None
    before=hashlib.sha256(account.read_bytes()).digest(); raw=None; left=None; right=None
    try:
        # socketpair gives two independently readable/writable datagram FDs; pass only right to Go.
        left,right=socket.socketpair(socket.AF_UNIX,socket.SOCK_DGRAM); right.set_inheritable(True)
        root=td/'psi-root'; root.mkdir(mode=0o700)
        bootstrap=json.loads((ROOT/'android/app/src/main/assets/mix_psiphon_bootstrap.json').read_text())
        cfg={**bootstrap,"LocalSocksProxyPort":0,"LocalHttpProxyPort":0,"DisableLocalSocksProxy":True,"DisableLocalHTTPProxy":True,"DisableTunnels":False,"EnableLightProxyFallback":False,"EnablePersonalLightProxyTunnels":False,"ClientPlatform":"Linux","DataRootDirectory":str(root),"PacketTunnelTunFileDescriptor":right.fileno(),"TunnelPoolSize":1,"EmitDiagnosticNotices":True}
        if a.region: cfg['EgressRegion']=a.region
        cp=td/'psiphon.json'; cp.write_text(json.dumps(cfg)); cp.chmod(0o600)
        raw=td/'psiphon.log'; lf=raw.open('w')
        # -notices takes a filename ("-" is not stdout for this console).
        cmd=[str(psi),'-config',str(cp),'-dataRootDirectory',str(root),'-notices',str(raw)]
        if server_list: cmd += ['-serverList',str(server_list)]
        ps=subprocess.Popen(cmd,pass_fds=(right.fileno(),),stdout=lf,stderr=subprocess.STDOUT,text=True); procs.append(ps); right.close(); right=None
        # Native create is asynchronous; readiness means SOCKS listener + stack packet pump.
        l=ctypes.CDLL(str(libp)); l.aether_mix_packet_create.argtypes=[ctypes.c_char_p,ctypes.c_int]; l.aether_mix_packet_create.restype=ctypes.c_longlong; l.aether_mix_packet_is_ready.argtypes=[ctypes.c_longlong]; l.aether_mix_packet_is_ready.restype=ctypes.c_int; l.aether_mix_packet_stop.argtypes=[ctypes.c_longlong]
        native_cfg=json.dumps({'ipv4':'10.0.0.3','ipv6':'fd00::3','mtu':1500,'listen':f'127.0.0.1:{free_port()}', 'dns':['10.0.0.2:53']}).encode(); hid=l.aether_mix_packet_create(native_cfg,left.fileno())
        if hid<1: raise RuntimeError('aether_mix_packet_create rejected config/fd')
        for _ in range(200):
            if l.aether_mix_packet_is_ready(hid): break
            if ps.poll() is not None: raise RuntimeError(f'Psiphon exited; notices: {raw.read_text(errors="replace")[-3000:]}')
            time.sleep(.1)
        if not l.aether_mix_packet_is_ready(hid): raise TimeoutError('native Mix packet stack not ready')
        # Discover listen port from config: native chose the free port above.
        port=int(json.loads(native_cfg)['listen'].rsplit(':',1)[1]); wait_port(port)
        deadline=time.monotonic()+a.timeout; notices=''; tunnel=False
        while time.monotonic()<deadline:
            notices=raw.read_text(errors='replace')
            for line in notices.splitlines():
                try: notice=json.loads(line)
                except ValueError: continue
                if notice.get('noticeType')=='Tunnels' and notice.get('data',{}).get('count')==1:
                    tunnel=True
                    break
            if tunnel: break
            if ps.poll() is not None: raise RuntimeError('Psiphon exited before Tunnels count=1: '+notices[-2000:])
            time.sleep(.5)
        if not tunnel: raise TimeoutError('Psiphon did not report Tunnels count=1: '+notices[-2000:])
        t1=trace(port); d1=dns_query(port)
        # The real WARP engine sends its WireGuard UDP through that exact packet
        # SOCKS endpoint. No Xray/TLS relay or third-party gateway is involved.
        account_copy=td/'aether-warp.toml'
        if not a.fresh_warp:
            shutil.copyfile(account,account_copy); account_copy.chmod(0o600)
        # With --fresh-warp this stage-private path deliberately does not exist:
        # Aether provisions it through upstream_proxy, matching per-stage app
        # identities without altering the original account or global config.
        classpath=Path(a.classpath).read_text().strip()
        fresh=ROOT/'build/app/tmp/kotlin-classes/debug'
        classpath=str(fresh)+os.pathsep+classpath+os.pathsep+str(td)
        warp_port=free_port()
        warp_input={'config_path':'__APP_FILES__/aether-warp.toml','wireguard_config_path':'__APP_FILES__/aether-warp.toml',
            'protocol':'wg','forced_peer':a.peer,'wireguard_data_check':True,
            'log_level':'info','upstreamSupportsUdp':True}
        warp_config=td/'warp.json'
        warp_config.write_text(json.dumps(run_exporter(classpath,td,warp_input,warp_port,f'socks5://127.0.0.1:{port}')))
        warp_config.chmod(0o600)
        with (td/'warp.log').open('w') as warp_log:
            h=subprocess.Popen([sys.executable,'-c',DIAGNOSTIC_WORKER,str(libp.resolve()),str(warp_config)],
                stdout=warp_log,stderr=subprocess.STDOUT,text=True)
        procs.append(h); wait_port(warp_port,h,min(a.timeout,90))
        successful=0; deadline=time.monotonic()+min(a.timeout,60)
        while time.monotonic()<deadline and successful<2:
            try: response=trace(warp_port)
            except RuntimeError: successful=0; time.sleep(.5); continue
            successful=successful+1 if 'warp=on' in response.splitlines() else 0
        if successful<2: raise AssertionError('Native WARP over native Psiphon did not return warp=on twice')
        # Cut the actual Psiphon tunnel while WARP and its SOCKS endpoint remain
        # alive. A working physical fallback here would be a failed test.
        stop(ps)
        cut=subprocess.run(['curl','--silent','--show-error','--max-time','6','--socks5-hostname',f'127.0.0.1:{warp_port}',
            'https://www.cloudflare.com/cdn-cgi/trace'],capture_output=True,text=True)
        if cut.returncode==0: raise AssertionError('WARP bypassed the stopped Psiphon packet tunnel')
        l.aether_mix_packet_stop(hid); hid=0; left.close(); left=None
        q=subprocess.run(['curl','--silent','--show-error','--max-time','3','--socks5-hostname',f'127.0.0.1:{port}','https://www.cloudflare.com/cdn-cgi/trace'],capture_output=True,text=True)
        if q.returncode==0: raise AssertionError('TCP traffic bypassed stopped packet stack')
        if hashlib.sha256(account.read_bytes()).digest()!=before: raise AssertionError('WARP account fixture modified')
        print(json.dumps({'status':'PASS','direction':'Psiphon→WARP','tcp':'Cloudflare trace',
            'udp_dns_bytes':d1,'warp_on_probes':successful,'psiphon_cut':'fail-closed','external_relay':False},sort_keys=True),flush=True)
    finally:
        if h: stop(h)
        if 'hid' in locals() and hid>0:
            try:l.aether_mix_packet_stop(hid)
            except Exception:pass
        for s in (left,right):
            try:
                if s:s.close()
            except Exception:pass
        for p in reversed(procs):stop(p)
        try: lf.close()
        except Exception:pass
        if a.keep_temp: print(f'kept temp: {td}',file=sys.stderr)
        else: shutil.rmtree(td,ignore_errors=True)
if __name__=='__main__':
    try:main()
    except Exception as e: print('FAIL:',e,file=sys.stderr); raise
