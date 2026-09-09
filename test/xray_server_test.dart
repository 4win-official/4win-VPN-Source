import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/models/xray_server.dart';
import 'package:vpn_swift/services/secret_text_cipher.dart';

void main() {
  group('XrayServer.fromLink', () {
    test('parses vless links', () {
      final s = XrayServer.fromLink(
          'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443'
          '?security=tls&sni=example.com&type=ws&path=%2Fws#MyVless');
      expect(s.protocol, 'vless');
      expect(s.address, '1.2.3.4');
      expect(s.port, 443);
      expect(s.remark, 'MyVless');
      expect(s.encrypted, isFalse);
    });

    test('parses trojan links', () {
      final s = XrayServer.fromLink('trojan://pass@5.6.7.8:443#MyTrojan');
      expect(s.protocol, 'trojan');
      expect(s.address, '5.6.7.8');
      expect(s.port, 443);
      expect(s.remark, 'MyTrojan');
    });

    test('parses shadowsocks links', () {
      final userinfo = base64.encode(utf8.encode('aes-256-gcm:mypass'));
      final s =
          XrayServer.fromLink('ss://$userinfo@7.8.9.10:8388#MySS');
      expect(s.protocol, 'shadowsocks');
      expect(s.address, '7.8.9.10');
      expect(s.port, 8388);
      expect(s.remark, 'MySS');
    });

    test('parses vmess links', () {
      final payload = base64.encode(utf8.encode(jsonEncode({
        'add': '9.9.9.9',
        'port': '443',
        'ps': 'MyVmess',
        'id': 'uuid-here',
        'aid': '0',
        'scy': 'auto',
        'net': 'tcp',
        'tls': '',
      })));
      final s = XrayServer.fromLink('vmess://$payload');
      expect(s.protocol, 'vmess');
      expect(s.address, '9.9.9.9');
      expect(s.port, 443);
      expect(s.remark, 'MyVmess');
    });

    test('rejects unsupported links', () {
      expect(() => XrayServer.fromLink('socks5://1.2.3.4:1080'),
          throwsFormatException);
      expect(
          () => XrayServer.fromLink('https://example.com'), throwsFormatException);
      expect(() => XrayServer.fromLink('not a link'), throwsFormatException);
    });

    test('decrypts 4ws:// links and flags them encrypted', () {
      const inner = 'vless://u@1.1.1.1:443#Hidden';
      final wrapped = SecretTextCipher.encodeServerLink(inner);
      final s = XrayServer.fromLink(wrapped);
      expect(s.encrypted, isTrue);
      expect(s.link, inner);
      expect(s.address, '1.1.1.1');
      expect(s.exportLink.startsWith('4ws://'), isTrue);
      expect(s.exportLink.contains('1.1.1.1'), isFalse);
    });

    test('plain servers export the link as-is', () {
      const link = 'trojan://p@2.2.2.2:443#T';
      final s = XrayServer.fromLink(link);
      expect(s.exportLink, link);
    });

    test('ids are deterministic per link', () {
      const link = 'vless://u@3.3.3.3:443#X';
      expect(XrayServer.fromLink(link).id, XrayServer.fromLink(link).id);
      expect(XrayServer.fromLink(link).id,
          isNot(equals(XrayServer.fromLink('${link}2').id)));
    });

    test('json roundtrip', () {
      final s = XrayServer.fromLink('trojan://p@4.4.4.4:443#R');
      final restored = XrayServer.fromJson(s.toJson());
      expect(restored.id, s.id);
      expect(restored.link, s.link);
      expect(restored.protocol, s.protocol);
      expect(restored.address, s.address);
      expect(restored.port, s.port);
      expect(restored.remark, s.remark);
    });
  });
}
