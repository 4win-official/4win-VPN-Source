/// OpenVPN configuration model.
///
/// IMPORTANT: parsing the raw `.ovpn` text is relatively expensive (several
/// regexes, one of them `dotAll` over the whole file). Earlier versions called
/// `parseConfigFile` inside EVERY getter (serverAddress, serverPort, protocol,
/// embeddedUsername, effectiveUsername, normalizedConfig …). Selecting a server
/// touched most of those getters — and the list tiles rebuilt them on every
/// frame — so tapping a config re-parsed a large config many times on the UI
/// thread, freezing the app (and, with a big config, risking an ANR/crash).
///
/// We now parse the config EXACTLY ONCE (lazily, cached) and every getter reads
/// from that cache. This is what makes selection instant.
class OpenVpnConfig {
  /// Global "Traffic Compression" toggle (from General Settings). When true, an
  /// When enabled, `allow-compression asym` is added so the client can safely
  /// decompress server-sent data (the download direction) to reduce data usage,
  /// without forcing outbound compression that could break the tunnel. Set by
  /// VpnProvider from the persisted `traffic_compression` preference before a
  /// connect.
  static bool trafficCompressionEnabled = false;

  final String name; // نام کانفیگ
  final String config; // محتوای فایل .ovpn
  final String? username; // نام کاربری (اختیاری)
  final String? password; // رمز عبور (اختیاری)
  final DateTime addedAt; // تاریخ اضافه شدن

  // Lazily-computed, cached parse of [config]. Never re-parsed.
  Map<String, String>? _parsed;

  OpenVpnConfig({
    required this.name,
    required this.config,
    this.username,
    this.password,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'config': config,
      'username': username,
      'password': password,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory OpenVpnConfig.fromJson(Map<String, dynamic> json) {
    return OpenVpnConfig(
      name: json['name'] as String,
      config: json['config'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  /// Parse OpenVPN config file to extract server info (static, pure).
  static Map<String, String> parseConfigFile(String configContent) {
    final result = <String, String>{};

    // remote (server address and port)
    final remoteMatch =
        RegExp(r'^\s*remote\s+(\S+)\s+(\d+)', multiLine: true)
            .firstMatch(configContent);
    if (remoteMatch != null) {
      result['server'] = remoteMatch.group(1) ?? '';
      result['port'] = remoteMatch.group(2) ?? '';
    }

    // proto (tcp, tcp-client, udp, udp4, udp6)
    final protoMatch =
        RegExp(r'^\s*proto\s+(tcp-client|tcp|udp6|udp4|udp)', multiLine: true)
            .firstMatch(configContent);
    if (protoMatch != null) {
      var proto = protoMatch.group(1) ?? 'udp';
      if (proto == 'tcp') proto = 'tcp-client';
      result['proto'] = proto;
    } else {
      result['proto'] = 'udp';
    }

    // Embedded credentials: <auth-user-pass> ... </auth-user-pass>
    final authBlockMatch = RegExp(
      r'<auth-user-pass>\s*(.+?)\s*</auth-user-pass>',
      dotAll: true,
    ).firstMatch(configContent);
    if (authBlockMatch != null) {
      final authContent = authBlockMatch.group(1)?.trim() ?? '';
      final lines = authContent.split('\n');
      if (lines.length >= 2) {
        result['username'] = lines[0].trim();
        result['password'] = lines[1].trim();
      } else if (lines.length == 1) {
        result['username'] = lines[0].trim();
        result['password'] = '';
      }
    }

    return result;
  }

  /// Cached parse of this instance's [config]. Parsed once, then reused.
  Map<String, String> get _p => _parsed ??= parseConfigFile(config);

  /// Get embedded username from config file
  String? get embeddedUsername => _p['username'];

  /// Get embedded password from config file
  String? get embeddedPassword => _p['password'];

  /// Get effective username (embedded or user-provided)
  String? get effectiveUsername {
    final u = username;
    if (u != null && u.isNotEmpty) return u;
    return embeddedUsername;
  }

  /// Get effective password (embedded or user-provided)
  String? get effectivePassword {
    final p = password;
    if (p != null && p.isNotEmpty) return p;
    return embeddedPassword;
  }

  /// Whether this config requires username/password auth (has an auth-user-pass
  /// directive or block). Used to decide whether to inject credentials.
  bool get requiresAuth =>
      config.contains('<auth-user-pass>') ||
      config.contains(RegExp(r'^\s*auth-user-pass\b', multiLine: true));

  /// True when the config carries a CLIENT certificate/key (inline `<cert>` /
  /// `<key>` blocks or file-based `cert`/`key` directives). When it does NOT,
  /// the core
  /// must be told the client cert is not required, otherwise it waits for a
  /// certificate that never comes and the handshake stalls — the classic
  /// "connects to nothing" symptom for username/password-only servers.
  bool get hasClientCert =>
      config.contains('<cert>') ||
      config.contains('<key>') ||
      config.contains(RegExp(r'^\s*cert\s+\S+', multiLine: true)) ||
      config.contains(RegExp(r'^\s*key\s+\S+', multiLine: true)) ||
      config.contains(RegExp(r'^\s*pkcs12\s+\S+', multiLine: true));

  /// Normalized config fed to the native OpenVPN core.
  ///
  /// The official OpenVPN Connect app works with so many configs because it
  /// feeds them to the core essentially UNCHANGED. We do only minimal, safe
  /// fixes and cache the result so it's computed once:
  ///   1. `proto tcp`  → `proto tcp-client` (core needs the -client form)
  ///   2. inject `<auth-user-pass>` ONLY when the user supplied credentials and
  ///      the config carries no auth directive of its own.
  /// Always terminated by a newline.
  /// Whitespace/junk sanitizer. Some real-world configs (e.g. exported from
  /// Hiddify / cg-dialup) carry Windows CRLF line endings AND thousands of
  /// trailing blank lines. Those blank lines are harmless to the core but are
  /// CATASTROPHIC for our `dotAll` regexes (`configWithoutClientCert`), which
  /// then chew through ~15k empty lines ON THE UI THREAD — the app freezes
  /// (hang) and then ANR-crashes. This is exactly the "connects everywhere but
  /// hangs+crashes in our app" report. We normalise line endings and collapse
  /// runs of blank lines ONCE, up front, so nothing downstream ever sees them.
  static String _sanitize(String raw) {
    // Normalise CRLF/CR → LF.
    String s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Trim trailing spaces/tabs on each line.
    s = s.replaceAll(RegExp(r'[ \t]+$', multiLine: true), '');
    // Collapse 2+ consecutive blank lines into a single blank line.
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  String? _normalizedCache;
  bool? _normalizedCompression;
  String get normalizedConfig {
    // Cache is keyed on the global compression toggle so flipping it in
    // settings actually takes effect on the next connect.
    final cached = _normalizedCache;
    if (cached != null &&
        _normalizedCompression == trafficCompressionEnabled) {
      return cached;
    }

    // 🔴 STEP 0 — sanitize first (fixes the hang/crash on bloated configs).
    String normalized = _sanitize(config);

    // Fix 1: whole-line `proto tcp` → `proto tcp-client`.
    normalized = normalized.replaceAllMapped(
      RegExp(r'^(\s*proto\s+)tcp\s*$', multiLine: true),
      (m) => '${m.group(1)}tcp-client',
    );

    // Fix 1a: clamp a runaway `connect-retry-max` (some configs ship
    // `connect-retry-max 9999`, which makes the core spin internally for a very
    // long time and appear hung). We own the retry loop ourselves, so cap it.
    normalized = normalized.replaceAll(
      RegExp(r'^\s*connect-retry-max\s+\d+.*$', multiLine: true),
      'connect-retry-max 3',
    );

    // Fix 1b: The official OpenVPN app connects even when a config references a
    // client cert/key FILE that isn't present (it shows a warning and proceeds).
    // ics-openvpn instead rejects such a profile with `missing_certificates`,
    // so the tunnel never starts. To mirror the official app, strip FILE-based
    // `cert <file>` / `key <file>` / `pkcs12 <file>` directives.
    //
    // 🔴 CRITICAL: an INLINE `<cert>` block with NO matching `<key>` (exactly
    // this Hiddify config) is INVALID for a certificate auth type — ics-openvpn
    // either rejects it or STALLS waiting for a private key that never comes.
    // Since the config authenticates with username/password (`<auth-user-pass>`
    // present), the client certificate is not actually needed. So: only treat
    // it as a real inline-cert profile when BOTH `<cert>` and `<key>` exist.
    // Otherwise we strip the lone `<cert>`/`<key>` block so the profile parses
    // as pure user/pass (auth type 3) and connects — like the official app.
    final bool hasInlineCert = normalized.contains('<cert>');
    final bool hasInlineKey = normalized.contains('<key>');
    final bool hasInlinePkcs12 = normalized.contains('<pkcs12>');
    final bool validInlineCertPair =
        (hasInlineCert && hasInlineKey) || hasInlinePkcs12;
    if (!validInlineCertPair) {
      // Remove any lone inline <cert>/<key> blocks (they'd stall the core).
      for (final tag in ['cert', 'key']) {
        normalized = normalized.replaceAll(
          RegExp('<$tag>.*?</$tag>\\s*', dotAll: true),
          '',
        );
      }
      // Remove file-based cert/key/pkcs12 directives.
      normalized = normalized.replaceAll(
          RegExp(r'^\s*cert\s+\S.*$', multiLine: true), '');
      normalized = normalized.replaceAll(
          RegExp(r'^\s*key\s+\S.*$', multiLine: true), '');
      normalized = normalized.replaceAll(
          RegExp(r'^\s*pkcs12\s+\S.*$', multiLine: true), '');
    }

    // Fix 2: add credentials only if provided and config has none of its own.
    if (!requiresAuth) {
      final user = effectiveUsername;
      final pass = effectivePassword;
      if (user != null && user.isNotEmpty) {
        final authBlock =
            '\n<auth-user-pass>\n$user\n${pass ?? ""}\n</auth-user-pass>\n';
        if (normalized.contains('<ca>')) {
          normalized = normalized.replaceFirst('<ca>', '$authBlock<ca>');
        } else if (normalized.contains('<cert>')) {
          normalized = normalized.replaceFirst('<cert>', '$authBlock<cert>');
        } else {
          normalized = normalized + authBlock;
        }
      }
    }

    // Data-saver for OpenVPN.
    //
    // FORCING a compression algorithm (e.g. `compress lz4-v2`) is unsafe: if the
    // server hasn't enabled that exact algorithm the framing byte mismatches and
    // the tunnel either drops packets (visible quality drop) or fails outright.
    // Modern OpenVPN discourages pushing compression at all for this reason.
    //
    // The safe, universal knob is `allow-compression asym`: it lets the client
    // DECOMPRESS data the server chooses to send compressed (that's the download
    // direction — the bulk of a user's traffic and where a data-saver pays off)
    // WITHOUT ever forcing outbound compression that could corrupt framing. If
    // the server sends nothing compressed, it is a harmless no-op — so it never
    // breaks a working config, unlike a forced `compress` line.
    //
    // Do not rewrite a profile's compression settings when the data-saver
    // toggle is off. Some servers require the compression mode declared by the
    // profile; replacing it with `allow-compression no` lets the control
    // channel connect while silently breaking the data channel.
    if (trafficCompressionEnabled) {
      // With data-saver enabled, make decompression asymmetric and avoid
      // forcing compression in the upload direction.
      normalized = normalized.replaceAll(
          RegExp(r'^\s*(compress|comp-lzo|allow-compression)\b.*$',
              multiLine: true),
          '');
      normalized = normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      normalized = 'allow-compression asym\n$normalized';
    }

    // ALWAYS end with a newline (see plugin's client-cert-not-required append).
    if (!normalized.endsWith('\n')) normalized = '$normalized\n';

    _normalizedCache = normalized;
    _normalizedCompression = trafficCompressionEnabled;
    return normalized;
  }

  /// A copy of the normalized config with EVERY client-certificate artifact
  /// removed — inline `<cert>` / `<key>` / `<pkcs12>` blocks AND file-based
  /// `cert` / `key` / `pkcs12` directives. Used when the user chooses to
  /// "connect anyway" after a certificate warning (mirroring the official
  /// OpenVPN app): the profile then parses as pure user/pass (auth type 3),
  /// passing ics-openvpn's checkProfile so the tunnel actually starts.
  String get configWithoutClientCert {
    String c = normalizedConfig;
    // Remove inline blocks (multiline).
    for (final tag in ['cert', 'key', 'pkcs12']) {
      c = c.replaceAll(
        RegExp('<$tag>.*?</$tag>\\s*', dotAll: true),
        '',
      );
    }
    // Remove file-based directives (whole line).
    c = c.replaceAll(RegExp(r'^\s*cert\s+\S.*$', multiLine: true), '');
    c = c.replaceAll(RegExp(r'^\s*key\s+\S.*$', multiLine: true), '');
    c = c.replaceAll(RegExp(r'^\s*pkcs12\s+\S.*$', multiLine: true), '');
    if (!c.endsWith('\n')) c = '$c\n';
    return c;
  }

  /// Get server address from config
  String? get serverAddress => _p['server'];

  /// Get server port from config
  String? get serverPort => _p['port'];

  /// Get protocol from config
  String? get protocol => _p['proto'];

  @override
  String toString() =>
      'OpenVpnConfig(name: $name, server: $serverAddress:$serverPort, proto: $protocol)';
}
