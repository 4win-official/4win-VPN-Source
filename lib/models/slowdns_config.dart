import 'dart:convert';

/// A standalone dnstt profile. DNS transport is not a tunnel protocol selector.
class SlowDnsConfig {
  final String name;
  final String domain;
  final String nameServer;
  final String? pubKey;
  final int? port;
  final String? username;
  final String? password;
  final String dnsTransport;
  final String? dohUrl;
  final List<String> resolvers;
  final DateTime addedAt;

  SlowDnsConfig({
    required this.name,
    required this.domain,
    required this.nameServer,
    this.pubKey,
    this.port,
    this.username,
    this.password,
    this.dnsTransport = 'udp',
    this.dohUrl,
    this.resolvers = const [],
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  static const supportedTransports = {'udp', 'dot', 'doh'};
  int get defaultPort => switch (dnsTransport.toLowerCase()) {
    'dot' => 853,
    'doh' => 443,
    _ => 53,
  };
  int get effectivePort => port ?? defaultPort;

  List<String> get validationErrors {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Name is required.');
    if (resolvers.length > 31) {
      errors.add('Use at most 32 resolver candidates per profile.');
    }
    if (!isValidDnsName(domain)) errors.add('Domain must be a valid DNS name.');
    if (!isValidPublicKey(pubKey)) {
      errors.add('A 64-character hexadecimal public key is required.');
    }
    if (!supportedTransports.contains(dnsTransport.toLowerCase())) {
      errors.add('DNS transport must be udp, dot, or doh.');
    }
    if (effectivePort < 1 || effectivePort > 65535) {
      errors.add('Port must be between 1 and 65535.');
    }
    if (dnsTransport.toLowerCase() == 'doh') {
      if (!isValidDohUrl(dohUrl)) {
        errors.add('DoH URL must be a valid HTTPS URL.');
      }
    } else {
      if (!isValidResolverEndpoint(nameServer) ||
          resolvers.any((value) => !isValidResolverEndpoint(value))) {
        errors.add(
          'Resolvers must be valid IP addresses or hostnames; enter the port separately.',
        );
      }
    }
    final hasUsername = username?.isNotEmpty ?? false;
    final hasPassword = password?.isNotEmpty ?? false;
    if (hasUsername != hasPassword) {
      errors.add(
        'Remote SOCKS5 username and password must be provided together.',
      );
    } else if (hasUsername &&
        (utf8.encode(username!).length > 255 ||
            utf8.encode(password!).length > 255)) {
      errors.add(
        'Remote SOCKS5 username and password must be 1 to 255 UTF-8 bytes.',
      );
    }
    return errors;
  }

  String? get validationError {
    final errors = validationErrors;
    return errors.isEmpty ? null : errors.first;
  }

  bool get isValid => validationError == null;

  static bool isValidPublicKey(String? value) =>
      value != null && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value.trim());

  /// Profile UI accepts host:port; storage/native APIs still use separate fields.
  static ({String host, int port})? parseResolverAddress(
    String value, {
    int defaultPort = 53,
  }) {
    final text = value.trim();
    if (defaultPort < 1 || defaultPort > 65535 || text.isEmpty) return null;
    String host = text;
    int port = defaultPort;
    if (':'.allMatches(text).length > 1 ||
        text.contains('[') ||
        text.contains(']')) {
      return null;
    }
    if (text.contains(':')) {
      final parts = text.split(':');
      host = parts.first;
      if (!RegExp(r'^[0-9]+$').hasMatch(parts.last)) return null;
      port = int.tryParse(parts.last) ?? 0;
    }
    if (!isValidResolverEndpoint(host) || port < 1 || port > 65535) return null;
    return (host: host, port: port);
  }

  static bool isValidDnsName(String value) {
    final v = value.trim().replaceFirst(RegExp(r'\.$'), '');
    if (v.isEmpty || v.length > 253) return false;
    return v
        .split('.')
        .every(
          (label) =>
              label.length <= 63 &&
              RegExp(
                r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
              ).hasMatch(label),
        );
  }

  /// IPv4 or hostname only. IPv6 is intentionally excluded from Slow DNS.
  static bool isValidResolverEndpoint(String value) {
    final v = value.trim();
    if (v.isEmpty || v.contains(RegExp(r'[\s/@?#%:\[\]]'))) return false;
    if (RegExp(r'^[0-9.]+$').hasMatch(v)) {
      final parts = v.split('.');
      return parts.length == 4 &&
          parts.every(
            (part) =>
                RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part) &&
                int.parse(part) <= 255,
          );
    }
    return isValidDnsName(v);
  }

  static bool isValidDohUrl(String? value) {
    try {
      final uri = Uri.parse(value?.trim() ?? '');
      return uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          isValidResolverEndpoint(uri.host) &&
          uri.userInfo.isEmpty &&
          !uri.hasFragment &&
          uri.port >= 1 &&
          uri.port <= 65535;
    } on FormatException {
      return false;
    }
  }

  List<String> get allResolvers => [nameServer, ...resolvers]
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  Map<String, dynamic> toJson() => {
    'name': name,
    'domain': domain,
    'nameServer': nameServer,
    'pubKey': pubKey,
    'port': port,
    'username': username,
    'password': password,
    'dnsTransport': dnsTransport,
    'dohUrl': dohUrl,
    'resolvers': resolvers,
    'addedAt': addedAt.toIso8601String(),
  };

  factory SlowDnsConfig.fromJson(Map<String, dynamic> json) => SlowDnsConfig(
    name: json['name'] as String,
    domain: json['domain'] as String,
    nameServer: json['nameServer'] as String,
    pubKey: json['pubKey'] as String?,
    port: json['port'] as int?,
    username: json['username'] as String?,
    password: json['password'] as String?,
    dnsTransport: (json['dnsTransport'] as String?) ?? 'udp',
    dohUrl: json['dohUrl'] as String?,
    resolvers:
        (json['resolvers'] as List<dynamic>?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
    addedAt:
        DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
  );

  SlowDnsConfig copyWith({
    String? name,
    String? domain,
    String? nameServer,
    String? pubKey,
    int? port,
    String? username,
    String? password,
    String? dnsTransport,
    String? dohUrl,
    List<String>? resolvers,
    DateTime? addedAt,
  }) => SlowDnsConfig(
    name: name ?? this.name,
    domain: domain ?? this.domain,
    nameServer: nameServer ?? this.nameServer,
    pubKey: pubKey ?? this.pubKey,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    dnsTransport: dnsTransport ?? this.dnsTransport,
    dohUrl: dohUrl ?? this.dohUrl,
    resolvers: resolvers ?? this.resolvers,
    addedAt: addedAt ?? this.addedAt,
  );

  @override
  String toString() =>
      'SlowDnsConfig(name: $name, domain: $domain, transport: $dnsTransport)';
}
