package com.forwin.vpn.mix

import org.json.JSONArray
import org.json.JSONObject

/** Pure config construction. Every prefix is a SOCKS endpoint consumed by the next engine. */
internal object MixRouting {
    val nativeProtocols = setOf("warp", "sstp", "openvpn", "psiphon")

    fun sidecar(plan: JSONObject, prefixPorts: List<Int>, workerPorts: Map<Int, Int>): JSONObject {
        val hops = plan.getJSONArray("hops")
        require(hops.length() in 1..16 && prefixPorts.size == hops.length()) { "Invalid Mix hop count" }
        val outbounds = mutableListOf<JSONObject>()
        val inbounds = JSONArray()
        val rules = JSONArray()
        for (i in 0 until hops.length()) {
            val hop = hops.getJSONObject(i)
            val protocol = hop.getString("protocol")
            val tag = "mix-stage-$i"
            val outbound: JSONObject
            if (protocol in nativeProtocols) {
                val port = workerPorts[i] ?: error("No worker assigned to stage ${i + 1}")
                outbound = socksOutbound(tag, port)
                // The engine itself dials its prior prefix. Adding dialerProxy here
                // would try to reach a localhost worker THROUGH a remote tunnel.
            } else {
                require(protocol == "xray" || protocol == "proxy") { "Unknown Mix stage" }
                outbound = JSONObject(hop.getJSONObject("outbound").toString()).put("tag", tag)
                require(outbound.optString("protocol") in setOf("vless", "vmess", "trojan", "shadowsocks", "socks", "http")) {
                    "Unsupported Xray outbound at stage ${i + 1}"
                }
                val stream = outbound.optJSONObject("streamSettings") ?: JSONObject()
                val socket = stream.optJSONObject("sockopt") ?: JSONObject()
                socket.remove("dialerProxy")
                if (i > 0) socket.put("dialerProxy", "mix-stage-${i - 1}")
                socket.put("domainStrategy", "AsIs")
                stream.put("sockopt", socket)
                outbound.put("streamSettings", stream)
                outbound.remove("proxySettings")
            }
            outbounds.add(outbound)
            inbounds.put(JSONObject().put("tag", "mix-prefix-$i").put("listen", "127.0.0.1")
                .put("port", prefixPorts[i]).put("protocol", "socks")
                .put("settings", JSONObject().put("auth", "noauth").put("udp", true)))
            rules.put(JSONObject().put("type", "field").put("inboundTag", JSONArray().put("mix-prefix-$i"))
                .put("outboundTag", tag))
        }
        val ordered = JSONArray().put(outbounds.last())
        outbounds.dropLast(1).forEach { ordered.put(it) }
        return JSONObject().put("log", JSONObject().put("loglevel", "warning"))
            .put("inbounds", inbounds).put("outbounds", ordered)
            .put("routing", JSONObject().put("domainStrategy", "AsIs").put("rules", rules))
    }

    fun vpn(plan: JSONObject, exitPort: Int, supportsUdp: Boolean, probe: Boolean = false): JSONObject {
        val config = JSONObject(plan.getJSONObject("baseConfig").toString())
        val dns = plan.optString("dns", "1.1.1.1")
        require(dns.isNotBlank() && !dns.contains('/') && !dns.contains("://")) { "Invalid Mix DNS address" }
        val proxy = socksOutbound("proxy", exitPort)
        val dnsOutbound = JSONObject().put("tag", "mix-dns").put("protocol", "dns")
            .put("settings", JSONObject().put("rewriteNetwork", "tcp").put("rewriteAddress", dns)
                .put("rewritePort", 53).put("rules", JSONArray().put(JSONObject().put("action", "direct"))))
            .put("streamSettings", JSONObject().put("sockopt", JSONObject()
                .put("dialerProxy", "proxy").put("domainStrategy", "AsIs")))
        val outbounds = JSONArray().put(proxy).put(dnsOutbound)
        val rules = JSONArray().put(JSONObject().put("type", "field").put("port", "53")
            .put("network", "tcp,udp").put("outboundTag", "mix-dns"))
        if (!supportsUdp) {
            outbounds.put(JSONObject().put("tag", "mix-udp-block").put("protocol", "blackhole"))
            rules.put(JSONObject().put("type", "field").put("network", "udp").put("outboundTag", "mix-udp-block"))
        }
        rules.put(JSONObject().put("type", "field").put("network", "tcp,udp").put("outboundTag", "proxy"))
        config.put("outbounds", outbounds).put("routing", JSONObject()
            .put("domainStrategy", "AsIs").put("rules", rules))
        val resolver = if (dns.contains(':')) "tcp://[$dns]" else "tcp://$dns"
        config.put("dns", JSONObject().put("servers", JSONArray().put(resolver)).put("tag", "mix-resolver"))
        if (probe) config.remove("inbounds") else {
            val original = config.getJSONArray("inbounds")
            val tun = (0 until original.length()).map { original.getJSONObject(it) }
                .single { it.optString("protocol") == "tun" }
            config.put("inbounds", JSONArray().put(tun))
        }
        return config
    }

    private fun socksOutbound(tag: String, port: Int): JSONObject = JSONObject()
        .put("tag", tag).put("protocol", "socks")
        .put("settings", JSONObject().put("servers", JSONArray().put(JSONObject()
            .put("address", "127.0.0.1").put("port", port))))
}
