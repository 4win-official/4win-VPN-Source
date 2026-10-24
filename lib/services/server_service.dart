import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/vpn_server.dart';
import 'probe_cancellation.dart';

class ServerService {
  // لینک سرور - محرمانه (هرگز به کاربر نمایش داده نمی‌شود)
  static const String _serverUrl = 'https://raw.githubusercontent.com/4win-official/sub/refs/heads/main/Gate.txt';
  static const String cacheKey = 'cached_servers';
  static const String lastUpdateKey = 'last_server_update';
  static const Duration cacheExpiration = Duration(hours: 6);
  // تعداد تست همزمان - قابل تنظیم از Settings
  static Future<int> getConcurrentTests() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('concurrent_tests') ?? 100; // پیش‌فرض 100
    // Clamp to the supported 1–300 parallel range.
    return v.clamp(1, 300);
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

  /// Test server connectivity with a REAL micro-connection attempt (NOT an
  /// ICMP ping).
  ///
  /// Why not a ping: many SSTP servers do NOT answer ICMP/UDP pings at all yet
  /// still accept a TCP session on their SSTP port — sometimes the TCP
  /// handshake itself completes only a few seconds after the request. So the
  /// only reliable signal is: "can we actually open a TCP connection to the
  /// SSTP port?". If the 3-way handshake succeeds, the server is usable —
  /// regardless of how slow it was.
  ///
  /// We therefore:
  ///  • use a generous connect timeout (up to ~6s) so slow-to-accept servers
  ///    (e.g. one that connects ~4s after the request) are NOT dropped,
  ///  • accept ANY successful handshake as reachable (no low-latency cutoff),
  ///  • retry a couple of times so a single transient drop doesn't reject a
  ///    working server.
  Future<int?> testServerConnectivity(
    VpnServer server, {
    ProbeCancellation? cancellation,
  }) async {
    final token = cancellation ?? ProbeCancellation();
    if (token.isCancelled) return null;
    final bool deepScan = await isDeepScanEnabled();

    // Generous timeout so slow-accepting SSTP servers still pass. Deep Scan
    // waits even longer and retries more.
    final Duration connectTimeout =
        deepScan ? const Duration(seconds: 8) : const Duration(seconds: 6);
    final int maxAttempts = deepScan ? 3 : 2;

    int? bestPing;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (token.isCancelled) return null;
      final ping = await _singleConnectivityTest(server, connectTimeout, token);
      if (token.isCancelled) return null;
      if (ping != null) {
        if (bestPing == null || ping < bestPing) bestPing = ping;
        // First successful handshake is enough — the server is reachable.
        break;
      }
    }
    return bestPing;
  }

  /// A single REAL connection attempt: open a TCP socket to the SSTP port and
  /// measure how long the handshake took. A completed handshake means the
  /// server accepted the connection — that is the actual "can I connect?"
  /// signal the user asked for. We do NOT reject on latency, and we do NOT
  /// require the server to echo any bytes (SSTP servers legitimately stay
  /// silent until the TLS/PPP handshake begins). Returns the handshake time in
  /// ms, or null if the connection could not be established.
  Future<int?> _singleConnectivityTest(
    VpnServer server,
    Duration connectTimeout,
    ProbeCancellation cancellation,
  ) async {
    Socket? socket;
    try {
      final stopwatch = Stopwatch()..start();

      socket = await connectProbeSocket(
        server.address,
        server.port,
        cancellation: cancellation,
        timeout: connectTimeout,
      );

      stopwatch.stop();
      final ping = stopwatch.elapsedMilliseconds;

      // Connection established = server is reachable. Close cleanly and report
      // the handshake latency (used only for ordering, never for filtering).
      socket.destroy();
      return ping;
    } catch (e) {
      try {
        socket?.destroy();
      } catch (_) {}
      return null; // handshake failed within the timeout → unreachable
    }
  }

  /// Test servers in parallel batches and remove unreachable ones
  Future<List<VpnServer>> testServersInParallel(
    List<VpnServer> servers,
    {Function(int tested, int total)? onProgress,
    ProbeCancellation? cancellation}
  ) async {
    final token = cancellation ?? ProbeCancellation();
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
      if (token.isCancelled) break;
      final int end = (i + batchSize < servers.length) 
          ? i + batchSize 
          : servers.length;
      
      final batch = servers.sublist(i, end);
      
      // تست همزمان این batch
      final results = await Future.wait(
        batch.map((server) => testServerConnectivity(server, cancellation: token)),
      );
      if (token.isCancelled) break;

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
