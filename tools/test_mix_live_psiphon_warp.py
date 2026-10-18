#!/usr/bin/env python3
"""Live, fail-closed integration test for the real Psiphon/WARP orders."""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_mix_udp_bridge import free_port, terminate, wait_port, wait_ready
from test_mix_live_http_warp import run_exporter, WORKER

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "android/app/src/main/assets/mix_psiphon_bootstrap.json"
PSIPHON_DEFAULT = Path("/tmp/psiphon-run/psiphon-tunnel-core-x86_64")
ACCOUNT_DEFAULT = Path("/tmp/mix-live-warp/account.toml")


def java_mix(cp: str, out: Path) -> None:
    src = out / "PsiRelayHarness.java"
    src.write_text(r'''package com.forwin.vpn.mix;
import java.io.*; import java.nio.file.*; import java.security.*; import java.security.cert.*;
import java.util.*; import javax.net.ssl.*; import org.json.*;
public final class PsiRelayHarness {
 static SSLContext context(String cert) throws Exception { CertificateFactory f=CertificateFactory.getInstance("X.509"); X509Certificate c=(X509Certificate)f.generateCertificate(new FileInputStream(cert)); KeyStore k=KeyStore.getInstance(KeyStore.getDefaultType()); k.load(null,null); k.setCertificateEntry("relay",c); TrustManagerFactory t=TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()); t.init(k); SSLContext x=SSLContext.getInstance("TLS"); x.init(null,t.getTrustManagers(),new SecureRandom()); return x; }
 public static void main(String[] a) throws Exception {
  int prefix=Integer.parseInt(a[0]), underlay=Integer.parseInt(a[1]), localRelay=Integer.parseInt(a[2]), bridge=Integer.parseInt(a[3]), psi=Integer.parseInt(a[4]); String token=a[5], cert=a[6], cfg=a[7], publicHost=a[8]; int publicPort=Integer.parseInt(a[9]);
  JSONObject plan=new JSONObject().put("hops",new JSONArray().put(new JSONObject().put("protocol","psiphon").put("config",new JSONObject())));
  JSONObject side=MixRouting.INSTANCE.sidecar(plan,Arrays.asList(prefix),new HashMap<Integer,Integer>(){{put(0,psi);}},Collections.emptyMap(),Collections.emptyMap(),new HashMap<Integer,Integer>(){{put(0,bridge);}},new HashMap<Integer,Integer>(){{put(0,underlay);}});
  Files.writeString(Path.of(cfg),side.toString()); if(a.length>10 && a[10].equals("config-only")) return;
  MixUdpRelay b=new MixUdpRelay(new MixUdpRelay.Config(publicHost,publicPort,token,"localhost"),bridge,underlay,context(cert));
  try { b.start(); System.out.println("READY"); System.out.flush(); while(System.in.read()!=-1){} } finally { b.close(); }
 }
}''')
    q = subprocess.run(["javac", "-cp", cp, "-d", str(out), str(src)], capture_output=True, text=True)
    if q.returncode:
        raise RuntimeError("javac failed: " + q.stderr[-3000:])


def start_logged(cmd, log: Path, env=None, stdin=None):
    log.touch(mode=0o600); log.chmod(0o600)
    f = log.open("w")
    return subprocess.Popen(cmd, stdin=stdin, stdout=f, stderr=subprocess.STDOUT, text=True, env=env)


def wait_psi(proc, log: Path, timeout: float) -> None:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if proc.poll() is not None:
            raise RuntimeError("Psiphon exited before Tunnels=1")
        try:
            for line in log.read_text(errors="replace").splitlines():
                try:
                    notice = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if notice.get("noticeType") == "Tunnels" and isinstance(notice.get("data"), dict) and notice["data"].get("count") == 1:
                    return
        except OSError:
            pass
        time.sleep(.25)
    raise TimeoutError("Psiphon did not report Tunnels data.count 1")


def trace(port: int, timeout: float = 10) -> tuple[str, subprocess.CompletedProcess[str]]:
    r = subprocess.run(["curl", "--silent", "--show-error", "--max-time", str(int(timeout)), "--socks5-hostname", f"127.0.0.1:{port}", "https://www.cloudflare.com/cdn-cgi/trace"], capture_output=True, text=True, timeout=timeout + 3)
    ip = next((line[3:].strip() for line in r.stdout.splitlines() if line.startswith("ip=")), "")
    return ip, r


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--order", choices=("reverse", "forward", "both"), default="reverse")
    ap.add_argument("--public-relay-host")
    ap.add_argument("--public-relay-port", type=int)
    ap.add_argument("--local-relay-port", type=int)
    ap.add_argument("--psiphon", default=str(PSIPHON_DEFAULT)); ap.add_argument("--classpath", default="/tmp/mix-routing-classpath")
    ap.add_argument("--xray", default="/tmp/xray-mix-test/xray"); ap.add_argument("--native-lib", default=str(ROOT / "core/aether/target/debug/libaether.so"))
    ap.add_argument("--account", default=str(ACCOUNT_DEFAULT)); ap.add_argument("--timeout", type=float, default=100.0); ap.add_argument("--keep-temp", action="store_true")
    ap.add_argument("--native-worker", nargs=2, metavar=("LIB", "CONFIG"), help=argparse.SUPPRESS)
    a = ap.parse_args()
    if a.native_worker: os.execv(sys.executable, [sys.executable, "-c", WORKER, *a.native_worker])
    if a.order in ("forward", "both") and (not a.public_relay_host or not a.public_relay_port):
        ap.error("--order forward/both requires --public-relay-host and --public-relay-port")
    psi, cp_file, xray, native, account = map(Path, (a.psiphon, a.classpath, a.xray, a.native_lib, a.account))
    account = account.resolve()
    for p, label in ((psi, "Psiphon binary"), (xray, "Xray"), (native, "native library"), (account, "account"), (BOOTSTRAP, "bootstrap")):
        if label == "Xray" and a.order == "reverse":
            continue
        if not p.is_file() or (label in ("Psiphon binary", "Xray") and not os.access(p, os.X_OK)): ap.error(f"{label} not found or not executable: {p}")
    cp = cp_file.read_text().strip(); relay_classes = ROOT / "build/app/tmp/kotlin-classes/debug"
    if (relay_classes / "com/forwin/vpn/mix/MixUdpRelay.class").is_file() and "MixUdpRelay.class" not in cp: cp += os.pathsep + str(relay_classes)
    a.timeout = min(a.timeout, 100.0)
    td = Path(tempfile.mkdtemp(prefix="mix-live-psiphon-warp-")); td.chmod(0o700); processes=[]; result=[]; before=hashlib.sha256(account.read_bytes()).digest()
    try:
        account_copy = td / "aether-warp.toml"; shutil.copyfile(account, account_copy); account_copy.chmod(0o600)
        cert, key, san = td/"relay-cert.pem", td/"relay-key.pem", td/"relay-san.cnf"; san.write_text("[req]\ndistinguished_name=dn\nreq_extensions=reqext\n[dn]\n[reqext]\nsubjectAltName=DNS:localhost\n"); san.chmod(0o600)
        subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-nodes","-days","1","-subj","/CN=localhost","-config",str(san),"-extensions","reqext","-keyout",str(key),"-out",str(cert)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); key.chmod(0o600); cert.chmod(0o600)
        token="mix-psi-relay-"+os.urandom(16).hex(); hcp=cp+os.pathsep+str(td); java_mix(hcp,td)
        b=json.loads(BOOTSTRAP.read_text()); b.update(ClientPlatform="Linux",DiagnosticNotices=True,EmitDiagnosticNotices=True)
        common={"ClientVersion":b.get("ClientVersion","1"),"ClientPlatform":"Linux","PropagationChannelId":b["PropagationChannelId"],"SponsorId":b["SponsorId"],"RemoteServerListURLs":b["RemoteServerListURLs"],"RemoteServerListSignaturePublicKey":b["RemoteServerListSignaturePublicKey"],"DataRootDirectory":str(td/"psiphon-data"),"LocalHttpProxyPort":0,"DiagnosticNotices":True,"EmitDiagnosticNotices":True}
        (td/"psiphon-data").mkdir(mode=0o700); psiconfig=td/"psiphon.json"; psilog=td/"psiphon.log"; socks,prefix,underlay,bridge_port,warp_psi,warp_direct=[free_port() for _ in range(6)]
        warp_input={"config_path":"__APP_FILES__/aether-warp.toml","wireguard_config_path":"__APP_FILES__/aether-warp.toml","protocol":"wg","forced_peer":"162.159.192.1:2408","wireguard_data_check":True,"log_level":"error","upstreamSupportsUdp":True}
        if a.order in ("forward","both"):
            local_relay=a.local_relay_port or free_port(); public_host=a.public_relay_host; public_port=a.public_relay_port; relay=start_logged([sys.executable,str(ROOT/"tools/mix_udp_relay.py"),"--host","127.0.0.1","--port",str(local_relay),"--cert",str(cert),"--key",str(key)],td/"relay.log",env={**os.environ,"MIX_RELAY_TOKEN":token}); processes.append(relay); wait_port(local_relay,relay)
            common["LocalSocksProxyPort"]=socks; psiconfig.write_text(json.dumps(common)); p=start_logged([str(psi),"-config",str(psiconfig),"-dataRootDirectory",str(td/"psiphon-data"),"-notices",str(psilog)],td/"psiphon-process.log"); processes.append(p); wait_port(socks,p,timeout=25); wait_psi(p,psilog,min(45,a.timeout))
            side=td/"sidecar.json"; q=subprocess.run(["java","-cp",hcp,"com.forwin.vpn.mix.PsiRelayHarness",str(prefix),str(underlay),str(local_relay),str(bridge_port),str(socks),token,str(cert),str(side),public_host,str(public_port),"config-only"],capture_output=True,text=True,timeout=15); q.check_returncode(); sj=json.loads(side.read_text()); sj["log"]={"access":str(td/"sidecar.log"),"loglevel":"info"}; side.write_text(json.dumps(sj)); sidecar=start_logged([str(xray),"-c",str(side)],td/"sidecar-xray.log"); processes.append(sidecar); wait_port(prefix,sidecar); wait_port(underlay,sidecar)
            bridge=subprocess.Popen(["java","-cp",hcp,"com.forwin.vpn.mix.PsiRelayHarness",str(prefix),str(underlay),str(local_relay),str(bridge_port),str(socks),token,str(cert),str(side),public_host,str(public_port)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True); processes.append(bridge); wait_ready(bridge)
            wcfg=td/"warp-psi.json"; wcfg.write_text(json.dumps(run_exporter(hcp,td,warp_input,warp_psi,f"socks5://127.0.0.1:{prefix}"))); wp=subprocess.Popen([sys.executable,"-c",WORKER,str(native),str(wcfg)],stdout=(td/"warp-psi.log").open("w"),stderr=subprocess.STDOUT,text=True); processes.append(wp); wait_port(warp_psi,wp,timeout=30)
            good=0; end=time.monotonic()+min(35,a.timeout)
            while time.monotonic()<end and good<2:
                _,r=trace(warp_psi,8); good=good+1 if r.returncode==0 and "warp=on" in r.stdout else 0
                if good<2: time.sleep(.7)
            if good<2: raise AssertionError("Psi-to-WARP did not produce Cloudflare warp=on twice")
            terminate(p); time.sleep(1); _,fail=trace(warp_psi,6)
            if fail.returncode==0: raise AssertionError("Psi-to-WARP bypassed the cut Psiphon")
            result.append("Psiphon→WARP: warp=on twice; Psiphon cut fail-closed")
            for proc in reversed(processes): terminate(proc)
            processes.clear()
        if a.order in ("reverse","both"):
            root2=td/"psiphon-data-reverse"; root2.mkdir(mode=0o700); wdirect=td/"warp-direct.json"; wdirect.write_text(json.dumps(run_exporter(hcp,td,warp_input,warp_direct,""))); wp=subprocess.Popen([sys.executable,"-c",WORKER,str(native),str(wdirect)],stdout=(td/"warp-direct.log").open("w"),stderr=subprocess.STDOUT,text=True); processes.append(wp); wait_port(warp_direct,wp,timeout=30); outer,rr=trace(warp_direct,10)
            if rr.returncode or not outer: raise AssertionError("direct WARP did not provide an outer IP")
            reverse=dict(common,DataRootDirectory=str(root2),LocalSocksProxyPort=socks,UpstreamProxyURL=f"socks5://127.0.0.1:{warp_direct}"); psiconfig.write_text(json.dumps(reverse)); psilog.unlink(missing_ok=True); reverse_cmd=[str(psi),"-config",str(psiconfig),"-dataRootDirectory",str(root2),"-notices",str(psilog)]; p=start_logged(reverse_cmd,td/"psiphon-reverse-process.log"); processes.append(p); wait_port(socks,p,timeout=30); wait_psi(p,psilog,min(45,a.timeout)); inner,ri=trace(socks,10)
            if ri.returncode or not inner or inner==outer: raise AssertionError("WARP-to-Psiphon did not produce a distinct working egress IP")
            terminate(wp); time.sleep(1); _,cut=trace(socks,8)
            if cut.returncode==0: raise AssertionError("WARP-to-Psiphon bypassed the cut WARP upstream")
            result.append("WARP→Psiphon: Tunnels data.count=1 and distinct IP; WARP cut fail-closed")
        print("PASS " + "; ".join(result),flush=True)
    finally:
        for proc in reversed(processes): terminate(proc)
        if hashlib.sha256(account.read_bytes()).digest()!=before: raise AssertionError("account fixture was modified")
        if a.keep_temp: print(f"kept private temp: {td}",file=sys.stderr)
        else: shutil.rmtree(td,ignore_errors=True)

if __name__ == "__main__":
    try: main()
    except Exception as e: print(f"FAIL: {e}",file=sys.stderr); raise
