import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/slowdns_config.dart';
import 'dns_scanner_screen.dart';

/// Screen for managing Slow DNS (DNS Tunneling) configurations.
///
class SlowDnsConfigsScreen extends StatefulWidget {
  const SlowDnsConfigsScreen({super.key});

  @override
  State<SlowDnsConfigsScreen> createState() => _SlowDnsConfigsScreenState();
}

class _SlowDnsConfigsScreenState extends State<SlowDnsConfigsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VpnProvider>().loadSlowDnsConfigs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [const Text('Slow DNS')],
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'DNS Scanner',
            icon: const Icon(Icons.radar),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DnsScannerScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          final configs = provider.slowDnsConfigs;

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.orange.withValues(alpha: 0.12),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Requires a dnstt server exposing a remote SOCKS5 endpoint. '
                        'The client forwards TCP through tunneled DNS queries; it does not '
                        'provide SSH or arbitrary UDP tunneling.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: configs.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: configs.length,
                        itemBuilder: (context, index) {
                          final config = configs[index];
                          final isSelected =
                              provider.selectedSlowDnsConfig?.name ==
                              config.name;
                          return _buildConfigCard(
                            context,
                            provider,
                            config,
                            isSelected,
                            isDark,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddConfigDialog(context),
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: const Text('Add Config'),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_queue,
            size: 72,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            'No Slow DNS configs yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Config" to create one',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard(
    BuildContext context,
    VpnProvider provider,
    SlowDnsConfig config,
    bool isSelected,
    bool isDark,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.orange : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        leading: Icon(
          Icons.cloud_queue,
          color: isSelected
              ? Colors.orange
              : (isDark ? Colors.white54 : Colors.black54),
        ),
        title: Text(
          config.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Domain: ${config.domain}'),
            Text(
              config.dnsTransport == 'doh'
                  ? 'DoH: ${config.dohUrl}'
                  : 'NS: ${config.nameServer}:${config.effectivePort}',
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.orange),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _confirmDelete(context, provider, config),
            ),
          ],
        ),
        onTap: () {
          provider.selectSlowDnsConfig(config);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected: ${config.name}'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    VpnProvider provider,
    SlowDnsConfig config,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Config'),
        content: Text('Delete "${config.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              provider.removeSlowDnsConfig(config.name);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddConfigDialog(BuildContext context) {
    final nameController = TextEditingController();
    final domainController = TextEditingController();
    final nsController = TextEditingController();
    final pubKeyController = TextEditingController();
    final portController = TextEditingController(text: '53');
    final dohUrlController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final resolversController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    // DNS transport (SlipNet-inspired): udp | dot | doh
    String dnsTransport = 'udp';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('Add Slow DNS Config'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      hintText: 'My Slow DNS',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: domainController,
                    decoration: const InputDecoration(
                      labelText: 'Domain *',
                      hintText: 'tunnel.example.com',
                    ),
                    validator: (v) => SlowDnsConfig.isValidDnsName(v ?? '')
                        ? null
                        : 'Enter a valid DNS name (for example, tunnel.example.com).',
                  ),
                  TextFormField(
                    controller: nsController,
                    decoration: InputDecoration(
                      labelText: dnsTransport == 'doh'
                          ? 'Name Server (unused for DoH)'
                          : 'Name Server *',
                      hintText: '1.1.1.1',
                      suffixIcon: IconButton(
                        tooltip: 'Find best DNS (Scanner)',
                        icon: const Icon(Icons.radar, color: Colors.orange),
                        onPressed: () async {
                          final picked = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DnsScannerScreen(
                                probeDomain:
                                    domainController.text.trim().isEmpty
                                    ? null
                                    : domainController.text.trim(),
                              ),
                            ),
                          );
                          if (picked != null && picked.isNotEmpty) {
                            nsController.text = picked;
                          }
                        },
                      ),
                    ),
                    validator: (v) =>
                        dnsTransport == 'doh' ||
                            SlowDnsConfig.isValidResolverEndpoint(v ?? '')
                        ? null
                        : 'Enter an IP address or hostname, not a URL.',
                  ),
                  TextFormField(
                    controller: portController,
                    enabled: dnsTransport != 'doh',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '53',
                      helperText:
                          'UDP defaults to 53, DoT to 853. For DoH, set the port in its URL.',
                    ),
                    validator: (v) {
                      final value = int.tryParse(v?.trim() ?? '');
                      return value != null && value >= 1 && value <= 65535
                          ? null
                          : 'Enter a port between 1 and 65535.';
                    },
                  ),
                  TextFormField(
                    controller: pubKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Public Key *',
                      helperText:
                          'Required: exactly 64 hexadecimal characters.',
                    ),
                    validator: (v) => SlowDnsConfig.isValidPublicKey(v)
                        ? null
                        : 'Enter the server public key (64 hex characters).',
                  ),
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Remote SOCKS5 username (optional)',
                      helperText:
                          'Used by the dnstt server SOCKS5 endpoint, not SSH.',
                    ),
                    validator: (v) => _credentialValidator(
                      v,
                      passwordController.text,
                      'Username',
                    ),
                  ),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Remote SOCKS5 password (optional)',
                    ),
                    validator: (v) => _credentialValidator(
                      v,
                      usernameController.text,
                      'Password',
                    ),
                  ),
                  const SizedBox(height: 8),
                  // DNS transport: UDP, DoT, or DoH resolver transport.
                  DropdownButtonFormField<String>(
                    initialValue: dnsTransport,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'DNS Transport',
                      helperText: 'DoH/DoT help bypass DPI on DNS queries',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'udp',
                        child: Text('UDP (Plain, port 53)'),
                      ),
                      DropdownMenuItem(
                        value: 'dot',
                        child: Text('DoT (DNS over TLS)'),
                      ),
                      DropdownMenuItem(
                        value: 'doh',
                        child: Text('DoH (DNS over HTTPS)'),
                      ),
                    ],
                    onChanged: (v) => setLocalState(() {
                      dnsTransport = v ?? 'udp';
                      portController.text = dnsTransport == 'dot'
                          ? '853'
                          : dnsTransport == 'doh'
                          ? '443'
                          : '53';
                    }),
                  ),
                  if (dnsTransport == 'doh')
                    TextFormField(
                      controller: dohUrlController,
                      decoration: const InputDecoration(
                        labelText: 'DoH URL *',
                        hintText: 'https://dns.example.com/dns-query',
                      ),
                      validator: (v) => SlowDnsConfig.isValidDohUrl(v)
                          ? null
                          : 'Enter a valid HTTPS URL.',
                    ),
                  const SizedBox(height: 8),
                  // 🔁 Failover resolvers: multiple resolvers tried concurrently;
                  // the connection uses whichever reaches the server, and falls
                  // back through the list until one works.
                  TextFormField(
                    controller: resolversController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Failover resolvers (optional)',
                      hintText:
                          '8.8.8.8, 1.1.1.1, 9.9.9.9 — comma/space/newline',
                      helperText:
                          'Tried in order after the name server. DoH uses its URL only.',
                      suffixIcon: IconButton(
                        tooltip: 'Scan & pick a resolver',
                        icon: const Icon(Icons.radar, color: Colors.orange),
                        onPressed: () async {
                          final picked = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DnsScannerScreen(
                                probeDomain:
                                    domainController.text.trim().isEmpty
                                    ? null
                                    : domainController.text.trim(),
                              ),
                            ),
                          );
                          if (picked != null && picked.isNotEmpty) {
                            final cur = resolversController.text.trim();
                            setLocalState(() {
                              resolversController.text = cur.isEmpty
                                  ? picked
                                  : '$cur, $picked';
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final config = SlowDnsConfig(
                  name: nameController.text.trim(),
                  domain: domainController.text.trim(),
                  nameServer: nsController.text.trim(),
                  port: int.tryParse(portController.text.trim()),
                  pubKey: pubKeyController.text.trim().isEmpty
                      ? null
                      : pubKeyController.text.trim(),
                  username: usernameController.text.trim().isEmpty
                      ? null
                      : usernameController.text,
                  password: passwordController.text.isEmpty
                      ? null
                      : passwordController.text,
                  dnsTransport: dnsTransport,
                  dohUrl:
                      dnsTransport != 'doh' ||
                          dohUrlController.text.trim().isEmpty
                      ? null
                      : dohUrlController.text.trim(),
                  resolvers: resolversController.text
                      .split(RegExp(r'[\s,;\n]+'))
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList(),
                );

                if (config.validationError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(config.validationError!)),
                  );
                  return;
                }
                final provider = ctx.read<VpnProvider>();
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);

                final success = await provider.addSlowDnsConfig(config);

                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Config added'
                          : 'Failed: name may already exist',
                    ),
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  String? _credentialValidator(String? value, String peer, String label) {
    final current = value ?? '';
    if (current.isEmpty && peer.isEmpty) return null;
    if (current.isEmpty || peer.isEmpty)
      return 'Remote SOCKS5 username and password are required together.';
    if (current.length > 255) return '$label must be 1 to 255 characters.';
    return null;
  }
}
