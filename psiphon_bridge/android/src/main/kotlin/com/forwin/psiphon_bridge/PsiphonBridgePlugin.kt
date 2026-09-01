package com.forwin.psiphon_bridge

import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.forwin.vpn.PsiphonVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PsiphonBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.forwin.vpn/psiphon")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                val intent = VpnService.prepare(context)
                result.success(intent == null)
            }
            "start" -> {
                val intent = Intent().apply {
                    setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                    action = "com.forwin.vpn.psiphon.START"
                    putExtra("egressRegion", call.argument<String>("egressRegion") ?: "")
                }
                try {
                    ContextCompat.startForegroundService(context, intent)
                    result.success(true)
                } catch (t: Throwable) {
                    result.error("START_FAILED", t.message, null)
                }
            }
            "stop" -> {
                val intent = Intent().apply {
                    setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                    action = "com.forwin.vpn.psiphon.STOP"
                }
                context.startService(intent)
                result.success(true)
            }
            "reconnect" -> {
                val intent = Intent().apply {
                    setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                    action = "com.forwin.vpn.psiphon.RECONNECT"
                }
                context.startService(intent)
                result.success(true)
            }
            "isRunning" -> result.success(PsiphonVpnService.isRunning())
            "isConnected" -> result.success(PsiphonVpnService.isConnected())
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
