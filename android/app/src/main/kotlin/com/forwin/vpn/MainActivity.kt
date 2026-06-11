package com.forwin.vpn

import android.content.Intent
import android.net.TrafficStats
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import id.laskarmedia.openvpn_flutter.OpenVPNFlutterPlugin
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

class MainActivity: FlutterActivity() {
    private val DNS_CHANNEL = "com.forwin.vpn/dns"
    private val XRAY_CHANNEL = "com.forwin.vpn/xray"
    private val VPN_REQUEST_CODE = 100
    private val XRAY_REQUEST_CODE = 101
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // OpenVPN permission handler
        OpenVPNFlutterPlugin.connectWhileGranted(requestCode == 24 && resultCode == RESULT_OK)
        super.onActivityResult(requestCode, resultCode, data)
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // DNS Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DNS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestDnsPermission" -> {
                    val intent = VpnService.prepare(applicationContext)
                    if (intent != null) {
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        result.success(false) // Will be granted after user approval
                    } else {
                        result.success(true) // Already granted
                    }
                }
                "connectDns" -> {
                    val primaryDns = call.argument<String>("primaryDns") ?: "8.8.8.8"
                    val secondaryDns = call.argument<String>("secondaryDns") ?: "8.8.4.4"
                    
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_CONNECT
                        putExtra(DnsVpnService.EXTRA_DNS_PRIMARY, primaryDns)
                        putExtra(DnsVpnService.EXTRA_DNS_SECONDARY, secondaryDns)
                    }
                    startService(intent)
                    result.success(true)
                }
                "disconnectDns" -> {
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_DISCONNECT
                    }
                    startService(intent)
                    result.success(true)
                }
                "getDnsStats" -> {
                    // مجموع ترافیک رد و بدل شده دستگاه (دانلود/آپلود) بر حسب بایت
                    val rxBytes = TrafficStats.getTotalRxBytes()
                    val txBytes = TrafficStats.getTotalTxBytes()
                    val stats = HashMap<String, Any>()
                    // در صورت پشتیبانی نشدن، TrafficStats مقدار UNSUPPORTED (-1) برمی‌گرداند
                    stats["rxBytes"] = if (rxBytes == TrafficStats.UNSUPPORTED.toLong()) 0L else rxBytes
                    stats["txBytes"] = if (txBytes == TrafficStats.UNSUPPORTED.toLong()) 0L else txBytes
                    result.success(stats)
                }
                "pingDns" -> {
                    // پینگ واقعی به سرور DNS (به‌صورت native تا حتی موقع فعال بودن
                    // VPN دایرکت DNS هم به‌درستی کار کند). نتیجه: میلی‌ثانیه یا -1
                    val dnsIp = call.argument<String>("dnsIp") ?: "8.8.8.8"
                    Thread {
                        val ping = pingDnsServer(dnsIp)
                        runOnUiThread {
                            result.success(ping)
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        
        // Xray Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, XRAY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestXrayPermission" -> {
                    val intent = VpnService.prepare(applicationContext)
                    if (intent != null) {
                        startActivityForResult(intent, XRAY_REQUEST_CODE)
                        result.success(false) // Will be granted after user approval
                    } else {
                        result.success(true) // Already granted
                    }
                }
                "connectXray" -> {
                    val configJson = call.argument<String>("configJson") ?: ""
                    
                    val intent = Intent(this, XrayVpnService::class.java).apply {
                        action = XrayVpnService.ACTION_CONNECT
                        putExtra(XrayVpnService.EXTRA_CONFIG_JSON, configJson)
                    }
                    startService(intent)
                    result.success(true)
                }
                "disconnectXray" -> {
                    val intent = Intent(this, XrayVpnService::class.java).apply {
                        action = XrayVpnService.ACTION_DISCONNECT
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * پینگ واقعی به سرور DNS و برگرداندن تاخیر بر حسب میلی‌ثانیه.
     * دقیقاً مثل دستور `ping` در ترموکس عمل می‌کند.
     * روش 1: ICMP ping با InetAddress.isReachable (مثل ترموکس ping).
     * روش 2: TCP connect روی پورت‌های رایج (53، 443، 80).
     * روش 3: UDP DNS query روی پورت 53.
     * در صورت ناموفق بودن همه، -1 برمی‌گرداند.
     */
    private fun pingDnsServer(dnsIp: String): Int {
        // روش 1: ICMP echo (دقیقاً مثل دستور ping ترموکس)
        val icmp = pingIcmp(dnsIp)
        if (icmp >= 0) return icmp

        // روش 2: TCP connect روی پورت‌های رایج
        for (port in intArrayOf(53, 443, 80)) {
            val tcp = pingTcp(dnsIp, port)
            if (tcp >= 0) return tcp
        }

        // روش 3: UDP DNS query
        return pingDnsUdp(dnsIp)
    }

    /** ICMP ping - مثل دستور ping در ترموکس */
    private fun pingIcmp(host: String): Int {
        return try {
            val address = InetAddress.getByName(host)
            val start = System.currentTimeMillis()
            val reachable = address.isReachable(2000)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            if (reachable && elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        }
    }

    private fun pingDnsUdp(dnsIp: String): Int {
        var socket: DatagramSocket? = null
        return try {
            val address = InetAddress.getByName(dnsIp)
            val query = buildDnsQuery("google.com")

            socket = DatagramSocket()
            socket.soTimeout = 1500

            val sendPacket = DatagramPacket(query, query.size, address, 53)
            val responseBuffer = ByteArray(512)
            val responsePacket = DatagramPacket(responseBuffer, responseBuffer.size)

            val start = System.currentTimeMillis()
            socket.send(sendPacket)
            socket.receive(responsePacket) // در صورت تایم‌اوت استثنا می‌دهد
            val elapsed = (System.currentTimeMillis() - start).toInt()

            if (elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        } finally {
            socket?.close()
        }
    }

    private fun pingTcp(host: String, port: Int): Int {
        var socket: Socket? = null
        return try {
            socket = Socket()
            val start = System.currentTimeMillis()
            socket.connect(InetSocketAddress(host, port), 1500)
            val elapsed = (System.currentTimeMillis() - start).toInt()
            if (elapsed in 0..3000) elapsed else -1
        } catch (e: Exception) {
            -1
        } finally {
            try { socket?.close() } catch (e: Exception) {}
        }
    }

    /** ساخت یک بسته‌ی استاندارد DNS query (نوع A) برای دامنه‌ی داده‌شده */
    private fun buildDnsQuery(domain: String): ByteArray {
        val out = ArrayList<Byte>()
        fun b(v: Int) = out.add(v.toByte())
        // Transaction ID
        b(0x12); b(0x34)
        // Flags: standard query, recursion desired
        b(0x01); b(0x00)
        // QDCOUNT = 1
        b(0x00); b(0x01)
        // ANCOUNT / NSCOUNT / ARCOUNT = 0
        b(0x00); b(0x00)
        b(0x00); b(0x00)
        b(0x00); b(0x00)
        // QNAME
        for (part in domain.split(".")) {
            b(part.length)
            for (c in part.toByteArray(Charsets.US_ASCII)) {
                out.add(c)
            }
        }
        b(0x00) // پایان نام دامنه
        // QTYPE = A
        b(0x00); b(0x01)
        // QCLASS = IN
        b(0x00); b(0x01)
        return out.toByteArray()
    }
}
