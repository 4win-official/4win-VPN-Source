package com.forwin.vpn

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val DNS_CHANNEL = "com.forwin.vpn/dns"
    private val VPN_REQUEST_CODE = 100
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DNS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestDnsPermission" -> {
                    val intent = VpnService.prepare(applicationContext)
                    if (intent != null) {
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                        result.success(false) // Will be granted after user approval
                    } else {
                        result.success(true) // Already granted
                    }
                }
                "connectDns" -> {
                    val primaryDns = call.argument<String>("primaryDns") ?: "8.8.8.8"
                    val secondaryDns = call.argument<String>("secondaryDns") ?: "8.8.4.4"
                    
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_CONNECT
                        putExtra(DnsVpnService.EXTRA_DNS_PRIMARY, primaryDns)
                        putExtra(DnsVpnService.EXTRA_DNS_SECONDARY, secondaryDns)
                    }
                    startService(intent)
                    result.success(true)
                }
                "disconnectDns" -> {
                    val intent = Intent(this, DnsVpnService::class.java).apply {
                        action = DnsVpnService.ACTION_DISCONNECT
                    }
                    startService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
