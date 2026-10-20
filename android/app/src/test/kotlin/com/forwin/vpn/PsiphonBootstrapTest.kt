package com.forwin.vpn

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.util.Base64
import java.util.zip.DeflaterOutputStream

class PsiphonBootstrapTest {
    companion object {
        private val signingKey by lazy { KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair() }
        private val publicKey: String get() = Base64.getEncoder().encodeToString(signingKey.public.encoded)
    }

    private fun asset(name: String): File = generateSequence(File("").absoluteFile) { it.parentFile }
        .map { File(it, "android/app/src/main/assets/$name") }.first { it.isFile }

    private fun compress(envelope: JSONObject): ByteArray = ByteArrayOutputStream().also { out ->
        DeflaterOutputStream(out).use { it.write(envelope.toString().toByteArray(Charsets.UTF_8)) }
    }.toByteArray()

    private fun signed(data: String): JSONObject {
        val signer = Signature.getInstance("SHA256withRSA")
        signer.initSign(signingKey.private)
        signer.update(data.toByteArray(Charsets.UTF_8))
        return JSONObject().put("data", data)
            .put("signature", Base64.getEncoder().encodeToString(signer.sign()))
            .put("signingPublicKeyDigest", Base64.getEncoder().encodeToString(
                MessageDigest.getInstance("SHA-256").digest(publicKey.toByteArray(Charsets.UTF_8))))
    }

    private fun read(envelope: JSONObject) = PsiphonBootstrap.readServerEntries(
        ByteArrayInputStream(compress(envelope)), publicKey)

    @Test fun packagedSeedIsSignedByConfiguredDiscoveryKeyAndContainsServerEntries() {
        val config = JSONObject(asset("mix_psiphon_bootstrap.json").readText())
        val entries = PsiphonBootstrap.readServerEntries(asset(PsiphonBootstrap.SERVER_LIST_ASSET).inputStream(),
            config.getString("RemoteServerListSignaturePublicKey"))
        assertTrue(entries.count > 0)
        assertEquals(entries.count, entries.encoded.lineSequence().count { it.isNotBlank() })
        // Decode the SDK's entry format locally without disclosing any endpoints.
        for (line in entries.encoded.lineSequence().filter { it.isNotBlank() }) {
            val decoded = String(line.chunked(2).map { it.toInt(16).toByte() }.toByteArray(), Charsets.UTF_8)
            val record = JSONObject(decoded.substring(decoded.indexOf('{')))
            assertTrue(record.getString("ipAddress").isNotBlank())
        }
    }

    @Test fun standaloneAndMixBothPassVerifiedSeedToTheirOwnSdkInstance() {
        val kotlin = asset("mix_psiphon_bootstrap.json").parentFile.parentFile.resolve("kotlin/com/forwin/vpn")
        for (path in listOf("PsiphonVpnService.kt", "mix/PsiphonMixAdapter.kt")) {
            val source = kotlin.resolve(path).readText()
            assertTrue(source.contains("PsiphonServerList.readLatest"))
            assertTrue(source.contains("startTunneling(embeddedServers)"))
            assertFalse(source.contains("startTunneling(\"\")"))
        }
    }

    @Test fun signedEntriesAreReturnedAsNewlineDelimitedSdkInput() {
        val result = read(signed("ab12\nCD34\n"))
        assertEquals(2, result.count)
        assertEquals("ab12\nCD34\n", result.encoded)
    }

    @Test fun modifiedPayloadIsRejectedEvenWhenStillValidHex() {
        val envelope = signed("ab12\n").put("data", "ab13\n")
        assertThrows(IllegalArgumentException::class.java) { read(envelope) }
    }

    @Test fun wrongKeyDigestAndMissingSignatureAreRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            read(signed("ab12\n").put("signingPublicKeyDigest", Base64.getEncoder().encodeToString(ByteArray(32))))
        }
        assertThrows(Exception::class.java) { read(signed("ab12\n").apply { remove("signature") }) }
    }

    @Test fun correctDigestCannotMakeUntrustedSignatureValid() {
        val envelope = signed("ab12\n")
        val unrelated = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val forged = Signature.getInstance("SHA256withRSA").apply {
            initSign(unrelated.private); update("ab12\n".toByteArray())
        }.sign()
        assertThrows(IllegalArgumentException::class.java) {
            read(envelope.put("signature", Base64.getEncoder().encodeToString(forged)))
        }
    }

    @Test fun emptyAndMalformedEntriesAreRejectedAfterSignatureVerification() {
        for (data in listOf("", "\n", "abc\n", "not-hex\n")) {
            assertThrows(IllegalArgumentException::class.java) { read(signed(data)) }
        }
    }

    @Test fun corruptAndOversizedCompressedEnvelopesAreRejected() {
        assertThrows(Exception::class.java) {
            PsiphonBootstrap.readServerEntries(ByteArrayInputStream(byteArrayOf(1, 2, 3)), publicKey)
        }
        val compressed = ByteArrayOutputStream().also { out ->
            DeflaterOutputStream(out).use { it.write(ByteArray(8 * 1024 * 1024 + 1)) }
        }.toByteArray()
        assertThrows(IllegalArgumentException::class.java) {
            PsiphonBootstrap.readServerEntries(ByteArrayInputStream(compressed), publicKey)
        }
    }
}
