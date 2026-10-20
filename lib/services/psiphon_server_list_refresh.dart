import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional Android maintenance; never make any protocol await a list download.
class PsiphonServerListRefresh {
  static const _channel = MethodChannel('com.forwin.vpn/psiphon');

  static void request() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    unawaited(_schedule());
  }

  static Future<void> _schedule() async {
    try {
      await _channel.invokeMethod<void>('refreshServerList');
    } catch (_) {
      // Missing native implementation or refresh scheduling failure is non-fatal.
    }
  }
}
