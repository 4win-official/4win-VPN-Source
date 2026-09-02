package com.forwin.vpn

import android.content.Context
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bridges Android's VpnService TUN fd to Psiphon's localhost SOCKS5 listener.
 * Psiphon Tunnel Core is a proxy core; setVpnMode(true) does not itself consume
 * an Android TUN fd. Xray's TUN inbound is used as the packet-to-SOCKS bridge.
 */
object PsiphonTunBridge {
    private const val TAG = "PsiphonTunBridge"
    private const val MTU = 1500
    private var controller: CoreController? = null

    @Synchronized
    fun start(context: Context, tunFd: Int, socksPort: Int) {
        stop()

        Seq.setContext(context.applicationContext)
        Libv2ray.initCoreEnv(context.filesDir.absolutePath, "")

        val config = buildConfig(socksPort)
        val next = Libv2ray.newCoreController(object : CoreCallbackHandler {
            override fun startup(): Long = 0L
            override fun shutdown(): Long = 0L
            override fun onEmitStatus(level: Long, msg: String?): Long {
                android.util.Log.d(TAG, "bridge status[$level]: $msg")
                return 0L
            }
        })

        controller = next
        try {
            next.startLoop(config, tunFd)
        } catch (t: Throwable) {
            controller = null
            try { next.stopLoop() } catch (_: Throwable) {}
            throw t
        }
        android.util.Log.d(TAG, "TUN -> Psiphon SOCKS bridge started on 127.0.0.1:$socksPort")
    }

    @Synchronized
    fun stop() {
        val c = controller ?: return
        controller = null
        try { c.stopLoop() } catch (t: Throwable) {
            android.util.Log.w(TAG, "bridge stop failed: ${t.message}")
        }
    }

    private fun buildConfig(socksPort: Int): String {
        val socksServer = JSONObject()
            .put("address", "127.0.0.1")
            .put("port", socksPort)

        val socksSettings = JSONObject()
            .put("servers", JSONArray().put(socksServer))

        val proxy = JSONObject()
            .put("protocol", "socks")
            .put("settings", socksSettings)
            .put("tag", "psiphon")

        val direct = JSONObject()
            .put("protocol", "freedom")
            .put("settings", JSONObject())
            .put("tag", "direct")

        // Xray's Android TUN integration requires an explicit tun inbound.
        // startLoop() supplies the Android VpnService fd through xray.tun.fd.
        val tunInbound = JSONObject()
            .put("tag", "tun")
            .put("port", 0)
            .put("protocol", "tun")
            .put("settings", JSONObject()
                .put("name", "xray0")
                .put("MTU", MTU)
                .put("userLevel", 8))
            .put("sniffing", JSONObject()
                .put("enabled", true)
                .put("destOverride", JSONArray().put("http").put("tls").put("quic")))

        val routingRule = JSONObject()
            .put("type", "field")
            .put("network", "tcp,udp")
            .put("outboundTag", "psiphon")

        return JSONObject()
            .put("log", JSONObject().put("loglevel", "none"))
            .put("inbounds", JSONArray().put(tunInbound))
            .put("outbounds", JSONArray().put(proxy).put(direct))
            .put("routing", JSONObject()
                .put("domainStrategy", "AsIs")
                .put("rules", JSONArray().put(routingRule)))
            .toString()
    }
}
