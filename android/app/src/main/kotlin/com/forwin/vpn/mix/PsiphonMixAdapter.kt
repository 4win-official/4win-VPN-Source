package com.forwin.vpn.mix

import android.content.Context
import ca.psiphon.PsiphonTunnel
import gi.Seq
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Psiphon as a Mix hop. This class deliberately does not use VpnService, a
 * ParcelFileDescriptor, or Psiphon's VPN mode: its only externally useful
 * endpoint is the local SOCKS listener.
 *
 * Psiphon callbacks are delivered by native threads, so all state transitions
 * are generation-checked and serialized. In particular, a callback racing
 * with stop() cannot publish readiness to the next chain.
 */
class PsiphonMixAdapter : MixAdapter {
    companion object {
        private const val NATIVE_LIBRARY = "psiphon-gojni"
        private const val CONNECT_TIMEOUT_SECONDS = 120L
    }

    private val lock = Any()
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "psiphon-mix").apply { isDaemon = true }
    }

    @Volatile private var stopped = false
    private var started = false
    private var generation = 0L
    private var tunnel: PsiphonTunnel? = null
    private var connected = false
    private var socksPort = 0
    private var readySent = false
    private var failureSent = false
    private var timeout: ScheduledFuture<*>? = null
    private var timeoutExecutor: java.util.concurrent.ScheduledExecutorService? = null

    override fun start(config: JSONObject, environment: MixAdapterEnvironment) {
        val token: Long
        synchronized(lock) {
            if (started || stopped) return
            started = true
            token = ++generation
        }
        worker.execute {
            try {
                startNative(config, environment, token)
            } catch (t: Throwable) {
                fail(token, environment, "Psiphon start failed: ${t.message ?: "native initialization error"}")
            }
        }
    }

    private fun startNative(config: JSONObject, environment: MixAdapterEnvironment, token: Long) {
        if (!isLive(token)) return

        // The build relocates Psiphon's gomobile bridge from go.* to gi.* and
        // its library to libpsiphon-gojni.so. This process contains no Xray
        // runtime, but explicitly initializing it keeps this adapter usable
        // when the generic worker service has no ContentProvider initializer.
        Seq.setContext(environment.context.applicationContext)
        System.loadLibrary(NATIVE_LIBRARY)

        require(environment.listenPort in 1..65535) { "invalid Mix SOCKS listen port" }
        val psiphonConfig = JSONObject(config.toString())
            .put("LocalSocksProxyPort", environment.listenPort)
            // Mix consumes SOCKS only; do not ask Psiphon to expose HTTP.
            .put("LocalHttpProxyPort", 0)

        // Overwrite any caller-provided value. If this is a non-first hop,
        // the supplied proxy is mandatory and Psiphon must not silently use a
        // direct route when it cannot reach it. A null value is the deliberate
        // first-hop case and therefore omits the option.
        if (environment.upstreamSocksUrl != null) {
            psiphonConfig.put("UpstreamProxyURL", environment.upstreamSocksUrl)
        } else {
            psiphonConfig.remove("UpstreamProxyURL")
        }

        val hostService = object : PsiphonTunnel.HostService {
            override fun getContext(): Context = environment.context.applicationContext
            override fun getPsiphonConfig(): String = psiphonConfig.toString()
            override fun loadLibrary(library: String) {
                if (library == "gojni") System.loadLibrary(NATIVE_LIBRARY)
                else System.loadLibrary(library)
            }

            // This is a normal Service, not a VpnService. There is no TUN fd
            // to protect; the worker process is excluded from the outer VPN by
            // the coordinator. Leaving the socket on the normal network is
            // intentional and avoids an unsafe VpnService cast.
            override fun bindToDevice(fileDescriptor: Long) = Unit

            override fun onConnecting() = Unit

            override fun onConnected() {
                synchronized(lock) {
                    if (!isLiveLocked(token)) return
                    connected = true
                    publishReadyLocked(token, environment)
                }
            }

            override fun onListeningSocksProxyPort(port: Int) {
                synchronized(lock) {
                    if (!isLiveLocked(token)) return
                    if (port !in 1..65535) {
                        failLocked(token, environment, "Psiphon returned an invalid SOCKS port")
                        return
                    }
                    socksPort = port
                    publishReadyLocked(token, environment)
                }
            }

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

        val created = PsiphonTunnel.newPsiphonTunnel(hostService)
        created.setVpnMode(false)
        synchronized(lock) {
            if (!isLiveLocked(token)) {
                try { created.stop() } catch (_: Throwable) {}
                return
            }
            tunnel = created
            timeoutExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
                Thread(runnable, "psiphon-mix-timeout").apply { isDaemon = true }
            }
            timeout = timeoutExecutor!!.let { timer ->
                val future = timer.schedule({
                    fail(token, environment, "Psiphon connection timed out")
                    timer.shutdown()
                }, CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                future
            }
        }
        // The existing service supplies its bootstrap/license through the
        // HostService config and starts with an empty runtime argument. Keep
        // that behavior so encoded bootstrap/license fields in config remain
        // untouched and are not emitted in logs.
        created.startTunneling("")
    }

    private fun publishReadyLocked(token: Long, environment: MixAdapterEnvironment) {
        if (!connected || socksPort == 0 || readySent || !isLiveLocked(token)) return
        readySent = true
        timeout?.cancel(false)
        timeout = null
        try {
            environment.onReady(false)
        } catch (_: Throwable) {
            // The chain owner is external to the native callback thread.
        }
    }

    private fun fail(token: Long, environment: MixAdapterEnvironment, reason: String) {
        synchronized(lock) { failLocked(token, environment, reason) }
    }

    private fun failLocked(token: Long, environment: MixAdapterEnvironment, reason: String) {
        if (!isLiveLocked(token) || failureSent) return
        failureSent = true
        timeout?.cancel(false)
        timeout = null
        timeoutExecutor?.shutdownNow()
        timeoutExecutor = null
        try { tunnel?.stop() } catch (_: Throwable) {}
        tunnel = null
        try { environment.onFailure(reason) } catch (_: Throwable) {}
    }

    private fun isLive(token: Long): Boolean = synchronized(lock) { isLiveLocked(token) }

    private fun isLiveLocked(token: Long): Boolean =
        !stopped && started && generation == token && !failureSent

    override fun stop() {
        val toStop: PsiphonTunnel?
        synchronized(lock) {
            if (stopped) return
            stopped = true
            ++generation
            timeout?.cancel(true)
            timeout = null
            timeoutExecutor?.shutdownNow()
            timeoutExecutor = null
            toStop = tunnel
            tunnel = null
        }
        try { toStop?.stop() } catch (_: Throwable) {}
        worker.shutdownNow()
    }
}
