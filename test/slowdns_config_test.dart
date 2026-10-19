import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/slowdns_config.dart';

const key = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

SlowDnsConfig config({
  String transport = 'udp',
  int? port,
  String? dohUrl,
  String? username,
  String? password,
}) => SlowDnsConfig(
  name: 'test',
  domain: 'tunnel.example.com',
  nameServer: '1.1.1.1',
  pubKey: key,
  dnsTransport: transport,
  port: port,
  dohUrl: dohUrl,
  username: username,
  password: password,
);

void main() {
  test('requires a 64-character hexadecimal public key', () {
    expect(SlowDnsConfig.isValidPublicKey(key), isTrue);
    expect(SlowDnsConfig.isValidPublicKey('not-a-key'), isFalse);
    expect(
      config().copyWith(pubKey: List.filled(63, 'f').join()).validationError,
      contains('64'),
    );
  });

  test('accepts DNS names and resolver IPs but rejects URLs', () {
    expect(SlowDnsConfig.isValidDnsName('tunnel.example.com'), isTrue);
    expect(SlowDnsConfig.isValidDnsName('https://tunnel.example.com'), isFalse);
    expect(SlowDnsConfig.isValidResolverEndpoint('1.1.1.1'), isTrue);
    expect(SlowDnsConfig.isValidResolverEndpoint('resolver.example'), isTrue);
    expect(
      SlowDnsConfig.isValidResolverEndpoint('https://1.1.1.1/dns-query'),
      isFalse,
    );
  });

  test('uses transport default ports and validates DoH URL', () {
    expect(config().effectivePort, 53);
    expect(config(transport: 'dot').effectivePort, 853);
    expect(
      config(
        transport: 'doh',
        dohUrl: 'https://dns.example/dns-query',
      ).effectivePort,
      443,
    );
    expect(
      config(transport: 'doh', dohUrl: 'http://dns.example/dns-query').isValid,
      isFalse,
    );
    expect(config(transport: 'dot', port: 5353).isValid, isTrue);
    expect(config(port: 65536).isValid, isFalse);
    expect(SlowDnsConfig.isValidResolverEndpoint('999.1.2.3'), isFalse);
    expect(SlowDnsConfig.isValidResolverEndpoint('1.1.1.1:53'), isFalse);
    expect(
      SlowDnsConfig.isValidResolverEndpoint('2001:4860:4860::8888'),
      isTrue,
    );
  });

  test(
    'allows complete remote SOCKS5 credentials and rejects partial or oversized pairs',
    () {
      expect(config(username: 'user', password: 'pass').isValid, isTrue);
      expect(config(username: 'user').validationError, contains('together'));
      expect(
        config(username: List.filled(128, 'é').join(), password: 'p').isValid,
        isFalse,
      );
      expect(
        config(
          username: List.filled(256, 'u').join(),
          password: 'p',
        ).validationError,
        contains('255'),
      );
    },
  );

  test('preserves legacy JSON fields and serialization', () {
    final original = config(username: 'u', password: 'p');
    final restored = SlowDnsConfig.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
  });
}
