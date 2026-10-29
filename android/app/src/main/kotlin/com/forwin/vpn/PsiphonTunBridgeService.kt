package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import android.app.PendingIntent
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Runs the TUN -> Psiphon SOCKS bridge in its own Android process.
 *
 * Psiphon and Xray are both gomobile/Go runtimes. Loading both Go runtimes in
 * the Flutter process can cause native runtime collisions. Keeping this Xray
 * bridge in :psiphonbridge isolates the two native runtimes while preserving
 * the Android VpnService TUN fd.
 *
 * This service is foreground as well: the bridge is part of the actual VPN
 * data path and must not be treated as a disposable background service by
 * Android while the Psiphon VpnService is active.
 */
class PsiphonTunBridgeService : Service() {
    private var tunPfd: ParcelFileDescriptor? = null
    @Volatile private var controllerStarted = false
    @Volatile private var bridgeSession: String? = null
    private val stopping = AtomicBoolean(false)
    private var heartbeatExecutor: ScheduledExecutorService? = null

    companion object {
        const val ACTION_START = "com.forwin.vpn.PSIPHON_BRIDGE_START"
        const val ACTION_STOP = "com.forwin.vpn.PSIPHON_BRIDGE_STOP"
        const val EXTRA_TUN_FD = "tun_fd"
        const val EXTRA_SOCKS_PORT = "socks_port"
        const val EXTRA_BRIDGE_SESSION = "bridge_session"

        // Cross-process status broadcast: this service runs in :psiphonbridge,
        // while PsiphonVpnService (the thing Flutter polls "isConnected" on)
        // runs in :psiphon. Without this signal, PsiphonVpnService has
        // no way to know whether the actual device-wide TUN bridge succeeded —
        // it would report "connected" purely from Psiphon's own internal
        // tunnel-core callback even if packet routing never started.
        const val ACTION_BRIDGE_STATUS = "com.forwin.vpn.PSIPHON_BRIDGE_STATUS"
        const val EXTRA_BRIDGE_SUCCESS = "bridge_success"
        const val EXTRA_BRIDGE_ERROR = "bridge_error"

        private const val TAG = "PsiphonTunBridgeSvc"
        private const val CHANNEL_ID = "PsiphonBridgeChannel"
        private const val NOTIFICATION_ID = 4

        fun start(context: Context, intent: Intent) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, PsiphonTunBridgeService::class.java).apply {
                    action = ACTION_STOP
                }
            )
        }
    }

    private fun reportBridgeStatus(
        success: Boolean,
        session: String? = bridgeSession,
        error: String? = null,
    ) {
        try {
            val statusIntent = Intent(ACTION_BRIDGE_STATUS).apply {
                setPackage(packageName)
                putExtra(EXTRA_BRIDGE_SUCCESS, success)
                if (!session.isNullOrBlank()) putExtra(EXTRA_BRIDGE_SESSION, session)
                if (!success && !error.isNullOrBlank()) putExtra(EXTRA_BRIDGE_ERROR, error.take(600))
            }
            sendBroadcast(statusIntent)
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to report bridge status: ${t.message}")
        }
    }

    /** The isolated process can be killed without onDestroy; heartbeats expose that loss. */
    private fun startHeartbeat() {
        heartbeatExecutor?.shutdownNow()
        heartbeatExecutor = Executors.newSingleThreadScheduledExecutor()
        heartbeatExecutor?.scheduleAtFixedRate({
            if (controllerStarted && PsiphonTunBridge.isRunning()) reportBridgeStatus(true)
        }, 2, 2, TimeUnit.SECONDS)
    }

    private fun stopHeartbeat() {
        heartbeatExecutor?.shutdownNow()
        heartbeatExecutor = null
    }

    /** Forwards a timestamped line to the main process for the in-app log viewer. */
    private fun blog(msg: String) {
        try {
            Log.d(TAG, msg)
        } catch (_: Throwable) {}
        try {
            val line = try {
                "[${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date())}] [bridge] $msg"
            } catch (_: Throwable) {
                "[bridge] $msg"
            }
            sendBroadcast(Intent(PsiphonVpnService.ACTION_LOG).apply {
                setPackage(packageName)
                putStringArrayListExtra(
                    PsiphonVpnService.EXTRA_LOG_LINES,
                    arrayListOf(line)
                )
            })
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to report bridge log: ${t.message}")
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                try {
                    val session = intent.getStringExtra(EXTRA_BRIDGE_SESSION)
                    val reconnect = Intent(this, PsiphonVpnService::class.java).apply {
                        action = PsiphonVpnService.ACTION_RECONNECT
                        data = android.net.Uri.parse("forwin-psiphon://reconnect/$session")
                        if (!session.isNullOrBlank()) putExtra(PsiphonVpnService.EXTRA_GENERATION, session)
                    }
                    val requestCode = (session?.hashCode() ?: 0) and 0x7fffffff
                    val reconnectPending = PendingIntent.getService(
                        this, requestCode, reconnect,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                    val disconnect = Intent(this, PsiphonVpnService::class.java).apply {
                        action = PsiphonVpnService.ACTION_DISCONNECT
                        data = android.net.Uri.parse("forwin-psiphon://disconnect/$session")
                        if (!session.isNullOrBlank()) putExtra(PsiphonVpnService.EXTRA_GENERATION, session)
                    }
                    val disconnectPending = PendingIntent.getService(
                        this, requestCode xor 0x40000000, disconnect,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                    startForeground(
                        NOTIFICATION_ID,
                        NotificationCompat.Builder(this, CHANNEL_ID)
                            .setSmallIcon(android.R.drawable.ic_lock_lock)
                            .setContentTitle("4win VPN")
                            .setContentText(VpnNotificationLabels.localized(this, "Psiphon traffic bridge active"))
                            .addAction(android.R.drawable.ic_popup_sync, VpnNotificationLabels.localized(this, "Reconnect"), reconnectPending)
                            .addAction(android.R.drawable.ic_menu_close_clear_cancel, VpnNotificationLabels.localized(this, "Disconnect"), disconnectPending)
                            .setPriority(NotificationCompat.PRIORITY_LOW)
                            .setOngoing(true)
                            .build()
                    )
                    startBridge(intent)
                } catch (t: Throwable) {
                    Log.e(TAG, "Failed to start foreground bridge", t)
                    val detail = PsiphonNativeRuntime.describe(t)
                    reportBridgeStatus(false, intent.getStringExtra(EXTRA_BRIDGE_SESSION), detail)
                    blog("bridge failed: foreground start failed: $detail")
                    stopSelf()
                }
            }
            ACTION_STOP -> stopBridge()
        }
        return START_NOT_STICKY
    }

    private fun startBridge(intent: Intent) {
        val requestedSession = intent.getStringExtra(EXTRA_BRIDGE_SESSION)
        if (controllerStarted) {
            val duplicate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(EXTRA_TUN_FD, ParcelFileDescriptor::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(EXTRA_TUN_FD)
            }
            try { duplicate?.close() } catch (_: Throwable) {}
            if (requestedSession == bridgeSession && PsiphonTunBridge.isRunning()) {
                reportBridgeStatus(true, bridgeSession)
                blog("duplicate bridge start acknowledged for session=$bridgeSession")
                return
            }
            blog("replacing stale bridge session=$bridgeSession with session=$requestedSession")
            try { PsiphonTunBridge.stop() } catch (_: Throwable) {}
            try { tunPfd?.close() } catch (_: Throwable) {}
            tunPfd = null
            controllerStarted = false
            bridgeSession = null
        }
        val pfd = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_TUN_FD, ParcelFileDescriptor::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_TUN_FD)
        } ?: run {
            Log.e(TAG, "Missing TUN fd")
            blog("bridge failed: missing TUN fd")
            reportBridgeStatus(false, requestedSession, "Missing TUN file descriptor")
            stopSelf()
            return
        }
        val port = intent.getIntExtra(EXTRA_SOCKS_PORT, 0)
        if (port !in 1..65535) {
            Log.e(TAG, "Invalid SOCKS port: $port")
            blog("bridge failed: invalid SOCKS port $port")
            try { pfd.close() } catch (_: Throwable) {}
            reportBridgeStatus(false, requestedSession, "Invalid SOCKS port: $port")
            stopSelf()
            return
        }

        tunPfd = pfd
        bridgeSession = requestedSession
        stopping.set(false)
        try {
            PsiphonTunBridge.start(applicationContext, pfd.fd, port)
            if (!PsiphonTunBridge.isRunning()) error("native bridge loop is not running")
            controllerStarted = true
            blog("bridge active: tunFd=${pfd.fd} -> 127.0.0.1:$port")
            reportBridgeStatus(true)
            startHeartbeat()
        } catch (t: Throwable) {
            Log.e(TAG, "Bridge startup failed", t)
            val detail = PsiphonNativeRuntime.describe(t)
            blog("bridge startup failed: $detail")
            controllerStarted = false
            try { pfd.close() } catch (_: Throwable) {}
            tunPfd = null
            reportBridgeStatus(false, requestedSession, detail)
            stopSelf()
        }
    }

    private fun stopBridge() {
        if (!stopping.compareAndSet(false, true)) return
        blog("bridge stopping")
        stopHeartbeat()
        try { PsiphonTunBridge.stop() } catch (t: Throwable) {
            Log.w(TAG, "Bridge stop failed: ${t.message}")
        }
        controllerStarted = false
        try { tunPfd?.close() } catch (_: Throwable) {}
        tunPfd = null
        bridgeSession = null
        stopForegroundCompat()
        stopSelf()
    }

    override fun onDestroy() {
        val wasStarted = controllerStarted
        val destroyedSession = bridgeSession
        stopHeartbeat()
        try { PsiphonTunBridge.stop() } catch (_: Throwable) {}
        try { tunPfd?.close() } catch (_: Throwable) {}
        tunPfd = null
        controllerStarted = false
        bridgeSession = null
        if (wasStarted) reportBridgeStatus(false, destroyedSession)
        stopForegroundCompat()
        super.onDestroy()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                VpnNotificationLabels.localized(this, "Psiphon VPN bridge"),
                NotificationManager.IMPORTANCE_LOW
            )
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
