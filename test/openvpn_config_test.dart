import 'package:flutter_test/flutter_test.dart';

import '../lib/models/openvpn_config.dart';

void main() {
  setUp(() {
    OpenVpnConfig.trafficCompressionEnabled = false;
  });

  tearDown(() {
    OpenVpnConfig.trafficCompressionEnabled = false;
  });

  test('preserves profile compression when data saver is off', () {
    final config = OpenVpnConfig(
      name: 'compressed',
      config: '''client
remote vpn.example 1194
proto udp
comp-lzo yes
''',
    );

    expect(config.normalizedConfig, contains('comp-lzo yes'));
    expect(config.normalizedConfig, isNot(contains('allow-compression no')));
  });

  test('uses asymmetric compression only when data saver is enabled', () {
    OpenVpnConfig.trafficCompressionEnabled = true;
    final config = OpenVpnConfig(
      name: 'data-saver',
      config: '''client
remote vpn.example 1194
proto udp
comp-lzo yes
''',
    );

    expect(config.normalizedConfig, contains('allow-compression asym'));
    expect(config.normalizedConfig, isNot(contains('comp-lzo yes')));
  });

  test('keeps a valid inline client certificate in normal mode', () {
    final config = OpenVpnConfig(
      name: 'certificate',
      config: '''client
remote vpn.example 1194
proto udp
<cert>
CERTIFICATE
</cert>
<key>
PRIVATE KEY
</key>
''',
    );

    expect(config.normalizedConfig, contains('<cert>'));
    expect(config.normalizedConfig, contains('<key>'));
    expect(config.hasClientCert, isTrue);
  });
}
