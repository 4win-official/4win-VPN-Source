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
            listOf(20001, 20002, 20003), mapOf(1 to 21001))
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
        assertEquals("tcp", dns.getJSONObject("settings").getString("rewriteNetwork"))
        assertEquals("9.9.9.9", dns.getJSONObject("settings").getString("rewriteAddress"))
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
            MixRouting.sidecar(plan("warp"), listOf(20001), emptyMap())
        }
        assertThrows(IllegalArgumentException::class.java) {
            MixRouting.sidecar(plan("slowdns"), listOf(20001), emptyMap())
        }
    }
}
