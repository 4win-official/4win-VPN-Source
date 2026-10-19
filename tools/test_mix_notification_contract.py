"""Notification wiring regressions; run without Flutter, Gradle or an APK:

    python3 -m unittest tools.test_mix_notification_contract -v

The JVM VpnNotificationLabelsTest separately executes the title-selection policy.
These checks protect its service call sites and all coordinator refresh paths.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

from tools.test_vpn_background_contract import method_body

ROOT = Path(__file__).resolve().parents[1]
KOTLIN = ROOT / "android/app/src/main/kotlin/com/forwin/vpn"


def source(relative: str) -> str:
    return (KOTLIN / relative).read_text(encoding="utf-8")


class MixNotificationContractTest(unittest.TestCase):
    def test_coordinator_refreshes_use_one_fixed_top_level_title(self):
        coordinator = source("mix/MixCoordinatorService.kt")
        builder = method_body(coordinator, "showNotification")
        self.assertIn(".setContentTitle(VpnNotificationLabels.MIX_PROTOCOL)", builder)
        self.assertIn(".setContentText(text)", builder)
        self.assertEqual(coordinator.count("NotificationCompat.Builder("), 1)
        self.assertEqual(coordinator.count("startForeground("), 1)
        self.assertNotIn(".notify(", coordinator)
        # Preparation, per-stage progress, probing and connected state must all
        # flow through the same builder, never an engine-specific notification.
        calls = re.findall(r'showNotification\("([^"\n]*)', coordinator)
        self.assertEqual(len(calls), 4)
        for expected in ("Preparing", "Connecting stage", "Testing", "${hops.length()} stages active"):
            self.assertTrue(any(text.startswith(expected) for text in calls), expected)

    def test_existing_mix_channels_are_renamed_without_changing_ids(self):
        for relative, channel in (("mix/MixCoordinatorService.kt", "MixCoordinator"),
                                  ("mix/MixWorkerService.kt", "MixWorker")):
            with self.subTest(service=relative):
                text = source(relative)
                self.assertIn(f'private const val CHANNEL = "{channel}"', text)
                self.assertIn("NotificationChannel(CHANNEL, VpnNotificationLabels.MIX_PROTOCOL,", text)
                self.assertIn("createNotificationChannel(channel)", text)
                self.assertNotIn('"Mix VPN"', text)
                self.assertNotIn('"Mix engine"', text)

    def test_worker_notification_cannot_expose_an_underlying_engine_title(self):
        worker = source("mix/MixWorkerService.kt")
        self.assertEqual(worker.count(".setContentTitle("), 1)
        self.assertIn(".setContentTitle(VpnNotificationLabels.MIX_PROTOCOL)", worker)
        self.assertEqual(worker.count("NotificationCompat.Builder("), 1)

    def test_xray_refresh_resolves_title_from_connection_mode(self):
        service = source("XrayVpnService.kt")
        builder = method_body(service, "showNotification")
        self.assertIn(".setContentTitle(VpnNotificationLabels.xrayTitle(mixMode, isWarp))", builder)
        self.assertEqual(service.count(".setContentTitle("), 1)
        self.assertEqual(service.count("NotificationCompat.Builder("), 1)
        start = method_body(service, "onStartCommand")
        mode_assignment = "mixMode = intent.getBooleanExtra(EXTRA_MIX_MODE, false)"
        self.assertLess(start.index(mode_assignment), start.index("showNotification()"))
        # Status/traffic/core callbacks may not change the selected identity.
        self.assertEqual(len(re.findall(r"\bmixMode\s*=(?!=)", service)), 2)

    def test_native_entry_point_preserves_mix_identity_and_standalone_routing(self):
        activity = source("MainActivity.kt")
        connect = activity.split('"connectXray", "connectMix" -> {', 1)[1].split('"disconnectXray" ->', 1)[0]
        self.assertIn('val mixMode = call.method == "connectMix"', connect)
        self.assertIn("val proxyMode = !mixMode &&", connect)
        self.assertIn("putExtra(XrayVpnService.EXTRA_MIX_MODE, mixMode)", connect)
        self.assertIn("Intent(this, XrayVpnService::class.java)", connect)
        self.assertIn("Intent(this, XrayProxyService::class.java)", connect)


if __name__ == "__main__":
    unittest.main()
