#!/usr/bin/env python3
"""Regression contracts for Android/Dart boundaries not exercised by host JVM tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "android/app/src/main/kotlin/com/forwin/vpn"


class PsiphonStartupContractTest(unittest.TestCase):
    def test_only_current_notification_disconnect_echoes_to_flutter(self):
        source = (NATIVE / "PsiphonVpnService.kt").read_text()
        stop = source.split("ACTION_DISCONNECT -> {", 1)[1].split("ACTION_RECONNECT ->", 1)[0]
        reject = 'if (token != null && token != connectionGeneration) return START_STICKY'
        broadcast = 'if (token != null) VpnStateBroadcast.notifyDisconnected(this, "psiphon")'
        self.assertIn(reject, stop)
        self.assertIn(broadcast, stop)
        self.assertLess(stop.index(reject), stop.index(broadcast))
        self.assertEqual(stop.count("notifyDisconnected("), 1)
        self.assertIn('putBoolean("wanted", false)', stop)
        self.assertIn('stopPsiphon(fullStop = true)', stop)
        # Notification actions carry a generation; app cleanup does not.
        notification = source.split("private fun showNotification(", 1)[1]
        self.assertIn('if (generation != null) putExtra(EXTRA_GENERATION, generation)', notification)
        activity = (NATIVE / "MainActivity.kt").read_text()
        app_stop = activity.split('"stop" ->', 1)[1].split('"reconnect" ->', 1)[0]
        self.assertIn('PsiphonVpnService.ACTION_DISCONNECT', app_stop)
        self.assertNotIn('EXTRA_GENERATION', app_stop)

    def test_target_and_embedded_material_share_one_verified_snapshot(self):
        source = (NATIVE / "PsiphonVpnService.kt").read_text()
        startup = source.split("private fun initializePsiphonTunnel(", 1)[1].split("/** Runs [block]", 1)[0]
        self.assertEqual(startup.count("PsiphonServerList.readCatalog("), 1)
        self.assertIn('val embeddedServers = selectedSnapshot?.encoded ?: try', startup)
        self.assertIn('selectedSnapshot?.resolve(requestedId)', startup)
        self.assertIn('startTunneling(embeddedServers)', startup)
        self.assertNotIn('PsiphonServerListStore(', startup)
        self.assertIn('select a server or Automatic, then retry.', startup)
        # Missing explicit targets must fail, not silently switch to Automatic.
        self.assertIn('?: throw IllegalStateException("Selected Psiphon server', startup)

    def test_startup_failure_keeps_existing_kill_switch_tun(self):
        source = (NATIVE / "PsiphonVpnService.kt").read_text()
        failure = source.split('plog("startup failed:', 1)[1].split('private fun stopPsiphon(', 1)[0]
        self.assertIn('if (KillSwitch.isEnabled(applicationContext) && vpnInterface != null)', failure)
        self.assertIn('enterBlackhole("startup failed:', failure)
        self.assertIn('vpnInterface?.close()', failure.split('} else {', 1)[1])
        self.assertIn('lastStatusText = "Psiphon failed:', failure)


if __name__ == "__main__":
    unittest.main()
