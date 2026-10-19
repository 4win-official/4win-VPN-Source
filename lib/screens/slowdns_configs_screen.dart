import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/slowdns_config.dart';
import 'dns_scanner_screen.dart';
import 'slowdns_profile_screen.dart';

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

  Future<void> _showAddConfigDialog(BuildContext context) async {
    final provider = context.read<VpnProvider>();
    final config = await Navigator.of(context).push<SlowDnsConfig>(
      MaterialPageRoute(
        builder: (_) => SlowDnsProfileScreen(onSave: provider.addSlowDnsConfig),
      ),
    );
    if (!context.mounted || config == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: const Text('Profile added')));
  }
}
