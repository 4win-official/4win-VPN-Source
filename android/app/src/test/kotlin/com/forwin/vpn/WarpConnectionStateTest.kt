package com.forwin.vpn

import org.junit.Assert.*
import org.junit.Test

class WarpConnectionStateTest {
    @Test fun nativeReadyPollingCanCompleteWithoutAStatusCallback() {
        val request = WarpConnectionState.begin()
        // The morning connection path observed the native READY flag directly;
        // no status callback is required to complete the matching request.
        assertTrue(WarpConnectionState.connected(request))
        val connected = WarpConnectionState.snapshot()
        assertTrue(connected.connected)
        assertFalse(connected.starting)
        assertTrue(WarpConnectionState.connected(request))
        assertEquals(connected, WarpConnectionState.snapshot())
    }

    @Test fun nativeReadyPollingCannotReviveTimedOutCancelledOrReplacedRequests() {
        val timedOut = WarpConnectionState.begin()
        assertTrue(WarpConnectionState.timeout(timedOut, "validation timed out"))
        assertFalse(WarpConnectionState.connected(timedOut))
        val cancelled = WarpConnectionState.begin()
        WarpConnectionState.cancel(cancelled)
        assertFalse(WarpConnectionState.connected(cancelled))
        val current = WarpConnectionState.begin()
        assertFalse(WarpConnectionState.connected(cancelled))
        assertEquals(WarpConnectionState.Snapshot(current, true, false, null), WarpConnectionState.snapshot())
    }

    @Test fun timeoutCannotOverwriteReadyOrANewerAttempt() {
        val ready = WarpConnectionState.begin()
        WarpConnectionState.connected(ready)
        assertFalse(WarpConnectionState.timeout(ready, "timeout"))
        assertTrue(WarpConnectionState.snapshot().connected)
        val current = WarpConnectionState.begin()
        assertFalse(WarpConnectionState.timeout(ready, "old timeout"))
        assertTrue(WarpConnectionState.timeout(current, "WARP validation timed out"))
        WarpConnectionState.connected(current)
        assertEquals("WARP validation timed out", WarpConnectionState.snapshot().error)
        assertFalse(WarpConnectionState.snapshot().connected)
    }

    @Test fun nativeFailureRetainsItsExplanationUntilExplicitRetryOrDisconnect() {
        val request = WarpConnectionState.begin()
        WarpConnectionState.fail(request, "WARP handshake failed: endpoint unreachable")
        val failed = WarpConnectionState.snapshot()
        assertFalse(failed.starting)
        assertFalse(failed.connected)
        assertEquals("WARP handshake failed: endpoint unreachable", failed.error)
        WarpConnectionState.connected(request)
        assertEquals(failed, WarpConnectionState.snapshot())
        WarpConnectionState.cancel(request)
        assertNull(WarpConnectionState.snapshot().error)
    }

    @Test fun olderEngineCannotSucceedFailOrCancelNewerAttempt() {
        val old = WarpConnectionState.begin()
        val current = WarpConnectionState.begin()
        WarpConnectionState.connected(old)
        WarpConnectionState.fail(old, "stale failure")
        WarpConnectionState.cancel(old)
        assertEquals(WarpConnectionState.Snapshot(current, true, false, null), WarpConnectionState.snapshot())
        WarpConnectionState.connected(current)
        assertTrue(WarpConnectionState.snapshot().connected)
        assertFalse(WarpConnectionState.snapshot().starting)
    }

    @Test fun failureAfterReadyIsVisibleAndNewRetryClearsIt() {
        val request = WarpConnectionState.begin()
        WarpConnectionState.connected(request)
        WarpConnectionState.fail(request, "WARP tunnel stopped unexpectedly")
        assertEquals("WARP tunnel stopped unexpectedly", WarpConnectionState.snapshot().error)
        val retry = WarpConnectionState.begin()
        assertEquals(WarpConnectionState.Snapshot(retry, true, false, null), WarpConnectionState.snapshot())
    }
}
