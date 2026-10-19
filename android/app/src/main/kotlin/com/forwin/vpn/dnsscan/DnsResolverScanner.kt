package com.forwin.vpn.dnsscan

import org.json.JSONArray
import org.json.JSONObject
import java.io.DataInputStream
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.min

/** Strict, protocol-only DNS capability scanner. It does not authenticate a tunnel. */
object DnsResolverScanner {
    private const val DEFAULT_TIMEOUT_MS = 2500
    private const val MAX_TIMEOUT_MS = 10000
    private const val MAX_PACKET = 4096
    private const val MAX_PARALLEL = 64
    private const val MAX_INPUT = 200000
    private const val EDNS_PAYLOAD = 1232
    private const val TXT = 16
    private const val A = 1
    private val random = SecureRandom()

    fun scan(ips: List<String>, domain: String, parallel: Int, port: Int = 53, timeoutMs: Int = DEFAULT_TIMEOUT_MS): String {
        require(port in 1..65535)
        val timeout = timeoutMs.coerceIn(100, MAX_TIMEOUT_MS)
        val targets = ips.asSequence().map { it.trim() }.filter { isNumericIp(it) }
            .distinct().take(MAX_INPUT).toList()
        val executor = Executors.newFixedThreadPool(parallel.coerceIn(1, MAX_PARALLEL))
        val pending = ArrayDeque<Pair<String, java.util.concurrent.Future<String>>>()
        val out = JSONArray()
        try {
            for (ip in targets) {
                pending.add(ip to executor.submit<String> { scanEndpoint(ip, domain, port, port, timeout) })
                if (pending.size >= parallel.coerceIn(1, MAX_PARALLEL)) { val first = pending.removeFirst(); out.put(JSONObject(getSafely(first.second, first.first))) }
            }
            while (pending.isNotEmpty()) { val first = pending.removeFirst(); out.put(JSONObject(getSafely(first.second, first.first))) }
        } finally {
            executor.shutdownNow()
            executor.awaitTermination(1, TimeUnit.SECONDS)
        }
        return out.toString()
    }

    /** Internal fixture hook: probes the supplied UDP and TCP ports without DNS resolution. */
    internal fun scanEndpoint(ip: String, domain: String, udpPort: Int, tcpPort: Int, timeoutMs: Int = DEFAULT_TIMEOUT_MS): String {
        val base = JSONObject().put("ip", ip).put("udpMs", -1).put("tcpMs", -1)
            .put("reachable", false).put("txtSupported", false).put("responseBytes", 0)
            .put("ednsSupported", false).put("ednsPayload", EDNS_PAYLOAD)
            .put("nxdomainSafe", false).put("nxdomainHijacked", false)
            .put("tunnelCandidate", false).put("tunnelVerified", false)
        val address = try { numericAddress(ip) } catch (_: Exception) { return base.toString() }
        var udp: Reply? = null
        var tcp: Reply? = null
        try { udp = queryUdp(address, udpPort, domain, TXT, timeoutMs) } catch (_: Exception) { }
        try { tcp = queryTcp(address, tcpPort, domain, TXT, timeoutMs) } catch (_: Exception) { }
        val primary = udp ?: tcp
        var nx: Reply? = null
        var udpNx: Reply? = null
        // NXDOMAIN must use an actually available transport; UDP is preferred.
        if (udp != null) try { udpNx = queryUdp(address, udpPort, randomLabel(), A, timeoutMs); nx = udpNx } catch (_: Exception) { }
        if (nx == null && tcp != null) try { nx = queryTcp(address, tcpPort, randomLabel(), A, timeoutMs) } catch (_: Exception) { }
        val edns = (udp?.edns == true) || (tcp?.edns == true) || (nx?.edns == true)
        val safe = nx?.rcode == 3
        val hijacked = nx?.let { it.rcode != 3 } ?: false
        base.put("udpMs", udp?.ms ?: -1).put("tcpMs", tcp?.ms ?: -1)
            .put("reachable", primary != null || nx != null) // validated DNS only; a bare open TCP socket never qualifies
            .put("txtSupported", (udp?.txt == true) || (tcp?.txt == true))
            .put("responseBytes", maxOf(udp?.bytes ?: 0, tcp?.bytes ?: 0))
            .put("ednsSupported", edns).put("ednsPayload", listOfNotNull(udp, tcp, nx).firstOrNull { it.edns }?.payload ?: 0)
            .put("nxdomainSafe", safe).put("nxdomainHijacked", hijacked)
            .put("tunnelCandidate", (udp != null && udp.edns && udpNx?.rcode == 3))
        return base.toString()
    }

    private fun getSafely(f: java.util.concurrent.Future<String>, fallback: String): String = try {
        f.get()
    } catch (_: Exception) {
        JSONObject().put("ip", fallback).put("udpMs", -1).put("tcpMs", -1)
            .put("reachable", false).put("txtSupported", false).put("responseBytes", 0)
            .put("ednsSupported", false).put("ednsPayload", EDNS_PAYLOAD)
            .put("nxdomainSafe", false).put("nxdomainHijacked", false)
            .put("tunnelCandidate", false).put("tunnelVerified", false).toString()
    }

    private data class Reply(val ms: Int, val bytes: Int, val txt: Boolean, val edns: Boolean, val rcode: Int, val payload: Int)
    private fun queryUdp(address: InetAddress, port: Int, name: String, type: Int, timeoutMs: Int): Reply {
        val id = random.nextInt(65536); val packet = query(id, name, type)
        DatagramSocket().use { socket ->
            socket.soTimeout = timeoutMs
            socket.connect(InetSocketAddress(address, port)) // fixes source peer and avoids unrelated replies
            val sent = System.nanoTime(); socket.send(DatagramPacket(packet, packet.size))
            val buf = ByteArray(MAX_PACKET); val received = DatagramPacket(buf, buf.size); socket.receive(received)
            require(received.address == address && received.port == port)
            val parsed = parse(buf.copyOf(received.length), id, name, type, false)
            return Reply(elapsed(sent), received.length, parsed.txt, parsed.edns, parsed.rcode, parsed.payload)
        }
    }

    private fun queryTcp(address: InetAddress, port: Int, name: String, type: Int, timeoutMs: Int): Reply {
        val id = random.nextInt(65536); val packet = query(id, name, type)
        Socket().use { socket ->
            socket.soTimeout = timeoutMs; socket.connect(InetSocketAddress(address, port), timeoutMs)
            val sent = System.nanoTime(); val output = socket.getOutputStream()
            output.write(packet.size ushr 8); output.write(packet.size); output.write(packet); output.flush()
            val input = DataInputStream(DeadlineInputStream(socket, System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs.toLong()))); val length = input.readUnsignedShort()
            require(length in 12..MAX_PACKET); val answer = ByteArray(length); input.readFully(answer)
            val parsed = parse(answer, id, name, type, false)
            return Reply(elapsed(sent), length, parsed.txt, parsed.edns, parsed.rcode, parsed.payload)
        }
    }

    /** Validated reply details shared by protocol probes and JVM fixtures. */
    internal data class ParsedReply(
        val txt: Boolean,
        val edns: Boolean,
        val rcode: Int,
        val answerCount: Int,
        val payload: Int
    )
    /** Reusable strict response parser; rejects malformed records in every section. */
    internal fun validate(message: ByteArray, id: Int, name: String, type: Int, truncatedAllowed: Boolean = false): ParsedReply =
        parse(message, id, name, type, truncatedAllowed)

    private fun parse(message: ByteArray, id: Int, name: String, type: Int, truncatedAllowed: Boolean): ParsedReply {
        require(message.size >= 12)
        require(u16(message, 0) == id)
        val flags = u16(message, 2)
        require(flags and 0x8000 != 0 && flags and 0x7800 == 0)
        require(truncatedAllowed || flags and 0x0200 == 0)
        val qd = u16(message, 4); val an = u16(message, 6); val ns = u16(message, 8); val ar = u16(message, 10)
        require(qd == 1)
        var pos = 12
        val q = readName(message, pos); pos = q.next
        require(q.name.equals(name.trimEnd('.'), true)); require(pos + 4 <= message.size && u16(message, pos) == type && u16(message, pos + 2) == 1); pos += 4
        var txt = false; var opt = false; var extRcode = 0; var payload = 0
        repeat(an + ns + ar) { sectionIndex ->
            val n = readName(message, pos); pos = n.next
            require(pos + 10 <= message.size)
            val rrType = u16(message, pos); val rrClass = u16(message, pos + 2)
            val ttl = u32(message, pos + 4); val rdLength = u16(message, pos + 8); pos += 10
            require(rdLength <= message.size - pos)
            if (rrType == 41) {
                require(sectionIndex >= an + ns && n.name.isEmpty() && !opt)
                opt = true; extRcode = ((ttl ushr 24) and 255L).toInt()
                require(((ttl ushr 16) and 255L) == 0L) // EDNS version 0
                parseOptions(message, pos, rdLength)
                require(rrClass >= 512); payload = rrClass
            } else if (rrType == TXT) {
                require(validTxt(message, pos, rdLength)); txt = true
            }
            pos += rdLength
        }
        require(pos == message.size)
        val rcode = (flags and 15) or (extRcode shl 4)
        require(rcode == 0 || rcode == 3)
        return ParsedReply(txt, opt, rcode, an, payload)
    }

    private fun parseOptions(b: ByteArray, start: Int, length: Int) {
        var p = start; val end = start + length
        while (p < end) { require(p + 4 <= end); val n = u16(b, p + 2); p += 4; require(n <= end - p); p += n }
        require(p == end)
    }
    private fun validTxt(b: ByteArray, start: Int, length: Int): Boolean {
        var p = start; val end = start + length
        while (p < end) { val n = b[p++].toInt() and 255; require(n <= end - p); p += n }
        return p == end
    }

    private data class Name(val name: String, val next: Int)
    private fun readName(b: ByteArray, start: Int): Name {
        require(start in b.indices); var p = start; var next = start; var jumped = false; var jumps = 0; val labels = ArrayList<String>()
        while (true) {
            require(p < b.size); val n = b[p].toInt() and 255
            when {
                n == 0 -> { p++; if (!jumped) next = p; break }
                n and 0xc0 == 0xc0 -> { require(p + 1 < b.size && ++jumps <= 32); if (!jumped) next = p + 2; p = ((n and 0x3f) shl 8) or (b[p + 1].toInt() and 255); jumped = true }
                n and 0xc0 != 0 -> error("invalid DNS label")
                else -> { require(n <= 63 && p + 1 + n <= b.size); labels.add(String(b, p + 1, n, Charsets.US_ASCII)); p += 1 + n }
            }
        }
        return Name(labels.joinToString("."), next)
    }

    private fun query(id: Int, name: String, type: Int): ByteArray {
        val out = ByteArrayOutputStream(); out.write(id ushr 8); out.write(id); out.write(1); out.write(0)
        out.write(0); out.write(1); out.write(0); out.write(0); out.write(0); out.write(0); out.write(0); out.write(1)
        val clean = name.trimEnd('.'); require(clean.isNotEmpty())
        for (part in clean.split('.')) { val bytes = part.toByteArray(Charsets.US_ASCII); require(bytes.isNotEmpty() && bytes.size <= 63); out.write(bytes.size); out.write(bytes) }
        out.write(0); out.write(type ushr 8); out.write(type); out.write(0); out.write(1)
        // OPT: root, type 41, class UDP payload 1232, TTL extended-rcode/version/flags all zero, no options.
        out.write(0); out.write(0); out.write(41); out.write(4); out.write(0xD0); out.write(0); out.write(0); out.write(0); out.write(0); out.write(0); out.write(0)
        return out.toByteArray()
    }

    private fun elapsed(start: Long) = ((System.nanoTime() - start) / 1_000_000L).toInt().coerceAtLeast(0)
    private fun u16(b: ByteArray, p: Int) = ((b[p].toInt() and 255) shl 8) or (b[p + 1].toInt() and 255)
    private fun u32(b: ByteArray, p: Int) = ((b[p].toLong() and 255) shl 24) or ((b[p + 1].toLong() and 255) shl 16) or ((b[p + 2].toLong() and 255) shl 8) or (b[p + 3].toLong() and 255)
    private fun randomLabel() = "${java.lang.Long.toUnsignedString(random.nextLong(), 16)}-${java.lang.Long.toUnsignedString(random.nextLong(), 16)}.invalid"
    private fun isNumericIp(s: String): Boolean {
        if (s.contains(':')) return false // IPv4-only resolver discovery.
        val p = s.split('.')
        return p.size == 4 && p.all { it.matches(Regex("0|[1-9][0-9]{0,2}")) && (it.toIntOrNull() ?: 256) <= 255 }
    }
    private fun numericAddress(s: String): InetAddress { require(isNumericIp(s)); return InetAddress.getByName(s) }
}
