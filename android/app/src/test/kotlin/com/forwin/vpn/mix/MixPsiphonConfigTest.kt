package com.forwin.vpn.mix

import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MixPsiphonConfigTest {
    @Test fun packagedBootstrapHasCoreRequirementsAndSignedHttpsListWithoutChangingStandalone() {
        val asset = generateSequence(File("").absoluteFile) { it.parentFile }
            .map { File(it, "android/app/src/main/assets/mix_psiphon_bootstrap.json") }
            .first { it.isFile }
        val bootstrap = JSONObject(asset.readText())
        val before = bootstrap.toString()
        assertTrue(bootstrap.getString("ClientVersion").toInt() > 0)
        for (key in listOf("SponsorId", "PropagationChannelId")) {
            assertTrue(bootstrap.getString(key).matches(Regex("[A-Fa-f0-9]{16}")))
        }
        val key = java.util.Base64.getDecoder().decode(bootstrap.getString("RemoteServerListSignaturePublicKey"))
        val publicKey = java.security.KeyFactory.getInstance("RSA")
            .generatePublic(java.security.spec.X509EncodedKeySpec(key))
        assertEquals("RSA", publicKey.algorithm)
        val urls = bootstrap.getJSONArray("RemoteServerListURLs")
        assertTrue(urls.length() > 0)
        for (i in 0 until urls.length()) {
            val url = urls.getJSONObject(i)
            assertFalse(url.optBoolean("SkipVerify", false))
            val decoded = String(java.util.Base64.getDecoder().decode(url.getString("URL")))
            assertEquals("https", java.net.URI(decoded).scheme)
        }
        val caller = JSONObject().put("EgressRegion", "DE")
        val callerBefore = caller.toString()
        val result = MixPsiphonConfig.build(caller, File("/mix/stage-0"), 20000, null, bootstrap)
        assertEquals("DE", result.getString("EgressRegion"))
        assertEquals(bootstrap.getString("SponsorId"), result.getString("SponsorId"))
        assertEquals(bootstrap.getString("RemoteServerListSignaturePublicKey"), result.getString("RemoteServerListSignaturePublicKey"))
        assertEquals(before, bootstrap.toString())
        assertEquals(callerBefore, caller.toString())
    }

    @Test fun repeatedPsiphonHopsNeverShareDatastoresOrStandaloneState() {
        val files = File("/app/files")
        val first = MixPsiphonConfig.root(files, "0")
        val second = MixPsiphonConfig.root(files, "1")
        assertNotEquals(first, second)
        assertEquals(first, MixPsiphonConfig.root(files, "0"))
        val caller = JSONObject().put("DataRootDirectory", "/app/files/standalone")
            .put("DataStoreDirectory", "/app/files/standalone.db")
            .put("MigrateDataStoreDirectory", "/app/files")
            .put("MigrateRemoteServerListDownloadFilename", "/app/files/remote_server_list")
            .put("MigrateObfuscatedServerListDownloadDirectory", "/app/files/osl")
            .put("RemoteServerListDownloadFilename", "/app/files/remote_server_list")
            .put("SponsorId", "keep-bootstrap")
            .put("UpstreamProxyURL", "socks5://untrusted:1080")
        val before = caller.toString()
        val config = MixPsiphonConfig.build(caller, first, 20001, "socks5://127.0.0.1:19999")
        assertEquals(File(first, "tunnel-core").absolutePath, config.getString("DataRootDirectory"))
        for (key in listOf("DataStoreDirectory", "RemoteServerListDownloadFilename",
            "MigrateDataStoreDirectory", "MigrateRemoteServerListDownloadFilename",
            "MigrateObfuscatedServerListDownloadDirectory")) assertFalse(config.has(key))
        assertEquals("keep-bootstrap", config.getString("SponsorId"))
        assertEquals("socks5://127.0.0.1:19999", config.getString("UpstreamProxyURL"))
        assertEquals(20001, config.getInt("LocalSocksProxyPort"))
        assertEquals(before, caller.toString())
        assertFalse(MixPsiphonConfig.build(caller, second, 20002, null).has("UpstreamProxyURL"))
    }

    @Test fun stageIdCannotEscapePrivateRootAndMustFitBlockLimit() {
        for (id in listOf("-1", "50", "../standalone", "", "abc", "01", "+1", " 1 ")) {
            assertThrows(IllegalArgumentException::class.java) {
                MixPsiphonConfig.root(File("/app/files"), id)
            }
        }
        assertTrue(MixPsiphonConfig.root(File("/app/files"), "49").path.endsWith("stage-49"))
    }
}
