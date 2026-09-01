package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import ca.psiphon.PsiphonTunnel
import java.util.concurrent.Semaphore

class PsiphonVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var psiphonTunnel: PsiphonTunnel? = null
    @Volatile private var tunnelRunning = false
    private var currentRegion: String = ""

    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.PSIPHON_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.PSIPHON_DISCONNECT"
        const val ACTION_RECONNECT = "com.forwin.vpn.PSIPHON_RECONNECT"
        const val EXTRA_EGRESS_REGION = "egress_region"

        private const val TAG = "PsiphonVpnService"
        private const val NOTIFICATION_ID = 3
        private const val CHANNEL_ID = "PsiphonVpnChannel"
        private const val VPN_MTU = 1500
        private const val PRIVATE_VLAN4 = "10.8.0.1"
        private const val PSIPHON_NATIVE_LIBRARY = "psiphon-gojni"

        @Volatile
        private var isServiceRunning = false

        @Volatile
        private var isTunnelConnected = false

        @Volatile
        private var totalUplink = 0L

        @Volatile
        private var totalDownlink = 0L

        private val semaphore = Semaphore(1)

        fun isRunning(): Boolean = isServiceRunning
        fun isConnected(): Boolean = isTunnelConnected

        fun queryTrafficStats(): LongArray {
            return longArrayOf(totalUplink, totalDownlink)
        }
    }

    override fun onCreate() {
        super.onCreate()
        loadPsiphonNativeLibrary()
        Log.d(TAG, "PsiphonVpnService created")
        createNotificationChannel()
    }

    private fun loadPsiphonNativeLibrary() {
        try {
            System.loadLibrary(PSIPHON_NATIVE_LIBRARY)
            Log.d(TAG, "Loaded isolated Psiphon native runtime")
        } catch (e: UnsatisfiedLinkError) {
            // Local development may still use the unmodified Maven AAR.
            // CI/release builds always provide the isolated library.
            Log.w(TAG, "Isolated Psiphon runtime unavailable; using bundled gomobile runtime", e)
            try {
                System.loadLibrary("gojni")
            } catch (fallback: UnsatisfiedLinkError) {
                Log.e(TAG, "Unable to load gomobile runtime", fallback)
                throw fallback
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        Log.d(TAG, "onStartCommand: action=$action")

        when (action) {
            ACTION_CONNECT -> {
                val region = intent.getStringExtra(EXTRA_EGRESS_REGION) ?: ""
                Thread { startPsiphon(region) }.start()
            }
            ACTION_DISCONNECT -> {
                Thread { stopPsiphon() }.start()
            }
            ACTION_RECONNECT -> {
                Thread {
                    stopPsiphon()
                    Thread.sleep(500)
                    val region = intent.getStringExtra(EXTRA_EGRESS_REGION) ?: ""
                    startPsiphon(region)
                }.start()
            }
        }

        return START_STICKY
    }
