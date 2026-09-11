import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/proxy_server.dart';
import 'package:vpn_swift/services/secret_text_cipher.dart';

void main() {
  group('ProxyServer.fromLink', () {
    test('parses socks5 with auth and remark', () {
      final s = ProxyServer.fromLink('socks5://user:pass@1.2.3.4:1080#MyProxy');
      expect(s.protocol, 'socks5');
      expect(s.address, '1.2.3.4');
      expect(s.port, 1080);
      expect(s.username, 'user');
      expect(s.password, 'pass');
      expect(s.remark, 'MyProxy');
      expect(s.encrypted, isFalse);
      expect(s.isLocked, isFalse);
    });

    test('parses socks4 without auth', () {
      final s = ProxyServer.fromLink('socks4://5.6.7.8:1080');
      expect(s.protocol, 'socks4');
      expect(s.address, '5.6.7.8');
      expect(s.port, 1080);
      expect(s.username, isEmpty);
      expect(s.remark, '5.6.7.8:1080');
    });

    test('treats socks:// as socks5 and http(s):// as http', () {
      expect(ProxyServer.fromLink('socks://1.1.1.1:1080').protocol, 'socks5');
      final http = ProxyServer.fromLink('http://u:p@2.2.2.2:8080#H');
      expect(http.protocol, 'http');
      expect(http.username, 'u');
      expect(http.password, 'p');
      expect(http.remark, 'H');
      expect(ProxyServer.fromLink('https://3.3.3.3:443').protocol, 'http');
    });

    test('parses bare host:port forms', () {
      final bare = ProxyServer.fromLink('10.0.0.1:8080');
      expect(bare.protocol, 'socks5');
      expect(bare.address, '10.0.0.1');
      expect(bare.port, 8080);

      final creds = ProxyServer.fromLink('10.0.0.2:1080:bob:s3cret');
      expect(creds.username, 'bob');
      expect(creds.password, 's3cret');
    });

    test('rejects unsupported or malformed links', () {
      expect(() => ProxyServer.fromLink('vmess://abc'),
          throwsFormatException);
      expect(() => ProxyServer.fromLink('socks5://:1080'), throwsFormatException);
      expect(() => ProxyServer.fromLink('justahost'), throwsFormatException);
      expect(() => ProxyServer.fromLink('host:notaport'), throwsFormatException);
    });

    test('decrypts 4ws:// links and flags them encrypted', () {
      const inner = 'socks5://u:p@9.9.9.9:1080#Hidden';
      final wrapped = SecretTextCipher.encodeServerLink(inner);
      final s = ProxyServer.fromLink(wrapped);
      expect(s.encrypted, isTrue);
      expect(s.address, '9.9.9.9');
      expect(s.remark, 'Hidden');
      // Exporting re-hides the real link.
      expect(s.exportLink.startsWith('4ws://'), isTrue);
      expect(s.exportLink.contains('9.9.9.9'), isFalse);
    });

    test('group assignment locks the server', () {
      final s = ProxyServer.fromLink('1.2.3.4:1080', group: 'MySub');
      expect(s.group, 'MySub');
      expect(s.isLocked, isTrue);
    });

    test('json roundtrip', () {
      final s = ProxyServer.fromLink('socks5://u:p@1.2.3.4:1080#R');
      final restored = ProxyServer.fromJson(s.toJson());
      expect(restored.id, s.id);
      expect(restored.link, s.link);
      expect(restored.protocol, s.protocol);
      expect(restored.address, s.address);
      expect(restored.port, s.port);
      expect(restored.username, s.username);
      expect(restored.password, s.password);
      expect(restored.remark, s.remark);
    });
  });
}
