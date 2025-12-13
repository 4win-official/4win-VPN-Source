class VpnServer {
  final String address;
  final int port;
  final String username;
  final String password;
  int? ping;
  bool isConnecting;
  bool isConnected;

  VpnServer({
    required this.address,
    required this.port,
    this.username = 'vpn',
    this.password = 'vpn',
    this.ping,
    this.isConnecting = false,
    this.isConnected = false,
  });

  String get fullAddress => '$address:$port';

  factory VpnServer.fromString(String serverString) {
    final parts = serverString.trim().split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid server format: $serverString');
    }

    return VpnServer(
      address: parts[0],
      port: int.parse(parts[1]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'port': port,
      'username': username,
      'password': password,
      'ping': ping,
      'isConnecting': isConnecting,
      'isConnected': isConnected,
    };
  }

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    return VpnServer(
      address: json['address'] as String,
      port: json['port'] as int,
      username: json['username'] as String? ?? 'vpn',
      password: json['password'] as String? ?? 'vpn',
      ping: json['ping'] as int?,
      isConnecting: json['isConnecting'] as bool? ?? false,
      isConnected: json['isConnected'] as bool? ?? false,
    );
  }

  VpnServer copyWith({
    String? address,
    int? port,
    String? username,
    String? password,
    int? ping,
    bool? isConnecting,
    bool? isConnected,
  }) {
    return VpnServer(
      address: address ?? this.address,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      ping: ping ?? this.ping,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  String toString() => fullAddress;
}
