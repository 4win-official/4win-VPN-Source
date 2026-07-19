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
  /// [parallel] controls how many probes run at once natively.
  Future<List<DnsScanResult>> scan({
    List<String>? servers,
    String domain = 'google.com',
    int parallel = 100,
  }) async {
    final targets = (servers == null || servers.isEmpty)
        ? defaultServers
        : servers;
    return _scanChunk(targets, domain, parallel);
  }

  Future<List<DnsScanResult>> _scanChunk(
      List<String> targets, String domain, int parallel) async {
    final raw = await DnsVpnConnection.scanDns(
      targets,
      domain: domain,
      parallel: parallel,
    );
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final results = list
          .map((e) => DnsScanResult.fromJson(
                e as Map<String, dynamic>,
                name: knownProviders[(e)['ip']],
              ))
          .toList();
      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to parse DNS scan result: $e');
      return [];
    }
  }

  /// Parse a dotted IPv4 string into a 32-bit int, or null if invalid.
  static int? _ipToInt(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return null;
    var n = 0;
    for (var i = 0; i < 4; i++) {
      final o = int.tryParse(parts[i]);
      if (o == null || o < 0 || o > 255) return null;
      n = (n << 8) | o;
    }
    return n & 0xFFFFFFFF;
  }

  static String _intToIp(int v) =>
      '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';

  /// Generate every host IPv4 in the inclusive range [fromIp] .. [toIp]
  /// (skipping .0 and .255 hosts), capped at [max] addresses. Used by the
  /// range scanner — the user gives a start and end of the range to scan.
  static List<String> generateRange(String fromIp, String toIp,
      {int max = 200000}) {
    final a = _ipToInt(fromIp);
    final b = _ipToInt(toIp);
    if (a == null || b == null) return [];
    final lo = a <= b ? a : b;
    final hi = a <= b ? b : a;
    final out = <String>[];
    for (var cur = lo; cur <= hi && out.length < max; cur++) {
      final last = cur & 0xFF;
      if (last != 0 && last != 255) out.add(_intToIp(cur));
    }
    return out;
  }

  /// Generate [count] RANDOM public-ish IPv4 addresses (avoids private,
  /// loopback, multicast, and reserved blocks). Used by the scanner's random
  /// mode so the user can just say "scan 10,000 random IPs".
  static List<String> generateRandom(int count, {int? seed}) {
    final rnd = seed ?? (DateTime.now().microsecondsSinceEpoch & 0x7fffffff);
    var state = rnd == 0 ? 0x2545F491 : rnd;
    int next() {
      // xorshift32 — fast, dependency-free.
      state ^= (state << 13) & 0xFFFFFFFF;
      state ^= (state >> 17);
      state ^= (state << 5) & 0xFFFFFFFF;
      return state & 0xFFFFFFFF;
    }

    bool isPublic(int a, int b) {
      if (a == 0 || a == 10 || a == 127) return false; // this-net / private / loopback
      if (a == 172 && b >= 16 && b <= 31) return false; // private
      if (a == 192 && b == 168) return false; // private
      if (a == 169 && b == 254) return false; // link-local
      if (a == 100 && b >= 64 && b <= 127) return false; // CGNAT
      if (a >= 224) return false; // multicast / reserved
      return true;
    }

    final out = <String>{};
    var guard = count * 20 + 100;
    while (out.length < count && guard-- > 0) {
      final a = next() % 256;
      final b = next() % 256;
      final c = next() % 256;
      final d = 1 + (next() % 254); // 1..254
      if (!isPublic(a, b)) continue;
      out.add('$a.$b.$c.$d');
    }
    return out.toList();
  }

  /// Bulk scan a pre-built list of [targets] (from a range or random set),
  /// probing them against [domain] in chunks (so progress can be reported and
  /// memory stays bounded), running [parallel] probes concurrently per chunk.
  /// [onProgress] is called with (scanned, total) after each chunk; [onFound]
  /// streams working results as they arrive. Returns reachable results only,
  /// fastest-first.
  Future<List<DnsScanResult>> scanRange({
    required List<String> targets,
    String domain = 'google.com',
    int parallel = 100,
    int chunkSize = 500,
    void Function(int scanned, int total)? onProgress,
    void Function(List<DnsScanResult> found)? onFound,
    bool Function()? isCancelled,
  }) async {
    final all = targets;
    if (all.isEmpty) return [];
    final found = <DnsScanResult>[];
    var scanned = 0;
    for (var i = 0; i < all.length; i += chunkSize) {
      if (isCancelled?.call() == true) break;
      final chunk = all.sublist(
          i, (i + chunkSize).clamp(0, all.length));
      final res = await _scanChunk(chunk, domain, parallel);
      final reachable = res.where((r) => r.reachable).toList();
      if (reachable.isNotEmpty) {
        found.addAll(reachable);
        onFound?.call(reachable);
      }
      scanned += chunk.length;
      onProgress?.call(scanned, all.length);
    }
    found.sort((a, b) {
      if (a.reachable != b.reachable) return a.reachable ? -1 : 1;
      final am = a.bestMs < 0 ? 1 << 30 : a.bestMs;
      final bm = b.bestMs < 0 ? 1 << 30 : b.bestMs;
      return am.compareTo(bm);
    });
    return found;
  }
}
