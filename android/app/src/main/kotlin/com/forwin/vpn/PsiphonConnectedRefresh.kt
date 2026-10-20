package com.forwin.vpn

import java.lang.ref.WeakReference

/** One refresh after three seconds of native connected state, not three seconds after startup. */
internal class PsiphonConnectedRefresh(
    private val schedule: (Long, () -> Unit) -> Cancellation,
    private val refresh: () -> Unit,
) {
    fun interface Cancellation { fun cancel() }

    companion object { const val DELAY_MS = 3_000L }

    private val lock = Any()
    private var owner: WeakReference<Any>? = null
    private var generation = 0L
    private var connected = false
    private var pending: Cancellation? = null

    fun starting(source: Any) = synchronized(lock) {
        invalidate()
        owner = WeakReference(source)
    }

    fun stateChanged(source: Any, isConnected: Boolean) = synchronized(lock) {
        // A late stop/status from a replaced service must not affect the new service's timer.
        if (owner?.get() !== source) return@synchronized
        if (!isConnected) {
            invalidate()
            return@synchronized
        }
        if (connected) return@synchronized // Status/heartbeat repetition is not a new connection.
        connected = true
        val token = ++generation
        pending = schedule(DELAY_MS) {
            synchronized(lock) {
                if (token == generation && connected && owner?.get() != null) {
                    pending = null
                    // This callback only queues background work; no network/disk I/O under this lock.
                    refresh()
                }
            }
        }
    }

    private fun invalidate() {
        generation++
        connected = false
        pending?.cancel()
        pending = null
    }
}
