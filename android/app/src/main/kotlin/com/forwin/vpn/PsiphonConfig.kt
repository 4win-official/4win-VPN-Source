package com.forwin.vpn

import org.json.JSONObject

/** Standalone proxy-mode config; never imports Mix packet-FD or datastore settings. */
internal object PsiphonConfig {
    fun build(bootstrap: JSONObject, region: String): JSONObject {
        val result = JSONObject(bootstrap.toString())
        require(result.optString("PropagationChannelId").isNotBlank()) { "Psiphon bootstrap missing propagation channel" }
        require(result.optString("SponsorId").isNotBlank()) { "Psiphon bootstrap missing sponsor" }
        require(result.optString("ClientVersion").toIntOrNull() != null) { "Psiphon bootstrap missing numeric client version" }
        require(result.optJSONArray("RemoteServerListURLs")?.length()?.let { it > 0 } == true) { "Psiphon bootstrap missing server list" }
        require(result.optString("RemoteServerListSignaturePublicKey").isNotBlank()) { "Psiphon bootstrap missing server list signing key" }
        return result
            .put("EgressRegion", region)
            // Zero requests a free port, reported by onListeningSocksProxyPort.
            // Fixed 1080/8080 collide with other local proxies and prevent startup.
            .put("LocalSocksProxyPort", 0)
            .put("LocalHttpProxyPort", 0)
            .put("DisableLocalHTTPProxy", true)
            .put("EmitBytesTransferred", true)
            .put("EstablishTunnelTimeoutSeconds", 0)
    }
}
