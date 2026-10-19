package com.forwin.vpn

/** Notification identity follows the user-selected protocol, not its routing engine. */
internal object VpnNotificationLabels {
    const val MIX_PROTOCOL = "Mix Protocol"

    fun xrayTitle(mixMode: Boolean, isWarp: Boolean): String = when {
        // Mix may use Xray/WARP internally; neither may replace its top-level name.
        mixMode -> MIX_PROTOCOL
        isWarp -> "🔒 WARP Connected"
        else -> "🔒 Xray Connected"
    }
}
