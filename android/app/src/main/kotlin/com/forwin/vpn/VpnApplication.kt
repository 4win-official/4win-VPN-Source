package com.forwin.vpn

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.sstp_flutter.VpnConnectionObserver

/**
 * Custom Application that bridges Psiphon state across processes.
 *
 * [PsiphonVpnService] runs in the `:psiphon` process (NOT the main process) so
 * its gomobile/Go runtime never shares a process with Xray's Go runtime in the
 * main process — loading both in one process natively crashes the app.
 *
 * Because Android process statics are not shared, the `:psiphon` process
 * publishes state + logs via package-scoped broadcasts, and this receiver
 * (registered for the lifetime of every process, but only *read* from the main
 * one) feeds them into [PsiphonStatusStore], which MainActivity's MethodChannel
 * handlers read synchronously.
 */
class VpnApplication : Application(), VpnConnectionObserver {
    private fun protocolFor(source: Context): String? = when (source.javaClass.simpleName) {
        "DnsVpnService" -> "direct_dns"
        "SlowDnsVpnService" -> "slowdns"
        // WARP, Proxy and Xray-based Mix share these same native transports.
        // Key metadata by the owning service, never the UI's selected alias.
        "XrayVpnService" -> "xray"
        "XrayProxyService" -> "proxy"
        "MixCoordinatorService" -> "mix"
        "OpenVPNService" -> "openvpn"
        "PsiphonVpnService" -> "psiphon"
        else -> null
    }

    private val connectedRefresh by lazy {
        val handler = Handler(Looper.getMainLooper())
        PsiphonConnectedRefresh(
            schedule = { delay, action ->
                val task = Runnable { action() }
                handler.postDelayed(task, delay)
                PsiphonConnectedRefresh.Cancellation { handler.removeCallbacks(task) }
            },
            refresh = { PsiphonServerList.refreshInBackground(this) },
        )
    }

    override fun onVpnConnectionStarting(source: Context) {
        // A native start/reconnect is a new session, but recreating an Activity
        // never calls this hook. End immediately so a fast disconnect/connect
        // cannot accidentally inherit the previous session's elapsed time.
        protocolFor(source)?.let { NativeSessionMetrics.end(it) }
        connectedRefresh.starting(source)
    }

    override fun onVpnConnectionStateChanged(source: Context, connected: Boolean) {
        protocolFor(source)?.let { protocol ->
            if (connected) NativeSessionMetrics.begin(protocol)
            else NativeSessionMetrics.end(protocol)
        }
        connectedRefresh.stateChanged(source, connected)
    }

    override fun onCreate() {
        super.onCreate()
        val filter = IntentFilter().apply {
            addAction(PsiphonVpnService.ACTION_STATUS)
            addAction(PsiphonVpnService.ACTION_LOG)
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                try {
                    when (intent.action) {
                        PsiphonVpnService.ACTION_STATUS -> {
                            PsiphonStatusStore.onStatusBroadcast(intent)
                            val id = PsiphonStatusStore.sessionId()
                            val started = PsiphonStatusStore.sessionStartedAtElapsed()
                            if (PsiphonStatusStore.isRunning() && !id.isNullOrBlank() && started > 0L)
                                NativeSessionMetrics.adopt("psiphon", id, started)
                            else if (!PsiphonStatusStore.isRunning()) NativeSessionMetrics.end("psiphon", id)
                        }
                        PsiphonVpnService.ACTION_LOG -> {
                            val lines = intent.getStringArrayListExtra(
                                PsiphonVpnService.EXTRA_LOG_LINES
                            )
                            if (lines != null) PsiphonStatusStore.appendLogs(lines)
                        }
                    }
                } catch (t: Throwable) {
                    Log.w(TAG, "psiphon broadcast handling failed: ${t.message}")
                }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(receiver, filter)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "failed to register psiphon status receiver", t)
        }
    }

    companion object {
        private const val TAG = "VpnApplication"
    }
}
