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
import java.util.concurrent.atomic.AtomicBoolean

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
    private var controllerStarted = false
    private val stopping = AtomicBoolean(false)

    companion object {
        const val ACTION_START = "com.forwin.vpn.PSIPHON_BRIDGE_START"
        const val ACTION_STOP = "com.forwin.vpn.PSIPHON_BRIDGE_STOP"
        const val EXTRA_TUN_FD = "tun_fd"
        const val EXTRA_SOCKS_PORT = "socks_port"
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

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                try {
                    startForeground(
                        NOTIFICATION_ID,
                        NotificationCompat.Builder(this, CHANNEL_ID)
                            .setSmallIcon(android.R.drawable.ic_lock_lock)
                            .setContentTitle("4win VPN")
                            .setContentText("Psiphon traffic bridge active")
                            .setPriority(NotificationCompat.PRIORITY_LOW)
                            .setOngoing(true)
                            .build()
                    startBridge(intent)
                } catch (t: Throwable) {
                    Log.e(TAG, "Failed to start foreground bridge", t)
                    stopSelf()
                }
            }
            ACTION_STOP -> stopBridge()
        }
        return START_NOT_STICKY
    }

    private fun startBridge(intent: Intent) {
        if (controllerStarted) return
        val pfd = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_TUN_FD, ParcelFileDescriptor::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_TUN_FD)
        } ?: run {
            Log.e(TAG, "Missing TUN fd")
            stopSelf()
            return
        }
        val port = intent.getIntExtra(EXTRA_SOCKS_PORT, 0)
        if (port !in 1..65535) {
            Log.e(TAG, "Invalid SOCKS port: $port")
            try { pfd.close() } catch (_: Throwable) {}
            stopSelf()
            return
        }

        tunPfd = pfd
        stopping.set(false)
        try {
            PsiphonTunBridge.start(applicationContext, pfd.fd, port)
            controllerStarted = true
            Log.d(TAG, "Bridge active: tunFd=${pfd.fd} -> 127.0.0.1:$port")
        } catch (t: Throwable) {
            Log.e(TAG, "Bridge startup failed", t)
            controllerStarted = false
            try { pfd.close() } catch (_: Throwable) {}
            tunPfd = null
            stopSelf()
        }
    }

    private fun stopBridge() {
        if (!stopping.compareAndSet(false, true)) return
        try { PsiphonTunBridge.stop() } catch (t: Throwable) {
            Log.w(TAG, "Bridge stop failed: ${t.message}")
        }
        controllerStarted = false
        try { tunPfd?.close() } catch (_: Throwable) {}
        tunPfd = null
        stopForegroundCompat()
        stopSelf()
    }

    override fun onDestroy() {
        try { PsiphonTunBridge.stop() } catch (_: Throwable) {}
        try { tunPfd?.close() } catch (_: Throwable) {}
        tunPfd = null
        controllerStarted = false
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
                "Psiphon VPN bridge",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
