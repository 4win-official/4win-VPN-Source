"""Regression contracts for Android VPN services surviving task/activity recreation.

Run from the repository root with:
    python3 -m unittest tools.test_vpn_background_contract -v

These tests intentionally inspect only checked-in XML/YAML/Kotlin source; they do
not require Flutter, Gradle, an APK build, or network access.
"""

from __future__ import annotations

import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID = "{" + ANDROID_NS + "}"


def android_attr(element: ET.Element, name: str) -> str | None:
    return element.get(ANDROID + name)


def declared_services(manifest: Path) -> list[ET.Element]:
    root = ET.parse(manifest).getroot()
    return list(root.findall(".//service"))


def method_body(source: str, method_name: str) -> str:
    """Return one Kotlin method body using brace balancing, not line matching."""
    match = re.search(r"\b(?:override\s+)?fun\s+" + re.escape(method_name) + r"\s*\([^)]*\)[^{]*\{", source)
    if not match:
        raise AssertionError(f"{method_name} was not found")
    start = match.end() - 1
    depth = 0
    for index in range(start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    raise AssertionError(f"unterminated Kotlin method: {method_name}")


class VpnBackgroundContractTest(unittest.TestCase):
    app_manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    sstp_manifest = ROOT / "packages/sstp_flutter/android/src/main/AndroidManifest.xml"
    plugin_source = ROOT / (
        "packages/sstp_flutter/android/src/main/kotlin/com/example/sstp_flutter/"
        "SstpFlutterPlugin.kt"
    )

    def test_every_app_runtime_service_is_not_stopped_with_task_except_tile(self):
        services = declared_services(self.app_manifest)
        self.assertTrue(services, "the app manifest must declare runtime services")
        for service in services:
            name = android_attr(service, "name") or "<unnamed service>"
            if name.endswith("SstpTileService") or name.endswith("TileService"):
                continue
            self.assertEqual(
                android_attr(service, "stopWithTask"),
                "false",
                f"{name} must explicitly survive task removal",
            )

    def test_app_service_types_and_process_isolation_are_preserved(self):
        services = {
            android_attr(service, "name"): service
            for service in declared_services(self.app_manifest)
        }
        self.assertEqual(
            android_attr(services[".slowdns.SlowDnsVpnService"], "foregroundServiceType"),
            "specialUse",
        )
        self.assertEqual(
            android_attr(services[".DnsVpnService"], "foregroundServiceType"),
            "specialUse",
        )
        self.assertEqual(
            android_attr(services[".XrayVpnService"], "foregroundServiceType"),
            "specialUse",
        )
        self.assertEqual(
            android_attr(services[".XrayProxyService"], "foregroundServiceType"),
            "specialUse",
        )
        self.assertEqual(
            android_attr(services["com.forwin.vpn.PsiphonVpnService"], "process"),
            ":psiphon",
        )

        for index in range(50):
            worker = services[f".mix.MixWorker{index}"]
            openvpn = services[f".mix.openvpn.OpenVpnMixService{index}"]
            self.assertEqual(android_attr(worker, "process"), f":mixworker{index}")
            self.assertEqual(android_attr(openvpn, "process"), f":mixworker{index}")
            self.assertEqual(android_attr(worker, "foregroundServiceType"), "specialUse")
            self.assertEqual(android_attr(openvpn, "foregroundServiceType"), "specialUse")

    def test_standalone_sstp_service_is_special_use_and_survives_task_removal(self):
        services = {
            android_attr(service, "name"): service
            for service in declared_services(self.sstp_manifest)
        }
        sstp = services[".service.SstpVpnService"]
        self.assertEqual(android_attr(sstp, "foregroundServiceType"), "specialUse")
        self.assertEqual(android_attr(sstp, "stopWithTask"), "false")

    def test_sstp_is_resolved_from_the_vendored_path_dependency(self):
        lines = (ROOT / "pubspec.yaml").read_text(encoding="utf-8").splitlines()
        dependency_start = next(
            (i for i, line in enumerate(lines) if line == "  sstp_flutter:"), None
        )
        self.assertIsNotNone(dependency_start, "pubspec must declare sstp_flutter")
        block: list[str] = []
        for line in lines[dependency_start + 1 :]:
            if re.match(r"^  \S", line):
                break
            block.append(line)
        self.assertIn("    path: packages/sstp_flutter", block)

    def test_activity_and_engine_detach_never_disconnects_the_vpn(self):
        source = self.plugin_source.read_text(encoding="utf-8")
        self.assertIn("ACTION_VPN_DISCONNECT", source, "manual disconnect action disappeared")
        for method_name in ("onDetachedFromActivity", "onDetachedFromEngine"):
            body = method_body(source, method_name)
            self.assertNotRegex(body, r"(?i)\bdisconnect\b|\bstop(?:Vpn|Service)?\b")


if __name__ == "__main__":
    unittest.main()
