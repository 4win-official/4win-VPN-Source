package com.forwin.vpn

import android.os.SystemClock
import java.util.UUID

/**
 * Process-local registry owned by native services. Activities may only call snapshot().
 * A service begins a record at its real connection transition and ends it at true teardown;
 * reconnect starts preserve the record when the same identity is supplied.
 */
object NativeSessionMetrics {
    data class Snapshot(val sessionId: String, val elapsedMillis: Long, val uplink: Long?, val downlink: Long?)
    private data class Entry(val id: String, val startedAt: Long, var uplink: Long?, var downlink: Long?)
    private val entries = HashMap<String, Entry>()
    @Volatile var clock: () -> Long = { SystemClock.elapsedRealtime() }

    @Synchronized fun begin(protocol: String, authoritativeId: String? = null, startedAtElapsed: Long? = null) {
        val key = protocol.lowercase()
        val current = entries[key]
        if (current == null || (authoritativeId != null && current.id != authoritativeId)) {
            entries[key] = Entry(authoritativeId ?: UUID.randomUUID().toString(), startedAtElapsed ?: clock(), null, null)
        }
    }
    @Synchronized fun adopt(protocol: String, id: String, startedAtElapsed: Long) = begin(protocol, id, startedAtElapsed)
    @Synchronized fun update(protocol: String, uplink: Long?, downlink: Long?) {
        entries[protocol.lowercase()]?.let { e ->
            if (uplink != null && uplink >= 0) e.uplink = uplink
            if (downlink != null && downlink >= 0) e.downlink = downlink
        }
    }
    @Synchronized fun end(protocol: String, id: String? = null) {
        val key = protocol.lowercase()
        if (id == null || entries[key]?.id == id) entries.remove(key)
    }
    @Synchronized fun snapshot(protocol: String): Snapshot? = entries[protocol.lowercase()]?.let { e ->
        Snapshot(e.id, (clock() - e.startedAt).coerceAtLeast(0L), e.uplink, e.downlink)
    }
    @Synchronized fun clearForTests() { entries.clear() }
}
