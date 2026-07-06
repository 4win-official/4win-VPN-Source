package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
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
    @Volatile private var isRunning = false

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.XRAY_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.XRAY_DISCONNECT"
        const val EXTRA_CONFIG_JSON = "config_json"

        private const val TAG = "XrayVpnService"
        private const val NOTIFICATION_ID = 2
        private const val CHANNEL_ID = "XrayVpnChannel"
        private const val VPN_MTU = 1500
        private const val PRIVATE_VLAN4_CLIENT = "26.26.26.1"
        private const val PRIVATE_VLAN6_CLIENT = "da26:2626::1"

        // Tracks the running instance so the Flutter side can query connection state.
        @Volatile
        var isServiceRunning = false
            private set

        // Reference to the live core controller so the Flutter side can poll
        // outbound traffic stats (uplink/downlink) exactly like v2rayNG does.
        @Volatile
        private var activeController: CoreController? = null

        /**
         * Query cumulative outbound traffic for the proxy since connect.
         * Returns a LongArray of [uplinkBytes, downlinkBytes]. Zeros if not running.
         * queryStats is destructive (resets the counter) in the core, so we keep
         * running totals here and return the accumulated value.
         */
        @Volatile private var totalUplink = 0L
        @Volatile private var totalDownlink = 0L

        fun queryTrafficStats(): LongArray {
            val controller = activeController ?: return longArrayOf(totalUplink, totalDownlink)
            try {
                // queryStats returns the delta since the last call and resets it.
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
                // Show the foreground notification IMMEDIATELY. The service was
                // started via startForegroundService(), so Android requires
                // startForeground() within ~5s or it force-crashes the app.
                try {
                    showNotification()
                } catch (t: Throwable) {
                    android.util.Log.e(TAG, "showNotification failed: ${t.message}", t)
                }
                // Heavy startup (TUN establish + Go core) on a background thread.
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

        // Catch Throwable (not just Exception) so a native UnsatisfiedLinkError
        // or Go panic surfaced as an Error doesn't crash the whole app.
        try {
            // 1) Build the TUN interface.
            val builder = Builder()
                .setSession("4win VPN - Xray")
                .setMtu(VPN_MTU)
                .addAddress(PRIVATE_VLAN4_CLIENT, 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("8.8.8.8")
                .addDnsServer("1.1.1.1")

            // IPv6 (best effort).
            try {
                builder.addAddress(PRIVATE_VLAN6_CLIENT, 126)
                builder.addRoute("::", 0)
            } catch (_: Throwable) { /* device without IPv6 */ }

            // Keep our own app traffic out of the tunnel to avoid loops.
            try {
                builder.addDisallowedApplication(packageName)
            } catch (_: Throwable) { }

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

            // 2) Initialize the core environment.
            //
            // CRITICAL (this was the reason configs never connected):
            //  * go.Seq.setContext(applicationContext) MUST be called first. It
            //    bridges the Android Context into the Go runtime so the core's
            //    asset reader (mobasset) can open geoip.dat / geosite.dat that are
            //    bundled inside libv2ray.aar's assets, and so the gVisor TUN /
            //    socket layer works. Without it the core silently fails to route.
            //  * initCoreEnv(assetPath, deviceKey) — assetPath is where the core
            //    looks for asset files on disk; if not found it falls back to the
            //    Android assets via mobasset (needs the Seq context above).
            Seq.setContext(applicationContext)
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")
            android.util.Log.d(TAG, "initCoreEnv done, "
                + "version=${runCatching { Libv2ray.checkVersionX() }.getOrNull()}")

            // 3) Create the core controller and start the loop with the TUN fd.
            val controller = Libv2ray.newCoreController(XrayCallback())
            coreController = controller

            val tunFd = tun.fd
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

    private fun stopXray() {
        try {
            isRunning = false
            isServiceRunning = false
            activeController = null
            totalUplink = 0L
            totalDownlink = 0L

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

    /** Receives lifecycle/status callbacks from the Go core. */
    private inner class XrayCallback : CoreCallbackHandler {
        override fun startup(): Long = 0L
        override fun shutdown(): Long {
            // Core requested shutdown (e.g. fatal error). Tear down on a safe thread.
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

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔒 Xray Connected")
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
