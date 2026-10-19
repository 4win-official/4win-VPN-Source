#!/usr/bin/env python3
"""Offline regression tests for the RIPE operator snapshot updater."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "update_operator_ipv4", Path(__file__).with_name("update_operator_ipv4.py")
)
updater = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(updater)
END = "2026-10-19T00:00:00"


def fixture(asn="197207"):
    def prefix(value, end=END):
        return {"prefix": value, "timelines": [
            {"starttime": "2026-10-05T00:00:00", "endtime": end}
        ]}
    return {
        "status": "ok", "status_code": 200, "time": "2026-10-19T06:00:00",
        "data": {"resource": asn, "query_endtime": END, "prefixes": [
            prefix("8.8.8.0/24"), prefix("8.8.8.0/25"),
            prefix("9.9.9.0/24", "2026-10-18T00:00:00"),
            prefix("2001:db8::/32"),
        ]},
    }


class UpdaterTest(unittest.TestCase):
    def test_active_ipv4_union_only(self):
        ranges, raw, visible, _ = updater.parse_response("AS197207", fixture(), END)
        self.assertEqual((raw, visible), (3, 2))
        self.assertEqual(ranges, [(0x08080800, 0x080808ff)])

    def test_rejects_invalid_source_and_timeline(self):
        variants = []
        value = fixture(); value["data"]["resource"] = "44244"; variants.append(value)
        value = fixture(); value["status"] = "error"; variants.append(value)
        value = fixture(); value["data"]["prefixes"][0]["timelines"][0]["endtime"] = "2020-01-01T00:00:00"; variants.append(value)
        value = fixture(); value["data"]["prefixes"] = []; variants.append(value)
        for value in variants:
            with self.subTest(value=value), self.assertRaises(ValueError):
                updater.parse_response("AS197207", value, END)

    def test_cli_uses_returned_endpoint_and_atomic_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for asn in ("197207", "44244"):
                (root / f"AS{asn}.json").write_text(json.dumps(fixture(asn)))
            output = root / "snapshot.dart"
            command = [sys.executable, str(Path(updater.__file__)),
                       "--input-dir", str(root), "--output", str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            before = output.read_bytes()
            self.assertIn((END + "Z").encode(), before)
            self.assertIn(b"collapsedTotalAddresses: 256", before)
            bad = copy.deepcopy(fixture("44244")); bad["status"] = "error"
            (root / "AS44244.json").write_text(json.dumps(bad))
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
