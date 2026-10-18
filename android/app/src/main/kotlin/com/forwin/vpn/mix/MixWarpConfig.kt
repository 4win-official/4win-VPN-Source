package com.forwin.vpn.mix

import org.json.JSONObject

/** Mix-only translation into Aether's strict NativeStartOptions schema. */
internal object MixWarpConfig {
    @JvmOverloads
    fun build(config: JSONObject, privateRoot: String, listenPort: Int, upstream: String?, identityPath: String? = null): JSONObject {
        require(listenPort in 1..65535) { "Invalid Mix SOCKS port" }
        val effective = JSONObject(config.toString())
        // Older coordinators included this capability flag in the engine JSON.
        // It belongs to MixAdapterEnvironment, not Rust's strict config schema.
        effective.remove("upstreamSupportsUdp")
        effective.keys().asSequence().toList().forEach { key ->
            val value = effective.opt(key)
            if (value is String && value.contains("__APP_FILES__")) {
                effective.put(key, value.replace("__APP_FILES__", privateRoot))
            }
        }
        // Mix identities are persistent per stage, not per session. Do this
        // after placeholder expansion so both legacy path spellings agree.
        if (identityPath != null) {
            effective.put("config_path", identityPath)
                .put("wireguard_config_path", identityPath)
        }
        effective.put("listen", "127.0.0.1:$listenPort")
            .put("mix_force_tunnel", true).put("gateway", false)
        if (upstream != null) effective.put("upstream_proxy", upstream)
        else effective.remove("upstream_proxy")
        return effective
    }
}
