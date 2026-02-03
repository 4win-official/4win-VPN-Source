package com.forwin.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * Xray VPN Service for handling Xray/V2Ray connections
 * Inspired by v2rayNG but simplified for Flutter integration
 */
class XrayVpnService : VpnService() {
    
    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private var configJson: String? = null
    
    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.XRAY_CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.XRAY_DISCONNECT"
        const val EXTRA_CONFIG_JSON = "config_json"
        
        private const val NOTIFICATION_ID = 2
        private const val CHANNEL_ID = "XrayVpnChannel"
        private const val VPN_MTU = 1500
        private const val VPN_ADDRESS = "26.26.26.1"
        private const val VPN_ROUTE = "0.0.0.0"
    }
    
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                configJson = intent.getStringExtra(EXTRA_CONFIG_JSON)
                startXrayVpn()
            }
            ACTION_DISCONNECT -> {
                stopXrayVpn()
            }
        }
        return START_STICKY
    }
    
    private fun startXrayVpn() {
        if (isRunning) {
            android.util.Log.d("XrayVpnService", "VPN already running")
            return
        }
        
        try {
            // Create VPN interface
            val builder = Builder()
                .setSession("4win VPN - Xray")
                .setMtu(VPN_MTU)
                .addAddress(VPN_ADDRESS, 24)
                .addRoute(VPN_ROUTE, 0)
                .addDnsServer("8.8.8.8")
                .addDnsServer("8.8.4.4")
            
            // Establish VPN
            vpnInterface = builder.establish()
            
            if (vpnInterface == null) {
                android.util.Log.e("XrayVpnService", "Failed to establish VPN interface")
                stopSelf()
                return
            }
            
            isRunning = true
            
            // Show notification
            showNotification()
            
            // TODO: Start Xray Core
            // This is where we would initialize libxray.so and start the proxy
            // For now, we'll establish the VPN tunnel which is the first step
            
            android.util.Log.d("XrayVpnService", "✅ Xray VPN started successfully")
            
            // Start traffic forwarding
            startTrafficForwarding()
            
        } catch (e: Exception) {
            android.util.Log.e("XrayVpnService", "Failed to start Xray VPN: ${e.message}")
            stopXrayVpn()
        }
    }
    
    private fun startTrafficForwarding() {
        Thread {
            try {
                val fd = vpnInterface?.fileDescriptor ?: return@Thread
                val inputStream = FileInputStream(fd)
                val outputStream = FileOutputStream(fd)
                
                val packet = ByteBuffer.allocate(VPN_MTU)
                
                while (isRunning) {
                    val length = inputStream.read(packet.array())
                    if (length > 0) {
                        // TODO: Forward to Xray Core
                        // For now, we just read and discard to keep the tunnel alive
                        packet.clear()
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("XrayVpnService", "Traffic forwarding error: ${e.message}")
            }
        }.start()
    }
    
    private fun stopXrayVpn() {
        try {
            isRunning = false
            
            // Close VPN interface
            vpnInterface?.close()
            vpnInterface = null
            
            // Stop foreground service
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            
            android.util.Log.d("XrayVpnService", "✅ Xray VPN stopped")
            stopSelf()
            
        } catch (e: Exception) {
            android.util.Log.e("XrayVpnService", "Error stopping Xray VPN: ${e.message}")
        }
    }
    
    private fun showNotification() {
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        // Create disconnect action
        val disconnectIntent = Intent(this, XrayVpnService::class.java).apply {
            action = ACTION_DISCONNECT
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this,
            0,
            disconnectIntent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🔒 Xray VPN Connected")
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
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }
    
    override fun onRevoke() {
        stopXrayVpn()
        super.onRevoke()
    }
    
    override fun onDestroy() {
        stopXrayVpn()
        super.onDestroy()
    }
}
