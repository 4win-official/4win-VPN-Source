import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/mix_strategy.dart';

MixStrategy strategy(List<MixHop> hops) =>
    MixStrategy(id: 'mix', name: 'Test strategy', hops: hops);

MixHop tunnel(String id) => MixHop(protocol: 'xray', serverId: id);
MixHop dns(String ip) => MixHop(protocol: 'direct_dns', serverId: ip);

void main() {
  test('accepts exactly 50 blocks and rejects 51', () {
    expect(
      strategy(
        List.generate(49, (i) => tunnel('s$i'))..add(dns('9.9.9.9')),
      ).validationError,
      isNull,
    );
    expect(
      strategy(
        List.generate(50, (i) => tunnel('s$i'))..add(tunnel('s50')),
      ).validationError,
      'At most 50 blocks are supported.',
    );
  });

  test('DNS can be first, middle, repeated, and reordered', () {
    final hops = [
      dns('1.1.1.1'),
      tunnel('a'),
      dns('9.9.9.9'),
      tunnel('b'),
      dns('1.1.1.1'),
    ];
    expect(strategy(hops).validationError, isNull);
    expect(strategy(hops).hops.map((h) => h.serverId), [
      '1.1.1.1',
      'a',
      '9.9.9.9',
      'b',
      '1.1.1.1',
    ]);
  });

  test('DNS requires a server IP reference and never counts as a tunnel', () {
    expect(strategy([dns('9.9.9.9')]).validationError, isNotNull);
    expect(
      strategy([
        const MixHop(protocol: 'direct_dns', group: 'resolvers'),
        tunnel('a'),
      ]).validationError,
      isNotNull,
    );
    expect(MixStrategy.unavailableReason('slowdns'), isNotNull);
  });
}
