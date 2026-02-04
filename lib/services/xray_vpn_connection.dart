import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';

/// Xray VPN Connection Handler using flutter_v2ray
/// This provides real Xray/V2Ray core integration with traffic forwarding
class XrayVpnConnection {
  static late FlutterV2ray _v2ray;
  static bool _initialized = false;
  
  /// Initialize V2Ray with status callback
  static void initialize({void Function(V2RayStatus)? onStatusChanged}) {
    if (!_initialized) {
      _v2ray = FlutterV2ray(
        onStatusChanged: (V2RayStatus status) {
          if (onStatusChanged != null) {
            onStatusChanged(status);
          } else if (kDebugMode) {
            debugPrint('V2Ray Status: ${status.state}');
          }
        },
      );
      _initialized = true;
    }
  }
  
  /// Check if V2Ray core is running
  static Future<bool> isRunning() async {
    try {
      initialize();
      final version = await _v2ray.getCoreVersion();
      return version != null && version.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
  
  /// Request VPN permission
  static Future<bool> requestPermission() async {
    try {
      initialize();
      final hasPermission = await _v2ray.requestPermission();
      return hasPermission ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to request permission: $e');
      }
      return false;
    }
  }
  
  /// Connect to V2Ray/Xray server with config
  static Future<bool> connect({
    required String configContent,
    String? remark,
  }) async {
    try {
      initialize();
      
      // Request permission first
      final hasPermission = await requestPermission();
      if (!hasPermission) {
        if (kDebugMode) {
          debugPrint('❌ VPN permission denied');
        }
        return false;
      }
      
      // Start V2Ray core in VPN mode
      await _v2ray.startV2Ray(
        remark: remark ?? 'Xray Connection',
        config: configContent,
        proxyOnly: false, // VPN mode (not proxy only)
        notificationDisconnectButtonName: 'Disconnect',
      );
      
      if (kDebugMode) {
        debugPrint('✅ V2Ray started successfully');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to start V2Ray: $e');
      }
      return false;
    }
  }
  
  /// Disconnect from V2Ray/Xray
  static Future<bool> disconnect() async {
    try {
      if (!_initialized) return true;
      
      await _v2ray.stopV2Ray();
      
      if (kDebugMode) {
        debugPrint('✅ V2Ray stopped successfully');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to stop V2Ray: $e');
      }
      return false;
    }
  }
  
  /// Check if connected
  static Future<String?> getCoreVersion() async {
    try {
      initialize();
      final version = await _v2ray.getCoreVersion();
      return version;
    } catch (e) {
      return null;
    }
  }
  
  /// Convert XrayConfig to V2Ray JSON format
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
    
    // Complete V2Ray config
    final config = {
      "log": {
        "loglevel": "warning",
      },
      "inbounds": [
        {
          "tag": "socks-in",
          "port": 10808,
          "protocol": "socks",
          "settings": {
            "auth": "noauth",
            "udp": true,
            "userLevel": 8
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          }
        },
        {
          "tag": "http-in",
          "port": 10809,
          "protocol": "http",
          "settings": {
            "userLevel": 8
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
        "domainStrategy": "IPIfNonMatch",
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
          "8.8.8.8",
          "8.8.4.4"
        ]
      }
    };
    
    // Convert to JSON string - flutter_v2ray expects JSON string
    return _prettyJson(config);
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
        return {};
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
    final Map<String, dynamic> streamSettings = {
      "network": network,
    };
    
    // Network-specific settings
    switch (network) {
      case "ws":
        streamSettings["wsSettings"] = {
          "path": path ?? "/",
          if (host != null)
            "headers": {
              "Host": host
            }
        };
        break;
      
      case "grpc":
        streamSettings["grpcSettings"] = {
          "serviceName": path ?? "",
          "multiMode": false,
        };
        break;
      
      case "h2":
      case "http":
        streamSettings["httpSettings"] = {
          "path": path ?? "/",
          if (host != null) "host": [host]
        };
        break;
      
      case "tcp":
        if (headerType != null && headerType != "none") {
          streamSettings["tcpSettings"] = {
            "header": {
              "type": headerType
            }
          };
        }
        break;
    }
    
    // Security settings
    if (security == "tls") {
      streamSettings["security"] = "tls";
      streamSettings["tlsSettings"] = {
        if (sni != null) "serverName": sni,
        if (alpn != null && alpn.isNotEmpty) "alpn": alpn,
        if (fingerprint != null) "fingerprint": fingerprint,
        "allowInsecure": false,
      };
    } else if (security == "reality") {
      streamSettings["security"] = "reality";
      streamSettings["realitySettings"] = {
        if (sni != null) "serverName": sni,
        if (fingerprint != null) "fingerprint": fingerprint,
        if (publicKey != null) "publicKey": publicKey,
        if (shortId != null) "shortId": shortId,
        if (flow != null) "flow": flow,
      };
    }
    
    return streamSettings;
  }
  
  static String _prettyJson(Map<String, dynamic> json) {
    // Use built-in JSON encoder
    return json.toString()
        .replaceAll('{', '{\n  ')
        .replaceAll('}', '\n}')
        .replaceAll(',', ',\n  ');
  }
}
