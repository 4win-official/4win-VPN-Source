"""Source contracts for standalone notification wiring (no APK/native runtime)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "android/app/src/main/kotlin/com/forwin/vpn"


class StandaloneNotificationTrafficTest(unittest.TestCase):
    def test_xray_uses_serialized_draining_core_counters(self):
        for service in ("XrayVpnService.kt", "XrayProxyService.kt"):
            source = (APP / service).read_text()
            with self.subTest(service=service):
                self.assertIn('@Synchronized\n        private fun readTrafficStats()', source)
                self.assertIn('controller.queryStats("proxy", "uplink")', source)
                self.assertIn('controller.queryStats("proxy", "downlink")', source)
                self.assertIn('totalUplink += up', source)
                self.assertIn('totalDownlink += down', source)
                self.assertIn('synchronized(Companion)', source)
                self.assertIn('counters = { readTrafficStats() }', source)
                self.assertNotIn('TrafficStats.get', source)
                for label in ('"Reconnect"', '"Disconnect"'):
                    self.assertIn(label, source)
                self.assertIn('liveTraffic.stop()', source)

    def test_warp_uses_native_traffic_only_after_connected(self):
        source = (APP / "XrayVpnService.kt").read_text()
        self.assertIn('event.optString("type") == "traffic" && aetherActive', source)
        self.assertIn('event.has("tx") && event.has("rx")', source)
        self.assertIn('totalUplink = event.optLong("tx", -1L)', source)
        self.assertIn('totalDownlink = event.optLong("rx", -1L)', source)
        self.assertIn('(!aetherActive || aetherConnected)', source)
        self.assertIn('if (!mixMode) liveTraffic.start(', source)

    def test_dns_does_not_misrepresent_bypass_traffic_as_vpn_speed(self):
        source = (APP / "DnsVpnService.kt").read_text()
        self.assertIn('Speed unavailable (DNS-only)', source)
        self.assertIn('showNotification(primaryDns, token, connected = true)', source)
        self.assertNotIn('TrafficStats.get', source)

    def test_updater_uses_monotonic_elapsed_time_and_existing_builder(self):
        source = (APP / "LiveTrafficNotification.kt").read_text()
        self.assertIn('SystemClock.elapsedRealtime()', source)
        self.assertIn('sampler.reset()', source)
        self.assertIn('manager?.notify(id, builder.build())', source)
        self.assertIn('handler.postDelayed(this, 1_000L)', source)
        self.assertIn('version != revision.get()', source)
        self.assertNotIn('PendingIntent', source.split('internal class', 1)[1])
        self.assertNotIn('startForeground', source)
        self.assertNotIn('TrafficStats', source)

    def test_mix_services_never_use_standalone_traffic_updater(self):
        for path in (APP / 'mix').rglob('*.kt'):
            self.assertNotIn('LiveTrafficNotification', path.read_text(), str(path))

    def test_slowdns_enables_system_outbound_stats_and_samples_its_own_tag(self):
        config = (APP / 'slowdns/SlowDnsXrayConfig.kt').read_text()
        self.assertIn('put("system", JSONObject()', config)
        self.assertIn('put("statsOutboundUplink", true)', config)
        self.assertIn('put("statsOutboundDownlink", true)', config)
        source = (APP / 'slowdns/SlowDnsVpnService.kt').read_text()
        self.assertIn('controller.queryStats("slowdns", "uplink")', source)
        self.assertIn('controller.queryStats("slowdns", "downlink")', source)
        self.assertIn('synchronized(s.lock)', source)
        self.assertNotIn('TrafficStats.get', source)

    def test_psiphon_accumulates_native_deltas_and_requires_bridge_connectivity(self):
        source = (APP / 'PsiphonVpnService.kt').read_text()
        self.assertIn('onBytesTransferred(sent: Long, received: Long)', source)
        self.assertIn('totalUplink += sent', source)
        self.assertIn('totalDownlink += received', source)
        self.assertIn('connected = { tunnelRunning && isTunnelConnected }', source)
        self.assertNotIn('TrafficStats.get', source)

    def test_services_do_not_access_context_before_android_attaches_it(self):
        for name in ('PsiphonVpnService.kt', 'XrayVpnService.kt',
                     'XrayProxyService.kt', 'slowdns/SlowDnsVpnService.kt'):
            self.assertIn('liveTraffic by lazy { LiveTrafficNotification(this) }',
                          (APP / name).read_text(), name)

    def test_sstp_samples_periodically_without_replacing_protocol_title_or_ui_counters(self):
        base = ROOT / 'packages/sstp_flutter/android/src/main/kotlin/com/example/sstp_flutter'
        service = (base / 'service/SstpVpnService.kt').read_text()
        terminal = (base / 'terminal/IPTerminal.kt').read_text()
        self.assertIn('delay(1000L)', service)
        self.assertIn('owner === activeTrafficOwner', service)
        self.assertIn('trafficSamplerJob?.cancel()', service)
        self.assertIn('builder.setContentTitle(prefs.getString(OscPrefKey.NotificationText.name', service)
        self.assertIn('builder.setContentText(throughput', service)
        self.assertIn('val output = outputStream ?: return', terminal)
        self.assertIn('FlutterCaller().DownloadSpeed(', terminal)
        self.assertIn('FlutterCaller().UploadSpeed(', terminal)
        self.assertNotIn('calculateSpeedKb', terminal)


if __name__ == '__main__':
    unittest.main()
