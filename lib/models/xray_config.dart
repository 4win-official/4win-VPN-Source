import 'dart:convert';

class XrayConfig {
  final String protocol; // 'vless' or 'vmess'
  final String address;
  final int port;
  final String id; // UUID
  final String? flow; // For VLESS (e.g., 'xtls-rprx-vision')
  final String? encryption; // For VLESS (e.g., 'none')
  final String? security; // 'tls', 'reality', 'none'
  final String? network; // 'tcp', 'ws', 'grpc'
  final String? path; // For WebSocket
  final String? host; // For WebSocket/HTTP
  final String? sni; // Server Name Indication
  final String? fingerprint; // 'chrome', 'firefox', etc.
  final String? publicKey; // For Reality
  final String? shortId; // For Reality
  final String? alpn; // Application-Layer Protocol Negotiation
  final String? headerType; // For TCP
  final String remark; // Config name/description
  final String rawConfig; // Original config string
  
  // For VMess
  final int? alterId; // VMess alterID
  final String? type; // VMess type
  
  // Ping test result
  int? ping;

  XrayConfig({
    required this.protocol,
    required this.address,
    required this.port,
    required this.id,
    this.flow,
    this.encryption,
    this.security,
    this.network,
    this.path,
    this.host,
    this.sni,
    this.fingerprint,
    this.publicKey,
    this.shortId,
    this.alpn,
    this.headerType,
    required this.remark,
    required this.rawConfig,
    this.alterId,
    this.type,
  });

  /// Parse VLESS config (vless://...)
  factory XrayConfig.fromVless(String config) {
    try {
      // Remove 'vless://' prefix
      final uri = Uri.parse(config);
      
      // Extract UUID and address
      final userInfo = uri.userInfo; // UUID
      final address = uri.host;
      final port = uri.port;
      
      // Parse query parameters
      final params = uri.queryParameters;
      
      // Extract remark from fragment
      String remark = 'VLESS Server';
      if (uri.fragment.isNotEmpty) {
        remark = Uri.decodeComponent(uri.fragment);
      }
      
      return XrayConfig(
        protocol: 'vless',
        address: address,
        port: port,
        id: userInfo,
        flow: params['flow'],
        encryption: params['encryption'] ?? 'none',
        security: params['security'] ?? 'none',
        network: params['type'] ?? 'tcp',
        path: params['path'],
        host: params['host'],
        sni: params['sni'],
        fingerprint: params['fp'],
        publicKey: params['pbk'],
        shortId: params['sid'],
        alpn: params['alpn'],
        headerType: params['headerType'],
        remark: remark,
        rawConfig: config,
      );
    } catch (e) {
      throw FormatException('Invalid VLESS config: $e');
    }
  }

  /// Parse VMess config (vmess://...)
  factory XrayConfig.fromVmess(String config) {
    try {
      // Remove 'vmess://' prefix
      final base64Data = config.replaceFirst('vmess://', '');
      
      // Decode Base64
      final jsonString = utf8.decode(base64.decode(base64Data));
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      
      return XrayConfig(
        protocol: 'vmess',
        address: json['add'] as String,
        port: json['port'] is String 
            ? int.parse(json['port'] as String) 
            : json['port'] as int,
        id: json['id'] as String,
        security: json['tls'] as String? ?? json['security'] as String? ?? 'none',
        network: json['net'] as String? ?? 'tcp',
        path: json['path'] as String?,
        host: json['host'] as String?,
        sni: json['sni'] as String?,
        alpn: json['alpn'] as String?,
        remark: json['ps'] as String? ?? 'VMess Server',
        rawConfig: config,
        alterId: json['aid'] is String 
            ? int.parse(json['aid'] as String) 
            : json['aid'] as int?,
        type: json['type'] as String?,
      );
    } catch (e) {
      throw FormatException('Invalid VMess config: $e');
    }
  }

  /// Parse Trojan config from trojan:// URI
  factory XrayConfig.fromTrojan(String config) {
    try {
      // Remove 'trojan://' prefix
      final uri = Uri.parse(config.replaceFirst('trojan://', 'https://'));
      
      // Extract password from user info
      final password = uri.userInfo;
      
      // Extract address and port
      final address = uri.host;
      final port = uri.port != 0 ? uri.port : 443;
      
      // Parse query parameters
      final params = uri.queryParameters;
      
      return XrayConfig(
        protocol: 'trojan',
        address: address,
        port: port,
        id: password, // Password is used as ID in Trojan
        security: params['security'] ?? 'tls',
        network: params['type'] ?? 'tcp',
        sni: params['sni'] ?? address,
        alpn: params['alpn'],
        host: params['host'],
        path: params['path'],
        fingerprint: params['fp'],
        remark: params['#'] ?? Uri.decodeComponent(uri.fragment.isNotEmpty ? uri.fragment : 'Trojan Server'),
        rawConfig: config,
      );
    } catch (e) {
      throw FormatException('Invalid Trojan config: $e');
    }
  }
  
  /// Parse Shadowsocks config from ss:// URI
  factory XrayConfig.fromShadowsocks(String config) {
    try {
      // Remove 'ss://' prefix
      final uri = Uri.parse(config.replaceFirst('ss://', 'https://'));
      
      // Decode user info (method:password)
      final userInfo = utf8.decode(base64.decode(uri.userInfo));
      final parts = userInfo.split(':');
      
      if (parts.length != 2) {
        throw FormatException('Invalid Shadowsocks user info format');
      }
      
      final method = parts[0];
      final password = parts[1];
      
      // Extract address and port
      final address = uri.host;
      final port = uri.port;
      
      return XrayConfig(
        protocol: 'shadowsocks',
        address: address,
        port: port,
        id: password,
        encryption: method,
        remark: Uri.decodeComponent(uri.fragment.isNotEmpty ? uri.fragment : 'Shadowsocks Server'),
        rawConfig: config,
      );
    } catch (e) {
      throw FormatException('Invalid Shadowsocks config: $e');
    }
  }

  /// Auto-detect and parse config
  factory XrayConfig.fromString(String config) {
    if (config.startsWith('vless://')) {
      return XrayConfig.fromVless(config);
    } else if (config.startsWith('vmess://')) {
      return XrayConfig.fromVmess(config);
    } else if (config.startsWith('trojan://')) {
      return XrayConfig.fromTrojan(config);
    } else if (config.startsWith('ss://')) {
      return XrayConfig.fromShadowsocks(config);
    } else {
      throw FormatException('Unsupported protocol');
    }
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol,
      'address': address,
      'port': port,
      'id': id,
      'flow': flow,
      'encryption': encryption,
      'security': security,
      'network': network,
      'path': path,
      'host': host,
      'sni': sni,
      'fingerprint': fingerprint,
      'publicKey': publicKey,
      'shortId': shortId,
      'alpn': alpn,
      'headerType': headerType,
      'remark': remark,
      'rawConfig': rawConfig,
      'alterId': alterId,
      'type': type,
      'ping': ping,
    };
  }

  /// Create from JSON
  factory XrayConfig.fromJson(Map<String, dynamic> json) {
    return XrayConfig(
      protocol: json['protocol'] as String,
      address: json['address'] as String,
      port: json['port'] as int,
      id: json['id'] as String,
      flow: json['flow'] as String?,
      encryption: json['encryption'] as String?,
      security: json['security'] as String?,
      network: json['network'] as String?,
      path: json['path'] as String?,
      host: json['host'] as String?,
      sni: json['sni'] as String?,
      fingerprint: json['fingerprint'] as String?,
      publicKey: json['publicKey'] as String?,
      shortId: json['shortId'] as String?,
      alpn: json['alpn'] as String?,
      headerType: json['headerType'] as String?,
      remark: json['remark'] as String,
      rawConfig: json['rawConfig'] as String,
      alterId: json['alterId'] as int?,
      type: json['type'] as String?,
    )..ping = json['ping'] as int?;
  }

  @override
  String toString() {
    return 'XrayConfig(protocol: $protocol, address: $address:$port, remark: $remark)';
  }
}
