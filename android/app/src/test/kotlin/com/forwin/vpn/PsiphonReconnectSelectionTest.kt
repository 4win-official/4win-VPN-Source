package com.forwin.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PsiphonReconnectSelectionTest {
    @Test
    fun activeAutomaticSelectionDoesNotReuseStalePersistedTarget() {
        assertNull(
            PsiphonReconnectSelection.targetServerId(
                hasActiveConnectIntent = true,
                activeTargetServerId = null,
                persistedTargetServerId = "removed-server-id",
            ),
        )
    }

    @Test
    fun activeManualSelectionRemainsAuthoritativeAcrossReconnect() {
        assertEquals(
            "selected-server-id",
            PsiphonReconnectSelection.targetServerId(
                hasActiveConnectIntent = true,
                activeTargetServerId = "selected-server-id",
                persistedTargetServerId = "different-stale-id",
            ),
        )
    }

    @Test
    fun stickyRestoreUsesPersistedTargetOnlyWhenNoActiveConnectIntentExists() {
        assertEquals(
            "saved-server-id",
            PsiphonReconnectSelection.targetServerId(
                hasActiveConnectIntent = false,
                activeTargetServerId = null,
                persistedTargetServerId = "saved-server-id",
            ),
        )
        assertNull(
            PsiphonReconnectSelection.targetServerId(
                hasActiveConnectIntent = false,
                activeTargetServerId = null,
                persistedTargetServerId = "   ",
            ),
        )
    }
}
