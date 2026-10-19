package com.forwin.vpn.dnsscan

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicBoolean

class DnsResolverScannerTest {
    private fun message(id: Int = 1234, flags: Int = 0x8180, name: String = "example.com", type: Int = 16): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf((id shr 8).toByte(), id.toByte(), (flags shr 8).toByte(), flags.toByte(), 0,1,0,0,0,0,0,0))
        name.split('.').forEach { out.write(it.length); out.write(it.toByteArray()) }
        out.write(byteArrayOf(0,0,type.toByte(),0,1))
        return out.toByteArray()
    }
    @Test fun channelReturnsObjectsNotNestedJsonStrings() {
        val results = org.json.JSONArray(DnsResolverScanner.scan(listOf("127.0.0.1"), "example.com", 1))
        assertEquals(1, results.length())
        assertTrue(results.get(0) is JSONObject)
        assertEquals("127.0.0.1", results.getJSONObject(0).getString("ip"))
    }
    @Test fun validatesQuestionAndHeaderBeforeAcceptingDns() {
        val valid = message()
        assertEquals(0, DnsResolverScanner.validate(valid, 1234, "example.com", 16).rcode)
        for (invalid in listOf(valid.copyOf(8), message(id=9), message(flags=0x0100),
            message(flags=0x8380), message(flags=0x8980), message(name="other.example"))) {
            assertThrows(Exception::class.java) { DnsResolverScanner.validate(invalid,1234,"example.com",16) }
        }
    }
    @Test fun distinguishesNxDomainAndRejectsPointerLoopAndTruncatedRecord() {
        assertEquals(3, DnsResolverScanner.validate(message(flags=0x8183),1234,"example.com",16).rcode)
        val pointerLoop = message().copyOfRange(0,12) + byteArrayOf(0xc0.toByte(),12,0,16,0,1)
        assertThrows(Exception::class.java) { DnsResolverScanner.validate(pointerLoop,1234,"example.com",16) }
        val claimedAnswer = message().also { it[7]=1 }
        assertThrows(Exception::class.java) { DnsResolverScanner.validate(claimedAnswer,1234,"example.com",16) }
    }

    private fun reply(query: ByteArray, hijack: Boolean): ByteArray {
        var end = 12
        while (query[end].toInt() != 0) end += 1 + (query[end].toInt() and 255)
        end += 5
        val name = String(query,12,end-12,Charsets.US_ASCII)
        val nx = name.contains("invalid") && !hijack
        val q = query.copyOfRange(0,end)
        q[2]=0x81.toByte();q[3]=(if(nx)0x83 else 0x80).toByte()
        q[6]=0;q[7]=(if(nx)0 else 1);q[8]=0;q[9]=0;q[10]=0;q[11]=1
        val answer = if(nx) byteArrayOf() else byteArrayOf(0xc0.toByte(),12,0,16,0,1,0,0,0,10,0,4,3, 'o'.code.toByte(),'k'.code.toByte(),'!'.code.toByte())
        val opt = byteArrayOf(0,0,41,4,0xd0.toByte(),0,0,0,0,0,0)
        return q + answer + opt
    }

    private class Fixture(val hijack: Boolean, val answer: (ByteArray, Boolean) -> ByteArray) : AutoCloseable {
        val running = AtomicBoolean(true)
        val udp = DatagramSocket(0, InetAddress.getLoopbackAddress())
        val tcp = ServerSocket(0,10,InetAddress.getLoopbackAddress())
        init {
            Thread {
                while(running.get()) try {
                    val packet=DatagramPacket(ByteArray(4096),4096);udp.receive(packet)
                    val response=answer(packet.data.copyOf(packet.length),hijack)
                    udp.send(DatagramPacket(response,response.size,packet.address,packet.port))
                } catch (_: Exception) { }
            }.apply { isDaemon=true;start() }
            Thread {
                while(running.get()) try { tcp.accept().use { socket ->
                    socket.soTimeout=2000
                    val input=DataInputStream(socket.getInputStream());val output=DataOutputStream(socket.getOutputStream())
                    val query=ByteArray(input.readUnsignedShort());input.readFully(query)
                    val response=answer(query,hijack);output.writeShort(response.size);output.write(response);output.flush()
                }} catch (_: Exception) { }
            }.apply { isDaemon=true;start() }
        }
        override fun close() { running.set(false);udp.close();tcp.close() }
    }
    @Test fun realUdpAndTcpDnsProbesRecognizeSafeCandidate() {
        Fixture(false,::reply).use { f ->
            val result=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort))
            assertTrue(result.toString(),result.getBoolean("reachable"))
            assertTrue(result.getBoolean("txtSupported"));assertTrue(result.getBoolean("ednsSupported"))
            assertTrue(result.getBoolean("nxdomainSafe"));assertTrue(result.getBoolean("tunnelCandidate"))
            assertFalse(result.getBoolean("tunnelVerified"))
        }
    }
    @Test fun nxDomainHijackingNeverQualifiesAsTunnelCandidate() {
        Fixture(true,::reply).use { f ->
            val result=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort))
            assertTrue(result.getBoolean("nxdomainHijacked"));assertFalse(result.getBoolean("tunnelCandidate"))
        }
    }
    @Test fun genericTcpListenerIsNotDnsReachability() {
        Fixture(false) { _,_ -> byteArrayOf(1,2,3) }.use { f ->
            val result=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort))
            assertFalse(result.getBoolean("reachable"));assertFalse(result.getBoolean("tunnelCandidate"))
        }
    }
}
