package com.forwin.vpn

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/** Separate from SDK datastores: one signed snapshot shared by all app processes. */
internal class PsiphonServerListStore(
    private val directory: File,
    private val publicKey: String,
    private val bundled: () -> InputStream,
) {
    data class Snapshot(val entries: List<PsiphonServerCatalog.Entry>, val source: String, val updatedAt: Long?)

    companion object {
        const val CACHE_NAME = "server-list.bin"
        private const val MAX_DOWNLOAD_BYTES = 8 * 1024 * 1024

        /** Normal app routing only: no protected socket, network binding or TLS bypass. */
        fun download(address: String): ByteArray {
            val url = URL(address)
            require(url.protocol == "https") { "Psiphon discovery requires HTTPS" }
            val connection = url.openConnection() as HttpsURLConnection
            connection.connectTimeout = 5_000
            connection.readTimeout = 10_000
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            val deadline = System.nanoTime() + 25_000_000_000L
            try {
                check(connection.responseCode == 200) { "Psiphon discovery HTTP error" }
                require(connection.contentLengthLong <= MAX_DOWNLOAD_BYTES) { "Psiphon list exceeds size limit" }
                return connection.inputStream.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        check(System.nanoTime() < deadline) { "Psiphon discovery deadline exceeded" }
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= MAX_DOWNLOAD_BYTES) { "Psiphon list exceeds size limit" }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            } finally {
                connection.disconnect()
            }
        }
    }

    /** Never performs network I/O or waits for a refresh. Reverify even cached input. */
    fun readLatest(): PsiphonBootstrap.ServerEntries {
        try {
            return PsiphonBootstrap.readServerEntries(File(directory, CACHE_NAME).inputStream(), publicKey)
        } catch (_: Exception) {
            return PsiphonBootstrap.readServerEntries(bundled(), publicKey)
        }
    }

    /** Reads and verifies one complete snapshot, exposing only safe metadata. */
    fun readCatalog(): Snapshot {
        val cache = File(directory, CACHE_NAME)
        return try {
            val verified = PsiphonBootstrap.readServerEntries(cache.inputStream(), publicKey)
            val entries = PsiphonServerCatalog.parse(verified.encoded)
            require(entries.isNotEmpty()) { "verified cache contains no usable server entries" }
            Snapshot(entries, "cache", cache.lastModified().takeIf { it > 0L })
        } catch (_: Exception) {
            val verified = PsiphonBootstrap.readServerEntries(bundled(), publicKey)
            val entries = PsiphonServerCatalog.parse(verified.encoded)
            require(entries.isNotEmpty()) { "bundled snapshot contains no usable server entries" }
            Snapshot(entries, "bundled", null)
        }
    }

    /** Resolves only against the latest verified snapshot, never stale SDK data. */
    fun resolve(id: String): PsiphonServerCatalog.Entry? = readCatalog().entries.firstOrNull { it.id == id }

    /** Verify first, fsync a private temp file, then atomically publish for other processes. */
    fun refresh(urls: List<String>, fetch: (String) -> ByteArray = ::download): Boolean {
        for (url in urls) {
            var temporary: File? = null
            try {
                val bytes = fetch(url)
                require(bytes.size <= MAX_DOWNLOAD_BYTES) { "Psiphon list exceeds size limit" }
                // Signature verification is the cache publication gate. The
                // catalog projection separately filters unusable entries; keep
                // this layer compatible with tunnel-core's future/legacy lines.
                PsiphonBootstrap.readServerEntries(ByteArrayInputStream(bytes), publicKey)
                check(directory.mkdirs() || directory.isDirectory) { "Cannot prepare Psiphon list cache" }
                temporary = File.createTempFile("server-list-", ".tmp", directory)
                temporary.outputStream().use { out -> out.write(bytes); out.fd.sync() }
                // Same-filesystem rename is atomic on Android/Linux; readers see old or new, never partial.
                check(temporary.renameTo(File(directory, CACHE_NAME))) { "Cannot publish Psiphon list cache" }
                return true
            } catch (_: Exception) {
                // An unavailable/invalid source must never delete the last valid cache.
            } finally {
                temporary?.delete()
            }
        }
        return false
    }
}
