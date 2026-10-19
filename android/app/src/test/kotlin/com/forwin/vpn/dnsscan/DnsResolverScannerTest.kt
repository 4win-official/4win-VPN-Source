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
    private fun header(id: Int = 1234, flags: Int = 0x8180, an: Int = 0, ar: Int = 0): ByteArray = byteArrayOf(
        (id shr 8).toByte(), id.toByte(), (flags shr 8).toByte(), flags.toByte(), 0, 1,
        (an shr 8).toByte(), an.toByte(), 0, 0, (ar shr 8).toByte(), ar.toByte())
    private fun question(name: String = "example.com", type: Int = 16): ByteArray {
        val out = ByteArrayOutputStream(); name.split('.').forEach { out.write(it.length); out.write(it.toByteArray()) }
        out.write(byteArrayOf(0, (type shr 8).toByte(), type.toByte(), 0, 1)); return out.toByteArray()
    }
    private fun message(id: Int = 1234, flags: Int = 0x8180, name: String = "example.com", type: Int = 16) = header(id, flags) + question(name, type)

    @Test fun channelReturnsObjectsNotNestedJsonStrings() {
        val results = org.json.JSONArray(DnsResolverScanner.scan(listOf("127.0.0.1"), "example.com", 1))
        assertEquals(1, results.length()); assertTrue(results.get(0) is JSONObject)
    }
    @Test fun validatesQuestionAndHeaderBeforeAcceptingDns() {
        val valid = message(); assertEquals(0, DnsResolverScanner.validate(valid, 1234, "example.com", 16).rcode)
        for (invalid in listOf(valid.copyOf(8), message(id=9), message(flags=0x0100), message(flags=0x8380), message(flags=0x8980), message(name="other.example")))
            assertThrows(Exception::class.java) { DnsResolverScanner.validate(invalid, 1234, "example.com", 16) }
    }
    @Test fun distinguishesNxDomainAndRejectsPointerLoopAndTruncatedRecord() {
        assertEquals(3, DnsResolverScanner.validate(message(flags=0x8183),1234,"example.com",16).rcode)
        val pointerLoop = message().copyOfRange(0,12) + byteArrayOf(0xc0.toByte(),12,0,16,0,1)
        assertThrows(Exception::class.java) { DnsResolverScanner.validate(pointerLoop,1234,"example.com",16) }
        val claimedAnswer = message().also { it[7]=1 }
        assertThrows(Exception::class.java) { DnsResolverScanner.validate(claimedAnswer,1234,"example.com",16) }
    }

    private fun record(owner: String, type: Int, data: ByteArray, recordClass: Int = 1): ByteArray {
        return encodeName(owner) + byteArrayOf(
            (type shr 8).toByte(), type.toByte(),
            (recordClass shr 8).toByte(), recordClass.toByte(),
            0, 0, 0, 10, (data.size shr 8).toByte(), data.size.toByte()
        ) + data
    }

    @Test fun onlyMatchingInternetClassAnswersResolveTheTarget() {
        val address = byteArrayOf(1, 2, 3, 4)
        for (answer in listOf(
            record("other.example", 1, address),
            record("example.com", 1, address, recordClass = 3)
        )) {
            val response = header(an = 1) + question(type = 1) + answer
            assertFalse(DnsResolverScanner.validate(response, 1234, "example.com", 1).targetResolved)
        }
    }

    @Test fun acceptsPositiveAnswerThroughAValidatedCnameChain() {
        val response = header(an = 2) + question(type = 1) +
            record("example.com", 5, encodeName("alias.example")) +
            record("alias.example", 1, byteArrayOf(1, 2, 3, 4))
        assertTrue(DnsResolverScanner.validate(response, 1234, "example.com", 1).targetResolved)
    }

    @Test fun rejectsWrongALengthAndTrailingPtrRdataBytes() {
        val badA = header(an = 1) + question(type = 1) +
            record("example.com", 1, byteArrayOf(1, 2, 3))
        val badPtr = header(an = 1) + question(type = 12) +
            record("example.com", 12, encodeName("ptr.example") + byteArrayOf(0))
        assertThrows(Exception::class.java) {
            DnsResolverScanner.validate(badA, 1234, "example.com", 1)
        }
        assertThrows(Exception::class.java) {
            DnsResolverScanner.validate(badPtr, 1234, "example.com", 12)
        }
    }

    private enum class Mode { POSITIVE, NXDOMAIN, NODATA, HIJACK }
    private fun encodeName(name: String): ByteArray { val out=ByteArrayOutputStream(); name.trimEnd('.').split('.').forEach { out.write(it.length); out.write(it.toByteArray()) }; out.write(0); return out.toByteArray() }
    private fun reply(query: ByteArray, mode: Mode): ByteArray {
        var p=12; val labels=ArrayList<String>(); while (query[p].toInt()!=0) { val n=query[p++].toInt() and 255; labels.add(String(query,p,n)); p+=n }; p++; val type=(query[p].toInt() and 255)*256+(query[p+1].toInt() and 255)
        val name=labels.joinToString("."); val nx=mode==Mode.NXDOMAIN || (name.endsWith(".invalid") && mode != Mode.HIJACK); val nodata=mode==Mode.NODATA && !name.endsWith(".invalid")
        val flags=if(nx) 0x8183 else 0x8180; val answer=if(nx||nodata) byteArrayOf() else when(type) {
            1 -> byteArrayOf(0xc0.toByte(),12,0,1,0,1,0,0,0,10,0,4,127,0,0,1)
            12 -> byteArrayOf(0xc0.toByte(),12,0,12,0,1,0,0,0,10,0, encodeName("ptr.example").size.toByte()) + encodeName("ptr.example")
            16 -> byteArrayOf(0xc0.toByte(),12,0,16,0,1,0,0,0,10,0,4,3,'o'.code.toByte(),'k'.code.toByte(),'!'.code.toByte())
            else -> byteArrayOf()
        }
        val opt=byteArrayOf(0,0,41,4,0xd0.toByte(),0,0,0,0,0,0)
        val h=header(query[0].toInt()*256+(query[1].toInt() and 255),flags,if(answer.isEmpty()) 0 else 1,1)
        return h + query.copyOfRange(12,p+4) + answer + opt
    }
    private inner class Fixture(private val mode: Mode, private val malformedTcp: Boolean = false) : AutoCloseable {
        val running=AtomicBoolean(true); val udp=DatagramSocket(0,InetAddress.getLoopbackAddress()); val tcp=ServerSocket(0,10,InetAddress.getLoopbackAddress())
        val questions = java.util.Collections.synchronizedList(mutableListOf<Pair<String, Int>>())
        init {
            Thread { while(running.get()) try { val packet=DatagramPacket(ByteArray(4096),4096); udp.receive(packet); val q=packet.data.copyOf(packet.length); questions.add(questionKey(q)); val r=reply(q,mode); udp.send(DatagramPacket(r,r.size,packet.address,packet.port)) } catch(_:Exception){} }.apply{isDaemon=true;start()}
            Thread { while(running.get()) try { tcp.accept().use { s -> val i=DataInputStream(s.getInputStream()); val o=DataOutputStream(s.getOutputStream()); val q=ByteArray(i.readUnsignedShort()); i.readFully(q); questions.add(questionKey(q)); if (malformedTcp) { o.writeShort(3); o.write(byteArrayOf(1,2,3)); o.flush() } else { val r=reply(q,mode); o.writeShort(r.size);o.write(r);o.flush() } } } catch(_:Exception){} }.apply{isDaemon=true;start()}
        }
        private fun questionKey(q: ByteArray): Pair<String, Int> { var p=12; val labels=ArrayList<String>(); while(q[p].toInt()!=0){ val n=q[p++].toInt() and 255; labels.add(String(q,p,n)); p+=n }; p++; return labels.joinToString(".") to ((q[p].toInt() and 255)*256+(q[p+1].toInt() and 255)) }
        override fun close(){running.set(false);udp.close();tcp.close()}
    }
    @Test fun realUdpAndTcpDnsProbesRequirePositiveTargetResolution() { Fixture(Mode.POSITIVE).use { f -> val r=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort)); assertTrue(r.getBoolean("reachable")); assertTrue(r.getBoolean("targetResolved")); assertTrue(r.getBoolean("txtSupported")); assertTrue(r.getBoolean("ednsSupported")); assertTrue(r.getBoolean("tunnelCandidate")); assertFalse(r.getBoolean("tunnelVerified")) } }
    @Test fun publicScannerApiUsesConfiguredPortAndTimeout() { Fixture(Mode.POSITIVE).use { f -> val results=org.json.JSONArray(DnsResolverScanner.scan(listOf("127.0.0.1"),"example.com",1,f.udp.localPort,200)); assertEquals(1,results.length()); assertTrue(results.getJSONObject(0).getBoolean("tunnelCandidate")) }; assertThrows(IllegalArgumentException::class.java) { DnsResolverScanner.scan(listOf("127.0.0.1"),"example.com",1,0,200) } }
    @Test fun ipv6ScanTargetsAreNeverScheduled() { val results=org.json.JSONArray(DnsResolverScanner.scan(listOf("::1","2001:db8::1"),"example.com",1,53,100)); assertEquals(0,results.length()) }
    @Test fun ipv4UsesExactReversePtrQuestion() { Fixture(Mode.POSITIVE).use { f -> val r=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","127.0.0.1",f.udp.localPort,f.tcp.localPort)); assertTrue(r.getBoolean("targetResolved")); assertTrue(r.getBoolean("tunnelCandidate")); assertTrue(f.questions.contains("1.0.0.127.in-addr.arpa" to 12)); assertFalse(f.questions.contains("127.0.0.1" to 1)) } }
    @Test fun nxDomainAndNoDataDoNotResolveTarget() { Fixture(Mode.NXDOMAIN).use { f -> val r=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort)); assertFalse(r.getBoolean("targetResolved")); assertTrue(r.getBoolean("nxdomainSafe")); assertFalse(r.getBoolean("tunnelCandidate")) }; Fixture(Mode.NODATA).use { f -> val r=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort)); assertFalse(r.getBoolean("targetResolved")); assertFalse(r.getBoolean("tunnelCandidate")) } }
    @Test fun malformedTargetsAreRejectedAndIpv6IsIgnored() { assertThrows(IllegalArgumentException::class.java) { DnsResolverScanner.scan(listOf("127.0.0.1"), "https://example.com", 1) }; assertThrows(IllegalArgumentException::class.java) { DnsResolverScanner.scan(listOf("127.0.0.1"), "bad_name.example", 1) }; assertThrows(IllegalArgumentException::class.java) { DnsResolverScanner.scan(listOf("127.0.0.1"), "123.456", 1) }; assertEquals(0, org.json.JSONArray(DnsResolverScanner.scan(listOf("::1"), "example.com", 1)).length()) }
    @Test fun nxDomainHijackingNeverQualifiesAsTunnelCandidate() { Fixture(Mode.HIJACK).use { f -> val r=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort)); assertTrue(r.getBoolean("nxdomainHijacked")); assertFalse(r.getBoolean("tunnelCandidate")) } }
    @Test fun genericTcpListenerIsNotDnsReachability() { Fixture(Mode.POSITIVE, malformedTcp=true).use { f -> f.udp.close(); val r=JSONObject(DnsResolverScanner.scanEndpoint("127.0.0.1","example.com",f.udp.localPort,f.tcp.localPort)); assertFalse(r.getBoolean("reachable")) } }
}
