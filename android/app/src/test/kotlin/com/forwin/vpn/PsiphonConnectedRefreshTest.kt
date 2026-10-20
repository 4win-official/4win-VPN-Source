package com.forwin.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PsiphonConnectedRefreshTest {
    private class FakeClock {
        data class Task(
            val delayMs: Long,
            val action: () -> Unit,
            var canceled: Boolean = false,
        )

        val tasks = mutableListOf<Task>()
        private var elapsedMs = 0L
        fun schedule(delayMs: Long, action: () -> Unit): PsiphonConnectedRefresh.Cancellation {
            val task = Task(delayMs, action)
            tasks += task
            return PsiphonConnectedRefresh.Cancellation { task.canceled = true }
        }

        fun fire(index: Int) {
            tasks[index].action()
        }

        fun advance(ms: Long) {
            elapsedMs += ms
            tasks.filter { !it.canceled && it.delayMs <= elapsedMs }.forEach { it.action() }
        }
    }

    private fun refresh(fake: FakeClock, refreshed: () -> Unit = {}): PsiphonConnectedRefresh =
        PsiphonConnectedRefresh(fake::schedule, refreshed)

    @Test
    fun startingOnlyCancelsAndResets_withoutSchedulingOrRefreshing() {
        val clock = FakeClock()
        var refreshes = 0
        val service = Any()
        val connected = refresh(clock) { refreshes++ }

        connected.starting(service)

        assertTrue(clock.tasks.isEmpty())
        assertEquals(0, refreshes)
    }

    @Test
    fun failedStartDoesNotScheduleOrRefresh() {
        val clock = FakeClock()
        var refreshes = 0
        val service = Any()
        val connected = refresh(clock) { refreshes++ }

        connected.starting(service)
        connected.stateChanged(service, false)

        assertTrue(clock.tasks.isEmpty())
        assertEquals(0, refreshes)
    }

    @Test
    fun refreshOccursAtExactlyThreeSeconds_notBefore() {
        val clock = FakeClock()
        var refreshes = 0
        val service = Any()
        val connected = refresh(clock) { refreshes++ }

        connected.starting(service)
        connected.stateChanged(service, true)

        assertEquals(1, clock.tasks.size)
        assertEquals(PsiphonConnectedRefresh.DELAY_MS, clock.tasks.single().delayMs)
        clock.advance(2_999)
        assertEquals(0, refreshes)
        clock.advance(1)
        assertEquals(1, refreshes)
    }

    @Test
    fun repeatedTrueDoesNotScheduleDuplicateRetries() {
        val clock = FakeClock()
        val service = Any()
        val connected = refresh(clock)

        connected.starting(service)
        connected.stateChanged(service, true)
        connected.stateChanged(service, true)
        connected.stateChanged(service, true)

        assertEquals(1, clock.tasks.size)
    }

    @Test
    fun disconnectAtTwoSecondsCancelsPendingRefresh() {
        val clock = FakeClock()
        var refreshes = 0
        val service = Any()
        val connected = refresh(clock) { refreshes++ }

        connected.starting(service)
        connected.stateChanged(service, true)
        connected.stateChanged(service, false)

        assertTrue(clock.tasks.single().canceled)
        clock.fire(0) // A real scheduler can race; generation/connected must reject it.
        assertEquals(0, refreshes)
    }

    @Test
    fun reconnectStartsAFullNewThreeSecondTimer() {
        val clock = FakeClock()
        var refreshes = 0
        val service = Any()
        val connected = refresh(clock) { refreshes++ }

        connected.starting(service)
        connected.stateChanged(service, true)
        connected.stateChanged(service, false)
        connected.stateChanged(service, true)

        assertEquals(2, clock.tasks.size)
        assertEquals(PsiphonConnectedRefresh.DELAY_MS, clock.tasks[1].delayMs)
        clock.fire(0)
        assertEquals(0, refreshes)
        clock.fire(1)
        assertEquals(1, refreshes)
    }

    @Test
    fun replacedOwnerIgnoresOldFalseAndTrueStates() {
        val clock = FakeClock()
        var refreshes = 0
        val oldService = Any()
        val newService = Any()
        val connected = refresh(clock) { refreshes++ }

        connected.starting(oldService)
        connected.stateChanged(oldService, true)
        connected.starting(newService)
        connected.stateChanged(oldService, false)
        connected.stateChanged(oldService, true)

        assertTrue(clock.tasks[0].canceled)
        assertEquals(1, clock.tasks.size)
        connected.stateChanged(newService, true)
        assertEquals(2, clock.tasks.size)
        clock.fire(1)
        assertEquals(1, refreshes)
    }

    @Test
    fun manuallyFiredCanceledOldTimerIsRejectedByGenerationGuard() {
        val clock = FakeClock()
        var refreshes = 0
        val service = Any()
        val connected = refresh(clock) { refreshes++ }

        connected.starting(service)
        connected.stateChanged(service, true)
        connected.starting(service)
        connected.stateChanged(service, true)

        clock.fire(0)
        assertEquals(0, refreshes)
        clock.fire(1)
        assertEquals(1, refreshes)
    }

    @Test
    fun ownerIsNotRetainedByRefreshController() {
        val clock = FakeClock()
        val connected = refresh(clock)
        val service = Any()

        connected.starting(service)
        connected.stateChanged(service, true)

        // The implementation stores only a WeakReference; inspect the field rather
        // than relying on nondeterministic garbage collection.
        assertFalse(clock.tasks.isEmpty())
        val ownerField = PsiphonConnectedRefresh::class.java.getDeclaredField("owner")
        assertEquals(java.lang.ref.WeakReference::class.java, ownerField.type)
    }
}
