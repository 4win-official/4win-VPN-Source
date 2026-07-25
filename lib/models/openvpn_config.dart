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
  String? _normalizedCache;
  String get normalizedConfig {
    final cached = _normalizedCache;
    if (cached != null) return cached;

    String normalized = config;

    // Fix 1: whole-line `proto tcp` → `proto tcp-client`.
    normalized = normalized.replaceAllMapped(
      RegExp(r'^(\s*proto\s+)tcp\s*$', multiLine: true),
      (m) => '${m.group(1)}tcp-client',
    );

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

    // ALWAYS end with a newline. This is what makes the plugin's
    // `config += "client-cert-not-required"` (appended when certIsRequired ==
    // false) land on its OWN line instead of being glued onto the last config
    // line — the difference between a profile that parses and one that stalls.
    if (!normalized.endsWith('\n')) normalized = '$normalized\n';

    _normalizedCache = normalized;
    return normalized;
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
