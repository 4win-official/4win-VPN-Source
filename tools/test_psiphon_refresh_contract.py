"""Native wiring regression; behavior is also exercised by JVM/Flutter tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "android/app/src/main/kotlin/com/forwin/vpn"
PLUGIN = ROOT / "packages/sstp_flutter/android/src/main"


class PsiphonRefreshContractTest(unittest.TestCase):
    def test_flutter_start_does_not_duplicate_native_start_refresh(self):
        source = (ROOT / "lib/providers/vpn_provider.dart").read_text()
        connect = source.split("Future<void> connect({", 1)[1].split("List<String> _deepScanDnsList", 1)[0]
        self.assertNotIn("PsiphonServerListRefresh.request", connect)
        self.assertNotIn("PsiphonServerListRefresh", source)

    def test_every_native_engine_start_calls_shared_optional_host_observer(self):
        paths_and_methods = {
            "DnsVpnService.kt": "private fun startVpn(",
            "XrayVpnService.kt": "private fun startXray(",
            "XrayProxyService.kt": "private fun startXray(",
            "PsiphonVpnService.kt": "private fun startPsiphon(",
            "slowdns/SlowDnsVpnService.kt": "private fun connect(s:",
            "mix/MixCoordinatorService.kt": "private fun startChain(",
        }
        for path, method in paths_and_methods.items():
            source = (NATIVE / path).read_text()
            startup = source.split(method, 1)[1].split("VpnConnectionObserver.notifyStarting(this)", 1)
            self.assertEqual(len(startup), 2, path)
            self.assertEqual(source.count("VpnConnectionObserver.notifyStarting(this)"), 1, path)
        app = (NATIVE / "VpnApplication.kt").read_text()
        self.assertIn("Application(), VpnConnectionObserver", app)
        callback = app.split("override fun onVpnConnectionStarting(source: Context)", 1)[1].split("override fun onCreate()", 1)[0]
        self.assertIn("connectedRefresh.starting(source)", callback)
        self.assertIn("connectedRefresh.stateChanged(source, connected)", callback)
        self.assertNotIn("refreshInBackground", callback)
        self.assertNotIn("download(", callback)

    def test_three_second_timer_only_starts_after_native_ready_and_cancels_on_loss(self):
        timer = (NATIVE / "PsiphonConnectedRefresh.kt").read_text()
        self.assertIn("const val DELAY_MS = 3_000L", timer)
        self.assertIn("if (owner?.get() !== source)", timer)
        self.assertIn("if (connected) return@synchronized", timer)
        self.assertIn("token == generation && connected", timer)
        self.assertIn("pending?.cancel()", timer)
        for path in ("DnsVpnService.kt", "XrayVpnService.kt", "XrayProxyService.kt", "slowdns/SlowDnsVpnService.kt", "mix/MixCoordinatorService.kt"):
            source = (NATIVE / path).read_text()
            self.assertIn("VpnConnectionObserver.notifyState(this, true)", source, path)
            self.assertIn("VpnConnectionObserver.notifyState(this, false)", source, path)
        psiphon = (NATIVE / "PsiphonVpnService.kt").read_text()
        self.assertIn("VpnConnectionObserver.notifyState(this, isTunnelConnected)", psiphon)
        self.assertIn("psiphonCoreConnected && bridgeConfirmed", psiphon)
        warp = (NATIVE / "XrayVpnService.kt").read_text().split("fun onEvent(json: String)", 1)[1].split("fun protectSocket", 1)[0]
        self.assertIn('event.optString("status") == "connected"', warp)
        self.assertIn("isCurrent(token)", warp)

    def test_native_reconnect_and_sticky_restore_reach_same_start_hooks(self):
        psiphon = (NATIVE / "PsiphonVpnService.kt").read_text()
        reconnect = psiphon.split("ACTION_RECONNECT -> {", 1)[1].split("null ->", 1)[0]
        self.assertLess(reconnect.index("token != connectionGeneration"), reconnect.index("startPsiphon(currentRegion)"))
        self.assertIn("compareAndSet(false, true)", reconnect)
        restore = psiphon.split('null -> if (prefs.getBoolean("wanted", false))', 1)[1].split("private fun startPsiphon", 1)[0]
        self.assertIn("startPsiphon(currentRegion)", restore)
        dns = (NATIVE / "DnsVpnService.kt").read_text().split("private fun reconnect(", 1)[1]
        self.assertIn("startVpn(primary, secondary, token)", dns)
        for path in ("XrayVpnService.kt", "XrayProxyService.kt"):
            source = (NATIVE / path).read_text()
            self.assertIn("launch(token)", source.split("private fun reconnect(", 1)[1])
        mix = (NATIVE / "mix/MixCoordinatorService.kt").read_text()
        self.assertIn("startChain(next)", mix.split("private fun requestReconnect(", 1)[1])
        slow = (NATIVE / "slowdns/SlowDnsVpnService.kt").read_text()
        self.assertIn("connect(next, raw)", slow.split("ACTION_RECONNECT ->", 1)[1].split("ACTION_DISCONNECT ->", 1)[0])

    def test_sstp_tile_notification_sticky_and_automatic_retry_share_initialize_client(self):
        source = (PLUGIN / "kotlin/com/example/sstp_flutter/service/SstpVpnService.kt").read_text()
        initialize = source.split("private fun initializeClient(", 1)[1].split("private fun prepareLogWriter", 1)[0]
        self.assertIn("VpnConnectionObserver.notifyStarting(this)", initialize)
        self.assertEqual(source.count("VpnConnectionObserver.notifyStarting(this)"), 1)
        self.assertIn("initializeClient(sessionPrefs)", source.split("internal fun launchJobReconnect()", 1)[1])
        tile = (PLUGIN / "kotlin/com/example/sstp_flutter/service/SstpTileService.kt").read_text()
        self.assertIn("startVpnService(ACTION_VPN_CONNECT)", tile)

    def test_background_refresh_has_nonblocking_cross_process_lock(self):
        source = (NATIVE / "PsiphonServerList.kt").read_text()
        self.assertIn("queue.request {", source)
        self.assertIn("PsiphonRefreshLock.runIfIdle(", source)
        self.assertIn(".refresh(urls)", source)
        lock = (NATIVE / "PsiphonRefreshLock.kt").read_text()
        self.assertIn("channel.tryLock()", lock)
        self.assertNotIn("channel.lock()", lock)
        self.assertIn("lock.use { refresh() }", lock)

    def test_native_refresh_handler_only_schedules_and_acknowledges(self):
        source = (NATIVE / "MainActivity.kt").read_text()
        handler = source.split('"refreshServerList" -> {', 1)[1].split('"prepare" ->', 1)[0]
        self.assertIn("PsiphonServerList.refreshInBackground(applicationContext)", handler)
        self.assertIn("result.success(null)", handler)
        self.assertNotIn("download(", handler)
        self.assertNotIn(".get()", handler)

    def test_both_psiphon_paths_only_read_local_snapshot(self):
        for path in ("PsiphonVpnService.kt", "mix/PsiphonMixAdapter.kt"):
            source = (NATIVE / path).read_text()
            self.assertIn("PsiphonServerList.readLatest(", source)
            self.assertIn("startTunneling(embeddedServers)", source)
            self.assertNotIn("PsiphonServerListStore.download", source)
        store = (NATIVE / "PsiphonServerListStore.kt").read_text()
        reader = store.split("fun readLatest()", 1)[1].split("fun refresh(", 1)[0]
        self.assertNotIn("download(", reader)
        self.assertIn("readServerEntries", reader)

    def test_maintenance_does_not_bypass_android_routing_or_tls(self):
        store = (NATIVE / "PsiphonServerListStore.kt").read_text()
        self.assertIn('require(url.protocol == "https")', store)
        self.assertIn("instanceFollowRedirects = false", store)
        self.assertNotIn("setDefaultSSLSocketFactory", store)
        self.assertNotIn("hostnameVerifier", store)
        self.assertNotIn(".protect(", store)
        self.assertNotIn("bindSocket(", store)


if __name__ == "__main__":
    unittest.main()
