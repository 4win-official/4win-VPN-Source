import 'dart:convert';

/// A registered Cloudflare WARP identity (WireGuard peer configuration),
/// obtained from Cloudflare's client registration API
/// (`POST https://api.cloudflareclient.com/<version>/reg`).
///
/// This is NOT a user-picked server like [XrayServer]/[ProxyServer] — it is a
/// single, auto-generated device identity. The private key is generated
/// on-device (X25519, via package:cryptography) and never leaves the device;
/// only the public key is sent to Cloudflare during registration.
class WarpAccount {
  /// Cloudflare's device id for this registration (`GET/PATCH .../reg/<id>`).
  final String id;

  /// Cloudflare's account id (the `account.id` field of the reg response).
  final String accountId;

  /// Bearer token used to refresh/patch this registration later.
  final String token;

  /// Base64 X25519 private key generated on-device. Kept locally only.
  final String privateKeyBase64;

  /// Base64 X25519 public key sent to Cloudflare (matches [privateKeyBase64]).
  final String publicKeyBase64;

  /// Base64 X25519 public key of Cloudflare's WireGuard peer.
  final String peerPublicKeyBase64;

  /// Peer endpoint host:port, e.g. "engage.cloudflareclient.com:2408".
  final String peerEndpoint;

  /// Tunnel-assigned IPv4 address with /32, e.g. "172.16.0.2/32".
  final String addressV4;

  /// Tunnel-assigned IPv6 address with /128 (may be empty if unavailable).
  final String addressV6;

  /// 3 raw bytes decoded from the reg response's `config.client_id` (base64),
  /// used as the `reserved` field in Xray's wireguard outbound. Cloudflare's
  /// edge uses this to route/identify the client at the WireGuard layer;
  /// omitting it is known to cause unreliable WARP connectivity.
  final List<int> reserved;

  /// Whether this identity is on the WARP+ (warp_enabled) plan. Free WARP
  /// (warp_enabled=false) still fully works as a WireGuard proxy — this flag
  /// is informational only and not used for connection logic.
  final bool warpEnabled;

  /// [addressV4] without its "/32" suffix — Xray's wireguard outbound
  /// `address` field wants a bare IP, not a CIDR route.
  String get addressV4Bare => addressV4.split('/').first;

  /// [addressV6] without any CIDR suffix (bare IP), if present.
  String get addressV6Bare => addressV6.split('/').first;

  const WarpAccount({
    required this.id,
    required this.accountId,
    required this.token,
    required this.privateKeyBase64,
    required this.publicKeyBase64,
    required this.peerPublicKeyBase64,
    required this.peerEndpoint,
    required this.addressV4,
    required this.addressV6,
    required this.reserved,
    this.warpEnabled = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'token': token,
        'privateKeyBase64': privateKeyBase64,
        'publicKeyBase64': publicKeyBase64,
        'peerPublicKeyBase64': peerPublicKeyBase64,
        'peerEndpoint': peerEndpoint,
        'addressV4': addressV4,
        'addressV6': addressV6,
        'reserved': reserved,
        'warpEnabled': warpEnabled,
      };

  factory WarpAccount.fromJson(Map<String, dynamic> j) => WarpAccount(
        id: j['id'] as String,
        accountId: j['accountId'] as String,
        token: j['token'] as String,
        privateKeyBase64: j['privateKeyBase64'] as String,
        publicKeyBase64: j['publicKeyBase64'] as String,
        peerPublicKeyBase64: j['peerPublicKeyBase64'] as String,
        peerEndpoint: j['peerEndpoint'] as String,
        addressV4: j['addressV4'] as String,
        addressV6: (j['addressV6'] as String?) ?? '',
        reserved: (j['reserved'] as List).map((e) => e as int).toList(),
        warpEnabled: (j['warpEnabled'] as bool?) ?? false,
      );

  String toStorageString() => jsonEncode(toJson());

  factory WarpAccount.fromStorageString(String s) =>
      WarpAccount.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
