import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dns_vpn_connection.dart';

/// A single DNS resolver scan result.
class DnsScanResult {
  final String ip;
  final int udpMs; // -1 = failed
  final int tcpMs; // -1 = failed
  final bool reachable;
  final String? name; // friendly provider name if known

  const DnsScanResult({
    required this.ip,
    required this.udpMs,
    required this.tcpMs,
    required this.reachable,
    this.name,
  });

  /// Best latency across the two probes (used for display/sorting).
  int get bestMs {
    if (udpMs >= 0 && tcpMs >= 0) return udpMs < tcpMs ? udpMs : tcpMs;
    if (udpMs >= 0) return udpMs;
    if (tcpMs >= 0) return tcpMs;
    return -1;
  }

  bool get udpOk => udpMs >= 0;
  bool get tcpOk => tcpMs >= 0;

  factory DnsScanResult.fromJson(Map<String, dynamic> j, {String? name}) {
    return DnsScanResult(
      ip: j['ip'] as String,
      udpMs: (j['udpMs'] as num?)?.toInt() ?? -1,
      tcpMs: (j['tcpMs'] as num?)?.toInt() ?? -1,
      reachable: j['reachable'] == true,
      name: name,
    );
  }
}

/// Advanced DNS scanner for the Slow DNS protocol.
///
/// Slow DNS tunnels rely on a working, low-latency public DNS resolver as the
/// `nameServer`. This scanner probes a large curated list of public resolvers
/// (plus any custom IPs the user adds), concurrently, using a REAL DNS query
/// and a TCP/53 probe, and returns them ranked fastest-first so the user can
/// pick the best resolver for their network.
class DnsScannerService {
  /// Friendly names for well-known resolvers (best-effort labelling).
  static const Map<String, String> knownProviders = {
    '1.1.1.1': 'Cloudflare',
    '1.0.0.1': 'Cloudflare',
    '8.8.8.8': 'Google',
    '8.8.4.4': 'Google',
    '9.9.9.9': 'Quad9',
    '149.112.112.112': 'Quad9',
    '208.67.222.222': 'OpenDNS',
    '208.67.220.220': 'OpenDNS',
    '94.140.14.14': 'AdGuard',
    '94.140.15.15': 'AdGuard',
    '76.76.2.0': 'Control D',
    '76.76.10.0': 'Control D',
    '4.2.2.1': 'Level3',
    '4.2.2.2': 'Level3',
    '84.200.69.80': 'DNS.WATCH',
    '84.200.70.40': 'DNS.WATCH',
    '77.88.8.8': 'Yandex',
    '77.88.8.1': 'Yandex',
    '156.154.70.1': 'Neustar',
    '156.154.71.1': 'Neustar',
    '8.26.56.26': 'Comodo',
    '8.20.247.20': 'Comodo',
    '185.228.168.9': 'CleanBrowsing',
    '185.228.169.9': 'CleanBrowsing',
    '64.6.64.6': 'Verisign',
    '64.6.65.6': 'Verisign',
    '45.90.28.0': 'NextDNS',
    '45.90.30.0': 'NextDNS',
    '199.85.126.10': 'Norton',
    '199.85.127.10': 'Norton',
    '74.82.42.42': 'Hurricane Electric',
    '109.69.8.51': 'puntCAT',
    '5.2.75.75': 'Freenom',
    '80.80.80.80': 'Freenom',
    '216.146.35.35': 'Dyn',
    '216.146.36.36': 'Dyn',
  };

  /// The default curated list of public resolvers scanned when the user hasn't
  /// added custom targets. Broad enough to find something that works on almost
  /// any network, while still finishing fast thanks to native concurrency.
  static const List<String> defaultServers = [
    '1.1.1.1', '1.0.0.1',
    '8.8.8.8', '8.8.4.4',
    '9.9.9.9', '149.112.112.112',
    '208.67.222.222', '208.67.220.220',
    '94.140.14.14', '94.140.15.15',
    '76.76.2.0', '76.76.10.0',
    '4.2.2.1', '4.2.2.2',
    '84.200.69.80', '84.200.70.40',
    '77.88.8.8', '77.88.8.1',
    '156.154.70.1', '156.154.71.1',
    '8.26.56.26', '8.20.247.20',
    '185.228.168.9', '185.228.169.9',
    '64.6.64.6', '64.6.65.6',
    '45.90.28.0', '45.90.30.0',
    '199.85.126.10', '199.85.127.10',
    '74.82.42.42',
    '109.69.8.51',
    '5.2.75.75', '80.80.80.80',
    '216.146.35.35', '216.146.36.36',
    '223.5.5.5', '223.6.6.6', // AliDNS
    '119.29.29.29', // DNSPod
    '180.76.76.76', // Baidu
    '114.114.114.114', // 114DNS
    '101.101.101.101', // Quad101 (TWNIC)
    '168.95.1.1', // HiNet
    '45.11.45.11', // DNS.SB
    '193.110.81.0', '185.253.5.0', // dns0.eu
  ];

  /// Scans [servers] (or [defaultServers] when null/empty) and returns the
  /// results ranked fastest-first. [domain] is the name resolved during the
  /// probe (change it to test resolution of a specific/tunnel domain).
  Future<List<DnsScanResult>> scan({
    List<String>? servers,
    String domain = 'google.com',
  }) async {
    final targets = (servers == null || servers.isEmpty)
        ? defaultServers
        : servers;

    final raw = await DnsVpnConnection.scanDns(targets, domain: domain);
    if (raw == null) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final results = list
          .map((e) => DnsScanResult.fromJson(
                e as Map<String, dynamic>,
                name: knownProviders[(e)['ip']],
              ))
          .toList();
      // Native already sorts, but re-sort defensively (reachable first, then
      // by best latency).
      results.sort((a, b) {
        if (a.reachable != b.reachable) return a.reachable ? -1 : 1;
        final am = a.bestMs < 0 ? 1 << 30 : a.bestMs;
        final bm = b.bestMs < 0 ? 1 << 30 : b.bestMs;
        return am.compareTo(bm);
      });
      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to parse DNS scan result: $e');
      return [];
    }
  }
}
