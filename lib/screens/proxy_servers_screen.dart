import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../widgets/four_win_loader.dart';
import '../models/proxy_server.dart';
import '../services/proxy_service.dart';

class ProxyServersScreen extends StatefulWidget {
  const ProxyServersScreen({super.key});

  @override
  State<ProxyServersScreen> createState() => _ProxyServersScreenState();
}

class _ProxyServersScreenState extends State<ProxyServersScreen> {
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VpnProvider>().loadProxyServers();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _exportServers(List<ProxyServer> servers, String title) async {
    final plain = servers.map((s) => s.exportLink).join('\n');
    final encoded = base64.encode(utf8.encode(plain));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$title (${servers.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy proxy links'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: plain));
                if (ctx.mounted) Navigator.pop(ctx);
                _toast('Proxy links copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Copy as subscription (base64)'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: encoded));
                if (ctx.mounted) Navigator.pop(ctx);
                _toast('Subscription copied');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final scheme = ValueNotifier<String>('socks5');
    final host = TextEditingController();
    final port = TextEditingController(text: '1080');
    final user = TextEditingController();
    final pass = TextEditingController();
    final remark = TextEditingController();

    Future<void> addSingle(BuildContext dialogContext) async {
      final h = host.text.trim();
      final p = int.tryParse(port.text.trim());
      if (h.isEmpty || p == null || p < 1 || p > 65535) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Enter a valid host and port')),
        );
        return;
      }
      try {
        final ui = user.text.isEmpty
            ? ''
            : '${Uri.encodeComponent(user.text)}:${Uri.encodeComponent(pass.text)}@';
        final safeHost = h.contains(':') && !h.startsWith('[') ? '[$h]' : h;
        final fragment = remark.text.trim().isEmpty
            ? ''
            : '#${Uri.encodeComponent(remark.text.trim())}';
        final link = '${scheme.value}://$ui$safeHost:$p$fragment';
        final provider = dialogContext.read<VpnProvider>();
        final added = await provider.addProxyServers(link);
        if (!dialogContext.mounted) return;
        Navigator.pop(dialogContext);
        _toast(added > 0 ? 'Proxy added successfully' : 'Proxy already exists');
      } catch (e) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('Invalid proxy: $e')),
        );
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Proxy'),
        content: ValueListenableBuilder<String>(
          valueListenable: scheme,
          builder: (ctx, selectedScheme, _) {
            if (selectedScheme == 'socks4' && port.text == '1080') {
              // SOCKS4 normally uses 1080; keep the user's value if changed.
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedScheme,
                    decoration: const InputDecoration(
                      labelText: 'Protocol',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'socks5', child: Text('SOCKS5')),
                      DropdownMenuItem(value: 'socks4', child: Text('SOCKS4')),
                      DropdownMenuItem(value: 'http', child: Text('HTTP')),
                    ],
                    onChanged: (v) {
                      if (v != null) scheme.value = v;
                      if (v == 'http' && port.text == '1080') port.text = '8080';
                      if (v != 'http' && port.text == '8080') port.text = '1080';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: host,
                    decoration: const InputDecoration(
                      labelText: 'Host / IP',
                      hintText: 'proxy.example.com',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: user,
                    decoration: const InputDecoration(
                      labelText: 'Username (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remark,
                    decoration: const InputDecoration(
                      labelText: 'Name / Remark (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Bulk import / Import group'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _showBulkImportDialog();
                    },
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => addSingle(ctx), child: const Text('Add Proxy')),
        ],
      ),
    );
    scheme.dispose();
    host.dispose();
    port.dispose();
    user.dispose();
    pass.dispose();
    remark.dispose();
  }

  Future<void> _showBulkImportDialog() async {
    final group = TextEditingController(text: 'My Proxy Group');
    final links = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk Import Proxies'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: group,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: links,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Proxy links',
                  hintText: 'socks5://user:pass@host:1080\nsocks4://host:1080\nhttp://host:8080',
                  helperText: 'One proxy per line. host:port is also accepted.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final raw = links.text.trim();
              final groupName = group.text.trim().isEmpty ? 'My Proxy Group' : group.text.trim();
              if (raw.isEmpty) return;
              final service = ProxyServerService();
              final all = await service.loadServers();
              final existing = all.map((s) => s.link).toSet();
              var added = 0;
              for (final line in raw.split(RegExp(r'[\r\n]+'))) {
                final value = line.trim();
                if (value.isEmpty || existing.contains(value)) continue;
                try {
                  final server = ProxyServer.fromLink(value, group: groupName);
                  if (existing.add(server.link)) {
                    all.add(server);
                    added++;
                  }
                } catch (_) {}
              }
              if (added > 0) await service.saveServers(all);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) await context.read<VpnProvider>().loadProxyServers();
              _toast(added > 0 ? '$added proxy(s) imported into "$groupName"' : 'No valid new proxies found');
            },
            child: const Text('Import Group'),
          ),
        ],
      ),
    );
    group.dispose();
    links.dispose();
  }

  Future<void> _refreshAll() async {
    final count = await context.read<VpnProvider>().refreshProxySubs(force: true);
    if (!mounted) return;
    _toast(count > 0 ? 'Proxies updated ($count)' : 'No subscription proxies to update');
  }

  Future<void> _refreshOneGroup(VpnProvider provider, String group, String title) async {
    final count = await provider.refreshProxyOneGroup(group);
    if (!mounted) return;
    _toast(count >= 0 ? '"$title" updated ($count)' : 'Could not update "$title"');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = Colors.tealAccent.shade700;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxy Servers'),
        actions: [
          Consumer<VpnProvider>(
            builder: (context, p, _) => IconButton(
              icon: p.proxyRefreshing
                  ? const SizedBox(width: 18, height: 18, child: FourWinLoader(strokeWidth: 2))
                  : const Icon(Icons.cloud_download_outlined),
              tooltip: 'Update subscriptions',
              onPressed: p.proxyRefreshing ? null : _refreshAll,
            ),
          ),
          Consumer<VpnProvider>(
            builder: (context, p, _) => IconButton(
              icon: p.proxyGroupTesting
                  ? const SizedBox(width: 18, height: 18, child: FourWinLoader(strokeWidth: 2))
                  : const Icon(Icons.speed),
              tooltip: 'Test all',
              onPressed: p.proxyGroupTesting ? null : () {
                p.testAllProxyGroups();
                _toast('Testing all proxies…');
              },
            ),
          ),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add proxy', onPressed: _showAddDialog),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          final all = provider.proxyServers;
          if (all.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz, size: 64, color: accent.withValues(alpha: .6)),
                    const SizedBox(height: 16),
                    const Text('No proxy servers yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('Use Add Proxy to enter a proxy as a form, or import many proxies as a group.', textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: _showAddDialog, icon: const Icon(Icons.add), label: const Text('Add Proxy')),
                  ],
                ),
              ),
            );
          }
          final groups = <String, List<ProxyServer>>{};
          for (final s in all) groups.putIfAbsent(s.group, () => []).add(s);
          final rows = <Widget>[];
          for (final entry in groups.entries) {
            final key = entry.key;
            final servers = entry.value;
            final title = key.isEmpty ? 'My Proxies' : key;
            final expanded = _expandedGroups.contains(key);
            final locked = key.isNotEmpty;
            final selectedGroup = locked && provider.proxyGroupSelectedFor(key);
            final selectedServer = servers.any((s) => provider.selectedProxyServer?.id == s.id);
            final highlight = selectedGroup || selectedServer;
            rows.add(Container(
              margin: EdgeInsets.only(bottom: expanded ? 0 : 12),
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: .04) : Colors.black.withValues(alpha: .03),
                borderRadius: expanded ? const BorderRadius.vertical(top: Radius.circular(14)) : BorderRadius.circular(14),
                border: Border.all(color: highlight ? accent : Colors.transparent, width: 2),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(locked ? Icons.cloud_outlined : Icons.folder, color: accent),
                    title: Text('$title (${servers.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: locked ? Text(selectedGroup ? 'Selected — connects to the fastest proxy' : 'Tap to select • auto-picks fastest') : null,
                    onTap: locked ? () => provider.selectProxyGroup(key) : () => setState(() => expanded ? _expandedGroups.remove(key) : _expandedGroups.add(key)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selectedGroup) Icon(Icons.check_circle, color: accent),
                        if (locked && key != ProxyServerService.userLinksGroup)
                          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Update group', onPressed: () => _refreshOneGroup(provider, key, title)),
                        IconButton(icon: Icon(Icons.copy_all, color: accent), tooltip: 'Export group', onPressed: () => _exportServers(servers, title)),
                        IconButton(icon: Icon(Icons.speed, color: accent), tooltip: 'Test group', onPressed: provider.proxyGroupTesting ? null : () => provider.testProxyServers(servers)),
                        IconButton(icon: Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down), onPressed: () => setState(() => expanded ? _expandedGroups.remove(key) : _expandedGroups.add(key)),),
                      ],
                    ),
                  ),
                  if (expanded)
                    for (final s in servers) _buildServerTile(provider, s, provider.selectedProxyServer?.id == s.id, dark, accent),
                ],
              ),
            ));
          }
          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView(padding: const EdgeInsets.all(12), children: rows),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: accent,
        icon: const Icon(Icons.add),
        label: const Text('Add Proxy'),
      ),
    );
  }

  Widget _buildServerTile(VpnProvider provider, ProxyServer s, bool selected, bool dark, Color accent) {
    final testing = provider.proxyTestingIds.contains(s.id);
    final ping = s.ping;
    final pingColor = ping == null ? Colors.grey : ping < 300 ? Colors.green : ping < 800 ? Colors.orange : Colors.deepOrange;
    return ListTile(
      dense: true,
      leading: CircleAvatar(backgroundColor: accent.withValues(alpha: .15), child: Icon(Icons.swap_horiz, color: accent, size: 18)),
      title: Text(s.remark.isEmpty ? s.address : s.remark, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Row(
        children: [
          Expanded(child: Text('${s.protocol.toUpperCase()} • ${s.fullAddress}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 6),
          Text(ping == null ? '—' : '$ping ms', style: TextStyle(color: pingColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: Icon(Icons.copy, color: accent, size: 18), tooltip: 'Copy link', onPressed: () async { await Clipboard.setData(ClipboardData(text: s.exportLink)); _toast('Link copied'); }),
          IconButton(icon: testing ? const SizedBox(width: 18, height: 18, child: FourWinLoader(strokeWidth: 2)) : Icon(Icons.network_ping, color: accent, size: 20), tooltip: 'Ping test', onPressed: testing ? null : () => provider.pingProxyServer(s)),
          IconButton(icon: Icon(Icons.public, color: accent, size: 20), tooltip: 'Open-site test', onPressed: testing ? null : () => provider.openSiteTestProxyServer(s)),
          Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? accent : Colors.grey),
          if (s.group.isEmpty || s.group == ProxyServerService.userLinksGroup)
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => provider.removeProxyServer(s.id)),
        ],
      ),
      onTap: () => provider.selectProxyServer(s),
    );
  }
}
