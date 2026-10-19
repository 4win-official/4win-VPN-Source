#!/usr/bin/env python3
"""Exercise exported standalone bridge routing with local Xray and a fake SOCKS.

Requires --config JSON exported from PsiphonTunBridge.buildConfig and --xray.
Only the TUN ingress is replaced with synthetic loopback ingress. This tests
TCP/UDP DNS conversion and UDP blocking, NOT Android TUN or real Psiphon access.
No external connection, VPN route or account is used.
"""
import argparse
import json
import socket
import struct
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from test_mix_chain import dns_query, dns_reply, recv_exact


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--xray', type=Path, required=True)
    args = parser.parse_args()
    requests = []
    failures = []
    dns_seen = []
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen()
    listener.settimeout(.2)
    stop = threading.Event()

    def serve(client):
        with client:
            try:
                client.settimeout(5)
                version, methods = recv_exact(client, 2)
                assert version == 5
                recv_exact(client, methods)
                client.sendall(b'\x05\x00')
                version, command, _, kind = recv_exact(client, 4)
                if kind == 1:
                    host = socket.inet_ntoa(recv_exact(client, 4))
                elif kind == 3:
                    host = recv_exact(client, recv_exact(client, 1)[0]).decode()
                elif kind == 4:
                    host = socket.inet_ntop(socket.AF_INET6, recv_exact(client, 16))
                else:
                    raise AssertionError('bad SOCKS address')
                port = struct.unpack('!H', recv_exact(client, 2))[0]
                requests.append((command, host, port))
                assert version == 5 and command == 1, 'must use SOCKS TCP CONNECT'
                assert host == '1.1.1.1' and port == 53, 'unexpected direct/UDP route'
                client.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00')
                while not stop.is_set():
                    frame = client.recv(2)
                    if not frame:
                        return
                    frame += recv_exact(client, 2 - len(frame))
                    query = recv_exact(client, struct.unpack('!H', frame)[0])
                    dns_seen.append(query)
                    reply = dns_reply(query)
                    client.sendall(struct.pack('!H', len(reply)) + reply)
            except (EOFError, socket.timeout):
                pass
            except Exception as error:
                failures.append(repr(error))

    def accept():
        while not stop.is_set():
            try:
                client, _ = listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            threading.Thread(target=serve, args=(client,), daemon=True).start()

    threading.Thread(target=accept, daemon=True).start()
    config = json.loads(args.config.read_text())
    config['outbounds'][0]['settings']['servers'][0]['port'] = listener.getsockname()[1]
    dns_port, blocked_port = free_port(), free_port()
    config['inbounds'] = [
        {'tag': 'test-dns', 'listen': '127.0.0.1', 'port': dns_port,
         'protocol': 'dokodemo-door', 'settings': {
             'address': '8.8.8.8', 'port': 53, 'network': 'tcp,udp'}},
        {'tag': 'test-udp', 'listen': '127.0.0.1', 'port': blocked_port,
         'protocol': 'dokodemo-door', 'settings': {
             'address': '203.0.113.1', 'port': 443, 'network': 'udp'}},
    ]
    process = None
    try:
        with tempfile.TemporaryDirectory(prefix='psiphon-dns-transport-') as directory:
            path = Path(directory) / 'config.json'
            path.write_text(json.dumps(config))
            with (Path(directory) / 'xray.log').open('w+') as log:
                process = subprocess.Popen([str(args.xray), 'run', '-config', str(path)],
                                           stdout=log, stderr=log)
                deadline = time.monotonic() + 5
                while True:
                    try:
                        with socket.create_connection(('127.0.0.1', dns_port), .2):
                            break
                    except OSError:
                        if process.poll() is not None or time.monotonic() >= deadline:
                            log.seek(0)
                            raise AssertionError('Xray startup failed: ' + log.read())
                        time.sleep(.05)
                udp_query = dns_query(b'\x12\x34', 'standalone.test')
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                    sock.settimeout(4)
                    sock.sendto(udp_query, ('127.0.0.1', dns_port))
                    reply = sock.recv(4096)
                    assert reply[:2] == udp_query[:2] and b'\x7f\x00\x00\x01' in reply
                tcp_query = dns_query(b'\x43\x21', 'standalone.test')
                with socket.create_connection(('127.0.0.1', dns_port), 4) as sock:
                    sock.settimeout(4)
                    sock.sendall(struct.pack('!H', len(tcp_query)) + tcp_query)
                    reply = recv_exact(sock, struct.unpack('!H', recv_exact(sock, 2))[0])
                    assert reply[:2] == tcp_query[:2] and b'\x7f\x00\x00\x01' in reply
                before = len(requests)
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                    sock.settimeout(.4)
                    sock.sendto(b'blocked-QUIC-fixture', ('127.0.0.1', blocked_port))
                    try:
                        sock.recv(4096)
                        raise AssertionError('non-DNS UDP unexpectedly returned data')
                    except socket.timeout:
                        pass
                assert len(requests) == before, 'non-DNS UDP reached SOCKS'
                assert udp_query in dns_seen and tcp_query in dns_seen
                assert not failures, failures
                print('PASS: UDP and TCP DNS -> SOCKS TCP CONNECT -> local DNS fixture; non-DNS UDP blocked')
                print('Scope: desktop Xray routing only, not Android or a real Psiphon tunnel')
    finally:
        stop.set()
        listener.close()
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == '__main__':
    main()
