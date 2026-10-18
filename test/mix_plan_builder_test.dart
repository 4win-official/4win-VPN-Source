import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/dns_server.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/services/mix_plan_builder.dart';

void main() {
  final proxy = ProxyServer(
    id: 'p1', remark: 'proxy', link: 'socks5://127.0.0.1:1080',
    protocol: 'socks5', address: '127.0.0.1', port: 1080,
  );
  test('builds a logical plan without local listener ports', () {
    final plan = MixPlanBuilder.build(
      strategy: MixStrategy(id: 'm', name: 'mix', hops: const [
        MixHop(protocol: 'proxy', serverId: 'p1'),
      ]),
      proxyServers: [proxy],
    );
    expect(plan['version'], 1);
    expect((plan['hops'] as List).single['protocol'], 'proxy');
    expect(plan['baseConfig'], isA<Map<String, dynamic>>());
  });

  test('keeps DNS out of hops and resolves it into plan DNS', () {
    final plan = MixPlanBuilder.build(
      strategy: MixStrategy(id: 'm', name: 'mix', hops: const [
        MixHop(protocol: 'proxy', serverId: 'p1'),
        MixHop(protocol: 'direct_dns', serverId: '9.9.9.9'),
      ]),
      proxyServers: [proxy],
      dnsServers: [DnsServer(name: 'quad9', primaryDns: '9.9.9.9', description: '', country: '')],
    );
    expect(plan['dns'], '9.9.9.9');
    expect((plan['hops'] as List).length, 1);
  });
}
