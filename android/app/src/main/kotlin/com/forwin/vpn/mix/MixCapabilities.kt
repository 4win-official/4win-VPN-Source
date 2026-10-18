package com.forwin.vpn.mix

import org.json.JSONObject

/** Transport requirements are different from the capabilities INSIDE a tunnel.
 * For example SSTP/OpenVPN-TCP/VLESS can carry UDP over a TCP-only underlay.
 */
internal object MixCapabilities {
    // Psiphon workers use the authenticated native packet-tunnel channel;
    // their UDP is supplied by Psiphon's own server, not an external relay.
    fun needsRelay(hop: JSONObject): Boolean =
        (hop.optString("protocol") in setOf("xray", "proxy") &&
            (hop.has("socks4") || hop.getJSONObject("outbound").optString("protocol") in setOf("http", "socks")))

    fun afterXray(hop: JSONObject, upstreamUdp: Boolean): Boolean =
        if (hop.has("socks4")) false else when (hop.getJSONObject("outbound").getString("protocol")) {
            "http" -> false
            // SOCKS/ordinary Shadowsocks send UDP datagrams through their
            // underlay; unlike stream-tunneled VLESS/VMess/Trojan, they cannot
            // restore UDP after an unsupported preceding transport by themselves.
            "socks", "shadowsocks" -> upstreamUdp
            "vless", "vmess", "trojan" -> true
            else -> error("Unsupported Mix outbound capability")
        }
}
