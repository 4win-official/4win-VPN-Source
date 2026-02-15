import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/openvpn_config.dart';

/// Service for managing OpenVPN configurations
class OpenVpnService {
  static const String _storageKey = 'openvpn_configs';
  static const String _selectedConfigKey = 'selected_openvpn_config';
  
  /// Load all OpenVPN configs from local storage
  Future<List<OpenVpnConfig>> loadConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = prefs.getStringList(_storageKey) ?? [];
      
      final configs = configsJson
          .map((json) {
            try {
              return OpenVpnConfig.fromJson(jsonDecode(json));
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ Failed to parse OpenVPN config: $e');
              }
              return null;
            }
          })
          .whereType<OpenVpnConfig>()
          .toList();
      
      if (kDebugMode) {
        debugPrint('✅ Loaded ${configs.length} OpenVPN configs');
      }
      
      return configs;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load OpenVPN configs: $e');
      }
      return [];
    }
  }
  
  /// Save configs to local storage
  Future<bool> saveConfigs(List<OpenVpnConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configsJson = configs
          .map((config) => jsonEncode(config.toJson()))
          .toList();
      
      await prefs.setStringList(_storageKey, configsJson);
      
      if (kDebugMode) {
        debugPrint('✅ Saved ${configs.length} OpenVPN configs');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to save OpenVPN configs: $e');
      }
      return false;
    }
  }
  
  /// Add a new config
  Future<bool> addConfig(OpenVpnConfig config) async {
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
        debugPrint('❌ Failed to add OpenVPN config: $e');
      }
      return false;
    }
  }
  
  /// Remove a config
  Future<bool> removeConfig(String name) async {
    try {
      final configs = await loadConfigs();
      configs.removeWhere((c) => c.name == name);
      return await saveConfigs(configs);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to remove OpenVPN config: $e');
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
  
  /// Validate OpenVPN config file format
  static bool validateConfig(String configContent) {
    // بررسی حداقل الزامات یک فایل .ovpn
    if (configContent.trim().isEmpty) {
      return false;
    }
    
    // باید حداقل یکی از کلمات کلیدی OpenVPN را داشته باشد
    final requiredKeywords = [
      'remote',
      'client',
      'dev',
      'proto',
    ];
    
    int foundKeywords = 0;
    for (final keyword in requiredKeywords) {
      if (configContent.contains(keyword)) {
        foundKeywords++;
      }
    }
    
    // حداقل 2 کلمه کلیدی باید وجود داشته باشد
    return foundKeywords >= 2;
  }
  
  /// Extract config name from file content (از comment یا remote)
  static String extractConfigName(String configContent) {
    // سعی در یافتن نام از کامنت
    final commentRegex = RegExp(r'#\s*Name:\s*(.+)');
    final commentMatch = commentRegex.firstMatch(configContent);
    if (commentMatch != null) {
      return commentMatch.group(1)?.trim() ?? 'Unnamed Config';
    }
    
    // اگر نام نبود، از remote استفاده کن
    final remoteRegex = RegExp(r'remote\s+(\S+)');
    final remoteMatch = remoteRegex.firstMatch(configContent);
    if (remoteMatch != null) {
      return remoteMatch.group(1) ?? 'Unnamed Config';
    }
    
    return 'Unnamed Config';
  }
}
