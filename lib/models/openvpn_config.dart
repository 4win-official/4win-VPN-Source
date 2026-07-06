/// OpenVPN configuration model
class OpenVpnConfig {
  final String name; // نام کانفیگ
  final String config; // محتوای فایل .ovpn
  final String? username; // نام کاربری (اختیاری)
  final String? password; // رمز عبور (اختیاری)
  final DateTime addedAt; // تاریخ اضافه شدن
  
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
  
  /// Parse OpenVPN config file to extract server info
  static Map<String, String> parseConfigFile(String configContent) {
    final result = <String, String>{};
    
    // پیدا کردن remote (server address and port)
    final remoteRegex = RegExp(r'remote\s+(\S+)\s+(\d+)');
    final remoteMatch = remoteRegex.firstMatch(configContent);
    if (remoteMatch != null) {
      result['server'] = remoteMatch.group(1) ?? '';
      result['port'] = remoteMatch.group(2) ?? '';
    }
    
    // پیدا کردن proto (protocol: tcp, tcp-client, udp, udp4, udp6)
    final protoRegex = RegExp(r'proto\s+(tcp-client|tcp|udp6|udp4|udp)');
    final protoMatch = protoRegex.firstMatch(configContent);
    if (protoMatch != null) {
      var proto = protoMatch.group(1) ?? 'udp';
      // Normalize: tcp → tcp-client (for display purposes)
      if (proto == 'tcp') {
        proto = 'tcp-client';
      }
      result['proto'] = proto;
    } else {
      // Default to UDP if not specified
      result['proto'] = 'udp';
    }
    
    // ✅ Extract username/password from config file
    // Format 1: <auth-user-pass> ... </auth-user-pass>
    final authBlockRegex = RegExp(r'<auth-user-pass>\s*(.+?)\s*</auth-user-pass>', dotAll: true);
    final authBlockMatch = authBlockRegex.firstMatch(configContent);
    if (authBlockMatch != null) {
      final authContent = authBlockMatch.group(1)?.trim() ?? '';
      final lines = authContent.split('\n');
      if (lines.length >= 2) {
        result['username'] = lines[0].trim();
        result['password'] = lines[1].trim();
      } else if (lines.length == 1) {
        // فقط username (password خالی)
        result['username'] = lines[0].trim();
        result['password'] = '';
      }
    }
    
    return result;
  }
  
  /// Get embedded username from config file
  String? get embeddedUsername {
    final parsed = parseConfigFile(config);
    return parsed['username'];
  }
  
  /// Get embedded password from config file
  String? get embeddedPassword {
    final parsed = parseConfigFile(config);
    return parsed['password'];
  }
  
  /// Get effective username (embedded or user-provided)
  String? get effectiveUsername {
    return username ?? embeddedUsername;
  }
  
  /// Get effective password (embedded or user-provided)
  String? get effectivePassword {
    return password ?? embeddedPassword;
  }
  
  /// Get normalized config.
  ///
  /// IMPORTANT: The official OpenVPN Connect app succeeds with a huge number of
  /// configs precisely because it feeds them to the core essentially UNCHANGED.
  /// Our earlier normalizer was too aggressive — it force-injected DNS
  /// (dhcp-option DNS), persist-key/persist-tun/nobind/resolv-retry, and (worst
  /// of all) `connect-retry-max 3`, which makes the client give up after only a
  /// few attempts. Those injections conflict with directives the server pushes
  /// and are the reason many configs that work in the official app failed here.
  ///
  /// We now do ONLY the two minimal, universally-safe fixes:
  ///   1. `proto tcp`  → `proto tcp-client` (the core requires the -client form)
  ///   2. inject an `<auth-user-pass>` block ONLY when the user supplied
  ///      credentials AND the config has no auth directive of its own.
  /// Everything else is left exactly as the user imported it.
  String get normalizedConfig {
    String normalized = config;

    // Fix 1: `proto tcp` → `proto tcp-client`. Match only whole-line proto
    // directives so we don't touch tokens inside comments or blocks.
    normalized = normalized.replaceAllMapped(
      RegExp(r'^(\s*proto\s+)tcp\s*$', multiLine: true),
      (m) => '${m.group(1)}tcp-client',
    );

    // Fix 2: add credentials ONLY if the user provided them and the config has
    // no auth-user-pass of its own. Never touch configs that already carry auth.
    final hasAuthBlock = normalized.contains('<auth-user-pass>');
    final hasAuthLine =
        normalized.contains(RegExp(r'^\s*auth-user-pass\b', multiLine: true));

    if (!hasAuthBlock && !hasAuthLine) {
      final user = effectiveUsername;
      final pass = effectivePassword;
      if (user != null && user.isNotEmpty) {
        final authBlock = '\n<auth-user-pass>\n$user\n${pass ?? ""}\n</auth-user-pass>\n';
        if (normalized.contains('<ca>')) {
          normalized = normalized.replaceFirst('<ca>', '$authBlock<ca>');
        } else if (normalized.contains('<cert>')) {
          normalized = normalized.replaceFirst('<cert>', '$authBlock<cert>');
        } else {
          normalized = normalized + authBlock;
        }
      }
    }

    return normalized;
  }
  
  /// Get server address from config
  String? get serverAddress {
    final parsed = parseConfigFile(config);
    return parsed['server'];
  }
  
  /// Get server port from config
  String? get serverPort {
    final parsed = parseConfigFile(config);
    return parsed['port'];
  }
  
  /// Get protocol from config
  String? get protocol {
    final parsed = parseConfigFile(config);
    return parsed['proto'];
  }
  
  @override
  String toString() {
    return 'OpenVpnConfig(name: $name, server: $serverAddress:$serverPort, proto: $protocol)';
  }
}
