import 'dart:convert';

import '../models/dns_server.dart';
import '../models/mix_strategy.dart';
import '../models/openvpn_config.dart';
import '../models/proxy_server.dart';
import '../models/vpn_server.dart';
import '../models/warp_account.dart';
import '../models/xray_server.dart';
import 'xray_config_builder.dart';

/// Builds the in-memory logical plan consumed by the native multi-protocol
/// coordinator. References are resolved here, but the plan is never persisted.
class MixPlanBuilder {
  static Map<String, dynamic> build({
    required MixStrategy strategy,
    List<XrayServer> xrayServers = const [],
    List<ProxyServer> proxyServers = const [],
    List<VpnServer> sstpServers = const [],
    List<OpenVpnConfig> openVpnConfigs = const [],
    List<DnsServer> dnsServers = const [],
    WarpAccount? warpAccount,
  }) {
    final validation = strategy.validationError;
    if (validation != null) throw FormatException(validation);
    final hops = <Map<String, dynamic>>[];
    for (final hop in strategy.hops) {
      switch (hop.protocol) {
        case 'direct_dns':
          _findDns(hop, dnsServers);
          break;
        case 'xray':
          final s = _choose(
            xrayServers,
            hop,
            (v) => v.id,
            (v) => v.group,
            'Xray server/group',
          );
          final decoded = _decode(
            XrayConfigBuilder.build(s, fragmentEnabled: false),
          );
          hops.add({'protocol': 'xray', 'outbound': _firstOutbound(decoded)});
          break;
        case 'proxy':
          final s = _choose(
            proxyServers,
            hop,
            (v) => v.id,
            (v) => v.group,
            'proxy server/group',
          );
          if (s.protocol != 'socks5' && s.protocol != 'http') {
            throw const FormatException(
              'Mix supports SOCKS5 and HTTP proxies, not SOCKS4.',
            );
          }
          final decoded = _decode(XrayConfigBuilder.buildForProxyServer(s));
          final outbound = _firstOutbound(decoded);
          if (s.link.toLowerCase().startsWith('https://')) {
            outbound['streamSettings'] = {
              'security': 'tls',
              'tlsSettings': {'serverName': s.address, 'allowInsecure': false},
            };
          }
          hops.add({'protocol': 'proxy', 'outbound': outbound});
          break;
        case 'warp':
          if (hop.serverId != 'default') {
            throw const FormatException(
              'WARP Mix reference must be the default account.',
            );
          }
          final account = warpAccount;
          if (account == null) {
            throw const FormatException('No WARP account is registered.');
          }
          hops.add({
            'protocol': 'warp',
            'config': _decode(XrayConfigBuilder.buildForWarp(account)),
          });
          break;
        case 'psiphon':
          if (hop.serverId != 'default') {
            throw const FormatException(
              'Psiphon Mix reference must be the default profile.',
            );
          }
          hops.add({'protocol': 'psiphon', 'config': <String, dynamic>{}});
          break;
        case 'sstp':
          final s = _choose(
            sstpServers,
            hop,
            (v) => v.fullAddress,
            (_) => '',
            'SSTP server',
          );
          hops.add({
            'protocol': 'sstp',
            'config': {
              'host': s.address,
              'port': s.port,
              'username': s.username,
              'password': s.password,
              'verifyCertificate': true,
            },
          });
          break;
        case 'openvpn':
          final c = _choose(
            openVpnConfigs,
            hop,
            (v) => v.name,
            (_) => '',
            'OpenVPN config',
          );
          hops.add({
            'protocol': 'openvpn',
            'config': {
              'config': c.normalizedConfig,
              'username': c.effectiveUsername ?? '',
              'password': c.effectivePassword ?? '',
            },
          });
          break;
        default:
          throw FormatException('Unsupported Mix block: ${hop.protocol}');
      }
    }
    // Native allocates all local listeners. The base config only supplies the
    // TUN/stats shape and a harmless dummy SOCKS5 outbound.
    final dummy = ProxyServer(
      id: '__mix_dummy__',
      remark: 'Mix',
      link: 'socks5://127.0.0.1:1',
      protocol: 'socks5',
      address: '127.0.0.1',
      port: 1,
    );
    final base = _decode(XrayConfigBuilder.buildForProxyServer(dummy));
    final dnsHop = strategy.hops
        .where((h) => h.protocol == 'direct_dns')
        .toList();
    final dns = dnsHop.isEmpty
        ? '1.1.1.1'
        : (dnsHop.first.serverId ?? '1.1.1.1');
    return {'version': 1, 'hops': hops, 'dns': dns, 'baseConfig': base};
  }

  /// Named alias for callers that prefer the plan terminology.
  static Map<String, dynamic> buildPlan({
    required MixStrategy strategy,
    List<XrayServer> xrayServers = const [],
    List<ProxyServer> proxyServers = const [],
    List<VpnServer> sstpServers = const [],
    List<OpenVpnConfig> openVpnConfigs = const [],
    List<DnsServer> dnsServers = const [],
    WarpAccount? warpAccount,
  }) => build(
    strategy: strategy,
    xrayServers: xrayServers,
    proxyServers: proxyServers,
    sstpServers: sstpServers,
    openVpnConfigs: openVpnConfigs,
    dnsServers: dnsServers,
    warpAccount: warpAccount,
  );

  static Map<String, dynamic> _decode(String value) =>
      Map<String, dynamic>.from(jsonDecode(value) as Map);
  static Map<String, dynamic> _firstOutbound(Map<String, dynamic> config) =>
      Map<String, dynamic>.from((config['outbounds'] as List).first as Map);
  static T _choose<T>(
    List<T> values,
    MixHop hop,
    String Function(T) id,
    String Function(T) group,
    String label,
  ) {
    final found = hop.group != null
        ? values.where((v) => group(v) == hop.group).toList()
        : values.where((v) => id(v) == hop.serverId).toList();
    if (found.isEmpty) {
      throw FormatException('$label reference is missing. Edit this strategy.');
    }
    return found.first;
  }

  static DnsServer _findDns(MixHop hop, List<DnsServer> values) {
    final found = values.where((v) => v.primaryDns == hop.serverId).toList();
    if (found.isEmpty) {
      throw const FormatException(
        'DNS resolver reference is missing. Edit this strategy.',
      );
    }
    return found.first;
  }
}
