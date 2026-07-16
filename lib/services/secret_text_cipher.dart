import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Self-contained, dependency-free reversible text cipher for 4win VPN.
///
/// Goal (per the user request): turn any text into a "strange-looking" string
/// that can ONLY be decoded from inside this app, and back again. It uses:
///   • a fixed app secret key (embedded below) — without it the output cannot
///     be decoded, so only this app (or anyone with the same key) can read it,
///   • an RC4-style keystream XOR over the UTF-8 bytes with a per-message
///     random salt (so the same input yields different output each time),
///   • a lightweight integrity check byte,
///   • a custom Base85-like alphabet + a recognizable "4W~" prefix so the
///     result looks like gibberish and is easy to spot as a 4win secret.
///
/// This is obfuscation-grade privacy for casual sharing (notes, messages),
/// NOT a substitute for audited end-to-end encryption.
class SecretTextCipher {
  // Embedded app secret. Anyone with this app can decode; outsiders cannot
  // without knowing this exact key.
  static const String _appSecret =
      '4win-VPN::SecretText::v1::b8Fq2Zx9Lp7Ws3Nk';

  static const String _prefix = '4W~';

  // Custom 85-char alphabet (no spaces, no easily-confused chars removed for
  // uniqueness). Deliberately unusual so output looks "weird".
  static const String _alphabet =
      r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_{|}~.';

  /// Encode [plain] into a 4win secret string. Returns '' for empty input.
  static String encode(String plain) {
    if (plain.isEmpty) return '';
    final data = utf8.encode(plain);

    // 4-byte random salt mixed into the key so output differs every time.
    final rnd = Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(4, (_) => rnd.nextInt(256)));

    // checksum byte over the plaintext (integrity + wrong-key detection).
    var sum = 0;
    for (final b in data) {
      sum = (sum + b) & 0xFF;
    }

    final payload = Uint8List(1 + data.length);
    payload[0] = sum;
    payload.setRange(1, payload.length, data);

    final keystream = _rc4(_keyBytes(salt), payload.length);
    final cipher = Uint8List(payload.length);
    for (var i = 0; i < payload.length; i++) {
      cipher[i] = payload[i] ^ keystream[i];
    }

    // salt (plaintext) + cipher, then base85 with our alphabet.
    final full = Uint8List(salt.length + cipher.length);
    full.setRange(0, salt.length, salt);
    full.setRange(salt.length, full.length, cipher);

    return _prefix + _base85Encode(full);
  }

  /// Decode a 4win secret string produced by [encode]. Throws [FormatException]
  /// if the input isn't a valid 4win secret or the checksum fails (wrong/foreign
  /// text or corruption).
  static String decode(String secret) {
    var s = secret.trim();
    if (s.isEmpty) {
      throw const FormatException('Empty input');
    }
    if (s.startsWith(_prefix)) {
      s = s.substring(_prefix.length);
    } else {
      throw const FormatException('Not a 4win secret (missing prefix)');
    }

    final full = _base85Decode(s);
    if (full.length < 5) {
      throw const FormatException('Corrupted secret');
    }
    final salt = full.sublist(0, 4);
    final cipher = full.sublist(4);

    final keystream = _rc4(_keyBytes(Uint8List.fromList(salt)), cipher.length);
    final payload = Uint8List(cipher.length);
    for (var i = 0; i < cipher.length; i++) {
      payload[i] = cipher[i] ^ keystream[i];
    }

    final sum = payload[0];
    final data = payload.sublist(1);
    var check = 0;
    for (final b in data) {
      check = (check + b) & 0xFF;
    }
    if (check != sum) {
      throw const FormatException('Wrong key or corrupted secret');
    }
    return utf8.decode(data);
  }

  /// True if [text] looks like a 4win secret string.
  static bool looksLikeSecret(String text) =>
      text.trim().startsWith(_prefix);

  // ---- internals ----

  static Uint8List _keyBytes(Uint8List salt) {
    final base = utf8.encode(_appSecret);
    final out = Uint8List(base.length + salt.length);
    out.setRange(0, base.length, base);
    out.setRange(base.length, out.length, salt);
    return out;
  }

  /// RC4 keystream generator (used purely as a fast keyed stream cipher).
  static Uint8List _rc4(Uint8List key, int length) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xFF;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }
    final out = Uint8List(length);
    var a = 0, b = 0;
    for (var k = 0; k < length; k++) {
      a = (a + 1) & 0xFF;
      b = (b + s[a]) & 0xFF;
      final tmp = s[a];
      s[a] = s[b];
      s[b] = tmp;
      out[k] = s[(s[a] + s[b]) & 0xFF];
    }
    return out;
  }

  // Base85 encode/decode over our custom 85-char alphabet.
  static String _base85Encode(Uint8List data) {
    final sb = StringBuffer();
    var i = 0;
    while (i < data.length) {
      final chunkLen = (data.length - i) >= 4 ? 4 : (data.length - i);
      var value = 0;
      for (var k = 0; k < 4; k++) {
        value <<= 8;
        if (k < chunkLen) value |= data[i + k];
      }
      final chars = List<int>.filled(5, 0);
      for (var k = 4; k >= 0; k--) {
        chars[k] = value % 85;
        value = value ~/ 85;
      }
      // Emit chunkLen+1 characters for chunkLen bytes.
      for (var k = 0; k < chunkLen + 1; k++) {
        sb.write(_alphabet[chars[k]]);
      }
      i += 4;
    }
    return sb.toString();
  }

  static Uint8List _base85Decode(String str) {
    final out = <int>[];
    final idx = <int, int>{};
    for (var k = 0; k < _alphabet.length; k++) {
      idx[_alphabet.codeUnitAt(k)] = k;
    }
    var i = 0;
    while (i < str.length) {
      final groupLen = (str.length - i) >= 5 ? 5 : (str.length - i);
      if (groupLen < 2) {
        throw const FormatException('Corrupted secret');
      }
      var value = 0;
      for (var k = 0; k < 5; k++) {
        final c = k < groupLen
            ? (idx[str.codeUnitAt(i + k)] ??
                (throw const FormatException('Invalid character')))
            : 84; // pad with max digit
        value = value * 85 + c;
      }
      final bytes = <int>[
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ];
      out.addAll(bytes.take(groupLen - 1));
      i += 5;
    }
    return Uint8List.fromList(out);
  }
}
