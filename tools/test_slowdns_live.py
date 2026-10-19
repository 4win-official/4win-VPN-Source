#!/usr/bin/env python3
"""Loopback-only SlowDNS/dnstt and optional Linux Xray integration test.

The test uses real dnstt binaries but never contacts the public network.  The
fixture is a SOCKS5 server whose 1.1.1.1:53 target is a loopback DNS service.
"""
import argparse
import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import time
from pathlib import Path

import select

LOG = Path("/tmp/4win-slowdns-live.log")
AUTH_USER = "fixture-user"
AUTH_PASS = "fixture-pass"


class Fixture:
    def __init__(self):
        self.stop = threading.Event()
        self.threads = []
        self.lock = threading.Lock()
        self.connections = 0
        self.dns_connections = 0
        self.rejections = 0
        self.echo = self._listen()
        self.dns = self._listen()
        self.socks = self._listen()
        self.echo_addr = self.echo.getsockname()
        self.dns_addr = self.dns.getsockname()
        self.socks_addr = self.socks.getsockname()

    @staticmethod
    def _listen():
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("127.0.0.1", 0))
        s.listen(32)
        s.settimeout(0.2)
        return s

    @staticmethod
    def recv_exact(c, n):
        data = bytearray()
        while len(data) < n:
            chunk = c.recv(n - len(data))
            if not chunk:
                raise EOFError("short socket read")
            data.extend(chunk)
        return bytes(data)

    def start(self):
        for sock, handler in ((self.echo, self.echo_client),
                              (self.dns, self.dns_client),
                              (self.socks, self.socks_client)):
            t = threading.Thread(target=self._accept, args=(sock, handler), daemon=True)
            t.start()
            self.threads.append(t)

    def _accept(self, sock, handler):
        while not self.stop.is_set():
            try:
                conn, _ = sock.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            t = threading.Thread(target=handler, args=(conn,), daemon=True)
            t.start()
            self.threads.append(t)

    @staticmethod
    def echo_client(conn):
        with conn:
            while True:
                data = conn.recv(65536)
                if not data:
                    return
                conn.sendall(data)

    def dns_client(self, conn):
        # DNS-over-TCP is a two-byte big-endian message length followed by one
        # complete DNS message. Never parse a raw stream as a datagram.
        with conn:
            conn.settimeout(2)
            try:
                length = int.from_bytes(self.recv_exact(conn, 2), "big")
                if not 12 <= length <= 65535:
                    return
                query = self.recv_exact(conn, length)
                # Return a minimal, type-correct answer for both the A and TXT
                # probes.  The tests below parse the complete DNS message.
                qname_end = 12
                while qname_end < len(query) and query[qname_end]:
                    qname_end += 1 + query[qname_end]
                qname_end += 1
                qtype = int.from_bytes(query[qname_end:qname_end + 2], "big")
                flags = (int.from_bytes(query[2:4], "big") | 0x8000 | 0x0080).to_bytes(2, "big")
                if qtype == 16:
                    rr = (b"\xc0\x0c\x00\x10\x00\x01\x00\x00\x00<\x00\x05"
                          b"\x04test")
                else:
                    rr = (b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00<\x00\x04\x7f\x00\x00\x01")
                response = query[:2] + flags + b"\x00\x01\x00\x01\x00\x00\x00\x00" + query[12:] + rr
                conn.sendall(len(response).to_bytes(2, "big") + response)
                with self.lock:
                    self.dns_connections += 1
            except (EOFError, OSError, socket.timeout):
                return

    def socks_client(self, conn):
        with conn:
            conn.settimeout(5)
            try:
                version, count = self.recv_exact(conn, 2)
                if version != 5:
                    raise ValueError("bad SOCKS version")
                methods = self.recv_exact(conn, count)
                if 2 in methods:
                    conn.sendall(b"\x05\x02")
                    av, ulength = self.recv_exact(conn, 2)
                    user = self.recv_exact(conn, ulength)
                    plength = self.recv_exact(conn, 1)[0]
                    password = self.recv_exact(conn, plength)
                    ok = (av == 1 and user == AUTH_USER.encode() and password == AUTH_PASS.encode())
                    conn.sendall(b"\x01\x00" if ok else b"\x01\x01")
                    if not ok:
                        with self.lock:
                            self.rejections += 1
                        return
                elif 0 in methods:
                    conn.sendall(b"\x05\x00")
                else:
                    conn.sendall(b"\x05\xff")
                    return
                ver, command, _, atyp = self.recv_exact(conn, 4)
                if ver != 5 or command != 1:
                    conn.sendall(b"\x05\x07\x00\x01" + b"\x00" * 6)
                    return
                if atyp == 1:
                    host = socket.inet_ntoa(self.recv_exact(conn, 4))
                elif atyp == 3:
                    host = self.recv_exact(conn, self.recv_exact(conn, 1)[0]).decode()
                elif atyp == 4:
                    host = socket.inet_ntop(socket.AF_INET6, self.recv_exact(conn, 16))
                else:
                    raise ValueError("bad address type")
                port = int.from_bytes(self.recv_exact(conn, 2), "big")
                if (host, port) == ("1.1.1.1", 53):
                    target = self.dns_addr
                elif host == "127.0.0.1" and port == self.echo_addr[1]:
                    target = self.echo_addr
                else:
                    with self.lock:
                        self.rejections += 1
                    conn.sendall(b"\x05\x02\x00\x01" + b"\x00" * 6)
                    return
                upstream = socket.create_connection(target, 3)
                with self.lock:
                    self.connections += 1
                conn.sendall(b"\x05\x00\x00\x01" + socket.inet_aton("127.0.0.1") +
                             target[1].to_bytes(2, "big"))
                self.bridge(conn, upstream)
            except (EOFError, OSError, ValueError, socket.timeout):
                return

    def bridge(self, left, right):
        try:
            while not self.stop.is_set():
                ready, _, _ = select.select([left, right], [], [], 0.2)
                for source in ready:
                    data = source.recv(65536)
                    if not data:
                        return
                    (right if source is left else left).sendall(data)
        except (OSError, socket.timeout):
            return
        finally:
            try:
                right.close()
            except OSError:
                pass

    def close(self):
        self.stop.set()
        for sock in (self.echo, self.dns, self.socks):
            try:
                sock.close()
            except OSError:
                pass


def wait_port(address, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            probe = socket.create_connection(address, 0.2)
            probe.close()
            return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("port did not open: %s" % (address,))


def socks_connect(address, target, auth=False):
    sock = socket.create_connection(address, 3)
    sock.settimeout(5)
    methods = b"\x00\x02" if auth else b"\x00"
    sock.sendall(b"\x05" + bytes([len(methods)]) + methods)
    choice = Fixture.recv_exact(sock, 2)
    if auth:
        if choice != b"\x05\x02":
            raise RuntimeError("RFC1929 method was not selected: %r" % (choice,))
        user = AUTH_USER.encode()
        password = AUTH_PASS.encode()
        sock.sendall(b"\x01" + bytes([len(user)]) + user + bytes([len(password)]) + password)
        if Fixture.recv_exact(sock, 2) != b"\x01\x00":
            raise RuntimeError("RFC1929 credentials rejected")
    elif choice != b"\x05\x00":
        raise RuntimeError("SOCKS negotiation failed: %r" % (choice,))
    host, port = target
    encoded = host.encode()
    sock.sendall(b"\x05\x01\x00\x03" + bytes([len(encoded)]) + encoded + port.to_bytes(2, "big"))
    reply = Fixture.recv_exact(sock, 10)
    if reply[1] != 0:
        raise RuntimeError("SOCKS CONNECT failed: %r" % (reply,))
    return sock


def run(command, log):
    log.write("RUN " + " ".join(map(str, command)) + "\n")
    log.flush()
    return subprocess.Popen(command, stdout=log, stderr=log, text=True, start_new_session=True)


def xray_config(local_port, xray_port):
    server = {"address": "127.0.0.1", "port": local_port}
    return {"log": {"loglevel": "warning"}, "dns": {"servers": ["tcp://1.1.1.1"], "queryStrategy": "UseIP"}, "inbounds": [{"tag": "socks", "listen": "127.0.0.1", "port": xray_port,
        "protocol": "socks", "settings": {"auth": "noauth", "udp": True}}],
        "outbounds": [{"tag": "slowdns", "protocol": "socks", "settings": {"servers": [server]}},
                       {"tag": "dns-out", "protocol": "dns", "settings": {"network": "tcp", "address": "1.1.1.1", "port": 53, "nonIPQuery": "skip"},
                        "proxySettings": {"tag": "slowdns"}}, {"tag": "block", "protocol": "blackhole"}],
        "routing": {"domainStrategy": "AsIs", "rules": [{"type": "field", "port": "53", "network": "tcp,udp",
            "inboundTag": ["socks"], "outboundTag": "dns-out"}, {"type": "field", "network": "udp", "outboundTag": "block"}]}}


def free_port():
    sock = socket.socket(); sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]; sock.close(); return port


def assert_dns_response(message, query, qtype):
    assert len(message) >= 12 and message[:2] == query[:2], "DNS ID mismatch"
    flags = int.from_bytes(message[2:4], "big")
    assert flags & 0x8000 and (flags & 0x000f) == 0, "DNS QR/RCODE invalid"
    assert int.from_bytes(message[4:6], "big") == 1 and int.from_bytes(message[6:8], "big") == 1
    assert message[12:12 + len(query) - 12] == query[12:], "DNS question mismatch"
    pos = 12 + len(query) - 12
    assert message[pos:pos + 2] == b"\xc0\x0c"
    atype = int.from_bytes(message[pos + 2:pos + 4], "big")
    rdlen = int.from_bytes(message[pos + 10:pos + 12], "big")
    rdata = message[pos + 12:pos + 12 + rdlen]
    assert atype == qtype and pos + 12 + rdlen == len(message), "DNS trailing/garbage data"
    if qtype == 1:
        assert rdata == b"\x7f\x00\x00\x01", "unexpected A answer"
    else:
        assert rdata == b"\x04test", "unexpected TXT answer"


def expect_connect_failure(address, target, timeout=2):
    try:
        sock = socks_connect(address, target)
        sock.settimeout(timeout)
        sock.sendall(b"should fail")
        if not sock.recv(1):
            return
    except (OSError, RuntimeError, EOFError, socket.timeout):
        return
    finally:
        try: sock.close()
        except (UnboundLocalError, OSError): pass
    raise AssertionError("connection unexpectedly survived")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="build/slowdns-source/dnstt-20260501")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--xray", help="Linux Xray binary; exercise the generated packet-bridge config")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = Path(args.source)
    if not source.is_absolute():
        source = root / source
    output = root / "build/slowdns-live"
    output.mkdir(parents=True, exist_ok=True)
    server_bin, client_bin = output / "dnstt-server", output / "dnstt-client"
    processes = []
    fixture = None
    keydir = None
    LOG.write_text("slowdns live integration\nsource=%s\n" % source)
    try:
        if not source.is_dir():
            raise RuntimeError("missing pinned source: %s" % source)
        if not args.no_build:
            for package, destination in (("./dnstt-server", server_bin), ("./dnstt-client", client_bin)):
                subprocess.run(["go", "build", "-mod=readonly", "-trimpath", "-o", str(destination), package], cwd=source, check=True)
        with LOG.open("a") as log:
            fixture = Fixture()
            fixture.start()
            keydir = Path(tempfile.mkdtemp(prefix="slowdns-live-"))
            priv, pub = keydir / "priv", keydir / "pub"
            subprocess.run([str(server_bin), "-gen-key", "-privkey-file", str(priv), "-pubkey-file", str(pub)], check=True, stdout=log, stderr=log)
            udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            udp.bind(("127.0.0.1", 0)); resolver_port = udp.getsockname()[1]; udp.close()
            server = run([str(server_bin), "-udp", "127.0.0.1:%d" % resolver_port, "-privkey-file", str(priv), "t.example.com", "127.0.0.1:%d" % fixture.socks_addr[1]], log)
            processes.append(server); time.sleep(0.3)
            if server.poll() is not None:
                raise RuntimeError("dnstt server exited early")
            local = socket.socket(); local.bind(("127.0.0.1", 0)); client_port = local.getsockname()[1]; local.close()
            client = run([str(client_bin), "-udp", "127.0.0.1:%d" % resolver_port, "-pubkey-file", str(pub), "t.example.com", "127.0.0.1:%d" % client_port], log)
            processes.append(client); wait_port(("127.0.0.1", client_port))
            auth_probe = socks_connect(fixture.socks_addr, ("127.0.0.1", fixture.echo_addr[1]), auth=True)
            auth_payload = b"RFC1929 fixture"; auth_probe.sendall(auth_payload); assert auth_probe.recv(len(auth_payload)) == auth_payload; auth_probe.close(); print("PASS RFC1929 username/password")
            stream = socks_connect(("127.0.0.1", client_port), ("127.0.0.1", fixture.echo_addr[1]))
            payload = b"loopback encrypted dnstt roundtrip"; stream.sendall(payload); assert stream.recv(len(payload)) == payload; stream.close(); print("PASS encrypted TCP echo roundtrip")
            auth_encrypted = socks_connect(("127.0.0.1", client_port), ("127.0.0.1", fixture.echo_addr[1]), auth=True)
            auth_encrypted.sendall(b"RFC1929 encrypted")
            assert auth_encrypted.recv(len(b"RFC1929 encrypted")) == b"RFC1929 encrypted"
            auth_encrypted.close(); print("PASS RFC1929 through encrypted dnstt port")
            query = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07fixture\x04test\x00\x00\x01\x00\x01"
            dns = socks_connect(("127.0.0.1", client_port), ("1.1.1.1", 53)); dns.sendall(len(query).to_bytes(2, "big") + query)
            answer_length = int.from_bytes(Fixture.recv_exact(dns, 2), "big"); answer = Fixture.recv_exact(dns, answer_length); dns.close()
            assert answer_length == len(answer); assert_dns_response(answer, query, 1); print("PASS framed DNS-over-TCP query via SOCKS")
            if args.xray:
                xray_port = free_port()
                config_path = keydir / "xray.json"; config_path.write_text(json.dumps(xray_config(client_port, xray_port)))
                xray = run([args.xray, "run", "-c", str(config_path)], log); processes.append(xray); wait_port(("127.0.0.1", xray_port))
                udp_sock = socket.create_connection(("127.0.0.1", xray_port), 3); udp_sock.sendall(b"\x05\x01\x00"); assert Fixture.recv_exact(udp_sock, 2) == b"\x05\x00"
                udp_sock.sendall(b"\x05\x03\x00\x01" + b"\x00" * 6); bind_reply = Fixture.recv_exact(udp_sock, 10); assert bind_reply[1] == 0
                bind_host = socket.inet_ntoa(bind_reply[4:8]); bind_port = int.from_bytes(bind_reply[8:10], "big")
                prior_dns = fixture.dns_connections
                udp_packet = b"\x00\x00\x00\x01\x01\x01\x01\x01\x00\x35" + query
                wire = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); wire.settimeout(5); wire.sendto(udp_packet, (bind_host, bind_port)); wrapped, peer = wire.recvfrom(2048); wire.close()
                assert peer[0] == "127.0.0.1" and wrapped[:10] == udp_packet[:10]
                assert int.from_bytes(wrapped[8:10], "big") == 53; assert_dns_response(wrapped[10:], query, 1)
                assert fixture.dns_connections > prior_dns; print("PASS Xray UDP DNS route and complete response")
                txt = query[:-4] + b"\x00\x10\x00\x01"
                prior_dns = fixture.dns_connections; wire = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); wire.settimeout(5)
                wire.sendto(udp_packet[:10] + txt, (bind_host, bind_port)); wrapped, _ = wire.recvfrom(2048); wire.close(); assert_dns_response(wrapped[10:], txt, 16)
                assert fixture.dns_connections > prior_dns; print("PASS Xray UDP TXT forwarding")
                before_connections = fixture.connections; wire = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); wire.settimeout(1); wire.sendto(b"\x00\x00\x00\x01\x01\x01\x01\x01\x01\xbbgarbage", (bind_host, bind_port))
                try: wire.recvfrom(2048); raise AssertionError("non-DNS UDP was not blackholed")
                except socket.timeout: pass
                finally: wire.close()
                assert fixture.connections == before_connections; print("PASS non-DNS UDP blackhole")
            wrong_priv, wrong_pub = keydir / "wrong-priv", keydir / "wrong-pub"
            subprocess.run([str(server_bin), "-gen-key", "-privkey-file", str(wrong_priv), "-pubkey-file", str(wrong_pub)], check=True, stdout=log, stderr=log)
            bad_port = free_port(); bad_client = run([str(client_bin), "-udp", "127.0.0.1:%d" % resolver_port, "-pubkey-file", str(wrong_pub), "t.example.com", "127.0.0.1:%d" % bad_port], log); processes.append(bad_client)
            time.sleep(1); assert bad_client.poll() is None
            expect_connect_failure(("127.0.0.1", bad_port), ("127.0.0.1", fixture.echo_addr[1])); print("PASS wrong valid generated key rejected")
            dead_port = free_port(); dead_client_port = free_port(); dead_client = run([str(client_bin), "-udp", "127.0.0.1:%d" % dead_port, "-pubkey-file", str(pub), "t.example.com", "127.0.0.1:%d" % dead_client_port], log); processes.append(dead_client)
            wait_port(("127.0.0.1", dead_client_port), 2)
            expect_connect_failure(("127.0.0.1", dead_client_port), ("127.0.0.1", fixture.echo_addr[1]), timeout=2)
            print("PASS dead resolver timeout")
            server.terminate(); server.wait(3); print("PASS server stop terminated transport")
            expect_connect_failure(("127.0.0.1", client_port), ("127.0.0.1", fixture.echo_addr[1])); print("PASS new stream breaks after server stop")
            print("fixture connections=%d dns=%d rejected=%d" % (fixture.connections, fixture.dns_connections, fixture.rejections)); log.write("RESULT PASS all assertions\n")
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
        for process in reversed(processes):
            try: process.wait(3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(3)
        if fixture:
            fixture.close()
            for thread in fixture.threads:
                thread.join(1)
        if keydir: shutil.rmtree(keydir, ignore_errors=True)


if __name__ == "__main__":
    main()
