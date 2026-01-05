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
 * Direct DNS VPN Service
 * Changes only DNS server while allowing all traffic to pass through normally
 * This is a "transparent proxy" that only intercepts DNS queries
 */
class DnsVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    private var isRunning = false
    
    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.dns.CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.dns.DISCONNECT"
        const val EXTRA_DNS_PRIMARY = "dns_primary"
        const val EXTRA_DNS_SECONDARY = "dns_secondary"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "dns_vpn_channel"
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val primaryDns = intent.getStringExtra(EXTRA_DNS_PRIMARY) ?: "8.8.8.8"
                val secondaryDns = intent.getStringExtra(EXTRA_DNS_SECONDARY) ?: "8.8.4.4"
                startVpn(primaryDns, secondaryDns)
            }
            ACTION_DISCONNECT -> {
                stopVpn()
                stopSelf()
            }
        }
        return START_STICKY
    }
    
    private fun startVpn(primaryDns: String, secondaryDns: String) {
        if (isRunning) {
            return
        }
        
        stopVpn()
        
        try {
            // Create notification for foreground service
            createNotificationChannel()
            
            // Create disconnect intent
            val disconnectIntent = Intent(this, DnsVpnService::class.java).apply {
                action = ACTION_DISCONNECT
            }
            val disconnectPendingIntent = PendingIntent.getService(
                this,
                0,
                disconnectIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            // Create main activity intent (when user taps notification)
            val mainIntent = packageManager.getLaunchIntentForPackage(packageName)
            val mainPendingIntent = PendingIntent.getActivity(
                this,
                0,
                mainIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("🔒 VPN Connected")
                .setContentText("DNS: $primaryDns • Tap to disconnect")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true) // Cannot be dismissed
                .setContentIntent(mainPendingIntent) // Open app when tapped
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Disconnect",
                    disconnectPendingIntent
                )
                .build()
            
            startForeground(NOTIFICATION_ID, notification)
            
            // Configure VPN with minimal routing - only DNS interception
            val builder = Builder()
                .setSession("4win DNS VPN")
                .addAddress("10.0.0.2", 32) // Single IP, not a subnet
                .addDnsServer(primaryDns)
                .addDnsServer(secondaryDns)
                .setBlocking(false)
            
            // CRITICAL: Do NOT add routes - let traffic flow normally
            // Only DNS queries will be intercepted by Android system
            // .addRoute("0.0.0.0", 0) // REMOVED - this blocks all traffic!
            
            vpnInterface = builder.establish()
            
            if (vpnInterface != null) {
                isRunning = true
                
                // Start minimal packet handler thread
                // This is required by VpnService but we don't actually process packets
                vpnThread = Thread {
                    runVpnLoop()
                }.apply {
                    name = "DnsVpnThread"
                    start()
                }
            } else {
                stopSelf()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            stopVpn()
            stopSelf()
        }
    }
    
    private fun runVpnLoop() {
        try {
            val input = FileInputStream(vpnInterface?.fileDescriptor)
            val output = FileOutputStream(vpnInterface?.fileDescriptor)
            val buffer = ByteArray(32767)
            
            // Minimal loop - just keep VPN alive
            // Android system handles DNS interception automatically
            // We don't need to process packets manually
            while (isRunning && vpnInterface != null && !Thread.interrupted()) {
                try {
                    // Read packet (non-blocking)
                    val length = input.read(buffer)
                    if (length > 0) {
                        // Echo back immediately - transparent pass-through
                        // This ensures traffic flows normally
                        output.write(buffer, 0, length)
                    } else {
                        // No data, sleep briefly to avoid busy-wait
                        Thread.sleep(10)
                    }
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    // Ignore transient errors
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            isRunning = false
        }
    }
    
    private fun stopVpn() {
        isRunning = false
        
        vpnThread?.interrupt()
        vpnThread = null
        
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        vpnInterface = null
        
        stopForeground(true)
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DNS VPN Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when DNS VPN is active"
            }
            
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }
}
