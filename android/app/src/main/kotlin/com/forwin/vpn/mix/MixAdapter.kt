package com.forwin.vpn.mix

import android.content.Context
import org.json.JSONObject

/** One engine instance in a dedicated Mix worker process. Never owns Android's TUN. */
interface MixAdapter {
    /** Asynchronous. Report ready only after the real tunnel and SOCKS listener work. */
    fun start(config: JSONObject, environment: MixAdapterEnvironment)
    /** Must close all listeners, control connections, packet I/O and background tasks. */
    fun stop()
}

data class MixAdapterEnvironment(
    val context: Context,
    val sessionId: String,
    val hopId: String,
    val listenPort: Int,
    /** null only on the first hop. A non-null upstream MUST NOT fall back to direct. */
    val upstreamSocksUrl: String?,
    val onReady: (supportsUdp: Boolean) -> Unit,
    val onFailure: (String) -> Unit,
    val workerSlot: Int = 0,
    /** Coordinator metadata, never part of any native engine's config schema. */
    val upstreamSupportsUdp: Boolean = true,
)
