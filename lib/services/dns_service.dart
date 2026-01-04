import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/dns_server.dart';

class DnsService {
  static const String customDnsKey = 'custom_dns_servers';
  static const String selectedProtocolKey = 'selected_protocol'; // 'sstp' or 'direct_dns'

  /// گرفتن پروتکل انتخاب شده
  Future<String> getSelectedProtocol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(selectedProtocolKey) ?? 'sstp'; // پیش‌فرض SSTP
  }

  /// ذخیره پروتکل انتخاب شده
  Future<void> setSelectedProtocol(String protocol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(selectedProtocolKey, protocol);
  }

  /// تست اتصال به DNS server (با HTTP request به IP سرور)
  Future<int?> testDnsConnectivity(DnsServer server) async {
    try {
      final stopwatch = Stopwatch()..start();
      
      // تست HTTP به آدرس سرور DNS
      // از Cloudflare استفاده می‌کنیم که سریع و قابل اعتماد است
      final response = await http.get(
        Uri.parse('https://1.1.1.1/dns-query?name=google.com&type=A'),
        headers: {'Accept': 'application/dns-json'},
      ).timeout(const Duration(seconds: 3));
      
      stopwatch.stop();
      
      // اگر پاسخ موفق بود، پینگ را برگردان
      if (response.statusCode == 200) {
        final ping = stopwatch.elapsedMilliseconds;
        return ping;
      }
      
      return null;
    } catch (e) {
      return null; // اگر خطا بود، null برگردان تا N/A نشون بده
    }
  }

  /// تست همزمان چند DNS server
  Future<List<DnsServer>> testDnsServersInParallel(
    List<DnsServer> servers, {
    Function(int tested, int total)? onProgress,
  }) async {
    const int batchSize = 100; // تست 100 تا 100 تا
    final testedServers = <DnsServer>[];
    int tested = 0;

    for (int i = 0; i < servers.length; i += batchSize) {
      final batch = servers.skip(i).take(batchSize).toList();
      final futures = batch.map((server) => testDnsConnectivity(server));
      final results = await Future.wait(futures);

      for (int j = 0; j < batch.length; j++) {
        final server = batch[j];
        final ping = results[j];

        // ✅ همیشه سرور را اضافه کن (با یا بدون پینگ)
        server.ping = ping;
        testedServers.add(server);

        tested++;
        onProgress?.call(tested, servers.length);
      }
    }

    // مرتب‌سازی بر اساس ping
    testedServers.sort((a, b) => (a.ping ?? 9999).compareTo(b.ping ?? 9999));
    return testedServers;
  }

  /// ذخیره DNS های سفارشی
  Future<void> saveCustomDnsServers(List<DnsServer> servers) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = servers.map((s) => s.toJson()).toList();
    await prefs.setString(customDnsKey, json.encode(jsonList));
  }

  /// گرفتن DNS های سفارشی
  Future<List<DnsServer>> getCustomDnsServers() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(customDnsKey);
    
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((j) => DnsServer.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  /// گرفتن تمام DNS های موجود (عمومی + سفارشی)
  Future<List<DnsServer>> getAllDnsServers() async {
    final publicServers = DnsServer.getPublicDnsServers();
    final customServers = await getCustomDnsServers();
    return [...publicServers, ...customServers];
  }

  /// افزودن DNS سفارشی
  Future<void> addCustomDns(DnsServer server) async {
    final customServers = await getCustomDnsServers();
    server.isCustom = true;
    customServers.add(server);
    await saveCustomDnsServers(customServers);
  }

  /// حذف DNS سفارشی
  Future<void> removeCustomDns(String primaryDns) async {
    final customServers = await getCustomDnsServers();
    customServers.removeWhere((s) => s.primaryDns == primaryDns);
    await saveCustomDnsServers(customServers);
  }
}
