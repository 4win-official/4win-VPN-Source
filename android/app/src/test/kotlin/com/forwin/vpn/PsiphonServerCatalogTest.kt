package com.forwin.vpn

import org.junit.Assert.*
import org.junit.Test
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.io.File
import org.json.JSONObject

class PsiphonServerCatalogTest {
    private fun hex(value: String) = value.toByteArray(StandardCharsets.UTF_8).joinToString("") { "%02x".format(it) }

    @Test fun decodesOfficialHexJsonAndExposesOnlySafeProjection() {
        val encoded = hex("{\"ipAddress\":\"192.0.2.1\",\"sshPort\":443,\"region\":\"CA\",\"sshPassword\":\"secret\"}")
        val entry = PsiphonServerCatalog.parse(encoded).single()
        assertEquals("192.0.2.1", entry.ipAddress)
        assertEquals("CA", entry.region)
        assertEquals(443, entry.port)
        assertEquals(MessageDigest.getInstance("SHA-256").digest(encoded.toByteArray()).joinToString("") { "%02x".format(it) }, entry.id)
    }

    @Test fun skipsMalformedNoIpAndNoPortEntriesAndCapsCatalog() {
        val malformed = listOf("abc", hex("not-json"), hex("{\"sshPort\":443}"))
        assertTrue(PsiphonServerCatalog.parse(malformed.joinToString("\n")).isEmpty())
        assertNull(PsiphonServerCatalog.parse(hex("{\"ipAddress\":\"192.0.2.1\"}" )).single().port)
        val many = (0 until PsiphonServerCatalog.MAX_ENTRIES + 20).joinToString("\n") {
            hex("{\"ipAddress\":\"192.0.2.${(it % 240) + 1}\",\"sshPort\":443}")
        }
        assertTrue(PsiphonServerCatalog.parse(many).size <= PsiphonServerCatalog.MAX_ENTRIES)
    }

    @Test fun decodesPackagedSignedLegacySnapshot() {
        val root = generateSequence(File("").absoluteFile) { it.parentFile }
            .map { File(it, "android/app/src/main/assets") }.first { it.isDirectory }
        val bootstrap = JSONObject(File(root, "mix_psiphon_bootstrap.json").readText())
        val entries = PsiphonBootstrap.readServerEntries(
            File(root, PsiphonBootstrap.SERVER_LIST_ASSET).inputStream(),
            bootstrap.getString("RemoteServerListSignaturePublicKey")
        )
        assertTrue(PsiphonServerCatalog.parse(entries.encoded).isNotEmpty())
    }
}
