#!/usr/bin/env python3
"""Bounded live WARP -> WARP identity/registration regression test."""
from __future__ import annotations
import argparse, hashlib, ipaddress, json, os, shutil, subprocess, sys, tempfile, time, tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_mix_udp_bridge import free_port, terminate, wait_port

ROOT = Path(__file__).resolve().parents[1]
WORKER = r'''import ctypes, signal, sys
lib=ctypes.CDLL(sys.argv[1]); lib.aether_start_json.argtypes=[ctypes.c_char_p]; lib.aether_start_json.restype=ctypes.c_int; lib.aether_stop.argtypes=[]
def stop(*_):
    try: lib.aether_stop()
    finally: raise SystemExit(0)
signal.signal(signal.SIGTERM,stop); signal.signal(signal.SIGINT,stop)
print("STARTED",flush=True)
rc=lib.aether_start_json(open(sys.argv[2],"rb").read()); print("NATIVE_RETURN "+str(rc),flush=True); sys.exit(1 if rc else 0)
'''
EGRESS_HARNESS = r'''import com.forwin.vpn.mix.MixEgressProbe;
public final class MixEgressProbeHarness {
  public static void main(String[] a) {
    var result = MixEgressProbe.INSTANCE.fetch(Integer.parseInt(a[0]), 8000);
    System.out.print(result.getIp() + "\t" + result.getWarp());
  }
}
'''


def export_config(cp: str, root: Path, data: dict, listen: int, upstream: str, identity: Path) -> dict:
    src = root / (f"Exporter{listen}.java")
    src.write_text('''import java.nio.file.*; import org.json.*; import com.forwin.vpn.mix.MixWarpConfig;
public final class Exporter%s { public static void main(String[] a) throws Exception { JSONObject c=new JSONObject(Files.readString(Path.of(a[0]))); System.out.print(MixWarpConfig.INSTANCE.build(c,a[1],Integer.parseInt(a[2]),a[3],a[4]).toString()); } }
''' % listen)
    q = subprocess.run(["javac", "-cp", cp, "-d", str(root), str(src)], capture_output=True, text=True)
    if q.returncode: raise RuntimeError("javac failed: " + q.stderr[-2000:])
    inp = root / f"input-{listen}.json"; inp.write_text(json.dumps(data))
    return json.loads(subprocess.check_output(["java", "-cp", str(root)+os.pathsep+cp, f"Exporter{listen}", str(inp), str(root), str(listen), upstream, str(identity)], text=True))


def key_fingerprint(path: Path) -> str:
    with path.open("rb") as f: obj = tomllib.load(f)
    key = obj.get("wg_private_key")
    if not isinstance(key, str) or not key: raise AssertionError(f"missing wg_private_key in {path.name}")
    return hashlib.sha256(key.encode()).hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--account", required=True)
    ap.add_argument("--classpath", default="/tmp/mix-routing-classpath")
    ap.add_argument("--native-lib", default=str(ROOT / "core/aether/target/debug/libaether.so"))
    ap.add_argument("--timeout", type=float, default=120)
    ap.add_argument("--keep-temp", action="store_true")
    a = ap.parse_args()
    account = Path(a.account).resolve(); cpfile=Path(a.classpath); native=Path(a.native_lib)
    if not account.is_file(): ap.error("--account must be an existing Aether WARP identity")
    if not cpfile.is_file(): ap.error(f"classpath not found: {cpfile}")
    if not native.is_file(): ap.error(f"native library not found: {native}")
    td=Path(tempfile.mkdtemp(prefix="mix-live-warp-repeat-")); td.chmod(0o700)
    procs=[]; p0=p1=None; before=hashlib.sha256(account.read_bytes()).digest(); deadline=time.monotonic()+min(a.timeout,180.0)
    try:
        d0=td/"stage0"; d1=td/"stage1"; d0.mkdir(mode=0o700); d1.mkdir(mode=0o700)
        id0=d0/"account.toml"; id1=d1/"account.toml"; shutil.copyfile(account,id0); id0.chmod(0o600)
        port0,port1=free_port(),free_port(); cp=cpfile.read_text().strip()
        harness=td/"MixEgressProbeHarness.java"; harness.write_text(EGRESS_HARNESS)
        compiled=subprocess.run(["javac","-cp",cp,"-d",str(td),str(harness)],capture_output=True,text=True)
        if compiled.returncode: raise RuntimeError("egress harness javac failed: "+compiled.stderr[-2000:])
        harness_cp=str(td)+os.pathsep+cp
        common={"config_path":"__APP_FILES__/placeholder.toml","wireguard_config_path":"__APP_FILES__/placeholder.toml","protocol":"wg","forced_peer":"162.159.192.1:2408","wireguard_data_check":True,"log_level":"error"}
        c0=export_config(cp,d0,common,port0,"",id0); c0.pop("upstream_proxy",None)
        c1=export_config(cp,d1,common,port1,f"socks5://127.0.0.1:{port0}",id1)
        w0=d0/"warp.json"; w1=d1/"warp.json"; w0.write_text(json.dumps(c0)); w1.write_text(json.dumps(c1));
        log0=(d0/"native.log").open("w"); log1=(d1/"native.log").open("w")
        p0=subprocess.Popen([sys.executable,"-c",WORKER,str(native),str(w0)],stdout=log0,stderr=subprocess.STDOUT,text=True); procs.append(p0); wait_port(port0,p0,timeout=min(30,deadline-time.monotonic()))
        p1=subprocess.Popen([sys.executable,"-c",WORKER,str(native),str(w1)],stdout=log1,stderr=subprocess.STDOUT,text=True); procs.append(p1); wait_port(port1,p1,timeout=min(45,deadline-time.monotonic()))
        def probe(port: int, seconds=8):
            return subprocess.run(["curl","--silent","--show-error","--max-time",str(seconds),"--socks5-hostname",f"127.0.0.1:{port}","https://www.cloudflare.com/cdn-cgi/trace"],capture_output=True,text=True)
        def live(port: int, label: str):
            while time.monotonic()<deadline:
                r=probe(port, min(8,max(1,deadline-time.monotonic())))
                if r.returncode==0:
                    fields=dict(line.split("=",1) for line in r.stdout.splitlines() if "=" in line)
                    try: address=ipaddress.ip_address(fields.get("ip",""))
                    except ValueError: address=None
                    if fields.get("warp")=="on" and address is not None and address.is_global:
                        return str(address)
                time.sleep(1)
            raise AssertionError(label+" did not produce warp=on with a public egress IP")
        def kotlin_probe(port: int, label: str):
            result=subprocess.run(["java","-cp",harness_cp,"MixEgressProbeHarness",str(port)],capture_output=True,text=True,timeout=12)
            if result.returncode: raise AssertionError(label+" production verifier failed: "+result.stderr[-1000:])
            ip,separator,warp=result.stdout.partition("\t")
            try: address=ipaddress.ip_address(ip)
            except ValueError: address=None
            if not separator or warp!="on" or address is None or not address.is_global:
                raise AssertionError(label+" production verifier did not confirm WARP with a public IP")
            return str(address)
        stage0_ip=live(port0,"stage0"); stage1_ip=live(port1,"stage1")
        kotlin_probe(port0,"MixEgressProbe stage0"); kotlin_probe(port1,"MixEgressProbe stage1")
        if not id1.is_file(): raise AssertionError("stage1 registration did not create identity TOML")
        f0=key_fingerprint(id0); f1=key_fingerprint(id1)
        if f0==f1: raise AssertionError("stage0 and stage1 wg_private_keys are not distinct")
        hash1=hashlib.sha256(id1.read_bytes()).digest()
        terminate(p1); procs.remove(p1); p1=subprocess.Popen([sys.executable,"-c",WORKER,str(native),str(w1)],stdout=log1,stderr=subprocess.STDOUT,text=True); procs.append(p1); wait_port(port1,p1,timeout=min(30,deadline-time.monotonic())); live(port1,"stage1 restart"); kotlin_probe(port1,"MixEgressProbe stage1 restart")
        if hashlib.sha256(id1.read_bytes()).digest()!=hash1 or key_fingerprint(id1)!=f1: raise AssertionError("stage1 identity changed across restart")
        terminate(p0); time.sleep(1); failed=probe(port1,8)
        if failed.returncode==0: raise AssertionError("stage1 traffic bypassed stopped stage0; direct fallback detected")
        if hashlib.sha256(account.read_bytes()).digest()!=before: raise AssertionError("account fixture was modified")
        assert stage0_ip and stage1_ip
        print("PASS live WARP→WARP: public egress IP at both ordered stages, distinct identities, stage1 registration via stage0 SOCKS5, restart reuse stable, stage0 cut fail-closed",flush=True)
    finally:
        for p in reversed(procs): terminate(p)
        if a.keep_temp: print(f"kept temp: {td}",file=sys.stderr)
        else: shutil.rmtree(td,ignore_errors=True)

if __name__=="__main__":
    try: main()
    except Exception as e: print("FAIL: "+str(e),file=sys.stderr); raise
