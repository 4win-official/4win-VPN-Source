package com.forwin.vpn.slowdns

import com.forwin.vpn.dnsscan.DeadlineInputStream
import com.forwin.vpn.dnsscan.DnsResolverScanner
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.ConnectException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ThreadLocalRandom

/** RFC1928/1929 SOCKS5 plus a real DNS-over-TCP data-plane probe. */
object Socks5Probe {
    fun connectAndQuery(port: Int, username: String?, password: String?, timeoutMs: Int = 15_000): Boolean {
        require(timeoutMs > 0)
        val deadline = System.nanoTime() + timeoutMs * 1_000_000L
        var last: Throwable? = null
        while (System.nanoTime() < deadline) {
            try { return attempt(port, username, password, deadline) }
            catch (t: Throwable) { last = t; if (t is IllegalArgumentException) throw t; Thread.sleep(40) }
        }
        throw (last ?: ConnectException("SOCKS probe timed out"))
    }

    private fun attempt(port: Int, username: String?, password: String?, deadline: Long): Boolean {
        Socket().use { socket ->
            val remaining = { ((deadline - System.nanoTime()) / 1_000_000L).coerceAtLeast(1L).toInt() }
            socket.connect(InetSocketAddress("127.0.0.1", port), remaining())
            socket.soTimeout = remaining()
            val input = DataInputStream(DeadlineInputStream(socket, deadline)); val output = DataOutputStream(socket.getOutputStream())
            val auth = if (username != null) byteArrayOf(0x02) else byteArrayOf(0x00)
            output.write(byteArrayOf(5, auth.size.toByte()) + auth); output.flush()
            check(input.readUnsignedByte() == 5) { "invalid SOCKS version" }
            val method = input.readUnsignedByte()
            if (username != null) {
                check(method == 2) { "SOCKS username/password rejected" }
                val u = username.toByteArray(Charsets.UTF_8); val p = password!!.toByteArray(Charsets.UTF_8)
                require(u.isNotEmpty() && u.size <= 255 && p.isNotEmpty() && p.size <= 255) { "credentials must be 1..255 UTF-8 bytes" }
                output.writeByte(1); output.writeByte(u.size); output.write(u); output.writeByte(p.size); output.write(p); output.flush()
                check(input.readUnsignedByte() == 1 && input.readUnsignedByte() == 0) { "SOCKS authentication failed" }
            } else check(method == 0) { "SOCKS no-auth rejected" }
            output.write(byteArrayOf(5, 1, 0, 1, 1, 1, 1, 1, 0, 53)); output.flush()
            check(input.readUnsignedByte() == 5 && input.readUnsignedByte() == 0) { "SOCKS CONNECT failed" }
            input.readUnsignedByte(); val atyp = input.readUnsignedByte()
            when (atyp) { 1 -> input.readFully(ByteArray(4)); 3 -> input.readFully(ByteArray(input.readUnsignedByte())); 4 -> input.readFully(ByteArray(16)); else -> error("bad SOCKS address") }
            input.readUnsignedShort()
            val query = dnsQuery(); output.writeShort(query.size); output.write(query); output.flush()
            val length = input.readUnsignedShort(); check(length in 12..4096) { "invalid DNS response length" }
            val response = ByteArray(length); input.readFully(response)
            validateDnsResponse(query, response)
            return true
        }
    }

    internal fun validateDnsResponse(query: ByteArray, response: ByteArray) {
        require(query.size >= 12 && response.size >= 12) { "Truncated DNS response." }
        val id = ((query[0].toInt() and 255) shl 8) or (query[1].toInt() and 255)
        val parsed = DnsResolverScanner.validate(response, id, "example.com", 1)
        check(parsed.rcode == 0 && parsed.answerCount > 0) { "No successful tunneled DNS answer." }
    }

    private fun dnsQuery(): ByteArray {
        val id = ThreadLocalRandom.current().nextInt(1, 65536)
        val q = byteArrayOf(0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 7, 'e'.code.toByte(), 'x'.code.toByte(), 'a'.code.toByte(), 'm'.code.toByte(), 'p'.code.toByte(), 'l'.code.toByte(), 'e'.code.toByte(), 3, 'c'.code.toByte(), 'o'.code.toByte(), 'm'.code.toByte(), 0, 0, 1, 0, 1)
        q[0] = (id ushr 8).toByte(); q[1] = id.toByte(); return q
    }
}
