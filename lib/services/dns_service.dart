import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/dns_server.dart';

class DnsService {
  static const String customDnsKey = 'custom_dns_servers';
  static const String selectedProtocolKey = 'selected_protocol'; // 'sstp' or 'direct_dns'

  /// گرفتن پروتکل انتخاب شده
  Future<String> getSelectedProtocol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(selectedProtocolKey) ?? 'psiphon'; // پیش‌فرض Psiphon
  }

  /// ذخیره پروتکل انتخاب شده
  Future<void> setSelectedProtocol(String protocol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(selectedProtocolKey, protocol);
  }

  /// تست اتصال (پینگ واقعی) به DNS server.
  /// مثل دستور ping در ترموکس - تاخیر واقعی تا اون DNS رو اندازه می‌گیره.
  ///
  /// روش اصلی: یک DNS query واقعی روی UDP پورت 53 می‌فرسته و زمان پاسخ رو
  /// اندازه می‌گیره. این روش حتی وقتی VPN دایرکت DNS فعاله هم کار می‌کنه چون
  /// از پروتکل واقعی DNS استفاده می‌کنه (مثل کاری که خود اپ موقع DNS resolution
  /// انجام می‌ده). اگر UDP پاسخ نداد، به‌عنوان fallback از TCP Socket استفاده می‌کنه.
  Future<int?> testDnsConnectivity(DnsServer server) async {
    // روش 1: پینگ واقعی DNS با UDP query
    final udpPing = await _pingDnsUdp(server.primaryDns);
    if (udpPing != null) return udpPing;

    // روش 2 (fallback): تست TCP روی پورت‌های رایج DNS
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
        if (ping < 2000) return ping;
        return null;
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  /// ارسال یک DNS query واقعی روی UDP و اندازه‌گیری زمان پاسخ (میلی‌ثانیه)
  Future<int?> _pingDnsUdp(String ip) async {
    RawDatagramSocket? socket;
    try {
      final InternetAddress address = InternetAddress(ip);
      final query = _buildDnsQuery('google.com');

      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final completer = Completer<int?>();
      final stopwatch = Stopwatch()..start();

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram != null && !completer.isCompleted) {
            stopwatch.stop();
            completer.complete(stopwatch.elapsedMilliseconds);
          }
        }
      });

      socket.send(query, address, 53);

      final result = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => null,
      );

      if (result != null && result < 2000) return result;
      return null;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  /// ساخت یک بسته‌ی استاندارد DNS query (نوع A) برای دامنه‌ی داده‌شده
  Uint8List _buildDnsQuery(String domain) {
    final builder = BytesBuilder();
    builder.add([0x12, 0x34]); // Transaction ID
    builder.add([0x01, 0x00]); // Flags: standard query, recursion desired
    builder.add([0x00, 0x01]); // QDCOUNT = 1
    builder.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]); // AN/NS/AR = 0
    for (final part in domain.split('.')) {
      builder.addByte(part.length);
      builder.add(part.codeUnits);
    }
    builder.addByte(0); // پایان نام دامنه
    builder.add([0x00, 0x01]); // QTYPE = A
    builder.add([0x00, 0x01]); // QCLASS = IN
    return builder.toBytes();
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
