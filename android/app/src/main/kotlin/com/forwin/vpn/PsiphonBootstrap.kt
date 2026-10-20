package com.forwin.vpn

import org.json.JSONObject
import java.io.InputStream
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.zip.InflaterInputStream
import kotlin.io.encoding.Base64

/** Offline seed for both Psiphon paths. Remote discovery remains owned by the SDK.
 *
 * Keep the original signed envelope, not a hand-maintained collection of peers.
 * Verification matches tunnel-core's common.ReadAuthenticatedDataPackage:
 * SHA256(base64 public-key string), then RSA PKCS#1 v1.5/SHA256 over UTF-8 data.
 * No server address or authentication material is logged by this reader.
 */
internal object PsiphonBootstrap {
    const val SERVER_LIST_ASSET = "psiphon_server_list.bin"
    private const val MAX_ENVELOPE_BYTES = 8 * 1024 * 1024

    data class ServerEntries(val encoded: String, val count: Int)

    fun readServerEntries(source: InputStream, publicKey: String): ServerEntries {
        val bytes = InflaterInputStream(source).use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                require(output.size() + read <= MAX_ENVELOPE_BYTES) { "Psiphon seed exceeds size limit" }
                output.write(buffer, 0, read)
            }
            output.toByteArray()
        }
        val envelope = JSONObject(String(bytes, Charsets.UTF_8))
        val digest = MessageDigest.getInstance("SHA-256").digest(publicKey.toByteArray(Charsets.UTF_8))
        require(MessageDigest.isEqual(digest, Base64.decode(envelope.getString("signingPublicKeyDigest")))) {
            "Psiphon seed signing key mismatch"
        }
        val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.decode(publicKey)))
        val data = envelope.getString("data")
        val verifier = Signature.getInstance("SHA256withRSA")
        verifier.initVerify(key)
        verifier.update(data.toByteArray(Charsets.UTF_8))
        require(verifier.verify(Base64.decode(envelope.getString("signature")))) { "Psiphon seed signature invalid" }
        val entries = data.lineSequence().filter { it.isNotBlank() }.toList()
        require(entries.isNotEmpty()) { "Psiphon seed contains no servers" }
        require(entries.all { line -> line.length % 2 == 0 && line.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' } }) {
            "Psiphon seed contains malformed entries"
        }
        return ServerEntries(entries.joinToString("\n", postfix = "\n"), entries.size)
    }
}
