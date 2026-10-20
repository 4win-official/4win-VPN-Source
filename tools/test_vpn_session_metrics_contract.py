"""Source-level wiring checks; runtime clock/counter behavior is covered by JUnit."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "android/app/src/main/kotlin/com/forwin/vpn"


class VpnSessionMetricsContractTest(unittest.TestCase):
    def test_activity_never_starts_or_ends_a_session(self):
        activity = (NATIVE / "MainActivity.kt").read_text()
        state_reader = activity.split("private fun nativeVpnState(", 1)[1]
        self.assertNotRegex(state_reader, r"NativeSessionMetrics\.(begin|adopt|end)\(")
        self.assertNotIn("SystemClock.elapsedRealtime()", state_reader)
        for field in ("sessionId", "elapsedMillis", "uplink", "downlink"):
            self.assertIn('"' + field + '"', state_reader)

    def test_protocol_aliases_follow_actual_transport_owner(self):
        activity = (NATIVE / "MainActivity.kt").read_text()
        self.assertIn('"xray", "proxy" ->', activity)
        warp = activity.split('"warp" -> {', 1)[1].split('"xray", "proxy" ->', 1)[0]
        self.assertIn('WarpConnectionState.snapshot()', warp)
        self.assertIn('connected = state.connected', warp)
        self.assertIn('metricsOwner = "xray"', warp)
        self.assertIn('stats = XrayVpnService.queryTrafficStats()', warp)
        self.assertIn('metricsOwner = if (pr || prr) "proxy" else "xray"', activity)
        self.assertIn('metricsOwner = if (mr || mrr) "mix" else "xray"', activity)
        self.assertIn('if (mr) MixCoordinatorService.traffic() else XrayVpnService.queryTrafficStats()', activity)
        application = (NATIVE / "VpnApplication.kt").read_text()
        self.assertIn('"XrayVpnService" -> "xray"', application)
        self.assertIn('"XrayProxyService" -> "proxy"', application)
        self.assertIn('"MixCoordinatorService" -> "mix"', application)
        # Service mode flags are published after callbacks: do not key the clock by them.
        self.assertNotIn('isMixModeRunning', application)

    def test_native_lifecycle_resets_without_ui_or_delayed_end(self):
        application = (NATIVE / "VpnApplication.kt").read_text()
        starting = application.split('override fun onVpnConnectionStarting', 1)[1].split('override fun onVpnConnectionStateChanged', 1)[0]
        self.assertIn('NativeSessionMetrics.end(it)', starting)
        self.assertIn('if (connected) NativeSessionMetrics.begin(protocol)', application)
        self.assertIn('else NativeSessionMetrics.end(protocol)', application)
        self.assertNotIn('pendingSessionEnds', application)

    def test_psiphon_broadcast_restores_service_start_across_processes(self):
        service = (NATIVE / "PsiphonVpnService.kt").read_text()
        store = (NATIVE / "PsiphonStatusStore.kt").read_text()
        application = (NATIVE / "VpnApplication.kt").read_text()
        self.assertIn('sessionStartedAtElapsed = SystemClock.elapsedRealtime()', service)
        self.assertIn('putExtra(EXTRA_SESSION_ID, activeSession)', service)
        self.assertIn('putExtra(EXTRA_STARTED_AT_ELAPSED, sessionStartedAtElapsed)', service)
        self.assertIn('intent.getLongExtra(PsiphonVpnService.EXTRA_STARTED_AT_ELAPSED', store)
        self.assertIn('NativeSessionMetrics.adopt("psiphon", id, started)', application)

    def test_direct_dns_does_not_fabricate_vpn_traffic(self):
        activity = (NATIVE / "MainActivity.kt").read_text()
        reader = activity.split('private fun nativeVpnState', 1)[1]
        dns = reader.split('"direct_dns" -> {', 1)[1].split('"slowdns" ->', 1)[0]
        self.assertNotRegex(dns, r'TrafficStats|stats\s*=')

    def test_standalone_sstp_metadata_is_merged_not_mix_hop_counters(self):
        activity = (NATIVE / "MainActivity.kt").read_text()
        self.assertIn('val state = SstpVpnService.state(applicationContext)', activity)
        self.assertIn('standaloneMetrics = state', activity)
        self.assertIn('state[key]?.let { out[key] = it }', activity)

    def test_sstp_clock_and_totals_belong_to_the_live_service(self):
        service = (ROOT / 'packages/sstp_flutter/android/src/main/kotlin/com/example/sstp_flutter/service/SstpVpnService.kt').read_text()
        self.assertIn('private var liveInstance: SstpVpnService?', service)
        self.assertIn('service.snapshotState(running)', service)
        self.assertIn('if (connected) markNativeConnected()', service)
        self.assertIn('nativeConnectedAtElapsedRealtime = SystemClock.elapsedRealtime()', service)
        self.assertIn('state["uplink"] = trafficUploadBytes', service)
        self.assertIn('state["downlink"] = trafficDownloadBytes', service)
        self.assertIn('nativeSessionId = UUID.randomUUID().toString()', service)
        for name in ('internal fun close()', 'override fun onDestroy'):
            section = service.split(name, 1)[1]
            self.assertIn('resetNativeSession()', section)


if __name__ == '__main__':
    unittest.main()
