package com.forwin.vpn.slowdns

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.ServerSocket

class Socks5ProbeTest {
    @Test fun probesSocksAndDnsDataPlane() {
        ServerSocket(0).use { server ->
            val thread = Thread {
                server.accept().use { socket ->
                    val input = DataInputStream(socket.getInputStream()); val out = DataOutputStream(socket.getOutputStream())
                    val version = input.readUnsignedByte(); val methods = ByteArray(input.readUnsignedByte()); input.readFully(methods)
                    check(version == 5 && methods.contains(0))
                    out.write(byteArrayOf(5, 0)); out.flush()
                    val request = ByteArray(10); input.readFully(request)
                    out.write(byteArrayOf(5, 0, 0, 1, 1, 1, 1, 1, 0, 53)); out.flush()
                    val length = input.readUnsignedShort(); val query = ByteArray(length); input.readFully(query)
                    val response = query.copyOf().also {
                        it[2] = 0x81.toByte(); it[3] = 0x80.toByte(); it[6] = 0; it[7] = 1
                    } + byteArrayOf(0xc0.toByte(), 12, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184.toByte(), 216.toByte(), 34)
                    out.writeShort(response.size); out.write(response); out.flush()
                }
            }.also { it.start() }
            assertTrue(Socks5Probe.connectAndQuery(server.localPort, null, null, 2000))
            thread.join(2000)
        }
    }
}
