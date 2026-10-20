import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper over the native Xray MethodChannel (`com.forwin.vpn/xray`).
/// Bridges to [XrayVpnService] which runs the real Xray core (libv2ray).
class XrayConnection {
  static const platform = MethodChannel('com.forwin.vpn/xray');

  static Future<int> connectMixPlan(Map<String, dynamic> plan) async {
    try {
      final result = await platform.invokeMethod('connectMixPlan', {
        'planJson': jsonEncode(plan),
      });
      if (result is int) return result;
      if (result is num) return result.toInt();
      throw StateError(
        'The native Mix coordinator returned an invalid response.',
      );
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'The complete Mix chain failed.');
    } on MissingPluginException {
      throw StateError('This app build does not include the Mix coordinator.');
    }
  }

  /// Optional diagnostics: lack of support never changes connection behavior.
  static Future<Map<dynamic, dynamic>?> getMixDiagnostics() async {
    try {
      return await platform
          .invokeMapMethod<dynamic, dynamic>('getMixDiagnostics')
          .timeout(const Duration(milliseconds: 750));
    } catch (_) {
      return null;
    }
  }

  static Future<void> disconnectMixPlan() async {
    try {
      await platform.invokeMethod('disconnectMixPlan');
    } catch (_) {
      // Optional on older native builds and test method-channel mocks.
    }
  }

  /// Separate entry point: always a system-wide tunnel, never proxy-only or
  /// the standalone split-tunnel preference. Existing connect() is unchanged.
  static Future<bool> connectMix(String configJson) async {
    try {
      return await platform.invokeMethod('connectMix', {
            'configJson': configJson,
          }) ==
          true;
    } catch (_) {
      return false;
    }
  }

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
  ///
  /// When [proxyMode] is true the native service runs the core WITHOUT a system
  /// VpnService tunnel — it only serves a local SOCKS/HTTP proxy on
  /// 127.0.0.1:4444, so no VPN key icon appears.
  static Future<bool> connect(
    String configJson, {
    bool proxyMode = false,
    bool propagateErrors = false,
  }) async {
    try {
      final result = await platform.invokeMethod('connectXray', {
        'configJson': configJson,
        'proxyMode': proxyMode,
      });
      return result == true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Xray connect error: $e');
      if (propagateErrors) rethrow;
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

  /// Whether native Xray/Mix is intentionally rebuilding after a transient
  /// loss. A false isRunning during this window is not a terminal stop.
  static Future<bool> isReconnecting() async {
    try {
      final result = await platform.invokeMethod('isXrayReconnecting');
      return result == true;
    } catch (_) {
      // Preserve compatibility with older native builds.
      return false;
    }
  }

  /// Real delay test (v2rayNG style). Measures the latency of an actual HTTP
  /// request routed through the proxy described by [configJson] (a proxy-only
  /// config built by XrayConfigBuilder.buildForDelayTest). Returns latency in
  /// ms, or -1 if the config does not work / times out.
  static Future<int> measureDelay(
    String configJson, {
    String url = 'https://www.google.com/generate_204',
  }) async {
    try {
      final result = await platform.invokeMethod('measureDelay', {
        'configJson': configJson,
        'url': url,
      });
      if (result is int) return result;
      if (result is num) return result.toInt();
      return -1;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Xray measureDelay error: $e');
      return -1;
    }
  }

  /// Fresh complete-chain delay for the running Mix session. Native code owns
  /// the resolved chain; never reload/select servers or fall back to direct HTTP.
  static Future<int> measureMixDelay() async {
    try {
      final result = await platform.invokeMethod('measureMixDelay');
      return result is num ? result.toInt() : -1;
    } catch (_) {
      return -1;
    }
  }

  /// Reads the RTT recorded by the already-running native WARP tunnel.
  /// This never starts or probes a second core when the indicator is tapped.
  static Future<int> measureWarpDelay() async {
    try {
      final result = await platform.invokeMethod('measureWarpDelay');
      if (result is int) return result;
      if (result is num) return result.toInt();
      return -1;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ WARP measureDelay error: $e');
      return -1;
    }
  }

  /// Cumulative outbound traffic since connect: {'uplink': bytes, 'downlink': bytes}.
  /// Polled while connected to display data usage on the home screen.
  static Future<Map<String, int>> queryStats() async {
    try {
      final result = await platform.invokeMethod('queryXrayStats');
      if (result is Map) {
        final up = result['uplink'];
        final down = result['downlink'];
        return {
          'uplink': up is int ? up : (up is num ? up.toInt() : 0),
          'downlink': down is int ? down : (down is num ? down.toInt() : 0),
        };
      }
      return {'uplink': 0, 'downlink': 0};
    } catch (e) {
      return {'uplink': 0, 'downlink': 0};
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
