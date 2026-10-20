#!/usr/bin/env python3
"""Verify and maintain the offline Psiphon signed server-list asset.

Dependencies: Python 3.10+ and ``cryptography`` (the latter is intentionally
used for RSA verification; no network access is performed by the Android
build). The signed file is the official zlib-compressed Psiphon authenticated
data package. Android verifies this envelope and passes its newline-delimited
hexadecimal data field to the SDK's embedded-server-list import API.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import urllib.request
import zlib

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa

MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024
MAX_DECOMPRESSED_BYTES = 8 * 1024 * 1024
DEFAULT_TIMEOUT = 30
CONFIG_RELATIVE = Path("android/app/src/main/assets/mix_psiphon_bootstrap.json")
ASSET_RELATIVE = Path("android/app/src/main/assets/psiphon_server_list.bin")


class VerificationError(ValueError):
    """The input is not a valid signed Psiphon server-list package."""


def _b64(value: object, field: str) -> bytes:
    if not isinstance(value, str) or not value:
        raise VerificationError(f"{field} must be a non-empty base64 string")
    try:
        return base64.b64decode(value.encode("ascii"), validate=True)
    except (UnicodeEncodeError, binascii.Error) as exc:
        raise VerificationError(f"{field} is not valid base64") from exc


def _read_zlib_envelope(blob: bytes) -> dict[str, object]:
    if not blob or len(blob) > MAX_DOWNLOAD_BYTES:
        raise VerificationError("compressed package exceeds size limit")
    decompressor = zlib.decompressobj()
    try:
        decoded = decompressor.decompress(blob, MAX_DECOMPRESSED_BYTES + 1)
        if len(decoded) > MAX_DECOMPRESSED_BYTES or decompressor.unconsumed_tail:
            raise VerificationError("decompressed package exceeds size limit")
        decoded += decompressor.flush(MAX_DECOMPRESSED_BYTES + 1 - len(decoded))
    except zlib.error as exc:
        raise VerificationError("package is not a valid zlib envelope") from exc
    if len(decoded) > MAX_DECOMPRESSED_BYTES or not decompressor.eof:
        raise VerificationError("decompressed package exceeds size limit or is truncated")
    try:
        value = json.loads(decoded.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise VerificationError("envelope is not UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise VerificationError("envelope must be a JSON object")
    return value


def verify_package(blob: bytes, public_key_b64: str) -> tuple[int, str]:
    """Verify *blob* and return (entry_count, SHA256 of compressed bytes)."""
    envelope = _read_zlib_envelope(blob)
    data = envelope.get("data")
    if not isinstance(data, str) or not data:
        raise VerificationError("envelope data is empty or not a string")
    digest_text = envelope.get("signingPublicKeyDigest")
    if not isinstance(digest_text, str):
        raise VerificationError("envelope signingPublicKeyDigest is missing")
    expected_digest = _b64(digest_text, "signingPublicKeyDigest")
    actual_digest = hashlib.sha256(public_key_b64.encode("ascii")).digest()
    if expected_digest != actual_digest:
        raise VerificationError("signing public-key digest mismatch")

    try:
        public_key = serialization.load_der_public_key(_b64(public_key_b64, "public key"))
    except (ValueError, TypeError) as exc:
        raise VerificationError("public key is not a valid DER key") from exc
    if not isinstance(public_key, rsa.RSAPublicKey):
        raise VerificationError("public key is not RSA")
    signature = _b64(envelope.get("signature"), "signature")
    try:
        public_key.verify(signature, data.encode("utf-8"), padding.PKCS1v15(), hashes.SHA256())
    except Exception as exc:  # cryptography uses InvalidSignature plus key-specific errors
        raise VerificationError("signature verification failed") from exc

    entries = data.splitlines()
    if not entries or any(not line for line in entries):
        raise VerificationError("server entries must be non-empty lines")
    for line in entries:
        if len(line) % 2 or any(ch not in "0123456789abcdefABCDEF" for ch in line):
            raise VerificationError("server entries must be valid hexadecimal lines")
    return len(entries), hashlib.sha256(blob).hexdigest()


def _bounded_download(url: str, timeout: int) -> bytes:
    if not url.lower().startswith("https://"):
        raise VerificationError("configured server-list URL must use HTTPS")
    request = urllib.request.Request(url, headers={"User-Agent": "4win-psiphon-bootstrap/1"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            length = response.headers.get("Content-Length")
            if length is not None and int(length) > MAX_DOWNLOAD_BYTES:
                raise VerificationError("download exceeds size limit")
            chunks: list[bytes] = []
            total = 0
            while True:
                chunk = response.read(64 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_DOWNLOAD_BYTES:
                    raise VerificationError("download exceeds size limit")
                chunks.append(chunk)
    except VerificationError:
        raise
    except (OSError, ValueError) as exc:
        raise VerificationError("download failed") from exc
    return b"".join(chunks)


def _config(config_path: Path) -> tuple[str, str]:
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        urls = config["RemoteServerListURLs"]
        url_b64 = urls[0]["URL"]
        url = base64.b64decode(url_b64.encode("ascii"), validate=True).decode("ascii")
        key = config["RemoteServerListSignaturePublicKey"]
    except (OSError, KeyError, IndexError, TypeError, ValueError, UnicodeError, binascii.Error) as exc:
        raise VerificationError("invalid Psiphon bootstrap configuration") from exc
    if not isinstance(url, str) or not url or not isinstance(key, str) or not key:
        raise VerificationError("bootstrap URL or public key is empty")
    return url, key


def _atomic_replace(destination: Path, content: bytes) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
        directory_fd = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="verify the current asset without changing it")
    mode.add_argument("--source", type=Path, help="verify this local signed package and install it")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT, help="HTTPS timeout in seconds")
    args = parser.parse_args(argv)
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    config_path = root / CONFIG_RELATIVE
    destination = root / ASSET_RELATIVE
    try:
        _, public_key = _config(config_path)
        if args.check:
            blob = destination.read_bytes()
        elif args.source:
            blob = args.source.read_bytes()
        else:
            url, _ = _config(config_path)
            blob = _bounded_download(url, args.timeout)
        count, digest = verify_package(blob, public_key)
        if not args.check:
            _atomic_replace(destination, blob)
        action = "checked" if args.check else "installed"
        print(f"PASS: {action} Psiphon signed asset; entries={count}; sha256={digest}")
        return 0
    except (OSError, VerificationError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
