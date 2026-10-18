package com.forwin.vpn

import org.json.JSONObject

/** JNI bridge to the Aether WARP core. The core owns registration, endpoint
 * validation, WireGuard framing and the userspace data plane. */
object NativeCore {
    init {
        System.loadLibrary("aether")
        System.loadLibrary("aether_jni")
    }

    data class TunnelAddresses(val ipv4: String, val ipv6: String)

    fun prepare(config: String): TunnelAddresses {
        check(nativePrepare(config) == 0) { nativeLastError() }
        val result = JSONObject(nativeLastResult())
        return TunnelAddresses(result.optString("ipv4"), result.optString("ipv6"))
    }

    fun start(config: String, tunFd: Int): Int = nativeStart(config, tunFd)
    /** Starts the userspace proxy path without manufacturing a TUN fd of -1. */
    fun startProxy(config: String): Int = nativeStartProxy(config)
    fun stop(): Int = nativeStop()
    fun isRunning(): Boolean = nativeIsRunning()
    fun isReady(): Boolean = nativeIsReady()
    fun lastRttMs(): Long = nativeLastRttMs()
    fun lastError(): String = nativeLastError()
    fun lastLog(): String = nativeLastLog()
    fun attach(service: XrayVpnService) = nativeAttach(service)
    fun detach() = nativeDetach()

    @JvmStatic private external fun nativePrepare(config: String): Int
    @JvmStatic private external fun nativeLastResult(): String
    @JvmStatic private external fun nativeStart(config: String, tunFd: Int): Int
    @JvmStatic private external fun nativeStartProxy(config: String): Int
    @JvmStatic private external fun nativeStop(): Int
    @JvmStatic private external fun nativeIsRunning(): Boolean
    @JvmStatic private external fun nativeIsReady(): Boolean
    @JvmStatic private external fun nativeLastRttMs(): Long
    @JvmStatic private external fun nativeLastError(): String
    @JvmStatic private external fun nativeLastLog(): String
    @JvmStatic private external fun nativeAttach(service: XrayVpnService)
    @JvmStatic private external fun nativeDetach()
}
