package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
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
    private val lifecycleLock = Any()
    @Volatile private var generation = System.nanoTime()
    private var reconnectInProgress = false
    private var activeConnectIntent: Intent? = null
    private val commandExecutor: ExecutorService = Executors.newSingleThreadExecutor { r -> Thread(r, "XrayProxyLifecycle") }

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.XRAY_PROXY_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.XRAY_PROXY_DISCONNECT"
        const val ACTION_RECONNECT = "com.forwin.vpn.XRAY_PROXY_RECONNECT"
        private const val EXTRA_GENERATION = "connection_generation"
        const val EXTRA_CONFIG_JSON = "config_json"

        private const val TAG = "XrayProxyService"
        private const val NOTIFICATION_ID = 3
        private const val CHANNEL_ID = "XrayProxyChannel"

        @Volatile
        var isServiceRunning = false
            private set

        @Volatile
        var isReconnecting = false
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
                runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
                val token: Long
                synchronized(lifecycleLock) {
                    generation++; token = generation
                    reconnectInProgress = false
                    isReconnecting = false
                    activeConnectIntent = Intent(intent)
                    configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                }
                commandExecutor.execute { teardown(false); if (isCurrent(token)) { runCatching { showNotification(token) }; launch(token) } }
            }
            ACTION_DISCONNECT -> if (isCurrentToken(intent)) {
                runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
                // Notify Flutter before invalidating the generation or tearing down
                // the core.  A stale notification action is rejected above.
                VpnStateBroadcast.notifyDisconnected(this, "xray")
                synchronized(lifecycleLock) { invalidateConnectionLocked() }
                commandExecutor.execute { teardown(true) }
            }
            ACTION_RECONNECT -> reconnect(intent)
        }
        return START_STICKY
    }

    private fun isCurrent(token: Long): Boolean = token == generation

    private fun launch(token: Long) {
        if (!isCurrent(token)) return
        startXray(token)
    }

    private fun finishReconnect(token: Long) {
        synchronized(lifecycleLock) {
            if (generation == token) {
                reconnectInProgress = false
                isReconnecting = false
            }
        }
    }

    private fun startXray(expectedGeneration: Long = generation) {
        if (expectedGeneration != generation) return
        if (isRunning) return
        val config = configJson
        if (config.isNullOrBlank()) {
            android.util.Log.e(TAG, "No config provided")
            finishReconnect(expectedGeneration)
            commandExecutor.execute { if (isCurrent(expectedGeneration)) teardown(false) }
            return
        }
        com.example.sstp_flutter.VpnConnectionObserver.notifyStarting(this)
        try {
            Seq.setContext(applicationContext)
            Libv2ray.initCoreEnv(filesDir.absolutePath, "")

            val controller = Libv2ray.newCoreController(XrayCallback(expectedGeneration))
            coreController = controller

            // tunFd = -1: proxy-only, the config has no tun inbound.
            controller.startLoop(config, -1)

            if (!isCurrent(expectedGeneration)) {
                controller.stopLoop()
                return
            }
            isRunning = true
            runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, true) }
            isServiceRunning = true
            activeController = controller
            totalUplink = 0L
            totalDownlink = 0L
            finishReconnect(expectedGeneration)
            android.util.Log.d(TAG, "Xray proxy started (127.0.0.1:4444)")
        } catch (t: Throwable) {
            android.util.Log.e(TAG, "Failed to start Xray proxy: ${t.message}", t)
            finishReconnect(expectedGeneration)
            commandExecutor.execute { if (isCurrent(expectedGeneration)) teardown(false) }
        }
    }

    private fun reconnect(intent: Intent?) {
        if (!isCurrentToken(intent)) return
        runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
        val token: Long
        synchronized(lifecycleLock) {
            if (reconnectInProgress || activeConnectIntent == null) return
            reconnectInProgress = true; isReconnecting = true
            generation++; token = generation
            activeConnectIntent = activeConnectIntent?.let { Intent(it) }
        }
        runCatching { showNotification(token) }
        commandExecutor.execute {
            teardown(false)
            if (isCurrent(token)) {
                runCatching { showNotification(token) }
                launch(token)
            }
            if (!isCurrent(token)) finishReconnect(token)
        }
    }

    private fun isCurrentToken(intent: Intent?): Boolean =
        intent == null || !intent.hasExtra(EXTRA_GENERATION) ||
            intent.getLongExtra(EXTRA_GENERATION, Long.MIN_VALUE) == generation

    private fun invalidateConnectionLocked() {
        generation++
        reconnectInProgress = false
        isReconnecting = false
        activeConnectIntent = null
    }

    private fun teardown(stopService: Boolean) {
        runCatching { com.example.sstp_flutter.VpnConnectionObserver.notifyState(this, false) }
        isRunning = false; isServiceRunning = false; activeController = null
        totalUplink = 0L; totalDownlink = 0L
        runCatching { coreController?.stopLoop() }
        coreController = null
        if (stopService) {
            runCatching { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true) }
            stopSelf()
        }
    }

    private fun requestShutdown(token: Long) {
        if (isCurrent(token)) commandExecutor.execute { if (isCurrent(token)) teardown(false) }
    }

    private inner class XrayCallback(private val token: Long) : CoreCallbackHandler {
        override fun startup(): Long = 0L
        override fun shutdown(): Long {
            try {
                requestShutdown(token)
            } catch (_: Exception) { }
            return 0L
        }
        override fun onEmitStatus(level: Long, msg: String?): Long = 0L
    }

    private fun showNotification(token: Long) {
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE
        )
        val disconnectIntent = Intent(this, XrayProxyService::class.java).apply {
            action = ACTION_DISCONNECT
                data = android.net.Uri.parse("forwin-xray-proxy://disconnect/$token")
            putExtra(EXTRA_GENERATION, token)
        }
        val reconnectIntent = Intent(this, XrayProxyService::class.java).apply {
            action = ACTION_RECONNECT
                data = android.net.Uri.parse("forwin-xray-proxy://reconnect/$token")
            putExtra(EXTRA_GENERATION, token)
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this, token.toInt(), disconnectIntent, PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val reconnectPendingIntent = PendingIntent.getService(
            this, token.toInt() + 1, reconnectIntent, PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔌 Xray Proxy (127.0.0.1:4444)")
            .setContentText("Local proxy running • Reconnect or disconnect")
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
        synchronized(lifecycleLock) { invalidateConnectionLocked() }
        commandExecutor.execute { teardown(true); commandExecutor.shutdown() }
        super.onDestroy()
    }
}
