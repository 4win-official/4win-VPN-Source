import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Xray VPN Connection Handler
/// Manages native Xray VPN service through MethodChannel
class XrayVpnConnection {
  static const MethodChannel _channel = MethodChannel('com.forwin.vpn/xray');
  
  /// Request VPN permission from Android
  static Future<bool> requestPermission() async {
    try {
      final bool? result = await _channel.invokeMethod('requestXrayPermission');
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to request Xray permission: $e');
      }
      return false;
    }
  }
  
  /// Connect to Xray server with config JSON
  static Future<bool> connect({
    required String configJson,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod('connectXray', {
        'configJson': configJson,
      });
      
      if (kDebugMode) {
        debugPrint('✅ Xray connection initiated: $result');
      }
      
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to connect Xray: $e');
      }
      return false;
    }
  }
  
  /// Disconnect from Xray server
  static Future<bool> disconnect() async {
    try {
      final bool? result = await _channel.invokeMethod('disconnectXray');
      
      if (kDebugMode) {
        debugPrint('✅ Xray disconnection initiated: $result');
      }
      
      return result ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to disconnect Xray: $e');
      }
      return false;
    }
  }
  
  /// Convert XrayConfig to V2Ray compatible JSON format
  static String generateConfigJson({
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
  }) {
    // Simplified V2Ray/Xray config format
    final config = {
      "log": {
        "loglevel": "warning"
      },
      "inbounds": [
        {
          "port": 10808,
          "protocol": "socks",
          "settings": {
            "auth": "noauth",
            "udp": true,
            "userLevel": 8
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls"]
          }
        }
      ],
      "outbounds": [
        {
          "protocol": protocol.toLowerCase(),
          "settings": _generateOutboundSettings(
            protocol: protocol,
            address: address,
            port: port,
            id: id,
          ),
          "streamSettings": _generateStreamSettings(
            network: network ?? "tcp",
            security: security ?? "none",
            path: path,
            host: host,
            sni: sni,
            fingerprint: fingerprint,
            publicKey: publicKey,
            shortId: shortId,
            alpn: alpn,
          )
        }
      ]
    };
    
    return config.toString();
  }
  
  static Map<String, dynamic> _generateOutboundSettings({
    required String protocol,
    required String address,
    required int port,
    required String id,
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
                  "encryption": "none",
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
                  "security": "auto",
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
      
      default:
        return {};
    }
  }
  
  static Map<String, dynamic> _generateStreamSettings({
    required String network,
    required String security,
    String? path,
    String? host,
    String? sni,
    String? fingerprint,
    String? publicKey,
    String? shortId,
    List<String>? alpn,
  }) {
    final streamSettings = <String, dynamic>{
      "network": network,
    };
    
    // Add network-specific settings
    if (network == "ws" && path != null) {
      streamSettings["wsSettings"] = {
        "path": path,
        if (host != null) "headers": {"Host": host}
      };
    } else if (network == "grpc" && path != null) {
      streamSettings["grpcSettings"] = {
        "serviceName": path,
      };
    }
    
    // Add security settings
    if (security == "tls" || security == "reality") {
      streamSettings["security"] = security;
      
      if (security == "tls") {
        streamSettings["tlsSettings"] = {
          if (sni != null) "serverName": sni,
          if (alpn != null) "alpn": alpn,
          if (fingerprint != null) "fingerprint": fingerprint,
        };
      } else if (security == "reality") {
        streamSettings["realitySettings"] = {
          if (sni != null) "serverName": sni,
          if (fingerprint != null) "fingerprint": fingerprint,
          if (publicKey != null) "publicKey": publicKey,
          if (shortId != null) "shortId": shortId,
        };
      }
    }
    
    return streamSettings;
  }
}
