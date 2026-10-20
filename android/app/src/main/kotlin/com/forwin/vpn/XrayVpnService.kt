package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import androidx.core.app.NotificationCompat
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Xray VPN Service backed by the REAL Xray core (AndroidLibXrayLite / libv2ray.aar),
 * the exact same core used by v2rayNG.
 *
 * The core's [CoreController.startLoop] receives the TUN file descriptor directly and
 * runs its built-in tun2socks, so no external tunnel binary is needed. We only need to:
 *   1. Build the VPN TUN interface (ParcelFileDescriptor).
 *   2. Call [Libv2ray.initCoreEnv] (asset path for geoip/geosite).
 *   3. Create a [CoreController] and call startLoop(configJson, tunFd).
 *   4. Tear down via stopLoop() + close the TUN on disconnect.
 */
class XrayVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var coreController: CoreController? = null
    private var configJson: String? = null
    private var mixMode = false
    @Volatile private var isRunning = false
    @Volatile private var aetherActive = false
    @Volatile private var aetherGeneration: Long? = null
    private val lifecycleLock = Any()
    @Volatile private var generation = System.nanoTime()
    private var reconnectInProgress = false
    private var activeConnectIntent: Intent? = null
    private val commandExecutor: ExecutorService = Executors.newSingleThreadExecutor { r -> Thread(r, "XrayVpnLifecycle") }
    @Volatile private var engineThread: Thread? = null

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.XRAY_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.XRAY_DISCONNECT"
        const val ACTION_RECONNECT = "com.forwin.vpn.XRAY_RECONNECT"
        private const val EXTRA_GENERATION = "connection_generation"
        const val EXTRA_CONFIG_JSON = "config_json"
        const val EXTRA_PROXY_MODE = "proxy_mode"
        const val EXTRA_MIX_MODE = "mix_mode"

        private const val TAG = "XrayVpnService"
        private const val NOTIFICATION_ID = 2
        private const val CHANNEL_ID = "XrayVpnChannel"
        private const val VPN_MTU = 1500
        private const val PRIVATE_VLAN4_CLIENT = "26.26.26.1"
        private const val PRIVATE_VLAN6_CLIENT = "da26:2626::1"

        @Volatile
        var isServiceRunning = false
            private set

        @Volatile
        var isReconnecting = false
            private set

        @Volatile
        var isMixModeRunning = false
            private set

        @Volatile
        var isMixModeReconnecting = false
            private set

        @Volatile
        private var activeController: CoreController? = null

        @Volatile private var totalUplink = 0L
        @Volatile private var totalDownlink = 0L

        fun queryTrafficStats(): LongArray {
            val controller = activeController ?: return longArrayOf(totalUplink, totalDownlink)
            try {
                val up = controller.queryStats("proxy", "uplink")
                val down = controller.queryStats("proxy", "downlink")
                if (up > 0) totalUplink += up
                if (down > 0) totalDownlink += down
            } catch (_: Throwable) { }
            return longArrayOf(totalUplink, totalDownlink)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
                val token: Long
                synchronized(lifecycleLock) { generation++; token=generation; reconnectInProgress=false; isReconnecting=false; activeConnectIntent=Intent(intent); configJson=intent.getStringExtra(EXTRA_CONFIG_JSON); mixMode=intent.getBooleanExtra(EXTRA_MIX_MODE,false); isMixModeReconnecting=mixMode }
                commandExecutor.execute { if (teardown(false) && isCurrent(token)) { runCatching { showNotification(token) }; launch(token) } }
            }
            ACTION_DISCONNECT -> if (isCurrentToken(intent)) {
                runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
                VpnStateBroadcast.notifyDisconnected(this, when { mixMode -> "mix"; configJson?.contains("__APP_FILES__") == true -> "warp"; else -> "xray" })
                synchronized(lifecycleLock) { invalidateConnectionLocked() }
                commandExecutor.execute { teardown(true) }
            }
            ACTION_RECONNECT -> reconnect(intent)
        }
        return START_STICKY
    }
    private fun isCurrent(token: Long) = token == generation
    private fun launch(token: Long) {
        if (!isCurrent(token)) return
        if (configJson?.contains("__APP_FILES__") != true) {
            startXray(token)
            return
        }
        val thread = Thread { startXray(token) }
        engineThread = thread
        thread.name = "XrayVpnEngine-$token"
        thread.start()
    }

    private fun finishReconnect(token: Long) {
        synchronized(lifecycleLock) {
            if (generation == token) {
                reconnectInProgress = false
                isReconnecting = false
                isMixModeReconnecting = false
            }
        }
    }

    private fun startXray(expectedGeneration: Long = generation) {
        if (expectedGeneration != generation) return
        if (isRunning) {
            android.util.Log.d(TAG, "Xray already running")
            return
        }
        val config = configJson
        if (config.isNullOrBlank()) {
            android.util.Log.e(TAG, "No config provided")
            finishReconnect(expectedGeneration)
            commandExecutor.execute { if (isCurrent(expectedGeneration)) teardown(false) }
            return
        }

        com.example.sstp_flutter.VpnConnectionObserver.notifyStarting(this)
        try {
            if (config.contains("__APP_FILES__")) {
                startAether(config, expectedGeneration)
                return
            }
            val builder = Builder()
                .setSession(if (mixMode) "4win VPN - Mix" else "4win VPN - Xray")
                .setMtu(VPN_MTU)
                .addAddress(PRIVATE_VLAN4_CLIENT, 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("8.8.8.8")
                .addDnsServer("1.1.1.1")

            try {
                builder.addAddress(PRIVATE_VLAN6_CLIENT, 126)
                builder.addRoute("::", 0)
            } catch (_: Throwable) { }

            // Android VpnService.Builder does not allow mixing allowed- and
            // disallowed-application lists. In split-tunnel INCLUDE mode the
            // helper owns the allow-list, so do not pre-add our package to the
            // disallowed list. In OFF/EXCLUDE mode our app stays outside the
            // tunnel to prevent loops.
            val splitMode = SplitTunnel.mode(applicationContext)
            if (mixMode || splitMode != "include") {
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (_: Throwable) { }
            }

            // Mix captures all other apps; never rewrite standalone preferences.
            if (!mixMode) SplitTunnel.apply(applicationContext, builder, packageName)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            val tun = builder.establish()
            vpnInterface = tun
            if (tun == null) {
                android.util.Log.e(TAG, "Failed to establish VPN interface")
                commandExecutor.execute { if (isCurrent(expectedGeneration)) teardown(false) }
                return
            }
            val tunFd = tun.fd

            Seq.setContext(applicationContext)
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")
            android.util.Log.d(TAG, "initCoreEnv done, "
                + "version=${runCatching { Libv2ray.checkVersionX() }.getOrNull()}")

            val controller = Libv2ray.newCoreController(XrayCallback(expectedGeneration))
            coreController = controller

            android.util.Log.d(TAG, "Starting Xray core (tunFd=$tunFd, "
                + "version=${runCatching { Libv2ray.checkVersionX() }.getOrNull()})")
            controller.startLoop(config, tunFd)

            if (!isCurrent(expectedGeneration)) {
                controller.stopLoop()
                return
            }
            isRunning = true
            runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, true) }
            isServiceRunning = true
            isMixModeRunning = mixMode
            activeController = controller
            totalUplink = 0L
            totalDownlink = 0L
            finishReconnect(expectedGeneration)

            android.util.Log.d(TAG, "Xray core started successfully")
        } catch (t: Throwable) {
            android.util.Log.e(TAG, "Failed to start Xray: ${t.message}", t)
            finishReconnect(expectedGeneration)
            commandExecutor.execute { if (isCurrent(expectedGeneration)) teardown(false) }
        }
    }

    /** Starts WARP through Aether, not Xray's WireGuard outbound. Aether only
     * emits ready after endpoint handshake plus a real HTTP probe. */
    private fun startAether(rawConfig: String, token: Long) {
        if (isRunning || aetherActive) return
        var tun: ParcelFileDescriptor? = null
        try {
            val config = rawConfig.replace("__APP_FILES__", filesDir.absolutePath)
            aetherGeneration = token
            aetherActive = true
            NativeCore.attach(this)
            val addresses = NativeCore.prepare(config)
            val builder = Builder()
                .setSession("4win VPN - WARP")
                .setMtu(1280)
                .addAddress(addresses.ipv4.substringBefore('/'), 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
            if (addresses.ipv6.isNotBlank()) {
                runCatching {
                    builder.addAddress(addresses.ipv6.substringBefore('/'), 128)
                    builder.addRoute("::", 0)
                }
            }
            if (SplitTunnel.mode(applicationContext) != "include") {
                runCatching { builder.addDisallowedApplication(packageName) }
            }
            SplitTunnel.apply(applicationContext, builder, packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
            tun = builder.establish() ?: error("Failed to establish WARP VPN interface")
            check(isCurrent(token)) { "WARP startup cancelled" }
            vpnInterface = tun
            aetherActive = true
            isRunning = true
            isServiceRunning = true
            totalUplink = 0L
            totalDownlink = 0L
            check(isCurrent(token)) { "WARP startup cancelled" }
            val result = NativeCore.start(config, tun.fd)
            if (result != 0) error(NativeCore.lastError().ifBlank { "Aether exited with code $result" })
            teardown(false)
        } catch (t: Throwable) {
            android.util.Log.e(TAG, "Aether WARP failed: ${t.message}", t)
            runCatching { tun?.close() }
            runCatching { NativeCore.stop() }
            runCatching { NativeCore.detach() }
            aetherActive = false
            teardown(false)
        } finally {
            finishReconnect(token)
        }
    }

    /** Called by the Aether JNI callback; status=connected is emitted only after
     * its data-plane validation, unlike the old Xray handshake-only path. */
    fun onEvent(json: String) {
        runCatching {
            val event = JSONObject(json)
            if (event.optString("type") == "status" && event.optString("status") == "connected") {
                val token = aetherGeneration
                if (token != null && isCurrent(token) && aetherActive) {
                    runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, true) }
                    finishReconnect(token)
                }
            }
            if (event.optString("type") == "traffic") {
                totalUplink = event.optLong("tx")
                totalDownlink = event.optLong("rx")
            }
            android.util.Log.d(TAG, "Aether event: $json")
        }
    }

    fun protectSocket(fd: Int): Boolean = protect(fd)

    private fun reconnect(intent: Intent?) {
        if (!isCurrentToken(intent)) return
        runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
        val token: Long
        synchronized(lifecycleLock) {
            if (reconnectInProgress || activeConnectIntent == null) return
            reconnectInProgress = true
            isReconnecting = true
            isMixModeReconnecting = mixMode
            generation++
            token = generation
        }
        runCatching { showNotification(token) }
        commandExecutor.execute {
            if (teardown(false) && isCurrent(token)) {
                runCatching { showNotification(token) }
                launch(token)
            } else finishReconnect(token)
        }
    }

    private fun isCurrentToken(intent: Intent?): Boolean =
        intent == null || !intent.hasExtra(EXTRA_GENERATION) ||
            intent.getLongExtra(EXTRA_GENERATION, Long.MIN_VALUE) == generation

    private fun invalidateConnectionLocked() {
        generation++
        reconnectInProgress = false
        isReconnecting = false
        isMixModeReconnecting = false
        activeConnectIntent = null
    }

    private fun teardown(stopService: Boolean): Boolean {
        runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
        isRunning=false; isServiceRunning=false; isMixModeRunning=false; isMixModeReconnecting=false; activeController=null; totalUplink=0L; totalDownlink=0L
        if (aetherActive) runCatching { NativeCore.stop() }
        runCatching { coreController?.stopLoop() }; coreController=null
        val old=engineThread
        if (old != null && old !== Thread.currentThread()) {
            val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
            while (old.isAlive && android.os.SystemClock.elapsedRealtime() < deadline) {
                runCatching { NativeCore.stop() }
                runCatching { old.join(100) }
            }
            if (old.isAlive) {
                finishReconnect(generation)
                return false
            }
        }
        engineThread=null
        if (aetherActive) runCatching { NativeCore.detach() }
        aetherActive=false
        aetherGeneration=null
        runCatching { vpnInterface?.close() }; vpnInterface=null
        if (stopService) { runCatching { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true) }; stopSelf() }
        return true
    }
    private fun requestShutdown(token: Long) { if (isCurrent(token)) commandExecutor.execute { if (isCurrent(token)) teardown(false) } }

    private inner class XrayCallback(private val token: Long) : CoreCallbackHandler {
        override fun startup(): Long = 0L
        override fun shutdown(): Long {
            try {
                requestShutdown(token)
            } catch (_: Exception) { }
            return 0L
        }
        override fun onEmitStatus(level: Long, msg: String?): Long {
            android.util.Log.d(TAG, "core status [$level]: $msg")
            return 0L
        }
    }

    private fun showNotification(token: Long) {
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        )
        val disconnectIntent = Intent(this, XrayVpnService::class.java).apply {
            action = ACTION_DISCONNECT
                data = android.net.Uri.parse("forwin-xray-vpn://disconnect/$token")
            putExtra(EXTRA_GENERATION, token)
        }
        val reconnectIntent = Intent(this, XrayVpnService::class.java).apply {
            action = ACTION_RECONNECT
                data = android.net.Uri.parse("forwin-xray-vpn://reconnect/$token")
            putExtra(EXTRA_GENERATION, token)
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this, token.toInt(), disconnectIntent, PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val reconnectPendingIntent = PendingIntent.getService(
            this, token.toInt() + 1, reconnectIntent, PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val isWarp = configJson?.contains("__APP_FILES__") == true
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(VpnNotificationLabels.xrayTitle(mixMode, isWarp))
            .setContentText("Tap to open • Reconnect or disconnect")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_popup_sync, "Reconnect", reconnectPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnectPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Xray VPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Xray VPN connection status"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    override fun onRevoke() {
        synchronized(lifecycleLock) { invalidateConnectionLocked() }
        commandExecutor.execute { teardown(true) }
        super.onRevoke()
    }

    override fun onDestroy() {
        synchronized(lifecycleLock) { invalidateConnectionLocked() }
        commandExecutor.execute { teardown(true); commandExecutor.shutdown() }
        super.onDestroy()
    }
}
