import 'package:flutter/services.dart';

/// Flutter bridge for the native Psiphon Android tunnel.
///
/// Psiphon owns its server discovery and tunnel lifecycle; Flutter only
/// selects the protocol, starts/stops the native foreground VPN service, and
/// receives lightweight state/traffic callbacks.
class PsiphonConnection {
  static const MethodChannel _channel = MethodChannel('com.forwin.vpn/psiphon');

  static bool _initialized = false;
  static bool _connected = false;
  static String? _region;
  static int _downloadBytes = 0;
  static int _uploadBytes = 0;

  static void Function(String state, String? message)? onStateChanged;
  static void Function(String region)? onRegionChanged;
  static void Function(int bytesIn, int bytesOut)? onByteCount;

  static bool get isConnected => _connected;
  static String? get region => _region;
  static int get downloadBytes => _downloadBytes;
  static int get uploadBytes => _uploadBytes;

  static Future<void> initialize() async {
    if (_initialized) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'state':
          final args = call.arguments;
          final state = args is Map ? (args['state'] ?? '').toString() : '';
          final message = args is Map ? args['message']?.toString() : null;
          _connected = state == 'connected';
          if (args is Map && args['region'] != null) {
            _region = args['region'].toString();
            onRegionChanged?.call(_region!);
          }
          onStateChanged?.call(state, message);
          break;
        case 'region':
          final region = call.arguments?.toString() ?? '';
          if (region.isNotEmpty) {
            _region = region;
            onRegionChanged?.call(region);
          }
          break;
        case 'bytes':
          final args = call.arguments;
          if (args is Map) {
            _downloadBytes = int.tryParse('${args['received'] ?? 0}') ?? 0;
            _uploadBytes = int.tryParse('${args['sent'] ?? 0}') ?? 0;
            onByteCount?.call(_downloadBytes, _uploadBytes);
          }
          break;
      }
      return null;
    });
    _initialized = true;
  }

  static Future<bool> connect() async {
    await initialize();
    try {
      final result = await _channel.invokeMethod<bool>('connect');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> disconnect() async {
    await initialize();
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {}
    _connected = false;
    _region = null;
  }

  static Future<bool> reconnect() async {
    await initialize();
    try {
      final result = await _channel.invokeMethod<bool>('reconnect');
      return result == true;
    } catch (_) {
      return false;
    }
  }
}
