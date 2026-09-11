package com.forwin.vpn

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log

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
class VpnApplication : Application() {
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
                        PsiphonVpnService.ACTION_STATUS ->
                            PsiphonStatusStore.onStatusBroadcast(intent)
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
