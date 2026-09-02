package com.forwin.vpn

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Runs the TUN -> Psiphon SOCKS bridge in its own Android process.
 *
 * Psiphon and Xray are both gomobile/Go runtimes. Loading both Go runtimes in
 * the Flutter process can cause native runtime collisions. Keeping this Xray
 * bridge in :psiphonbridge isolates the two native runtimes while preserving
 * the Android VpnService TUN fd.
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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startBridge(intent)
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
        stopSelf()
    }

    override fun onDestroy() {
        try { PsiphonTunBridge.stop() } catch (_: Throwable) {}
        try { tunPfd?.close() } catch (_: Throwable) {}
        tunPfd = null
        controllerStarted = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
