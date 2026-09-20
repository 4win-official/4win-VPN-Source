import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';
import '../models/warp_account.dart';

/// Registers and persists a Cloudflare WARP (WireGuard) device identity.
///
/// Cloudflare's client registration API is the same one used by the
/// official WARP apps and reverse-engineered tools (wgcf, MSN-GUARD):
/// `POST https://api.cloudflareclient.com/{API_VERSION}/reg`
/// with a device-generated X25519 public key. The response contains the
/// Cloudflare WireGuard peer's public key + endpoint + the tunnel-assigned
/// IPv4/IPv6 addresses — everything needed to build an Xray "wireguard"
/// outbound (see XrayConfigBuilder.buildForWarp). The private key never
/// leaves the device.
///
/// Values below (API version, headers) match wgcf
/// (github.com/ViRb3/wgcf) and were verified live against Cloudflare's API
/// during development. If Cloudflare ever bumps the API version and starts
/// rejecting registrations, update [_apiVersion]/[_clientVersion] here.
///
/// IMPORTANT — endpoint selection: the WireGuard peer endpoint MUST be a
/// numeric IPv4 address, never Cloudflare's documented hostname
/// ("engage.cloudflareclient.com:2408"). On networks/devices where the
/// hostname's IPv6 (AAAA) record wins DNS resolution but IPv6 has no real
/// route (this is common on mobile carriers and was reproduced end-to-end
/// against the live Cloudflare API during development), the WireGuard UDP
/// handshake fails permanently with "network is unreachable" while the
/// local SOCKS/HTTP listener still reports itself as connected — the
/// exact "always shows connected, never actually passes traffic" bug this
/// avoids. See [register]'s `peerEndpoint` derivation.
class WarpService {
  static const String _apiBase = 'https://api.cloudflareclient.com';
  static const String _apiVersion = 'v0a1922';
  static const String _userAgent = 'okhttp/3.12.1';
  static const String _clientVersion = 'a-6.3-1922';

  static const String _storageKey = 'warp_account';

  /// Load the persisted WARP identity, if one has been registered before.
  ///
  /// Self-heals identities saved by an older build that stored the
  /// hostname endpoint ("engage.cloudflareclient.com:2408") instead of a
  /// numeric IP — that hostname is what caused the "always connects, never
  /// actually passes traffic" bug (see [register]). If a hostname is found
  /// here, wipe the stored identity so the caller re-registers a fresh one
  /// with a numeric endpoint instead of reusing the broken one forever.
  Future<WarpAccount?> getAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final account = WarpAccount.fromStorageString(raw);
      if (_isHostnameEndpoint(account.peerEndpoint)) {
        await clearAccount();
        return null;
      }
      return account;
    } catch (_) {
      return null;
    }
  }

  bool _isHostnameEndpoint(String endpoint) {
    final host = endpoint.split(':').first;
    // A numeric IPv4 endpoint always starts with a digit; anything else
    // (e.g. "engage.cloudflareclient.com") is the old, broken hostname form.
    return host.isEmpty || int.tryParse(host.split('.').first) == null;
  }

  Future<void> _saveAccount(WarpAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, account.toStorageString());
  }

  Future<void> clearAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Returns the existing identity if one is already registered, otherwise
  /// registers a brand-new one. Call this once before the first WARP
  /// connect; subsequent connects just reuse the stored [WarpAccount].
  Future<WarpAccount> getOrRegister() async {
    final existing = await getAccount();
    if (existing != null) return existing;
    return register();
  }

  /// Generates a fresh on-device X25519 keypair and registers it with
  /// Cloudflare as a new WARP device. Overwrites any previously stored
  /// identity. Throws on network/parse failure.
  Future<WarpAccount> register() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    final privB64 = base64.encode(privateKeyBytes);
    final pubB64 = base64.encode(publicKey.bytes);

    final body = jsonEncode({
      'key': pubB64,
      'install_id': '',
      'fcm_token': '',
      'tos': DateTime.now().toUtc().toIso8601String(),
      'model': 'PC',
      'serial_number': _randomSerial(),
      'locale': 'en_US',
      'type': 'Android',
    });

    final resp = await http.post(
      Uri.parse('$_apiBase/$_apiVersion/reg'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': _userAgent,
        'CF-Client-Version': _clientVersion,
      },
      body: body,
    ).timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception(
          'WARP registration failed: HTTP ${resp.statusCode} ${resp.body}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final config = json['config'] as Map<String, dynamic>;
    final peers = (config['peers'] as List).cast<Map<String, dynamic>>();
    if (peers.isEmpty) {
      throw Exception('WARP registration response has no peers');
    }
    final peer = peers.first;
    final endpoint = peer['endpoint'] as Map<String, dynamic>;
    final iface = config['interface'] as Map<String, dynamic>;
    final addresses = iface['addresses'] as Map<String, dynamic>;

    final clientIdB64 = config['client_id'] as String? ?? '';
    List<int> reserved = const [0, 0, 0];
    try {
      final raw = base64.decode(clientIdB64);
      if (raw.length >= 3) reserved = raw.sublist(0, 3);
    } catch (_) {
      // keep default [0,0,0] if client_id is missing/malformed
    }

    // Use Cloudflare's numeric IPv4 endpoint, NOT the `host` field
    // ("engage.cloudflareclient.com:2408"). This was verified live during
    // development: on networks/devices where IPv6 has no real route (very
    // common — many mobile carriers and this build environment both hit
    // it), resolving that hostname picks the AAAA (IPv6) record and the
    // WireGuard UDP handshake fails at the socket layer with
    // "network is unreachable" — forever, silently, while the local
    // SOCKS/HTTP listener still reports "connected". That is exactly the
    // single-fixed-IP / never-actually-connects bug this fixes.
    //
    // Cloudflare's `endpoint.v4` field comes back as "ip:0" (port always
    // 0 — a placeholder), so always force the real WARP UDP port (2408)
    // onto whatever IP it gives us. If the API ever omits `v4` entirely,
    // fall back to a known-good literal WARP edge IP (never a hostname,
    // so DNS/IPv6 selection can never silently reintroduce this bug).
    final v4Raw = (endpoint['v4'] as String?)?.trim() ?? '';
    final v4Ip = v4Raw.contains(':') ? v4Raw.split(':').first : v4Raw;
    final peerEndpoint = v4Ip.isNotEmpty ? '$v4Ip:2408' : '162.159.192.1:2408';

    final account = WarpAccount(
      id: json['id'] as String? ?? '',
      accountId: (json['account'] as Map<String, dynamic>?)?['id'] as String? ?? '',
      token: json['token'] as String? ?? '',
      privateKeyBase64: privB64,
      publicKeyBase64: pubB64,
      peerPublicKeyBase64: peer['public_key'] as String? ?? '',
      peerEndpoint: peerEndpoint,
      addressV4: '${addresses['v4'] ?? ''}/32',
      addressV6: (addresses['v6'] as String?) ?? '',
      reserved: reserved,
      warpEnabled: json['warp_enabled'] as bool? ?? false,
    );

    if (account.peerPublicKeyBase64.isEmpty || account.addressV4 == '/32') {
      throw Exception('WARP registration response missing required fields');
    }

    await _saveAccount(account);
    if (kDebugMode) {
      debugPrint('✅ WARP registered: ${account.addressV4} via ${account.peerEndpoint}');
    }
    return account;
  }

  String _randomSerial() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(8, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
