import 'dart:convert';
import 'package:vpn_swift/services/dns_vpn_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/services/dns_scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(DnsVpnConnection.platform, null),
  );

  test('parses capability fields and keeps tunnel verification false', () {
    final r = DnsScanResult.fromJson({
      'ip': '1.2.3.4',
      'udpMs': 8,
      'tcpMs': 12,
      'reachable': true,
      'ednsSupported': true,
      'ednsPayload': 1232,
      'txtSupported': true,
      'responseBytes': 145,
      'tunnelVerified': false,
      'tunnelCandidate': true,
      'nxdomainSafe': true,
    });
    expect(r.reachable, isTrue);
    expect(r.txtSupported, isTrue);
    expect(r.responseBytes, 145);
    expect(r.tunnelVerified, isFalse);
    expect(r.nxdomainSafe, isTrue);
    expect(r.ednsSupported, isTrue);
    expect(r.ednsPayload, 1232);
    expect(r.isCandidate, isTrue);
  });
  test('CIDR and ranges are bounded and skip network/broadcast octets', () {
    expect(DnsScannerService.generateCidr('192.0.2.0/30'), [
      '192.0.2.1',
      '192.0.2.2',
    ]);
    expect(DnsScannerService.generateRange('198.51.100.0', '198.51.100.3'), [
      '198.51.100.0',
      '198.51.100.1',
      '198.51.100.2',
      '198.51.100.3',
    ]);
    expect(DnsScannerService.generateCidr('10.0.0.0/8', max: 3), hasLength(3));
    expect(DnsScannerService.generateCidr('bad/99'), isEmpty);
    expect(DnsScannerService.generateRange('198.51.100.0', '198.51.100.0'), [
      '198.51.100.0',
    ]);
    expect(
      () => DnsScannerService.expandTargets(['1.2.3.4', 'bad']),
      throwsFormatException,
    );
    expect(DnsScannerService.expandTargets(['1.2.3.4', '1.2.3.4']), [
      '1.2.3.4',
    ]);
  });
  test('random targets are capped and avoid private/reserved first octets', () {
    final xs = DnsScannerService.generateRandom(500, seed: 42);
    expect(xs, hasLength(500));
    expect(
      xs.every((ip) {
        final a = int.parse(ip.split('.').first);
        return a != 0 && a != 10 && a != 127 && a < 224;
      }),
      isTrue,
    );
    expect(
      DnsScannerService.generateRandom(200001, seed: 1),
      hasLength(DnsScannerService.maxTargets),
    );
  });
  test('strict IPv4 parsing rejects IPv6 and ambiguous numeric inputs', () {
    for (final value in [
      '::1',
      '2001:db8::1',
      '1.2.3.+4',
      '01.2.3.4',
      '1.2.3.4x',
      '256.2.3.4',
    ]) {
      expect(DnsScannerService.parseIp(value), isNull, reason: value);
    }
  });

  test('mixed IPv4 and IPv6 sources fail before any native scan', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      calls++;
      return '[]';
    });
    for (final ipv6 in ['2001:db8::1', '2001:db8::/64', '::ffff:8.8.8.8']) {
      await expectLater(
        DnsScannerService().scanRange(targets: ['8.8.8.8', ipv6]),
        throwsFormatException,
      );
      await expectLater(
        DnsScannerService().scan(servers: ['8.8.8.8', ipv6]),
        throwsFormatException,
      );
    }
    expect(calls, 0);
  });

  test(
    'operator lists and random samples use the same bounded DNS probe',
    () async {
      final queried = <String>[];
      messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (
        call,
      ) async {
        expect(call.method, 'scanDns');
        final args = call.arguments as Map;
        final ips = List<String>.from(args['ips'] as List);
        expect(ips.length, lessThanOrEqualTo(2));
        expect(args['domain'], 'probe.example');
        expect(args['port'], 5353);
        expect(args['timeoutMs'], 500);
        queried.addAll(ips);
        return '[]';
      });
      final sources = [
        // Operator-local resolvers remain valid manual targets.
        DnsScannerService.expandTargets(['10.1.2.0/30', '10.1.2.1']),
        DnsScannerService.generateRange('10.1.3.1', '10.1.3.3'),
        DnsScannerService.generateRandom(5, seed: 42),
      ];
      for (final targets in sources) {
        queried.clear();
        await DnsScannerService().scanRange(
          targets: targets,
          domain: 'probe.example',
          chunkSize: 2,
          parallel: 2,
          port: 5353,
          timeoutMs: 500,
        );
        expect(queried, targets);
        expect(queried.toSet().length, queried.length);
      }
    },
  );

  test(
    'random samples exclude special-use IPv4 blocks and are reproducible by seed',
    () {
      final targets = DnsScannerService.generateRandom(10000, seed: 12345);
      expect(targets.toSet(), hasLength(10000));
      expect(targets, DnsScannerService.generateRandom(10000, seed: 12345));
      expect(
        targets,
        isNot(DnsScannerService.generateRandom(10000, seed: 54321)),
      );
      const excluded = [
        '0.0.0.0/8',
        '10.0.0.0/8',
        '100.64.0.0/10',
        '127.0.0.0/8',
        '169.254.0.0/16',
        '172.16.0.0/12',
        '192.0.0.0/24',
        '192.0.2.0/24',
        '192.88.99.0/24',
        '192.168.0.0/16',
        '198.18.0.0/15',
        '198.51.100.0/24',
        '203.0.113.0/24',
        '224.0.0.0/3',
      ];
      for (final ip in targets) {
        final value = DnsScannerService.parseIp(ip)!;
        for (final cidr in excluded) {
          final parts = cidr.split('/');
          final mask = (0xffffffff << (32 - int.parse(parts[1]))) & 0xffffffff;
          expect(
            value & mask,
            isNot(DnsScannerService.parseIp(parts[0])! & mask),
            reason: '$ip must not be in $cidr',
          );
        }
      }
    },
  );

  test(
    'nearby expansion starts only after a safe candidate and scans each /24 IP once',
    () async {
      final queried = <String>[];
      var finalDone = 0, finalTotal = 0;
      messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (
        call,
      ) async {
        if (call.method != 'scanDns') return null;
        final args = call.arguments as Map;
        expect(args['port'], 5353);
        expect(args['timeoutMs'], 700);
        final ips = List<String>.from(args['ips'] as List);
        queried.addAll(ips);
        return jsonEncode(
          ips
              .where((ip) => ip == '192.0.2.9')
              .map(
                (ip) => {
                  'ip': ip,
                  'reachable': true,
                  'udpMs': 1,
                  'tcpMs': -1,
                  'ednsSupported': true,
                  'nxdomainSafe': true,
                  'tunnelCandidate': true,
                },
              )
              .toList(),
        );
      });
      final found = await DnsScannerService().scanRange(
        targets: ['192.0.2.9'],
        expandNearby: true,
        port: 5353,
        timeoutMs: 700,
        onProgress: (done, total) {
          finalDone = done;
          finalTotal = total;
        },
      );
      expect(found, hasLength(1));
      expect(queried, hasLength(256));
      expect(queried.toSet(), hasLength(256));
      expect(queried, containsAll(['192.0.2.0', '192.0.2.255']));
      expect(finalDone, 256);
      expect(finalTotal, 256);
    },
  );

  test('unsafe result never triggers nearby expansion', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      calls++;
      return jsonEncode([
        {
          'ip': '192.0.2.9',
          'reachable': true,
          'udpMs': 2,
          'ednsSupported': true,
          'nxdomainHijacked': true,
        },
      ]);
    });
    await DnsScannerService().scanRange(
      targets: ['192.0.2.9'],
      expandNearby: true,
    );
    expect(calls, 1);
  });

  test('cancellation after a hit prevents neighbouring scans', () async {
    var calls = 0;
    var cancelled = false;
    messenger.setMockMethodCallHandler(DnsVpnConnection.platform, (call) async {
      if (call.method != 'scanDns') return null;
      calls++;
      return jsonEncode([
        {
          'ip': '192.0.2.9',
          'reachable': true,
          'udpMs': 1,
          'ednsSupported': true,
          'nxdomainSafe': true,
          'tunnelCandidate': true,
        },
      ]);
    });
    await DnsScannerService().scanRange(
      targets: ['192.0.2.9'],
      expandNearby: true,
      isCancelled: () => cancelled,
      onFound: (_) => cancelled = true,
    );
    expect(calls, 1);
  });
}
