package com.forwin.vpn.slowdns

import org.json.JSONArray
import org.json.JSONObject

/** Packet bridge only: every TCP flow uses dnstt and non-DNS UDP is rejected. */
object SlowDnsXrayConfig {
    fun build(localPort: Int, username: String?, password: String?): String {
        require(localPort in 1..65535)
        val server = JSONObject().put("address", "127.0.0.1").put("port", localPort)
        if (username != null) {
            server.put("users", JSONArray().put(JSONObject().put("user", username).put("pass", password)))
        }
        val tunnel = JSONObject().put("tag", "slowdns").put("protocol", "socks")
            .put("settings", JSONObject().put("servers", JSONArray().put(server)))
        // The DNS outbound rewrites both UDP/TCP DNS to TCP/53. proxySettings
        // forces that stream through dnstt, not through a freedom/direct outbound.
        val dns = JSONObject().put("tag", "dns-out").put("protocol", "dns")
            .put("settings", JSONObject().put("network", "tcp").put("address", "1.1.1.1")
                .put("port", 53).put("nonIPQuery", "skip"))
            .put("proxySettings", JSONObject().put("tag", "slowdns"))
        val blocked = JSONObject().put("tag", "block").put("protocol", "blackhole")
        val rules = JSONArray()
            .put(JSONObject().put("type", "field").put("port", "53")
                .put("network", "tcp,udp").put("inboundTag", JSONArray().put("socks"))
                .put("outboundTag", "dns-out"))
            .put(JSONObject().put("type", "field").put("network", "udp").put("outboundTag", "block"))
        val stats = JSONObject()
        val policy = JSONObject().put("system", JSONObject()
            .put("statsOutboundUplink", true).put("statsOutboundDownlink", true))
        return JSONObject()
            .put("stats", stats)
            .put("policy", policy)
            .put("log", JSONObject().put("loglevel", "none"))
            .put("dns", JSONObject().put("servers", JSONArray().put("tcp://1.1.1.1"))
                .put("queryStrategy", "UseIP"))
            .put("inbounds", JSONArray().put(JSONObject().put("tag", "socks")
                .put("listen", "127.0.0.1").put("port", 10808).put("protocol", "socks")
                .put("settings", JSONObject().put("auth", "noauth").put("udp", true))))
            .put("outbounds", JSONArray().put(tunnel).put(dns).put(blocked))
            .put("routing", JSONObject().put("domainStrategy", "AsIs").put("rules", rules))
            .toString()
    }
}
