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

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.XRAY_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.XRAY_DISCONNECT"
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
                configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                mixMode = intent.getBooleanExtra(EXTRA_MIX_MODE, false)
                try {
                    showNotification()
                } catch (t: Throwable) {
                    android.util.Log.e(TAG, "showNotification failed: ${t.message}", t)
                }
                Thread { startXray() }.start()
            }
            ACTION_DISCONNECT -> stopXray()
        }
        return START_STICKY
    }

    private fun startXray() {
        if (isRunning) {
            android.util.Log.d(TAG, "Xray already running")
            return
        }
        val config = configJson
        if (config.isNullOrBlank()) {
            android.util.Log.e(TAG, "No config provided")
            stopXray()
            return
        }

        try {
            if (config.contains("__APP_FILES__")) {
                startAether(config)
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
                stopXray()
                return
            }
            val tunFd = tun.fd

            Seq.setContext(applicationContext)
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")
            android.util.Log.d(TAG, "initCoreEnv done, "
                + "version=${runCatching { Libv2ray.checkVersionX() }.getOrNull()}")

            val controller = Libv2ray.newCoreController(XrayCallback())
            coreController = controller

            android.util.Log.d(TAG, "Starting Xray core (tunFd=$tunFd, "
                + "version=${runCatching { Libv2ray.checkVersionX() }.getOrNull()})")
            controller.startLoop(config, tunFd)

            isRunning = true
            isServiceRunning = true
            activeController = controller
            totalUplink = 0L
            totalDownlink = 0L

            android.util.Log.d(TAG, "Xray core started successfully")
        } catch (t: Throwable) {
            android.util.Log.e(TAG, "Failed to start Xray: ${t.message}", t)
            stopXray()
        }
    }

    /** Starts WARP through Aether, not Xray's WireGuard outbound. Aether only
     * emits ready after endpoint handshake plus a real HTTP probe. */
    private fun startAether(rawConfig: String) {
        if (isRunning || aetherActive) return
        var tun: ParcelFileDescriptor? = null
        try {
            val config = rawConfig.replace("__APP_FILES__", filesDir.absolutePath)
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
            vpnInterface = tun
            aetherActive = true
            isRunning = true
            isServiceRunning = true
            totalUplink = 0L
            totalDownlink = 0L
            val result = NativeCore.start(config, tun.fd)
            if (result != 0) error(NativeCore.lastError().ifBlank { "Aether exited with code $result" })
            stopXray()
        } catch (t: Throwable) {
            android.util.Log.e(TAG, "Aether WARP failed: ${t.message}", t)
            runCatching { NativeCore.stop() }
            runCatching { NativeCore.detach() }
            aetherActive = false
            stopXray()
        }
    }

    /** Called by the Aether JNI callback; status=connected is emitted only after
     * its data-plane validation, unlike the old Xray handshake-only path. */
    fun onEvent(json: String) {
        runCatching {
            val event = JSONObject(json)
            if (event.optString("type") == "traffic") {
                totalUplink = event.optLong("tx")
                totalDownlink = event.optLong("rx")
            }
            android.util.Log.d(TAG, "Aether event: $json")
        }
    }

    fun protectSocket(fd: Int): Boolean = protect(fd)

    private fun stopXray() {
        try {
            isRunning = false
            isServiceRunning = false
            activeController = null
            totalUplink = 0L
            totalDownlink = 0L

            if (aetherActive) {
                runCatching { NativeCore.stop() }
                runCatching { NativeCore.detach() }
                aetherActive = false
            }
            try {
                coreController?.stopLoop()
            } catch (e: Exception) {
                android.util.Log.e(TAG, "stopLoop error: ${e.message}")
            }
            coreController = null

            vpnInterface?.close()
            vpnInterface = null

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            android.util.Log.d(TAG, "Xray stopped")
            stopSelf()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error stopping Xray: ${e.message}")
        }
    }

    private inner class XrayCallback : CoreCallbackHandler {
        override fun startup(): Long = 0L
        override fun shutdown(): Long {
            try {
                Thread { stopXray() }.start()
            } catch (_: Exception) { }
            return 0L
        }
        override fun onEmitStatus(level: Long, msg: String?): Long {
            android.util.Log.d(TAG, "core status [$level]: $msg")
            return 0L
        }
    }

    private fun showNotification() {
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        )
        val disconnectIntent = Intent(this, XrayVpnService::class.java).apply {
            action = ACTION_DISCONNECT
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this, 0, disconnectIntent, PendingIntent.FLAG_IMMUTABLE
        )

        val isWarp = configJson?.contains("__APP_FILES__") == true
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(if (isWarp) "🔒 WARP Connected" else "🔒 Xray Connected")
            .setContentText("Tap to open • Tap disconnect to stop")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Disconnect",
                disconnectPendingIntent
            )
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
        stopXray()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopXray()
        super.onDestroy()
    }
}
