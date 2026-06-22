import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A single pending `.ovpn` file that the user opened or shared into the app
/// (via Telegram, a file manager, email, ...).
class PendingOvpnImport {
  final String name;
  final String content;

  const PendingOvpnImport({required this.name, required this.content});
}

/// Bridges the native `com.forwin.vpn/import` MethodChannel that captures
/// incoming `.ovpn` VIEW / SEND intents.
///
/// Usage:
///  * Call [checkPending] after the app's first frame to handle a cold start
///    (the app was launched by tapping an .ovpn file).
///  * Set [onImportAvailable]; the native side calls back when a new file is
///    opened while the app is already running (warm start / onNewIntent).
class OvpnImportService {
  OvpnImportService._();
  static final OvpnImportService instance = OvpnImportService._();

  static const MethodChannel _channel = MethodChannel('com.forwin.vpn/import');

  /// Invoked when a new .ovpn becomes available while the app is running.
  void Function()? onImportAvailable;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOvpnImportAvailable') {
        onImportAvailable?.call();
      }
      return null;
    });
  }

  /// Pulls the pending .ovpn (if any) from the native side. Returns null when
  /// there is nothing to import. The native side clears it once returned, so a
  /// file is never imported twice.
  Future<PendingOvpnImport?> checkPending() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getPendingOvpnImport',
      );
      if (res == null) return null;
      final content = (res['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) return null;
      return PendingOvpnImport(
        name: (res['name'] as String?)?.trim().isNotEmpty == true
            ? res['name'] as String
            : 'Imported',
        content: content,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('OvpnImportService.checkPending error: $e');
      return null;
    }
  }
}
