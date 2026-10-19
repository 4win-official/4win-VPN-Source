import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dns_vpn_connection.dart';

class DnsScanResult {
  final String ip;
  final int udpMs, tcpMs, responseBytes, ednsPayload;
  final bool reachable, ednsSupported, txtSupported, tunnelVerified;
  final bool nxdomainSafe, nxdomainHijacked, tunnelCandidate;
  final String? name;
  const DnsScanResult({
    required this.ip,
    required this.udpMs,
    required this.tcpMs,
    required this.reachable,
    this.ednsSupported = false,
    this.ednsPayload = 1232,
    this.txtSupported = false,
    this.responseBytes = 0,
    this.tunnelVerified = false,
    this.nxdomainSafe = false,
    this.nxdomainHijacked = false,
    this.tunnelCandidate = false,
    this.name,
  });
  int get bestMs => udpMs >= 0 && tcpMs >= 0
      ? (udpMs < tcpMs ? udpMs : tcpMs)
      : (udpMs >= 0 ? udpMs : tcpMs);
  bool get udpOk => udpMs >= 0;
  bool get tcpOk => tcpMs >= 0;

  /// A candidate is usable over UDP and passed the EDNS and NXDOMAIN checks.
  bool get isCandidate =>
      tunnelCandidate &&
      reachable &&
      udpOk &&
      ednsSupported &&
      nxdomainSafe &&
      !nxdomainHijacked;
  factory DnsScanResult.fromJson(Map<String, dynamic> j, {String? name}) {
    final ip = j['ip'];
    if (ip is! String || DnsScannerService.parseIp(ip) == null)
      throw const FormatException('Native scanner returned an invalid IP');
    return DnsScanResult(
      ip: ip,
      udpMs: (j['udpMs'] as num?)?.toInt() ?? -1,
      tcpMs: (j['tcpMs'] as num?)?.toInt() ?? -1,
      reachable: j['reachable'] == true,
      ednsSupported: j['ednsSupported'] == true,
      ednsPayload: (j['ednsPayload'] as num?)?.toInt() ?? 1232,
      txtSupported: j['txtSupported'] == true,
      responseBytes: (j['responseBytes'] as num?)?.toInt() ?? 0,
      tunnelVerified: j['tunnelVerified'] == true,
      nxdomainSafe: j['nxdomainSafe'] == true,
      nxdomainHijacked: j['nxdomainHijacked'] == true,
      tunnelCandidate: j['tunnelCandidate'] == true,
      name: name,
    );
  }
}

class DnsScanUnavailableException implements Exception {
  final String message;
  const DnsScanUnavailableException(this.message);
  @override
  String toString() => message;
}

class DnsScannerService {
  static const knownProviders = <String, String>{
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
    '223.5.5.5': 'AliDNS',
    '223.6.6.6': 'AliDNS',
  };
  static const defaultServers = <String>[
    '1.1.1.1',
    '1.0.0.1',
    '8.8.8.8',
    '8.8.4.4',
    '9.9.9.9',
    '149.112.112.112',
    '208.67.222.222',
    '208.67.220.220',
    '94.140.14.14',
    '94.140.15.15',
    '76.76.2.0',
    '76.76.10.0',
    '4.2.2.1',
    '4.2.2.2',
    '84.200.69.80',
    '84.200.70.40',
    '77.88.8.8',
    '77.88.8.1',
    '156.154.70.1',
    '156.154.71.1',
    '8.26.56.26',
    '8.20.247.20',
    '185.228.168.9',
    '185.228.169.9',
    '64.6.64.6',
    '64.6.65.6',
    '45.90.28.0',
    '45.90.30.0',
    '223.5.5.5',
    '223.6.6.6',
    '114.114.114.114',
    '101.101.101.101',
  ];
  static const maxTargets = 200000, maxParallel = 64;

  Future<List<DnsScanResult>> scan({
    List<String>? servers,
    String domain = 'google.com',
    int parallel = 100,
  }) async {
    final targets = expandTargets(servers ?? defaultServers);
    _validateDomain(domain);
    return _scanChunk(targets, domain, parallel);
  }

  Future<List<DnsScanResult>> _scanChunk(
    List<String> targets,
    String domain,
    int parallel,
  ) async {
    final raw = await DnsVpnConnection.scanDns(
      targets,
      domain: domain,
      parallel: parallel.clamp(1, maxParallel),
    );
    if (raw == null)
      throw const DnsScanUnavailableException(
        'DNS scanning is not supported on this platform.',
      );
    try {
      final list = jsonDecode(raw);
      if (list is! List)
        throw const FormatException('Unexpected scanner response');
      return list
          .map(
            (e) => DnsScanResult.fromJson(
              e as Map<String, dynamic>,
              name: knownProviders[e['ip']],
            ),
          )
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to parse DNS scan result: $e');
      throw const DnsScanUnavailableException(
        'The DNS scanner returned an invalid response.',
      );
    }
  }

  static int? parseIp(String ip) {
    final p = ip.trim().split('.');
    if (p.length != 4) return null;
    var n = 0;
    for (final s in p) {
      if (!RegExp(r'^\d{1,3}').hasMatch('$s')) {}
      final x = int.tryParse(s);
      if (x == null || x < 0 || x > 255 || s.isEmpty) return null;
      n = (n << 8) | x;
    }
    return n & 0xffffffff;
  }

  static String _intToIp(int v) =>
      '${(v >> 24) & 255}.${(v >> 16) & 255}.${(v >> 8) & 255}.${v & 255}';
  static int _limit(int max) =>
      max < 0 ? 0 : (max > maxTargets ? maxTargets : max);
  static List<String> generateRange(
    String fromIp,
    String toIp, {
    int max = maxTargets,
  }) {
    final a = parseIp(fromIp), b = parseIp(toIp), lim = _limit(max);
    if (a == null || b == null || lim == 0) return [];
    final lo = a < b ? a : b, hi = a < b ? b : a, out = <String>[];
    for (var v = lo; v <= hi && out.length < lim; v++) out.add(_intToIp(v));
    return out;
  }

  static List<String> generateCidr(String cidr, {int max = maxTargets}) {
    final p = cidr.trim().split('/');
    final base = p.length == 2 ? parseIp(p[0]) : null;
    final bits = p.length == 2 ? int.tryParse(p[1]) : null;
    final lim = _limit(max);
    if (base == null || bits == null || bits < 0 || bits > 32 || lim == 0)
      return [];
    final network = bits == 0
            ? 0
            : base & ((0xffffffff << (32 - bits)) & 0xffffffff),
        size = bits == 32 ? 1 : 1 << (32 - bits),
        exclude = bits < 31;
    final first = exclude ? 1 : 0,
        last = exclude ? size - 2 : size - 1,
        out = <String>[];
    for (var i = first; i <= last && out.length < lim; i++)
      out.add(_intToIp(network + i));
    return out;
  }

  /// Parses IPs and CIDRs; invalid entries are rejected, never silently dropped.
  static List<String> expandTargets(
    Iterable<String> entries, {
    int max = maxTargets,
  }) {
    final lim = _limit(max);
    if (lim == 0) return [];
    final out = <String>[], seen = <String>{};
    for (final raw in entries) {
      for (final token
          in raw.split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty)) {
        final value = token.contains('/')
            ? generateCidr(token, max: lim)
            : (parseIp(token) != null ? [token.trim()] : <String>[]);
        if (value.isEmpty) throw FormatException('Invalid IP or CIDR: $token');
        for (final ip in value) {
          if (seen.add(ip) && out.length < lim) out.add(ip);
        }
      }
    }
    return out;
  }

  static bool _public(int v) {
    final a = (v >> 24) & 255, b = (v >> 16) & 255, c = (v >> 8) & 255;
    if (a == 0 ||
        a == 10 ||
        a == 127 ||
        a >= 224 ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 192 && b == 0) ||
        (a == 192 && b == 2) ||
        (a == 198 && (b == 18 || b == 19 || b == 51)) ||
        (a == 203 && b == 0 && c == 113) ||
        (a == 198 && b == 100))
      return false;
    return true;
  }

  static List<String> generateRandom(int count, {int? seed}) {
    final wanted = count.clamp(0, maxTargets), out = <String>{};
    if (wanted == 0) return [];
    var state = (seed ?? DateTime.now().microsecondsSinceEpoch) & 0x7fffffff;
    if (state == 0) state = 0x2545f491;
    int next() {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      return state & 0xffffffff;
    }

    var guard = wanted * 80 + 1000;
    while (out.length < wanted && guard-- > 0) {
      final v = next();
      final x = (next() << 8 | next()) & 0xffffffff;
      final ip = (v ^ x) & 0xffffffff;
      if (_public(ip)) out.add(_intToIp(ip));
    }
    return out.toList();
  }

  static void _validateDomain(String domain) {
    final d = domain.trim();
    if (d.isEmpty ||
        d.length > 253 ||
        d.contains(RegExp(r'[^A-Za-z0-9.\-_]')) ||
        d.startsWith('.') ||
        d.endsWith('.'))
      throw const FormatException(
        'Enter a valid DNS probe domain, not an IP or URL.',
      );
  }

  Future<List<DnsScanResult>> scanRange({
    required List<String> targets,
    String domain = 'google.com',
    int parallel = 100,
    int chunkSize = 128,
    void Function(int, int)? onProgress,
    void Function(List<DnsScanResult>)? onFound,
    bool Function()? isCancelled,
  }) async {
    _validateDomain(domain);
    final all = expandTargets(targets), found = <DnsScanResult>[];
    final wave = chunkSize.clamp(1, maxParallel),
        p = parallel.clamp(1, maxParallel);
    var scanned = 0;
    for (var i = 0; i < all.length; i += wave) {
      if (isCancelled?.call() == true) break;
      final part = all.sublist(i, (i + wave).clamp(0, all.length));
      final res = await _scanChunk(part, domain, p);
      if (isCancelled?.call() == true) break;
      final good = res.where((r) => r.reachable).toList();
      found.addAll(good);
      if (good.isNotEmpty) onFound?.call(good);
      scanned += part.length;
      onProgress?.call(scanned, all.length);
    }
    found.sort(_compare);
    return found;
  }

  static int _compare(DnsScanResult a, DnsScanResult b) {
    if (a.isCandidate != b.isCandidate) return a.isCandidate ? -1 : 1;
    if (a.reachable != b.reachable) return a.reachable ? -1 : 1;
    return (a.bestMs < 0 ? 1 << 30 : a.bestMs).compareTo(
      b.bestMs < 0 ? 1 << 30 : b.bestMs,
    );
  }
}
