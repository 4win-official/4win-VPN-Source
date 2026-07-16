/// Slow DNS (DNS Tunneling) configuration model
///
/// A Slow DNS config describes how to tunnel traffic through DNS queries.
/// It is primarily intended for use under heavy censorship where regular
/// VPN protocols are blocked but DNS traffic still flows.
class SlowDnsConfig {
  final String name; // نام کانفیگ
  final String domain; // دامنه‌ی تونل DNS (مثال: tunnel.example.com)
  final String nameServer; // آدرس Name Server / Resolver (مثال: 1.1.1.1)
  final String? pubKey; // کلید عمومی سرور SlowDNS (اختیاری)
  final int? port; // پورت (پیش‌فرض 53)
  final String? username; // نام کاربری (اختیاری)
  final String? password; // رمز عبور (اختیاری)
  // نوع انتقال DNS برای تونل (الهام‌گرفته از SlipNet): udp | dot | doh
  // udp = رزولوِر معمولی روی پورت 53 (پیش‌فرض)
  // dot = DNS over TLS، doh = DNS over HTTPS (برای عبور از DPI)
  final String dnsTransport;
  // آدرس سرور DoH (فقط وقتی dnsTransport == 'doh')، مثال: https://1.1.1.1/dns-query
  final String? dohUrl;
  final DateTime addedAt; // تاریخ اضافه شدن

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
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// پورت موثر (پیش‌فرض 53 برای DNS)
  int get effectivePort => port ?? 53;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'domain': domain,
      'nameServer': nameServer,
      'pubKey': pubKey,
      'port': port,
      'username': username,
      'password': password,
      'dnsTransport': dnsTransport,
      'dohUrl': dohUrl,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory SlowDnsConfig.fromJson(Map<String, dynamic> json) {
    return SlowDnsConfig(
      name: json['name'] as String,
      domain: json['domain'] as String,
      nameServer: json['nameServer'] as String,
      pubKey: json['pubKey'] as String?,
      port: json['port'] as int?,
      username: json['username'] as String?,
      password: json['password'] as String?,
      dnsTransport: (json['dnsTransport'] as String?) ?? 'udp',
      dohUrl: json['dohUrl'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  /// Create a copy with modified fields
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
    DateTime? addedAt,
  }) {
    return SlowDnsConfig(
      name: name ?? this.name,
      domain: domain ?? this.domain,
      nameServer: nameServer ?? this.nameServer,
      pubKey: pubKey ?? this.pubKey,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      dnsTransport: dnsTransport ?? this.dnsTransport,
      dohUrl: dohUrl ?? this.dohUrl,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  String toString() {
    return 'SlowDnsConfig(name: $name, domain: $domain, ns: $nameServer:$effectivePort)';
  }
}
