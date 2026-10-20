package com.forwin.vpn.slowdns

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SlowDnsConfigTest {
    private fun profile(transport: String = "udp") = JSONObject().apply {
        put("name", "fixture"); put("domain", "t.example.com"); put("nameServer", "1.1.1.1")
        put("pubKey", "ab".repeat(32)); put("port", JSONObject.NULL)
        put("username", JSONObject.NULL); put("password", JSONObject.NULL)
        put("dnsTransport", transport); put("dohUrl", JSONObject.NULL)
        put("resolvers", JSONArray())
        if (transport == "doh") put("dohUrl", "https://dns.example/dns-query")
    }
    @Test fun primaryResolverAndNullLegacyFieldsWork() {
        val cfg = SlowDnsConfig.fromJson(profile())
        assertEquals(listOf(SlowDnsConfig.Resolver("1.1.1.1", 53)), cfg.resolvers)
        assertNull(cfg.username); assertNull(cfg.password)
        assertEquals(listOf("/installed/libdnstt.so", "-udp", "1.1.1.1:53", "-pubkey",
            "ab".repeat(32), "t.example.com", "127.0.0.1:1234"),
            SlowDnsCommand.build(cfg, cfg.resolvers.first(), "/installed", 1234))
    }
    @Test fun failoversUseConfiguredPortAndAreDeduplicated() {
        val cfg = SlowDnsConfig.fromJson(profile().put("port", 5300)
            .put("resolvers", JSONArray().put("1.1.1.1").put("8.8.8.8")))
        assertEquals(listOf("1.1.1.1:5300", "8.8.8.8:5300"), cfg.resolvers.map { it.authority() })
    }
    @Test fun transportsHaveCorrectDefaultsAndNeverDowngradeDoh() {
        assertEquals(853, SlowDnsConfig.fromJson(profile("dot")).port)
        val cfg = SlowDnsConfig.fromJson(profile("doh").put("nameServer", ""))
        val args = SlowDnsCommand.build(cfg, cfg.resolvers.first(), "/lib", 1234)
        assertEquals("-doh", args[1]); assertEquals("https://dns.example/dns-query", args[2])
        assertFalse(args.contains("-udp")); assertFalse(args.contains("-dot"))
    }
    @Test fun ipv6ResolversAreRejectedForEveryTransport() {
        for (transport in listOf("udp", "dot", "doh")) {
            val input = profile(transport).put("nameServer", "[2001:db8::1]")
            if (transport == "doh") input.put("dohUrl", "https://[2001:db8::1]/dns-query")
            try { SlowDnsConfig.fromJson(input); fail("Accepted IPv6 resolver") }
            catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun rejectsBadKeysDomainsResolversAndCredentialPairs() {
        for (invalid in listOf(
            profile().put("pubKey", "aa"), profile().put("domain", "bad/name"),
            profile().put("nameServer", "999.1.2.3"), profile().put("nameServer", "1.1.1.1:53"),
            profile().put("username", "user"), profile().put("username", "é".repeat(128)).put("password", "p"),
            profile("doh").put("dohUrl", "http://example.com/dns-query"),
            profile("doh").put("dohUrl", "https://user:pass@example.com/dns-query"),
            profile().put("port", 65536)
        )) {
            try { SlowDnsConfig.fromJson(invalid); fail("Accepted invalid profile") }
            catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun routingHasNoDirectFallbackAndDnsPrecedesUdpBlock() {
        val config = JSONObject(SlowDnsXrayConfig.build(1234, "user", "pass"))
        val outbounds = config.getJSONArray("outbounds")
        assertEquals("socks", outbounds.getJSONObject(0).getString("protocol"))
        assertEquals("user", outbounds.getJSONObject(0).getJSONObject("settings")
            .getJSONArray("servers").getJSONObject(0).getJSONArray("users").getJSONObject(0).getString("user"))
        for (i in 0 until outbounds.length()) assertNotEquals("freedom", outbounds.getJSONObject(i).getString("protocol"))
        val dns = outbounds.getJSONObject(1)
        assertEquals("dns", dns.getString("protocol"))
        assertEquals("tcp", dns.getJSONObject("settings").getString("network"))
        assertEquals("slowdns", dns.getJSONObject("proxySettings").getString("tag"))
        assertTrue(config.has("stats"))
        val system = config.getJSONObject("policy").getJSONObject("system")
        assertTrue(system.getBoolean("statsOutboundUplink"))
        assertTrue(system.getBoolean("statsOutboundDownlink"))
        val rules = config.getJSONObject("routing").getJSONArray("rules")
        assertEquals("dns-out", rules.getJSONObject(0).getString("outboundTag"))
        assertEquals("block", rules.getJSONObject(1).getString("outboundTag"))
    }
}
