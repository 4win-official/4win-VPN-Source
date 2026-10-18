#!/usr/bin/env python3
"""Opt-in LIVE Mix proxy -> WARP regression, using real Kotlin configs and FFI.

Requires --classpath (compiled app classes + org.json + Kotlin stdlib), --xray,
--native-lib, and --account (an existing personal Aether WARP identity TOML).
The account is copied into a private temporary directory, never modified/logged.
This contacts Cloudflare; it checks warp=on twice and fails closed after cutting
its preceding SOCKS5 hop. It does NOT validate Psiphon -> WireGuard (TCP-only).
"""
import argparse
import ctypes
import json
import shutil
import socket
import subprocess
import tempfile
import threading
import time
from pathlib import Path

EXPORTER = r'''
import java.nio.file.*;
import java.util.*;
import org.json.*;
import com.forwin.vpn.mix.MixRouting;
import com.forwin.vpn.mix.MixWarpConfig;
public class ExportLiveMixWarp {
  public static void main(String[] args) throws Exception {
    JSONObject s = new JSONObject(Files.readString(Path.of(args[0])));
    List<Integer> ports = Arrays.asList(s.getInt("entry"), s.getInt("exit"));
    Map<Integer,Integer> workers = Collections.singletonMap(1, s.getInt("worker"));
    JSONObject sidecar = MixRouting.INSTANCE.sidecar(s.getJSONObject("plan"), ports,
        workers, Collections.emptyMap(), Collections.emptyMap());
    JSONObject warp = MixWarpConfig.INSTANCE.build(s.getJSONObject("warp"),
        args[1], s.getInt("worker"), "socks5://127.0.0.1:" + s.getInt("entry"));
    System.out.print(new JSONObject().put("sidecar", sidecar).put("warp", warp));
  }
}
'''


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classpath', required=True)
    parser.add_argument('--xray', required=True)
    parser.add_argument('--native-lib', required=True)
    parser.add_argument('--account', required=True)
    args = parser.parse_args()
    account = Path(args.account).resolve()
    if not account.is_file():
        parser.error('--account must be an existing Aether WARP identity')
    processes = []
    native = None
    thread = None
    with tempfile.TemporaryDirectory(prefix='mix-live-warp-') as temp:
        root = Path(temp)
        shutil.copyfile(account, root / 'aether-warp.toml')
        (root / 'aether-warp.toml').chmod(0o600)
        entry, exit_port, worker, proxy_port = [free_port() for _ in range(4)]
        spec = {
            'entry': entry, 'exit': exit_port, 'worker': worker,
            'plan': {'hops': [
                {'protocol': 'proxy', 'outbound': {'protocol': 'socks', 'settings': {
                    'servers': [{'address': '127.0.0.1', 'port': proxy_port}]}}},
                {'protocol': 'warp', 'config': {}},
            ]},
            'warp': {
                'config_path': '__APP_FILES__/aether-warp.toml',
                'wireguard_config_path': '__APP_FILES__/aether-warp.toml',
                'protocol': 'wg', 'forced_peer': '162.159.192.1:2408',
                'wireguard_data_check': True, 'log_level': 'error',
                # Negative legacy metadata is deliberately supplied to the helper.
                'upstreamSupportsUdp': True,
            },
        }
        (root / 'spec.json').write_text(json.dumps(spec))
        (root / 'ExportLiveMixWarp.java').write_text(EXPORTER)
        subprocess.run(['javac', '-cp', args.classpath, str(root / 'ExportLiveMixWarp.java')], check=True)
        bundle = json.loads(subprocess.check_output([
            'java', '-cp', str(root) + ':' + args.classpath, 'ExportLiveMixWarp',
            str(root / 'spec.json'), str(root)], text=True))
        assert 'upstreamSupportsUdp' not in bundle['warp']
        # Real SOCKS5 proxy with native UDP ASSOCIATE support, not a mocked hop.
        proxy = {
            'log': {'loglevel': 'warning', 'access': str(root / 'proxy-access.log')},
            'inbounds': [{'listen': '127.0.0.1', 'port': proxy_port, 'protocol': 'socks',
                          'settings': {'auth': 'noauth', 'udp': True}}],
            'outbounds': [{'protocol': 'freedom', 'tag': 'physical'}],
        }
        try:
            for name, config in [('proxy', proxy), ('sidecar', bundle['sidecar'])]:
                path = root / (name + '.json')
                path.write_text(json.dumps(config))
                with (root / (name + '.log')).open('w') as log:
                    processes.append(subprocess.Popen([args.xray, '-c', str(path)], stdout=log, stderr=log))
            time.sleep(.5)
            assert all(p.poll() is None for p in processes), 'Xray process failed to bind'
            native = ctypes.CDLL(str(Path(args.native_lib).resolve()))
            native.aether_start_json.argtypes = [ctypes.c_char_p]
            native.aether_start_json.restype = ctypes.c_int
            native.aether_stop.argtypes = []
            outcome = []
            def run_warp():
                outcome.append(native.aether_start_json(json.dumps(bundle['warp']).encode()))
            thread = threading.Thread(target=run_warp, daemon=True)
            thread.start()
            def probe(timeout=5):
                return subprocess.run([
                    'curl', '--silent', '--show-error', '--max-time', str(timeout),
                    '--socks5-hostname', f'127.0.0.1:{exit_port}',
                    'https://www.cloudflare.com/cdn-cgi/trace'], capture_output=True, text=True)
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                assert thread.is_alive(), f'WARP exited before readiness: {outcome}'
                result = probe(3)
                if result.returncode == 0 and 'warp=on' in result.stdout.splitlines():
                    break
                time.sleep(1)
            else:
                raise AssertionError('Live proxy -> WARP did not reach Cloudflare with warp=on')
            second = probe(12)
            assert second.returncode == 0 and 'warp=on' in second.stdout.splitlines(), 'Second live tunnel probe failed'
            access = (root / 'proxy-access.log').read_text()
            assert '162.159.192.1:2408' in access, 'WARP peer did not traverse the previous proxy'
            print('PASS live Kotlin Mix sidecar proxy -> WARP: Cloudflare warp=on twice; real UDP proxy traversal', flush=True)
            processes[0].terminate()
            processes[0].wait(timeout=5)
            time.sleep(1)
            failed = probe(8)
            assert failed.returncode != 0, 'Traffic bypassed the dropped preceding proxy'
            print('PASS fail-closed: cutting preceding SOCKS5 proxy prevents public HTTP; no direct fallback', flush=True)
        finally:
            if native is not None:
                native.aether_stop()
            if thread is not None:
                thread.join(timeout=5)
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == '__main__':
    main()
