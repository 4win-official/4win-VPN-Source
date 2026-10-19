import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/dns_server.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/models/sstp_server_group.dart';
import 'package:vpn_swift/models/vpn_server.dart';
import 'package:vpn_swift/services/mix_plan_builder.dart';

void main() {
  final proxy = ProxyServer(
    id: 'p1',
    remark: 'proxy',
    link: 'socks5://127.0.0.1:1080',
    protocol: 'socks5',
    address: '127.0.0.1',
    port: 1080,
  );
  final first = VpnServer(
    address: 'same.example',
    port: 443,
    username: 'first',
  );
  final second = VpnServer(
    address: 'same.example',
    port: 443,
    username: 'second',
  );
  final groups = [
    SstpServerGroup(id: 'default', name: 'Default', servers: [first]),
    SstpServerGroup(id: 'custom', name: 'Custom', servers: [second]),
  ];
  Map<String, dynamic> sstpPlan(MixHop hop) => MixPlanBuilder.build(
    strategy: MixStrategy(id: 'sstp', name: 'SSTP', hops: [hop]),
    sstpGroups: groups,
  );

  test('SSTP group resolves its own server and credentials', () {
    final plan = sstpPlan(const MixHop(protocol: 'sstp', group: 'custom'));
    final config = (plan['hops'] as List).single['config'];
    expect(config['host'], 'same.example');
    expect(config['username'], 'second');
  });
  test('SSTP manual server is scoped to its retained group', () {
    final plan = sstpPlan(
      const MixHop(
        protocol: 'sstp',
        serverId: 'same.example:443',
        group: 'custom',
      ),
    );
    expect((plan['hops'] as List).single['config']['username'], 'second');
  });
  test('removed SSTP group and missing member never fall back', () {
    expect(
      () => sstpPlan(
        const MixHop(
          protocol: 'sstp',
          serverId: 'same.example:443',
          group: 'deleted',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => sstpPlan(
        const MixHop(
          protocol: 'sstp',
          serverId: 'removed.example:443',
          group: 'custom',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => sstpPlan(const MixHop(protocol: 'sstp', group: 'deleted')),
      throwsFormatException,
    );
  });
  test('legacy address-only SSTP references remain supported', () {
    final plan = MixPlanBuilder.buildPlan(
      strategy: MixStrategy(
        id: 'legacy',
        name: 'Legacy',
        hops: const [MixHop(protocol: 'sstp', serverId: 'same.example:443')],
      ),
      sstpServers: [first],
    );
    expect((plan['hops'] as List).single['config']['username'], 'first');
  });
  test('buildPlan forwards SSTP groups', () {
    final plan = MixPlanBuilder.buildPlan(
      strategy: MixStrategy(
        id: 'alias',
        name: 'Alias',
        hops: const [MixHop(protocol: 'sstp', group: 'custom')],
      ),
      sstpGroups: groups,
    );
    expect((plan['hops'] as List).single['config']['username'], 'second');
  });

  test('builds a logical plan without local listener ports', () {
    final plan = MixPlanBuilder.build(
      strategy: MixStrategy(
        id: 'm',
        name: 'mix',
        hops: const [MixHop(protocol: 'proxy', serverId: 'p1')],
      ),
      proxyServers: [proxy],
    );
    expect(plan['version'], 1);
    expect((plan['hops'] as List).single['protocol'], 'proxy');
    expect(plan['baseConfig'], isA<Map<String, dynamic>>());
  });

  test('retains DNS in exact block order and resolves its address', () {
    final plan = MixPlanBuilder.build(
      strategy: MixStrategy(
        id: 'm',
        name: 'mix',
        hops: const [
          MixHop(protocol: 'proxy', serverId: 'p1'),
          MixHop(protocol: 'direct_dns', serverId: '9.9.9.9'),
        ],
      ),
      proxyServers: [proxy],
      dnsServers: [
        DnsServer(
          name: 'quad9',
          primaryDns: '9.9.9.9',
          description: '',
          country: '',
        ),
      ],
    );
    expect(plan['dns'], '9.9.9.9');
    expect((plan['hops'] as List).map((h) => h['protocol']), [
      'proxy',
      'direct_dns',
    ]);
    expect((plan['hops'] as List).last['address'], '9.9.9.9');
  });
  test('DNS first, middle and repeated are never moved or dropped', () {
    final blocks = [
      const MixHop(protocol: 'direct_dns', serverId: '9.9.9.9'),
      const MixHop(protocol: 'proxy', serverId: 'p1'),
      const MixHop(protocol: 'direct_dns', serverId: '1.1.1.1'),
      const MixHop(protocol: 'proxy', serverId: 'p1'),
    ];
    final plan = MixPlanBuilder.build(
      strategy: MixStrategy(id: 'm', name: 'mix', hops: blocks),
      proxyServers: [proxy],
      dnsServers: ['9.9.9.9', '1.1.1.1']
          .map(
            (address) => DnsServer(
              name: address,
              primaryDns: address,
              description: '',
              country: '',
            ),
          )
          .toList(),
    );
    expect(
      (plan['hops'] as List).map((h) => h['protocol']),
      blocks.map((h) => h.protocol),
    );
    expect(plan['dns'], '1.1.1.1');
  });
  test('native plan preserves an ordered 50-block chain and final DNS', () {
    final blocks = <MixHop>[];
    final dnsAddresses = <String>[];
    for (var i = 0; i < 50; i++) {
      if (i.isEven) {
        final address = i % 4 == 0 ? '9.9.9.9' : '1.1.1.1';
        dnsAddresses.add(address);
        blocks.add(MixHop(protocol: 'direct_dns', serverId: address));
      } else {
        blocks.add(const MixHop(protocol: 'proxy', serverId: 'p1'));
      }
    }
    final plan = MixPlanBuilder.build(
      strategy: MixStrategy(id: 'ordered', name: 'Ordered', hops: blocks),
      proxyServers: [proxy],
      dnsServers: [
        for (final address in {'9.9.9.9', '1.1.1.1'})
          DnsServer(
            name: address,
            primaryDns: address,
            description: '',
            country: '',
          ),
      ],
    );
    expect(plan['hops'], hasLength(50));
    expect(
      (plan['hops'] as List).map((hop) => hop['protocol']),
      blocks.map((hop) => hop.protocol),
    );
    expect(plan['dns'], dnsAddresses.last);
  });

  test(
    'Slow DNS remains excluded while supported Mix protocols are listed',
    () {
      expect(MixStrategy.protocols.containsKey('slowdns'), isFalse);
      expect(MixStrategy.unavailableReason('slowdns'), isNotNull);
    },
  );

  test('plan accepts 50 blocks and rejects 51 before execution', () {
    Map<String, dynamic> build(int length) => MixPlanBuilder.build(
      strategy: MixStrategy(
        id: 'm',
        name: 'mix',
        hops: List.generate(
          length,
          (_) => const MixHop(protocol: 'proxy', serverId: 'p1'),
        ),
      ),
      proxyServers: [proxy],
    );
    expect(build(50)['hops'], hasLength(50));
    expect(() => build(51), throwsFormatException);
  });
}
