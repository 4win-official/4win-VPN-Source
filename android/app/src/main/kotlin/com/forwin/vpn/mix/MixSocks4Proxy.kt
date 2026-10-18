package com.forwin.vpn.mix

import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.net.IDN
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Mix-only SOCKS5 CONNECT frontend for a real SOCKS4/SOCKS4a upstream.
 * Domain names are passed to SOCKS4a, never resolved on a physical fallback.
 */
internal class MixSocks4Proxy(
    private val listenPort: Int,
    private val proxyHost: String,
    private val proxyPort: Int,
    private val userId: String,
    private val upstreamSocksPort: Int? = null,
) : Closeable {
    private val closed = AtomicBoolean(false)
    private val resources = ConcurrentHashMap.newKeySet<Closeable>()
    private val permits = Semaphore(64)
    private val pool = Executors.newCachedThreadPool { task ->
        Thread(task, "mix-socks4").apply { isDaemon = true }
    }
    private var server: ServerSocket? = null
    val boundPort: Int get() = server?.localPort ?: 0

    private fun <T : Closeable> own(resource: T): T {
        resources.add(resource)
        if (closed.get()) { release(resource); throw EOFException("Mix SOCKS4 stopped") }
        return resource
    }
    private fun release(resource: Closeable?) {
        if (resource != null) { runCatching { resource.close() }; resources.remove(resource) }
    }

    fun start() {
        check(server == null && !closed.get()) { "Mix SOCKS4 already started or stopped" }
        require(listenPort in 1..65535 && proxyPort in 1..65535 &&
            (upstreamSocksPort == null || upstreamSocksPort in 1..65535)) { "Invalid Mix SOCKS4 port" }
        require(proxyHost.isNotBlank() && proxyHost.none { it.isWhitespace() || it == '\u0000' }) { "Invalid Mix SOCKS4 host" }
        require(userId.length <= 255 && userId.all { it.code in 1..255 }) { "Invalid Mix SOCKS4 user ID" }
        val listener = own(ServerSocket(listenPort, 64, InetAddress.getByName("127.0.0.1")))
        server = listener
        pool.execute {
            while (!closed.get()) {
                val client = try { own(listener.accept()) } catch (_: Exception) { break }
                if (!permits.tryAcquire()) { release(client); continue }
                try {
                    pool.execute {
                        try { serve(client) } catch (_: Exception) { }
                        finally { release(client); permits.release() }
                    }
                } catch (_: Exception) { release(client); permits.release() }
            }
        }
    }

    private fun serve(client: Socket) {
        client.soTimeout = TIMEOUT
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
        if (command != 1) { reply(output, 7); return }
        val kind = input.readUnsignedByte()
        if (kind == 4) { reply(output, 8); return }
        val target = when (kind) {
            1 -> ByteArray(4).also { input.readFully(it) }
            3 -> ByteArray(input.readUnsignedByte()).also { input.readFully(it) }
            else -> { reply(output, 8); return }
        }
        val port = input.readUnsignedShort()
        if (port == 0 || target.isEmpty()) { reply(output, 1); return }
        var remote: Socket? = null
        var replied = false
        try {
            remote = openRemote()
            val remoteInput = DataInputStream(remote.getInputStream())
            val remoteOutput = DataOutputStream(remote.getOutputStream())
            remoteOutput.write(byteArrayOf(4, 1)); remoteOutput.writeShort(port)
            if (kind == 1) remoteOutput.write(target) else remoteOutput.write(byteArrayOf(0, 0, 0, 1))
            remoteOutput.write(userId.toByteArray(Charsets.ISO_8859_1)); remoteOutput.writeByte(0)
            if (kind == 3) {
                val host = String(target, Charsets.US_ASCII)
                require(host.none { it == '\u0000' || it.isWhitespace() || it == ':' }) { "Invalid SOCKS4a destination" }
                val ascii = IDN.toASCII(host).toByteArray(Charsets.US_ASCII)
                require(ascii.size in 1..253) { "Invalid SOCKS4a hostname" }
                remoteOutput.write(ascii); remoteOutput.writeByte(0)
            }
            remoteOutput.flush()
            val response = ByteArray(8).also { remoteInput.readFully(it) }
            require(response[0].toInt() in setOf(0, 4) && (response[1].toInt() and 255) == 90) { "SOCKS4 server refused CONNECT" }
            reply(output, 0); replied = true
            client.soTimeout = 0; remote.soTimeout = 0
            val connected = remote
            val downstream = pool.submit {
                try { connected.getInputStream().copyTo(client.getOutputStream()) }
                catch (_: Exception) { }
                finally {
                    runCatching { client.shutdownOutput() }
                    runCatching { client.shutdownInput() }
                }
            }
            client.getInputStream().copyTo(remote.getOutputStream())
            runCatching { remote.shutdownOutput() }
            downstream.get(30, TimeUnit.SECONDS)
        } catch (_: Exception) {
            if (!replied) runCatching { reply(output, 1) }
        } finally { release(remote) }
    }

    private fun openRemote(): Socket {
        val socket = own(Socket())
        try {
            socket.soTimeout = TIMEOUT; socket.tcpNoDelay = true
            if (upstreamSocksPort == null) {
                socket.connect(InetSocketAddress(proxyHost, proxyPort), TIMEOUT)
            } else {
                socket.connect(InetSocketAddress("127.0.0.1", upstreamSocksPort), TIMEOUT)
                val input = DataInputStream(socket.getInputStream())
                val output = DataOutputStream(socket.getOutputStream())
                output.write(byteArrayOf(5, 1, 0)); output.flush()
                require(input.readUnsignedByte() == 5 && input.readUnsignedByte() == 0) { "SOCKS4 prefix authentication failed" }
                val literal = proxyHost.removePrefix("[").removeSuffix("]")
                val address = if (literal.contains(':')) {
                    val ip = InetAddress.getByName(literal).address
                    byteArrayOf(if (ip.size == 4) 1 else 4) + ip
                } else {
                    val host = IDN.toASCII(proxyHost).toByteArray(Charsets.US_ASCII)
                    require(host.size in 1..253)
                    byteArrayOf(3, host.size.toByte()) + host
                }
                output.write(byteArrayOf(5, 1, 0)); output.write(address)
                output.writeShort(proxyPort); output.flush()
                require(input.readUnsignedByte() == 5 && input.readUnsignedByte() == 0 && input.readUnsignedByte() == 0) { "SOCKS4 prefix CONNECT failed" }
                val size = when (input.readUnsignedByte()) {
                    1 -> 4; 4 -> 16; 3 -> input.readUnsignedByte()
                    else -> error("Invalid SOCKS4 prefix address")
                }
                require(size > 0)
                input.readFully(ByteArray(size + 2))
            }
            return socket
        } catch (failure: Exception) { release(socket); throw failure }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        resources.toList().forEach { release(it) }
        pool.shutdownNow()
    }

    companion object {
        private const val TIMEOUT = 10_000
        private fun reply(output: DataOutputStream, status: Int) {
            output.write(byteArrayOf(5, status.toByte(), 0, 1, 127, 0, 0, 1, 0, 0)); output.flush()
        }
    }
}
