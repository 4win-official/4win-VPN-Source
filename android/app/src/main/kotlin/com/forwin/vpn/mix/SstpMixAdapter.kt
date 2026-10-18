package com.forwin.vpn.mix

import com.forwin.vpn.mix.sstp.client.ClientBridge
import com.forwin.vpn.mix.sstp.client.control.ControlClient
import com.forwin.vpn.mix.sstp.service.SstpVpnService
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean
import java.net.URI
import com.forwin.vpn.mix.sstp.preference.OscPrefKey

/** SSTP adapter backed by the vendored PPP/SSTP engine. */
class SstpMixAdapter : MixAdapter {
    @Volatile private var service: SstpVpnService? = null
    @Volatile private var client: ControlClient? = null
    @Volatile private var bridge: ClientBridge? = null
    private val stopped = AtomicBoolean(true)

    override fun start(config: JSONObject, environment: MixAdapterEnvironment) {
        stop()
        stopped.set(false)
        val host = config.optString("host", "").trim()
        if (host.isBlank() || host.any { it.isWhitespace() }) {
            stopped.set(true)
            environment.onFailure("SSTP host is invalid")
            return
        }
        val port = config.optInt("port", 443).takeIf { it in 1..65535 } ?: run {
            stopped.set(true)
            environment.onFailure("SSTP port is invalid")
            return
        }
        val mtu = config.optInt("mtu", 1500).coerceIn(576, 65535)
        try {
            val s = SstpVpnService(
                environment.context, host, config.optString("username", ""),
                config.optString("password", ""), port, mtu, environment.listenPort
            ) { message -> if (!stopped.get()) environment.onFailure(message) }
            service = s
            val settings = s.prefs.edit()
                .putBoolean(OscPrefKey.SSL_DO_VERIFY_CERT.name, config.optBoolean("verifyCertificate", true))
                .putBoolean(OscPrefKey.SSL_DO_VERIFY.name, config.optBoolean("verifyCertificate", true))
            val upstream = environment.upstreamSocksUrl
            if (upstream != null) {
                val proxy = URI(upstream)
                require(proxy.scheme in setOf("socks5", "socks5h") &&
                    proxy.host == "127.0.0.1" && proxy.port in 1..65535 && proxy.userInfo == null) {
                    "Invalid SSTP Mix upstream SOCKS endpoint"
                }
                settings.putBoolean(OscPrefKey.PROXY_DO_USE_PROXY.name, true)
                    .putString(OscPrefKey.PROXY_HOSTNAME.name, proxy.host)
                    .putString(OscPrefKey.PROXY_PORT.name, proxy.port.toString())
            } else settings.putBoolean(OscPrefKey.PROXY_DO_USE_PROXY.name, false)
            settings.apply()
            val b = ClientBridge(s)
            bridge = b
            val c = ControlClient(b)
            client = c
            c.launchJobMain()
            s.scope.launch {
                try {
                    while (!stopped.get() && s.packetStack == null) delay(25)
                    while (!stopped.get() && s.packetStack?.ready != true) {
                        delay(25)
                    }
                    if (!stopped.get() && s.packetStack?.ready == true && s.packetPeer != null) {
                        environment.onReady(true)
                        while (!stopped.get()) {
                            delay(500)
                            if (s.packetStack?.ready != true) {
                                environment.onFailure(s.packetStack?.error?.takeIf { it.isNotBlank() }
                                    ?: "SSTP packet bridge stopped")
                                break
                            }
                        }
                    } else if (!stopped.get()) {
                        environment.onFailure(s.packetStack?.error?.takeIf { it.isNotBlank() } ?: "SSTP engine stopped before IPCP/TUN readiness")
                    }
                } catch (t: Throwable) {
                    if (!stopped.get()) environment.onFailure(t.message ?: "SSTP failure")
                }
            }
        } catch (t: Throwable) {
            stop()
            environment.onFailure(t.message ?: "SSTP startup failed")
        }
    }

    override fun stop() {
        if (!stopped.compareAndSet(false, true)) return
        runCatching { client?.kill(false, null) }
        client = null
        runCatching { bridge?.sslTerminal?.close() }
        runCatching { bridge?.ipTerminal?.close() }
        bridge = null
        service?.close()
        service = null
    }
}
