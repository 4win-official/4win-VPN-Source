#!/usr/bin/env python3
"""Verify MixWarpConfig output with Aether's real strict Rust FFI parser.

Run after :app:compileDebugKotlin and cargo build --lib, supplying --classpath
(compiled app classes, org.json and Kotlin stdlib) and --native-lib libaether.so.
No account or network is used: a deliberately corrupt temporary identity makes
accepted options stop at local identity parsing, before tunnel provisioning.
This is a config-boundary regression test, NOT an end-to-end WARP connection.
"""
import argparse
import ctypes
import json
import subprocess
import tempfile
from pathlib import Path

EXPORTER = r'''
import java.nio.file.*;
import org.json.*;
import com.forwin.vpn.mix.MixWarpConfig;
public class ExportMixWarpConfig {
  public static void main(String[] args) throws Exception {
    JSONObject input = new JSONObject(Files.readString(Path.of(args[0])));
    JSONObject result = MixWarpConfig.INSTANCE.build(input, args[1], 21345,
        args.length > 2 ? args[2] : null);
    System.out.print(result);
  }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classpath', required=True)
    parser.add_argument('--native-lib', required=True)
    args = parser.parse_args()
    native = ctypes.CDLL(str(Path(args.native_lib).resolve()))
    native.aether_start_json.argtypes = [ctypes.c_char_p]
    native.aether_start_json.restype = ctypes.c_int
    native.aether_last_error.restype = ctypes.c_char_p

    def start(config):
        result = native.aether_start_json(json.dumps(config).encode())
        return result, native.aether_last_error().decode()

    with tempfile.TemporaryDirectory(prefix='mix-warp-config-') as temp:
        root = Path(temp)
        source = root / 'ExportMixWarpConfig.java'
        source.write_text(EXPORTER)
        subprocess.run(['javac', '-cp', args.classpath, str(source)], check=True)
        config = {
            'config_path': '__APP_FILES__/aether-warp.toml',
            'wireguard_config_path': '__APP_FILES__/aether-warp.toml',
            'protocol': 'wg', 'listen': '127.0.0.1:1819',
            'scan_mode': 'balanced', 'ip_scan': 'v4',
            'endpoint_discovery': 'cache', 'wireguard_data_check': True,
            'retry_obfuscation_profiles': True, 'tls_curve_preset': 'chrome',
            'log_level': 'error', 'upstreamSupportsUdp': True,
        }
        input_path = root / 'input.json'
        input_path.write_text(json.dumps(config))
        for upstream in (None, 'socks5://127.0.0.1:21344'):
            command = ['java', '-cp', str(root) + ':' + args.classpath,
                       'ExportMixWarpConfig', str(input_path), str(root)]
            if upstream:
                command.append(upstream)
            effective = json.loads(subprocess.check_output(command, text=True))
            assert 'upstreamSupportsUdp' not in effective
            assert effective.get('upstream_proxy') == upstream
            # Negative control reproduces the reported failure in the real parser.
            old = dict(effective, upstreamSupportsUdp=True)
            code, error = start(old)
            assert code == -1 and 'unknown field' in error and 'upstreamSupportsUdp' in error, (code, error)
            # A valid engine config passes the schema and reaches local TOML load.
            (root / 'aether-warp.toml').write_text('deliberately invalid TOML [')
            code, error = start(effective)
            assert code == -2 and 'config parse:' in error, (code, error)
            assert 'unknown field' not in error
            print(f"PASS real Rust parser: {'inner WARP with upstream' if upstream else 'first WARP'}; legacy metadata rejected, corrected config accepted")


if __name__ == '__main__':
    main()
