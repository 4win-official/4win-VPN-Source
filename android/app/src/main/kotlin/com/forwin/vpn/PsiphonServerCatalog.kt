package com.forwin.vpn

import org.json.JSONObject
import java.net.InetAddress
import java.security.MessageDigest

/**
 * Safe projection of tunnel-core's encoded ServerEntry. The encoded entry is
 * retained only in the private [Entry] used when constructing TargetServerEntry;
 * callers receive no secrets or encoded material.
 */
internal object PsiphonServerCatalog {
    const val MAX_ENTRIES = 512
    const val MAX_LINE_CHARS = 256 * 1024

    data class Entry(
        val id: String,
        val ipAddress: String,
        val region: String,
        val port: Int?,
        internal val encoded: String,
    ) {
        // Older versions persisted a hash of the entire signed record. Accept
        // it only if that exact record is still in the current verified list.
        val legacyId: String get() = sha256(encoded.toByteArray(Charsets.UTF_8))
        fun matchesId(requestedId: String): Boolean = id == requestedId || legacyId == requestedId
    }

    fun parse(encodedList: String): List<Entry> {
        val result = ArrayList<Entry>()
        for (line in encodedList.lineSequence()) {
            if (result.size >= MAX_ENTRIES) break
            val encoded = line.trim()
            if (encoded.isEmpty()) continue
            if (encoded.length > MAX_LINE_CHARS || encoded.length % 2 != 0) continue
            val raw = try { hexDecode(encoded) } catch (_: Exception) { continue }
            val decoded = raw.toString(Charsets.UTF_8)
            // tunnel-core's official encoded form is four legacy header
            // fields followed by the JSON record. Newer records may be JSON
            // directly; in both cases the JSON object is authoritative.
            val jsonText = decoded.substring(decoded.indexOf('{').takeIf { it >= 0 } ?: continue)
            val json = try { JSONObject(jsonText) } catch (_: Exception) { continue }
            val ip = json.optString("ipAddress", "").trim()
            if (!validIp(ip)) continue
            val port = candidatePort(json)
            // A selection identifies a server, not a revision of its credentials,
            // ports or JSON serialization. Always take connection material from
            // the newly verified record, never from the persisted identifier.
            val canonicalIp = InetAddress.getByName(ip).hostAddress ?: continue
            val id = "ip-v1:" + sha256(canonicalIp.toByteArray(Charsets.UTF_8))
            result += Entry(id, ip, json.optString("region", "").trim(), port, encoded)
        }
        return result
    }

    private fun candidatePort(json: JSONObject): Int? {
        // These are actual TCP endpoints from the official ServerEntry schema.
        // Prefer SSH, then the web server, then other TCP tunnel transports.
        val keys = listOf("sshPort", "webServerPort", "tlsOSSHPort", "meekServerPort", "sshObfuscatedPort", "sshShadowsocksPort")
        for (key in keys) {
            val value = if (key == "webServerPort") json.optString(key, "").toIntOrNull() else json.optInt(key, 0)
            if (value in 1..65535) return value
        }
        return null
    }

    private fun validIp(value: String): Boolean = try {
        // Reject hostnames without performing DNS (catalog reads must not
        // block on network resolution); InetAddress then validates literals.
        value.isNotEmpty() && !value.contains('/') && !value.contains(' ') &&
            (value.matches(Regex("[0-9.]+")) || value.contains(':')) &&
            InetAddress.getByName(value).hostAddress != null
    } catch (_: Exception) { false }

    private fun hexDecode(value: String): ByteArray {
        val out = ByteArray(value.length / 2)
        for (i in out.indices) {
            val hi = Character.digit(value[i * 2], 16)
            val lo = Character.digit(value[i * 2 + 1], 16)
            require(hi >= 0 && lo >= 0)
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }
}
