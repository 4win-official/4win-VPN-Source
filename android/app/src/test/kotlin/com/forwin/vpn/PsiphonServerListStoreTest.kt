package com.forwin.vpn

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.DeflaterOutputStream

class PsiphonServerListStoreTest {
    companion object {
        private val signingKey by lazy { KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair() }
        private val publicKey get() = Base64.getEncoder().encodeToString(signingKey.public.encoded)
    }

    private fun tempDir(): File = Files.createTempDirectory("psiphon-store-test").toFile()

    private fun envelope(data: String): ByteArray {
        val keyText = publicKey
        val signer = Signature.getInstance("SHA256withRSA").apply {
            initSign(signingKey.private)
            update(data.toByteArray(Charsets.UTF_8))
        }
        val json = JSONObject().put("data", data)
            .put("signature", Base64.getEncoder().encodeToString(signer.sign()))
            .put("signingPublicKeyDigest", Base64.getEncoder().encodeToString(
                MessageDigest.getInstance("SHA-256").digest(keyText.toByteArray(Charsets.UTF_8))))
        return ByteArrayOutputStream().also { out ->
            DeflaterOutputStream(out).use { it.write(json.toString().toByteArray(Charsets.UTF_8)) }
        }.toByteArray()
    }

    private fun store(dir: File, bundled: ByteArray = envelope("aa11\n")) =
        PsiphonServerListStore(dir, publicKey) { ByteArrayInputStream(bundled) }

    private fun encodedServer(ip: String = "192.0.2.1", port: Int = 443): String =
        """{"ipAddress":"$ip","sshPort":$port,"region":"NL"}""".toByteArray()
            .joinToString("") { "%02x".format(it) }

    @Test fun selectedServerResolvesLatestVerifiedRevisionAndNeverRemovedServer() {
        val dir = tempDir()
        val old = encodedServer()
        val bundled = envelope(old)
        val reader = store(dir, bundled)
        val initial = reader.readCatalog().entries.single()
        assertEquals(old, reader.resolve(initial.legacyId)?.encoded)
        val fresh = encodedServer(port = 8443)
        assertTrue(reader.refresh(listOf("fresh")) { envelope(fresh) })
        assertEquals(fresh, reader.resolve(initial.id)?.encoded)
        assertNull(reader.resolve(initial.legacyId))
        assertTrue(reader.refresh(listOf("removed")) { envelope(encodedServer("192.0.2.2")) })
        // Do not fall back to a bundled/stale selected server after removal.
        assertNull(reader.resolve(initial.id))
        assertNull(reader.resolve(initial.legacyId))
    }

    @Test fun startupSnapshotKeepsSelectionAndEmbeddedBytesTogetherDuringRefresh() {
        val dir = tempDir()
        val old = encodedServer()
        val reader = store(dir, envelope(old))
        val startup = reader.readCatalog()
        val selection = startup.entries.single().id
        val fresh = encodedServer(port = 8443)
        assertTrue(reader.refresh(listOf("fresh")) { envelope(fresh) })
        assertEquals("$old\n", startup.encoded)
        assertEquals(old, startup.resolve(selection)?.encoded)
        assertEquals("$fresh\n", reader.readCatalog().encoded)
        assertEquals(fresh, reader.resolve(selection)?.encoded)
    }

    @Test fun invalidOrUnusableCacheFallsBackToOneVerifiedBundledSnapshot() {
        val dir = tempDir()
        val bundledEntry = encodedServer()
        val reader = store(dir, envelope(bundledEntry))
        val id = reader.readCatalog().entries.single().id
        // Even a valid signature does not make a malformed catalog usable.
        assertTrue(reader.refresh(listOf("unusable")) { envelope("aa11") })
        val fallback = reader.readCatalog()
        assertEquals("bundled", fallback.source)
        assertEquals("$bundledEntry\n", fallback.encoded)
        assertEquals(bundledEntry, fallback.resolve(id)?.encoded)
        File(dir, PsiphonServerListStore.CACHE_NAME).writeBytes(byteArrayOf(1, 2, 3))
        assertEquals(bundledEntry, reader.readCatalog().resolve(id)?.encoded)
        val invalidBundle = PsiphonServerListStore(dir, publicKey) { ByteArrayInputStream(byteArrayOf(1, 2, 3)) }
        assertThrows(Exception::class.java) { invalidBundle.readCatalog() }
    }

    @Test fun absentAndCorruptCacheUseVerifiedBundledFallback() {
        val dir = tempDir()
        val bundled = envelope("aa11\nbb22\n")
        assertEquals(2, store(dir, bundled).readLatest().count)
        File(dir, PsiphonServerListStore.CACHE_NAME).writeBytes(byteArrayOf(1, 2, 3))
        assertEquals("aa11\nbb22\n", store(dir, bundled).readLatest().encoded)
    }

    @Test fun verifiedRefreshIsAtomicAndPersistsAcrossFreshStoreInstances() {
        val dir = tempDir()
        val replacement = envelope("cc33\ndd44\n")
        assertTrue(store(dir).refresh(listOf("https://one")) { replacement })
        assertEquals("cc33\ndd44\n", store(dir).readLatest().encoded)
        assertEquals("cc33\ndd44\n", store(dir).readLatest().encoded)
        assertArrayEquals(replacement, File(dir, PsiphonServerListStore.CACHE_NAME).readBytes())
    }

    @Test fun failedSourcesAndInvalidRefreshesRetainExactOldCacheAndTryFallbackEndpoint() {
        val dir = tempDir()
        val old = envelope("aa11\n")
        assertTrue(store(dir).refresh(listOf("https://initial")) { old })
        val cache = File(dir, PsiphonServerListStore.CACHE_NAME)
        val oldBytes = cache.readBytes()
        val invalidSignature = JSONObject(String(java.util.zip.InflaterInputStream(ByteArrayInputStream(envelope("bb22\n"))).readBytes()))
            .put("signature", Base64.getEncoder().encodeToString(ByteArray(256)))
        val invalid = ByteArrayOutputStream().also { out -> DeflaterOutputStream(out).use { it.write(invalidSignature.toString().toByteArray()) } }.toByteArray()
        val oversized = ByteArray(8 * 1024 * 1024 + 1)
        val invalidSources = listOf<ByteArray>(ByteArray(0), byteArrayOf(1, 2, 3), invalid, oversized, envelope("ee55\n").copyOf(10))
        invalidSources.forEach { source ->
            assertFalse(store(dir).refresh(listOf("bad-source")) { source })
            assertArrayEquals(oldBytes, cache.readBytes())
        }
        val calls = mutableListOf<String>()
        assertTrue(store(dir).refresh(listOf("offline", "timeout", "good")) { url ->
            calls += url
            if (url == "good") envelope("ff66\n") else throw java.io.IOException(url)
        })
        assertEquals(listOf("offline", "timeout", "good"), calls)
        assertEquals("ff66\n", store(dir).readLatest().encoded)
        assertNotEquals(oldBytes.toList(), cache.readBytes().toList())

        val beforeFailure = cache.readBytes()
        assertFalse(store(dir).refresh(listOf("failed")) { throw java.io.IOException("timeout") })
        assertArrayEquals(beforeFailure, cache.readBytes())
    }

    @Test fun unusableCacheDirectoryCannotClobberExistingSignedSnapshot() {
        val dir = tempDir()
        val old = envelope("aa11\n")
        assertTrue(store(dir).refresh(listOf("initial")) { old })
        val cache = File(dir, PsiphonServerListStore.CACHE_NAME)
        // A regular file cannot serve as the refresh directory, even when run as root.
        assertFalse(store(cache).refresh(listOf("fresh")) { envelope("bb22\n") })
        assertArrayEquals(old, cache.readBytes())
        assertEquals("aa11\n", store(dir).readLatest().encoded)
    }

    @Test fun concurrentReadersObserveOnlyCompleteOldOrNewSnapshots() {
        val dir = tempDir()
        val old = envelope("aa11\n")
        val fresh = envelope("bb22\n")
        assertTrue(store(dir).refresh(listOf("old")) { old })
        val failure = AtomicReference<Throwable?>()
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val writer = Thread {
            try {
                started.countDown()
                assertTrue(release.await(5, TimeUnit.SECONDS))
                repeat(30) { index ->
                    assertTrue(store(dir).refresh(listOf("new")) { if (index % 2 == 0) old else fresh })
                }
            } catch (t: Throwable) { failure.set(t) }
        }
        writer.start()
        assertTrue(started.await(5, TimeUnit.SECONDS))
        release.countDown()
        repeat(200) {
            val value = store(dir).readLatest().encoded
            assertTrue(value == "aa11\n" || value == "bb22\n")
        }
        writer.join(5000)
        assertFalse(writer.isAlive)
        assertNull(failure.get())
        assertEquals("bb22\n", store(dir).readLatest().encoded)
    }
}
