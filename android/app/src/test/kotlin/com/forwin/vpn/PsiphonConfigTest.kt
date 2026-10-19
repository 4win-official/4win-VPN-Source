package com.forwin.vpn

import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PsiphonConfigTest {
    private fun bootstrap(): JSONObject {
        val asset = generateSequence(File("").absoluteFile) { it.parentFile }
            .map { File(it, "android/app/src/main/assets/mix_psiphon_bootstrap.json") }
            .first { it.isFile }
        return JSONObject(asset.readText())
    }

    @Test fun standaloneIncludesRequiredIdsAndSignedDiscoveryOnFirstInstall() {
        val source = bootstrap()
        val before = source.toString()
        val config = PsiphonConfig.build(source, "NL")
        assertEquals(before, source.toString())
        assertEquals("NL", config.getString("EgressRegion"))
        for (key in listOf("ClientVersion", "SponsorId", "PropagationChannelId",
            "RemoteServerListSignaturePublicKey")) {
            assertEquals(source.getString(key), config.getString(key))
        }
        assertEquals(source.getJSONArray("RemoteServerListURLs").toString(),
            config.getJSONArray("RemoteServerListURLs").toString())
        assertFalse(config.has("PacketTunnelTunFileDescriptor"))
        assertFalse(config.has("DataRootDirectory")) // preserve standalone SDK data/migration
        assertFalse(config.has("UpstreamProxyURL"))
    }

    @Test fun autoRegionAndEphemeralProxyAvoidFixedPortCollisions() {
        val config = PsiphonConfig.build(bootstrap(), "")
        assertEquals("", config.getString("EgressRegion"))
        assertEquals(0, config.getInt("LocalSocksProxyPort"))
        assertFalse(config.optBoolean("DisableLocalSocksProxy", false))
        assertEquals(0, config.getInt("LocalHttpProxyPort"))
        assertTrue(config.getBoolean("DisableLocalHTTPProxy"))
        assertTrue(config.getBoolean("EmitBytesTransferred"))
        assertEquals(0, config.getInt("EstablishTunnelTimeoutSeconds"))
    }

    @Test fun incompleteBootstrapFailsBeforeInvokingNativeCore() {
        for (key in listOf("ClientVersion", "SponsorId", "PropagationChannelId",
            "RemoteServerListURLs", "RemoteServerListSignaturePublicKey")) {
            val incomplete = bootstrap().apply { remove(key) }
            assertThrows(IllegalArgumentException::class.java) { PsiphonConfig.build(incomplete, "") }
        }
        assertThrows(IllegalArgumentException::class.java) {
            PsiphonConfig.build(bootstrap().put("ClientVersion", "not-a-number"), "")
        }
    }
}
