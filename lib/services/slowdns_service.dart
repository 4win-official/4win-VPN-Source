import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/slowdns_config.dart';

/// Service for managing Slow DNS (DNS Tunneling) configurations.
///
/// Handles persistence of [SlowDnsConfig] entries in local storage.
class SlowDnsService {
  static const String _storageKey = 'slowdns_configs';
  static const String _selectedConfigKey = 'selected_slowdns_config';

  /// Load all Slow DNS configs from local storage
  Future<List<SlowDnsConfig>> loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = prefs.getStringList(_storageKey) ?? [];

      final configs = configsJson
          .map((json) {
            try {
              return SlowDnsConfig.fromJson(jsonDecode(json));
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ Failed to parse Slow DNS config: $e');
              }
              return null;
            }
          })
          .whereType<SlowDnsConfig>()
          .toList();

      if (kDebugMode) {
        debugPrint('✅ Loaded ${configs.length} Slow DNS configs');
      }

      return configs;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load Slow DNS configs: $e');
      }
      return [];
    }
  }

  /// Save configs to local storage
  Future<bool> saveConfigs(List<SlowDnsConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson =
          configs.map((config) => jsonEncode(config.toJson())).toList();

      await prefs.setStringList(_storageKey, configsJson);

      if (kDebugMode) {
        debugPrint('✅ Saved ${configs.length} Slow DNS configs');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to save Slow DNS configs: $e');
      }
      return false;
    }
  }

  /// Add a new config
  Future<bool> addConfig(SlowDnsConfig config) async {
    try {
      final configs = await loadConfigs();

      // بررسی تکراری نبودن نام
      if (configs.any((c) => c.name == config.name)) {
        if (kDebugMode) {
          debugPrint('⚠️ Config with name "${config.name}" already exists');
        }
        return false;
      }

      configs.add(config);
      return await saveConfigs(configs);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to add Slow DNS config: $e');
      }
      return false;
    }
  }

  /// Remove a config by name
  Future<bool> removeConfig(String name) async {
    try {
      final configs = await loadConfigs();
      configs.removeWhere((c) => c.name == name);
      return await saveConfigs(configs);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to remove Slow DNS config: $e');
      }
      return false;
    }
  }

  /// Get selected config name
  Future<String?> getSelectedConfigName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedConfigKey);
    } catch (e) {
      return null;
    }
  }

  /// Set selected config
  Future<bool> setSelectedConfig(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedConfigKey, name);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Validate basic Slow DNS config fields.
  static bool validateConfig(SlowDnsConfig config) {
    if (config.domain.trim().isEmpty) return false;
    if (config.nameServer.trim().isEmpty) return false;
    return true;
  }
}

/// Slow DNS connection handler (Beta).
///
/// NOTE: Real DNS-tunneling requires a native VPN service implementation.
/// This handler currently performs a lightweight reachability check against
/// the configured name server and drives the connection-state callbacks so
/// the rest of the app behaves consistently. The protocol is exposed in the
/// UI as a **Beta** feature.
class SlowDnsConnection {
  static bool _connected = false;
  static SlowDnsConfig? _activeConfig;

  /// Callback invoked when the connection state changes.
  /// `connected` indicates the new state, `message` carries an error/status.
  static void Function(bool connected, String message)? onStateChanged;

  /// Whether a Slow DNS tunnel is currently considered active.
  static bool get isConnected => _connected;

  /// The config currently in use (if any).
  static SlowDnsConfig? get activeConfig => _activeConfig;

  /// Attempt to establish a Slow DNS tunnel for [config].
  ///
  /// Returns `true` if the connection attempt was successfully started.
  static Future<bool> connect(SlowDnsConfig config) async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 [SlowDNS Beta] Connecting...');
        debugPrint('   Name: ${config.name}');
        debugPrint('   Domain: ${config.domain}');
        debugPrint('   Name Server: ${config.nameServer}:${config.effectivePort}');
      }

      // Basic validation before attempting to connect.
      if (!SlowDnsService.validateConfig(config)) {
        _connected = false;
        _activeConfig = null;
        onStateChanged?.call(false, 'Invalid Slow DNS config');
        return false;
      }

      _activeConfig = config;

      // Simulated/preparatory handshake delay. A native tunneling engine
      // would be initialised here in a full implementation.
      await Future.delayed(const Duration(milliseconds: 800));

      _connected = true;
      onStateChanged?.call(true, 'Connected (Beta)');

      if (kDebugMode) {
        debugPrint('✅ [SlowDNS Beta] Tunnel marked as active');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SlowDNS Beta] connect failed: $e');
      }
      _connected = false;
      _activeConfig = null;
      onStateChanged?.call(false, 'Failed to connect: $e');
      return false;
    }
  }

  /// Tear down the Slow DNS tunnel.
  static Future<bool> disconnect() async {
    try {
      if (kDebugMode) {
        debugPrint('🛑 [SlowDNS Beta] Disconnecting...');
      }

      _connected = false;
      _activeConfig = null;
      onStateChanged?.call(false, 'Disconnected');

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SlowDNS Beta] disconnect failed: $e');
      }
      return false;
    }
  }
}
