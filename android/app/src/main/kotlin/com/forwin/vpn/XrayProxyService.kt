package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray

/**
 * Runs the Xray core in PROXY mode as a PLAIN foreground [Service] — it does NOT
 * extend [android.net.VpnService], so Android never shows the VPN key icon.
 *
 * The core serves only a local SOCKS/HTTP proxy on 127.0.0.1:<port> (the config
 * built with proxyMode has no `tun` inbound), so no system tunnel is created and
 * nothing is captured device-wide; apps opt in by pointing at the local proxy.
 */
class XrayProxyService : Service() {

    private var coreController: CoreController? = null
    private var configJson: String? = null
    @Volatile private var isRunning = false

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.XRAY_PROXY_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.XRAY_PROXY_DISCONNECT"
        const val EXTRA_CONFIG_JSON = "config_json"

        private const val TAG = "XrayProxyService"
        private const val NOTIFICATION_ID = 3
        private const val CHANNEL_ID = "XrayProxyChannel"

        @Volatile
        var isServiceRunning = false
            private set

        @Volatile private var activeController: CoreController? = null
        @Volatile private var totalUplink = 0L
        @Volatile private var totalDownlink = 0L

        fun queryTrafficStats(): LongArray {
            val controller = activeController
                ?: return longArrayOf(totalUplink, totalDownlink)
            try {
                val up = controller.queryStats("proxy", "uplink")
                val down = controller.queryStats("proxy", "downlink")
                if (up > 0) totalUplink += up
                if (down > 0) totalDownlink += down
            } catch (_: Throwable) { }
            return longArrayOf(totalUplink, totalDownlink)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
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
        if (isRunning) return
        val config = configJson
        if (config.isNullOrBlank()) {
            android.util.Log.e(TAG, "No config provided")
            stopXray()
            return
        }
        try {
            Seq.setContext(applicationContext)
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")

            val controller = Libv2ray.newCoreController(XrayCallback())
            coreController = controller

            // tunFd = -1: proxy-only, the config has no tun inbound.
            controller.startLoop(config, -1)

            isRunning = true
            isServiceRunning = true
            activeController = controller
            totalUplink = 0L
            totalDownlink = 0L
            android.util.Log.d(TAG, "Xray proxy started (127.0.0.1:4444)")
        } catch (t: Throwable) {
            android.util.Log.e(TAG, "Failed to start Xray proxy: ${t.message}", t)
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Error stopping Xray proxy: ${e.message}")
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
        override fun onEmitStatus(level: Long, msg: String?): Long = 0L
    }

    private fun showNotification() {
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        )
        val disconnectIntent = Intent(this, XrayProxyService::class.java).apply {
            action = ACTION_DISCONNECT
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this, 0, disconnectIntent, PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔌 Xray Proxy (127.0.0.1:4444)")
            .setContentText("Local proxy running • Tap disconnect to stop")
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
                "Xray Proxy Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Xray local proxy status"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        stopXray()
        super.onDestroy()
    }
}
