package com.forwin.vpn

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

class PsiphonRefreshLockTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun idleRequestRunsAndReleasesLockForNextStart() {
        val directory = temporary.newFolder()
        var calls = 0
        assertTrue(PsiphonRefreshLock.runIfIdle(directory) { calls++ })
        assertTrue(PsiphonRefreshLock.runIfIdle(directory) { calls++ })
        assertEquals(2, calls)
    }

    @Test fun overlapReturnsWithoutWaitingOrExecutingDuplicateDownload() {
        val directory = temporary.newFolder()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        val owner = Thread {
            try {
                PsiphonRefreshLock.runIfIdle(directory) {
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                }
            } catch (error: Throwable) { failure.set(error) }
        }
        owner.start()
        try {
            assertTrue(entered.await(2, TimeUnit.SECONDS))
            // Owner is still blocked inside a simulated network request.
            assertFalse(PsiphonRefreshLock.runIfIdle(directory) { fail("Duplicate refresh executed") })
            assertEquals(1L, release.count)
        } finally {
            release.countDown()
            owner.join(5000)
        }
        assertFalse(owner.isAlive)
        assertNull(failure.get())
    }

    @Test fun downloadFailureReleasesLockAndKeepsExistingCacheBytes() {
        val directory = temporary.newFolder()
        val cache = File(directory, PsiphonServerListStore.CACHE_NAME).apply { writeText("previous-cache") }
        assertThrows(IllegalStateException::class.java) {
            PsiphonRefreshLock.runIfIdle(directory) { throw IllegalStateException("offline") }
        }
        assertEquals("previous-cache", cache.readText())
        assertTrue(PsiphonRefreshLock.runIfIdle(directory) {})
    }

    @Test fun separateJvmProcessCannotStartAParallelRefreshAndExitReleasesLock() {
        val directory = temporary.newFolder()
        val java = File(System.getProperty("java.home"), "bin/java").absolutePath
        val process = ProcessBuilder(java, "-cp", System.getProperty("java.class.path"),
            Holder::class.java.name, directory.absolutePath).redirectErrorStream(true).start()
        try {
            val ready = directory.resolve("holder-ready")
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (!ready.exists() && process.isAlive && System.nanoTime() < deadline) Thread.sleep(10)
            assertTrue("Separate process failed to acquire lock", ready.exists())
            assertFalse(PsiphonRefreshLock.runIfIdle(directory) { fail("Parallel process refresh executed") })
            // Simulate Android killing the refresh process: the OS must release its file lock.
            process.destroyForcibly()
            assertTrue(process.waitFor(5, TimeUnit.SECONDS))
            assertTrue(PsiphonRefreshLock.runIfIdle(directory) {})
        } finally {
            process.destroyForcibly()
            process.waitFor(5, TimeUnit.SECONDS)
        }
    }

    object Holder {
        @JvmStatic fun main(args: Array<String>) {
            val directory = File(args.single())
            check(PsiphonRefreshLock.runIfIdle(directory) {
                directory.resolve("holder-ready").writeText("ready")
                System.`in`.read()
            })
        }
    }
}
