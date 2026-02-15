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
    
    return result;
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
