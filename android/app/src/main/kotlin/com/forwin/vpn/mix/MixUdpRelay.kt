package com.forwin.vpn.mix

import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket

/** Mix-only UDP-over-TLS compatibility layer. Every remote TCP socket is opened
 * through the exact preceding SOCKS prefix, never through a physical fallback.
 * A configured, authenticated remote relay is required: TCP-only servers cannot
 * turn into UDP exits through a client-side flag alone.
 */
internal class MixUdpRelay(
    private val config: Config,
    private val listenPort: Int,
    private val upstreamPort: Int,
    private val sslContext: SSLContext = SSLContext.getDefault(),
) : AutoCloseable {
    data class Config(val host: String, val port: Int, val token: String, val serverName: String) {
        init {
            require(host.isNotBlank() && host.length <= 253 && host.none { it.isWhitespace() || it == '/' || it == '\u0000' }) { "Invalid Mix relay host" }
            require(port in 1..65535) { "Invalid Mix relay port" }
            require(token.length in 32..256 && token.all { it.code in 33..126 }) { "Mix relay token must contain 32 to 256 printable non-space ASCII characters" }
            require(serverName.isNotBlank() && serverName.length <= 253 && serverName.none { it.isWhitespace() || it == '/' || it == '\u0000' }) { "Invalid Mix relay TLS server name" }
        }
        // Do not expose authentication material in diagnostics or data-class logs.
        override fun toString(): String = "MixUdpRelay.Config([redacted])"
        companion object {
            fun fromJson(json: JSONObject): Config = Config(
                json.getString("host"), json.getInt("port"), json.getString("token"),
                json.optString("serverName").ifBlank { json.getString("host") },
            )
        }
    }

    private val stopped = AtomicBoolean(false)
    private val slots = Semaphore(32)
    private val resources = ConcurrentHashMap.newKeySet<AutoCloseable>()
    private val threads = Executors.newCachedThreadPool { task ->
        Thread(task, "mix-udp-relay").apply { isDaemon = true }
    }
    private var listener: ServerSocket? = null
    private fun <T : AutoCloseable> own(resource: T): T {
        resources.add(resource)
        if (stopped.get()) { resource.close(); resources.remove(resource); throw EOFException("Mix relay stopped") }
        return resource
    }
    private fun release(resource: AutoCloseable?) {
        if (resource != null) { runCatching { resource.close() }; resources.remove(resource) }
    }

    /** Call only once the raw prefix is ready; validates TLS/auth before UDP is advertised. */
    fun start() {
        check(!stopped.get() && listener == null) { "Mix relay already started or stopped" }
        require(listenPort in 1..65535 && upstreamPort in 1..65535 && listenPort != upstreamPort)
        openRelay().let { release(it) }
        val server = own(ServerSocket(listenPort, 32, InetAddress.getByName("127.0.0.1")))
        listener = server
        threads.execute {
            while (!stopped.get()) {
                val client = try { own(server.accept()) } catch (_: Exception) { break }
                if (!slots.tryAcquire()) { release(client); continue }
                try {
                    threads.execute {
                        try { serve(client) } catch (_: Exception) { /* Session fails closed. */ }
                        finally { release(client); slots.release() }
                    }
                } catch (_: Exception) { release(client); slots.release() }
            }
        }
    }

    private fun serve(client: Socket) {
        client.soTimeout = 15_000
        client.tcpNoDelay = true
        val input = DataInputStream(client.getInputStream())
        val output = DataOutputStream(client.getOutputStream())
        if (input.readUnsignedByte() != 5) return
        val methods = ByteArray(input.readUnsignedByte()).also { input.readFully(it) }
        if (!methods.contains(0.toByte())) { output.write(byteArrayOf(5, -1)); output.flush(); return }
        output.write(byteArrayOf(5, 0)); output.flush()
        if (input.readUnsignedByte() != 5) return
        val command = input.readUnsignedByte()
        if (input.readUnsignedByte() != 0) return
        val address = readAddress(input)
        when (command) {
            1 -> {
                var remote: Socket? = null
                var connectedReply = false
                try {
                    remote = openSocks(address)
                    reply(output, 0, 0)
                    connectedReply = true
                    client.soTimeout = 0
                    remote.soTimeout = 0
                    val connected = remote
                    val downstream = threads.submit {
                        try { connected.getInputStream().copyTo(client.getOutputStream()) }
                        catch (_: Exception) { }
                        finally {
                            runCatching { client.shutdownOutput() }
                            // Remote EOF also wakes a client upload that would
                            // otherwise keep a connection slot forever.
                            runCatching { client.shutdownInput() }
                        }
                    }
                    client.getInputStream().copyTo(remote.getOutputStream())
                    runCatching { remote.shutdownOutput() }
                    // EOF of the upload is a half-close, not cancellation of
                    // a delayed response. Bound only this draining phase.
                    downstream.get(30, TimeUnit.SECONDS)
                } catch (_: Exception) {
                    if (!connectedReply) runCatching { reply(output, 1, 0) }
                }
                finally { release(remote) }
            }
            3 -> serveUdp(client, input, output)
            else -> reply(output, 7, 0)
        }
    }

    private fun serveUdp(client: Socket, control: DataInputStream, output: DataOutputStream) {
        val udp = own(DatagramSocket(InetSocketAddress("127.0.0.1", 0)))
        var tls: SSLSocket? = null
        try {
            tls = openRelay()
            val relay = tls
            val associationClosed = AtomicBoolean(false)
            fun closeAssociation() {
                if (associationClosed.compareAndSet(false, true)) {
                    release(udp); release(relay); release(client)
                }
            }
            reply(output, 0, udp.localPort)
            client.soTimeout = 0
            relay.soTimeout = 90_000
            // The first valid loopback sender pins this association's UDP port.
            val sender = java.util.concurrent.atomic.AtomicReference<InetSocketAddress?>()
            threads.execute {
                try {
                    val stream = DataOutputStream(relay.getOutputStream())
                    val buffer = ByteArray(65535)
                    while (!stopped.get() && !associationClosed.get()) {
                        val packet = DatagramPacket(buffer, buffer.size)
                        udp.receive(packet)
                        if (packet.address != client.inetAddress) continue
                        val source = InetSocketAddress(packet.address, packet.port)
                        val pinned = sender.get()
                        if (pinned != null && pinned != source) continue
                        if (!validDatagram(buffer, packet.length)) continue
                        sender.compareAndSet(null, source)
                        stream.writeShort(packet.length)
                        stream.write(buffer, 0, packet.length)
                        stream.flush()
                    }
                } catch (_: Exception) { }
                finally { closeAssociation() }
            }
            threads.execute {
                try {
                    val stream = DataInputStream(relay.getInputStream())
                    while (!stopped.get() && !associationClosed.get()) {
                        val size = stream.readUnsignedShort()
                        require(size in 10..65529) { "Invalid Mix UDP frame length" }
                        val frame = ByteArray(size).also { stream.readFully(it) }
                        require(validDatagram(frame, size)) { "Invalid Mix UDP frame" }
                        val destination = sender.get() ?: continue
                        udp.send(DatagramPacket(frame, frame.size, destination))
                    }
                } catch (_: Exception) { }
                finally { closeAssociation() }
            }
            try { while (control.read() >= 0) { /* Control must remain open. */ } }
            finally { closeAssociation() }
        } finally { release(tls); release(udp) }
    }

    private fun openRelay(): SSLSocket {
        val address = encodeAddress(config.host, config.port)
        val plain = openSocks(address)
        var tls: SSLSocket? = null
        try {
            tls = own(sslContext.socketFactory.createSocket(plain, config.serverName, config.port, true) as SSLSocket)
            tls.soTimeout = 15_000
            tls.sslParameters = tls.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
            tls.enabledProtocols = tls.supportedProtocols.filter { it == "TLSv1.2" || it == "TLSv1.3" }.toTypedArray()
            tls.startHandshake()
            val output = DataOutputStream(tls.getOutputStream())
            val token = config.token.toByteArray(Charsets.US_ASCII)
            output.write("4WUD1".toByteArray(Charsets.US_ASCII)); output.writeShort(token.size)
            output.write(token); output.flush()
            check(tls.getInputStream().read() == 0) { "Mix UDP relay authentication rejected" }
            // SSL owns plain; do not retain a second resource for every session.
            resources.remove(plain)
            return tls
        } catch (error: Exception) { release(tls); release(plain); throw error }
    }

    private fun openSocks(address: ByteArray): Socket {
        val socket = own(Socket())
        try {
            socket.connect(InetSocketAddress("127.0.0.1", upstreamPort), 10_000)
            socket.soTimeout = 15_000; socket.tcpNoDelay = true
            val output = DataOutputStream(socket.getOutputStream())
            val input = DataInputStream(socket.getInputStream())
            output.write(byteArrayOf(5, 1, 0)); output.flush()
            require(input.readUnsignedByte() == 5 && input.readUnsignedByte() == 0) { "Mix prefix SOCKS authentication failed" }
            output.write(byteArrayOf(5, 1, 0)); output.write(address); output.flush()
            require(input.readUnsignedByte() == 5 && input.readUnsignedByte() == 0 && input.readUnsignedByte() == 0) { "Mix prefix SOCKS connect failed" }
            readAddress(input)
            return socket
        } catch (error: Exception) { release(socket); throw error }
    }

    override fun close() {
        if (!stopped.compareAndSet(false, true)) return
        resources.toList().forEach { release(it) }
        threads.shutdownNow()
    }

    companion object {
        private fun reply(output: DataOutputStream, status: Int, port: Int) {
            output.write(byteArrayOf(5, status.toByte(), 0, 1, 127, 0, 0, 1))
            output.writeShort(port); output.flush()
        }
        private fun readAddress(input: DataInputStream): ByteArray {
            val kind = input.readUnsignedByte()
            val size = when (kind) { 1 -> 4; 4 -> 16; 3 -> input.readUnsignedByte(); else -> error("Invalid SOCKS address") }
            require(size > 0) { "Empty SOCKS hostname" }
            val data = ByteArray(size + 2).also { input.readFully(it) }
            return if (kind == 3) byteArrayOf(3, size.toByte()) + data else byteArrayOf(kind.toByte()) + data
        }
        private fun encodeAddress(host: String, port: Int): ByteArray {
            // IPv6 is a literal; other hostnames are forwarded as SOCKS names,
            // avoiding local DNS and retaining the prefix's resolver policy.
            val raw = host.removePrefix("[").removeSuffix("]")
            val ip = when {
                raw.contains(':') -> InetAddress.getByName(raw).address
                raw.matches(Regex("(?:[0-9]{1,3}\\.){3}[0-9]{1,3}")) -> {
                    val pieces = raw.split('.').map { it.toInt() }
                    require(pieces.all { it in 0..255 })
                    pieces.map { it.toByte() }.toByteArray()
                }
                else -> null
            }
            val address = if (ip != null) byteArrayOf(if (ip.size == 4) 1 else 4) + ip else {
                val name = java.net.IDN.toASCII(raw).toByteArray(Charsets.US_ASCII)
                require(name.size in 1..253) { "Invalid Mix relay hostname" }
                byteArrayOf(3, name.size.toByte()) + name
            }
            return address + byteArrayOf((port ushr 8).toByte(), port.toByte())
        }
        private fun validDatagram(frame: ByteArray, size: Int): Boolean {
            if (size < 10 || size > 65529 || frame[0] != 0.toByte() || frame[1] != 0.toByte() || frame[2] != 0.toByte()) return false
            val offset = when (frame[3].toInt() and 255) {
                1 -> 10
                4 -> 22
                3 -> if (size >= 5) 7 + (frame[4].toInt() and 255) else return false
                else -> return false
            }
            return offset <= size && (frame[offset - 2] != 0.toByte() || frame[offset - 1] != 0.toByte())
        }
    }
}
