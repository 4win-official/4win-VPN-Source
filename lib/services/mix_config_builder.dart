import 'dart:convert';
import 'dart:io';
import '../models/dns_server.dart';
import '../models/mix_block_exception.dart';
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
    // A resolver is a boundary in the ordered plan, not a VPN transport.
    // Each boundary retains its preceding tunnel prefix. The last policy is
    // effective for app DNS; earlier policies remain scoped to their prefixes.
    final dnsPolicies = <({String address, int prefixLength})>[];
    // DNS-only Mix is a resolver configuration, not an encrypted tunnel. Keep
    // the normal TUN shape, but use a direct freedom outbound for non-DNS
    // traffic when there are no transport blocks.
    final dummy = ProxyServer(
      id: '__mix_dummy__',
      remark: 'Mix',
      link: 'socks5://127.0.0.1:1',
      protocol: 'socks5',
      address: '127.0.0.1',
      port: 1,
    );
    Map<String, dynamic> base =
        jsonDecode(XrayConfigBuilder.buildForProxyServer(dummy))
            as Map<String, dynamic>;
    var tcpOnly = false;
    for (var hopIndex = 0; hopIndex < strategy.hops.length; hopIndex++) {
      final hop = strategy.hops[hopIndex];
      try {
        if (hop.protocol == 'direct_dns') {
          final resolver = _choose<DnsServer>(
            dnsServers,
            (server) => server.primaryDns == hop.serverId,
            'The selected DNS server was removed. Edit this strategy.',
          );
          if (InternetAddress.tryParse(resolver.primaryDns) == null) {
            throw const FormatException('Mix DNS must be an IP address.');
          }
          dnsPolicies.add((
            address: resolver.primaryDns,
            prefixLength: tunnels.length,
          ));
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
        if (tunnels.isEmpty) base = decoded;
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
      } catch (error, stackTrace) {
        throw MixBlockException(hopIndex, error, stackTrace: stackTrace);
      }
    }
    // Keep the existing native traffic counter's tag for the exit only.
    final List<Map<String, dynamic>> outbounds;
    if (tunnels.isEmpty) {
      outbounds = [
        {
          'tag': 'proxy',
          'protocol': 'freedom',
          'settings': <String, dynamic>{},
          'streamSettings': {
            'sockopt': {'domainStrategy': 'AsIs'},
          },
        },
      ];
    } else {
      tunnels.last['tag'] = 'proxy';
      outbounds = [tunnels.last, ...tunnels.take(tunnels.length - 1)];
    }
    if (dnsPolicies.isEmpty) {
      dnsPolicies.add((address: '1.1.1.1', prefixLength: tunnels.length));
    }
    final dnsAddress = dnsPolicies.last.address;
    final address = InternetAddress.tryParse(dnsAddress);
    if (address == null) {
      throw const FormatException('Mix DNS must be an IP address.');
    }
    for (var i = 0; i < dnsPolicies.length; i++) {
      final policy = dnsPolicies[i];
      final prefix = policy.prefixLength;
      outbounds.add({
        'tag': i == dnsPolicies.length - 1 ? 'mix-dns' : 'mix-dns-policy-$i',
        'protocol': 'dns',
        // DNS leaves at its selected boundary, not at the final tunnel.
        // A DNS block before every tunnel intentionally uses the physical link.
        'settings': {
          'network': 'tcp',
          'address': policy.address,
          'port': 53,
          'nonIPQuery': 'skip',
        },
        'streamSettings': {
          'sockopt': {
            if (prefix > 0)
              'dialerProxy': prefix == tunnels.length
                  ? 'proxy'
                  : 'mix-hop-${prefix - 1}',
            'domainStrategy': 'AsIs',
          },
        },
      });
    }
    // A/AAAA are resolved by Xray's global DNS client, not by the DNS
    // outbound's address. Route that client's own queries explicitly to the
    // selected boundary; otherwise the default exit would move DNS to the end.
    final dnsPrefix = dnsPolicies.last.prefixLength;
    outbounds.add({
      'tag': 'mix-dns-transport',
      'protocol': 'freedom',
      'settings': {},
      'streamSettings': {
        'sockopt': {
          if (dnsPrefix > 0)
            'dialerProxy': dnsPrefix == tunnels.length
                ? 'proxy'
                : 'mix-hop-${dnsPrefix - 1}',
          'domainStrategy': 'AsIs',
        },
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
          'inboundTag': ['mix-resolver'],
          'outboundTag': 'mix-dns-transport',
        },
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
