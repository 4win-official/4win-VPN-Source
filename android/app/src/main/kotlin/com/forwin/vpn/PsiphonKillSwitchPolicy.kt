package com.forwin.vpn

/** Psiphon-only decisions for holding or releasing its fail-closed TUN. */
internal object PsiphonKillSwitchPolicy {
    fun shouldHoldBlackhole(killSwitchEnabled: Boolean, hasTun: Boolean): Boolean =
        killSwitchEnabled && hasTun

    fun shouldReleaseBlackhole(killSwitchEnabled: Boolean, blackholeActive: Boolean): Boolean =
        !killSwitchEnabled && blackholeActive
}
