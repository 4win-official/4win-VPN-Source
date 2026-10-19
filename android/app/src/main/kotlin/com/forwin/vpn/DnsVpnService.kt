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
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Direct DNS VPN Service
 * Changes only DNS server while allowing all traffic to pass through normally
 * This is a "transparent proxy" that only intercepts DNS queries
 */
class DnsVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    @Volatile private var isRunning = false
    private val lifecycleLock = Any()
    @Volatile private var generation = System.nanoTime()
    private var reconnectInProgress = false
    private var activeConnectIntent: Intent? = null
    private val lifecycleExecutor: ExecutorService = Executors.newSingleThreadExecutor { r -> Thread(r, "DnsVpnLifecycle") }
    
    companion object {
        const val ACTION_CONNECT = "com.forwin.vpn.dns.CONNECT"
        const val ACTION_DISCONNECT = "com.forwin.vpn.dns.DISCONNECT"
        const val ACTION_RECONNECT = "com.forwin.vpn.dns.RECONNECT"
        private const val EXTRA_GENERATION = "connection_generation"
        const val EXTRA_DNS_PRIMARY = "dns_primary"
        const val EXTRA_DNS_SECONDARY = "dns_secondary"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "dns_vpn_channel"

        @Volatile
        var isReconnecting = false
            private set

        // ارجاع به نمونه‌ی فعال سرویس تا MainActivity بتواند پینگ protected بگیرد
        @Volatile
        var instance: DnsVpnService? = null
        @Volatile var isServiceRunning = false

        /**
         * پینگ به سرور DNS از طریق سوکت protect-شده (خارج از تونل VPN).
         * اگر سرویس فعال نباشد، -1 برمی‌گرداند تا caller روش دیگری امتحان کند.
         */
        fun pingViaService(dnsIp: String): Int {
            val svc = instance ?: return -2 // سرویس فعال نیست
            return svc.pingDnsProtected(dnsIp)
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val token: Long
                val primary: String; val secondary: String
                synchronized(lifecycleLock) { generation++; token=generation; reconnectInProgress=false; isReconnecting=false; activeConnectIntent=Intent(intent); primary=intent.getStringExtra(EXTRA_DNS_PRIMARY) ?: "8.8.8.8"; secondary=intent.getStringExtra(EXTRA_DNS_SECONDARY) ?: "8.8.4.4" }
                lifecycleExecutor.execute { stopVpn(false); if (token == generation) startVpn(primary, secondary, token) }
            }
            ACTION_DISCONNECT -> if (isCurrentToken(intent)) {
                VpnStateBroadcast.notifyDisconnected(this, "direct_dns")
                synchronized(lifecycleLock) { invalidateConnectionLocked() }
                lifecycleExecutor.execute { stopVpn(true) }
            }
            ACTION_RECONNECT -> reconnect(intent)
        }
        return START_STICKY
    }

    private fun showNotification(primaryDns: String, token: Long) {
        // Create notification for foreground service
        createNotificationChannel()

        // Create disconnect intent
        val disconnectIntent = Intent(this, DnsVpnService::class.java).apply {
            action = ACTION_DISCONNECT
            data = android.net.Uri.parse("forwin-dns-vpn://disconnect/$token")
            putExtra(EXTRA_GENERATION, token)
        }
        val reconnectIntent = Intent(this, DnsVpnService::class.java).apply {
            action = ACTION_RECONNECT
            data = android.net.Uri.parse("forwin-dns-vpn://reconnect/$token")
            putExtra(EXTRA_GENERATION, token)
        }
        val disconnectPendingIntent = PendingIntent.getService(
            this,
            token.toInt(),
            disconnectIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val reconnectPendingIntent = PendingIntent.getService(
            this,
            token.toInt() + 1,
            reconnectIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE
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
            .setContentTitle("DNS VPN")
            .setContentText("DNS: $primaryDns • Reconnect or disconnect")
            .setSmallIcon(R.mipmap.ic_launcher) // لوگو اپ
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true) // Cannot be dismissed
            .setContentIntent(mainPendingIntent) // Open app when tapped
            .addAction(android.R.drawable.ic_popup_sync, "Reconnect", reconnectPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnectPendingIntent)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun startVpn(primaryDns: String, secondaryDns: String, token: Long = generation) {
        if (token != generation) return
        if (isRunning) {
            return
        }
        
        try {
            showNotification(primaryDns, token)

            // Configure VPN with minimal routing - only DNS interception
            val builder = Builder()
                .setSession("4win DNS VPN")
                .addAddress("10.0.0.2", 32) // Single IP, not a subnet
                .addDnsServer(primaryDns)
                .addDnsServer(secondaryDns)
                .setBlocking(false)

            // Split Tunneling: apply the user's per-app include/exclude rules.
            SplitTunnel.apply(applicationContext, builder, packageName)
            
            // CRITICAL: Do NOT add routes - let traffic flow normally
            // Only DNS queries will be intercepted by Android system
            // .addRoute("0.0.0.0", 0) // REMOVED - this blocks all traffic!
            
            vpnInterface = builder.establish()
            if (token != generation) { stopVpn(false); return }
            
            if (vpnInterface != null) {
                isRunning = true
                instance = this // ثبت نمونه‌ی فعال برای پینگ protected
                
                // Start minimal packet handler thread
                // This is required by VpnService but we don't actually process packets
                vpnThread = Thread {
                    runVpnLoop()
                }.apply {
                    name = "DnsVpnThread"
                    start()
                }
            } else {
                stopVpn(false)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            stopVpn(false)
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
    
    private fun reconnect(intent: Intent?) {
        if (!isCurrentToken(intent)) return
        val token: Long
        val restart: Intent
        synchronized(lifecycleLock) {
            val current = activeConnectIntent ?: return
            if (reconnectInProgress) return
            reconnectInProgress = true
            isReconnecting = true
            generation++
            token = generation
            restart = Intent(current)
        }
        runCatching { showNotification(restart.getStringExtra(EXTRA_DNS_PRIMARY) ?: "8.8.8.8", token) }
        lifecycleExecutor.execute {
            stopVpn(false)
            if (token == generation) {
                val primary=restart.getStringExtra(EXTRA_DNS_PRIMARY) ?: "8.8.8.8"
                val secondary=restart.getStringExtra(EXTRA_DNS_SECONDARY) ?: "8.8.4.4"
                startVpn(primary, secondary, token)
            }
            synchronized(lifecycleLock) { if (generation==token) { reconnectInProgress=false; isReconnecting=false } }
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

    private fun stopVpn(stopService: Boolean) {
        isRunning = false
        if (instance === this) {
            instance = null // پاک کردن نمونه‌ی فعال
        }
        
        val oldThread = vpnThread
        oldThread?.interrupt()
        runCatching { vpnInterface?.close() }
        if (oldThread != null && oldThread !== Thread.currentThread()) runCatching { oldThread.join(5_000) }
        vpnThread = null
        
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        vpnInterface = null
        
        if (stopService) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
            stopSelf()
        }
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
    
    /**
     * پینگ به سرور DNS از طریق سوکت‌های protect-شده (با VpnService.protect)
     * تا ترافیک پینگ از تونل VPN عبور نکند و مستقیم به مقصد برسد.
     * روش 1: UDP DNS query روی پورت 53. روش 2: TCP connect.
     * خروجی: میلی‌ثانیه یا -1 در صورت ناموفق بودن.
     */
    fun pingDnsProtected(dnsIp: String): Int {
        // روش 1: UDP DNS query با سوکت protect-شده
        val udp = pingUdpProtected(dnsIp)
        if (udp >= 0) return udp

        // روش 2 (fallback): TCP روی پورت‌های رایج با سوکت protect-شده
        for (port in intArrayOf(53, 443, 80)) {
            val tcp = pingTcpProtected(dnsIp, port)
            if (tcp >= 0) return tcp
        }
        return -1
    }

    private fun pingUdpProtected(dnsIp: String): Int {
        var socket: DatagramSocket? = null
        return try {
            val address = InetAddress.getByName(dnsIp)
            val query = buildDnsQuery("google.com")

            socket = DatagramSocket()
            // protect: سوکت را از تونل VPN خارج می‌کند
            protect(socket)
            socket.soTimeout = 2000

            val sendPacket = DatagramPacket(query, query.size, address, 53)
            val responseBuffer = ByteArray(512)
            val responsePacket = DatagramPacket(responseBuffer, responseBuffer.size)

            val start = System.currentTimeMillis()
            socket.send(sendPacket)
            socket.receive(responsePacket)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            if (elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        } finally {
            socket?.close()
        }
    }

    private fun pingTcpProtected(host: String, port: Int): Int {
        var socket: Socket? = null
        return try {
            socket = Socket()
            // protect قبل از connect
            protect(socket)
            val start = System.currentTimeMillis()
            socket.connect(InetSocketAddress(host, port), 2000)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            if (elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        } finally {
            try { socket?.close() } catch (e: Exception) {}
        }
    }

    /** ساخت بسته‌ی استاندارد DNS query (نوع A) */
    private fun buildDnsQuery(domain: String): ByteArray {
        val out = ArrayList<Byte>()
        fun b(v: Int) = out.add(v.toByte())
        b(0x12); b(0x34) // Transaction ID
        b(0x01); b(0x00) // Flags
        b(0x00); b(0x01) // QDCOUNT
        b(0x00); b(0x00); b(0x00); b(0x00); b(0x00); b(0x00) // AN/NS/AR
        for (part in domain.split(".")) {
            b(part.length)
            for (c in part.toByteArray(Charsets.US_ASCII)) out.add(c)
        }
        b(0x00) // end of name
        b(0x00); b(0x01) // QTYPE = A
        b(0x00); b(0x01) // QCLASS = IN
        return out.toByteArray()
    }

    override fun onRevoke() {
        synchronized(lifecycleLock) { invalidateConnectionLocked() }
        lifecycleExecutor.execute { stopVpn(true); lifecycleExecutor.shutdown() }
        super.onRevoke()
    }

    override fun onDestroy() {
        isServiceRunning = false
        synchronized(lifecycleLock) { invalidateConnectionLocked() }
        lifecycleExecutor.execute { stopVpn(true); lifecycleExecutor.shutdown() }
        super.onDestroy()
    }
}
