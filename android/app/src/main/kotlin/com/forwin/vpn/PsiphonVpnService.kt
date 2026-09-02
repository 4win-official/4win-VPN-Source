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
import go.Seq
import org.json.JSONObject
import java.util.concurrent.Semaphore

class PsiphonVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var psiphonTunnel: PsiphonTunnel? = null
    @Volatile private var tunnelRunning = false
    private var currentRegion = ""
    private var psiphonSocksPort = 0
    private val lifecycleLock = Semaphore(1)

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
        private const val PSIPHON_SOCKS_PORT = 1080
        private const val PSIPHON_HTTP_PORT = 8080

        @Volatile private var isServiceRunning = false
        @Volatile private var isTunnelConnected = false
        @Volatile private var totalUplink = 0L
        @Volatile private var totalDownlink = 0L

        fun isRunning() = isServiceRunning
        fun isConnected() = isTunnelConnected
        fun queryTrafficStats() = longArrayOf(totalUplink, totalDownlink)
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            // gomobile's Seq context must be initialized in the same Android
            // process that owns Psiphon's Go runtime, before newPsiphonTunnel().
            Seq.setContext(applicationContext)
            System.loadLibrary(PSIPHON_NATIVE_LIBRARY)
            Log.d(TAG, "Psiphon native runtime loaded and gomobile context initialized")
        } catch (t: Throwable) {
            Log.e(TAG, "Psiphon native runtime initialization failed", t)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                currentRegion = intent.getStringExtra(EXTRA_EGRESS_REGION) ?: ""
                try { showNotification("Connecting to Psiphon...", true) } catch (_: Throwable) {}
                Thread { startPsiphon(currentRegion) }.start()
            }
            ACTION_DISCONNECT -> Thread { stopPsiphon() }.start()
            ACTION_RECONNECT -> Thread {
                stopPsiphon()
                Thread.sleep(500)
                try { showNotification("Connecting to Psiphon...", true) } catch (_: Throwable) {}
                Thread { startPsiphon(currentRegion) }.start()
            }.start()
        }
        return START_STICKY
    }

    private fun startPsiphon(region: String) {
        var locked = false
        try {
            lifecycleLock.acquire()
            locked = true
            if (tunnelRunning) return

            isServiceRunning = true
            isTunnelConnected = false
            psiphonSocksPort = 0
            totalUplink = 0
            totalDownlink = 0

            val builder = Builder()
                .setSession("4win VPN - Psiphon")
                .setMtu(VPN_MTU)
                .addAddress(PRIVATE_VLAN4, 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("8.8.8.8")
                .addDnsServer("1.1.1.1")

            try {
                builder.addAddress("fc00::1", 128)
                builder.addRoute("::", 0)
            } catch (_: Throwable) {}

            try { builder.addDisallowedApplication(packageName) } catch (_: Throwable) {}
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

            val tun = builder.establish()
                ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
            vpnInterface = tun
            Log.d(TAG, "Android TUN established fd=${tun.fd}")

            initializePsiphonTunnel(region)
            tunnelRunning = true
            showNotification("Psiphon is starting...", true)
        } catch (t: Throwable) {
            Log.e(TAG, "Psiphon startup failed", t)
            tunnelRunning = false
            isTunnelConnected = false
            isServiceRunning = false
            stopBridgeProcess()
            try { psiphonTunnel?.stop() } catch (_: Throwable) {}
            psiphonTunnel = null
            try { vpnInterface?.close() } catch (_: Throwable) {}
            vpnInterface = null
            try { showNotification("Psiphon failed: ${t.message ?: "unknown error"}", false) } catch (_: Throwable) {}
        } finally {
            if (locked) lifecycleLock.release()
        }
    }

    private fun stopPsiphon() {
        var locked = false
        try {
            lifecycleLock.acquire()
            locked = true
            tunnelRunning = false
            isTunnelConnected = false
            isServiceRunning = false
            stopBridgeProcess()
            try { psiphonTunnel?.stop() } catch (t: Throwable) { Log.w(TAG, "Psiphon stop: ${t.message}") }
            psiphonTunnel = null
            psiphonSocksPort = 0
            try { vpnInterface?.close() } catch (_: Throwable) {}
            vpnInterface = null

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
            else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (t: Throwable) {
            Log.e(TAG, "Psiphon stop failed", t)
        } finally {
            if (locked) lifecycleLock.release()
        }
    }

    private fun initializePsiphonTunnel(region: String) {
        val hostService = object : PsiphonTunnel.HostService {
            override fun getContext(): Context = applicationContext
            override fun getPsiphonConfig(): String = JSONObject()
                .put("EgressRegion", region)
                .put("LocalSocksProxyPort", PSIPHON_SOCKS_PORT)
                .put("LocalHttpProxyPort", PSIPHON_HTTP_PORT)
                .put("EmitBytesTransferred", true)
                .put("EstablishTunnelTimeoutSeconds", 0)
                .toString()
            override fun loadLibrary(library: String) {
                if (library == "gojni") System.loadLibrary(PSIPHON_NATIVE_LIBRARY)
                else System.loadLibrary(library)
            }
            override fun bindToDevice(fileDescriptor: Long) {
                if (!protect(fileDescriptor.toInt())) throw IllegalStateException("VpnService.protect failed for fd=$fileDescriptor")
            }
            override fun onConnecting() {
                Log.d(TAG, "Psiphon tunnel connecting")
                showNotification("Connecting to Psiphon...", true)
            }
            override fun onConnected() {
                Log.d(TAG, "Psiphon tunnel connected")
                isTunnelConnected = true
                val port = psiphonSocksPort
                if (port > 0) startTunBridge(port)
                else Log.w(TAG, "Psiphon connected before SOCKS port notification")
                showNotification("Connected to ${if (region.isBlank()) "Psiphon" else region}", true)
            }
            override fun onListeningSocksProxyPort(port: Int) {
                psiphonSocksPort = port
                Log.d(TAG, "Psiphon SOCKS5 listening on 127.0.0.1:$port")
                startTunBridge(port)
            }
            override fun onListeningHttpProxyPort(port: Int) { Log.d(TAG, "Psiphon HTTP proxy listening on $port") }
            override fun onBytesTransferred(sent: Long, received: Long) { totalUplink += sent; totalDownlink += received }
            override fun onAvailableEgressRegions(regions: MutableList<String>?) { Log.d(TAG, "Psiphon regions: $regions") }
            override fun onSplitTunnelRegions(regions: MutableList<String>?) { Log.d(TAG, "Psiphon split regions: $regions") }
            override fun onUpstreamProxyError(message: String?) { Log.e(TAG, "Psiphon upstream proxy error: $message") }
            override fun onStartedWaitingForNetworkConnectivity() { Log.d(TAG, "Psiphon waiting for network") }
            override fun onStoppedWaitingForNetworkConnectivity() { Log.d(TAG, "Psiphon network restored") }
            override fun onDiagnosticMessage(message: String?) { Log.d(TAG, "Psiphon: $message") }
        }

        val tunnel = PsiphonTunnel.newPsiphonTunnel(hostService)
        tunnel.setVpnMode(true)
        psiphonTunnel = tunnel
        tunnel.startTunneling("")
    }

    private fun startTunBridge(port: Int) {
        val tun = vpnInterface ?: run { Log.e(TAG, "Cannot start Psiphon bridge: TUN is closed"); return }
        if (port !in 1..65535) { Log.e(TAG, "Cannot start Psiphon bridge: invalid SOCKS port $port"); return }
        try {
            val bridgeIntent = Intent(this, PsiphonTunBridgeService::class.java).apply {
                action = PsiphonTunBridgeService.ACTION_START
                putExtra(PsiphonTunBridgeService.EXTRA_TUN_FD, ParcelFileDescriptor.dup(tun.fileDescriptor))
                putExtra(PsiphonTunBridgeService.EXTRA_SOCKS_PORT, port)
            }
            startService(bridgeIntent)
            Log.d(TAG, "Requested isolated full-device bridge on SOCKS port $port")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to launch isolated Psiphon bridge", t)
            isTunnelConnected = false
        }
    }

    private fun stopBridgeProcess() {
        try { startService(Intent(this, PsiphonTunBridgeService::class.java).apply { action = PsiphonTunBridgeService.ACTION_STOP }) }
        catch (t: Throwable) { Log.w(TAG, "Failed to stop isolated bridge: ${t.message}") }
    }

    private fun showNotification(status: String, foreground: Boolean) {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE)
        val disconnect = Intent(this, PsiphonVpnService::class.java).apply { action = ACTION_DISCONNECT }
        val disconnectPending = PendingIntent.getService(this, 0, disconnect, PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔐 Psiphon VPN")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnectPending)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(foreground)
            .build()
        if (foreground) startForeground(NOTIFICATION_ID, notification)
        else getSystemService(Context.NOTIFICATION_SERVICE)?.let { (it as NotificationManager).notify(NOTIFICATION_ID, notification) }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Psiphon VPN Service", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Psiphon VPN tunnel status"
            channel.setShowBadge(false)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}