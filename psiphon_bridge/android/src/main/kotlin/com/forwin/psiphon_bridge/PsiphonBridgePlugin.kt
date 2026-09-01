package com.forwin.psiphon_bridge

import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class PsiphonBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val TAG = "PsiphonBridgePlugin"

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.forwin.vpn/psiphon")
        channel.setMethodCallHandler(this)
        Log.d(TAG, "PsiphonBridgePlugin attached to engine")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "prepare" -> handlePrepare(result)
            "start" -> {
                val region = call.argument<String>("egressRegion") ?: ""
                handleStart(region, result)
            }
            "stop" -> handleStop(result)
            "reconnect" -> {
                val region = call.argument<String>("egressRegion") ?: ""
                handleReconnect(region, result)
            }
            "isRunning" -> handleIsRunning(result)
            "isConnected" -> handleIsConnected(result)
            "queryStats" -> handleQueryStats(result)
            else -> result.notImplemented()
        }
    }

    private fun handlePrepare(result: MethodChannel.Result) {
        try {
            val intent = VpnService.prepare(context)
            result.success(intent == null)
            Log.d(TAG, "prepare: ${intent == null}")
        } catch (e: Exception) {
            Log.e(TAG, "prepare failed: ${e.message}")
            result.error("PREPARE_FAILED", e.message, null)
        }
    }

    private fun handleStart(region: String, result: MethodChannel.Result) {
        try {
            val intent = Intent().apply {
                setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                action = "com.forwin.vpn.PSIPHON_CONNECT"
                putExtra("egress_region", region)
            }
            ContextCompat.startForegroundService(context, intent)
            result.success(true)
            Log.d(TAG, "start: region=$region")
        } catch (t: Throwable) {
            Log.e(TAG, "start failed: ${t.message}", t)
            result.error("START_FAILED", t.message, null)
        }
    }

    private fun handleStop(result: MethodChannel.Result) {
        try {
            val intent = Intent().apply {
                setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                action = "com.forwin.vpn.PSIPHON_DISCONNECT"
            }
            context.startService(intent)
            result.success(true)
            Log.d(TAG, "stop: called")
        } catch (t: Throwable) {
            Log.e(TAG, "stop failed: ${t.message}", t)
            result.error("STOP_FAILED", t.message, null)
        }
    }

    private fun handleReconnect(region: String, result: MethodChannel.Result) {
        try {
            val intent = Intent().apply {
                setClassName(context, "com.forwin.vpn.PsiphonVpnService")
                action = "com.forwin.vpn.PSIPHON_RECONNECT"
                putExtra("egress_region", region)
            }
            context.startService(intent)
            result.success(true)
            Log.d(TAG, "reconnect: region=$region")
        } catch (t: Throwable) {
            Log.e(TAG, "reconnect failed: ${t.message}", t)
            result.error("RECONNECT_FAILED", t.message, null)
        }
    }

    private fun handleIsRunning(result: MethodChannel.Result) {
        try {
            val clazz = Class.forName("com.forwin.vpn.PsiphonVpnService")
            val method = clazz.getMethod("isRunning")
            val response = method.invoke(null) as Boolean
            result.success(response)
            Log.d(TAG, "isRunning: $response")
        } catch (e: Exception) {
            Log.e(TAG, "isRunning failed: ${e.message}")
            result.success(false)
        }
    }

    private fun handleIsConnected(result: MethodChannel.Result) {
        try {
            val clazz = Class.forName("com.forwin.vpn.PsiphonVpnService")
            val method = clazz.getMethod("isConnected")
            val response = method.invoke(null) as Boolean
            result.success(response)
            Log.d(TAG, "isConnected: $response")
        } catch (e: Exception) {
            Log.e(TAG, "isConnected failed: ${e.message}")
            result.success(false)
        }
    }

    private fun handleQueryStats(result: MethodChannel.Result) {
        try {
            val clazz = Class.forName("com.forwin.vpn.PsiphonVpnService")
            val method = clazz.getMethod("queryTrafficStats")
            val stats = method.invoke(null) as LongArray
            val map = mapOf(
                "uplink" to stats[0],
                "downlink" to stats[1]
            )
            result.success(map)
            Log.d(TAG, "queryStats: up=${stats[0]} down=${stats[1]}")
        } catch (e: Exception) {
            Log.e(TAG, "queryStats failed: ${e.message}")
            result.success(mapOf("uplink" to 0L, "downlink" to 0L))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        Log.d(TAG, "PsiphonBridgePlugin detached from engine")
    }
}