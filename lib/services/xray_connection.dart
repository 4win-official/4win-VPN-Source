import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper over the native Xray MethodChannel (`com.forwin.vpn/xray`).
/// Bridges to [XrayVpnService] which runs the real Xray core (libv2ray).
class XrayConnection {
  static const platform = MethodChannel('com.forwin.vpn/xray');

  /// Request the system VPN permission. Returns true if already granted.
  static Future<bool> requestPermission() async {
    try {
      final result = await platform.invokeMethod('requestXrayPermission');
      return result == true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Xray permission error: $e');
      return false;
    }
  }

  /// Start the Xray core with a full Xray JSON config.
  static Future<bool> connect(String configJson) async {
    try {
      final result = await platform.invokeMethod('connectXray', {
        'configJson': configJson,
      });
      return result == true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Xray connect error: $e');
      return false;
    }
  }

  /// Stop the Xray core.
  static Future<bool> disconnect() async {
    try {
      final result = await platform.invokeMethod('disconnectXray');
      return result == true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Xray disconnect error: $e');
      return false;
    }
  }

  /// Whether the Xray service is currently running (best-effort).
  static Future<bool> isRunning() async {
    try {
      final result = await platform.invokeMethod('isXrayRunning');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Returns the bundled Xray core version string.
  static Future<String> version() async {
    try {
      final result = await platform.invokeMethod('getXrayVersion');
      return result?.toString() ?? 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }
}
