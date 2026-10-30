#!/usr/bin/env python3
"""Contract checks for the authoritative default Split Tunneling package list."""

from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = "http://schemas.android.com/apk/res/android"

EXPECTED_PACKAGES = {
    "com.isc.bminew",
    "com.isc.bsinew",
    "mob.banking.android.pasargad",
    "com.adpdigital.mbs.ayande",
    "com.pmb.mobile",
    "com.bmelat.mobile",
    "com.bpm.sekeh",
    "com.refahbank.dpi.android",
    "com.refah.superapp",
    "com.parsmobapp",
    "com.ada.mbank.mehr",
    "com.rahand.qkids",
    "com.rahand.qbank",
    "com.tosan.dara.sina",
    "com.tosan.dara.sepah",
    "ir.stts.bjt",
    "com.maskanmobilebank",
    "com.bki.mobilebanking.android",
    "com.citydi.hplus",
    "ir.mobillet.app",
    "mob.banking.android.resalat",
    "ir.stsepehr.hamrahcard",
    "com.farazpardazan.enbank",
    "ir.tes.sarmayeh",
    "co.nilin.faraznative",
    "com.tosan.dara.day",
    "digital.neobank",
    "ir.omidbank",
    "com.gostaresh.mobilebank.boilerplate",
    "com.samanpr.blu",
    "co.redbank.app",
    "app.rbmain.a",
    "ir.sep.sesoot",
    "mobi.mmdt.ott",
    "mobi.mmdt.ottplus",
    "ir.eitaa.messenger",
    "ir.resaneh1.iptv",
    "com.app.shadplus",
    "com.bestapps.shadimadareswebbrowser",
    "ir.nasim",
    "com.farsitel.bazaar",
    "com.digikala",
    "com.mydigipay.app.android",
    "ir.divar",
    "com.fidibo.app",
    "com.myirancell",
    "ir.mci.ecareapp",
    "ir.mservices.market",
    "org.rajman.neshan.traffic.tehran.navigator",
    "cab.snapp.passenger",
    "ir.torob",
    "com.dotin.wepod",
    "com.pdpsoft.android.saapa",
    "com.delfan.madp",
    "net.pajal.nili.hamta",
}


def dart_packages():
    source = (ROOT / "lib/screens/split_tunnel_screen.dart").read_text()
    block = re.search(
        r"static const Set<String> _defaultBypassPackages = \{(.*?)\};",
        source,
        re.S,
    )
    if not block:
        raise AssertionError("Dart default package set was not found")
    return set(re.findall(r"'([^']+)'", block.group(1)))


def kotlin_packages():
    source = (ROOT / "android/app/src/main/kotlin/com/forwin/vpn/SplitTunnel.kt").read_text()
    block = re.search(r"private val defaultBypassPackages = setOf\((.*?)\n    \)", source, re.S)
    if not block:
        raise AssertionError("Kotlin default package set was not found")
    return set(re.findall(r'"([^\"]+)"', block.group(1)))


class SplitTunnelContractTest(unittest.TestCase):
    def test_authoritative_list_is_identical_in_dart_kotlin_and_manifest(self):
        self.assertEqual(len(EXPECTED_PACKAGES), 55)
        self.assertEqual(dart_packages(), EXPECTED_PACKAGES)
        self.assertEqual(kotlin_packages(), EXPECTED_PACKAGES)

        manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml").getroot()
        queries = manifest.find("queries")
        self.assertIsNotNone(queries)
        visible_packages = {
            item.attrib[f"{{{ANDROID_NS}}}name"]
            for item in queries.findall("package")
        }
        self.assertEqual(visible_packages, EXPECTED_PACKAGES)
        self.assertEqual(len(visible_packages), len(queries.findall("package")))

    def test_ui_has_only_two_modes_and_migrates_legacy_modes_to_bypass(self):
        ui = (ROOT / "lib/screens/split_tunnel_screen.dart").read_text()
        native = (ROOT / "android/app/src/main/kotlin/com/forwin/vpn/SplitTunnel.kt").read_text()
        self.assertNotIn("ButtonSegment(value: 'off'", ui)
        self.assertIn("Text('Only selected')", ui)
        self.assertIn("Text('Bypass selected')", ui)
        self.assertIn("_mode = modeMigrated && savedMode == 'include' ? 'include' : 'exclude'", ui)
        self.assertIn('putString(MODE_KEY, "exclude")', native)
        self.assertIn('check(allowed > 0)', native)
        self.assertIn('builder.addDisallowedApplication(ownPackage)', native)

    def test_all_standalone_native_vpn_builders_use_the_shared_helper(self):
        paths = [
            "android/app/src/main/kotlin/com/forwin/vpn/DnsVpnService.kt",
            "android/app/src/main/kotlin/com/forwin/vpn/XrayVpnService.kt",
            "android/app/src/main/kotlin/com/forwin/vpn/PsiphonVpnService.kt",
            "android/app/src/main/kotlin/com/forwin/vpn/slowdns/SlowDnsVpnService.kt",
        ]
        for relative in paths:
            with self.subTest(relative=relative):
                source = (ROOT / relative).read_text()
                self.assertIn("SplitTunnel.apply(applicationContext, builder, packageName)", source)

        # Mix owns separate routing and must not be coupled to this preference.
        mix = (ROOT / "android/app/src/main/kotlin/com/forwin/vpn/mix/MixCoordinatorService.kt").read_text()
        self.assertNotIn("SplitTunnel", mix)


if __name__ == "__main__":
    unittest.main()
