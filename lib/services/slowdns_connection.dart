import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/slowdns_config.dart';

/// Standalone authenticated dnstt tunnel. Never participates in Mix.
class SlowDnsConnection {
  static const platform = MethodChannel('com.forwin.vpn/slowdns');
  static bool _connected = false;
  static SlowDnsConfig? _activeConfig;
  static String? _activeResolver;
  static String? _lastError;
  static Timer? _monitor;
  static bool _polling = false;
  static int _generation = 0;

  static void Function(bool connected, String message)? onStateChanged;
  static bool get isConnected => _connected;
  static SlowDnsConfig? get activeConfig => _activeConfig;
  static String? get activeResolver => _activeResolver;
  static String? get lastError => _lastError;

  static Future<bool> requestPermission() async {
    _lastError = null;
    try {
      return await platform.invokeMethod<bool>('requestPermission') == true;
    } on MissingPluginException {
      _lastError = 'Slow DNS is only available in supported Android builds.';
    } on PlatformException catch (error) {
      _lastError = error.message ?? 'Unable to request VPN permission.';
    }
    return false;
  }

  /// Only the native service can report ready: a listening local socket or a
  /// responsive DNS resolver is not an authenticated tunnel.
  static Future<bool> connect(SlowDnsConfig config) async {
    final generation = ++_generation;
    _monitor?.cancel();
    _monitor = null;
    _connected = false;
    _activeConfig = null;
    _activeResolver = null;
    _lastError = config.validationError;
    if (_lastError != null) {
      onStateChanged?.call(false, _lastError!);
      return false;
    }
    try {
      final response = await platform.invokeMapMethod<String, dynamic>(
        'connect',
        {'configJson': jsonEncode(config.toJson())},
      );
      if (generation != _generation) return false;
      if (response?['ready'] != true || response?['connected'] != true) {
        throw StateError(
          response?['error'] as String? ??
              'No resolver established an authenticated Slow DNS tunnel.',
        );
      }
      _connected = true;
      _activeConfig = config;
      _activeResolver = response?['resolver'] as String?;
      _lastError = null;
      onStateChanged?.call(true, 'Connected via $_activeResolver');
      _monitor = Timer.periodic(const Duration(seconds: 2), (_) {
        _poll(generation);
      });
      return true;
    } on MissingPluginException {
      if (generation != _generation) return false;
      _lastError = 'This Android build does not include the Slow DNS engine.';
    } on PlatformException catch (error) {
      if (generation != _generation) return false;
      _lastError = error.message ?? 'Slow DNS connection failed.';
    } catch (error) {
      if (generation != _generation) return false;
      _lastError = 'Slow DNS connection failed: $error';
    }
    _connected = false;
    _activeConfig = null;
    _activeResolver = null;
    onStateChanged?.call(false, _lastError!);
    return false;
  }

  static Future<void> _poll(int generation) async {
    if (_polling || generation != _generation) return;
    _polling = true;
    try {
      final state = await platform.invokeMapMethod<String, dynamic>('status');
      if (generation != _generation) return;
      if (state?['ready'] != true || state?['connected'] != true) {
        _monitor?.cancel();
        _monitor = null;
        _connected = false;
        _activeConfig = null;
        _activeResolver = null;
        _lastError = state?['error'] as String? ?? 'Slow DNS tunnel stopped.';
        onStateChanged?.call(false, _lastError!);
      }
    } catch (_) {
      if (generation != _generation) return;
      _monitor?.cancel();
      _monitor = null;
      _connected = false;
      _activeConfig = null;
      _activeResolver = null;
      _lastError = 'Unable to verify the Slow DNS tunnel state.';
      onStateChanged?.call(false, _lastError!);
    } finally {
      _polling = false;
    }
  }

  static Future<bool> disconnect() async {
    ++_generation;
    _monitor?.cancel();
    _monitor = null;
    _connected = false;
    _activeConfig = null;
    _activeResolver = null;
    _lastError = null;
    try {
      await platform.invokeMethod<void>('disconnect');
      onStateChanged?.call(false, 'Disconnected');
      return true;
    } catch (_) {
      _lastError = 'Unable to stop the native Slow DNS service.';
      onStateChanged?.call(false, _lastError!);
      return false;
    }
  }

  /// Detach UI listeners without silently disconnecting a background VPN.
  static void detach() {
    ++_generation;
    _monitor?.cancel();
    _monitor = null;
    onStateChanged = null;
  }
}
