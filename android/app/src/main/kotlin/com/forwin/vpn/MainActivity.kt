package com.forwin.vpn

import com.forwin.vpn.mix.MixCoordinatorService
import com.forwin.vpn.slowdns.SlowDnsVpnService
import com.example.sstp_flutter.service.SstpVpnService

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.TrafficStats
import android.net.Uri
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin
import de.blinkt.openvpn.VpnProfile
import de.blinkt.openvpn.core.ConfigParser
import de.blinkt.openvpn.core.VpnStatus
import de.blinkt.openvpn.core.ConnectionStatus
import de.blinkt.openvpn.core.LogItem
import java.io.StringReader
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.HttpURLConnection
import java.net.URL

class MainActivity: FlutterActivity() {
    private val DNS_CHANNEL = "com.forwin.vpn/dns"
    private val PSIPHON_CHANNEL = "com.forwin.vpn/psiphon"
    private val PSIPHON_REQUEST_CODE = 102
    private var pendingPsiphonPermission: MethodChannel.Result? = null
    private val XRAY_CHANNEL = "com.forwin.vpn/xray"
    private val IMPORT_CHANNEL = "com.forwin.vpn/import"
    private val OPENVPN_CHANNEL = "com.forwin.vpn/openvpn"
    private val APPS_CHANNEL = "com.forwin.vpn/apps"
    private val VPN_STATE_CHANNEL = "com.forwin.vpn/vpn_state"
    private var vpnStateChannel: MethodChannel? = null
    private var vpnStateReceiver: BroadcastReceiver? = null
    private val VPN_REQUEST_CODE = 100
    private val XRAY_REQUEST_CODE = 101

    // Holds an .ovpn file that the user opened/shared into the app (via VIEW or
    // SEND intents) until the Flutter side pulls it with getPendingOvpnImport.
    private var pendingOvpnName: String? = null
    private var pendingOvpnContent: String? = null
    // The import MethodChannel, kept so we can proactively notify Flutter when a
    // new file arrives while the app is already running (onNewIntent).
    private var importChannel: MethodChannel? = null

    // The OpenVPN MethodChannel, kept so the native VpnStatus StateListener can
    // proactively push an "authFailed" event to Flutter the instant ics-openvpn
    // reports LEVEL_AUTH_FAILED — the ONLY 100% reliable auth-failure signal
    // (the plugin's own status string mapping is lossy). This is what makes the
    // app detect a wrong username/password exactly like the official app.
    private var openvpnChannel: MethodChannel? = null
    private var openvpnStateListener: VpnStatus.StateListener? = null
    @Volatile private var openvpnConnected = false
    // A log listener as a SECOND, redundant auth-failure signal: the OpenVPN
    // core always writes an "AUTH_FAILED" / "auth-failure" log line when the
    // server rejects the credentials, even in edge cases where the state
    // transition to LEVEL_AUTH_FAILED is missed. Detecting either guarantees we
    // catch a wrong username/password like the official app does.
    private var openvpnLogListener: VpnStatus.LogListener? = null
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == PSIPHON_REQUEST_CODE) {
            val pending = pendingPsiphonPermission
            pendingPsiphonPermission = null
            pending?.success(resultCode == RESULT_OK && VpnService.prepare(applicationContext) == null)
        }
        // OpenVPN permission handler
        OpenVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == RESULT_OK)
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        vpnStateReceiver?.let { receiver ->
            try { unregisterReceiver(receiver) } catch (_: IllegalArgumentException) { }
            vpnStateReceiver = null
        }
        vpnStateChannel = null
        // Resolve a pending consent call, but never stop the background VPN
        // just because Android recreates/removes the Activity.
        val pending = pendingPsiphonPermission
        pendingPsiphonPermission = null
        try { pending?.success(false) } catch (_: Throwable) {}
        super.onDestroy()
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val stateChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_STATE_CHANNEL)
        vpnStateChannel = stateChannel
        stateChannel.setMethodCallHandler { call, result ->
            if (call.method != "getState") { result.notImplemented(); return@setMethodCallHandler }
            val protocol = call.argument<String>("protocol")?.lowercase()
            if (protocol == null) { result.error("INVALID_PROTOCOL", "protocol is required", null); return@setMethodCallHandler }
            result.success(nativeVpnState(protocol))
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != VpnStateBroadcast.ACTION_DISCONNECTED) return
                val protocol = intent.getStringExtra(VpnStateBroadcast.EXTRA_PROTOCOL) ?: return
                stateChannel.invokeMethod("onDisconnected", mapOf("protocol" to protocol))
            }
        }
        vpnStateReceiver = receiver
        val filter = IntentFilter(VpnStateBroadcast.ACTION_DISCONNECTED)
        androidx.core.content.ContextCompat.registerReceiver(
            this, receiver, filter, androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED
        )

        // ── OpenVPN validation channel ──────────────────────────────────────
        // The openvpn_flutter plugin (via VPNHelper.connect) catches the
        // RemoteException thrown by OpenVpnApi.startVpn when the config fails
        // ics-openvpn's parse/checkProfile, and SILENTLY swallows it
        // (e.printStackTrace()). So a config that fails to parse produces no
        // stage event and no error — the tunnel just never starts. That is the
        // real reason OpenVPN "does nothing".
        //
        // Here we run the EXACT same pipeline the core uses
        // (ConfigParser.parseConfig → convertProfile → checkProfile) up-front
        // and return the real error string to Dart, so we can (a) see exactly
        // why a config is rejected and (b) show the user a meaningful message
        // instead of a silent failure.
        val openvpnCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OPENVPN_CHANNEL)
        openvpnChannel = openvpnCh

        // Register a global ics-openvpn state listener. updateState() delivers the
        // real ConnectionStatus enum, so we can detect LEVEL_AUTH_FAILED directly
        // (wrong username/password) and push it to Flutter. This is far more
        // reliable than parsing the lowercased status string the plugin forwards.
        registerOpenVpnStateListener(openvpnCh)

        openvpnCh.setMethodCallHandler { call, result ->
                when (call.method) {
                    "validateConfig" -> {
                        val config = call.argument<String>("config") ?: ""
                        try {
                            val parser = ConfigParser()
                            parser.parseConfig(StringReader(config))
                            val profile: VpnProfile = parser.convertProfile()
                            profile.mName = call.argument<String>("name") ?: "4win"
                            val err = profile.checkProfile(applicationContext)
                            // R.string.no_error_found → returns that resource id
                            // when the profile is valid.
                            val okId = resources.getIdentifier(
                                "no_error_found", "string", packageName
                            )
                            val map = HashMap<String, Any?>()
                            if (err == okId || okId == 0 && err == 0) {
                                map["ok"] = true
                            } else {
                                map["ok"] = false
                                map["error"] = try {
                                    getString(err)
                                } catch (e: Exception) {
                                    "profile_error_$err"
                                }
                                map["authType"] = profile.mAuthenticationType
                            }
                            result.success(map)
                        } catch (e: Exception) {
                            val map = HashMap<String, Any?>()
                            map["ok"] = false
                            map["error"] = "parse_error: ${e.message}"
                            result.success(map)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Installed-apps channel (Split Tunneling app picker).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> {
                        try {
                            val pm = applicationContext.packageManager
                            val apps = pm.getInstalledApplications(0)
                            val out = ArrayList<Map<String, String>>()
                            for (ai in apps) {
                                // Only apps that can access the internet are useful
                                // to tunnel/bypass; skip our own package.
                                if (ai.packageName == packageName) continue
                                val label = try {
                                    pm.getApplicationLabel(ai).toString()
                                } catch (_: Throwable) { ai.packageName }
                                out.add(
                                    mapOf(
                                        "package" to ai.packageName,
                                        "name" to label,
                                        "system" to
                                            ((ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0).toString()
                                    )
                                )
                            }
                            result.success(out)
                        } catch (e: Throwable) {
                            result.error("APPS_ERR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Psiphon VPN channel. Keep permission approval and service startup in
        // native code so the Dart provider cannot report a false connection.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PSIPHON_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "refreshServerList" -> {
                    PsiphonServerList.refreshInBackground(applicationContext)
                    result.success(null)
                }
                "getServerList" -> {
                    Thread {
                        try {
                            val bootstrap = assets.open("mix_psiphon_bootstrap.json").bufferedReader().use { org.json.JSONObject(it.readText()) }
                            val snapshot = PsiphonServerList.readCatalog(applicationContext, bootstrap)
                            val servers = snapshot.entries.map { entry ->
                                mapOf("id" to entry.id, "ipAddress" to entry.ipAddress, "region" to entry.region, "port" to entry.port)
                            }
                            runOnUiThread { result.success(mapOf("servers" to servers, "source" to snapshot.source, "updatedAt" to snapshot.updatedAt)) }
                        } catch (t: Throwable) {
                            runOnUiThread { result.success(mapOf("servers" to emptyList<Map<String, Any>>(), "source" to "unavailable", "updatedAt" to null, "error" to (t.message ?: "server list unavailable"))) }
                        }
                    }.apply { isDaemon = true; name = "psiphon-list-read" }.start()
                }
                "refreshServerListNow" -> {
                    PsiphonServerList.refreshNow(applicationContext) { outcome ->
                        val payload = when (outcome) {
                            is PsiphonServerList.RefreshResult.Finished -> mapOf("updated" to outcome.updated, "busy" to false)
                            PsiphonServerList.RefreshResult.AlreadyRunning -> mapOf("updated" to false, "busy" to true)
                        }
                        runOnUiThread { result.success(payload) }
                    }
                }
                "prepare" -> {
                    val intent = VpnService.prepare(applicationContext)
                    if (intent != null) {
                        if (pendingPsiphonPermission != null) {
                            result.error("PSIPHON_PERMISSION_PENDING", "VPN consent is already open", null)
                        } else {
                            pendingPsiphonPermission = result
                            try {
                                startActivityForResult(intent, PSIPHON_REQUEST_CODE)
                            } catch (t: Throwable) {
                                pendingPsiphonPermission = null
                                result.error("PSIPHON_PERMISSION", "Unable to open VPN consent", null)
                            }
                        }
                    } else result.success(true)
                }
                "start" -> {
                    val intent = Intent(this, PsiphonVpnService::class.java).apply {
                        action = PsiphonVpnService.ACTION_CONNECT
                        putExtra(PsiphonVpnService.EXTRA_EGRESS_REGION, call.argument<String>("egressRegion") ?: "")
                        call.argument<String>("targetServerId")?.takeIf { it.isNotBlank() }?.let {
                            putExtra(PsiphonVpnService.EXTRA_TARGET_SERVER_ID, it)
                        }
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                "stop" -> { startService(Intent(this, PsiphonVpnService::class.java).setAction(PsiphonVpnService.ACTION_DISCONNECT)); result.success(true) }
                "reconnect" -> {
                    val intent = Intent(this, PsiphonVpnService::class.java).setAction(PsiphonVpnService.ACTION_RECONNECT)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                // NOTE: PsiphonVpnService runs in the :psiphon process, so its
                // statics are NOT visible here. All state reads go through
                // PsiphonStatusStore (fed by cross-process broadcasts).
                "isRunning" -> result.success(runCatching { PsiphonStatusStore.isRunning() }.getOrDefault(false))
                "isConnected" -> result.success(runCatching { PsiphonStatusStore.isConnected() }.getOrDefault(false))
                // Read-only diagnostic text from the isolated native service;
                // unlike the booleans this preserves the actual startup error.
                "getStatus" -> result.success(mapOf(
                    "statusText" to PsiphonStatusStore.statusText(),
                    "reconnecting" to PsiphonStatusStore.isReconnecting()
                ))
                "isKillSwitchActive" -> result.success(runCatching { PsiphonStatusStore.isKillSwitchActive() }.getOrDefault(false))
                "queryStats" -> {
                    val stats = runCatching { PsiphonStatusStore.queryTrafficStats() }.getOrDefault(longArrayOf(0L, 0L))
                    result.success(mapOf("uplink" to stats[0], "downlink" to stats[1]))
                }
                "getPsiphonLogs" -> {
                    result.success(runCatching { PsiphonStatusStore.getLogs() }.getOrDefault(emptyList<String>()))
                }
                // Available Psiphon exit servers (egress regions) as last
                // reported by the tunnel core: {count: Int, regions: [String]}.
                "getPsiphonServers" -> result.success(
                    mapOf(
                        "count" to runCatching { PsiphonStatusStore.egressRegionCount() }.getOrDefault(0),
                        "regions" to runCatching { PsiphonStatusStore.egressRegions() }.getOrDefault(emptyList<String>())
                    )
                )
                else -> result.notImplemented()
            }
        }

        // DNS Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DNS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestDnsPermission" -> {
                    val intent = VpnService.prepare(applicationContext)
                    if (intent != null) {
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        result.success(false) // Will be granted after user approval
                    } else {
                        result.success(true) // Already granted
                    }
                }
                "connectDns" -> {
                    val primaryDns = call.argument<String>("primaryDns") ?: "8.8.8.8"
                    val secondaryDns = call.argument<String>("secondaryDns") ?: "8.8.4.4"
                    
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_CONNECT
                        putExtra(DnsVpnService.EXTRA_DNS_PRIMARY, primaryDns)
                        putExtra(DnsVpnService.EXTRA_DNS_SECONDARY, secondaryDns)
                    }
                    startService(intent)
                    result.success(true)
                }
                "disconnectDns" -> {
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_DISCONNECT
                    }
                    startService(intent)
                    result.success(true)
                }
                "getDnsStats" -> {
                    // مجموع ترافیک رد و بدل شده دستگاه (دانلود/آپلود) بر حسب بایت
                    val rxBytes = TrafficStats.getTotalRxBytes()
                    val txBytes = TrafficStats.getTotalTxBytes()
                    val stats = HashMap<String, Any>()
                    // در صورت پشتیبانی نشدن، TrafficStats مقدار UNSUPPORTED (-1) برمی‌گرداند
                    stats["rxBytes"] = if (rxBytes == TrafficStats.UNSUPPORTED.toLong()) 0L else rxBytes
                    stats["txBytes"] = if (txBytes == TrafficStats.UNSUPPORTED.toLong()) 0L else txBytes
                    result.success(stats)
                }
                "pingDns" -> {
                    // پینگ واقعی به سرور DNS (به‌صورت native تا حتی موقع فعال بودن
                    // VPN دایرکت DNS هم به‌درستی کار کند). نتیجه: میلی‌ثانیه یا -1
                    val dnsIp = call.argument<String>("dnsIp") ?: "8.8.8.8"
                    Thread {
                        val ping = pingDnsServer(dnsIp)
                        runOnUiThread {
                            result.success(ping)
                        }
                    }.start()
                }
                "scanDns" -> {
                    // Bounded real DNS TXT/EDNS and NXDOMAIN safety probes.
                    // This discovers candidates, never authenticated tunnel readiness.
                    val ips = call.argument<List<String>>("ips") ?: emptyList()
                    val domain = call.argument<String>("domain") ?: "google.com"
                    val parallel = (call.argument<Int>("parallel") ?: 64).coerceIn(1, 64)
                    val port = call.argument<Int>("port") ?: 53
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 2500
                    Thread {
                        try {
                            val json = scanDnsServers(ips, domain, parallel, port, timeoutMs)
                            runOnUiThread { result.success(json) }
                        } catch (_: Exception) {
                            runOnUiThread { result.error("DNS_SCAN", "DNS scan failed. Check the scan configuration.", null) }
                        }
                    }.start()
                }
                "setSstpMtu" -> {
                    // Write the sstp_flutter plugin's MTU value into the default
                    // SharedPreferences (the plugin reads PPP_MTU from there as a String).
                    // This really applies the MTU to the SSTP/PPP tunnel on the next connect.
                    val mtu = call.argument<Int>("mtu") ?: 1400
                    val ok = setSstpMtu(mtu)
                    result.success(ok)
                }
                "detectBestMtu" -> {
                    // REAL MTU auto-detection. Probes the path to the given host using
                    // ping with the Don't-Fragment bit set, binary-searching for the
                    // largest payload that passes without fragmentation, then converts to
                    // the corresponding interface MTU and clamps to [minMtu, maxMtu].
                    // Returns the detected MTU (Int). Falls back to 1400 if probing fails.
                    val host = call.argument<String>("host") ?: "8.8.8.8"
                    val minMtu = call.argument<Int>("minMtu") ?: 1280
                    val maxMtu = call.argument<Int>("maxMtu") ?: 1500
                    Thread {
                        val mtu = detectBestMtu(host, minMtu, maxMtu)
                        // Persist it immediately so the next SSTP connect uses it.
                        setSstpMtu(mtu)
                        runOnUiThread {
                            result.success(mtu)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        
        // Standalone Slow DNS; deliberately not part of the Mix coordinator.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.forwin.vpn/slowdns")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        val permission = VpnService.prepare(applicationContext)
                        if (permission == null) result.success(true)
                        else {
                            startActivityForResult(permission, XRAY_REQUEST_CODE)
                            result.success(false)
                        }
                    }
                    "connect" -> {
                        try {
                            check(VpnService.prepare(applicationContext) == null) { "VPN permission is required." }
                            val config = org.json.JSONObject(call.argument<String>("configJson") ?: error("Missing Slow DNS config."))
                            com.forwin.vpn.slowdns.SlowDnsVpnService.start(applicationContext, config)
                                .whenComplete { state, failure ->
                                    runOnUiThread {
                                        if (failure == null) result.success(state)
                                        else result.error("SLOWDNS_CONNECTION", (failure.cause ?: failure).message ?: "Slow DNS failed.", null)
                                    }
                                }
                        } catch (failure: Throwable) {
                            result.error("SLOWDNS_CONNECTION", failure.message ?: "Invalid Slow DNS config.", null)
                        }
                    }
                    "disconnect" -> {
                        com.forwin.vpn.slowdns.SlowDnsVpnService.stop(applicationContext)
                        result.success(null)
                    }
                    "status" -> result.success(com.forwin.vpn.slowdns.SlowDnsVpnService.status())
                    else -> result.notImplemented()
                }
            }
        // Xray Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, XRAY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestXrayPermission" -> {
                    val intent = VpnService.prepare(applicationContext)
                    if (intent != null) {
                        startActivityForResult(intent, XRAY_REQUEST_CODE)
                        result.success(false) // Will be granted after user approval
                    } else {
                        result.success(true) // Already granted
                    }
                }
                "getMixDiagnostics" -> {
                    result.success(MixCoordinatorService.getMixDiagnostics())
                }
                "connectMixPlan" -> {
                    try {
                        val json = call.argument<String>("planJson") ?: error("Missing Mix plan")
                        MixCoordinatorService.connect(applicationContext, org.json.JSONObject(json))
                            .whenComplete { delay, failure ->
                                runOnUiThread {
                                    if (failure == null) result.success(delay)
                                    else result.error("MIX_CONNECTION", (failure.cause ?: failure).message ?: "Mix connection failed", null)
                                }
                            }
                    } catch (failure: Throwable) {
                        result.error("MIX_CONNECTION", failure.message ?: "Mix plan is invalid", null)
                    }
                }
                "disconnectMixPlan" -> {
                    MixCoordinatorService.disconnect().whenComplete { _, failure ->
                        runOnUiThread {
                            if (failure == null) result.success(true)
                            else result.error("MIX_DISCONNECT", "Mix cleanup failed", null)
                        }
                    }
                }
                "connectXray", "connectMix" -> {
                    val configJson = call.argument<String>("configJson") ?: ""
                    val mixMode = call.method == "connectMix"
                    val proxyMode = !mixMode && (call.argument<Boolean>("proxyMode") ?: false)

                    // Proxy mode uses a PLAIN foreground service (no VpnService),
                    // so Android shows no VPN key icon; VPN mode uses XrayVpnService.
                    val intent = if (proxyMode) {
                        Intent(this, XrayProxyService::class.java).apply {
                            action = XrayProxyService.ACTION_CONNECT
                            putExtra(XrayProxyService.EXTRA_CONFIG_JSON, configJson)
                        }
                    } else {
                        Intent(this, XrayVpnService::class.java).apply {
                            action = XrayVpnService.ACTION_CONNECT
                            putExtra(XrayVpnService.EXTRA_CONFIG_JSON, configJson)
                            putExtra(XrayVpnService.EXTRA_PROXY_MODE, false)
                            putExtra(XrayVpnService.EXTRA_MIX_MODE, mixMode)
                        }
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    if (configJson.contains("__APP_FILES__")) {
                        // Aether scans endpoints and performs a real data-plane
                        // check before emitting ready. Do not let Flutter mark
                        // the tunnel connected merely because the service was
                        // accepted by Android.
                        Thread {
                            val deadline = System.currentTimeMillis() + 45_000L
                            var ready = false
                            while (System.currentTimeMillis() < deadline) {
                                if (runCatching { NativeCore.isReady() }.getOrDefault(false)) {
                                    ready = true
                                    break
                                }
                                Thread.sleep(250L)
                            }
                            runOnUiThread { result.success(ready) }
                        }.start()
                        return@setMethodCallHandler
                    }
                    result.success(true)
                }
                "disconnectXray" -> {
                    // Stop BOTH services so a disconnect works regardless of the
                    // mode the current session was started in.
                    startService(Intent(this, XrayVpnService::class.java).apply {
                        action = XrayVpnService.ACTION_DISCONNECT
                    })
                    startService(Intent(this, XrayProxyService::class.java).apply {
                        action = XrayProxyService.ACTION_DISCONNECT
                    })
                    result.success(true)
                }
                "isXrayRunning" -> {
                    result.success(
                        XrayVpnService.isServiceRunning ||
                            XrayProxyService.isServiceRunning || MixCoordinatorService.isRunning
                    )
                }
                "isXrayReconnecting" -> {
                    // A reconnecting service may intentionally report
                    // !isRunning while teardown hands the next request to the
                    // worker. Do not expose that transient gap as a stop.
                    result.success(MixCoordinatorService.isReconnecting ||
                        XrayVpnService.isReconnecting || XrayProxyService.isReconnecting)
                }
                "queryXrayStats" -> {
                    // Returns cumulative proxy traffic [uplinkBytes, downlinkBytes]
                    // since connect, polled by Flutter to show data usage.
                    val stats = if (MixCoordinatorService.isRunning) {
                        MixCoordinatorService.traffic()
                    } else if (XrayProxyService.isServiceRunning) {
                        XrayProxyService.queryTrafficStats()
                    } else {
                        XrayVpnService.queryTrafficStats()
                    }
                    val map = HashMap<String, Any>()
                    map["uplink"] = stats[0]
                    map["downlink"] = stats[1]
                    result.success(map)
                }
                "getXrayVersion" -> {
                    result.success(
                        runCatching { libv2ray.Libv2ray.checkVersionX() }.getOrDefault("unknown")
                    )
                }
                "measureDelay" -> {
                    // REAL delay test (like v2rayNG's "real delay"): builds a
                    // proxy-only config from the share link and times an HTTP
                    // request to an international URL (Google generate_204)
                    // through the proxy. Returns ms, or -1 on failure.
                    val configJson = call.argument<String>("configJson") ?: ""
                    val url = call.argument<String>("url")
                        ?: "https://www.google.com/generate_204"
                    if (configJson.contains("__APP_FILES__")) {
                        // WARP is already running in Aether. Use a fresh
                        // request through the active VPN instead of returning
                        // the connect-time RTT stored by the native core.
                        Thread {
                            val delay = measureFreshWarpDelay()
                            runOnUiThread { result.success(delay) }
                        }.start()
                        return@setMethodCallHandler
                    }
                    Thread {
                        val delay = measureXrayDelay(configJson, url)
                        runOnUiThread { result.success(delay) }
                    }.start()
                }
                "measureWarpDelay" -> {
                    // Perform a fresh HTTP request through the active Android
                    // VPN. NativeCore.lastRttMs() is only the connect-time
                    // validation value and becomes stale after the first tap.
                    Thread {
                        val delay = measureFreshWarpDelay()
                        runOnUiThread { result.success(delay) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        // Import Channel — lets Flutter pull an .ovpn file that the user opened
        // or shared into the app (Telegram, file managers, email, ...).
        val importCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, IMPORT_CHANNEL)
        importChannel = importCh
        importCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingOvpnImport" -> {
                    // Parse the launch intent on first request (cold start).
                    if (pendingOvpnContent == null) {
                        handleIncomingIntent(intent)
                    }
                    val content = pendingOvpnContent
                    if (content != null) {
                        val map = HashMap<String, Any>()
                        map["name"] = pendingOvpnName ?: "Imported"
                        map["content"] = content
                        // Consume it so it isn't imported twice.
                        pendingOvpnName = null
                        pendingOvpnContent = null
                        result.success(map)
                    } else {
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun measureFreshWarpDelay(): Int {
        if (!XrayVpnService.isServiceRunning ||
            !runCatching { NativeCore.isReady() }.getOrDefault(false)) return -1
        var connection: HttpURLConnection? = null
        return try {
            val start = System.nanoTime()
            connection = (URL("https://www.gstatic.com/generate_204").openConnection()
                as HttpURLConnection).apply {
                connectTimeout = 6000
                readTimeout = 6000
                requestMethod = "GET"
                useCaches = false
                setRequestProperty("Cache-Control", "no-cache, no-store")
                setRequestProperty("Pragma", "no-cache")
            }
            val code = connection.responseCode
            val elapsed = ((System.nanoTime() - start) / 1_000_000L).toInt()
            if (code in 200..399) elapsed else -1
        } catch (_: Exception) {
            -1
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * Attaches a [VpnStatus.StateListener] to the ics-openvpn core (bundled in
     * the openvpn_library AAR). Every state transition delivers the real
     * [ConnectionStatus] level, so we can reliably detect an authentication
     * failure (LEVEL_AUTH_FAILED — wrong username/password) and forward it to
     * Flutter via the OpenVPN MethodChannel ("onOpenVpnState"). Flutter uses
     * this as the authoritative auth-failed signal.
     */
    private fun registerOpenVpnStateListener(channel: MethodChannel) {
        // Remove any previously registered listener (hot restart / re-attach).
        openvpnStateListener?.let {
            try { VpnStatus.removeStateListener(it) } catch (_: Exception) {}
        }
        val listener = object : VpnStatus.StateListener {
            override fun updateState(
                state: String?,
                logmessage: String?,
                localizedResId: Int,
                level: ConnectionStatus?,
                intent: Intent?
            ) {
                // addStateListener immediately replays the core's current
                // level, including when the Activity is newly recreated.
                openvpnConnected = level == ConnectionStatus.LEVEL_CONNECTED
                val stateName = state ?: ""
                val levelName = level?.name ?: ""
                val isAuthFailed = level == ConnectionStatus.LEVEL_AUTH_FAILED ||
                    stateName.contains("AUTH_FAILED", ignoreCase = true) ||
                    levelName.contains("AUTH_FAILED", ignoreCase = true)
                runOnUiThread {
                    try {
                        val map = HashMap<String, Any?>()
                        map["state"] = stateName
                        map["level"] = levelName
                        map["message"] = logmessage ?: ""
                        map["authFailed"] = isAuthFailed
                        channel.invokeMethod("onOpenVpnState", map)
                    } catch (_: Exception) {}
                }
            }

            override fun setConnectedVPN(uuid: String?) {}
        }
        openvpnStateListener = listener
        try {
            VpnStatus.addStateListener(listener)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "addStateListener failed: ${e.message}")
        }

        // ── Redundant auth-failure detection via the core LOG stream ──────────
        // The core writes an explicit log line when the server rejects the
        // credentials (typically containing "AUTH_FAILED" or "auth-failure").
        // Watching the log guarantees we catch a wrong username/password even in
        // the rare case the state transition is coalesced/missed.
        openvpnLogListener?.let {
            try { VpnStatus.removeLogListener(it) } catch (_: Exception) {}
        }
        val logListener = object : VpnStatus.LogListener {
            override fun newLog(item: LogItem?) {
                if (item == null) return
                val text = try {
                    item.getString(applicationContext) ?: item.toString()
                } catch (_: Exception) {
                    item.toString()
                }
                val lower = text.lowercase()
                // ONLY the explicit server-rejected-credentials markers. The
                // loose "(auth && failed)" match was too broad and flagged
                // healthy connections (e.g. TLS renegotiation notes), so a valid
                // config wrongly reported "authentication error". Match exactly
                // what the OpenVPN core prints when the SERVER rejects creds.
                val isAuthFailed = lower.contains("auth_failed") ||
                    lower.contains("auth-failure") ||
                    lower.contains("password verification failed")
                if (isAuthFailed) {
                    runOnUiThread {
                        try {
                            val map = HashMap<String, Any?>()
                            map["state"] = "AUTH_FAILED"
                            map["level"] = "LEVEL_AUTH_FAILED"
                            map["message"] = text
                            map["authFailed"] = true
                            channel.invokeMethod("onOpenVpnState", map)
                        } catch (_: Exception) {}
                    }
                }
            }
        }
        openvpnLogListener = logListener
        try {
            VpnStatus.addLogListener(logListener)
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "addLogListener failed: ${e.message}")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // App already running and a new .ovpn was opened/shared.
        setIntent(intent)
        if (handleIncomingIntent(intent)) {
            // Tell Flutter to come pull it.
            runOnUiThread {
                importChannel?.invokeMethod("onOvpnImportAvailable", null)
            }
        }
    }

    /**
     * Inspects an incoming VIEW/SEND intent for an .ovpn file. If one is found,
     * its content is read and cached in [pendingOvpnContent]/[pendingOvpnName].
     * Returns true if an .ovpn payload was captured.
     */
    private fun handleIncomingIntent(incoming: Intent?): Boolean {
        if (incoming == null) return false

        // Preferred path: ImportActivity already read the file (where it held
        // the caller's Uri permission) and handed us the config as plain-text
        // extras. This avoids forwarding a content:// Uri whose grant would not
        // survive the hop and used to crash us with a SecurityException.
        val forwardedContent = incoming.getStringExtra(ImportActivity.EXTRA_OVPN_CONTENT)
        if (!forwardedContent.isNullOrBlank()) {
            pendingOvpnName =
                incoming.getStringExtra(ImportActivity.EXTRA_OVPN_NAME) ?: "Imported"
            pendingOvpnContent = forwardedContent
            return true
        }

        val action = incoming.action
        val rawUri: Uri? = when (action) {
            Intent.ACTION_VIEW -> incoming.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    incoming.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            }
            else -> null
        }
        val uri: Uri = rawUri ?: return false

        return try {
            val content = readUriText(uri) ?: return false
            // Sanity check: must look like an OpenVPN config.
            val looksLikeOvpn = content.contains("remote ", ignoreCase = true) ||
                content.contains("<ca>", ignoreCase = true) ||
                content.contains("client", ignoreCase = true) ||
                content.contains("dev tun", ignoreCase = true)
            if (!looksLikeOvpn) return false
            pendingOvpnName = guessName(uri)
            pendingOvpnContent = content
            true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to read .ovpn: ${e.message}", e)
            false
        }
    }

    // Ensures the Xray core env is initialized exactly once for delay tests.
    @Volatile private var xrayEnvReady = false

    /**
     * Measures real proxy delay for [configJson] against [url] using the Xray
     * core's measureOutboundDelay (same mechanism v2rayNG uses for "real
     * delay"). Returns delay in ms, or -1 on failure / unreachable.
     */
    private fun measureXrayDelay(configJson: String, url: String): Long {
        if (configJson.isBlank()) return -1L
        return try {
            if (!xrayEnvReady) {
                go.Seq.setContext(applicationContext)
                libv2ray.Libv2ray.initCoreEnv(filesDir.absolutePath, "")
                xrayEnvReady = true
            }
            libv2ray.Libv2ray.measureOutboundDelay(configJson, url)
        } catch (t: Throwable) {
            android.util.Log.e("MainActivity", "measureDelay failed: ${t.message}")
            -1L
        }
    }

    /** Reads the text content behind a content:// or file:// URI. */
    private fun readUriText(uri: Uri): String? {
        return when (uri.scheme) {
            "content" -> contentResolver.openInputStream(uri)?.use {
                it.readBytes().toString(Charsets.UTF_8)
            }
            "file" -> uri.path?.let { java.io.File(it).readText(Charsets.UTF_8) }
            else -> null
        }
    }

    /** Best-effort display name (without extension) for an imported file. */
    private fun guessName(uri: Uri): String {
        var name = "Imported"
        try {
            if (uri.scheme == "content") {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && cursor.moveToFirst()) {
                        name = cursor.getString(idx) ?: name
                    }
                }
            } else {
                name = uri.lastPathSegment ?: name
            }
        } catch (_: Exception) { }
        return name.substringBeforeLast('.').ifBlank { "Imported" }
    }

    /**
     * پینگ واقعی به سرور DNS و برگرداندن تاخیر بر حسب میلی‌ثانیه.
     * دقیقاً مثل دستور `ping` در ترموکس عمل می‌کند.
     * روش 1: ICMP ping با InetAddress.isReachable (مثل ترموکس ping).
     * روش 2: TCP connect روی پورت‌های رایج (53، 443، 80).
     * روش 3: UDP DNS query روی پورت 53.
     * در صورت ناموفق بودن همه، -1 برمی‌گرداند.
     */
    private fun pingDnsServer(dnsIp: String): Int {
        // روش اصلی: پینگ از طریق سرویس VPN با سوکت protect-شده.
        // این تنها روشی است که موقع فعال بودن تونل دایرکت دی‌ان‌اس قطعاً کار می‌کند،
        // چون سوکت پینگ از تونل خارج می‌شود و مستقیم به DNS server می‌رسد.
        val viaService = DnsVpnService.pingViaService(dnsIp)
        if (viaService >= 0) return viaService
        // viaService == -2 یعنی سرویس فعال نیست → ادامه با روش‌های مستقیم

        // روش 1: ICMP echo (دقیقاً مثل دستور ping ترموکس)
        val icmp = pingIcmp(dnsIp)
        if (icmp >= 0) return icmp

        // روش 2: TCP connect روی پورت‌های رایج
        for (port in intArrayOf(53, 443, 80)) {
            val tcp = pingTcp(dnsIp, port)
            if (tcp >= 0) return tcp
        }

        // روش 3: UDP DNS query
        return pingDnsUdp(dnsIp)
    }

    /**
     * Auto-MTU for SSTP. The sstp_flutter plugin reads its PPP MTU from the
     * default SharedPreferences under the key "PPP_MTU" (stored as a String,
     * see preference/accessor/int.kt). We clamp to the plugin's valid range
     * (68..2000) and write it so the next connect uses the new MTU.
     */
    private fun setSstpMtu(mtu: Int): Boolean {
        return try {
            val clamped = mtu.coerceIn(68, 2000)
            // PreferenceManager.getDefaultSharedPreferences(context) (used by the
            // sstp_flutter plugin) is backed by the SharedPreferences file named
            // "<packageName>_preferences". We open the exact same file here so the
            // PPP_MTU we write is really read by the plugin on connect — without
            // needing the androidx.preference dependency in the app module.
            val prefs = applicationContext.getSharedPreferences(
                "${applicationContext.packageName}_preferences",
                Context.MODE_PRIVATE
            )
            prefs.edit().putString("PPP_MTU", clamped.toString()).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * REAL MTU path discovery to [host].
     *
     * Uses `ping` with the Don't-Fragment (DF) bit set (`-M do`) and a controlled
     * payload size (`-s`). When a payload is too large to traverse the path
     * without fragmentation, the router replies "Frag needed" / "Message too long"
     * and ping fails. We binary-search for the largest payload that succeeds.
     *
     * payload(success) -> path MTU = payload + 28 (20 IPv4 header + 8 ICMP header).
     * We then subtract a conservative SSTP/PPP/TLS encapsulation overhead so the
     * value we write is a safe inner (PPP) MTU, and clamp into [minMtu, maxMtu].
     *
     * Returns the detected MTU, or 1400 as a safe fallback if probing is not
     * possible (e.g. ICMP blocked).
     */
    private fun detectBestMtu(host: String, minMtu: Int, maxMtu: Int): Int {
        // SSTP runs PPP over TLS over TCP. Encapsulation overhead is roughly:
        // IP(20) + TCP(20) + TLS(~29) + SSTP(~4) + PPP(~8) ≈ 80+ bytes. We keep a
        // conservative margin so the inner MTU never causes fragmentation.
        val encapOverhead = 80
        // ICMP probe needs payload = mtu - 28 (IP + ICMP headers).
        val maxPayload = maxMtu - 28
        val minPayload = minMtu - 28

        var bestPayload = -1
        var lo = minPayload
        var hi = maxPayload

        // First confirm the minimum even works; if not, ICMP is likely blocked.
        if (!pingWithDf(host, minPayload)) {
            // Try once more with a tiny payload to distinguish "ICMP blocked"
            // from "path too small". If even 64 bytes fails, fall back.
            if (!pingWithDf(host, 64)) {
                return 1400.coerceIn(minMtu, maxMtu)
            }
            lo = 64
        } else {
            bestPayload = minPayload
        }

        // Binary search for the largest passing payload.
        var iterations = 0
        while (lo <= hi && iterations < 16) {
            iterations++
            val mid = (lo + hi) / 2
            if (pingWithDf(host, mid)) {
                bestPayload = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        if (bestPayload < 0) return 1400.coerceIn(minMtu, maxMtu)

        val pathMtu = bestPayload + 28
        val innerMtu = pathMtu - encapOverhead
        return innerMtu.coerceIn(minMtu, maxMtu)
    }

    /**
     * Sends a single ICMP echo to [host] with payload [payloadSize] bytes and the
     * Don't-Fragment bit set. Returns true if it succeeds (path can carry this
     * size without fragmentation), false otherwise.
     */
    private fun pingWithDf(host: String, payloadSize: Int): Boolean {
        return try {
            // -c 1 : one packet, -W 2 : 2s timeout, -M do : set DF, -s : payload size
            val process = Runtime.getRuntime().exec(
                arrayOf("/system/bin/ping", "-c", "1", "-W", "2", "-M", "do", "-s", payloadSize.toString(), host)
            )
            val finished = process.waitFor()
            // ping exit code 0 == reply received (DF size passed).
            finished == 0
        } catch (e: Exception) {
            false
        }
    }

    /** ICMP ping - مثل دستور ping در ترموکس */
    private fun pingIcmp(host: String): Int {
        return try {
            val address = InetAddress.getByName(host)
            val start = System.currentTimeMillis()
            val reachable = address.isReachable(2000)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            if (reachable && elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        }
    }

    private fun pingDnsUdp(dnsIp: String): Int {
        var socket: DatagramSocket? = null
        return try {
            val address = InetAddress.getByName(dnsIp)
            val query = buildDnsQuery("google.com")

            socket = DatagramSocket()
            socket.soTimeout = 1500

            val sendPacket = DatagramPacket(query, query.size, address, 53)
            val responseBuffer = ByteArray(512)
            val responsePacket = DatagramPacket(responseBuffer, responseBuffer.size)

            val start = System.currentTimeMillis()
            socket.send(sendPacket)
            socket.receive(responsePacket) // در صورت تایم‌اوت استثنا می‌دهد
            val elapsed = (System.currentTimeMillis() - start).toInt()

            if (elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        } finally {
            socket?.close()
        }
    }

    private fun pingTcp(host: String, port: Int): Int {
        var socket: Socket? = null
        return try {
            socket = Socket()
            val start = System.currentTimeMillis()
            socket.connect(InetSocketAddress(host, port), 1500)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            if (elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        } finally {
            try { socket?.close() } catch (e: Exception) {}
        }
    }

    /** Independent TXT/EDNS/NXDOMAIN capability scanner, not tunnel readiness. */
    private fun scanDnsServers(ips: List<String>, domain: String, parallel: Int = 64, port: Int = 53, timeoutMs: Int = 2500): String =
        com.forwin.vpn.dnsscan.DnsResolverScanner.scan(ips, domain, parallel, port, timeoutMs)

    /** ساخت یک بسته‌ی استاندارد DNS query (نوع A) برای دامنه‌ی داده‌شده */
    private fun buildDnsQuery(domain: String): ByteArray {
        val out = ArrayList<Byte>()
        fun b(v: Int) = out.add(v.toByte())
        // Transaction ID
        b(0x12); b(0x34)
        // Flags: standard query, recursion desired
        b(0x01); b(0x00)
        // QDCOUNT = 1
        b(0x00); b(0x01)
        // ANCOUNT / NSCOUNT / ARCOUNT = 0
        b(0x00); b(0x00)
        b(0x00); b(0x00)
        b(0x00); b(0x00)
        // QNAME
        for (part in domain.split(".")) {
            b(part.length)
            for (c in part.toByteArray(Charsets.US_ASCII)) {
                out.add(c)
            }
        }
        b(0x00) // پایان نام دامنه
        // QTYPE = A
        b(0x00); b(0x01)
        // QCLASS = IN
        b(0x00); b(0x01)
        return out.toByteArray()
    }
    private fun nativeVpnState(protocol: String): Map<String, Any> {
        var running = false
        var reconnecting = false
        var connected = false
        var stats: LongArray? = null
        var metricsOwner = protocol
        var standaloneMetrics: Map<String, Any>? = null
        when (protocol) {
            "xray", "proxy", "warp" -> {
                val xr = XrayVpnService.isServiceRunning
                val pr = XrayProxyService.isServiceRunning
                val xrr = XrayVpnService.isReconnecting
                val prr = XrayProxyService.isReconnecting
                running = xr || pr
                reconnecting = xrr || prr
                connected = (xr && !xrr) || (pr && !prr)
                metricsOwner = if (pr || prr) "proxy" else "xray"
                stats = if (pr) XrayProxyService.queryTrafficStats() else XrayVpnService.queryTrafficStats()
            }
            "mix" -> {
                val mr = MixCoordinatorService.isRunning
                val xr = XrayVpnService.isMixModeRunning
                val mrr = MixCoordinatorService.isReconnecting
                val xrr = XrayVpnService.isMixModeReconnecting
                running = mr || xr
                reconnecting = mrr || xrr
                connected = (mr && !mrr) || (xr && !xrr)
                // The coordinator owns the system TUN; Xray owns the Xray-mix TUN.
                metricsOwner = if (mr || mrr) "mix" else "xray"
                stats = if (mr) MixCoordinatorService.traffic() else XrayVpnService.queryTrafficStats()
            }
            "direct_dns" -> {
                running = DnsVpnService.isServiceRunning
                reconnecting = DnsVpnService.isReconnecting
                connected = running && !reconnecting
                // This DNS-only service has no VPN-only byte accounting.
            }
            "slowdns" -> {
                val state = SlowDnsVpnService.status()
                running = SlowDnsVpnService.isRunning()
                reconnecting = state["reconnecting"] == true || SlowDnsVpnService.isReconnecting()
                connected = state["connected"] == true
                stats = SlowDnsVpnService.traffic()
            }
            "psiphon" -> {
                running = PsiphonStatusStore.isRunning()
                reconnecting = PsiphonStatusStore.isReconnecting()
                connected = PsiphonStatusStore.isConnected()
                stats = PsiphonStatusStore.queryTrafficStats()
            }
            "openvpn" -> {
                running = VpnStatus.isVPNActive()
                reconnecting = OpenVpnNotificationActions.isReconnecting()
                connected = running && openvpnConnected && !reconnecting
                stats = OpenVpnNotificationActions.queryTrafficStats()
            }
            "sstp" -> {
                val state = SstpVpnService.state(applicationContext)
                running = state["running"] == true
                reconnecting = state["reconnecting"] == true
                connected = state["connected"] == true
                standaloneMetrics = state
            }
        }
        stats?.let { NativeSessionMetrics.update(metricsOwner, it[0], it[1]) }
        val snap = NativeSessionMetrics.snapshot(metricsOwner)
        val out = hashMapOf<String, Any>(
            "running" to running, "reconnecting" to reconnecting, "connected" to connected
        )
        snap?.let {
            out["sessionId"] = it.sessionId
            out["elapsedMillis"] = it.elapsedMillis
            it.uplink?.let { up -> out["uplink"] = up }
            it.downlink?.let { down -> out["downlink"] = down }
        }
        // The vendored standalone SSTP service owns its own session metadata.
        standaloneMetrics?.let { state ->
            for (key in listOf("sessionId", "elapsedMillis", "uplink", "downlink")) {
                state[key]?.let { out[key] = it }
            }
        }
        return out
    }

}
