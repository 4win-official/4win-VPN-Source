import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_vless/flutter_vless.dart';

/// Xray VPN Connection Handler using flutter_vless
/// Supports VLESS, VMESS, Trojan, Shadowsocks with real VPN tunnel
class XrayVpnConnection {
  static late FlutterVless _vless;
  static bool _initialized = false;
  
  /// Initialize flutter_vless with status callback
  static Future<void> initialize({void Function(VlessStatus)? onStatusChanged}) async {
    if (!_initialized) {
      _vless = FlutterVless(
        onStatusChanged: (VlessStatus status) {
          if (onStatusChanged != null) {
            onStatusChanged(status);
          }
          if (kDebugMode) {
            debugPrint('📊 Vless Status: ${status.state}');
            debugPrint('   Duration: ${status.duration}s');
            debugPrint('   Upload: ${status.upload} bytes');
            debugPrint('   Download: ${status.download} bytes');
          }
        },
      );
      
      // Initialize Vless
      await _vless.initializeVless(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      
      _initialized = true;
      
      if (kDebugMode) {
        final version = await _vless.getCoreVersion();
        debugPrint('✅ Flutter Vless initialized successfully');
        debugPrint('   Core version: $version');
      }
    }
  }
  
  /// Request VPN permission
  static Future<bool> requestPermission() async {
    try {
      await initialize();
      final hasPermission = await _vless.requestPermission();
      
      if (kDebugMode) {
        debugPrint(hasPermission 
            ? '✅ VPN permission granted' 
            : '❌ VPN permission denied');
      }
      
      return hasPermission;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to request permission: $e');
      }
      return false;
    }
  }
  
  /// Connect to VLESS/VMESS server with config
  static Future<bool> connect({
    required String configContent,
    String? remark,
  }) async {
    try {
      await initialize();
      
      if (kDebugMode) {
        debugPrint('🔧 Xray Config JSON (first 300 chars):');
        debugPrint(configContent.substring(0, configContent.length > 300 ? 300 : configContent.length));
      }
      
      // Request permission first
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        if (kDebugMode) {
          debugPrint('❌ VPN permission denied');
        }
        return false;
      }
      
      if (kDebugMode) {
        debugPrint('🚀 Starting Vless core in VPN MODE...');
        debugPrint('   Remark: ${remark ?? 'Xray Connection'}');
      }
      
      // Start Vless core in VPN mode (NOT proxy only)
      await _vless.startVless(
        remark: remark ?? 'Xray Connection',
        config: configContent,
        proxyOnly: false, // ✅ VPN mode - creates tunnel
        bypassSubnets: [], // Empty = route all traffic
        blockedApps: [], // Empty = all apps use VPN
        notificationDisconnectButtonName: 'Disconnect',
      );
      
      if (kDebugMode) {
        debugPrint('✅ Vless started successfully in VPN mode');
        debugPrint('🔍 Traffic should now be routing through VPN tunnel');
      }
      
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Failed to start Vless: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return false;
    }
  }
  
  /// Disconnect from VPN
  static Future<bool> disconnect() async {
    try {
      if (!_initialized) {
        return true;
      }
      
      if (kDebugMode) {
        debugPrint('🛑 Stopping Vless VPN...');
      }
      
      await _vless.stopVless();
      
      if (kDebugMode) {
        debugPrint('✅ Vless stopped successfully');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to stop Vless: $e');
      }
      return false;
    }
  }
  
  /// Get core version
  static Future<String?> getCoreVersion() async {
    try {
      await initialize();
      final version = await _vless.getCoreVersion();
      return version;
    } catch (e) {
      return null;
    }
  }
  
  /// Convert XrayConfig to V2Ray/Xray JSON format
  /// Supports VLESS, VMESS, Trojan, Shadowsocks
  static String generateV2RayConfig({
    required String protocol,
    required String address,
    required int port,
    required String id,
    String? flow,
    String? encryption,
    String? security,
    String? network,
    String? path,
    String? host,
    String? sni,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    List<String>? alpn,
    String? headerType,
  }) {
    // Build outbound configuration based on protocol
    final Map<String, dynamic> outbound = {
      "protocol": protocol.toLowerCase(),
      "settings": _buildOutboundSettings(
        protocol: protocol,
        address: address,
        port: port,
        id: id,
        encryption: encryption,
      ),
      "streamSettings": _buildStreamSettings(
        network: network ?? "tcp",
        security: security ?? "none",
        path: path,
        host: host,
        sni: sni,
        fingerprint: fingerprint,
        publicKey: publicKey,
        shortId: shortId,
        alpn: alpn,
        headerType: headerType,
        flow: flow,
      ),
    };
    
    // Add flow to outbound if present (for VLESS)
    if (flow != null && flow.isNotEmpty) {
      outbound["settings"]["vnext"][0]["users"][0]["flow"] = flow;
    }
    
    // Complete V2Ray config
    final config = {
      "log": {
        "loglevel": "warning",
      },
      "inbounds": [
        {
          "tag": "socks-in",
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "settings": {
            "auth": "noauth",
            "udp": true,
            "userLevel": 8
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic", "fakedns"],
            "routeOnly": false
          }
        }
      ],
      "outbounds": [
        outbound,
        {
          "protocol": "freedom",
          "tag": "direct"
        },
        {
          "protocol": "blackhole",
          "tag": "block"
        }
      ],
      "routing": {
        "domainStrategy": "AsIs",
        "rules": [
          {
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": "direct"
          }
        ]
      },
      "dns": {
        "servers": [
          "1.1.1.1",
          "8.8.8.8"
        ]
      }
    };
    
    // Convert to JSON string
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(config);
  }
  
  static Map<String, dynamic> _buildOutboundSettings({
    required String protocol,
    required String address,
    required int port,
    required String id,
    String? encryption,
  }) {
    switch (protocol.toLowerCase()) {
      case 'vless':
        return {
          "vnext": [
            {
              "address": address,
              "port": port,
              "users": [
                {
                  "id": id,
                  "encryption": encryption ?? "none",
                  "level": 8
                }
              ]
            }
          ]
        };
      
      case 'vmess':
        return {
          "vnext": [
            {
              "address": address,
              "port": port,
              "users": [
                {
                  "id": id,
                  "alterId": 0,
                  "security": encryption ?? "auto",
                  "level": 8
                }
              ]
            }
          ]
        };
      
      case 'trojan':
        return {
          "servers": [
            {
              "address": address,
              "port": port,
              "password": id,
              "level": 8
            }
          ]
        };
      
      case 'shadowsocks':
        return {
          "servers": [
            {
              "address": address,
              "port": port,
              "method": encryption ?? "aes-256-gcm",
              "password": id,
              "level": 8
            }
          ]
        };
      
      default:
        throw Exception('Unsupported protocol: $protocol');
    }
  }
  
  static Map<String, dynamic> _buildStreamSettings({
    required String network,
    required String security,
    String? path,
    String? host,
    String? sni,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    List<String>? alpn,
    String? headerType,
    String? flow,
  }) {
    final streamSettings = <String, dynamic>{
      "network": network,
      "security": security,
    };
    
    // Add network-specific settings
    switch (network.toLowerCase()) {
      case 'tcp':
        if (headerType != null && headerType.isNotEmpty) {
          streamSettings["tcpSettings"] = {
            "header": {
              "type": headerType,
            }
          };
        }
        break;
      
      case 'ws':
        streamSettings["wsSettings"] = {
          "path": path ?? "/",
          "headers": host != null ? {"Host": host} : {}
        };
        break;
      
      case 'grpc':
        streamSettings["grpcSettings"] = {
          "serviceName": path ?? "",
          "multiMode": false
        };
        break;
      
      case 'h2':
      case 'http':
        streamSettings["httpSettings"] = {
          "path": path ?? "/",
          "host": host != null ? [host] : []
        };
        break;
    }
    
    // Add security settings
    if (security == 'tls') {
      streamSettings["tlsSettings"] = {
        "serverName": sni ?? host,
        "allowInsecure": false,
        "fingerprint": fingerprint ?? "chrome",
      };
      
      if (alpn != null && alpn.isNotEmpty) {
        streamSettings["tlsSettings"]["alpn"] = alpn;
      }
    } else if (security == 'reality') {
      streamSettings["realitySettings"] = {
        "serverName": sni ?? host,
        "fingerprint": fingerprint ?? "chrome",
        "show": false,
        "publicKey": publicKey ?? "",
        "shortId": shortId ?? "",
      };
      
      if (alpn != null && alpn.isNotEmpty) {
        streamSettings["realitySettings"]["alpn"] = alpn;
      }
    }
    
    return streamSettings;
  }
}
