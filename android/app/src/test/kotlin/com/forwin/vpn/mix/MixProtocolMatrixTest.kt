package com.forwin.vpn.mix

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Exhaustive, pure tests for the seven-stage Mix protocol vocabulary. */
class MixProtocolMatrixTest {
    private val protocols = listOf("xray", "proxy", "warp", "psiphon", "sstp", "openvpn", "direct_dns")

    private fun hop(protocol: String, outbound: String = "vless"): JSONObject = JSONObject().apply {
        put("protocol", protocol)
        when (protocol) {
            "xray", "proxy" -> put("outbound", JSONObject()
                .put("protocol", outbound)
                .put("settings", JSONObject().put("servers", JSONArray().put(
                    JSONObject().put("address", "example.invalid").put("port", 443)))))
            "direct_dns" -> put("address", "9.9.9.9")
            else -> put("config", JSONObject().put("name", protocol))
        }
    }

    private fun plan(vararg stages: String): JSONObject = JSONObject()
        .put("version", 1)
        .put("hops", JSONArray().also { array -> stages.forEach { array.put(hop(it)) } })
        .put("dns", "9.9.9.9")
        .put("baseConfig", JSONObject().put("inbounds", JSONArray()
            .put(JSONObject().put("tag", "tun-in").put("protocol", "tun"))))

    private fun sidecar(p: JSONObject): JSONObject {
        val hops = p.getJSONArray("hops")
        val workers = (0 until hops.length()).filter {
            hops.getJSONObject(it).getString("protocol") in MixRouting.nativeProtocols ||
                hops.getJSONObject(it).has("socks4")
        }.associateWith { 22000 + it }
        val dns = (0 until hops.length()).filter {
            hops.getJSONObject(it).getString("protocol") == "direct_dns"
        }.associateWith { 23000 + it }
        return MixRouting.sidecar(p, List(hops.length()) { 20000 + it }, workers, dns)
    }

    @Test
    fun everyOrderedConcreteProtocolVariantIncludingSocks4Builds() {
        val variants = listOf("vless", "vmess", "trojan", "shadowsocks", "socks5",
            "socks4", "http", "https", "warp", "sstp", "openvpn-tcp", "openvpn-udp", "psiphon", "direct_dns")
        fun block(kind: String): JSONObject = when (kind) {
            "vless", "vmess", "trojan", "shadowsocks" -> hop("xray", kind)
            "socks5" -> hop("proxy", "socks")
            "socks4" -> hop("proxy", "socks").put("socks4", JSONObject()
                .put("host", "proxy.invalid").put("port", 1080).put("userId", "user"))
            "http", "https" -> hop("proxy", "http").apply {
                if (kind == "https") getJSONObject("outbound").put("streamSettings",
                    JSONObject().put("security", "tls").put("tlsSettings", JSONObject().put("serverName", "proxy.invalid")))
            }
            "openvpn-tcp", "openvpn-udp" -> hop("openvpn").put("config", JSONObject()
                .put("inline", "client\nproto ${if (kind.endsWith("tcp")) "tcp-client" else "udp"}\nremote vpn.invalid 443\n"))
            else -> hop(kind)
        }
        for (first in variants) for (second in variants) {
            val input = plan("xray", "proxy").put("hops", JSONArray().put(block(first)).put(block(second)))
            val before = input.toString()
            val result = sidecar(input)
            assertEquals("$first -> $second mutated input", before, input.toString())
            val outbounds = (0 until result.getJSONArray("outbounds").length())
                .map { result.getJSONArray("outbounds").getJSONObject(it) }.associateBy { it.getString("tag") }
            assertTrue(outbounds.containsKey("mix-stage-0") && outbounds.containsKey("mix-stage-1"))
            if (second == "socks4") {
                val adapter = outbounds.getValue("mix-stage-1")
                assertEquals(22001, adapter.getJSONObject("settings").getJSONArray("servers").getJSONObject(0).getInt("port"))
                assertFalse(adapter.has("streamSettings"))
                assertFalse(MixCapabilities.afterXray(input.getJSONArray("hops").getJSONObject(1), true))
                assertTrue(MixCapabilities.needsRelay(input.getJSONArray("hops").getJSONObject(1)))
            }
        }
    }

    @Test
    fun everyOrderedProtocolPairBuildsAndLinksPreviousStage() {
        var count = 0
        for (first in protocols) for (second in protocols) {
            val input = plan(first, second)
            val before = input.toString()
            val result = sidecar(input)
            assertEquals("input mutated for $first -> $second", before, input.toString())
            val outbounds = (0 until result.getJSONArray("outbounds").length())
                .map { result.getJSONArray("outbounds").getJSONObject(it) }
                .associateBy { it.getString("tag") }
            for (stage in 0..1) {
                val protocol = if (stage == 0) first else second
                val public = outbounds.getValue("mix-stage-$stage")
                if (protocol in MixRouting.nativeProtocols) {
                    assertEquals("socks", public.getString("protocol"))
                    assertEquals(22000 + stage, public.getJSONObject("settings")
                        .getJSONArray("servers").getJSONObject(0).getInt("port"))
                } else if (protocol == "direct_dns") {
                    assertEquals("freedom", public.getString("protocol"))
                    assertEquals("AsIs", public.getJSONObject("streamSettings")
                        .getJSONObject("sockopt").getString("domainStrategy"))
                } else {
                    val socket = public.getJSONObject("streamSettings").getJSONObject("sockopt")
                    assertEquals("AsIs", socket.getString("domainStrategy"))
                    if (stage == 1) assertEquals("mix-stage-0", socket.getString("dialerProxy"))
                    else assertFalse(socket.has("dialerProxy"))
                }
            }
            count++
        }
        assertEquals(49, count)
    }

    @Test
    fun nearestRepeatedDnsPolicyIsUsedAndDnsInputIsNotMutated() {
        val input = plan("direct_dns", "xray", "direct_dns", "proxy", "direct_dns", "warp", "xray")
        val before = input.toString()
        val result = MixRouting.sidecar(input, List(7) { 20000 + it },
            mapOf(5 to 22005, 6 to 22006), mapOf(0 to 23000, 2 to 23002, 4 to 23004))
        assertEquals(before, input.toString())
        val rules = result.getJSONObject("routing").getJSONArray("rules")
        for (stage in 0 until 7) {
            val stageRules = (0 until rules.length()).map { rules.getJSONObject(it) }
                .filter { it.getJSONArray("inboundTag").getString(0) == "mix-prefix-$stage" }
            val dnsRule = stageRules.firstOrNull { it.optInt("port", -1) == 53 }
            val expectedDns = when {
                stage >= 4 -> "mix-dns-4"
                stage >= 2 -> "mix-dns-2"
                else -> "mix-dns-0"
            }
            assertEquals(expectedDns, dnsRule!!.getString("outboundTag"))
            assertEquals("mix-stage-$stage", stageRules.last().getString("outboundTag"))
        }
    }

    @Test
    fun fiftyNativeHopsMapEveryWorkerAndMixedFiftyOneIsRejected() {
        for (native in listOf("warp", "psiphon", "sstp", "openvpn")) {
            val input = plan(*Array(50) { native })
            val result = MixRouting.sidecar(input, List(50) { 20000 + it },
                (0 until 50).associateWith { 21000 + it }, emptyMap())
            assertEquals(50, result.getJSONArray("outbounds").length())
            val byTag = (0 until 50).map { result.getJSONArray("outbounds").getJSONObject(it) }
                .associateBy { it.getString("tag") }
            for (i in 0 until 50) {
                assertEquals(21000 + i, byTag.getValue("mix-stage-$i").getJSONObject("settings")
                    .getJSONArray("servers").getJSONObject(0).getInt("port"))
            }
        }
        val mixed = Array(50) { protocols[it % protocols.size] }
        val mixedPlan = plan(*mixed)
        val mixedResult = sidecar(mixedPlan)
        assertEquals(50, mixedResult.getJSONArray("inbounds").length())
        assertThrows(IllegalArgumentException::class.java) {
            MixRouting.sidecar(plan(*mixed, "xray"), List(51) { 20000 + it },
                (0 until 51).filter { mixed.getOrNull(it) in MixRouting.nativeProtocols }
                    .associateWith { 22000 + it },
                (0 until 51).filter { mixed.getOrNull(it) == "direct_dns" }
                    .associateWith { 23000 + it })
        }
    }

    @Test
    fun relayWrappedHttpAndPsiphonPreserveUnderlayLinksWithoutCycles() {
        for (ordering in listOf(listOf("http", "psiphon"), listOf("psiphon", "http"))) {
            val blocks = JSONArray()
            ordering.forEach { protocol ->
                blocks.put(if (protocol == "http") hop("xray", "http") else hop("psiphon"))
            }
            blocks.put(hop("proxy"))
            val input = JSONObject().put("hops", blocks)
            val workerPorts = if (ordering[0] == "psiphon") mapOf(0 to 22000) else mapOf(1 to 22001)
            val result = MixRouting.sidecar(input, listOf(20000, 20001, 20002), workerPorts, emptyMap(),
                udpRelayPorts = mapOf(0 to 24000, 1 to 24001),
                relayUnderlayPorts = mapOf(0 to 25000, 1 to 25001))
        val outbounds = (0 until result.getJSONArray("outbounds").length())
            .map { result.getJSONArray("outbounds").getJSONObject(it) }.associateBy { it.getString("tag") }
        if (ordering[1] == "http") {
            assertEquals("mix-stage-0", outbounds.getValue("mix-underlay-1")
                .getJSONObject("streamSettings").getJSONObject("sockopt").getString("dialerProxy"))
        } else {
            // Native engines consume their prefix via the worker environment,
            // not via a dialerProxy on this local worker SOCKS outbound.
            assertEquals(22001, outbounds.getValue("mix-underlay-1")
                .getJSONObject("settings").getJSONArray("servers").getJSONObject(0).getInt("port"))
        }
        assertEquals("socks", outbounds.getValue("mix-stage-1").getString("protocol"))
        assertEquals("mix-stage-1", outbounds.getValue("mix-stage-2").getJSONObject("streamSettings")
            .getJSONObject("sockopt").getString("dialerProxy"))
        for ((tag, outbound) in outbounds) {
            val dialer = outbound.optJSONObject("streamSettings")?.optJSONObject("sockopt")?.optString("dialerProxy")
            assertNotEquals("$tag must not dial itself", tag, dialer)
            assertFalse(dialer?.contains("underlay-$tag") == true)
        }
        assertTrue(result.getJSONArray("inbounds").length() >= 5)
        }
    }

    @Test
    fun capabilitiesCoverUdpRestorationRelayAndDatagramUnderlays() {
        val http = hop("xray", "http")
        val vless = hop("xray", "vless")
        val psiphon = hop("psiphon")
        val sstp = hop("sstp")
        val shadowsocks = hop("xray", "shadowsocks")
        val socks = hop("proxy", "socks")
        assertFalse(MixCapabilities.afterXray(http, true))
        assertTrue(MixCapabilities.afterXray(vless, false))
        assertTrue(MixCapabilities.needsRelay(http))
        // Shadowsocks cannot carry UDP across a TCP-only preceding hop;
        // with a configured relay it must be wrapped rather than rejected.
        assertTrue(MixCapabilities.needsRelay(shadowsocks))
        assertFalse(MixCapabilities.needsRelay(psiphon))
        assertFalse(MixCapabilities.needsRelay(sstp))
        assertEquals(true, MixCapabilities.afterXray(shadowsocks, true))
        assertEquals(false, MixCapabilities.afterXray(shadowsocks, false))
        assertEquals(true, MixCapabilities.afterXray(socks, true))
        assertEquals(false, MixCapabilities.afterXray(socks, false))
    }

    @Test
    fun tcpOnlyProxyCapabilitiesFailClosedInsteadOfClaimingUdp() {
        val http = hop("xray", "http")
        val socks4 = hop("proxy", "socks").put("socks4", JSONObject())

        assertFalse(MixCapabilities.afterXray(http, true))
        assertFalse(MixCapabilities.afterXray(socks4, true))
        assertTrue(MixCapabilities.needsRelay(http))
        assertTrue(MixCapabilities.needsRelay(socks4))

        val mismatchedSocks4 = hop("xray", "http").put("socks4", JSONObject())
        assertThrows(IllegalArgumentException::class.java) {
            MixCapabilities.needsRelay(mismatchedSocks4)
        }
        assertThrows(IllegalArgumentException::class.java) {
            MixCapabilities.afterXray(mismatchedSocks4, true)
        }

        val missingOutbound = hop("xray", "http").apply { remove("outbound") }
        assertThrows(IllegalStateException::class.java) {
            MixCapabilities.needsRelay(missingOutbound)
        }
        assertThrows(IllegalStateException::class.java) {
            MixCapabilities.afterXray(missingOutbound, true)
        }
    }

    @Test
    fun wholePlanValidationRequiresRelayBeforeWarpButAllowsNativeRestoration() {
        val httpThenWarp = plan("xray", "warp")
        httpThenWarp.getJSONArray("hops").getJSONObject(0)
            .getJSONObject("outbound").put("protocol", "http")
        assertThrows(IllegalArgumentException::class.java) {
            MixCapabilities.validatePlan(httpThenWarp, relayConfigured = false)
        }
        MixCapabilities.validatePlan(httpThenWarp, relayConfigured = true)

        val socks4ThenWarp = plan("proxy", "warp")
        socks4ThenWarp.getJSONArray("hops").getJSONObject(0)
            .put("socks4", JSONObject().put("host", "proxy.invalid").put("port", 1080))
        assertThrows(IllegalArgumentException::class.java) {
            MixCapabilities.validatePlan(socks4ThenWarp, relayConfigured = false)
        }

        // DNS is a policy boundary, not a UDP tunnel. Nor can ordinary SOCKS
        // or Shadowsocks restore UDP lost at an earlier HTTP CONNECT hop.
        for (datagram in listOf("socks", "shadowsocks")) {
            val tcpOnly = plan("proxy", "direct_dns", "proxy", "direct_dns", "warp")
            tcpOnly.getJSONArray("hops").getJSONObject(0)
                .getJSONObject("outbound").put("protocol", "http")
            tcpOnly.getJSONArray("hops").getJSONObject(2)
                .getJSONObject("outbound").put("protocol", datagram)
            assertThrows(IllegalArgumentException::class.java) {
                MixCapabilities.validatePlan(tcpOnly, false)
            }
            MixCapabilities.validatePlan(tcpOnly, true)
        }

        // A native packet tunnel is a capability boundary; the worker's
        // runtime readiness remains authoritative after this preflight.
        for (restorer in listOf("sstp", "psiphon", "openvpn", "xray")) {
            val restored = plan("proxy", "direct_dns", restorer, "direct_dns", "warp")
            restored.getJSONArray("hops").getJSONObject(0)
                .getJSONObject("outbound").put("protocol", "http")
            val before = restored.toString()
            MixCapabilities.validatePlan(restored, relayConfigured = false)
            assertEquals(before, restored.toString())
        }
        for (count in listOf(0, 51)) {
            assertThrows(IllegalArgumentException::class.java) {
                MixCapabilities.validatePlan(plan(*Array(count) { "warp" }), false)
            }
        }
        val fifty = plan(*Array(50) { protocols[it % protocols.size] })
        val before = fifty.toString()
        MixCapabilities.validatePlan(fifty, false)
        assertEquals(before, fifty.toString())
        assertThrows(IllegalArgumentException::class.java) {
            MixCapabilities.validatePlan(plan("slowdns", "warp"), false)
        }
    }

    @Test
    fun psiphonPacketTunnelBetweenTcpProxyAndWarpAddsNoExternalRelayOrHiddenHop() {
        val input = plan("proxy", "psiphon", "warp")
        input.getJSONArray("hops").put(0, hop("proxy", "http"))
        assertFalse(MixCapabilities.afterXray(input.getJSONArray("hops").getJSONObject(0), true))
        assertFalse(MixCapabilities.needsRelay(input.getJSONArray("hops").getJSONObject(1)))
        val result = sidecar(input)
        assertEquals(3, result.getJSONArray("outbounds").length())
        assertEquals(3, result.getJSONArray("inbounds").length())
        val outbounds = (0 until 3).map { result.getJSONArray("outbounds").getJSONObject(it) }
            .associateBy { it.getString("tag") }
        assertEquals(22001, outbounds.getValue("mix-stage-1").getJSONObject("settings")
            .getJSONArray("servers").getJSONObject(0).getInt("port"))
        assertEquals(22002, outbounds.getValue("mix-stage-2").getJSONObject("settings")
            .getJSONArray("servers").getJSONObject(0).getInt("port"))
        assertFalse(result.toString().contains("mix-underlay"))
    }

    private fun <T : Throwable> assertThrows(type: Class<T>, body: () -> Unit) {
        try {
            body()
        } catch (error: Throwable) {
            assertTrue("expected ${type.simpleName}, got ${error::class.java.simpleName}", type.isInstance(error))
            return
        }
        throw AssertionError("expected ${type.simpleName}")
    }
}
