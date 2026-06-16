package com.forwin.vpn

import android.content.Context
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
                "setSstpMtu" -> {
                    // Write the sstp_flutter plugin's MTU value into the default
                    // SharedPreferences (the plugin reads PPP_MTU from there as a String).
                    // This really applies the MTU to the SSTP/PPP tunnel on the next connect.
                    val mtu = call.argument<Int>("mtu") ?: 1400
                    val ok = setSstpMtu(mtu)
                    result.success(ok)
                }
                "detectBestMtu" -> {
                    // REAL MTU auto-detection. Probes the path to the given host using
                    // ping with the Don't-Fragment bit set, binary-searching for the
                    // largest payload that passes without fragmentation, then converts to
                    // the corresponding interface MTU and clamps to [minMtu, maxMtu].
                    // Returns the detected MTU (Int). Falls back to 1400 if probing fails.
                    val host = call.argument<String>("host") ?: "8.8.8.8"
                    val minMtu = call.argument<Int>("minMtu") ?: 1280
                    val maxMtu = call.argument<Int>("maxMtu") ?: 1500
                    Thread {
                        val mtu = detectBestMtu(host, minMtu, maxMtu)
                        // Persist it immediately so the next SSTP connect uses it.
                        setSstpMtu(mtu)
                        runOnUiThread {
                            result.success(mtu)
                        }
                    }.start()
                }
                "setSstpFragment" -> {
                    // REAL PPP fragmentation control for SSTP. The sstp_flutter plugin
                    // reads PPP_MRU (Maximum Receive Unit) from the same default
                    // SharedPreferences and uses it during LCP negotiation (currentMRU).
                    // Lowering the MRU makes PPP frames smaller / fragmented, which helps
                    // data pass through DPI/filtering. This really applies on next connect.
                    val mru = call.argument<Int>("mru") ?: 1400
                    val ok = setSstpFragment(mru)
                    result.success(ok)
                }
                "detectBestFragment" -> {
                    // REAL auto fragmentation: reuse the DF-bit path probe to find the
                    // largest non-fragmenting size, then apply it as the PPP MRU.
                    val host = call.argument<String>("host") ?: "8.8.8.8"
                    val minMru = call.argument<Int>("minMru") ?: 1280
                    val maxMru = call.argument<Int>("maxMru") ?: 1500
                    Thread {
                        val mru = detectBestMtu(host, minMru, maxMru)
                        setSstpFragment(mru)
                        runOnUiThread {
                            result.success(mru)
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
        // روش اصلی: پینگ از طریق سرویس VPN با سوکت protect-شده.
        // این تنها روشی است که موقع فعال بودن تونل دایرکت دی‌ان‌اس قطعاً کار می‌کند،
        // چون سوکت پینگ از تونل خارج می‌شود و مستقیم به DNS server می‌رسد.
        val viaService = DnsVpnService.pingViaService(dnsIp)
        if (viaService >= 0) return viaService
        // viaService == -2 یعنی سرویس فعال نیست → ادامه با روش‌های مستقیم

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

    /**
     * Auto-MTU for SSTP. The sstp_flutter plugin reads its PPP MTU from the
     * default SharedPreferences under the key "PPP_MTU" (stored as a String,
     * see preference/accessor/int.kt). We clamp to the plugin's valid range
     * (68..2000) and write it so the next connect uses the new MTU.
     */
    private fun setSstpMtu(mtu: Int): Boolean {
        return try {
            val clamped = mtu.coerceIn(68, 2000)
            // PreferenceManager.getDefaultSharedPreferences(context) (used by the
            // sstp_flutter plugin) is backed by the SharedPreferences file named
            // "<packageName>_preferences". We open the exact same file here so the
            // PPP_MTU we write is really read by the plugin on connect — without
            // needing the androidx.preference dependency in the app module.
            val prefs = applicationContext.getSharedPreferences(
                "${applicationContext.packageName}_preferences",
                Context.MODE_PRIVATE
            )
            prefs.edit().putString("PPP_MTU", clamped.toString()).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * REAL PPP fragmentation for SSTP. Writes the plugin's PPP_MRU preference.
     * The sstp_flutter plugin reads PPP_MRU (see ClientBridge.currentMRU) and
     * sends it in the LCP MRU option, so a smaller value makes the peer send
     * smaller / fragmented PPP frames. Clamped to the plugin's valid 68..2000.
     */
    private fun setSstpFragment(mru: Int): Boolean {
        return try {
            val clamped = mru.coerceIn(68, 2000)
            val prefs = applicationContext.getSharedPreferences(
                "${applicationContext.packageName}_preferences",
                Context.MODE_PRIVATE
            )
            prefs.edit().putString("PPP_MRU", clamped.toString()).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * REAL MTU path discovery to [host].
     *
     * Uses `ping` with the Don't-Fragment (DF) bit set (`-M do`) and a controlled
     * payload size (`-s`). When a payload is too large to traverse the path
     * without fragmentation, the router replies "Frag needed" / "Message too long"
     * and ping fails. We binary-search for the largest payload that succeeds.
     *
     * payload(success) -> path MTU = payload + 28 (20 IPv4 header + 8 ICMP header).
     * We then subtract a conservative SSTP/PPP/TLS encapsulation overhead so the
     * value we write is a safe inner (PPP) MTU, and clamp into [minMtu, maxMtu].
     *
     * Returns the detected MTU, or 1400 as a safe fallback if probing is not
     * possible (e.g. ICMP blocked).
     */
    private fun detectBestMtu(host: String, minMtu: Int, maxMtu: Int): Int {
        // SSTP runs PPP over TLS over TCP. Encapsulation overhead is roughly:
        // IP(20) + TCP(20) + TLS(~29) + SSTP(~4) + PPP(~8) ≈ 80+ bytes. We keep a
        // conservative margin so the inner MTU never causes fragmentation.
        val encapOverhead = 80
        // ICMP probe needs payload = mtu - 28 (IP + ICMP headers).
        val maxPayload = maxMtu - 28
        val minPayload = minMtu - 28

        var bestPayload = -1
        var lo = minPayload
        var hi = maxPayload

        // First confirm the minimum even works; if not, ICMP is likely blocked.
        if (!pingWithDf(host, minPayload)) {
            // Try once more with a tiny payload to distinguish "ICMP blocked"
            // from "path too small". If even 64 bytes fails, fall back.
            if (!pingWithDf(host, 64)) {
                return 1400.coerceIn(minMtu, maxMtu)
            }
            lo = 64
        } else {
            bestPayload = minPayload
        }

        // Binary search for the largest passing payload.
        var iterations = 0
        while (lo <= hi && iterations < 16) {
            iterations++
            val mid = (lo + hi) / 2
            if (pingWithDf(host, mid)) {
                bestPayload = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        if (bestPayload < 0) return 1400.coerceIn(minMtu, maxMtu)

        val pathMtu = bestPayload + 28
        val innerMtu = pathMtu - encapOverhead
        return innerMtu.coerceIn(minMtu, maxMtu)
    }

    /**
     * Sends a single ICMP echo to [host] with payload [payloadSize] bytes and the
     * Don't-Fragment bit set. Returns true if it succeeds (path can carry this
     * size without fragmentation), false otherwise.
     */
    private fun pingWithDf(host: String, payloadSize: Int): Boolean {
        return try {
            // -c 1 : one packet, -W 2 : 2s timeout, -M do : set DF, -s : payload size
            val process = Runtime.getRuntime().exec(
                arrayOf("/system/bin/ping", "-c", "1", "-W", "2", "-M", "do", "-s", payloadSize.toString(), host)
            )
            val finished = process.waitFor()
            // ping exit code 0 == reply received (DF size passed).
            finished == 0
        } catch (e: Exception) {
            false
        }
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
