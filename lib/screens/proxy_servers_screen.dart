import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/proxy_server.dart';
import '../services/proxy_service.dart';

/// Server list screen for the dedicated **Proxy** protocol (real SOCKS4 /
/// SOCKS5 / HTTP upstream proxies). Its appearance mirrors the Xray server
/// list (collapsible groups, per-row copy/delete, group export/test) but the
/// servers connect to a REAL proxy. Each server offers TWO tests:
///   • a normal PING test (TCP connect latency to the proxy), and
///   • an "open site" test (a real request routed through the proxy).
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<VpnProvider>();
      await provider.loadProxyServers();
    });
  }

  void _toggleExpanded(String key) {
    if (!_expandedGroups.remove(key)) _expandedGroups.add(key);
  }

  Future<void> _exportServers(List<ProxyServer> servers, String title) async {
    if (servers.isEmpty) return;
    final plain = servers.map((s) => s.exportLink).join('\n');
    final b64 = base64.encode(utf8.encode(plain));
    final hasEncrypted = servers.any((s) => s.encrypted);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Export "$title" (${servers.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (hasEncrypted)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '🔒 Encrypted servers are copied in their protected '
                        '4win form.',
                        style: TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy proxy links'),
              subtitle: const Text('Plain text, one link per line'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: plain));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _toast('${servers.length} link(s) copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Copy as subscription (base64)'),
              subtitle: const Text('Paste into other apps as a sub blob'),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: b64));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _toast('Subscription (base64) copied');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _copyOneServer(ProxyServer s) async {
    await Clipboard.setData(ClipboardData(text: s.exportLink));
    if (!mounted) return;
    _toast(s.encrypted ? 'Encrypted link copied' : 'Link copied');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showAddDialog() async {
    final controller = TextEditingController();
    final clip = await Clipboard.getData('text/plain');
    final clipText = clip?.text ?? '';
    if (RegExp(r'^(socks5|socks4|socks|http|https|4ws)://',
            caseSensitive: false)
        .hasMatch(clipText.trim())) {
      controller.text = clipText.trim();
    }

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Proxy Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste one or more proxy links (socks5://, socks4://, http://) '
              'or a bare host:port (or host:port:user:pass). One per line. '
              'You can also add an http(s) subscription link to load proxies '
              'from it.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'socks5://user:pass@host:1080\n'
                    'http://host:8080\n'
                    'https://example.com/sub.txt',
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
    // A link that is an http(s) subscription URL (has a path) is added as a
    // subscription; raw proxy links are added directly.
    final text = result.trim();
    int added;
    if (_looksLikeSubscription(text)) {
      final ok = await provider.addProxySubUrl(text);
      added = ok ? 1 : 0;
    } else {
      added = await provider.addProxyServers(text);
      // Also handle a mix: if raw add found nothing, try the sub-input path.
      if (added == 0) {
        final ok = await provider.addProxySubUrl(text);
        added = ok ? 1 : 0;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added > 0
            ? 'Added successfully'
            : 'No valid proxy or subscription found'),
        backgroundColor: added > 0 ? Colors.green : Colors.red,
      ),
    );
  }

  bool _looksLikeSubscription(String e) {
    if (!e.startsWith('http://') && !e.startsWith('https://')) return false;
    if (e.contains(RegExp(r'[\r\n]'))) return false;
    try {
      final u = Uri.parse(e);
      final hasPath = u.path.isNotEmpty && u.path != '/';
      return hasPath || u.query.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshAll() async {
    final provider = context.read<VpnProvider>();
    final count = await provider.refreshProxySubs(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count > 0
            ? 'Proxies updated ($count)'
            : 'No subscription proxies to update'),
        backgroundColor: count > 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _refreshOneGroup(
      VpnProvider provider, String groupKey, String title) async {
    final count = await provider.refreshProxyOneGroup(groupKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count >= 0
            ? '"$title" updated ($count)'
            : 'Could not update "$title"'),
        backgroundColor: count >= 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Colors.tealAccent.shade700;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proxy Servers'),
        actions: [
          Consumer<VpnProvider>(
            builder: (context, provider, _) => IconButton(
              icon: provider.proxyRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              tooltip: 'Update subscriptions',
              onPressed: provider.proxyRefreshing ? null : _refreshAll,
            ),
          ),
          Consumer<VpnProvider>(
            builder: (context, provider, _) => IconButton(
              icon: provider.proxyGroupTesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed),
              tooltip: 'Test all',
              onPressed: provider.proxyGroupTesting
                  ? null
                  : () {
                      provider.testAllProxyGroups();
                      _toast('Testing all proxies…');
                    },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add proxy',
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, provider, _) {
          final all = provider.proxyServers;

          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshAll,
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

          final groups = <String, List<ProxyServer>>{};
          for (final s in all) {
            groups.putIfAbsent(s.group, () => []).add(s);
          }
          final individual = groups.remove('') ?? [];

          final orderedKeys = <String>[
            for (final k in groups.keys) k,
          ];

          final rows = <_Row>[];
          void addGroupRows(String key, String title, List<ProxyServer> servers,
              bool locked) {
            final expanded = _expandedGroups.contains(key);
            rows.add(_Row.header(key, title, servers, locked, expanded));
            if (expanded) {
              final show = servers.length > 500 ? 500 : servers.length;
              for (var i = 0; i < show; i++) {
                rows.add(_Row.tile(servers[i], locked));
              }
              if (servers.length > show) {
                rows.add(_Row.more(servers.length - show));
              }
            }
          }

          for (final key in orderedKeys) {
            addGroupRows(key, key, groups[key]!, true);
          }
          if (individual.isNotEmpty) {
            addGroupRows('', 'My Proxies', individual, false);
          }

          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                switch (row.kind) {
                  case _RowKind.header:
                    return _buildGroupHeader(
                      provider: provider,
                      isDark: isDark,
                      accent: accent,
                      title: row.title!,
                      groupKey: row.groupKey!,
                      servers: row.servers!,
                      locked: row.locked,
                      expanded: row.expanded,
                    );
                  case _RowKind.tile:
                    final s = row.server!;
                    return _buildServerTile(
                      provider,
                      s,
                      provider.selectedProxyServer?.id == s.id,
                      isDark,
                      accent,
                    );
                  case _RowKind.more:
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '…and ${row.moreCount} more proxies',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    );
                }
              },
            ),
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

  Widget _buildGroupHeader({
    required VpnProvider provider,
    required bool isDark,
    required Color accent,
    required String title,
    required String groupKey,
    required List<ProxyServer> servers,
    required bool locked,
    required bool expanded,
  }) {
    void onToggleExpand() => setState(() => _toggleExpanded(groupKey));
    final testing = provider.proxyGroupTestingFor(groupKey);
    final anyTesting = provider.proxyGroupTesting;
    final groupSelected = locked && provider.proxyGroupSelectedFor(groupKey);
    final aServerInGroupSelected =
        servers.any((s) => provider.selectedProxyServer?.id == s.id);
    final highlight = groupSelected || aServerInGroupSelected;
    final isRefreshable =
        locked && groupKey != ProxyServerService.userLinksGroup;
    final refreshing = provider.proxyGroupRefreshingFor(groupKey);

    return Container(
      margin: EdgeInsets.only(bottom: expanded ? 0 : 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: expanded
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: locked
                ? () => provider.selectProxyGroup(groupKey)
                : onToggleExpand,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                      !locked
                          ? Icons.folder
                          : (groupKey == ProxyServerService.userLinksGroup
                              ? Icons.list_alt
                              : Icons.cloud_outlined),
                      size: 20,
                      color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$title (${servers.length})',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (locked)
                          Text(
                            groupSelected
                                ? 'Selected — connects to the fastest proxy'
                                : 'Tap to select • auto-picks fastest',
                            style: TextStyle(
                              fontSize: 11,
                              color: groupSelected
                                  ? accent
                                  : (isDark
                                      ? Colors.white54
                                      : Colors.black45),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (groupSelected)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.check_circle, color: accent),
                    ),
                  if (isRefreshable)
                    IconButton(
                      tooltip: 'Update this sub link',
                      icon: refreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.refresh, color: accent),
                      onPressed: refreshing
                          ? null
                          : () => _refreshOneGroup(provider, groupKey, title),
                    ),
                  IconButton(
                    tooltip: 'Export group',
                    icon: Icon(Icons.copy_all, color: accent),
                    onPressed: () => _exportServers(servers, title),
                  ),
                  IconButton(
                    tooltip: 'Test all (open site)',
                    icon: testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.speed, color: accent),
                    onPressed: anyTesting
                        ? null
                        : () => provider.testProxyServers(servers),
                  ),
                  IconButton(
                    tooltip: expanded ? 'Collapse' : 'Expand',
                    icon: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down,
                          color: isDark ? Colors.white70 : Colors.black54),
                    ),
                    onPressed: onToggleExpand,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark, Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz,
              size: 64, color: accent.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text(
            'No proxy servers yet',
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
              'Tap "Add Proxy" to paste a socks5://, socks4:// or http:// '
              'proxy, a bare host:port, or an http(s) subscription link.',
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

  Widget _buildServerTile(VpnProvider provider, ProxyServer s, bool selected,
      bool isDark, Color accent) {
    final testing = provider.proxyTestingIds.contains(s.id);
    return Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.03),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Icon(Icons.swap_horiz, color: accent, size: 18),
        ),
        title: Text(
          s.remark.isEmpty ? s.address : s.remark,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                '${s.protocol.toUpperCase()} • ${s.fullAddress}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _pingColor(s.ping).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _pingLabel(s.ping),
                style: TextStyle(
                  color: _pingColor(s.ping),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Copy link',
              icon: Icon(Icons.copy, color: accent, size: 18),
              onPressed: () => _copyOneServer(s),
            ),
            // TEST 1 — normal ping test (TCP connect latency).
            IconButton(
              tooltip: 'Ping test',
              icon: testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.network_ping, color: accent, size: 20),
              onPressed: testing ? null : () => provider.pingProxyServer(s),
            ),
            // TEST 2 — open-site test (real request through the proxy).
            IconButton(
              tooltip: 'Open-site test',
              icon: Icon(Icons.public, color: accent, size: 20),
              onPressed:
                  testing ? null : () => provider.openSiteTestProxyServer(s),
            ),
            if (selected)
              Icon(Icons.check_circle, color: accent)
            else
              const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            if (s.group.isEmpty || s.group == ProxyServerService.userLinksGroup)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => provider.removeProxyServer(s.id),
              )
            else
              const Padding(
                padding: EdgeInsets.only(left: 8, right: 8),
                child: Icon(Icons.lock_outline, color: Colors.grey, size: 18),
              ),
          ],
        ),
        onTap: () => provider.selectProxyServer(s),
      ),
    );
  }
}

enum _RowKind { header, tile, more }

class _Row {
  final _RowKind kind;
  final String? groupKey;
  final String? title;
  final List<ProxyServer>? servers;
  final ProxyServer? server;
  final bool locked;
  final bool expanded;
  final int moreCount;

  _Row._({
    required this.kind,
    this.groupKey,
    this.title,
    this.servers,
    this.server,
    this.locked = false,
    this.expanded = false,
    this.moreCount = 0,
  });

  factory _Row.header(String groupKey, String title,
          List<ProxyServer> servers, bool locked, bool expanded) =>
      _Row._(
        kind: _RowKind.header,
        groupKey: groupKey,
        title: title,
        servers: servers,
        locked: locked,
        expanded: expanded,
      );

  factory _Row.tile(ProxyServer server, bool locked) =>
      _Row._(kind: _RowKind.tile, server: server, locked: locked);

  factory _Row.more(int count) =>
      _Row._(kind: _RowKind.more, moreCount: count);
}
