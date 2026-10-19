import 'package:flutter_test/flutter_test.dart';
import '../lib/services/dns_scanner_service.dart';

void main() {
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
}
