import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/dns_server.dart';
import 'package:vpn_swift/models/mix_block_exception.dart';
import 'package:vpn_swift/models/mix_strategy.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/services/mix_config_builder.dart';
import 'package:vpn_swift/services/mix_plan_builder.dart';

class _UnprintableError {
  @override
  String toString() => throw StateError('toString failed');
}

void main() {
  final proxy = ProxyServer(
    id: 'proxy',
    remark: 'proxy',
    link: 'socks5://127.0.0.1:1080',
    protocol: 'socks5',
    address: '127.0.0.1',
    port: 1080,
  );
  final dns = DnsServer(
    name: 'DNS',
    primaryDns: '9.9.9.9',
    description: '',
    country: '',
  );

  test(
    'message and toString stay safe for an error with a throwing toString',
    () {
      final error = MixBlockException(3, _UnprintableError());
      expect(error.index, 3);
      expect(error.blockIndex, 3);
      expect(error.hopIndex, 3);
      expect(error.message, 'Unknown Mix block error.');
      expect(error.toString(), 'Mix block 4 failed: Unknown Mix block error.');
    },
  );

  test(
    'config builder reports the configured index, including repeated DNS blocks',
    () {
      final strategy = MixStrategy(
        id: 'mix',
        name: 'mix',
        hops: const [
          MixHop(protocol: 'direct_dns', serverId: '9.9.9.9'),
          MixHop(protocol: 'proxy', serverId: 'proxy'),
          MixHop(protocol: 'direct_dns', serverId: 'missing'),
        ],
      );
      expect(
        () => MixConfigBuilder.build(
          strategy: strategy,
          xrayServers: const [],
          proxyServers: [proxy],
          dnsServers: [dns],
        ),
        throwsA(isA<MixBlockException>().having((e) => e.index, 'index', 2)),
      );
    },
  );

  test(
    'plan builder reports the exact failing hop in a self-repeated chain',
    () {
      final strategy = MixStrategy(
        id: 'mix',
        name: 'mix',
        hops: const [
          MixHop(protocol: 'proxy', serverId: 'proxy'),
          MixHop(protocol: 'proxy', serverId: 'missing'),
          MixHop(protocol: 'proxy', serverId: 'proxy'),
        ],
      );
      expect(
        () => MixPlanBuilder.build(strategy: strategy, proxyServers: [proxy]),
        throwsA(isA<MixBlockException>().having((e) => e.index, 'index', 1)),
      );
    },
  );
}
