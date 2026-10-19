package com.forwin.vpn.dnsscan

import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Strict, protocol-only DNS capability scanner. It does not authenticate a tunnel. */
object DnsResolverScanner {
    private const val DEFAULT_TIMEOUT_MS = 2500
    private const val MAX_TIMEOUT_MS = 10000
    private const val MAX_PACKET = 4096
    private const val MAX_PARALLEL = 64
    private const val MAX_INPUT = 200000
    private const val EDNS_PAYLOAD = 1232
    private const val A = 1
    private const val PTR = 12
    private const val TXT = 16
    private const val CNAME = 5
    private const val IN = 1
    private val random = SecureRandom()

    fun scan(ips: List<String>, domain: String, parallel: Int, port: Int = 53,
             timeoutMs: Int = DEFAULT_TIMEOUT_MS): String {
        require(port in 1..65535)
        val target = targetOf(domain)
        val timeout = timeoutMs.coerceIn(100, MAX_TIMEOUT_MS)
        val targets = ips.asSequence().map(String::trim).filter(::isNumericIp)
            .distinct().take(MAX_INPUT).toList()
        val workers = parallel.coerceIn(1, MAX_PARALLEL)
        val executor = Executors.newFixedThreadPool(workers)
        val pending = ArrayDeque<Pair<String, java.util.concurrent.Future<String>>>()
        val out = JSONArray()
        try {
            for (ip in targets) {
                pending.add(ip to executor.submit<String> {
                    scanEndpoint(ip, target, port, port, timeout)
                })
                if (pending.size >= workers) {
                    val item = pending.removeFirst()
                    out.put(JSONObject(getSafely(item.second, item.first)))
                }
            }
            while (pending.isNotEmpty()) {
                val item = pending.removeFirst()
                out.put(JSONObject(getSafely(item.second, item.first)))
            }
        } finally {
            executor.shutdownNow()
            executor.awaitTermination(1, TimeUnit.SECONDS)
        }
        return out.toString()
    }

    internal fun scanEndpoint(ip: String, domain: String, udpPort: Int, tcpPort: Int,
                              timeoutMs: Int = DEFAULT_TIMEOUT_MS): String =
        scanEndpoint(ip, targetOf(domain), udpPort, tcpPort, timeoutMs)

    private fun scanEndpoint(ip: String, target: Target, udpPort: Int, tcpPort: Int,
                             timeoutMs: Int): String {
        val address = try { numericAddress(ip) } catch (_: Exception) {
            return base(ip).toString()
        }
        var udpTxt: Reply? = null
        var tcpTxt: Reply? = null
        try { udpTxt = queryUdp(address, udpPort, target.name, TXT, timeoutMs) } catch (_: Exception) { }
        try { tcpTxt = queryTcp(address, tcpPort, target.name, TXT, timeoutMs) } catch (_: Exception) { }

        var udpTarget: Reply? = null
        try { udpTarget = queryUdp(address, udpPort, target.name, target.type, timeoutMs) } catch (_: Exception) { }
        var tcpTarget: Reply? = null
        try { tcpTarget = queryTcp(address, tcpPort, target.name, target.type, timeoutMs) } catch (_: Exception) { }

        var udpNx: Reply? = null
        var nx: Reply? = null
        if (udpTxt != null) {
            try { udpNx = queryUdp(address, udpPort, randomLabel(), A, timeoutMs); nx = udpNx } catch (_: Exception) { }
        }
        if (nx == null && tcpTxt != null) {
            try { nx = queryTcp(address, tcpPort, randomLabel(), A, timeoutMs) } catch (_: Exception) { }
        }
        val replies = listOfNotNull(udpTxt, tcpTxt, udpTarget, tcpTarget, nx)
        val edns = replies.firstOrNull { it.edns }
        return base(ip)
            .put("udpMs", udpTxt?.ms ?: -1)
            .put("tcpMs", tcpTxt?.ms ?: -1)
            .put("reachable", replies.isNotEmpty())
            .put("targetResolved", udpTarget?.targetResolved == true || tcpTarget?.targetResolved == true)
            .put("txtSupported", udpTxt?.txt == true || tcpTxt?.txt == true)
            .put("responseBytes", replies.maxOfOrNull { it.bytes } ?: 0)
            .put("ednsSupported", edns != null)
            .put("ednsPayload", edns?.payload ?: EDNS_PAYLOAD)
            .put("nxdomainSafe", nx?.rcode == 3)
            .put("nxdomainHijacked", nx != null && nx.rcode != 3)
            .put("tunnelCandidate", udpTxt != null && udpTxt.edns &&
                udpTarget?.targetResolved == true && udpNx?.rcode == 3)
            .toString()
    }

    private fun base(ip: String) = JSONObject()
        .put("ip", ip).put("udpMs", -1).put("tcpMs", -1)
        .put("reachable", false).put("targetResolved", false)
        .put("txtSupported", false).put("responseBytes", 0)
        .put("ednsSupported", false).put("ednsPayload", EDNS_PAYLOAD)
        .put("nxdomainSafe", false).put("nxdomainHijacked", false)
        .put("tunnelCandidate", false).put("tunnelVerified", false)

    private fun getSafely(f: java.util.concurrent.Future<String>, ip: String) =
        try { f.get() } catch (_: Exception) { base(ip).toString() }

    private data class Target(val name: String, val type: Int)

    private fun targetOf(raw: String): Target {
        val s = raw.trim()
        require(s.isNotEmpty() && !s.contains('/') && !s.contains(':') && !s.contains(' '))
        if (isNumericIp(s)) {
            return Target(s.split('.').reversed().joinToString(".") + ".in-addr.arpa", PTR)
        }
        require(validName(s) && !s.matches(Regex("[0-9.]+")))
        return Target(s.lowercase(), A)
    }

    private fun validName(s: String): Boolean {
        if (s.isEmpty() || s.length > 253 || s.endsWith('.')) return false
        return s.split('.').all { label ->
            label.length in 1..63 && label.first() != '-' && label.last() != '-' &&
                label.all { c -> c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '-' }
        }
    }

    private fun isNumericIp(s: String): Boolean {
        val parts = s.split('.')
        return parts.size == 4 && parts.all { it.matches(Regex("0|[1-9][0-9]{0,2}")) &&
            (it.toIntOrNull() ?: 256) <= 255 }
    }

    private fun numericAddress(s: String): InetAddress { require(isNumericIp(s)); return InetAddress.getByName(s) }

    private data class Reply(val ms: Int, val bytes: Int, val txt: Boolean, val edns: Boolean,
                             val rcode: Int, val payload: Int, val targetResolved: Boolean)
    internal data class ParsedReply(val txt: Boolean, val edns: Boolean, val rcode: Int,
                                    val answerCount: Int, val payload: Int,
                                    val targetResolved: Boolean = false)
    internal fun validate(message: ByteArray, id: Int, name: String, type: Int,
                          truncatedAllowed: Boolean = false): ParsedReply =
        parse(message, id, name, type, truncatedAllowed)

    private fun queryUdp(address: InetAddress, port: Int, name: String, type: Int, timeout: Int): Reply {
        val id = random.nextInt(65536)
        val packet = query(id, name, type)
        DatagramSocket().use { socket ->
            socket.soTimeout = timeout
            socket.connect(InetSocketAddress(address, port))
            val start = System.nanoTime()
            socket.send(DatagramPacket(packet, packet.size))
            val bytes = ByteArray(MAX_PACKET)
            val received = DatagramPacket(bytes, bytes.size)
            socket.receive(received)
            require(received.address == address && received.port == port)
            val parsed = parse(bytes.copyOf(received.length), id, name, type, false)
            return Reply(elapsed(start), received.length, parsed.txt, parsed.edns,
                parsed.rcode, parsed.payload, parsed.targetResolved)
        }
    }

    private fun queryTcp(address: InetAddress, port: Int, name: String, type: Int, timeout: Int): Reply {
        val id = random.nextInt(65536)
        val packet = query(id, name, type)
        Socket().use { socket ->
            socket.soTimeout = timeout
            socket.connect(InetSocketAddress(address, port), timeout)
            val start = System.nanoTime()
            socket.getOutputStream().apply {
                write(packet.size ushr 8); write(packet.size); write(packet); flush()
            }
            val input = DataInputStream(DeadlineInputStream(socket,
                System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeout.toLong())))
            val length = input.readUnsignedShort()
            require(length in 12..MAX_PACKET)
            val answer = ByteArray(length)
            input.readFully(answer)
            val parsed = parse(answer, id, name, type, false)
            return Reply(elapsed(start), length, parsed.txt, parsed.edns,
                parsed.rcode, parsed.payload, parsed.targetResolved)
        }
    }

    private fun parse(message: ByteArray, id: Int, name: String, type: Int,
                      truncatedAllowed: Boolean): ParsedReply {
        require(message.size >= 12 && u16(message, 0) == id)
        val flags = u16(message, 2)
        require(flags and 0x8000 != 0 && flags and 0x7800 == 0 &&
            (truncatedAllowed || flags and 0x0200 == 0))
        val questions = u16(message, 4)
        val answers = u16(message, 6)
        val authorities = u16(message, 8)
        val additionals = u16(message, 10)
        require(questions == 1)
        var pos = 12
        val question = readName(message, pos)
        pos = question.next
        require(question.name.equals(name, ignoreCase = true))
        require(pos + 4 <= message.size && u16(message, pos) == type && u16(message, pos + 2) == IN)
        pos += 4

        var txt = false
        var edns = false
        var payload = 0
        var extendedRcode = 0
        val records = ArrayList<Record>()
        repeat(answers + authorities + additionals) { section ->
            val owner = readName(message, pos)
            pos = owner.next
            require(pos + 10 <= message.size)
            val recordType = u16(message, pos)
            val recordClass = u16(message, pos + 2)
            val ttl = u32(message, pos + 4)
            val length = u16(message, pos + 8)
            pos += 10
            require(length <= message.size - pos)
            if (recordType == 41) {
                require(section >= answers + authorities && owner.name.isEmpty() && !edns)
                require(recordClass >= 512 && ((ttl ushr 16) and 0xffffL) == 0L)
                parseOptions(message, pos, length)
                edns = true
                payload = recordClass
                extendedRcode = ((ttl ushr 24) and 0xffL).toInt()
            }
            if (recordType == TXT) {
                require(validTxt(message, pos, length))
                txt = true
            }
            if (section < answers) {
                var rdataName: String? = null
                if (recordType == A) require(length == 4)
                if (recordType == PTR || recordType == CNAME) {
                    val decoded = readName(message, pos)
                    require(decoded.next == pos + length)
                    rdataName = decoded.name
                }
                records.add(Record(owner.name, recordType, recordClass, pos, length, rdataName))
            }
            pos += length
        }
        require(pos == message.size)
        val finalRcode = (flags and 15) or (extendedRcode shl 4)
        require(finalRcode == 0 || finalRcode == 3)
        val wanted = name.lowercase()
        val resolved = finalRcode == 0 && positiveAnswer(message, records, wanted, type)
        return ParsedReply(txt, edns, finalRcode, answers, payload, resolved)
    }

    private data class Record(val owner: String, val type: Int, val recordClass: Int,
                             val start: Int, val length: Int, val rdataName: String?)

    private fun positiveAnswer(bytes: ByteArray, records: List<Record>, wanted: String, type: Int): Boolean {
        val aliases = HashSet<String>()
        aliases.add(wanted)
        var changed: Boolean
        do {
            changed = false
            for (record in records) {
                if (record.recordClass == IN && record.type == CNAME &&
                    record.owner.lowercase() in aliases && record.rdataName != null &&
                    aliases.add(record.rdataName.lowercase())) changed = true
            }
        } while (changed)
        return records.any { record ->
            record.recordClass == IN && record.type == type &&
                record.owner.lowercase() in aliases &&
                (type != PTR || !record.rdataName.isNullOrEmpty())
        }
    }

    private fun parseOptions(bytes: ByteArray, start: Int, length: Int) {
        var p = start
        val end = start + length
        while (p < end) {
            require(p + 4 <= end)
            val optionLength = u16(bytes, p + 2)
            p += 4
            require(optionLength <= end - p)
            p += optionLength
        }
        require(p == end)
    }

    private fun validTxt(bytes: ByteArray, start: Int, length: Int): Boolean {
        var p = start
        val end = start + length
        while (p < end) {
            val size = bytes[p++].toInt() and 255
            require(size <= end - p)
            p += size
        }
        return p == end
    }

    private data class Name(val name: String, val next: Int)
    private fun readName(bytes: ByteArray, start: Int): Name {
        require(start in bytes.indices)
        var p = start
        var next = start
        var jumped = false
        var jumps = 0
        val labels = ArrayList<String>()
        while (true) {
            require(p < bytes.size)
            val size = bytes[p].toInt() and 255
            when {
                size == 0 -> { p++; if (!jumped) next = p; break }
                size and 0xc0 == 0xc0 -> {
                    require(p + 1 < bytes.size && ++jumps <= 32)
                    if (!jumped) next = p + 2
                    p = ((size and 0x3f) shl 8) or (bytes[p + 1].toInt() and 255)
                    jumped = true
                }
                size and 0xc0 != 0 -> error("invalid DNS label")
                else -> {
                    require(size <= 63 && p + 1 + size <= bytes.size)
                    labels.add(String(bytes, p + 1, size, Charsets.US_ASCII))
                    p += 1 + size
                }
            }
        }
        return Name(labels.joinToString("."), next)
    }

    private fun query(id: Int, name: String, type: Int): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(id ushr 8); out.write(id); out.write(1); out.write(0)
        out.write(0); out.write(1); out.write(0); out.write(0); out.write(0); out.write(0)
        out.write(0); out.write(1)
        for (part in name.split('.')) {
            val bytes = part.toByteArray(Charsets.US_ASCII)
            require(bytes.isNotEmpty() && bytes.size <= 63)
            out.write(bytes.size); out.write(bytes)
        }
        out.write(0); out.write(type ushr 8); out.write(type); out.write(0); out.write(1)
        out.write(byteArrayOf(0, 0, 41, 4, 0xd0.toByte(), 0, 0, 0, 0, 0, 0))
        return out.toByteArray()
    }

    private fun elapsed(start: Long) =
        ((System.nanoTime() - start) / 1_000_000L).toInt().coerceAtLeast(0)
    private fun u16(bytes: ByteArray, pos: Int) =
        ((bytes[pos].toInt() and 255) shl 8) or (bytes[pos + 1].toInt() and 255)
    private fun u32(bytes: ByteArray, pos: Int) =
        ((bytes[pos].toLong() and 255) shl 24) or ((bytes[pos + 1].toLong() and 255) shl 16) or
            ((bytes[pos + 2].toLong() and 255) shl 8) or (bytes[pos + 3].toLong() and 255)
    private fun randomLabel() = "${java.lang.Long.toUnsignedString(random.nextLong(), 16)}-${java.lang.Long.toUnsignedString(random.nextLong(), 16)}.invalid"
}
