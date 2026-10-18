import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/dns_server.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/models/xray_server.dart';
import 'package:vpn_swift/services/mix_config_builder.dart';
import 'package:vpn_swift/services/xray_config_builder.dart';

void main() {
  final first = XrayServer.fromLink(
    'vless://11111111-1111-1111-1111-111111111111@192.0.2.1:443?security=tls&sni=first.test#First',
  );
  final second = XrayServer.fromLink(
    'trojan://password@192.0.2.2:443?security=tls&sni=second.test#Second',
  );
  final proxy = ProxyServer.fromLink('socks5://user:pass@192.0.2.3:1080');
  final http = ProxyServer.fromLink('http://192.0.2.4:8080');
  final dns = DnsServer(
    name: 'Resolver',
    primaryDns: '9.9.9.9',
    description: '',
    country: '',
  );
  MixStrategy strategy(List<MixHop> hops) =>
      MixStrategy(id: 's', name: 'Test', hops: hops);
  Map<String, dynamic> compile(
    List<MixHop> hops, {
    bool delayTest = false,
    List<ProxyServer>? proxies,
  }) =>
      jsonDecode(
            MixConfigBuilder.build(
              strategy: strategy(hops),
              xrayServers: [first, second],
              proxyServers: proxies ?? [proxy, http],
              dnsServers: [dns],
              delayTest: delayTest,
            ),
          )
          as Map<String, dynamic>;

  test('strategy JSON round-trips and owns an immutable hop list', () {
    final hops = [MixHop(protocol: 'xray', serverId: first.id)];
    final value = strategy(hops);
    hops.clear();
    expect(value.hops, hasLength(1));
    expect(() => value.hops.clear(), throwsUnsupportedError);
    expect(
      MixStrategy.fromJson(jsonDecode(jsonEncode(value.toJson()))).toJson(),
      value.toJson(),
    );
  });
  test('empty, unknown, unselected and ambiguous blocks fail validation', () {
    expect(strategy([]).validationError, isNotNull);
    expect(
      strategy([const MixHop(protocol: 'unknown')]).validationError,
      isNotNull,
    );
    expect(
      strategy([const MixHop(protocol: 'xray')]).validationError,
      isNotNull,
    );
    expect(
      strategy([
        const MixHop(protocol: 'xray', serverId: 'a', group: 'b'),
      ]).validationError,
      isNotNull,
    );
  });
  test(
    'legacy Xray compiler rejects native plans rather than skipping blocks',
    () {
      for (final protocol in [
        'warp',
        'sstp',
        'openvpn',
        'slowdns',
        'psiphon',
      ]) {
        expect(
          MixStrategy.unavailableReason(protocol),
          protocol == 'slowdns' ? isNotNull : isNull,
        );
        expect(
          () => compile([MixHop(protocol: protocol, serverId: 'a')]),
          throwsFormatException,
        );
      }
    },
  );
  test('DNS may occupy any position but is not a standalone tunnel', () {
    final dnsHop = MixHop(protocol: 'direct_dns', serverId: dns.primaryDns);
    expect(strategy([dnsHop]).validationError, isNotNull);
    expect(
      strategy([
        dnsHop,
        MixHop(protocol: 'xray', serverId: first.id),
      ]).validationError,
      isNull,
    );
    expect(
      strategy([
        MixHop(protocol: 'xray', serverId: first.id),
        dnsHop,
      ]).validationError,
      isNull,
    );
  });
  test('single tunnel has no dangling previous-hop reference', () {
    final config = compile([MixHop(protocol: 'xray', serverId: first.id)]);
    final exit = (config['outbounds'] as List).first;
    expect(exit['tag'], 'proxy');
    expect(exit['streamSettings']['sockopt']['dialerProxy'], isNull);
    expect(
      (config['inbounds'] as List).where(
        (inbound) => inbound['protocol'] == 'tun',
      ),
      hasLength(1),
    );
  });
  test(
    'three-hop chain points each socket to its PREVIOUS hop, exit is default',
    () {
      final config = compile([
        MixHop(protocol: 'xray', serverId: first.id),
        MixHop(protocol: 'proxy', serverId: proxy.id),
        MixHop(protocol: 'xray', serverId: second.id),
      ]);
      final outbounds = config['outbounds'] as List;
      final byTag = {
        for (final outbound in outbounds) outbound['tag']: outbound,
      };
      expect(outbounds.first['tag'], 'proxy');
      expect(byTag['proxy']['protocol'], 'trojan');
      expect(
        byTag['proxy']['streamSettings']['sockopt']['dialerProxy'],
        'mix-hop-1',
      );
      expect(byTag['mix-hop-1']['protocol'], 'socks');
      expect(
        byTag['mix-hop-1']['streamSettings']['sockopt']['dialerProxy'],
        'mix-hop-0',
      );
      expect(
        byTag['mix-hop-0']['streamSettings']['sockopt']['dialerProxy'],
        isNull,
      );
      expect(byTag['mix-hop-0']['protocol'], 'vless');
      final rules = config['routing']['rules'] as List;
      expect(rules.last['outboundTag'], 'proxy');
      expect(rules.any((rule) => rule['outboundTag'] == 'direct'), isFalse);
      expect(outbounds.any((outbound) => outbound['tag'] == 'direct'), isFalse);
      expect(rules.any((rule) => rule.containsKey('ip')), isFalse);
    },
  );
  test('DNS queries use selected resolver over TCP INSIDE complete chain', () {
    final config = compile([
      MixHop(protocol: 'xray', serverId: first.id),
      MixHop(protocol: 'direct_dns', serverId: dns.primaryDns),
    ]);
    final dnsOutbound = (config['outbounds'] as List).singleWhere(
      (outbound) => outbound['tag'] == 'mix-dns',
    );
    expect(dnsOutbound['protocol'], 'dns');
    expect(dnsOutbound['settings']['network'], 'tcp');
    expect(dnsOutbound['settings']['address'], dns.primaryDns);
    expect(dnsOutbound['settings']['nonIPQuery'], 'skip');
    expect(dnsOutbound['streamSettings']['sockopt']['dialerProxy'], 'proxy');
    expect(config['dns']['servers'], ['tcp://9.9.9.9']);
    expect(config['routing']['rules'][1]['outboundTag'], 'mix-dns');
    expect(config['routing']['rules'].first['inboundTag'], ['mix-resolver']);
    expect(jsonEncode(config['dns']), isNot(contains('localhost')));
  });
  test('DNS in the middle exits through only its preceding tunnel prefix', () {
    final config = compile([
      MixHop(protocol: 'xray', serverId: first.id),
      MixHop(protocol: 'direct_dns', serverId: dns.primaryDns),
      MixHop(protocol: 'proxy', serverId: proxy.id),
      MixHop(protocol: 'xray', serverId: second.id),
    ]);
    final outbounds = config['outbounds'] as List;
    final resolver = outbounds.singleWhere((o) => o['tag'] == 'mix-dns');
    expect(resolver['streamSettings']['sockopt']['dialerProxy'], 'mix-hop-0');
    expect(
      outbounds.singleWhere(
        (o) => o['tag'] == 'mix-dns-transport',
      )['streamSettings']['sockopt']['dialerProxy'],
      'mix-hop-0',
    );
    expect(
      outbounds.first['streamSettings']['sockopt']['dialerProxy'],
      'mix-hop-1',
    );
    expect(
      outbounds.singleWhere(
        (o) => o['tag'] == 'mix-hop-1',
      )['streamSettings']['sockopt']['dialerProxy'],
      'mix-hop-0',
    );
  });
  test('DNS first intentionally resolves before the first tunnel', () {
    final config = compile([
      MixHop(protocol: 'direct_dns', serverId: dns.primaryDns),
      MixHop(protocol: 'xray', serverId: first.id),
    ]);
    final resolver = (config['outbounds'] as List).singleWhere(
      (o) => o['tag'] == 'mix-dns',
    );
    expect(
      resolver['streamSettings']['sockopt'].containsKey('dialerProxy'),
      isFalse,
    );
    expect(config['outbounds'].first['protocol'], 'vless');
  });
  test('repeated DNS policies retain their own selected prefixes', () {
    final config = compile([
      MixHop(protocol: 'direct_dns', serverId: dns.primaryDns),
      MixHop(protocol: 'xray', serverId: first.id),
      MixHop(protocol: 'direct_dns', serverId: dns.primaryDns),
      MixHop(protocol: 'proxy', serverId: proxy.id),
    ]);
    final policies = (config['outbounds'] as List)
        .where((o) => o['protocol'] == 'dns')
        .toList();
    expect(policies, hasLength(2));
    expect(policies.first['streamSettings']['sockopt']['dialerProxy'], isNull);
    expect(
      policies.last['streamSettings']['sockopt']['dialerProxy'],
      'mix-hop-0',
    );
    expect(config['routing']['rules'][1]['outboundTag'], 'mix-dns');
    expect(config['routing']['rules'].first['inboundTag'], ['mix-resolver']);
  });
  test('50 ordered tunnel blocks compile, 51 are rejected', () {
    final blocks = List.generate(
      50,
      (_) => MixHop(protocol: 'proxy', serverId: proxy.id),
    );
    final config = compile(blocks);
    expect(
      (config['outbounds'] as List).where((o) => o['protocol'] == 'socks'),
      hasLength(50),
    );
    expect(
      config['outbounds'].first['streamSettings']['sockopt']['dialerProxy'],
      'mix-hop-48',
    );
    expect(() => compile([...blocks, blocks.first]), throwsFormatException);
  });
  test('HTTP chain blocks unsupported UDP rather than bypassing any hop', () {
    final config = compile([
      MixHop(protocol: 'proxy', serverId: http.id),
      MixHop(protocol: 'xray', serverId: first.id),
    ]);
    final rules = config['routing']['rules'] as List;
    expect(rules[0]['outboundTag'], 'mix-dns-transport');
    expect(rules[1]['outboundTag'], 'mix-dns');
    expect(rules[2]['network'], 'udp');
    expect(rules[2]['outboundTag'], 'mix-udp-block');
    expect(
      (config['outbounds'] as List).singleWhere(
        (outbound) => outbound['tag'] == 'mix-udp-block',
      )['protocol'],
      'blackhole',
    );
  });
  test(
    'HTTPS proxy keeps TLS enabled in Mix without changing standalone builder',
    () {
      final https = ProxyServer.fromLink(
        'https://user:pass@secure.example:443',
      );
      final config = compile(
        [MixHop(protocol: 'proxy', serverId: https.id)],
        proxies: [https],
      );
      final stream = config['outbounds'].first['streamSettings'];
      expect(stream['security'], 'tls');
      expect(stream['tlsSettings']['serverName'], 'secure.example');
      expect(stream['tlsSettings']['allowInsecure'], isFalse);
    },
  );
  test('removed references and SOCKS4 are rejected before native start', () {
    expect(
      () => compile([const MixHop(protocol: 'xray', serverId: 'removed')]),
      throwsFormatException,
    );
    final socks4 = ProxyServer.fromLink('socks4://192.0.2.5:1080');
    expect(
      () => compile(
        [MixHop(protocol: 'proxy', serverId: socks4.id)],
        proxies: [socks4],
      ),
      throwsFormatException,
    );
    expect(
      () => compile([
        MixHop(protocol: 'xray', serverId: first.id),
        const MixHop(protocol: 'direct_dns', serverId: 'removed'),
      ]),
      throwsFormatException,
    );
  });
  test('a group resolves without changing its profile or selection', () {
    final grouped = first.copyWith(group: 'Group A');
    final config = jsonDecode(
      MixConfigBuilder.build(
        strategy: strategy([const MixHop(protocol: 'xray', group: 'Group A')]),
        xrayServers: [grouped],
        proxyServers: [],
        dnsServers: [],
      ),
    );
    expect(config['outbounds'].first['protocol'], 'vless');
    expect(grouped.group, 'Group A');
    expect(first.group, isNot('Group A'));
  });
  test('delay test has identical outbounds/routing but no system TUN', () {
    final hops = [
      MixHop(protocol: 'xray', serverId: first.id),
      MixHop(protocol: 'proxy', serverId: proxy.id),
    ];
    final vpn = compile(hops);
    final probe = compile(hops, delayTest: true);
    expect(probe['outbounds'], vpn['outbounds']);
    expect(probe['routing'], vpn['routing']);
    expect(probe.containsKey('inbounds'), isFalse);
  });
  test(
    'Mix compilation leaves standalone configs and profiles byte-for-byte unchanged',
    () {
      final originalXray = XrayConfigBuilder.build(first);
      final originalProxy = XrayConfigBuilder.buildForProxyServer(proxy);
      final profile = jsonEncode(first.toJson());
      compile([
        MixHop(protocol: 'xray', serverId: first.id),
        MixHop(protocol: 'proxy', serverId: proxy.id),
      ]);
      expect(XrayConfigBuilder.build(first), originalXray);
      expect(XrayConfigBuilder.buildForProxyServer(proxy), originalProxy);
      expect(jsonEncode(first.toJson()), profile);
    },
  );
}
