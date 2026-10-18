package com.forwin.vpn.mix

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MixWarpConfigTest {
    private fun config() = JSONObject()
        .put("protocol", "wg")
        .put("config_path", "__APP_FILES__/aether-warp.toml")
        .put("wireguard_config_path", "__APP_FILES__/aether-warp.toml")
        .put("wireguard_data_check", true)
        .put("upstreamSupportsUdp", true)
        .put("gateway", true)
        .put("upstream_proxy", "socks5://stale.invalid:1080")

    @Test fun metadataNeverReachesStrictRustParserAndInputIsUnchanged() {
        val original = config()
        val snapshot = original.toString()
        val result = MixWarpConfig.build(original, "/private/mix/stage-0", 21000, null)
        assertFalse(result.has("upstreamSupportsUdp"))
        assertFalse(result.has("upstream_proxy"))
        assertEquals("wg", result.getString("protocol"))
        assertEquals("/private/mix/stage-0/aether-warp.toml", result.getString("config_path"))
        assertEquals(result.getString("config_path"), result.getString("wireguard_config_path"))
        assertEquals("127.0.0.1:21000", result.getString("listen"))
        assertTrue(result.getBoolean("mix_force_tunnel"))
        assertTrue(result.getBoolean("wireguard_data_check"))
        assertFalse(result.getBoolean("gateway"))
        assertEquals(snapshot, original.toString())
    }

    @Test fun innerWarpMustUseItsExactPreviousPrefix() {
        val result = MixWarpConfig.build(config(), "/private/mix/stage-2", 21002,
            "socks5://127.0.0.1:22001")
        assertEquals("socks5://127.0.0.1:22001", result.getString("upstream_proxy"))
        assertFalse(result.has("upstreamSupportsUdp"))
        assertTrue(result.getBoolean("mix_force_tunnel"))
    }

    @Test fun unrelatedUnknownFieldsAreNotSilentlyHiddenFromRustValidation() {
        val input = config().put("misspelled_option", true)
        assertTrue(MixWarpConfig.build(input, "/private/mix", 21000, null).has("misspelled_option"))
    }
}
