import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/xray_config.dart';

class XrayService {
  static const String _configUrl = 'https://v-1.storage.c2.liara.space/1/sub.txt';
  static const String _cacheKey = 'xray_configs_cache';
  static const String _cacheTimeKey = 'xray_configs_cache_time';
  static const Duration _cacheDuration = Duration(hours: 1);

  /// Fetch Xray configs from server
  Future<List<XrayConfig>> fetchConfigs({bool forceRefresh = false}) async {
    try {
      // Check cache first
      if (!forceRefresh) {
        final cachedConfigs = await _getCachedConfigs();
        if (cachedConfigs != null && cachedConfigs.isNotEmpty) {
          return cachedConfigs;
        }
      }

      // Fetch from server
      final response = await http.get(
        Uri.parse(_configUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final configs = _parseConfigs(response.body);
        
        // Cache configs
        await _cacheConfigs(configs);
        
        return configs;
      } else {
        throw Exception('Failed to fetch configs: ${response.statusCode}');
      }
    } catch (e) {
      // Return cached configs if available
      final cachedConfigs = await _getCachedConfigs();
      if (cachedConfigs != null && cachedConfigs.isNotEmpty) {
        return cachedConfigs;
      }
      
      throw Exception('Failed to fetch Xray configs: $e');
    }
  }

  /// Parse config text to list of XrayConfig
  List<XrayConfig> _parseConfigs(String text) {
    final configs = <XrayConfig>[];
    final lines = text.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      try {
        if (trimmed.startsWith('vless://') || trimmed.startsWith('vmess://')) {
          final config = XrayConfig.fromString(trimmed);
          configs.add(config);
        }
      } catch (e) {
        // Skip invalid configs
        if (kDebugMode) {
          print('⚠️ Skipped invalid config: ${trimmed.substring(0, min(50, trimmed.length))}... Error: $e');
        }
      }
    }

    return configs;
  }

  /// Cache configs to local storage
  Future<void> _cacheConfigs(List<XrayConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert configs to JSON
      final jsonList = configs.map((c) => c.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to cache configs: $e');
      }
    }
  }

  /// Get cached configs
  Future<List<XrayConfig>?> _getCachedConfigs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check cache age
      final cacheTime = prefs.getInt(_cacheTimeKey);
      if (cacheTime != null) {
        final age = DateTime.now().millisecondsSinceEpoch - cacheTime;
        if (age > _cacheDuration.inMilliseconds) {
          return null; // Cache expired
        }
      }
      
      // Get cached data
      final jsonString = prefs.getString(_cacheKey);
      if (jsonString == null) return null;
      
      // Parse JSON
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList.map((json) => XrayConfig.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to get cached configs: $e');
      }
      return null;
    }
  }

  /// Clear cache
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimeKey);
  }

  /// Test config connectivity (real ping like v2rayNG)
  /// Tests by making HTTP request through the server
  Future<int?> testConfig(XrayConfig config) async {
    try {
      final stopwatch = Stopwatch()..start();
      
      // Method 1: TCP socket connection test (fast but not accurate)
      try {
        final socket = await Socket.connect(
          config.address,
          config.port,
          timeout: const Duration(seconds: 5),
        );
        
        stopwatch.stop();
        final ping = stopwatch.elapsedMilliseconds;
        socket.destroy();
        
        // Update config with ping
        config.ping = ping;
        
        if (kDebugMode) {
          print('✅ ${config.remark}: ${ping}ms');
        }
        
        return ping;
      } catch (e) {
        // Method 2: Try HTTP ping if socket fails (for HTTP/WS configs)
        if (config.network == 'ws' || config.network == 'h2' || config.network == 'http') {
          try {
            stopwatch.reset();
            stopwatch.start();
            
            final response = await http.head(
              Uri.parse('http://${config.address}:${config.port}'),
            ).timeout(const Duration(seconds: 5));
            
            stopwatch.stop();
            final ping = stopwatch.elapsedMilliseconds;
            
            if (response.statusCode < 500) {
              config.ping = ping;
              
              if (kDebugMode) {
                print('✅ ${config.remark}: ${ping}ms (HTTP)');
              }
              
              return ping;
            }
          } catch (httpError) {
            if (kDebugMode) {
              print('⚠️ ${config.remark}: HTTP test failed');
            }
          }
        }
        
        // If both methods fail, return null
        config.ping = null;
        if (kDebugMode) {
          print('❌ ${config.remark}: Unreachable');
        }
        return null;
      }
    } catch (e) {
      config.ping = null;
      if (kDebugMode) {
        print('❌ ${config.remark}: Error - $e');
      }
      return null;
    }
  }

  /// Test multiple configs in parallel
  Future<List<XrayConfig>> testConfigsInParallel(
    List<XrayConfig> configs, {
    Function(int tested, int total)? onProgress,
  }) async {
    final testedConfigs = <XrayConfig>[];
    int tested = 0;

    // Test in batches of 10
    const batchSize = 10;
    for (int i = 0; i < configs.length; i += batchSize) {
      final batch = configs.skip(i).take(batchSize).toList();
      
      // Test batch in parallel
      final futures = batch.map((config) => testConfig(config));
      await Future.wait(futures);
      
      // Add results
      for (int j = 0; j < batch.length; j++) {
        testedConfigs.add(batch[j]);
        tested++;
        
        if (onProgress != null) {
          onProgress(tested, configs.length);
        }
      }
    }

    // Sort by ping (null at the end)
    testedConfigs.sort((a, b) {
      if (a.ping == null && b.ping == null) return 0;
      if (a.ping == null) return 1;
      if (b.ping == null) return -1;
      return a.ping!.compareTo(b.ping!);
    });

    return testedConfigs;
  }
}
