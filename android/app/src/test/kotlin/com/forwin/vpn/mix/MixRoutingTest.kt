package com.forwin.vpn.mix

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MixRoutingTest {
    private fun plan(vararg protocols: String): JSONObject {
        val hops = JSONArray()
        protocols.forEach { protocol ->
            val hop = JSONObject().put("protocol", protocol)
            if (protocol == "xray" || protocol == "proxy") hop.put("outbound", JSONObject()
                .put("protocol", "socks").put("settings", JSONObject().put("servers", JSONArray()
                    .put(JSONObject().put("address", "example.invalid").put("port", 1080)))))
            else hop.put("config", JSONObject())
            hops.put(hop)
        }
        return JSONObject().put("version", 1).put("hops", hops).put("dns", "9.9.9.9")
            .put("baseConfig", JSONObject().put("inbounds", JSONArray()
                .put(JSONObject().put("tag", "tun-in").put("protocol", "tun")))
                .put("stats", JSONObject()).put("policy", JSONObject()))
    }

    @Test fun nativeEngineConsumesPreviousPrefixRatherThanProxyingLocalhostThroughIt() {
        val result = MixRouting.sidecar(plan("xray", "warp", "xray"),
            listOf(20001, 20002, 20003), mapOf(1 to 21001), emptyMap())
        val outbounds = result.getJSONArray("outbounds")
        val exit = outbounds.getJSONObject(0)
        assertEquals("mix-stage-2", exit.getString("tag"))
        assertEquals("mix-stage-1", exit.getJSONObject("streamSettings")
            .getJSONObject("sockopt").getString("dialerProxy"))
        val worker = (0 until outbounds.length()).map { outbounds.getJSONObject(it) }
            .single { it.getString("tag") == "mix-stage-1" }
        assertFalse(worker.has("streamSettings"))
        assertEquals(21001, worker.getJSONObject("settings").getJSONArray("servers")
            .getJSONObject(0).getInt("port"))
        val rules = result.getJSONObject("routing").getJSONArray("rules")
        for (i in 0..2) {
            assertEquals("mix-prefix-$i", rules.getJSONObject(i).getJSONArray("inboundTag").getString(0))
            assertEquals("mix-stage-$i", rules.getJSONObject(i).getString("outboundTag"))
        }
        assertFalse(result.toString().contains("freedom"))
    }

    @Test fun dnsUsesTcpThroughTheFullExitAndNoDirectFallbackIsEmitted() {
        val result = MixRouting.vpn(plan("warp", "sstp"), 22000, true)
        assertEquals(1, result.getJSONArray("inbounds").length())
        assertEquals("tun", result.getJSONArray("inbounds").getJSONObject(0).getString("protocol"))
        val dns = result.getJSONArray("outbounds").getJSONObject(1)
        assertEquals("tcp", dns.getJSONObject("settings").getString("network"))
        assertEquals("9.9.9.9", dns.getJSONObject("settings").getString("address"))
        assertEquals(53, dns.getJSONObject("settings").getInt("port"))
        assertEquals("skip", dns.getJSONObject("settings").getString("nonIPQuery"))
        assertEquals("proxy", dns.getJSONObject("streamSettings").getJSONObject("sockopt").getString("dialerProxy"))
        assertFalse(result.toString().contains("freedom"))
        assertFalse(MixRouting.vpn(plan("psiphon"), 22000, false, true).has("inbounds"))
    }

    @Test fun tcpOnlyPrefixBlocksOtherUdpButNotDns() {
        val result = MixRouting.vpn(plan("psiphon"), 22000, false)
        val rules = result.getJSONObject("routing").getJSONArray("rules")
        assertEquals("mix-dns", rules.getJSONObject(0).getString("outboundTag"))
        assertEquals("mix-udp-block", rules.getJSONObject(1).getString("outboundTag"))
        assertEquals("blackhole", result.getJSONArray("outbounds").getJSONObject(2).getString("protocol"))
    }

    @Test fun unsupportedOrMissingWorkersFailClosed() {
        assertThrows(IllegalStateException::class.java) {
            MixRouting.sidecar(plan("warp"), listOf(20001), emptyMap(), emptyMap())
        }
        assertThrows(IllegalArgumentException::class.java) {
            MixRouting.sidecar(plan("slowdns"), listOf(20001), emptyMap(), emptyMap())
        }
    }

    private fun dnsPlan(vararg protocols: String): JSONObject {
        val hops = JSONArray()
        protocols.forEachIndexed { index, protocol ->
            when (protocol) {
                "direct_dns" -> hops.put(JSONObject().put("protocol", protocol).put("address", if (index == 2) "9.9.9.9" else "1.1.1.1"))
                "xray", "proxy" -> hops.put(JSONObject().put("protocol", protocol).put("outbound", JSONObject()
                    .put("protocol", "socks").put("settings", JSONObject().put("servers", JSONArray()
                        .put(JSONObject().put("address", "example.invalid").put("port", 1080))))))
                else -> hops.put(JSONObject().put("protocol", protocol).put("config", JSONObject()))
            }
        }
        return JSONObject().put("version", 1).put("hops", hops)
    }

    @Test fun resolverUsesCorrectDnsSettingsAndRoutesOwnQueriesBeforePort53() {
        val result = MixRouting.resolver("9.9.9.9", 23002, 20002)
        assertEquals("mix-dns-in", result.getJSONArray("inbounds").getJSONObject(0).getString("tag"))
        assertEquals("mix-resolver", result.getJSONObject("dns").getString("tag"))
        val dns = result.getJSONArray("outbounds").getJSONObject(1)
        assertEquals("dns-outbound", dns.getString("tag"))
        assertEquals("tcp", dns.getJSONObject("settings").getString("network"))
        assertEquals("9.9.9.9", dns.getJSONObject("settings").getString("address"))
        assertEquals(53, dns.getJSONObject("settings").getInt("port"))
        assertEquals("skip", dns.getJSONObject("settings").getString("nonIPQuery"))
        assertEquals("transport", dns.getJSONObject("streamSettings").getJSONObject("sockopt").getString("dialerProxy"))
        val rules = result.getJSONObject("routing").getJSONArray("rules")
        assertEquals("transport", rules.getJSONObject(0).getString("outboundTag"))
        assertEquals("dns-outbound", rules.getJSONObject(1).getString("outboundTag"))
        assertEquals("transport", rules.getJSONObject(2).getString("outboundTag"))
    }

    @Test fun dnsPrefixRulesUseLocalResolverSocksAndNearestResolverWins() {
        val result = MixRouting.sidecar(dnsPlan("direct_dns", "xray", "direct_dns", "xray"),
            listOf(20001, 20002, 20003, 20004), mapOf(1 to 21001, 3 to 21003),
            mapOf(0 to 23000, 2 to 23002))
        val rules = result.getJSONObject("routing").getJSONArray("rules")
        assertEquals("mix-dns-0", rules.getJSONObject(0).getString("outboundTag"))
        assertEquals("mix-stage-0", rules.getJSONObject(1).getString("outboundTag"))
        assertEquals("mix-dns-0", rules.getJSONObject(2).getString("outboundTag"))
        assertEquals("mix-stage-1", rules.getJSONObject(3).getString("outboundTag"))
        assertEquals("mix-dns-2", rules.getJSONObject(4).getString("outboundTag"))
        assertEquals("mix-stage-3", rules.getJSONObject(7).getString("outboundTag"))
        val dns = (0 until result.getJSONArray("outbounds").length())
            .map { result.getJSONArray("outbounds").getJSONObject(it) }
            .single { it.getString("tag") == "mix-dns-2" }
        assertEquals("socks", dns.getString("protocol"))
        assertEquals(23002, dns.getJSONObject("settings").getJSONArray("servers").getJSONObject(0).getInt("port"))
        assertFalse(result.toString().contains("rewriteNetwork"))
    }

    @Test fun directDnsDoesNotConsumeWorkerSlotsAndFiftyBlocksIsTheLimit() {
        val fifty = Array(50) { if (it == 0) "direct_dns" else "xray" }
        val ports = List(50) { 21000 + it }
        val workers = (1 until 50).associate { it to 22000 + it }
        val result = MixRouting.sidecar(dnsPlan(*fifty), ports, workers, mapOf(0 to 25000))
        assertEquals(50, result.getJSONArray("inbounds").length())
        assertEquals(51, result.getJSONArray("outbounds").length())
        assertEquals("mix-stage-49", result.getJSONArray("outbounds").getJSONObject(0).getString("tag"))
        assertThrows(IllegalArgumentException::class.java) {
            MixRouting.sidecar(dnsPlan(*fifty, "xray"), List(51) { 23000 + it },
                (1..50).associate { it to 24000 + it }, mapOf(0 to 25000))
        }
    }
    @Test fun dnsEgressUsesSelectedPrefixInsteadOfExit() {
        val p = plan("proxy", "proxy")
        val result = MixRouting.vpn(p, 22000, true, dnsExitPort = 21000)
        val outbounds = result.getJSONArray("outbounds")
        val dns = outbounds.getJSONObject(1)
        assertEquals("mix-dns-prefix", dns.getJSONObject("streamSettings")
            .getJSONObject("sockopt").getString("dialerProxy"))
        val prefix = outbounds.getJSONObject(2)
        assertEquals(21000, prefix.getJSONObject("settings").getJSONArray("servers")
            .getJSONObject(0).getInt("port"))
        assertEquals(22000, outbounds.getJSONObject(0).getJSONObject("settings")
            .getJSONArray("servers").getJSONObject(0).getInt("port"))
    }

    @Test fun fiftyNativeWorkersAreMappedWithoutDroppingAnyStage() {
        val p = plan(*Array(50) { "warp" })
        val result = MixRouting.sidecar(p, List(50) { 20000 + it },
            (0 until 50).associateWith { 21000 + it }, emptyMap())
        val outbounds = result.getJSONArray("outbounds")
        assertEquals(50, outbounds.length())
        for (i in 0 until 50) {
            val stage = (0 until 50).map { outbounds.getJSONObject(it) }
                .single { it.getString("tag") == "mix-stage-$i" }
            assertEquals(21000 + i, stage.getJSONObject("settings")
                .getJSONArray("servers").getJSONObject(0).getInt("port"))
            assertFalse(stage.has("streamSettings"))
        }
    }

    @Test fun dnsAddressesAreNumericAndValidatedWithoutHostLookup() {
        for (address in listOf("999.1.1.1", "abc", "1:2:3", "dns.example", "")) {
            val p = dnsPlan("direct_dns", "proxy")
            p.getJSONArray("hops").getJSONObject(0).put("address", address)
            assertThrows(IllegalArgumentException::class.java) {
                MixRouting.sidecar(p, listOf(20000, 20001), emptyMap(), mapOf(0 to 25000))
            }
        }
        val p = dnsPlan("direct_dns", "proxy")
        p.getJSONArray("hops").getJSONObject(0).put("address", "2606:4700:4700::1111")
        assertEquals(2, MixRouting.sidecar(p, listOf(20000, 20001), emptyMap(), mapOf(0 to 25000))
            .getJSONArray("inbounds").length())
    }

    @Test fun resolverRawPrefixBypassesEarlierDnsPoliciesButNeverTunnelStages() {
        val result = MixRouting.sidecar(dnsPlan("proxy", "direct_dns", "proxy", "direct_dns"),
            listOf(20000, 20001, 20002, 20003), emptyMap(),
            mapOf(1 to 23001, 3 to 23003), mapOf(0 to 24000, 2 to 24002))
        val rules = result.getJSONObject("routing").getJSONArray("rules")
        for (stage in listOf(0, 2)) {
            val rule = (0 until rules.length()).map { rules.getJSONObject(it) }
                .single { it.getJSONArray("inboundTag").getString(0) == "mix-raw-prefix-$stage" }
            assertEquals("mix-stage-$stage", rule.getString("outboundTag"))
            assertFalse(rule.has("port"))
        }
    }

    @Test fun udpRelayWrapsStagesWithoutCreatingADialerCycle() {
        val result = MixRouting.sidecar(
            plan("xray", "proxy"),
            listOf(20000, 20001),
            emptyMap(), emptyMap(),
            udpRelayPorts = mapOf(0 to 21000, 1 to 21001),
            relayUnderlayPorts = mapOf(0 to 22000, 1 to 22001)
        )
        val outbounds = (0 until result.getJSONArray("outbounds").length())
            .map { result.getJSONArray("outbounds").getJSONObject(it) }
            .associateBy { it.getString("tag") }
        assertEquals("socks", outbounds["mix-stage-0"]!!.getString("protocol"))
        assertEquals(21000, outbounds["mix-stage-0"]!!.getJSONObject("settings")
            .getJSONArray("servers").getJSONObject(0).getInt("port"))
        assertEquals("mix-stage-0", outbounds["mix-underlay-1"]!!
            .getJSONObject("streamSettings").getJSONObject("sockopt")
            .getString("dialerProxy"))
        assertEquals("mix-underlay-0", (0 until result.getJSONObject("routing")
            .getJSONArray("rules").length()).map { result.getJSONObject("routing")
            .getJSONArray("rules").getJSONObject(it) }.single {
                it.getJSONArray("inboundTag").getString(0) == "mix-relay-underlay-0"
            }.getString("outboundTag"))
        assertEquals(22001, (0 until result.getJSONArray("inbounds").length())
            .map { result.getJSONArray("inbounds").getJSONObject(it) }.single {
                it.getString("tag") == "mix-relay-underlay-1"
            }.getInt("port"))
        assertThrows(IllegalArgumentException::class.java) {
            MixRouting.sidecar(plan("direct_dns"), listOf(20000), emptyMap(), mapOf(0 to 23000),
                udpRelayPorts = mapOf(0 to 24000), relayUnderlayPorts = mapOf(0 to 25000))
        }
    }

}
