package com.forwin.vpn

import java.util.concurrent.Executor

/** One active refresh plus one coalesced follow-up (e.g. when the VPN becomes ready). */
internal class PsiphonRefreshQueue(private val executor: Executor) {
    private val lock = Any()
    private var running = false
    private var pending: (() -> Unit)? = null

    fun request(refresh: () -> Unit) {
        synchronized(lock) {
            if (running) {
                pending = refresh
                return
            }
            running = true
            try {
                executor.execute {
                    var next: (() -> Unit)? = refresh
                    while (next != null) {
                        try { next.invoke() } catch (_: Exception) { /* best effort */ }
                        next = synchronized(lock) {
                            val followUp = pending
                            pending = null
                            if (followUp == null) running = false
                            followUp
                        }
                    }
                }
            } catch (_: Exception) {
                running = false
                pending = null
            }
        }
    }

    /** Starts only when idle; unlike request(), never queues a duplicate follow-up. */
    fun tryRequest(refresh: () -> Unit): Boolean {
        synchronized(lock) {
            if (running) return false
            running = true
            try {
                executor.execute {
                    try { refresh() } finally { synchronized(lock) { running = false } }
                }
                return true
            } catch (_: Exception) {
                running = false
                return false
            }
        }
    }
}
