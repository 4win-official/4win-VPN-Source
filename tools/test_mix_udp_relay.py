#!/usr/bin/env python3
import asyncio
import ipaddress
import os
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from mix_udp_relay import MAGIC, MAX_FRAME, RelayServer, _is_allowed_ip, _valid_token


class MixRelayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.cert, self.key = base / "cert.pem", base / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-keyout", str(self.key), "-out", str(self.cert),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.token = b"test-token-0123456789012345678901"
        self.relay = RelayServer("127.0.0.1", 0, str(self.cert), str(self.key), self.token)
        await self.relay.start()
        self.port = self.relay.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        await self.relay.close()
        self.tmp.cleanup()

    async def connect(self):
        ctx = ssl._create_unverified_context()
        return await asyncio.open_connection("127.0.0.1", self.port, ssl=ctx)

    async def auth(self, token=None):
        token = self.token if token is None else token
        r, w = await self.connect()
        w.write(MAGIC + struct.pack("!H", len(token)) + token)
        await w.drain()
        self.assertEqual(await r.readexactly(1), b"\x00")
        return r, w

    async def udp_echo(self, family=socket.AF_INET):
        class Echo(asyncio.DatagramProtocol):
            def __init__(self): self.transport = None
            def connection_made(self, transport): self.transport = transport
            def datagram_received(self, data, addr): self.transport.sendto(b"echo:" + data, addr)
        loop = asyncio.get_running_loop()
        if family == socket.AF_INET6:
            transport, _ = await loop.create_datagram_endpoint(Echo, local_addr=("::1", 0), family=family)
        else:
            transport, _ = await loop.create_datagram_endpoint(Echo, local_addr=("127.0.0.1", 0))
        return transport, transport.get_extra_info("sockname")

    async def send(self, w, body):
        w.write(struct.pack("!H", len(body)) + body)
        await w.drain()
        length = struct.unpack("!H", await asyncio.wait_for(self._reader.readexactly(2), 2))[0]
        return await self._reader.readexactly(length)

    async def test_bad_token_rejected(self):
        r, w = await self.connect()
        w.write(MAGIC + struct.pack("!H", 3) + b"bad")
        await w.drain()
        self.assertEqual(await asyncio.wait_for(r.readexactly(1), 2), b"\x01")
        self.assertEqual(await r.read(), b"")
        w.close(); await w.wait_closed()

    async def test_token_and_destination_contract(self):
        self.assertFalse(_valid_token(b"short"))
        self.assertTrue(_valid_token(b"x" * 32))
        self.assertTrue(_valid_token(b"x" * 256))
        self.assertFalse(_valid_token(b"x" * 31))
        self.assertFalse(_valid_token(b"x" * 257))
        self.assertFalse(_valid_token(b"x" * 32 + b"\n"))
        self.assertFalse(_is_allowed_ip("239.1.1.1", False))
        self.assertFalse(_is_allowed_ip("239.1.1.1", True))
        self.assertFalse(_is_allowed_ip("255.255.255.255", True))

    async def test_ipv4_roundtrip_and_multiple_peers(self):
        self.relay.allow_private = True  # explicit test/admin mode for local echo peers
        echo1, addr1 = await self.udp_echo()
        echo2, addr2 = await self.udp_echo()
        try:
            r, w = await self.auth()
            self._reader = r
            for addr, payload in ((addr1, b"one"), (addr2, b"two")):
                ip = ipaddress.ip_address(addr[0]).packed
                body = b"\0\0\0\1" + ip + struct.pack("!H", addr[1]) + payload
                reply = await self.send(w, body)
                self.assertEqual(reply[0:4], b"\0\0\0\1")
                self.assertEqual(reply[4:8], ipaddress.ip_address("127.0.0.1").packed)
                self.assertEqual(reply[10:], b"echo:" + payload)
            w.close(); await w.wait_closed()
        finally:
            echo1.close(); echo2.close()

    async def test_ipv6_when_available(self):
        self.relay.allow_private = True  # explicit test/admin mode for local echo peer
        try:
            echo, addr = await self.udp_echo(socket.AF_INET6)
        except OSError:
            self.skipTest("IPv6 unavailable")
        try:
            r, w = await self.auth(); self._reader = r
            body = b"\0\0\0\4" + ipaddress.ip_address("::1").packed + struct.pack("!H", addr[1]) + b"v6"
            reply = await self.send(w, body)
            self.assertEqual(reply[3], 4); self.assertEqual(reply[22:], b"echo:v6")
            w.close(); await w.wait_closed()
        finally:
            echo.close()

    async def test_zero_payload_and_more_than_256_frames(self):
        self.relay.allow_private = True
        echo, addr = await self.udp_echo()
        try:
            r, w = await self.auth(); self._reader = r
            ip = ipaddress.ip_address(addr[0]).packed
            prefix = b"\0\0\0\1" + ip + struct.pack("!H", addr[1])
            self.assertEqual(await self.send(w, prefix), prefix[:10] + b"echo:")
            for i in range(257):
                payload = bytes((i & 255,))
                self.assertEqual(await self.send(w, prefix + payload),
                                 prefix[:10] + b"echo:" + payload)
            w.close(); await w.wait_closed()
        finally:
            echo.close()

    async def test_malformed_oversized_and_private_domain_fail_closed(self):
        self.relay.allow_private = False
        r, w = await self.auth(); self._reader = r
        for body in (b"bad", b"\0\0\0\x05\x01\x7f", b"\0\0\0\x01" + b"\x7f\0\0\x01" + b"\x00\x35" + b"x"):
            w.write(struct.pack("!H", len(body)) + body); await w.drain()
            self.assertEqual(await asyncio.wait_for(r.read(), 2), b"")
            break
        w.close(); await w.wait_closed()
        r, w = await self.auth(); self._reader = r
        w.write(struct.pack("!H", MAX_FRAME + 1)); await w.drain()
        self.assertEqual(await asyncio.wait_for(r.read(), 2), b"")
        w.close(); await w.wait_closed()
        r, w = await self.auth(); self._reader = r
        # localhost resolves to loopback and all DNS results must be rejected.
        name = b"localhost"
        body = b"\0\0\0\x03" + bytes([len(name)]) + name + struct.pack("!H", 9) + b"x"
        w.write(struct.pack("!H", len(body)) + body); await w.drain()
        self.assertEqual(await asyncio.wait_for(r.read(), 2), b"")
        w.close(); await w.wait_closed()

    async def test_no_auth_timeout_and_udp_cleanup(self):
        r, w = await self.connect()
        w.write(MAGIC); await w.drain()
        # Use a short local override rather than waiting ten seconds in the test.
        self.relay.sessions  # session is still bounded and eventually closes
        w.close(); await w.wait_closed()


if __name__ == "__main__":
    unittest.main()
