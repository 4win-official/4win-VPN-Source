package com.forwin.vpn.mix

import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** The JNI start call BLOCKS for the complete native tunnel lifetime.
 * Never hold an adapter lifecycle lock around that call, and never release
 * identity resources merely because nativeStop() acknowledged a stop request.
 */
internal class MixBlockingCoreRunner(
    private val runCore: () -> Int,
    private val requestStop: () -> Unit,
    private val afterExit: () -> Unit,
) {
    private val lock = Any()
    private val cancelled = AtomicBoolean(false)
    private var thread: Thread? = null
    val result = CompletableFuture<Int>()

    fun start() = synchronized(lock) {
        check(thread == null && !cancelled.get()) { "Mix native core already started or stopped" }
        val task = Thread({
            var code = 0
            var failure: Throwable? = null
            try { if (!cancelled.get()) code = runCore() }
            catch (error: Throwable) { failure = error }
            finally {
                try { afterExit() } catch (error: Throwable) { if (failure == null) failure = error }
            }
            val error = failure
            if (error == null) result.complete(code) else result.completeExceptionally(error)
        }, "mix-warp-native").apply { isDaemon = true }
        thread = task
        task.start()
    }

    /** Returns false on timeout; afterExit still belongs to the live native
     * thread, keeping its identity lease until that thread actually returns.
     */
    fun stop(timeoutMillis: Long = 5_000): Boolean {
        val task = synchronized(lock) { cancelled.set(true); thread } ?: return true
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis)
        var interrupted = false
        while (task.isAlive && System.nanoTime() < deadline) {
            // The first stop can race the native RUNNING flag/reset. Repeat
            // until the blocking start returns instead of losing cancellation.
            runCatching { requestStop() }
            try { task.join(25) } catch (_: InterruptedException) { interrupted = true }
        }
        if (interrupted) Thread.currentThread().interrupt()
        return !task.isAlive
    }
}
