package com.forwin.vpn

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PsiphonTunBridgeConfigTest {
    private fun config(): JSONObject {
        val method = PsiphonTunBridge::class.java.getDeclaredMethod("buildConfig", Int::class.javaPrimitiveType)
        method.isAccessible = true
        return JSONObject(method.invoke(PsiphonTunBridge, 19080) as String)
    }

    @Test fun dnsIsCarriedOverTcpThroughPsiphon() {
        val root = config()
        val outbounds = root.getJSONArray("outbounds")
        val dns = (0 until outbounds.length()).map { outbounds.getJSONObject(it) }
            .single { it.getString("tag") == "psiphon-dns" }
        assertEquals("dns", dns.getString("protocol"))
        assertEquals("tcp", dns.getJSONObject("settings").getString("network"))
        assertEquals("psiphon", dns.getJSONObject("proxySettings").getString("tag"))
        assertEquals("tcp://1.1.1.1", root.getJSONObject("dns").getJSONArray("servers").getString(0))
    }

    @Test fun nonDnsUdpIsBlockedAndTcpUsesPsiphon() {
        val rules = config().getJSONObject("routing").getJSONArray("rules")
        assertEquals("psiphon-dns", rules.getJSONObject(0).getString("outboundTag"))
        assertEquals("block-udp", rules.getJSONObject(1).getString("outboundTag"))
        assertEquals("udp", rules.getJSONObject(1).getString("network"))
        assertEquals("psiphon", rules.getJSONObject(2).getString("outboundTag"))
        assertTrue(rules.getJSONObject(2).getString("network").contains("tcp"))
    }
}
