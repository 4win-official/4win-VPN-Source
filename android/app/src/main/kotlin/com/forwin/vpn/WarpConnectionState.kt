package com.forwin.vpn

/** Result of one standalone WARP attempt, independent of the Activity/Flutter UI.
 * Never read Aether's global ready/error flags: Mix can use that runtime too. */
internal object WarpConnectionState {
    data class Snapshot(val request: Long, val starting: Boolean, val connected: Boolean, val error: String?)
    private var nextRequest = 0L
    private var state = Snapshot(0L, false, false, null)

    @Synchronized fun begin(): Long {
        val request = ++nextRequest
        state = Snapshot(request, true, false, null)
        return request
    }
    @Synchronized fun snapshot(): Snapshot = state
    @Synchronized fun connected(request: Long): Boolean {
        if (state.request == request && state.starting) {
            state = Snapshot(request, false, true, null)
        }
        return state.request == request && state.connected
    }
    @Synchronized fun fail(request: Long, error: String) {
        if (state.request == request && (state.starting || state.connected)) {
            state = Snapshot(request, false, false, error.ifBlank { "WARP connection failed." })
        }
    }
    @Synchronized fun timeout(request: Long, error: String): Boolean {
        if (state.request != request || !state.starting) return false
        state = Snapshot(request, false, false, error)
        return true
    }
    @Synchronized fun cancel(request: Long) {
        if (state.request == request) state = Snapshot(request, false, false, null)
    }
}
