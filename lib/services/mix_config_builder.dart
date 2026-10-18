import 'dart:convert';
import 'dart:io';
import '../models/dns_server.dart';
import '../models/mix_strategy.dart';
import '../models/proxy_server.dart';
import '../models/xray_server.dart';
import 'xray_config_builder.dart';

/// Compiles an ordered chain into ONE core / ONE Android VpnService.
/// The exit is the default outbound; its socket dials through the preceding
/// hop recursively. There is deliberately no direct/fallback outbound or LAN
/// bypass rule. Standalone config builders and saved selections are untouched.
class MixConfigBuilder {
  static String build({
    required MixStrategy strategy,
    required List<XrayServer> xrayServers,
    required List<ProxyServer> proxyServers,
    required List<DnsServer> dnsServers,
    bool delayTest = false,
  }) {
    final error = strategy.validationError;
    if (error != null) throw FormatException(error);
    final tunnels = <Map<String, dynamic>>[];
    DnsServer? resolver;
    Map<String, dynamic>? base;
    var tcpOnly = false;
    for (final hop in strategy.hops) {
      if (hop.protocol == 'direct_dns') {
        resolver = _choose<DnsServer>(
          dnsServers,
          (server) => server.primaryDns == hop.serverId,
          'The selected DNS server was removed. Edit this strategy.',
        );
        continue;
      }
      late String standalone;
      String? httpsProxyHost;
      if (hop.protocol == 'xray') {
        final server = _choose(
          xrayServers,
          (server) => hop.group != null
              ? server.group == hop.group
              : server.id == hop.serverId,
          'An Xray server/group is missing. Edit this strategy.',
        );
        standalone = XrayConfigBuilder.build(server, fragmentEnabled: false);
      } else if (hop.protocol == 'proxy') {
        final server = _choose(
          proxyServers,
          (server) => hop.group != null
              ? server.group == hop.group
              : server.id == hop.serverId,
          'A proxy server/group is missing. Edit this strategy.',
        );
        // The standalone builder historically maps SOCKS4 to SOCKS5. Do not
        // change its behavior here, and never misrepresent SOCKS4 in Mix.
        if (server.protocol != 'socks5' && server.protocol != 'http') {
          throw const FormatException(
            'Mix supports SOCKS5 and HTTP proxies, not SOCKS4.',
          );
        }
        tcpOnly = tcpOnly || server.protocol == 'http';
        if (server.link.toLowerCase().startsWith('https://')) {
          httpsProxyHost = server.address;
        }
        standalone = XrayConfigBuilder.buildForProxyServer(server);
      } else {
        throw FormatException(
          MixStrategy.unavailableReason(hop.protocol) ??
              'Unsupported Mix block.',
        );
      }
      final decoded = jsonDecode(standalone) as Map<String, dynamic>;
      base ??= decoded;
      final outbound = Map<String, dynamic>.from(
        (decoded['outbounds'] as List).first as Map,
      );
      final index = tunnels.length;
      outbound['tag'] = 'mix-hop-$index';
      final stream = Map<String, dynamic>.from(
        outbound['streamSettings'] as Map? ?? {},
      );
      if (httpsProxyHost != null) {
        stream['security'] = 'tls';
        stream['tlsSettings'] = {
          'serverName': httpsProxyHost,
          'allowInsecure': false,
        };
      }
      final sockopt = Map<String, dynamic>.from(
        stream['sockopt'] as Map? ?? {},
      );
      if (index > 0) sockopt['dialerProxy'] = 'mix-hop-${index - 1}';
      // AsIs hands inner server names to the previous hop instead of resolving
      // them on the physical connection. Only the first hop needs bootstrap DNS.
      sockopt['domainStrategy'] = 'AsIs';
      stream['sockopt'] = sockopt;
      outbound['streamSettings'] = stream;
      tunnels.add(outbound);
    }
    if (base == null || tunnels.isEmpty) {
      throw const FormatException('A tunnel block is required.');
    }
    // Keep the existing native traffic counter's tag for the exit only.
    tunnels.last['tag'] = 'proxy';
    final outbounds = <Map<String, dynamic>>[
      tunnels.last,
      ...tunnels.take(tunnels.length - 1),
    ];
    final dnsAddress = resolver?.primaryDns ?? '1.1.1.1';
    final address = InternetAddress.tryParse(dnsAddress);
    if (address == null) {
      throw const FormatException('Mix DNS must be an IP address.');
    }
    outbounds.add({
      'tag': 'mix-dns',
      'protocol': 'dns',
      // All query types are forwarded, not just A/AAAA. UDP DNS from apps is
      // framed as TCP before entering the exit, so HTTP hops also carry DNS.
      'settings': {
        'rewriteNetwork': 'tcp',
        'rewriteAddress': dnsAddress,
        'rewritePort': 53,
        'rules': [
          {'action': 'direct'},
        ],
      },
      'streamSettings': {
        'sockopt': {'dialerProxy': 'proxy', 'domainStrategy': 'AsIs'},
      },
    });
    if (tcpOnly) {
      outbounds.add({'tag': 'mix-udp-block', 'protocol': 'blackhole'});
    }
    base['outbounds'] = outbounds;
    base['dns'] = {
      'servers': [
        'tcp://${address.type == InternetAddressType.IPv6 ? '[$dnsAddress]' : dnsAddress}',
      ],
      'tag': 'mix-resolver',
    };
    base['routing'] = {
      'domainStrategy': 'AsIs',
      'rules': [
        {
          'type': 'field',
          'port': '53',
          'network': 'tcp,udp',
          'outboundTag': 'mix-dns',
        },
        if (tcpOnly)
          {'type': 'field', 'network': 'udp', 'outboundTag': 'mix-udp-block'},
        {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'proxy'},
      ],
    };
    if (delayTest) base.remove('inbounds');
    return jsonEncode(base);
  }

  /// Groups resolve deterministically in stored order. No separate direct
  /// ping races are launched: the caller probes the ENTIRE compiled chain.
  static T _choose<T>(List<T> values, bool Function(T) matches, String error) {
    for (final value in values) {
      if (matches(value)) return value;
    }
    throw FormatException(error);
  }
}
