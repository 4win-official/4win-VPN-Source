import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/xray_server.dart';

/// Server list screen for the Xray protocol (real Xray core / v2rayNG).
/// Users paste vless:// / vmess:// / trojan:// / ss:// share links, the app
/// parses them, lets the user pick one and connect.
class XrayServersScreen extends StatefulWidget {
  const XrayServersScreen({super.key});

  @override
  State<XrayServersScreen> createState() => _XrayServersScreenState();
}

class _XrayServersScreenState extends State<XrayServersScreen> {
  @override
  void initState() {
    super.initState();
    // Make sure servers are loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VpnProvider>().loadXrayServers();
    });
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    // Pre-fill from clipboard if it looks like a share link.
    final clip = await Clipboard.getData('text/plain');
    final clipText = clip?.text ?? '';
    if (RegExp(r'^(vless|vmess|trojan|ss)://', caseSensitive: false)
        .hasMatch(clipText.trim())) {
      controller.text = clipText.trim();
    }

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Xray Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste one or more share links (vless://, vmess://, '
              'trojan://, ss://). One per line.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'vless://...\nvmess://...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    if (!mounted) return;
    final provider = context.read<VpnProvider>();
    final added = await provider.addXrayServers(result);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added > 0
            ? 'Added $added server${added == 1 ? '' : 's'}'
            : 'No valid links found'),
        backgroundColor: added > 0 ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Colors.tealAccent.shade700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xray Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add server',
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          final servers = provider.xrayServers;
          return Column(
            children: [
              Expanded(
                child: servers.isEmpty
                    ? _buildEmpty(isDark, accent)
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: servers.length,
                        itemBuilder: (context, i) {
                          final s = servers[i];
                          final selected =
                              provider.selectedXrayServer?.id == s.id;
                          return _buildServerTile(
                              provider, s, selected, isDark, accent);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: accent,
        icon: const Icon(Icons.add),
        label: const Text('Add Server'),
      ),
    );
  }

  Widget _buildEmpty(bool isDark, Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rocket_launch, size: 64, color: accent.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text(
            'No Xray servers yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Tap "Add Server" and paste a vless://, vmess://, '
              'trojan:// or ss:// share link.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerTile(VpnProvider provider, XrayServer s, bool selected,
      bool isDark, Color accent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Icon(Icons.dns, color: accent),
        ),
        title: Text(
          s.remark.isEmpty ? s.address : s.remark,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${s.protocol.toUpperCase()} • ${s.fullAddress}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              Icon(Icons.check_circle, color: accent)
            else
              const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => provider.removeXrayServer(s.id),
            ),
          ],
        ),
        onTap: () => provider.selectXrayServer(s),
      ),
    );
  }
}
