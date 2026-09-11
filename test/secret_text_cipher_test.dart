import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/services/secret_text_cipher.dart';

void main() {
  group('SecretTextCipher', () {
    test('encode/decode roundtrip (ascii, unicode, emoji, multiline)', () {
      const samples = [
        'hello world',
        'سلام دنیا! این یک تست است.',
        '🔐🚀 mixed-内容 123 !@#',
        'line1\nline2\nline3',
        'x', // single char
      ];
      for (final s in samples) {
        final encoded = SecretTextCipher.encode(s);
        expect(encoded.startsWith('4W~'), isTrue, reason: 'prefix: $s');
        expect(SecretTextCipher.looksLikeSecret(encoded), isTrue);
        expect(SecretTextCipher.decode(encoded), s);
      }
    });

    test('same input yields different output (random salt)', () {
      final a = SecretTextCipher.encode('same');
      final b = SecretTextCipher.encode('same');
      expect(a, isNot(equals(b)));
      expect(SecretTextCipher.decode(a), 'same');
      expect(SecretTextCipher.decode(b), 'same');
    });

    test('empty input encodes to empty string', () {
      expect(SecretTextCipher.encode(''), '');
    });

    test('decode rejects foreign / corrupted input', () {
      expect(() => SecretTextCipher.decode(''), throwsFormatException);
      expect(() => SecretTextCipher.decode('not a secret'),
          throwsFormatException);
      expect(() => SecretTextCipher.decode('4W~!!!'), throwsFormatException);

      // Corrupt several chars of a valid secret -> checksum must fail.
      final valid = SecretTextCipher.encode('integrity check');
      final chars = valid.split('');
      for (var i = 4; i < 8 && i < chars.length; i++) {
        chars[i] = chars[i] == '0' ? '1' : '0';
      }
      expect(() => SecretTextCipher.decode(chars.join()),
          throwsFormatException);
    });

    test('server link roundtrip hides the real link', () {
      const link = 'vless://uuid-1234@1.2.3.4:443?security=tls#MyServer';
      final encrypted = SecretTextCipher.encodeServerLink(link);
      expect(encrypted.startsWith('4ws://'), isTrue);
      expect(encrypted.contains('1.2.3.4'), isFalse);
      expect(SecretTextCipher.looksLikeServerLink(encrypted), isTrue);
      expect(SecretTextCipher.decodeServerLink(encrypted), link);
    });

    test('decodeServerLink rejects non-server links', () {
      expect(() => SecretTextCipher.decodeServerLink('vless://x'),
          throwsFormatException);
      expect(() => SecretTextCipher.decodeServerLink('4W~abc'),
          throwsFormatException);
    });

    test('encodeServerLinks passes through blanks and 4ws lines', () {
      const link = 'trojan://pass@5.6.7.8:443#T';
      final already = SecretTextCipher.encodeServerLink(link);
      final out = SecretTextCipher.encodeServerLinks(
          '  \n$link\n\n$already\n  ');
      final lines = out.split('\n');
      expect(lines.length, 2);
      expect(lines[0].startsWith('4ws://'), isTrue);
      expect(lines[1], already);
      expect(SecretTextCipher.decodeServerLink(lines[0]), link);
    });
  });
}
