import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../widgets/four_win_loader.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  bool _isTestingServers = false;
  int _testRun = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const LocalizedText(
          'Servers',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_isTestingServers)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent),
              tooltip: context.l10n.text('Stop test'),
              onPressed: _stopFindingBestServer,
            )
          else
            IconButton(
              icon: const Icon(Icons.speed, color: Colors.black54),
              tooltip: context.l10n.text('Find Best Server'),
              onPressed: () => _findBestServer(context),
            ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingServers) {
            return const Center(
              child: FourWinLoader(
                color: Colors.black87,
              ),
            );
          }

          if (provider.errorMessage != null && provider.servers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    LocalizedText(
                      provider.errorMessage!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () => provider.loadServers(forceRefresh: true),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        side: const BorderSide(color: Colors.black12),
                      ),
                      child: const LocalizedText(
                        'Retry',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.servers.isEmpty) {
            return const Center(
              child: LocalizedText(
                'No servers available',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: provider.servers.length,
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              color: Colors.black12,
            ),
            itemBuilder: (context, index) {
              final server = provider.servers[index];
              final isSelected = provider.selectedServer?.fullAddress == server.fullAddress;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                  child: Icon(
                    Icons.storage,
                    color: isSelected
                        ? const Color(0xFF4CAF50)
                        : Colors.black54,
                  ),
                ),
                title: Text(
                  server.address,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LocalizedText(
                    'Port: ${server.port}${server.ping != null ? ' • ${server.ping}ms' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ),
                trailing: isSelected
                    ? const Icon(
                        Icons.check_circle,
                        color: Color(0xFF4CAF50),
                      )
                    : null,
                onTap: () {
                  provider.selectServer(server);
                  Navigator.pop(context);
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _findBestServer(BuildContext context) async {
    if (_isTestingServers) return;
    final run = ++_testRun;
    setState(() {
      _isTestingServers = true;
    });

    final provider = Provider.of<VpnProvider>(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    
    await provider.findBestServer();

    if (!mounted || run != _testRun) return;
    
    setState(() {
      _isTestingServers = false;
    });

    if (provider.selectedServer != null) {
      messenger.showSnackBar(
        SnackBar(
          content: LocalizedText(
            'Best server: ${provider.selectedServer!.address} (${provider.selectedServer!.ping}ms)',
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      navigator.pop();
    }
  }

  void _stopFindingBestServer() {
    if (!_isTestingServers) return;
    _testRun++;
    Provider.of<VpnProvider>(context, listen: false).cancelSstpTest();
    setState(() => _isTestingServers = false);
  }
}
