import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/vpn_server.dart';

class ServerService {
  // لینک سرور - محرمانه (هرگز به کاربر نمایش داده نمی‌شود)
  static const String _serverUrl = 'https://raw.githubusercontent.com/4win-official/sub/refs/heads/main/Gate.txt';
  static const String cacheKey = 'cached_servers';
  static const String lastUpdateKey = 'last_server_update';
  static const Duration cacheExpiration = Duration(hours: 6);
  // تعداد تست همزمان - قابل تنظیم از Settings
  static Future<int> getConcurrentTests() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('concurrent_tests') ?? 100; // پیش‌فرض 100
  }

  /// آیا حالت Deep Scan فعال است؟ (برای اینترنت ضعیف یا محدودیت دولتی)
  /// در این حالت اپ با دقت بیشتر، تلاش مجدد و آستانه‌ی پینگ بالاتر اسکن می‌کند.
  static Future<bool> isDeepScanEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('deep_scan') ?? false;
  }

  /// Fetch servers from URL
  Future<List<VpnServer>> fetchServers({bool forceRefresh = false}) async {
    try {
      // Check cache first if not force refresh
      if (!forceRefresh) {
        final cachedServers = await _getCachedServers();
        if (cachedServers.isNotEmpty) {
          return cachedServers;
        }
      }

      // Fetch from network (URL محرمانه - از _serverUrl استفاده می‌شود)
      final response = await http.get(
        Uri.parse(_serverUrl),
        headers: {
          'User-Agent': '4win-VPN/1.0',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final serverList = _parseServerList(response.body);
        
        // Cache the servers
        await _cacheServers(serverList);
        
        return serverList;
      } else {
        throw Exception('Failed to load servers: ${response.statusCode}');
      }
    } catch (e) {
      // If network fails, try to return cached servers
      final cachedServers = await _getCachedServers();
      if (cachedServers.isNotEmpty) {
        return cachedServers;
      }
      
      rethrow;
    }
  }

  /// Parse server list from text content
  List<VpnServer> _parseServerList(String content) {
    final lines = content.split('\n');
    final servers = <VpnServer>[];

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      try {
        final server = VpnServer.fromString(trimmedLine);
        servers.add(server);
      } catch (e) {
        // Skip invalid server entries
        continue;
      }
    }

    return servers;
  }

  /// Cache servers locally
  Future<void> _cacheServers(List<VpnServer> servers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverJsonList = servers.map((s) => jsonEncode(s.toJson())).toList();
      
      await prefs.setStringList(cacheKey, serverJsonList);
      await prefs.setInt(lastUpdateKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Cache failure is not critical
    }
  }

  /// Get cached servers
  Future<List<VpnServer>> _getCachedServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if cache is expired
      final lastUpdate = prefs.getInt(lastUpdateKey);
      if (lastUpdate != null) {
        final updateTime = DateTime.fromMillisecondsSinceEpoch(lastUpdate);
        if (DateTime.now().difference(updateTime) > cacheExpiration) {
          // Cache expired
          return [];
        }
      }

      final serverJsonList = prefs.getStringList(cacheKey);
      if (serverJsonList == null || serverJsonList.isEmpty) {
        return [];
      }

      return serverJsonList
          .map((jsonStr) => VpnServer.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Test server connectivity (actual SSTP port check) - سختگیرانه‌تر
  ///
  /// در حالت Deep Scan (برای اینترنت ضعیف یا محدودیت دولتی):
  /// - تایم‌اوت اتصال کوتاه‌تر (3 ثانیه) برای رد سریع سرورهای فیلترشده
  /// - تا 3 بار تلاش مجدد روی هر سرور (مقابله با قطعی‌های لحظه‌ای)
  /// - آستانه‌ی پینگ بالاتر (2000ms) تا سرورهای کندتر هم برای کاربرانِ
  ///   با اینترنت ضعیف قابل‌استفاده باقی بمانند
  Future<int?> testServerConnectivity(VpnServer server) async {
    final bool deepScan = await isDeepScanEnabled();

    // پارامترها بر اساس حالت Deep Scan
    final Duration connectTimeout =
        deepScan ? const Duration(seconds: 3) : const Duration(seconds: 5);
    final int maxAttempts = deepScan ? 3 : 1; // تلاش مجدد فقط در Deep Scan
    final int pingThreshold = deepScan ? 2000 : 800; // آستانه‌ی پذیرش

    int? bestPing;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final ping = await _singleConnectivityTest(
        server,
        connectTimeout,
        pingThreshold,
      );
      if (ping != null) {
        // بهترین (کمترین) پینگ بین تلاش‌ها را نگه می‌داریم
        if (bestPing == null || ping < bestPing) {
          bestPing = ping;
        }
        // در حالت عادی همان اولین موفقیت کافی است
        if (!deepScan) break;
      }
    }
    return bestPing;
  }

  /// یک بار تست اتصال به سرور و برگرداندن پینگ (یا null)
  Future<int?> _singleConnectivityTest(
    VpnServer server,
    Duration connectTimeout,
    int pingThreshold,
  ) async {
    try {
      final stopwatch = Stopwatch()..start();

      final socket = await Socket.connect(
        server.address,
        server.port,
        timeout: connectTimeout,
      );

      stopwatch.stop();

      // تست دقیق‌تر: چک کردن اینکه سرور واقعاً پاسخ میده
      try {
        socket.write('CONNECT\r\n');
        await socket.flush();

        await Future.delayed(const Duration(milliseconds: 100));

        if (socket.remoteAddress.address.isEmpty) {
          await socket.close();
          return null; // سرور فیک - پینگ نداد
        }

        bool socketAlive = true;
        try {
          socket.listen(
            (data) {},
            onDone: () => socketAlive = false,
            onError: (e) => socketAlive = false,
            cancelOnError: true,
          );

          await Future.delayed(const Duration(milliseconds: 200));

          if (!socketAlive) {
            await socket.close();
            return null; // سرور قطع کرد - فیک است
          }
        } catch (e) {
          // خطا در خواندن - ولی سوکت زنده بود
        }
      } catch (e) {
        await socket.close();
        return null; // خطا - سرور قابل اتصال نیست
      }

      await socket.close();

      final ping = stopwatch.elapsedMilliseconds;
      return ping < pingThreshold ? ping : null;
    } catch (e) {
      return null; // Server unreachable
    }
  }

  /// Test servers in parallel batches and remove unreachable ones
  Future<List<VpnServer>> testServersInParallel(
    List<VpnServer> servers,
    {Function(int tested, int total)? onProgress}
  ) async {
    final reachableServers = <VpnServer>[];
    final totalServers = servers.length;
    int testedCount = 0;

    // دریافت تعداد تست همزمان از تنظیمات
    final int batchSize = await getConcurrentTests();
    
    if (kDebugMode) {
      debugPrint('🔍 Testing $totalServers servers in batches of $batchSize...');
    }

    // تقسیم سرورها به batch ها
    for (int i = 0; i < servers.length; i += batchSize) {
      final int end = (i + batchSize < servers.length) 
          ? i + batchSize 
          : servers.length;
      
      final batch = servers.sublist(i, end);
      
      // تست همزمان این batch
      final results = await Future.wait(
        batch.map((server) => testServerConnectivity(server)),
      );

      // اضافه کردن سرورهای قابل دسترس
      for (int j = 0; j < batch.length; j++) {
        final ping = results[j];
        if (ping != null) {
          final server = batch[j].copyWith(ping: ping);
          reachableServers.add(server);
          
          if (kDebugMode) {
            debugPrint('✅ ${server.address}:${server.port} - ${ping}ms');
          }
        } else {
          if (kDebugMode) {
            debugPrint('❌ ${batch[j].address}:${batch[j].port} - Unreachable');
          }
        }
      }

      testedCount += batch.length;
      onProgress?.call(testedCount, totalServers);
    }

    if (kDebugMode) {
      debugPrint('📊 Found ${reachableServers.length} reachable servers out of $totalServers');
    }

    // مرتب‌سازی براساس ping
    reachableServers.sort((a, b) {
      final pingA = a.ping ?? 9999;
      final pingB = b.ping ?? 9999;
      return pingA.compareTo(pingB);
    });

    return reachableServers;
  }

  /// Find best server based on actual connectivity test
  Future<VpnServer?> findBestServer(List<VpnServer> servers) async {
    if (servers.isEmpty) return null;

    // اگر سرورها قبلاً تست نشدن، تست کن
    final testedServers = servers.any((s) => s.ping != null)
        ? servers
        : await testServersInParallel(servers);

    if (testedServers.isEmpty) return null;

    // برگرداندن سرور با کمترین ping
    return testedServers.first;
  }

  /// Clear cache
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
    await prefs.remove(lastUpdateKey);
  }
}
