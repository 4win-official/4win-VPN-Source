package com.forwin.vpn.mix

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * Proves remote egress through one exact Mix prefix. The only socket dialed by
 * this process is the loopback SOCKS listener; the requested host is sent as a
 * SOCKS5 domain, and there is deliberately no direct-network fallback.
 */
internal object MixEgressProbe {
    const val TRACE_URL = "https://www.cloudflare.com/cdn-cgi/trace"
    private const val HOST = "www.cloudflare.com"
    private const val PATH = "/cdn-cgi/trace"
    private const val PORT = 443
    private const val MAX_RESPONSE_BYTES = 16 * 1024
    private const val MAX_HEADER_BYTES = 8 * 1024

    data class Result(val ip: String, val warp: String?, val elapsedMillis: Long)

    fun fetch(listenPort: Int, timeoutMillis: Int = 8_000): Result {
        require(listenPort in 1..65535) { "Invalid Mix egress probe port" }
        require(timeoutMillis in 1..30_000) { "Invalid Mix egress probe timeout" }
        val startedAt = System.nanoTime()
        val deadline = startedAt + TimeUnit.MILLISECONDS.toNanos(timeoutMillis.toLong())
        try {
            Socket().use { proxySocket ->
                proxySocket.connect(InetSocketAddress("127.0.0.1", listenPort), remainingMillis(deadline))
                proxySocket.soTimeout = remainingMillis(deadline)
                val input = proxySocket.getInputStream()
                val output = proxySocket.getOutputStream()

                // SOCKS5 no-auth negotiation.
                output.write(byteArrayOf(5, 1, 0))
                output.flush()
                val greeting = readExactly(input, 2)
                check(greeting[0].toInt() == 5 && greeting[1].toInt() == 0) {
                    "Mix prefix rejected SOCKS5 egress verification"
                }

                // Send the hostname in the SOCKS request so resolution remains
                // inside the selected prefix instead of using the phone's DNS.
                val host = HOST.toByteArray(StandardCharsets.US_ASCII)
                require(host.size in 1..255) { "Invalid egress verification host" }
                output.write(byteArrayOf(5, 1, 0, 3, host.size.toByte()))
                output.write(host)
                output.write(byteArrayOf((PORT ushr 8).toByte(), PORT.toByte()))
                output.flush()
                val reply = readExactly(input, 4)
                check(reply[0].toInt() == 5) { "Invalid SOCKS5 reply from Mix prefix" }
                check(reply[1].toInt() == 0) {
                    "Mix prefix could not reach Cloudflare trace (SOCKS status ${reply[1].toInt()})"
                }
                when (reply[3].toInt()) {
                    1 -> readExactly(input, 6)
                    3 -> readExactly(input, (readExactly(input, 1)[0].toInt() and 0xff) + 2)
                    4 -> readExactly(input, 18)
                    else -> error("Invalid SOCKS5 address type from Mix prefix")
                }
                proxySocket.soTimeout = remainingMillis(deadline)

                val ssl = (SSLSocketFactory.getDefault() as SSLSocketFactory)
                    .createSocket(proxySocket, HOST, PORT, true) as SSLSocket
                ssl.use { tls ->
                    tls.soTimeout = remainingMillis(deadline)
                    tls.sslParameters = tls.sslParameters.apply {
                        serverNames = listOf(SNIHostName(HOST))
                        endpointIdentificationAlgorithm = "HTTPS"
                    }
                    tls.startHandshake()
                    tls.getOutputStream().write(
                        ("GET $PATH HTTP/1.1\r\n" +
                            "Host: $HOST\r\n" +
                            "Accept: text/plain\r\n" +
                            "Connection: close\r\n\r\n").toByteArray(StandardCharsets.US_ASCII)
                    )
                    tls.getOutputStream().flush()
                    val traceBody = readHttpBody(tls.getInputStream(), deadline)
                    val trace = parseTrace(traceBody)
                    return Result(trace.ip, trace.warp, TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt))
                }
            }
        } catch (error: Throwable) {
            if (error is InterruptedException) Thread.currentThread().interrupt()
            throw IllegalStateException(
                "Cloudflare egress verification failed: ${error.message ?: error.javaClass.simpleName}",
                error
            )
        }
    }

    internal data class Trace(val ip: String, val warp: String?)

    internal fun parseTrace(body: String): Trace {
        val fields = body.lineSequence().mapNotNull { line ->
            val separator = line.indexOf('=')
            if (separator <= 0) null else line.substring(0, separator) to line.substring(separator + 1).trim()
        }.toMap()
        val rawIp = fields["ip"]?.trim().orEmpty()
        require(isValidPublicIp(rawIp)) { "Cloudflare trace did not return a valid public egress IP" }
        return Trace(rawIp, fields["warp"]?.lowercase())
    }

    internal fun requireWarpOn(warp: String?, ip: String) {
        check(warp == "on") {
            "Cloudflare did not confirm WARP (warp=${warp ?: "missing"}; exit IP $ip)"
        }
    }

    private fun isValidPublicIp(value: String): Boolean {
        if (value.isBlank() || value.any { it !in "0123456789abcdefABCDEF:." }) return false
        val address = if (value.contains(':')) {
            runCatching { InetAddress.getByName(value) }.getOrNull()
        } else {
            val parts = value.split('.')
            if (parts.size != 4 || parts.any { part -> part.isEmpty() || part.any { !it.isDigit() } }) return false
            val octets = parts.map { it.toIntOrNull()?.takeIf { octet -> octet in 0..255 } ?: return false }
            runCatching { InetAddress.getByAddress(octets.map { it.toByte() }.toByteArray()) }.getOrNull()
        } ?: return false
        if (address !is Inet4Address && address !is Inet6Address) return false
        if (address.isAnyLocalAddress || address.isLoopbackAddress || address.isLinkLocalAddress ||
            address.isSiteLocalAddress || address.isMulticastAddress) return false
        if (address is Inet4Address) {
            val b = address.address.map { it.toInt() and 0xff }
            if (b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224 ||
                (b[0] == 169 && b[1] == 254) || (b[0] == 172 && b[1] in 16..31) ||
                (b[0] == 192 && b[1] == 168) || (b[0] == 100 && b[1] in 64..127) ||
                (b[0] == 198 && b[1] in 18..19) ||
                (b[0] == 192 && b[1] == 0 && b[2] == 2) ||
                (b[0] == 198 && b[1] == 51 && b[2] == 100) ||
                (b[0] == 203 && b[1] == 0 && b[2] == 113)) return false
        } else if (address is Inet6Address) {
            // Cloudflare should report a globally scoped IPv6 address, not ULA.
            if ((address.address[0].toInt() and 0xe0) != 0x20) return false
        }
        return true
    }

    private fun readHttpBody(input: InputStream, deadline: Long): String {
        var headerBytes = 0
        val status = readAsciiLine(input, deadline).also { headerBytes += it.length + 2 }
        check(status.startsWith("HTTP/1.") && status.substringAfter(' ', "").take(3) == "200") {
            "Cloudflare trace returned an unsuccessful HTTP response"
        }
        val headers = LinkedHashMap<String, String>()
        while (true) {
            val line = readAsciiLine(input, deadline)
            headerBytes += line.length + 2
            check(headerBytes <= MAX_HEADER_BYTES) { "Cloudflare trace response headers are too large" }
            if (line.isEmpty()) break
            val separator = line.indexOf(':')
            if (separator > 0) headers[line.substring(0, separator).trim().lowercase()] =
                line.substring(separator + 1).trim()
        }
        val body = when {
            headers["transfer-encoding"]?.contains("chunked", ignoreCase = true) == true -> readChunked(input, deadline)
            headers["content-length"] != null -> {
                val length = headers.getValue("content-length").toIntOrNull()
                    ?: error("Invalid Cloudflare trace content length")
                require(length in 1..MAX_RESPONSE_BYTES) { "Cloudflare trace response is empty or too large" }
                readExactly(input, length)
            }
            else -> readUntilEof(input, deadline)
        }
        return String(body, StandardCharsets.UTF_8)
    }

    private fun readChunked(input: InputStream, deadline: Long): ByteArray {
        val output = ByteArrayOutputStream()
        while (true) {
            val sizeLine = readAsciiLine(input, deadline).substringBefore(';').trim()
            val size = sizeLine.toLongOrNull(16) ?: error("Invalid chunk in Cloudflare trace response")
            if (size == 0L) {
                while (readAsciiLine(input, deadline).isNotEmpty()) Unit
                break
            }
            require(size in 1..MAX_RESPONSE_BYTES.toLong() && output.size().toLong() + size <= MAX_RESPONSE_BYTES) {
                "Cloudflare trace response is too large"
            }
            output.write(readExactly(input, size.toInt()))
            check(readExactly(input, 2).contentEquals(byteArrayOf(13, 10))) {
                "Invalid Cloudflare trace chunk delimiter"
            }
        }
        return output.toByteArray()
    }

    private fun readUntilEof(input: InputStream, deadline: Long): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(1024)
        while (true) {
            remainingMillis(deadline)
            val count = input.read(buffer)
            if (count < 0) break
            require(output.size() + count <= MAX_RESPONSE_BYTES) { "Cloudflare trace response is too large" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun readAsciiLine(input: InputStream, deadline: Long): String {
        val output = ByteArrayOutputStream()
        while (output.size() <= MAX_HEADER_BYTES) {
            remainingMillis(deadline)
            val next = input.read()
            if (next < 0) break
            if (next == 10) break
            if (next != 13) output.write(next)
        }
        check(output.size() <= MAX_HEADER_BYTES) { "Cloudflare trace response line is too large" }
        return String(output.toByteArray(), StandardCharsets.US_ASCII)
    }

    private fun readExactly(input: InputStream, length: Int): ByteArray {
        require(length in 0..MAX_RESPONSE_BYTES) { "Invalid Mix egress probe response length" }
        val bytes = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val count = input.read(bytes, offset, length - offset)
            check(count >= 0) { "Unexpected end of Mix egress probe response" }
            offset += count
        }
        return bytes
    }

    private fun remainingMillis(deadline: Long): Int {
        val remaining = deadline - System.nanoTime()
        check(remaining > 0) { "Mix egress verification timed out" }
        return TimeUnit.NANOSECONDS.toMillis(remaining).coerceAtLeast(1).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }
}
