package com.forwin.vpn

import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class NativeSessionMetricsTest {
    private var now = 1000L

    @Before fun setUp() {
        NativeSessionMetrics.clearForTests()
        NativeSessionMetrics.clock = { now }
    }

    @After fun tearDown() {
        NativeSessionMetrics.clearForTests()
        NativeSessionMetrics.clock = { android.os.SystemClock.elapsedRealtime() }
    }

    @Test fun repeatedReadRestoresElapsedWithoutRestartingClock() {
        NativeSessionMetrics.begin("xray", "session-a", 100L)
        now = 1600L
        val first = NativeSessionMetrics.snapshot("xray")!!
        val second = NativeSessionMetrics.snapshot("xray")!!
        assertEquals("session-a", second.sessionId)
        assertEquals(1500L, first.elapsedMillis)
        assertEquals(1500L, second.elapsedMillis)
    }

    @Test fun countersRemainCumulativeAndUpdate() {
        NativeSessionMetrics.begin("mix", "m", 100L)
        NativeSessionMetrics.update("mix", 12L, 30L)
        NativeSessionMetrics.update("mix", 18L, 45L)
        assertEquals(18L, NativeSessionMetrics.snapshot("mix")!!.uplink)
        assertEquals(45L, NativeSessionMetrics.snapshot("mix")!!.downlink)
    }

    @Test fun disconnectThenNewIdentityResetsElapsedAndCounters() {
        NativeSessionMetrics.begin("slowdns", "old", 100L)
        NativeSessionMetrics.update("slowdns", 9L, 8L)
        NativeSessionMetrics.end("slowdns", "old")
        assertNull(NativeSessionMetrics.snapshot("slowdns"))
        NativeSessionMetrics.begin("slowdns", "new", 900L)
        now = 950L
        val snapshot = NativeSessionMetrics.snapshot("slowdns")!!
        assertEquals("new", snapshot.sessionId)
        assertEquals(50L, snapshot.elapsedMillis)
        assertNull(snapshot.uplink)
    }

    @Test fun repeatedConnectedCallbackKeepsExistingSession() {
        NativeSessionMetrics.begin("xray", "existing", 100L)
        NativeSessionMetrics.update("xray", 100L, 200L)
        now = 10000L
        NativeSessionMetrics.begin("xray")
        val snapshot = NativeSessionMetrics.snapshot("xray")!!
        assertEquals("existing", snapshot.sessionId)
        assertEquals(9900L, snapshot.elapsedMillis)
        assertEquals(100L, snapshot.uplink)
    }

    @Test fun crossProcessRestoreUsesRemoteServiceStartNotReceiptTime() {
        now = 125000L
        NativeSessionMetrics.adopt("psiphon", "remote", 1000L)
        NativeSessionMetrics.update("psiphon", 1024L, 2048L)
        assertEquals(124000L, NativeSessionMetrics.snapshot("psiphon")!!.elapsedMillis)
        now = 127000L
        NativeSessionMetrics.adopt("psiphon", "remote", 1000L)
        assertEquals(126000L, NativeSessionMetrics.snapshot("psiphon")!!.elapsedMillis)
        assertEquals(2048L, NativeSessionMetrics.snapshot("psiphon")!!.downlink)
    }

    @Test fun lateStopCannotEndNewerSession() {
        NativeSessionMetrics.begin("psiphon", "old", 100L)
        NativeSessionMetrics.begin("psiphon", "new", 900L)
        NativeSessionMetrics.end("psiphon", "old")
        assertEquals("new", NativeSessionMetrics.snapshot("psiphon")!!.sessionId)
    }

    @Test fun unavailableMeasurementsDoNotEraseMeasuredCounters() {
        NativeSessionMetrics.begin("mix", "m")
        NativeSessionMetrics.update("mix", 10L, 20L)
        NativeSessionMetrics.update("mix", -1L, null)
        assertEquals(10L, NativeSessionMetrics.snapshot("mix")!!.uplink)
        assertEquals(20L, NativeSessionMetrics.snapshot("mix")!!.downlink)
    }
}
