package com.forwin.vpn

import org.junit.Assert.assertEquals
import org.junit.Test

class VpnNotificationLabelsTest {
    @Test fun mixUsesTheExactEnglishProtocolLabel() {
        assertEquals("Mix Protocol", VpnNotificationLabels.MIX_PROTOCOL)
        assertEquals("Mix Protocol", VpnNotificationLabels.xrayTitle(mixMode = true, isWarp = false))
    }

    @Test fun mixIdentityWinsOverItsUnderlyingEngineOnEveryRefresh() {
        // Simulate successive updates with different underlying engine detections.
        listOf(false, true, false, true).forEach { warp ->
            assertEquals("Mix Protocol", VpnNotificationLabels.xrayTitle(mixMode = true, isWarp = warp))
        }
    }

    @Test fun standaloneXrayKeepsItsExistingLabel() {
        assertEquals("🔒 Xray Connected", VpnNotificationLabels.xrayTitle(mixMode = false, isWarp = false))
    }

    @Test fun standaloneWarpKeepsItsExistingLabel() {
        assertEquals("🔒 WARP Connected", VpnNotificationLabels.xrayTitle(mixMode = false, isWarp = true))
    }

    @Test fun switchingBackToStandaloneDoesNotKeepTheMixLabel() {
        assertEquals("Mix Protocol", VpnNotificationLabels.xrayTitle(mixMode = true, isWarp = false))
        assertEquals("🔒 Xray Connected", VpnNotificationLabels.xrayTitle(mixMode = false, isWarp = false))
        assertEquals("🔒 WARP Connected", VpnNotificationLabels.xrayTitle(mixMode = false, isWarp = true))
    }
}
