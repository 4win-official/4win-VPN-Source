package com.forwin.vpn.mix

import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class MixSocks4ProxyTest {
    private class Peer(handler: (Socket) -> Unit) : Closeable {
        val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
        private val pool = Executors.newSingleThreadExecutor { Thread(it, "socks4-test").apply { isDaemon = true } }
        val future: Future<*> = pool.submit { server.accept().use { it.soTimeout = 3000; handler(it) } }
        val port get() = server.localPort
        fun done() { future.get(5, TimeUnit.SECONDS) }
        override fun close() { server.close(); pool.shutdownNow() }
    }
    private fun port(): Int = ServerSocket(0).use { it.localPort }
    private fun connect(port: Int): Socket = Socket("127.0.0.1", port).apply {
        soTimeout = 4000
        getOutputStream().write(byteArrayOf(5, 1, 0))
        assertArrayEquals(byteArrayOf(5, 0), read(getInputStream(), 2))
    }
    private fun read(input: java.io.InputStream, n: Int): ByteArray = ByteArray(n).also { DataInputStream(input).readFully(it) }
    private fun cstring(input: DataInputStream): String = buildString {
        while (true) { val b = input.readUnsignedByte(); if (b == 0) break; append(b.toChar()); require(length <= 255) }
    }
    private fun request(socket: Socket, host: String, port: Int, ipv4: Boolean = false): Int {
        val out = DataOutputStream(socket.getOutputStream())
        out.write(byteArrayOf(5, 1, 0))
        if (ipv4) { out.writeByte(1); out.write(InetAddress.getByName(host).address) }
        else { out.writeByte(3); out.writeByte(host.length); out.write(host.toByteArray(Charsets.US_ASCII)) }
        out.writeShort(port); out.flush()
        return read(socket.getInputStream(), 10)[1].toInt() and 255
    }
    private fun checkRequest(socket: Socket, host: String, port: Int, user: String, ipv4: Boolean = false) {
        val input = DataInputStream(socket.getInputStream())
        assertEquals(4, input.readUnsignedByte()); assertEquals(1, input.readUnsignedByte())
        assertEquals(port, input.readUnsignedShort())
        val ip = read(input, 4)
        assertArrayEquals(if (ipv4) InetAddress.getByName(host).address else byteArrayOf(0, 0, 0, 1), ip)
        assertEquals(user, cstring(input))
        if (!ipv4) assertEquals(host, cstring(input))
    }
    private fun accept(socket: Socket) { socket.getOutputStream().write(byteArrayOf(0, 90, 0, 0, 0, 0, 0, 0)) }

    @Test fun domainAndIpv4HandshakeAndDelayedResponseAfterHalfClose() {
        for (ipv4 in listOf(false, true)) {
            val host = if (ipv4) "192.0.2.1" else "api.us.example.test"
            Peer { socket ->
                checkRequest(socket, host, 443, "user", ipv4); accept(socket)
                val payload = socket.getInputStream().readBytes()
                assertEquals("request", String(payload))
                Thread.sleep(50)
                socket.getOutputStream().write("reply:request".toByteArray())
            }.use { peer ->
                MixSocks4Proxy(port(), "127.0.0.1", peer.port, "user").use { proxy ->
                    proxy.start()
                    connect(proxy.boundPort).use { socket ->
                        assertEquals(0, request(socket, host, 443, ipv4))
                        socket.getOutputStream().write("request".toByteArray()); socket.shutdownOutput()
                        assertEquals("reply:request", String(socket.getInputStream().readBytes()))
                    }
                    peer.done()
                }
            }
        }
    }

    @Test fun upstreamPrefixReceivesProxyHostnameWithoutLocalDnsResolution() {
        Peer { socket ->
            val input = DataInputStream(socket.getInputStream())
            val output = socket.getOutputStream()
            assertArrayEquals(byteArrayOf(5, 1, 0), read(input, 3))
            output.write(byteArrayOf(5, 0))
            assertArrayEquals(byteArrayOf(5, 1, 0, 3), read(input, 4))
            val hostname = String(read(input, input.readUnsignedByte()), Charsets.US_ASCII)
            assertEquals("proxy.does-not-exist.invalid", hostname)
            assertEquals(1080, input.readUnsignedShort())
            output.write(byteArrayOf(5, 0, 0, 1, 127, 0, 0, 1, 0, 0))
            checkRequest(socket, "example.test", 80, "u"); accept(socket)
            assertEquals("ping", String(read(input, 4)))
            output.write("pong".toByteArray())
        }.use { prefix ->
            MixSocks4Proxy(port(), "proxy.does-not-exist.invalid", 1080, "u", prefix.port).use { proxy ->
                proxy.start()
                connect(proxy.boundPort).use { socket ->
                    assertEquals(0, request(socket, "example.test", 80))
                    socket.getOutputStream().write("ping".toByteArray())
                    assertEquals("pong", String(read(socket.getInputStream(), 4)))
                }
                prefix.done()
            }
        }
    }

    @Test fun udpAndIpv6AreExplicitlyRejectedWithoutOpeningRemoteSockets() {
        MixSocks4Proxy(port(), "127.0.0.1", 1, "").use { proxy ->
            proxy.start()
            for ((command, kind, code) in listOf(Triple(3, 1, 7), Triple(1, 4, 8))) {
                connect(proxy.boundPort).use { socket ->
                    socket.getOutputStream().write(byteArrayOf(5, command.toByte(), 0, kind.toByte()))
                    assertEquals(code, read(socket.getInputStream(), 10)[1].toInt())
                }
            }
            Socket("127.0.0.1", proxy.boundPort).use { socket ->
                socket.soTimeout = 3000
                socket.getOutputStream().write(byteArrayOf(5, 1, 2))
                assertArrayEquals(byteArrayOf(5, -1), read(socket.getInputStream(), 2))
            }
        }
    }

    @Test fun remoteRefusalIsReportedAsSocks5Failure() {
        Peer { socket ->
            checkRequest(socket, "refused.test", 80, "")
            socket.getOutputStream().write(byteArrayOf(0, 91, 0, 0, 0, 0, 0, 0))
        }.use { peer ->
            MixSocks4Proxy(port(), "127.0.0.1", peer.port, "").use { proxy ->
                proxy.start()
                connect(proxy.boundPort).use { assertEquals(1, request(it, "refused.test", 80)) }
                peer.done()
            }
        }
    }

    @Test fun closeInterruptsAnInFlightRemoteHandshake() {
        val waiting = CountDownLatch(1)
        Peer { socket ->
            assertArrayEquals(byteArrayOf(5, 1, 0), read(socket.getInputStream(), 3))
            waiting.countDown()
            assertEquals(-1, socket.getInputStream().read())
        }.use { peer ->
            val proxy = MixSocks4Proxy(port(), "remote.invalid", 1080, "", peer.port)
            proxy.start()
            connect(proxy.boundPort).use { client ->
                val output = DataOutputStream(client.getOutputStream())
                output.write(byteArrayOf(5, 1, 0, 3, 1, 97)); output.writeShort(80); output.flush()
                assertTrue(waiting.await(3, TimeUnit.SECONDS))
                proxy.close()
                assertEquals(-1, client.getInputStream().read())
                peer.done()
            }
        }
    }
}
