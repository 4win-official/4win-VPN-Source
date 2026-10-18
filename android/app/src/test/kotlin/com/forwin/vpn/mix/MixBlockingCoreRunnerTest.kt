package com.forwin.vpn.mix

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class MixBlockingCoreRunnerTest {
    @Test(timeout = 4000) fun blockingNativeStartDoesNotBlockReadinessOrStop() {
        val entered = CountDownLatch(1)
        val exit = CountDownLatch(1)
        val cleanups = AtomicInteger()
        val runner = MixBlockingCoreRunner(
            { entered.countDown(); exit.await(); 0 },
            { exit.countDown() }, { cleanups.incrementAndGet(); Unit })
        runner.start()
        assertTrue(entered.await(1, TimeUnit.SECONDS))
        assertFalse(runner.result.isDone)
        assertEquals(0, cleanups.get())
        assertTrue(runner.stop())
        assertEquals(0, runner.result.get().toInt())
        assertEquals(1, cleanups.get())
    }

    @Test(timeout = 4000) fun stopIsRetriedWhenNativeStartInitiallyDiscardsCancellation() {
        val entering = CountDownLatch(1)
        val active = AtomicBoolean()
        val exit = CountDownLatch(1)
        val stopCalls = AtomicInteger()
        val runner = MixBlockingCoreRunner(
            { entering.countDown(); Thread.sleep(120); active.set(true); exit.await(); 0 },
            { stopCalls.incrementAndGet(); if (active.get()) exit.countDown() }, {})
        runner.start()
        assertTrue(entering.await(1, TimeUnit.SECONDS))
        assertTrue(runner.stop())
        assertTrue(stopCalls.get() > 1)
        assertEquals(0, runner.result.get().toInt())
    }

    @Test(timeout = 4000) fun stopTimeoutDoesNotReleaseIdentityWhileCoreStillUsesIt() {
        val entered = CountDownLatch(1)
        val exit = CountDownLatch(1)
        val cleaned = AtomicBoolean()
        val runner = MixBlockingCoreRunner(
            { entered.countDown(); exit.await(); 0 }, {}, { cleaned.set(true) })
        runner.start()
        assertTrue(entered.await(1, TimeUnit.SECONDS))
        assertFalse(runner.stop(50))
        assertFalse(cleaned.get())
        assertFalse(runner.result.isDone)
        exit.countDown()
        assertEquals(0, runner.result.get(1, TimeUnit.SECONDS).toInt())
        assertTrue(cleaned.get())
    }

    @Test(timeout = 4000) fun nativeFailureStillReleasesExactlyOnceAndIsReported() {
        val cleaned = AtomicInteger()
        val runner = MixBlockingCoreRunner({ error("native failed") }, {}, { cleaned.incrementAndGet(); Unit })
        runner.start()
        try { runner.result.get(1, TimeUnit.SECONDS); fail("Expected native exception") }
        catch (expected: java.util.concurrent.ExecutionException) { assertEquals("native failed", expected.cause!!.message) }
        assertTrue(runner.stop())
        assertEquals(1, cleaned.get())
    }
}
