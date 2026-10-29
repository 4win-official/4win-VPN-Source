import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../models/dns_server.dart';
import '../providers/vpn_provider.dart';
import '../widgets/four_win_loader.dart';
import '../services/probe_cancellation.dart';

class DnsServersScreen extends StatefulWidget {
  const DnsServersScreen({super.key});

  @override
  State<DnsServersScreen> createState() => _DnsServersScreenState();
}

class _DnsServersScreenState extends State<DnsServersScreen> {
  bool _isTesting = false;
  ProbeCancellation? _testCancellation;
  List<DnsServer> _dnsServers = [];

  @override
  void initState() {
    super.initState();
    _loadDnsServers();
  }

  Future<void> _loadDnsServers() async {
    final provider = Provider.of<VpnProvider>(context, listen: false);
    final servers = await provider.getAllDnsServers();
    setState(() {
      _dnsServers = servers;
    });
  }

  Future<void> _testDnsServers() async {
    if (_isTesting) return;
    final cancellation = ProbeCancellation();
    _testCancellation = cancellation;
    setState(() {
      _isTesting = true;
    });

    final provider = Provider.of<VpnProvider>(context, listen: false);
    try {
      final testedServers = await provider.testAllDnsServers(
        _dnsServers,
        cancellation: cancellation,
      );
      if (mounted && !cancellation.isCancelled) {
        setState(() => _dnsServers = testedServers);
      }
    } finally {
      if (identical(_testCancellation, cancellation)) _testCancellation = null;
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _showAddCustomDnsDialog() {
    final nameController = TextEditingController();
    final primaryController = TextEditingController();
    final secondaryController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
          title: LocalizedText(
            'Add Custom DNS',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: context.l10n.text('Name'),
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: primaryController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: context.l10n.text('Primary DNS (required)'),
                    hintText: '8.8.8.8',
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: secondaryController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: context.l10n.text('Secondary DNS (optional)'),
                    hintText: '8.8.4.4',
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: context.l10n.text('Description (optional)'),
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: LocalizedText('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || primaryController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: LocalizedText('Name and Primary DNS are required')),
                  );
                  return;
                }

                final provider = Provider.of<VpnProvider>(context, listen: false);
                await provider.addCustomDns(DnsServer(
                  name: nameController.text,
                  primaryDns: primaryController.text,
                  secondaryDns: secondaryController.text.isEmpty ? null : secondaryController.text,
                  description: descController.text.isEmpty ? 'Custom DNS' : descController.text,
                  country: 'Custom',
                  isCustom: true,
                ));

                Navigator.pop(context);
                _loadDnsServers();
              },
              child: const LocalizedText('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: LocalizedText(
          'DNS Servers',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isTesting ? Icons.close : Icons.refresh,
              color: _isTesting
                  ? Colors.redAccent
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
            tooltip: context.l10n.text(_isTesting ? 'Stop testing' : 'Test all servers'),
            onPressed: _isTesting
                ? () => _testCancellation?.cancel()
                : _testDnsServers,
          ),
          IconButton(
            icon: Icon(
              Icons.add,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            onPressed: _showAddCustomDnsDialog,
          ),
        ],
      ),
      body: _isTesting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FourWinLoader(),
                  const SizedBox(height: 16),
                  LocalizedText(
                    'Testing DNS servers...',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () => _testCancellation?.cancel(),
                    icon: const Icon(Icons.close),
                    label: const LocalizedText('Stop testing'),
                  ),
                ],
              ),
            )
          : _dnsServers.isEmpty
              ? Center(
                  child: LocalizedText(
                    'No DNS servers available',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Test All Servers Button
                    Container(
                      margin: const EdgeInsets.all(16),
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _testDnsServers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF00FF88) : Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.speed, color: Colors.white),
                        label: const LocalizedText(
                          'Test All Servers',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _dnsServers.length,
                        itemBuilder: (context, index) {
                    final server = _dnsServers[index];
                    return Card(
                      color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          Icons.dns,
                          color: server.ping != null
                              ? _getPingColor(server.ping!)
                              : (isDark ? Colors.white38 : Colors.black38),
                        ),
                        title: Text(
                          server.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            LocalizedText(
                              'Primary: ${server.primaryDns}',
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            if (server.secondaryDns != null)
                              LocalizedText(
                                'Secondary: ${server.secondaryDns}',
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            Text(
                              server.description,
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // نمایش ping
                            if (server.ping != null)
                              LocalizedText(
                                '${server.ping}ms',
                                style: TextStyle(
                                  color: _getPingColor(server.ping!),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              )
                            else
                              Text(
                                'N/A',
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            // دکمه حذف (همیشه برای custom servers)
                            if (server.isCustom)
                              IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  color: Colors.red[300],
                                  size: 18,
                                ),
                                onPressed: () async {
                                  final provider = Provider.of<VpnProvider>(context, listen: false);
                                  await provider.removeCustomDns(server.primaryDns);
                                  _loadDnsServers();
                                },
                              ),
                          ],
                        ),
                        onTap: () async {
                          final provider = Provider.of<VpnProvider>(context, listen: false);
                          
                          // ✅ انتخاب DNS server و اتصال خودکار (حتی بدون تست)
                          await provider.selectDnsServerAndConnect(server);
                          
                          // بستن صفحه و برگشت به Home
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    );
                  },
                ),
                    ),
                  ],
                ),
    );
  }

  Color _getPingColor(int ping) {
    if (ping < 50) return Colors.green;
    if (ping < 100) return Colors.lightGreen;
    if (ping < 200) return Colors.orange;
    return Colors.red;
  }
}
