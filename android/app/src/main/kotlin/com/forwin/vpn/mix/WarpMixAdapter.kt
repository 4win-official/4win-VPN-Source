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
        Thread(task, "warp-mix").apply { isDaemon = true }
    }
    @Volatile private var stopped = false
    private var started = false
    @Volatile private var temporaryRoot: File? = null

    override fun start(config: JSONObject, environment: MixAdapterEnvironment) {
        synchronized(lock) { if (started || stopped) return; started = true }
        worker.execute {
            try {
                require(environment.listenPort in 1..65535) { "Invalid Mix SOCKS port" }
                val originalRoot = environment.context.filesDir
                val privateRoot = File(originalRoot, "mix-runtime/${environment.sessionId}/${environment.hopId}/warp")
                check(privateRoot.mkdirs() || privateRoot.isDirectory) { "Cannot create private Mix WARP directory" }
                temporaryRoot = privateRoot
                val originalAccount = File(originalRoot, "aether-warp.toml")
                check(originalAccount.isFile) { "Initialize WARP once before adding it to a Mix chain" }
                originalAccount.copyTo(File(privateRoot, "aether-warp.toml"), overwrite = true)
                val effective = MixWarpConfig.build(config, privateRoot.absolutePath,
                    environment.listenPort, environment.upstreamSocksUrl)
                synchronized(lock) {
                    if (stopped) return@execute
                    val result = NativeCore.startProxy(effective.toString())
                    check(result == 0) { NativeCore.lastError().ifBlank { "WARP native start failed ($result)" } }
                }
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(100)
                while (!stopped && System.nanoTime() < deadline) {
                    if (NativeCore.isReady() && listenerWorks(environment.listenPort)) break
                    Thread.sleep(100)
                }
                if (stopped) return@execute
                check(NativeCore.isReady() && listenerWorks(environment.listenPort)) { "WARP did not become ready" }
                environment.onReady(true)
                var failures = 0
                while (!stopped) {
                    Thread.sleep(1_000)
                    failures = if (NativeCore.isReady() && listenerWorks(environment.listenPort)) 0 else failures + 1
                    check(failures < 3) { "WARP stage stopped" }
                }
            } catch (failure: Throwable) {
                if (!stopped) {
                    runCatching { NativeCore.stop() }
                    environment.onFailure(failure.message ?: "WARP Mix failed")
                }
            } finally {
                if (stopped) { temporaryRoot?.deleteRecursively(); temporaryRoot = null }
            }
        }
    }

    private fun listenerWorks(port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 250) }
        true
    }.getOrDefault(false)

    override fun stop() {
        synchronized(lock) { if (stopped) return; stopped = true }
        runCatching { NativeCore.stop() }
        worker.shutdownNow()
        runCatching { worker.awaitTermination(5, TimeUnit.SECONDS) }
        temporaryRoot?.deleteRecursively()
        temporaryRoot = null
    }
}
