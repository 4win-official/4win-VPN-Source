package com.forwin.vpn

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class PsiphonRefreshQueueTest {
    private class ControlledExecutor : Executor {
        val submitted = CountDownLatch(1)
        val run = CountDownLatch(1)
        @Volatile var task: Runnable? = null
        override fun execute(command: Runnable) { task = command; submitted.countDown() }
        fun runTask() { task!!.run(); run.countDown() }
    }

    @Test fun requestReturnsBeforeNetworkWorkRuns() {
        val executor = ControlledExecutor()
        val queue = PsiphonRefreshQueue(executor)
        val started = AtomicInteger()
        queue.request { started.incrementAndGet() }
        assertTrue(executor.submitted.await(1, TimeUnit.SECONDS))
        assertEquals(0, started.get())
        executor.runTask()
        assertEquals(1, started.get())
    }

    @Test fun requestsWhileRunningCoalesceToOneLatestFollowUp() {
        val executor = ControlledExecutor()
        val queue = PsiphonRefreshQueue(executor)
        val firstStarted = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = mutableListOf<String>()
        queue.request {
            synchronized(calls) { calls += "first" }
            firstStarted.countDown()
            release.await(2, TimeUnit.SECONDS)
        }
        val worker = Thread { executor.runTask() }
        worker.start()
        assertTrue(firstStarted.await(1, TimeUnit.SECONDS))
        queue.request { synchronized(calls) { calls += "stale" } }
        queue.request { synchronized(calls) { calls += "latest" } }
        release.countDown()
        worker.join(3000)
        assertEquals(listOf("first", "latest"), calls)
    }

    @Test fun thrownRefreshDoesNotPoisonQueueAndNextRequestRuns() {
        val executor = ControlledExecutor()
        val queue = PsiphonRefreshQueue(executor)
        val calls = AtomicInteger()
        queue.request { calls.incrementAndGet(); throw IllegalStateException("network") }
        executor.runTask()
        queue.request { calls.incrementAndGet() }
        executor.runTask()
        assertEquals(2, calls.get())
    }

    @Test fun rejectedSubmissionResetsStateSoLaterSubmissionCanRecover() {
        val submissions = AtomicInteger()
        val tasks = java.util.ArrayDeque<Runnable>()
        val executor = Executor { command ->
            if (submissions.getAndIncrement() == 0) throw java.util.concurrent.RejectedExecutionException("busy")
            tasks.addLast(command)
        }
        val queue = PsiphonRefreshQueue(executor)
        val calls = AtomicInteger()
        queue.request { calls.incrementAndGet() }
        queue.request { calls.incrementAndGet() }
        assertEquals(0, calls.get())
        tasks.removeFirst().run()
        assertEquals(1, calls.get())
    }
}
