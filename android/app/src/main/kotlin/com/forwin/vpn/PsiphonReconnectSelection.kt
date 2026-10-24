package com.forwin.vpn

/** Resolves a reconnect target without changing an active session's selection semantics. */
internal object PsiphonReconnectSelection {
    fun targetServerId(
        hasActiveConnectIntent: Boolean,
        activeTargetServerId: String?,
        persistedTargetServerId: String?,
    ): String? {
        val requested = if (hasActiveConnectIntent) {
            activeTargetServerId
        } else {
            persistedTargetServerId
        }
        return requested?.takeIf { it.isNotBlank() }
    }
}
