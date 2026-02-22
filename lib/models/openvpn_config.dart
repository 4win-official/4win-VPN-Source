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
    
    // پیدا کردن proto (protocol: tcp or udp)
    final protoRegex = RegExp(r'proto\s+(\S+)');
    final protoMatch = protoRegex.firstMatch(configContent);
    if (protoMatch != null) {
      result['proto'] = protoMatch.group(1) ?? 'udp';
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
  
  /// Get normalized config with fixes for common issues
  String get normalizedConfig {
    String normalized = config;
    
    // ✅ Fix 1: Convert "proto tcp" to "proto tcp-client"
    // OpenVPN requires tcp-client for client configs, not just tcp
    normalized = normalized.replaceAll(RegExp(r'\bproto\s+tcp\b'), 'proto tcp-client');
    
    // ✅ Fix 2: Ensure auth-user-pass is present if credentials are provided
    final hasAuthBlock = normalized.contains('<auth-user-pass>');
    final hasAuthLine = normalized.contains(RegExp(r'\bauth-user-pass\b'));
    
    if (!hasAuthBlock && !hasAuthLine) {
      // اگر credentials داریم ولی auth-user-pass در config نیست
      final user = effectiveUsername;
      final pass = effectivePassword;
      
      if (user != null && user.isNotEmpty) {
        // اضافه کردن auth block
        final authBlock = '\n<auth-user-pass>\n$user\n${pass ?? ""}\n</auth-user-pass>\n';
        
        // اضافه کردن قبل از خطوط cert یا key
        if (normalized.contains('<ca>')) {
          normalized = normalized.replaceFirst('<ca>', '$authBlock<ca>');
        } else if (normalized.contains('<cert>')) {
          normalized = normalized.replaceFirst('<cert>', '$authBlock<cert>');
        } else {
          // اضافه کردن به انتها
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
