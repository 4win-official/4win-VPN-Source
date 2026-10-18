#!/usr/bin/env python3
"""Authenticated UDP-over-TLS relay for the 4Win client.

The relay deliberately has no plaintext listener.  MIX_RELAY_TOKEN is the only
credential source; never pass credentials on the command line.
"""
from __future__ import annotations

import argparse
import asyncio
import base64
import hmac
import ipaddress
import logging
import os
import socket
import ssl
import struct
from dataclasses import dataclass
from typing import Optional

LOG = logging.getLogger("mix_udp_relay")
MAGIC = b"4WUD1"
MAX_TOKEN = 256
MAX_UDP_PAYLOAD = 65507
MAX_FRAME = MAX_UDP_PAYLOAD + 22
MAX_MAPPINGS = 64
IDLE_TIMEOUT = 60.0
AUTH_TIMEOUT = 10.0
READ_TIMEOUT = 30.0
DNS_TIMEOUT = 5.0
SHUTDOWN_TIMEOUT = 5.0


def _valid_token(token: bytes) -> bool:
    return 32 <= len(token) <= MAX_TOKEN and all(32 <= b <= 126 for b in token)


def _is_allowed_ip(value: str, allow_private: bool) -> bool:
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        return False
    # These destinations are never valid relay peers, even in the explicit
    # private-address test mode.  In particular, is_global is not sufficient:
    # some multicast addresses are globally scoped.
    if (ip.is_multicast or ip.is_unspecified or
            (ip.version == 4 and ip == ipaddress.IPv4Address("255.255.255.255"))):
        return False
    if allow_private:
        return True
    return allow_private or ip.is_global


def _pack_datagram(addr: tuple, payload: bytes) -> bytes:
    host, port = addr[0], addr[1]
    ip = ipaddress.ip_address(host)
    atyp = 1 if ip.version == 4 else 4
    return b"\x00\x00\x00" + bytes((atyp,)) + ip.packed + struct.pack("!H", port) + payload


class RelayProtocolError(Exception):
    pass


@dataclass
class _Mapping:
    key: tuple
    sock: socket.socket
    task: asyncio.Task
    last_used: float


class RelaySession:
    def __init__(self, server: "RelayServer", reader: asyncio.StreamReader,
                 writer: asyncio.StreamWriter):
        self.server = server
        self.reader = reader
        self.writer = writer
        self.mappings: dict[tuple, _Mapping] = {}
        self.write_lock = asyncio.Lock()
        self.closed = False
        self.last_activity = asyncio.get_running_loop().time()

    async def run(self) -> None:
        try:
            if not await self._authenticate():
                return
            while not self.closed:
                try:
                    header = await asyncio.wait_for(self.reader.readexactly(2), READ_TIMEOUT)
                except asyncio.TimeoutError:
                    if asyncio.get_running_loop().time() - self.last_activity >= IDLE_TIMEOUT:
                        raise
                    continue
                length = struct.unpack("!H", header)[0]
                if length < 8 or length > MAX_FRAME:
                    raise RelayProtocolError("invalid frame length")
                frame = await asyncio.wait_for(self.reader.readexactly(length), READ_TIMEOUT)
                await self._send_frame(frame)
        except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError,
                ssl.SSLError, RelayProtocolError, OSError):
            pass
        finally:
            await self.close()

    async def _authenticate(self) -> bool:
        try:
            prefix = await asyncio.wait_for(self.reader.readexactly(7), AUTH_TIMEOUT)
            if prefix[:5] != MAGIC:
                return False
            token_len = struct.unpack("!H", prefix[5:])[0]
            if not (32 <= token_len <= MAX_TOKEN):
                self.writer.write(b"\x01")
                await self.writer.drain()
                return False
            token = await asyncio.wait_for(self.reader.readexactly(token_len), AUTH_TIMEOUT)
            expected = self.server.token
            ok = _valid_token(token) and hmac.compare_digest(token, expected)
            if not ok:
                self.writer.write(b"\x01")
                await self.writer.drain()
                return False
            self.writer.write(b"\x00")
            await self.writer.drain()
            return True
        except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError, ssl.SSLError):
            return False

    async def _send_frame(self, frame: bytes) -> None:
        if frame[:3] != b"\x00\x00\x00":
            raise RelayProtocolError("bad UDP reserved/fragment fields")
        atyp = frame[3]
        if atyp == 1:
            address_len = 4
        elif atyp == 4:
            address_len = 16
        elif atyp == 3:
            if len(frame) < 5:
                raise RelayProtocolError("short domain")
            address_len = frame[4]
            if not 1 <= address_len <= 253:
                raise RelayProtocolError("bad domain length")
        else:
            raise RelayProtocolError("unsupported address type")
        offset = 4 + (1 if atyp == 3 else 0)
        end = offset + address_len
        if len(frame) < end + 2:
            raise RelayProtocolError("short address")
        if atyp == 3:
            try:
                name = frame[offset:end].decode("ascii")
            except UnicodeDecodeError:
                raise RelayProtocolError("non-ascii domain")
            try:
                port = struct.unpack("!H", frame[end:end + 2])[0]
                if port == 0:
                    raise RelayProtocolError("invalid destination port")
                infos = await asyncio.wait_for(asyncio.get_running_loop().getaddrinfo(
                    name, port, type=socket.SOCK_DGRAM, proto=socket.IPPROTO_UDP), DNS_TIMEOUT)
            except OSError:
                raise RelayProtocolError("DNS failure")
            candidates = []
            for family, _, _, _, sockaddr in infos:
                host = sockaddr[0]
                if not _is_allowed_ip(host, self.server.allow_private):
                    raise RelayProtocolError("DNS result rejected")
                candidates.append((family, host, sockaddr[1]))
            if not candidates:
                raise RelayProtocolError("no DNS results")
            family, host, port = candidates[0]
            key = (family, host, port)
        else:
            raw = frame[offset:end]
            host = str(ipaddress.ip_address(raw))
            port = struct.unpack("!H", frame[end:end + 2])[0]
            if port == 0:
                raise RelayProtocolError("invalid destination port")
            if not _is_allowed_ip(host, self.server.allow_private):
                raise RelayProtocolError("destination rejected")
            family = socket.AF_INET if atyp == 1 else socket.AF_INET6
            key = (family, host, port)
        payload = frame[end + 2:]
        if len(payload) > MAX_UDP_PAYLOAD:
            raise RelayProtocolError("payload too large")
        mapping = self.mappings.get(key)
        if mapping is None:
            if len(self.mappings) >= MAX_MAPPINGS:
                raise RelayProtocolError("mapping limit")
            sock = socket.socket(family, socket.SOCK_DGRAM)
            sock.setblocking(False)
            try:
                sock.bind(("0.0.0.0", 0) if family == socket.AF_INET else ("::", 0))
                destination = (key[1], key[2], 0, 0) if family == socket.AF_INET6 else (key[1], key[2])
                await asyncio.get_running_loop().sock_connect(sock, destination)
            except BaseException:
                sock.close()
                raise
            task = asyncio.create_task(self._receive(key, sock))
            mapping = _Mapping(key, sock, task, asyncio.get_running_loop().time())
            self.mappings[key] = mapping
        mapping.last_used = asyncio.get_running_loop().time()
        try:
            await asyncio.get_running_loop().sock_sendall(mapping.sock, payload)
            self.last_activity = asyncio.get_running_loop().time()
        except OSError:
            raise RelayProtocolError("UDP send failed")

    async def _receive(self, key: tuple, sock: socket.socket) -> None:
        loop = asyncio.get_running_loop()
        try:
            while not self.closed:
                mapping = self.mappings.get(key)
                if not mapping:
                    return
                remaining = IDLE_TIMEOUT - (loop.time() - mapping.last_used)
                if remaining <= 0:
                    return
                try:
                    # The socket is connected to the authorized peer, so the
                    # kernel filters datagrams from every other source.
                    data = await asyncio.wait_for(loop.sock_recv(sock, MAX_UDP_PAYLOAD), remaining)
                except asyncio.TimeoutError:
                    if loop.time() - mapping.last_used >= IDLE_TIMEOUT:
                        return
                    continue
                mapping.last_used = loop.time()
                self.last_activity = mapping.last_used
                datagram = _pack_datagram((key[1], key[2]), data)
                if len(datagram) > MAX_FRAME:
                    continue
                async with self.write_lock:
                    if self.closed:
                        return
                    self.writer.write(struct.pack("!H", len(datagram)) + datagram)
                    await asyncio.wait_for(self.writer.drain(), READ_TIMEOUT)
        except (asyncio.TimeoutError, asyncio.CancelledError, ConnectionError, OSError, ssl.SSLError):
            return
        finally:
            current = self.mappings.get(key)
            if current and current.sock is sock:
                self.mappings.pop(key, None)
            sock.close()

    async def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        for mapping in list(self.mappings.values()):
            mapping.task.cancel()
            mapping.sock.close()
        await asyncio.gather(*(m.task for m in self.mappings.values()), return_exceptions=True)
        self.mappings.clear()
        self.writer.close()
        try:
            await asyncio.wait_for(self.writer.wait_closed(), SHUTDOWN_TIMEOUT)
        except (OSError, ConnectionError, asyncio.TimeoutError):
            pass


class RelayServer:
    def __init__(self, host: str, port: int, cert: str, key: str,
                 token: Optional[bytes] = None, allow_private: bool = False):
        self.host, self.port, self.cert, self.key = host, port, cert, key
        self.token = token if token is not None else os.environ.get("MIX_RELAY_TOKEN", "").encode("ascii", "strict")
        if not _valid_token(self.token):
            raise ValueError("MIX_RELAY_TOKEN must be 32-256 printable ASCII bytes")
        self.allow_private = allow_private
        self.server: Optional[asyncio.AbstractServer] = None
        self.sessions: set[RelaySession] = set()
        self.session_limit = asyncio.Semaphore(256)

    def ssl_context(self) -> ssl.SSLContext:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.options |= ssl.OP_NO_COMPRESSION
        context.load_cert_chain(self.cert, self.key)
        return context

    async def _accepted(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        # Do not let unauthenticated clients consume unbounded application tasks.
        if not self.session_limit.locked():
            await self.session_limit.acquire()
        else:
            writer.close()
            await writer.wait_closed()
            return
        session = RelaySession(self, reader, writer)
        self.sessions.add(session)
        try:
            await session.run()
        finally:
            self.sessions.discard(session)
            self.session_limit.release()

    async def start(self) -> asyncio.AbstractServer:
        self.server = await asyncio.start_server(self._accepted, self.host, self.port,
                                                 ssl=self.ssl_context(), ssl_handshake_timeout=AUTH_TIMEOUT,
                                                 limit=MAX_FRAME + 2)
        return self.server

    async def close(self) -> None:
        if self.server:
            self.server.close()
            await self.server.wait_closed()
        await asyncio.gather(*(s.close() for s in list(self.sessions)), return_exceptions=True)


async def _main(args: argparse.Namespace) -> None:
    relay = RelayServer(args.host, args.port, args.cert, args.key, allow_private=args.allow_private)
    server = await relay.start()
    sockets = server.sockets or []
    LOG.info("relay listening on %s", ", ".join(str(s.getsockname()) for s in sockets))
    try:
        await server.serve_forever()
    finally:
        await relay.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=4433)
    parser.add_argument("--cert", required=True, help="PEM certificate chain")
    parser.add_argument("--key", required=True, help="PEM private key")
    parser.add_argument("--allow-private", action="store_true", help="allow non-global destinations (testing/admin only)")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(_main(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
