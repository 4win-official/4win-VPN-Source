package com.forwin.psiphon_bridge

import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
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
                handlePrepare(result)
            }
            "start" -> {
                val egressRegion = call.argument<String>("egressRegion") ?: ""
                handleStart(egressRegion, result)
            }
            "stop" -> {
                handleStop(result)
            }
            "reconnect" -> {
                val egressRegion = call.argument<String>("egressRegion") ?: ""
                handleReconnect(egressRegion, result)
            }
            "isRunning" -> {
                handleIsRunning(result)
            }
            "isConnected" -> {
                handleIsConnected(result)
            }
            else -> result.notImplemented()
        }
    }

    private fun handlePrepare(result: MethodChannel.Result) {
        try {
            val intent = VpnService.prepare(context)
            result.success(intent == null)
        } catch (e: Exception) {
            result.error("PREPARE_FAILED", e.message, null)
        }
    }

    private fun handleStart(egressRegion: String, result: MethodChannel.Result) {
        try {
            val intent = Intent().apply {
                setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                action = "com.forwin.vpn.psiphon.START"
                putExtra("egressRegion", egressRegion)
            }
            ContextCompat.startForegroundService(context, intent)
            result.success(true)
        } catch (t: Throwable) {
            result.error("START_FAILED", t.message, null)
        }
    }

    private fun handleStop(result: MethodChannel.Result) {
        try {
            val intent = Intent().apply {
                setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                action = "com.forwin.vpn.psiphon.STOP"
            }
            context.startService(intent)
            result.success(true)
        } catch (t: Throwable) {
            result.error("STOP_FAILED", t.message, null)
        }
    }

    private fun handleReconnect(egressRegion: String, result: MethodChannel.Result) {
        try {
            val intent = Intent().apply {
                setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                action = "com.forwin.vpn.psiphon.RECONNECT"
                putExtra("egressRegion", egressRegion)
            }
            context.startService(intent)
            result.success(true)
        } catch (t: Throwable) {
            result.error("RECONNECT_FAILED", t.message, null)
        }
    }

    private fun handleIsRunning(result: MethodChannel.Result) {
        try {
            val clazz = Class.forName("com.forwin.vpn.PsiphonVpnService")
            val method = clazz.getMethod("isRunning")
            val response = method.invoke(null) as Boolean
            result.success(response)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleIsConnected(result: MethodChannel.Result) {
        try {
            val clazz = Class.forName("com.forwin.vpn.PsiphonVpnService")
            val method = clazz.getMethod("isConnected")
            val response = method.invoke(null) as Boolean
            result.success(response)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}