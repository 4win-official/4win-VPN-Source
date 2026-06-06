class DnsServer {
  final String name;
  final String primaryDns;
  final String? secondaryDns;
  final String description;
  final String country;
  int? ping;
  bool isCustom;

  DnsServer({
    required this.name,
    required this.primaryDns,
    this.secondaryDns,
    required this.description,
    required this.country,
    this.ping,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'primaryDns': primaryDns,
        'secondaryDns': secondaryDns,
        'description': description,
        'country': country,
        'ping': ping,
        'isCustom': isCustom,
      };

  factory DnsServer.fromJson(Map<String, dynamic> json) {
    return DnsServer(
      name: json['name'] as String,
      primaryDns: json['primaryDns'] as String,
      secondaryDns: json['secondaryDns'] as String?,
      description: json['description'] as String,
      country: json['country'] as String,
      ping: json['ping'] as int?,
      isCustom: json['isCustom'] as bool? ?? false,
    );
  }

  // لیست DNS های عمومی پیش‌فرض
  static List<DnsServer> getPublicDnsServers() {
    return [
      // ===== DNS های ضد تحریم ایرانی (Anti-Censorship) =====
      DnsServer(
        name: 'Shekan',
        primaryDns: '178.22.122.100',
        secondaryDns: '185.51.200.2',
        description: 'Iranian anti-censorship DNS',
        country: 'Iran',
      ),
      DnsServer(
        name: 'Bertina',
        primaryDns: '193.186.32.32',
        secondaryDns: null,
        description: 'Iranian anti-censorship DNS',
        country: 'Iran',
      ),
      DnsServer(
        name: 'Electro',
        primaryDns: '78.157.42.100',
        secondaryDns: '78.157.42.101',
        description: 'Iranian anti-censorship DNS',
        country: 'Iran',
      ),
      DnsServer(
        name: 'DNS Pro',
        primaryDns: '87.107.110.109',
        secondaryDns: null,
        description: 'Iranian anti-censorship DNS',
        country: 'Iran',
      ),
      DnsServer(
        name: 'Begzar',
        primaryDns: '185.55.226.26',
        secondaryDns: '185.55.225.25',
        description: 'Iranian anti-censorship DNS',
        country: 'Iran',
      ),
      DnsServer(
        name: 'Radar Game',
        primaryDns: '10.202.10.10',
        secondaryDns: '10.202.10.11',
        description: 'Iranian anti-censorship DNS',
        country: 'Iran',
      ),
      DnsServer(
        name: 'Online.403',
        primaryDns: '10.202.10.202',
        secondaryDns: '10.202.10.102',
        description: 'Iranian anti-censorship DNS',
        country: 'Iran',
      ),
      // ===== DNS های عمومی جهانی =====
      DnsServer(
        name: 'Google DNS',
        primaryDns: '8.8.8.8',
        secondaryDns: '8.8.4.4',
        description: 'Fast, secure and reliable',
        country: 'Global',
      ),
      DnsServer(
        name: 'Cloudflare',
        primaryDns: '1.1.1.1',
        secondaryDns: '1.0.0.1',
        description: 'Privacy-focused DNS',
        country: 'Global',
      ),
      DnsServer(
        name: 'OpenDNS',
        primaryDns: '208.67.222.222',
        secondaryDns: '208.67.220.220',
        description: 'Secure and fast',
        country: 'Global',
      ),
      DnsServer(
        name: 'Quad9',
        primaryDns: '9.9.9.9',
        secondaryDns: '149.112.112.112',
        description: 'Blocks malicious domains',
        country: 'Global',
      ),
      DnsServer(
        name: 'AdGuard DNS',
        primaryDns: '94.140.14.14',
        secondaryDns: '94.140.15.15',
        description: 'Blocks ads and trackers',
        country: 'Global',
      ),
      DnsServer(
        name: 'DNS.Watch',
        primaryDns: '84.200.69.80',
        secondaryDns: '84.200.70.40',
        description: 'No logging, uncensored',
        country: 'Germany',
      ),
      DnsServer(
        name: 'Comodo Secure DNS',
        primaryDns: '8.26.56.26',
        secondaryDns: '8.20.247.20',
        description: 'Security-focused',
        country: 'Global',
      ),
      DnsServer(
        name: 'CleanBrowsing',
        primaryDns: '185.228.168.9',
        secondaryDns: '185.228.169.9',
        description: 'Family-safe filtering',
        country: 'Global',
      ),
      DnsServer(
        name: 'Alternate DNS',
        primaryDns: '76.76.19.19',
        secondaryDns: '76.223.122.150',
        description: 'Fast and reliable',
        country: 'USA',
      ),
      DnsServer(
        name: 'Level3',
        primaryDns: '209.244.0.3',
        secondaryDns: '209.244.0.4',
        description: 'High performance',
        country: 'USA',
      ),
    ];
  }
}
