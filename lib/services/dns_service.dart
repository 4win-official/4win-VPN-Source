import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// تست اتصال (پینگ واقعی) به DNS server با Socket.connect به IP خود سرور
  /// مثل دستور ping 1.1.1.1 در ترموکس - تاخیر واقعی تا اون DNS رو اندازه می‌گیره
  Future<int?> testDnsConnectivity(DnsServer server) async {
    // پورت‌هایی که یک سرور DNS معمولاً روی اون‌ها پاسخ میده
    // 53 = DNS استاندارد ، 443 = DNS-over-HTTPS ، 853 = DNS-over-TLS ، 80 = fallback
    const List<int> portsToTry = [53, 443, 853, 80];

    for (final port in portsToTry) {
      try {
        final stopwatch = Stopwatch()..start();

        final socket = await Socket.connect(
          server.primaryDns,
          port,
          timeout: const Duration(seconds: 3),
        );

        stopwatch.stop();
        await socket.close();

        final ping = stopwatch.elapsedMilliseconds;
        // فقط پینگ منطقی برگردان (زیر 2 ثانیه)
        if (ping < 2000) {
          return ping;
        }
        return null;
      } catch (_) {
        // این پورت پاسخ نداد، پورت بعدی رو امتحان کن
        continue;
      }
    }

    // هیچ پورتی پاسخ نداد
    return null;
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
