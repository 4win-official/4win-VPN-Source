package com.forwin.vpn.mix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Regression coverage for native packet-stack startup/terminal-state mapping. */
class PsiphonMixAdapterTest {
    @Test
    fun nativeErrorBeforeReadyIsTerminalButNormalStartupIsNot() {
        assertEquals("bind failed", PsiphonMixAdapter.packetStackFailure(false, "bind failed"))
        assertNull(PsiphonMixAdapter.packetStackFailure(false, ""))
        assertNull(PsiphonMixAdapter.packetStackFailure(true, "stale error"))
    }
}
