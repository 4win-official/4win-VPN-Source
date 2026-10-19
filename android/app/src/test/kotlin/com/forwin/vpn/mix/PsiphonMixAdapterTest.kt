package com.forwin.vpn.mix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Regression coverage for native packet-stack startup/terminal-state mapping. */
class PsiphonMixAdapterTest {
    @Test
    fun droppedStartupConnectionCannotPublishReadyFromAStaleConnectedEvent() {
        val state = PsiphonMixAdapter.ConnectionState()
        assertFalse(state.canPublish(true))
        state.onConnected()
        assertFalse(state.canPublish(false))
        assertTrue(state.canPublish(true))
        state.onConnecting()
        assertFalse(state.canPublish(false))
        assertFalse(state.canPublish(true))
        state.onConnected()
        assertTrue(state.canPublish(true))
    }

    @Test
    fun nativeErrorBeforeReadyIsTerminalButNormalStartupIsNot() {
        assertEquals("bind failed", PsiphonMixAdapter.packetStackFailure(false, "bind failed"))
        assertNull(PsiphonMixAdapter.packetStackFailure(false, ""))
        assertNull(PsiphonMixAdapter.packetStackFailure(true, "stale error"))
    }
}
