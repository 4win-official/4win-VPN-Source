package com.forwin.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PsiphonKillSwitchPolicyTest {
    @Test
    fun failureHoldsTunOnlyWhenKillSwitchIsEnabled() {
        assertTrue(PsiphonKillSwitchPolicy.shouldHoldBlackhole(killSwitchEnabled = true, hasTun = true))
        assertFalse(PsiphonKillSwitchPolicy.shouldHoldBlackhole(killSwitchEnabled = false, hasTun = true))
        assertFalse(PsiphonKillSwitchPolicy.shouldHoldBlackhole(killSwitchEnabled = true, hasTun = false))
    }

    @Test
    fun disablingKillSwitchReleasesOnlyAnActiveBlackhole() {
        assertTrue(PsiphonKillSwitchPolicy.shouldReleaseBlackhole(killSwitchEnabled = false, blackholeActive = true))
        assertFalse(PsiphonKillSwitchPolicy.shouldReleaseBlackhole(killSwitchEnabled = true, blackholeActive = true))
        assertFalse(PsiphonKillSwitchPolicy.shouldReleaseBlackhole(killSwitchEnabled = false, blackholeActive = false))
    }
}
