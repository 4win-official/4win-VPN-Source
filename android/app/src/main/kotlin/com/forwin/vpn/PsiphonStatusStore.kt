package com.forwin.vpn

import android.content.Intent

/**
 * Main-process cache of the `:psiphon` [PsiphonVpnService] state.
 *
 * The Psiphon VPN service intentionally runs in its own process (see
 * [VpnApplication]), so its `@Volatile` statics are invisible here. Instead the
 * service publishes [PsiphonVpnService.ACTION_STATUS] broadcasts (on every state
 * change plus a 2s heartbeat while alive) and this store keeps the latest
 * snapshot for MainActivity's MethodChannel handlers.
 *
 * Staleness guard: if the `:psiphon` process dies without a clean shutdown
 * (e.g. a native crash), heartbeats stop arriving and [isRunning]/[isConnected]
 * automatically flip back to false instead of sticking on a stale "connected".
 */
object PsiphonStatusStore {
    @Volatile private var running = false
    @Volatile private var connected = false
    @Volatile private var killSwitch = false
    @Volatile private var uplink = 0L
    @Volatile private var downlink = 0L
    @Volatile private var statusText = ""
    @Volatile private var region = ""
    // Exit regions last reported available by the Psiphon core (server list
    // for the settings screen). An empty list = unknown / not yet reported.
    @Volatile private var egressRegions: List<String> = emptyList()
    @Volatile private var lastHeartbeatMs = 0L

    private const val STALE_AFTER_MS = 8000L
    private const val MAX_LOGS = 200
    private val logs = ArrayList<String>()

    @JvmStatic fun isRunning(): Boolean = running && !isStale()

    @JvmStatic fun isConnected(): Boolean = connected && !isStale()

    @JvmStatic fun isKillSwitchActive(): Boolean = killSwitch && !isStale()

    @JvmStatic fun queryTrafficStats(): LongArray = longArrayOf(uplink, downlink)

    @JvmStatic fun statusText(): String = statusText

    @JvmStatic fun region(): String = region

    /** Number of exit servers the Psiphon core last reported as available. */
    @JvmStatic fun egressRegionCount(): Int = egressRegions.size

    /** Exit server region codes (e.g. US, DE, NL…) last reported as available. */
    @JvmStatic fun egressRegions(): List<String> = egressRegions

    @JvmStatic
    fun getLogs(): List<String> = synchronized(logs) { ArrayList(logs) }

    @JvmStatic
    fun reset() {
        running = false
        connected = false
        killSwitch = false
        uplink = 0L
        downlink = 0L
        statusText = ""
        region = ""
        egressRegions = emptyList()
        lastHeartbeatMs = 0L
        synchronized(logs) { logs.clear() }
    }

    private fun isStale(): Boolean {
        if (lastHeartbeatMs == 0L) return true
        return System.currentTimeMillis() - lastHeartbeatMs > STALE_AFTER_MS
    }

    @JvmStatic
    fun onStatusBroadcast(intent: Intent) {
        try {
            running = intent.getBooleanExtra(PsiphonVpnService.EXTRA_RUNNING, running)
            connected = intent.getBooleanExtra(PsiphonVpnService.EXTRA_CONNECTED, connected)
            killSwitch = intent.getBooleanExtra(PsiphonVpnService.EXTRA_KILLSWITCH, killSwitch)
            uplink = intent.getLongExtra(PsiphonVpnService.EXTRA_UPLINK, uplink)
            downlink = intent.getLongExtra(PsiphonVpnService.EXTRA_DOWNLINK, downlink)
            intent.getStringExtra(PsiphonVpnService.EXTRA_STATUS_TEXT)?.let { statusText = it }
            intent.getStringExtra(PsiphonVpnService.EXTRA_REGION)?.let { region = it }
            intent.getStringArrayListExtra(PsiphonVpnService.EXTRA_EGRESS_REGIONS)?.let {
                egressRegions = ArrayList(it)
            }
            lastHeartbeatMs = System.currentTimeMillis()
            val lines = intent.getStringArrayListExtra(PsiphonVpnService.EXTRA_LOG_LINES)
            if (lines != null) appendLogs(lines)
        } catch (_: Throwable) {
            // Never let a malformed broadcast break the store.
        }
    }

    @JvmStatic
    fun appendLogs(lines: List<String>) {
        if (lines.isEmpty()) return
        synchronized(logs) {
            for (line in lines) {
                if (logs.size >= MAX_LOGS) logs.removeAt(0)
                logs.add(line)
            }
        }
    }
}
