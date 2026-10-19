import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/slowdns_config.dart';

export 'slowdns_connection.dart';

/// Persistence for standalone Slow DNS profiles; legacy fields are preserved.
class SlowDnsService {
  static const String _storageKey = 'slowdns_configs';
  static const String _selectedConfigKey = 'selected_slowdns_config';

  Future<List<SlowDnsConfig>> loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList(_storageKey) ?? [];
      final configs = <SlowDnsConfig>[];
      for (final entry in entries) {
        try {
          configs.add(SlowDnsConfig.fromJson(jsonDecode(entry)));
        } catch (_) {
          if (kDebugMode) debugPrint('Skipping a malformed Slow DNS profile.');
        }
      }
      return configs;
    } catch (_) {
      return [];
    }
  }

  Future<bool> saveConfigs(List<SlowDnsConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setStringList(
        _storageKey,
        configs.map((config) => jsonEncode(config.toJson())).toList(),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> addConfig(SlowDnsConfig config) async {
    if (!validateConfig(config)) return false;
    final configs = await loadConfigs();
    if (configs.any((entry) => entry.name == config.name)) return false;
    return saveConfigs([...configs, config]);
  }

  Future<bool> removeConfig(String name) async {
    final configs = await loadConfigs();
    configs.removeWhere((config) => config.name == name);
    return saveConfigs(configs);
  }

  Future<String?> getSelectedConfigName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedConfigKey);
    } catch (_) {
      return null;
    }
  }

  Future<bool> setSelectedConfig(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_selectedConfigKey, name);
    } catch (_) {
      return false;
    }
  }

  static bool validateConfig(SlowDnsConfig config) => config.isValid;
}
