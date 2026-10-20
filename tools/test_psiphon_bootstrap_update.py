#!/usr/bin/env python3
"""Offline regression tests for the signed Psiphon seed updater."""
from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zlib

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
import update_psiphon_bootstrap as updater

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / updater.ASSET_RELATIVE
CONFIG = ROOT / updater.CONFIG_RELATIVE


class PsiphonBootstrapUpdateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.public = base64.b64encode(cls.key.public_key().public_bytes(
            serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)).decode()

    def signed(self, data: str = "ab12\nCD34\n") -> dict:
        return dict(data=data, signature=base64.b64encode(self.key.sign(
            data.encode(), padding.PKCS1v15(), hashes.SHA256())).decode(),
            signingPublicKeyDigest=base64.b64encode(hashlib.sha256(self.public.encode()).digest()).decode())

    def encode(self, envelope: dict) -> bytes:
        return zlib.compress(json.dumps(envelope).encode())

    def test_packaged_asset_verifies_without_network_or_external_tmp_fixture(self) -> None:
        _, public = updater._config(CONFIG)
        blob = ASSET.read_bytes()
        count, digest = updater.verify_package(blob, public)
        self.assertGreater(count, 0)
        self.assertEqual(hashlib.sha256(blob).hexdigest(), digest)

    def test_valid_fixture(self) -> None:
        self.assertEqual(2, updater.verify_package(self.encode(self.signed()), self.public)[0])

    def test_signed_payload_tamper_and_key_digest_mismatch(self) -> None:
        for field, value in (("data", "ab13\nCD34\n"), ("signingPublicKeyDigest", base64.b64encode(bytes(32)).decode()),
                             ("signature", "AAAA")):
            envelope = self.signed()
            envelope[field] = value
            with self.subTest(field=field), self.assertRaises(updater.VerificationError):
                updater.verify_package(self.encode(envelope), self.public)

    def test_empty_and_malformed_entries_rejected_even_when_signed(self) -> None:
        for data in ("", "\n", "abc\n", "not-hex\n", "ab12\n\nCD34\n"):
            with self.subTest(data=data), self.assertRaises(updater.VerificationError):
                updater.verify_package(self.encode(self.signed(data)), self.public)

    def test_corrupt_truncated_and_oversized_input(self) -> None:
        for blob in (b"not-zlib", self.encode(self.signed())[:-5],
                     zlib.compress(b"x" * (updater.MAX_DECOMPRESSED_BYTES + 1))):
            with self.assertRaises(updater.VerificationError):
                updater.verify_package(blob, self.public)

    def test_missing_envelope_fields_and_invalid_key_rejected(self) -> None:
        for field in ("data", "signature", "signingPublicKeyDigest"):
            envelope = self.signed()
            del envelope[field]
            with self.subTest(field=field), self.assertRaises(updater.VerificationError):
                updater.verify_package(self.encode(envelope), self.public)
        with self.assertRaises(updater.VerificationError):
            updater.verify_package(self.encode(self.signed()), "invalid")

    def test_download_rejects_plain_http_before_network_access(self) -> None:
        with patch.object(updater.urllib.request, "urlopen") as urlopen:
            with self.assertRaises(updater.VerificationError):
                updater._bounded_download("http://example.com/list", 5)
            urlopen.assert_not_called()

    def test_invalid_update_never_replaces_existing_asset(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / updater.CONFIG_RELATIVE
            destination = root / updater.ASSET_RELATIVE
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps(dict(RemoteServerListURLs=[dict(URL=base64.b64encode(
                b"https://example.com/list").decode())], RemoteServerListSignaturePublicKey=self.public)))
            destination.write_bytes(b"previous-valid-asset")
            source = root / "invalid.bin"
            source.write_bytes(b"not-zlib")
            with patch.object(updater, "__file__", str(root / "tools/update_psiphon_bootstrap.py")):
                self.assertEqual(2, updater.main(["--source", str(source)]))
            self.assertEqual(b"previous-valid-asset", destination.read_bytes())
            self.assertEqual([], list(destination.parent.glob(".psiphon_server_list.bin.*")))

    def test_atomic_replace_writes_complete_asset(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "seed.bin"
            destination.write_bytes(b"old")
            updater._atomic_replace(destination, b"new-complete")
            self.assertEqual(b"new-complete", destination.read_bytes())
            self.assertEqual([destination], list(Path(directory).iterdir()))


if __name__ == "__main__":
    unittest.main()
