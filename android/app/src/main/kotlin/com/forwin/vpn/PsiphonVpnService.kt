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
import org.json.JSONObject
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
        private const val PSIPHON_SOCKS_PORT = 1080
        private const val PSIPHON_HTTP_PORT = 8080

        @Volatile private var isServiceRunning = false
        @Volatile private var isTunnelConnected = false
        @Volatile private var totalUplink = 0L
        @Volatile private var totalDownlink = 0L
        private val semaphore = Semaphore(1)

        fun isRunning(): Boolean = isServiceRunning
        fun isConnected(): Boolean = isTunnelConnected
        fun queryTrafficStats(): LongArray = longArrayOf(totalUplink, totalDownlink)
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
            Log.e(TAG, "Unable to load isolated Psiphon native runtime", e)
            throw e
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
            ACTION_DISCONNECT -> Thread { stopPsiphon() }.start()
            ACTION_RECONNECT -> Thread {
                stopPsiphon()
                Thread.sleep(500)
                val region = intent.getStringExtra(EXTRA_EGRESS_REGION) ?: ""
                Thread { startPsiphon(region) }.start()
            }.start()
        }
        return START_STICKY
    }

    private fun startPsiphon(region: String) {
        try {
            semaphore.acquire()
            if (tunnelRunning) {
                Log.d(TAG, "Tunnel already running")
                return
            }
            Log.d(TAG, "Starting Psiphon tunnel for region: $region")
            currentRegion = region
            isServiceRunning = true
            try { showNotification("Connecting...") } catch (t: Throwable) { Log.e(TAG, "showNotification failed: ${t.message}", t) }

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
            vpnInterface = tun
            if (tun == null) {
                Log.e(TAG, "Failed to establish VPN interface")
                throw IllegalStateException("Failed to establish VPN interface")
            }

            val tunFd = tun.fd
            Log.d(TAG, "VPN interface established, TUN FD: $tunFd")
            initializePsiphonTunnel(region, tunFd)
            tunnelRunning = true
            isTunnelConnected = false
            totalUplink = 0L
            totalDownlink = 0L
            showNotification("Connecting to Psiphon...")
            Log.d(TAG, "Psiphon tunnel started successfully")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to start Psiphon: ${t.message}", t)
            tunnelRunning = false
            isTunnelConnected = false
            isServiceRunning = false
            try { showNotification("Connection failed: ${t.message}") } catch (_: Throwable) {}
            cleanupTunnelAfterFailure()
        } finally {
            semaphore.release()
        }
    }

    private fun stopPsiphon() {
        try {
            semaphore.acquire()
            Log.d(TAG, "Stopping Psiphon tunnel")
            tunnelRunning = false
            isTunnelConnected = false
            isServiceRunning = false
            try { psiphonTunnel?.stop() } catch (e: Exception) { Log.e(TAG, "Error stopping Psiphon tunnel: ${e.message}") }
            psiphonTunnel = null
            vpnInterface?.close()
            vpnInterface = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE)
            else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            Log.d(TAG, "Psiphon tunnel stopped")
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping Psiphon: ${e.message}")
        } finally {
            semaphore.release()
        }
    }

    private fun cleanupTunnelAfterFailure() {
        try { psiphonTunnel?.stop() } catch (_: Throwable) {}
        psiphonTunnel = null
        try { vpnInterface?.close() } catch (_: Throwable) {}
        vpnInterface = null
    }

    private fun initializePsiphonTunnel(region: String, tunFd: Int) {
        try {
            Log.d(TAG, "Initializing Psiphon tunnel with HostService API")

            val hostService = object : PsiphonTunnel.HostService {
                override fun getContext(): Context = applicationContext

                override fun getPsiphonConfig(): String {
                    return JSONObject()
                        .put("EgressRegion", region)
                        .put("LocalSocksProxyPort", PSIPHON_SOCKS_PORT)
                        .put("LocalHttpProxyPort", PSIPHON_HTTP_PORT)
                        .put("EmitBytesTransferred", true)
                        .put("EstablishTunnelTimeoutSeconds", 0)
                        .toString()
                }

                override fun loadLibrary(library: String) {
                    // The CI pipeline renames Psiphon's gomobile runtime from
                    // libgojni.so to libpsiphon-gojni.so so it can coexist with Xray.
                    if (library == "gojni") {
                        System.loadLibrary(PSIPHON_NATIVE_LIBRARY)
                    } else {
                        System.loadLibrary(library)
                    }
                }

                override fun bindToDevice(fileDescriptor: Long) {
                    if (!protect(fileDescriptor.toInt())) {
                        throw IllegalStateException("VpnService.protect failed for fd=$fileDescriptor")
                    }
                }

                override fun onConnecting() {
                    Log.d(TAG, "Psiphon tunnel connecting...")
                    showNotification("Connecting to Psiphon...")
                }

                override fun onConnected() {
                    Log.d(TAG, "Psiphon tunnel connected")
                    isTunnelConnected = true
                    showNotification("Connected to ${if (region.isBlank()) "Psiphon" else region}")
                }

                override fun onBytesTransferred(sent: Long, received: Long) {
                    totalUplink += sent
                    totalDownlink += received
                }

                override fun onAvailableEgressRegions(regions: MutableList<String>?) {
                    Log.d(TAG, "Available regions: $regions")
                }

                override fun onSplitTunnelRegions(regions: MutableList<String>?) {
                    Log.d(TAG, "Split tunnel regions: $regions")
                }

                override fun onUpstreamProxyError(message: String?) {
                    Log.e(TAG, "Psiphon upstream proxy error: $message")
                }

                override fun onStartedWaitingForNetworkConnectivity() {
                    Log.d(TAG, "Psiphon waiting for network connectivity")
                }

                override fun onStoppedWaitingForNetworkConnectivity() {
                    Log.d(TAG, "Psiphon network connectivity restored")
                }

                override fun onDiagnosticMessage(message: String?) {
                    Log.d(TAG, "Psiphon: $message")
                }
            }

            val tunnel = PsiphonTunnel.newPsiphonTunnel(hostService)
            tunnel.setVpnMode(true)
            psiphonTunnel = tunnel

            // The Psiphon Android library uses its HostService to obtain the
            // configuration and to bind tunnel-core sockets. The VPN TUN fd
            // is intentionally not placed in the Psiphon JSON config.
            // tunnel-core receives the device binder through HostService.
            Log.d(TAG, "Starting Psiphon tunnel-core")
            tunnel.startTunneling("")
            Log.d(TAG, "Psiphon tunnel-core start requested")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize Psiphon tunnel: ${e.message}", e)
            throw e
        }
    }

    private fun showNotification(status: String) {
        try {
            val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = PendingIntent.getActivity(this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE)
            val disconnectIntent = Intent(this, PsiphonVpnService::class.java).apply { action = ACTION_DISCONNECT }
            val disconnectPendingIntent = PendingIntent.getService(this, 0, disconnectIntent, PendingIntent.FLAG_IMMUTABLE)
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("🔐 Psiphon VPN")
                .setContentText(status)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pendingIntent)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnectPendingIntent)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(tunnelRunning)
                .build()
            if (tunnelRunning) startForeground(NOTIFICATION_ID, notification)
            else (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) { Log.e(TAG, "Error showing notification: ${e.message}") }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Psiphon VPN Service", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Psiphon VPN tunnel status"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    override fun onRevoke() { Log.d(TAG, "VPN permission revoked"); stopPsiphon(); super.onRevoke() }
    override fun onDestroy() { Log.d(TAG, "PsiphonVpnService destroyed"); stopPsiphon(); super.onDestroy() }
}
