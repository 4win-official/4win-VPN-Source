import 'package:flutter_test/flutter_test.dart';

import '../lib/models/openvpn_config.dart';
import '../lib/services/openvpn_service.dart';

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

  test('recognizes and preserves an inline PKCS#12 client credential', () {
    final config = OpenVpnConfig(
      name: 'pkcs12',
      config: '''client
remote vpn.example 1194
proto udp
<pkcs12>
PKCS12 DATA
</pkcs12>
''',
    );

    expect(config.hasClientCert, isTrue);
    expect(config.normalizedConfig, contains('<pkcs12>'));
    expect(config.configWithoutClientCert, isNot(contains('<pkcs12>')));
  });

  test('certificate bypass preserves server CA and auth settings', () {
    final config = OpenVpnConfig(
      name: 'bypass',
      config: '''client
remote vpn.example 1194
proto udp
auth-user-pass
<ca>
SERVER CA
</ca>
<cert>
CLIENT CERT
</cert>
<key>
CLIENT KEY
</key>
''',
    );

    expect(config.configWithoutClientCert, contains('<ca>'));
    expect(config.configWithoutClientCert, contains('auth-user-pass'));
    expect(config.configWithoutClientCert, isNot(contains('<cert>')));
    expect(config.configWithoutClientCert, isNot(contains('<key>')));
  });

  test('does not add the server-only cert option to a client profile', () {
    final config = OpenVpnConfig(
      name: 'password-only',
      config: '''client
remote vpn.example 1194
proto udp
auth-user-pass
<ca>
SERVER CA
</ca>
''',
    );

    expect(
      config.normalizedConfig,
      isNot(contains('client-cert-not-required')),
    );
  });

  test('validates real remote and supporting client directives', () {
    expect(
      OpenVpnService.validateConfig('''
# remote comment.example 1194
client
remote vpn.example 1194
proto udp
'''),
      isTrue,
    );
  });

  test('rejects comments and partial directive names as config fields', () {
    expect(
      OpenVpnService.validateConfig('''
# remote vpn.example 1194
# client
not-remote vpn.example 1194
device tun
protocol udp
'''),
      isFalse,
    );
  });

  test('requires an actual remote directive', () {
    expect(
      OpenVpnService.validateConfig('''
client
dev tun
proto udp
'''),
      isFalse,
    );
  });
}
