package com.forwin.vpn.mix

import org.json.JSONArray
import org.json.JSONObject

/** Pure config construction. Every prefix is a SOCKS endpoint consumed by the next engine. */
internal object MixRouting {
    val nativeProtocols = setOf("warp", "sstp", "openvpn", "psiphon")
    private const val MAX_BLOCKS = 50

    fun sidecar(
        plan: JSONObject,
        prefixPorts: List<Int>,
        workerPorts: Map<Int, Int>,
        dnsPorts: Map<Int, Int>,
        rawPrefixPorts: Map<Int, Int> = emptyMap(),
        udpRelayPorts: Map<Int, Int> = emptyMap(),
        relayUnderlayPorts: Map<Int, Int> = emptyMap()
    ): JSONObject {
        val hops = plan.getJSONArray("hops")
        require(hops.length() in 1..MAX_BLOCKS && prefixPorts.size == hops.length()) {
            "Invalid Mix hop count"
        }
        require(prefixPorts.all { it in 1..65535 }) { "Invalid Mix prefix port" }
        require(udpRelayPorts.keys == relayUnderlayPorts.keys) {
            "UDP relay maps must contain the same stages"
        }
        val listenerPorts = (prefixPorts + workerPorts.values + dnsPorts.values +
            rawPrefixPorts.values + udpRelayPorts.values + relayUnderlayPorts.values)
        require(listenerPorts.all { it in 1..65535 } && listenerPorts.toSet().size == listenerPorts.size) {
            "Mix listener ports must be valid and distinct"
        }
        udpRelayPorts.forEach { (stage, relayPort) ->
            require(stage in 0 until hops.length() && relayPort in 1..65535 &&
                relayUnderlayPorts.getValue(stage) in 1..65535) { "Invalid UDP relay stage" }
            require(hops.getJSONObject(stage).getString("protocol") != "direct_dns") {
                "UDP relay cannot wrap a DNS stage"
            }
        }
        val outbounds = mutableListOf<JSONObject>()
        val inbounds = JSONArray()
        val rules = JSONArray()
        var nearestDnsStage: Int? = null

        for (i in 0 until hops.length()) {
            val hop = hops.getJSONObject(i)
            val protocol = hop.getString("protocol")
            val tag = "mix-stage-$i"
            val outbound: JSONObject
            val wrapped = udpRelayPorts.containsKey(i)
            if (protocol == "direct_dns") {
                require(!wrapped) { "UDP relay cannot wrap a DNS stage" }
                val address = hop.optString("address").trim()
                require(isIpAddress(address)) { "Invalid direct_dns address at stage ${i + 1}" }
                outbound = JSONObject().put("tag", tag).put("protocol", "freedom")
                    .put("settings", JSONObject())
                val socket = JSONObject().put("domainStrategy", "AsIs")
                if (i > 0) socket.put("dialerProxy", "mix-stage-${i - 1}")
                outbound.put("streamSettings", JSONObject().put("sockopt", socket))
                val dnsPort = dnsPorts[i] ?: error("No DNS resolver assigned to stage ${i + 1}")
                outbounds.add(socksOutbound("mix-dns-$i", dnsPort))
                nearestDnsStage = i
            } else if (protocol in nativeProtocols) {
                val port = workerPorts[i] ?: error("No worker assigned to stage ${i + 1}")
                outbound = socksOutbound(tag, port)
            } else if (protocol == "proxy" && hop.has("socks4")) {
                // SOCKS4 is converted by the Mix-only adapter. That adapter
                // consumes the previous prefix itself, just like a native hop.
                val port = workerPorts[i] ?: error("No SOCKS4 adapter assigned to stage ${i + 1}")
                outbound = socksOutbound(tag, port)
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
            if (wrapped) {
                // The relay's TCP-facing underlay must enter the original
                // outbound directly. It must not use the public stage tag,
                // otherwise the wrapper would dial itself through a cycle.
                outbound.put("tag", "mix-underlay-$i")
                outbounds.add(outbound)
                outbounds.add(socksOutbound(tag, udpRelayPorts.getValue(i)))
                inbounds.put(JSONObject().put("tag", "mix-relay-underlay-$i")
                    .put("listen", "127.0.0.1")
                    .put("port", relayUnderlayPorts.getValue(i))
                    .put("protocol", "socks")
                    .put("settings", JSONObject().put("auth", "noauth").put("udp", true)))
                // This is deliberately before the stage's normal rule and
                // has no port-53 matcher: relay traffic bypasses DNS policy.
                rules.put(JSONObject().put("type", "field")
                    .put("inboundTag", JSONArray().put("mix-relay-underlay-$i"))
                    .put("outboundTag", "mix-underlay-$i"))
            } else {
                outbounds.add(outbound)
            }
            inbounds.put(JSONObject().put("tag", "mix-prefix-$i").put("listen", "127.0.0.1")
                .put("port", prefixPorts[i]).put("protocol", "socks")
                .put("settings", JSONObject().put("auth", "noauth").put("udp", true)))
            nearestDnsStage?.let { dnsStage ->
                rules.put(JSONObject().put("type", "field")
                    .put("inboundTag", JSONArray().put("mix-prefix-$i"))
                    .put("port", 53).put("network", "tcp,udp")
                    .put("outboundTag", "mix-dns-$dnsStage"))
            }
            rules.put(JSONObject().put("type", "field").put("inboundTag", JSONArray().put("mix-prefix-$i"))
                .put("outboundTag", tag))
        }
        // A resolver must use the preceding tunnel transport without re-entering
        // an earlier resolver policy. Separate raw listeners avoid DNS recursion
        // and preserve the selected address when several DNS blocks are present.
        rawPrefixPorts.forEach { (stage, port) ->
            require(stage in 0 until hops.length() - 1 &&
                hops.getJSONObject(stage + 1).getString("protocol") == "direct_dns") {
                "Raw prefix must feed the following direct_dns stage"
            }
            val tag = "mix-raw-prefix-$stage"
            inbounds.put(JSONObject().put("tag", tag).put("listen", "127.0.0.1")
                .put("port", port).put("protocol", "socks")
                .put("settings", JSONObject().put("auth", "noauth").put("udp", true)))
            rules.put(JSONObject().put("type", "field").put("inboundTag", JSONArray().put(tag))
                .put("outboundTag", "mix-stage-$stage"))
        }
        val ordered = JSONArray().put(outbounds.last())
        outbounds.dropLast(1).forEach { ordered.put(it) }
        return JSONObject().put("log", JSONObject().put("loglevel", "warning"))
            .put("inbounds", inbounds).put("outbounds", ordered)
            .put("routing", JSONObject().put("domainStrategy", "AsIs").put("rules", rules))
    }

    /** A TUN-less, one-purpose DNS core for one direct_dns stage. */
    fun resolver(address: String, listenPort: Int, upstreamPort: Int?): JSONObject {
        require(isIpAddress(address)) { "Invalid resolver address" }
        require(listenPort in 1..65535 && (upstreamPort == null || upstreamPort in 1..65535)) {
            "Invalid resolver port"
        }
        val transport = if (upstreamPort == null) {
            JSONObject().put("tag", "transport").put("protocol", "freedom")
                .put("settings", JSONObject())
                .put("streamSettings", JSONObject().put("sockopt", JSONObject().put("domainStrategy", "AsIs")))
        } else socksOutbound("transport", upstreamPort)
        val dns = JSONObject().put("tag", "dns-outbound").put("protocol", "dns")
            .put("settings", JSONObject().put("network", "tcp").put("address", address)
                .put("port", 53).put("nonIPQuery", "skip"))
            .put("streamSettings", JSONObject().put("sockopt", JSONObject()
                .put("dialerProxy", "transport").put("domainStrategy", "AsIs")))
        val rules = JSONArray()
            .put(JSONObject().put("type", "field").put("inboundTag", JSONArray().put("mix-resolver"))
                .put("outboundTag", "transport"))
            .put(JSONObject().put("type", "field").put("port", 53)
                .put("network", "tcp,udp").put("outboundTag", "dns-outbound"))
            .put(JSONObject().put("type", "field").put("network", "tcp,udp").put("outboundTag", "transport"))
        return JSONObject().put("log", JSONObject().put("loglevel", "warning"))
            .put("dns", JSONObject().put("servers", JSONArray().put(uri(address))).put("tag", "mix-resolver"))
            .put("inbounds", JSONArray().put(JSONObject().put("tag", "mix-dns-in")
                .put("listen", "127.0.0.1").put("port", listenPort).put("protocol", "socks")
                .put("settings", JSONObject().put("auth", "noauth").put("udp", true))))
            .put("outbounds", JSONArray().put(transport).put(dns))
            .put("routing", JSONObject().put("domainStrategy", "AsIs").put("rules", rules))
    }

    fun vpn(plan: JSONObject, exitPort: Int, supportsUdp: Boolean, probe: Boolean = false,
            dnsExitPort: Int = exitPort): JSONObject {
        val config = JSONObject(plan.getJSONObject("baseConfig").toString())
        val dns = plan.optString("dns", "1.1.1.1").trim()
        require(isIpAddress(dns)) { "Invalid Mix DNS address" }
        require(exitPort in 1..65535 && dnsExitPort in 1..65535) { "Invalid Mix prefix port" }
        val proxy = socksOutbound("proxy", exitPort)
        val dnsUsesExit = dnsExitPort == exitPort
        val dnsOutbound = JSONObject().put("tag", "mix-dns").put("protocol", "dns")
            .put("settings", JSONObject().put("network", "tcp").put("address", dns)
                .put("port", 53).put("nonIPQuery", "skip"))
            .put("streamSettings", JSONObject().put("sockopt", JSONObject()
                .put("dialerProxy", if (dnsUsesExit) "proxy" else "mix-dns-prefix")
                .put("domainStrategy", "AsIs")))
        val outbounds = JSONArray().put(proxy).put(dnsOutbound)
        if (!dnsUsesExit) outbounds.put(socksOutbound("mix-dns-prefix", dnsExitPort))
        val rules = JSONArray().put(JSONObject().put("type", "field").put("port", "53")
            .put("network", "tcp,udp").put("outboundTag", "mix-dns"))
        if (!supportsUdp) {
            outbounds.put(JSONObject().put("tag", "mix-udp-block").put("protocol", "blackhole"))
            rules.put(JSONObject().put("type", "field").put("network", "udp").put("outboundTag", "mix-udp-block"))
        }
        rules.put(JSONObject().put("type", "field").put("network", "tcp,udp").put("outboundTag", "proxy"))
        config.put("outbounds", outbounds).put("routing", JSONObject()
            .put("domainStrategy", "AsIs").put("rules", rules))
        config.put("dns", JSONObject().put("servers", JSONArray().put(uri(dns))).put("tag", "mix-resolver"))
        if (probe) config.remove("inbounds") else {
            val original = config.getJSONArray("inbounds")
            val tun = (0 until original.length()).map { original.getJSONObject(it) }
                .single { it.optString("protocol") == "tun" }
            config.put("inbounds", JSONArray().put(tun))
        }
        return config
    }

    private fun uri(address: String): String = if (address.contains(':')) "tcp://[$address]" else "tcp://$address"

    private fun socksOutbound(tag: String, port: Int): JSONObject = JSONObject()
        .put("tag", tag).put("protocol", "socks")
        .put("settings", JSONObject().put("servers", JSONArray().put(JSONObject()
            .put("address", "127.0.0.1").put("port", port))))

    private fun isIpAddress(value: String): Boolean {
        if (value.matches(Regex("(?:\\d{1,3}\\.){3}\\d{1,3}"))) {
            return value.split('.').all { it.toInt() in 0..255 }
        }
        return value.contains(':') && value.matches(Regex("[0-9a-fA-F:]+")) &&
            runCatching { java.net.InetAddress.getByName(value) is java.net.Inet6Address }.getOrDefault(false)
    }
}
