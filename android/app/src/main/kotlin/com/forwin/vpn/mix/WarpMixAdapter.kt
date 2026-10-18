package com.forwin.vpn.mix

import com.forwin.vpn.NativeCore
import org.json.JSONObject
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** WARP worker: no Android TUN, no standalone settings/files writes, no bypass. */
class WarpMixAdapter : MixAdapter {
    private val lock = Any()
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "warp-mix-monitor").apply { isDaemon = true }
    }
    @Volatile private var stopped = false
    private var started = false
    private var engine: MixBlockingCoreRunner? = null

    override fun start(config: JSONObject, environment: MixAdapterEnvironment) {
        synchronized(lock) { if (started || stopped) return; started = true }
        worker.execute {
            var identity: MixWarpIdentity.Lease? = null
            var privateRoot: File? = null
            var nativeOwnsResources = false
            try {
                require(environment.listenPort in 1..65535) { "Invalid Mix SOCKS port" }
                val originalRoot = environment.context.filesDir
                val root = File(originalRoot, "mix-runtime/${environment.sessionId}/${environment.hopId}/warp")
                privateRoot = root
                check(root.mkdirs() || root.isDirectory) { "Cannot create private Mix WARP directory" }
                val lease = MixWarpIdentity.acquire(originalRoot, environment.hopId)
                identity = lease
                val effective = MixWarpConfig.build(config, root.absolutePath,
                    environment.listenPort, environment.upstreamSocksUrl, lease.account.absolutePath)
                val runner = MixBlockingCoreRunner(
                    runCore = { NativeCore.startProxy(effective.toString()) },
                    requestStop = { NativeCore.stop(); Unit },
                    afterExit = { try { lease.close() } finally { root.deleteRecursively() } },
                )
                synchronized(lock) {
                    if (stopped) return@execute
                    engine = runner
                    // startProxy blocks until shutdown; the runner dedicates a
                    // separate thread to it so readiness/stop remain responsive.
                    runner.start()
                    nativeOwnsResources = true
                }
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(100)
                while (!stopped && System.nanoTime() < deadline) {
                    checkNativeAlive(runner)
                    if (NativeCore.isReady() && listenerWorks(environment.listenPort)) break
                    Thread.sleep(100)
                }
                if (stopped) return@execute
                checkNativeAlive(runner)
                check(NativeCore.isReady() && listenerWorks(environment.listenPort)) { "WARP did not become ready" }
                environment.onReady(true)
                var failures = 0
                while (!stopped) {
                    Thread.sleep(1_000)
                    checkNativeAlive(runner)
                    failures = if (NativeCore.isReady() && listenerWorks(environment.listenPort)) 0 else failures + 1
                    check(failures < 3) { "WARP stage stopped" }
                }
            } catch (failure: Throwable) {
                val runner = synchronized(lock) { engine }
                runner?.stop()
                if (!stopped) environment.onFailure(failure.message ?: "WARP Mix failed")
            } finally {
                // Once launched, only the returning native thread may release
                // the lease or delete runtime files, even if stop times out.
                if (!nativeOwnsResources) {
                    identity?.close()
                    privateRoot?.deleteRecursively()
                }
            }
        }
    }

    private fun checkNativeAlive(runner: MixBlockingCoreRunner) {
        if (!runner.result.isDone) return
        val result = runner.result.get()
        error(NativeCore.lastError().ifBlank { "WARP native core exited ($result)" })
    }

    private fun listenerWorks(port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 250) }
        true
    }.getOrDefault(false)

    override fun stop() {
        val runner = synchronized(lock) {
            if (stopped) return
            stopped = true
            engine
        }
        worker.shutdownNow()
        runner?.stop()
        runCatching { worker.awaitTermination(1, TimeUnit.SECONDS) }
    }
}
