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
class WarpService {
  static const String _apiBase = 'https://api.cloudflareclient.com';
  static const String _apiVersion = 'v0a1922';
  static const String _userAgent = 'okhttp/3.12.1';
  static const String _clientVersion = 'a-6.3-1922';

  static const String _storageKey = 'warp_account';

  /// Load the persisted WARP identity, if one has been registered before.
  Future<WarpAccount?> getAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return WarpAccount.fromStorageString(raw);
    } catch (_) {
      return null;
    }
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

    // Prefer the documented host:port (rotates through Cloudflare's anycast
    // network); fall back to the numeric v4 endpoint if host is missing.
    final host = (endpoint['host'] as String?)?.trim();
    final v4 = (endpoint['v4'] as String?)?.trim();
    final peerEndpoint = (host != null && host.isNotEmpty)
        ? host
        : (v4 != null && v4.isNotEmpty ? v4 : 'engage.cloudflareclient.com:2408');

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
