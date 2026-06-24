import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/xray_server.dart';

/// Server list screen for the Xray protocol (real Xray core / v2rayNG).
/// Shows the locked free subscription group (cannot be deleted) plus the
/// user's own servers. Users can paste vless:// / vmess:// / trojan:// / ss://
/// share links, ping-test (real delay) individually or a whole group, and
/// pick one to connect.
class XrayServersScreen extends StatefulWidget {
  const XrayServersScreen({super.key});

  @override
  State<XrayServersScreen> createState() => _XrayServersScreenState();
}

class _XrayServersScreenState extends State<XrayServersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<VpnProvider>();
      await provider.loadXrayServers();
      // Auto-refresh the free group (throttled to every 6h inside the service).
      await provider.refreshXrayFreeGroup();
    });
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
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

  Future<void> _refreshFreeGroup() async {
    final provider = context.read<VpnProvider>();
    final count = await provider.refreshXrayFreeGroup(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count > 0
            ? 'Free servers updated ($count configs)'
            : 'Could not update free servers'),
        backgroundColor: count > 0 ? Colors.green : Colors.orange,
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
          Consumer<VpnProvider>(
            builder: (context, provider, _) => IconButton(
              icon: provider.xrayRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              tooltip: 'Update free servers',
              onPressed:
                  provider.xrayRefreshing ? null : _refreshFreeGroup,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add server',
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          final all = provider.xrayServers;
          final freeServers =
              all.where((s) => s.isLocked).toList();
          final userServers =
              all.where((s) => !s.isLocked).toList();

          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshFreeGroup,
              child: ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: _buildEmpty(isDark, accent),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshFreeGroup,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (freeServers.isNotEmpty) ...[
                  _buildGroupHeader(
                    provider,
                    isDark,
                    accent,
                    XrayServer.freeGroup,
                    freeServers,
                    locked: true,
                  ),
                  ...freeServers.map((s) => _buildServerTile(
                      provider,
                      s,
                      provider.selectedXrayServer?.id == s.id,
                      isDark,
                      accent)),
                  const SizedBox(height: 16),
                ],
                if (userServers.isNotEmpty) ...[
                  _buildGroupHeader(
                    provider,
                    isDark,
                    accent,
                    'My Servers',
                    userServers,
                    locked: false,
                  ),
                  ...userServers.map((s) => _buildServerTile(
                      provider,
                      s,
                      provider.selectedXrayServer?.id == s.id,
                      isDark,
                      accent)),
                ],
              ],
            ),
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

  Widget _buildGroupHeader(VpnProvider provider, bool isDark, Color accent,
      String title, List<XrayServer> servers,
      {required bool locked}) {
    final testing = provider.xrayGroupTesting;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4, left: 4, right: 4),
      child: Row(
        children: [
          Icon(locked ? Icons.lock : Icons.folder,
              size: 18, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$title (${servers.length})',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: testing
                ? null
                : () async {
                    await provider.testXrayServers(servers);
                  },
            icon: testing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed, size: 18),
            label: Text(testing ? 'Testing…' : 'Test all'),
            style: TextButton.styleFrom(foregroundColor: accent),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark, Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rocket_launch,
              size: 64, color: accent.withValues(alpha: 0.6)),
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
              'Pull down to load free servers, or tap "Add Server" to paste '
              'a vless://, vmess://, trojan:// or ss:// share link.',
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

  Color _pingColor(int? ping) {
    if (ping == null) return Colors.grey;
    if (ping < 0) return Colors.redAccent;
    if (ping < 300) return Colors.green;
    if (ping < 800) return Colors.orange;
    return Colors.deepOrange;
  }

  String _pingLabel(int? ping) {
    if (ping == null) return '—';
    if (ping < 0) return 'fail';
    return '$ping ms';
  }

  Widget _buildServerTile(VpnProvider provider, XrayServer s, bool selected,
      bool isDark, Color accent) {
    final testing = provider.xrayTestingIds.contains(s.id);
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
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                '${s.protocol.toUpperCase()} • ${s.fullAddress}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // Real-delay (ping) badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _pingColor(s.ping).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _pingLabel(s.ping),
                style: TextStyle(
                  color: _pingColor(s.ping),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Real-delay test button (v2rayNG style)
            IconButton(
              tooltip: 'Real delay test',
              icon: testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.speed, color: accent),
              onPressed:
                  testing ? null : () => provider.measureXrayDelay(s),
            ),
            if (selected)
              Icon(Icons.check_circle, color: accent)
            else
              const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            // Locked servers cannot be deleted.
            if (!s.isLocked)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.redAccent),
                onPressed: () => provider.removeXrayServer(s.id),
              )
            else
              const Padding(
                padding: EdgeInsets.only(left: 8, right: 8),
                child: Icon(Icons.lock_outline,
                    color: Colors.grey, size: 18),
              ),
          ],
        ),
        onTap: () => provider.selectXrayServer(s),
      ),
    );
  }
}
