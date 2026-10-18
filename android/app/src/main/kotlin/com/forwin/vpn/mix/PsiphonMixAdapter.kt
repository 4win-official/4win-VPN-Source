package com.forwin.vpn.mix

import android.content.Context
import android.content.ContextWrapper
import android.os.ParcelFileDescriptor
import ca.psiphon.PsiphonTunnel
import gi.Seq
import org.json.JSONObject
import psi.Psi
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/** Raw IP is carried by Psiphon's authenticated packet-tunnel SSH channel.
 * A private datagram socketpair replaces the device TUN: MixPacketStack supplies
 * the local SOCKS5 TCP/UDP endpoint. No second Android VPN, external UDP relay,
 * guessed UDPGW address, or direct UDP fallback is involved.
 */
class PsiphonMixAdapter : MixAdapter {
    companion object {
        private const val NATIVE_LIBRARY = "psiphon-gojni"
        private const val CONNECT_TIMEOUT_SECONDS = 120L
    }
    private val lock = Any()
    // Native stop can join callback threads. Never acquire this while holding
    // the callback lock; callbacks only schedule resource cleanup.
    private val nativeLock = Any()
    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "psiphon-mix").apply { isDaemon = true }
    }
    @Volatile private var stopped = false
    private var started = false
    private var generation = 0L
    private var connected = false
    private var readySent = false
    private var failureSent = false
    private var timer: ScheduledExecutorService? = null
    private var tunnel: PsiphonTunnel? = null // nativeLock ownership
    @Volatile private var packetStack: MixPacketStack? = null
    private var packetPair: Pair<ParcelFileDescriptor, ParcelFileDescriptor>? = null

    override fun start(config: JSONObject, environment: MixAdapterEnvironment) {
        val token = synchronized(lock) {
            if (started || stopped) return
            started = true
            ++generation
        }
        worker.execute {
            try { synchronized(nativeLock) { startNative(config, environment, token) } }
            catch (failure: Throwable) {
                fail(token, environment, "Psiphon packet tunnel failed: ${failure.message ?: "initialization error"}")
            }
        }
    }

    private fun startNative(config: JSONObject, environment: MixAdapterEnvironment, token: Long) {
        if (!isLive(token)) return
        Seq.setContext(environment.context.applicationContext)
        System.loadLibrary(NATIVE_LIBRARY)
        require(environment.listenPort in 1..65535) { "Invalid Mix SOCKS listen port" }
        val root = MixPsiphonConfig.root(environment.context.filesDir, environment.hopId)
        listOf(root, File(root, "tunnel-core"), File(root, "legacy"), File(root, "cache"),
            File(root, "no-backup")).forEach {
            check(it.mkdirs() || it.isDirectory) { "Cannot prepare private Mix Psiphon storage" }
        }
        val privateContext = object : ContextWrapper(environment.context.applicationContext) {
            override fun getApplicationContext(): Context = this
            override fun getFilesDir(): File = File(root, "legacy")
            override fun getCacheDir(): File = File(root, "cache")
            override fun getNoBackupFilesDir(): File = File(root, "no-backup")
            override fun getFileStreamPath(name: String): File = File(filesDir, name)
            override fun getSharedPreferences(name: String, mode: Int) =
                super.getSharedPreferences("mix_psiphon_${environment.hopId}_$name", mode)
        }
        val bootstrap = environment.context.assets.open("mix_psiphon_bootstrap.json")
            .bufferedReader(Charsets.UTF_8).use { JSONObject(it.readText()) }
        val pair = MixPacketStack.createPacketPair()
        packetPair = pair
        // Psiphon explicitly permits arbitrary local IPs and rewrites them at
        // the authenticated server; these are local stack addresses, not peers.
        val mtu = Psi.getPacketTunnelMTU().toInt()
        require(mtu in 576..65535) { "Invalid Psiphon packet-tunnel MTU" }
        packetStack = MixPacketStack.start(pair.first, "10.0.0.3", "fd00::3", mtu, environment.listenPort)
        val effective = MixPsiphonConfig.packet(config, root, environment.listenPort,
            environment.upstreamSocksUrl, bootstrap, pair.second.fd)
        val host = object : PsiphonTunnel.HostService {
            override fun getContext(): Context = privateContext
            override fun getPsiphonConfig(): String = effective.toString()
            override fun loadLibrary(library: String) {
                System.loadLibrary(if (library == "gojni") NATIVE_LIBRARY else library)
            }
            // The coordinator excludes its own package from the final TUN.
            // Every non-entry Psiphon connection uses UpstreamProxyURL instead.
            override fun bindToDevice(fileDescriptor: Long) = Unit
            override fun onConnecting() {
                synchronized(lock) {
                    if (readySent && isLiveLocked(token))
                        failLocked(token, environment, "Psiphon stage lost its packet tunnel")
                }
            }
            override fun onConnected() {
                synchronized(lock) {
                    if (!isLiveLocked(token)) return
                    connected = true
                    publishReadyLocked(token, environment)
                }
            }
            // Both built-in proxies are disabled; the SOCKS port belongs only
            // to MixPacketStack, not Psiphon's TCP-only local proxy.
            override fun onListeningSocksProxyPort(port: Int) = Unit
            override fun onListeningHttpProxyPort(port: Int) = Unit
            override fun onBytesTransferred(sent: Long, received: Long) = Unit
            override fun onAvailableEgressRegions(regions: MutableList<String>?) = Unit
            override fun onSplitTunnelRegions(regions: MutableList<String>?) = Unit
            override fun onUpstreamProxyError(message: String?) {
                fail(token, environment, "Psiphon upstream proxy failed")
            }
            override fun onStartedWaitingForNetworkConnectivity() = Unit
            override fun onStoppedWaitingForNetworkConnectivity() = Unit
            override fun onDiagnosticMessage(message: String?) = Unit
        }
        if (!isLive(token)) { closeNativeResources(); return }
        val created = PsiphonTunnel.newPsiphonTunnel(host)
        tunnel = created
        created.setVpnMode(false) // The private packet FD is already in JSON.
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(CONNECT_TIMEOUT_SECONDS)
        synchronized(lock) {
            if (!isLiveLocked(token)) return
            timer = Executors.newSingleThreadScheduledExecutor { task ->
                Thread(task, "psiphon-mix-monitor").apply { isDaemon = true }
            }.also { monitor ->
                monitor.scheduleAtFixedRate({
                    try {
                        synchronized(lock) {
                            if (!isLiveLocked(token)) return@scheduleAtFixedRate
                            val stack = packetStack
                            if (readySent && stack?.ready != true)
                                failLocked(token, environment, stack?.error ?: "Psiphon packet stack closed")
                            else if (!readySent && System.nanoTime() >= deadline)
                                failLocked(token, environment, "Psiphon packet tunnel connection timed out")
                            else publishReadyLocked(token, environment)
                        }
                    } catch (error: Throwable) {
                        fail(token, environment, error.message ?: "Psiphon packet stack failed")
                    }
                }, 100, 250, TimeUnit.MILLISECONDS)
            }
        }
        created.startTunneling("")
    }

    private fun publishReadyLocked(token: Long, environment: MixAdapterEnvironment) {
        if (!connected || packetStack?.ready != true || readySent || !isLiveLocked(token)) return
        readySent = true
        // This is a full packet tunnel, including UDP. The coordinator still
        // validates actual traffic through the complete chain before its TUN.
        try { environment.onReady(true) } catch (_: Throwable) { }
    }
    private fun fail(token: Long, environment: MixAdapterEnvironment, reason: String) {
        synchronized(lock) { failLocked(token, environment, reason) }
    }
    private fun failLocked(token: Long, environment: MixAdapterEnvironment, reason: String) {
        if (!isLiveLocked(token) || failureSent) return
        failureSent = true
        timer?.shutdownNow()
        timer = null
        Thread({ synchronized(nativeLock) { closeNativeResources() } }, "psiphon-mix-failed-stop")
            .apply { isDaemon = true; start() }
        try { environment.onFailure(reason) } catch (_: Throwable) { }
    }
    private fun isLive(token: Long): Boolean = synchronized(lock) { isLiveLocked(token) }
    private fun isLiveLocked(token: Long): Boolean =
        !stopped && started && generation == token && !failureSent

    /** Called under nativeLock, outside callback lock; idempotent. */
    private fun closeNativeResources() {
        val current = tunnel
        tunnel = null
        runCatching { current?.stop() }
        val stack = packetStack
        packetStack = null
        runCatching { stack?.close() }
        val pair = packetPair
        packetPair = null
        runCatching { pair?.first?.close() }
        runCatching { pair?.second?.close() }
    }
    override fun stop() {
        synchronized(lock) {
            if (stopped) return
            stopped = true
            ++generation
            timer?.shutdownNow()
            timer = null
        }
        synchronized(nativeLock) { closeNativeResources() }
        worker.shutdownNow()
    }
}
