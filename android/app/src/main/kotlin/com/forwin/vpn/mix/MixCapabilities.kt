package com.forwin.vpn.mix

import org.json.JSONObject

/** Transport requirements are different from the capabilities INSIDE a tunnel.
 * For example SSTP/OpenVPN-TCP/VLESS can carry UDP over a TCP-only underlay.
 */
internal object MixCapabilities {
    private val supportedOutbounds = setOf("http", "socks", "shadowsocks",
        "vless", "vmess", "trojan")

    private fun outboundProtocol(hop: JSONObject): String {
        val outbound = hop.optJSONObject("outbound")
            ?: error("Mix proxy stage is missing an outbound")
        val protocol = outbound.optString("protocol")
        require(protocol in supportedOutbounds) {
            "Unsupported Mix outbound capability"
        }
        return protocol
    }

    /**
     * Validate the statically knowable UDP capability of a complete Mix plan.
     * Native packet-tunnel stages are deliberately treated as restoration
     * boundaries: their actual readiness is still reported by the worker.
     */
    fun validatePlan(plan: JSONObject, relayConfigured: Boolean) {
        val hops = plan.optJSONArray("hops")
            ?: throw IllegalArgumentException("Mix plan is missing hops")
        require(hops.length() in 1..50) { "Mix supports 1 to 50 blocks" }
        var upstreamUdp = true
        for (index in 0 until hops.length()) {
            val hop = hops.optJSONObject(index)
                ?: throw IllegalArgumentException("Mix hop ${index + 1} is not an object")
            when (hop.optString("protocol")) {
                "xray", "proxy" -> {
                    val relayNeeded = needsRelay(hop)
                    upstreamUdp = afterXray(hop, upstreamUdp)
                    if (relayNeeded && relayConfigured) upstreamUdp = true
                }
                "warp" -> {
                    require(upstreamUdp) {
                        "Stage ${index + 1}: WARP needs a UDP-capable preceding path; " +
                            "HTTP CONNECT and SOCKS4 do not carry UDP by themselves"
                    }
                    upstreamUdp = true
                }
                in (MixRouting.nativeProtocols - "warp") -> {
                    // Native workers report their real output capability at runtime.
                    upstreamUdp = true
                }
                "direct_dns" -> Unit
                else -> throw IllegalArgumentException("Unknown Mix stage at ${index + 1}")
            }
        }
    }

    // Psiphon workers use the authenticated native packet-tunnel channel;
    // their UDP is supplied by Psiphon's own server, not an external relay.
    fun needsRelay(hop: JSONObject): Boolean {
        if (hop.optString("protocol") !in setOf("xray", "proxy")) return false
        if (hop.has("socks4")) {
            require(hop.optString("protocol") == "proxy") {
                "SOCKS4 is only valid on a proxy Mix stage"
            }
            return true
        }
        return outboundProtocol(hop) in setOf("http", "socks", "shadowsocks")
    }

    fun afterXray(hop: JSONObject, upstreamUdp: Boolean): Boolean =
        if (hop.has("socks4")) {
            require(hop.optString("protocol") == "proxy") {
                "SOCKS4 is only valid on a proxy Mix stage"
            }
            false
        } else when (outboundProtocol(hop)) {
            "http" -> false
            // SOCKS/ordinary Shadowsocks send UDP datagrams through their
            // underlay; unlike stream-tunneled VLESS/VMess/Trojan, they cannot
            // restore UDP after an unsupported preceding transport by themselves.
            "socks", "shadowsocks" -> upstreamUdp
            "vless", "vmess", "trojan" -> true
            else -> error("Unsupported Mix outbound capability")
        }
}
