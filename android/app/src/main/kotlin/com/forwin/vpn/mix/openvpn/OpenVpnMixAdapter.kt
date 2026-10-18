package com.forwin.vpn.mix.openvpn

import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.forwin.vpn.mix.MixAdapter
import com.forwin.vpn.mix.MixAdapterEnvironment
import de.blinkt.openvpn.VpnProfile
import de.blinkt.openvpn.core.ConfigParser
import de.blinkt.openvpn.core.Connection
import de.blinkt.openvpn.core.ProfileManager
import org.json.JSONObject
import java.io.StringReader
import java.net.URI
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** OpenVPN engine. Its OpenVPNService subclass returns a raw packet fd. */
class OpenVpnMixAdapter : MixAdapter {
    private val lifecycleLock = Any()
    private val failureReported = AtomicBoolean(false)
    private val stopped = AtomicBoolean(true)
    private val main = Handler(Looper.getMainLooper())
    private var worker: ExecutorService? = null
    private var runtime: OpenVpnMixService.Runtime? = null
    private var serviceIntent: Intent? = null
    private var environment: MixAdapterEnvironment? = null

    override fun start(config: JSONObject, environment: MixAdapterEnvironment) {
        if (!stopped.compareAndSet(true, false)) { environment.onFailure("OpenVPN Mix adapter is already running"); return }
        this.environment = environment
        worker = Executors.newSingleThreadExecutor { r -> Thread(r, "openvpn-mix-${environment.sessionId}").apply { isDaemon = true } }
        worker!!.execute {
            try {
                val raw = sequenceOf("config", "inlineConfig", "ovpn").mapNotNull { config.optString(it, "").takeIf(String::isNotBlank) }.firstOrNull()
                    ?: error("missing inline OpenVPN config")
                val upstream = environment.upstreamSocksUrl?.let(::parseSocks)
                val upstreamSupportsUdp = config.optBoolean("upstreamSupportsUdp", true)
                val parser = ConfigParser()
                parser.parseConfig(StringReader(stripProxyOptions(raw, upstream)))
                val profile = parser.convertProfile()
                if (upstream != null) {
                    if (!upstreamSupportsUdp && profile.mConnections.any { it.mUseUdp })
                        error("OpenVPN UDP remote requires an upstream with UDP support")
                    // Apply the selected upstream to every connection, including fallback remotes.
                    profile.mConnections.forEach {
                        it.mProxyType = Connection.ProxyType.SOCKS5
                        it.mProxyName = upstream.host
                        it.mProxyPort = upstream.port.toString()
                    }
                }
                config.optString("username", "").takeIf(String::isNotEmpty)?.let { profile.mUsername = it }
                config.optString("password", "").takeIf(String::isNotEmpty)?.let { profile.mPassword = it }
                profile.mName = "Mix OpenVPN ${environment.hopId}"
                synchronized(lifecycleLock) {
                if (stopped.get()) return@execute
                val uuid = profile.getUUIDString()
                val runtimeContext = OpenVpnMixService.RuntimeContext(environment.context, environment.sessionId, environment.hopId)
                val rt = OpenVpnMixService.Runtime(uuid, environment.sessionId, environment.listenPort, runtimeContext,
                    onReadyCallback = { udp -> main.post { if (!stopped.get()) environment.onReady(udp) } },
                    onFailureCallback = { message -> fail(message) })
                runtime = rt
                OpenVpnMixService.install(rt)
                // ProfileManager's temporary profile and VPNLaunchHelper's generated config are both private.
                ProfileManager.setTemporaryProfile(runtimeContext, profile)
                val intent = profile.prepareStartService(runtimeContext).apply {
                    component = android.content.ComponentName(environment.context,
                        Class.forName("com.forwin.vpn.mix.openvpn.OpenVpnMixService${environment.workerSlot}"))
                    putExtra(OpenVpnMixService.KEY_UUID, uuid)
                }
                serviceIntent = intent
                environment.context.startService(intent)
                }
            } catch (t: Throwable) { fail("OpenVPN Mix startup failed: ${t.message ?: t.javaClass.simpleName}") }
        }
    }

    override fun stop() {
        synchronized(lifecycleLock) {
        if (!stopped.compareAndSet(false, true)) return
        worker?.shutdownNow(); worker = null
        val rt = runtime
        rt?.stop()
        serviceIntent?.let { try { environment?.context?.stopService(it) } catch (_: Throwable) {} }
        if (rt?.awaitClosed(5, TimeUnit.SECONDS) == true) rt.cleanup()
        rt?.let { OpenVpnMixService.remove(it.uuid) }
        runtime = null; serviceIntent = null
        }
    }

    private fun fail(message: String) {
        if (stopped.get() || !failureReported.compareAndSet(false, true)) return
        // Service teardown needs the Android main looper: never await it there.
        Thread({
            stop()
            main.post { environment?.onFailure(message.take(512)) }
        }, "mix-openvpn-failure").apply { isDaemon = true; start() }
    }

    private data class Socks(val host: String, val port: Int)
    private fun parseSocks(value: String): Socks {
        val uri = URI(value)
        require(uri.scheme.equals("socks5", true) || uri.scheme.equals("socks5h", true)) { "upstream must be socks5:// or socks5h://" }
        require(!uri.host.isNullOrBlank() && uri.port in 1..65535) { "upstream SOCKS URL needs host and port" }
        return Socks(uri.host, uri.port)
    }

    /** Remove profile proxy directives only when Mix supplied the mandatory upstream. */
    private fun stripProxyOptions(raw: String, upstream: Socks?): String {
        if (upstream == null) return raw
        val filtered = raw.lineSequence().filterNot { line ->
            val token = line.substringBefore('#').trim().lowercase().split(Regex("\\s+"), limit = 2).firstOrNull()
            token == "http-proxy" || token == "http-proxy-option" || token == "socks-proxy"
        }.toMutableList()
        filtered += "socks-proxy ${upstream.host} ${upstream.port}"
        return filtered.joinToString("\n") + "\n"
    }
}
