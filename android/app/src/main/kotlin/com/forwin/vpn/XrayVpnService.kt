package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
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
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                startXray()
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
            stopSelf()
            return
        }

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
            } catch (_: Exception) { /* device without IPv6 */ }

            // Keep our own app traffic out of the tunnel to avoid loops.
            try {
                builder.addDisallowedApplication(packageName)
            } catch (_: Exception) { }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            vpnInterface = builder.establish()
            val tun = vpnInterface
            if (tun == null) {
                android.util.Log.e(TAG, "Failed to establish VPN interface")
                stopSelf()
                return
            }

            // 2) Initialize the core environment (asset path for geoip/geosite).
            // geoip.dat & geosite.dat are bundled inside libv2ray.aar's assets and are
            // resolved automatically by the core's asset reader; we still set filesDir
            // as the env path so any user-supplied assets there take precedence.
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")

            // 3) Create the core controller and start the loop with the TUN fd.
            val controller = Libv2ray.newCoreController(XrayCallback())
            coreController = controller

            val tunFd = tun.fd
            controller.startLoop(config, tunFd)

            isRunning = true
            isServiceRunning = true
            showNotification()

            android.util.Log.d(TAG, "Xray core started (version=${runCatching { Libv2ray.checkVersionX() }.getOrNull()})")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to start Xray: ${e.message}", e)
            stopXray()
        }
    }

    private fun stopXray() {
        try {
            isRunning = false
            isServiceRunning = false

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
