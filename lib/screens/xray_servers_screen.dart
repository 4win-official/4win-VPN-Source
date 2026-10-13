import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/xray_server.dart';
import '../services/xray_service.dart';

/// Server list screen for the Xray protocol (real Xray core / v2rayNG).
/// Servers are shown in collapsible groups: the locked free subscription
/// group ("4win Free Servers", cannot be deleted) and the user's own servers.
/// Tapping a group header selects the whole group as the connection target
/// (the app will delay-test it and pick the fastest on connect). Tapping the
/// down-arrow expands/collapses the group in place. Users can also paste
/// vless:// / vmess:// / trojan:// / ss:// share links and ping-test servers.
class XrayServersScreen extends StatefulWidget {
  const XrayServersScreen({super.key});

  @override
  State<XrayServersScreen> createState() => _XrayServersScreenState();
}

class _XrayServersScreenState extends State<XrayServersScreen> {
  // Which groups are currently expanded (by group name / title). Groups start
  // collapsed so the list stays tidy.
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<VpnProvider>();
      // لود سریع از حافظه تا لیست فوراً نمایش داده شود.
      await provider.loadXrayServers();
      // آپدیت ساب‌های پیش‌فرض (Free + Plus) فقط موقع باز شدن اپ در Loading
      // screen انجام می‌شود؛ دیگر هر بار ورود به این صفحه رفرش نمی‌کنیم.
      // کاربر می‌تواند دستی با دکمه‌ی رفرش لیست را به‌روز کند.
    });
  }

  void _toggleExpanded(String key) {
    if (!_expandedGroups.remove(key)) _expandedGroups.add(key);
  }

  /// Export one or more servers, exactly matching the import format:
  /// plain share links, one per line. Offers copying the raw links or a
  /// base64-encoded subscription blob (same as many providers use).
  Future<void> _exportServers(List<XrayServer> servers, String title) async {
    if (servers.isEmpty) return;
    // Use exportLink: encrypted servers are copied back in their ENCRYPTED
    // (4ws://) form so the real share link never leaves the app.
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
              title: const Text('Copy share links'),
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

  /// Copy a SINGLE server's link straight to the clipboard (no bottom sheet).
  /// Normal servers copy their plain share link; encrypted (4ws://) servers
  /// copy their protected form. This is the fast path used by the per-row copy
  /// icon so a normal server always copies exactly its own working link.
  Future<void> _copyOneServer(XrayServer s) async {
    final text = s.exportLink;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast(s.encrypted ? 'Encrypted link copied' : 'Link copied');
  }

  Future<void> _editServer(XrayServer server) async {
    if (server.encrypted ||
        (server.group.isNotEmpty &&
            server.group != XrayServerService.userLinksGroup)) {
      _toast('This server is protected and cannot be edited');
      return;
    }
    final nameController = TextEditingController(text: server.remark);
    final linkController = TextEditingController(text: server.link);
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: linkController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Share link / configuration',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (nameController.text.trim(), linkController.text.trim()),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.$2.isEmpty || !mounted) return;
    try {
      final parsed = XrayServer.fromLink(result.$2);
      final updated = XrayServer(
        id: server.id,
        remark: result.$1.isEmpty ? parsed.remark : result.$1,
        link: parsed.link,
        protocol: parsed.protocol,
        address: parsed.address,
        port: parsed.port,
        addedAt: server.addedAt,
        ping: parsed.link == server.link ? server.ping : null,
        group: server.group,
      );
      final ok = await context.read<VpnProvider>().updateXrayServer(updated);
      if (mounted) _toast(ok ? 'Server updated' : 'Could not update server');
    } catch (_) {
      _toast('Invalid Xray link');
    }
  }

  Future<void> _editSubscriptionGroup(
      VpnProvider provider, String groupKey, String title) async {
    if (XrayServer.isBuiltInGroup(groupKey)) {
      _toast('This subscription is protected');
      return;
    }
    final oldUrl = await provider.xraySubUrlForGroup(groupKey);
    if (oldUrl == null || !mounted) return;
    final urlController = TextEditingController(text: oldUrl);
    final nameController = TextEditingController(text: title);
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit subscription group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Subscription URL',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (nameController.text.trim(), urlController.text.trim()),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.$2.isEmpty || !mounted) return;
    var ok = true;
    if (result.$2 != oldUrl) {
      ok = await provider.changeXraySubUrl(oldUrl, result.$2);
    }
    if (ok) {
      final currentUrl = result.$2 == oldUrl ? oldUrl : result.$2;
      await provider.setXraySubName(currentUrl, result.$1);
    }
    if (mounted) _toast(ok ? 'Subscription group updated' : 'Could not update group');
  }

  Future<void> _confirmDeleteServer(XrayServer s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete server?'),
        content: Text('Remove "${s.remark.isEmpty ? s.address : s.remark}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<VpnProvider>().removeXrayServer(s.id);
    }
  }
  Future<void> _confirmDeleteGroup(String groupKey, String title) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete servers from "$title"?'),
        content: const Text(
          'The group itself will remain. Choose which servers to remove.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'untested'),
            child: const Text('Delete servers without a ping'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'bad'),
            child: const Text('Delete failed or bad-ping servers'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('Delete all servers in this group'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (mode != null && mounted) {
      final removed = await context
          .read<VpnProvider>()
          .removeXrayGroupServers(groupKey, mode);
      if (mounted) {
        _toast(removed == 0
            ? 'No matching servers found'
            : '$removed server${removed == 1 ? '' : 's'} deleted');
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _showAddDialog() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Add to Xray'),
              subtitle: Text('Choose a server or a subscription group'),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Add server'),
              subtitle: const Text('Paste one or more share links'),
              onTap: () => Navigator.pop(ctx, 'server'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Add subscription group'),
              subtitle: const Text('Add an HTTP(S) subscription URL'),
              onTap: () => Navigator.pop(ctx, 'subscription'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'subscription') {
      await _showAddSubscriptionDialog();
    } else {
      await _showAddServerDialog();
    }
  }

  Future<void> _showAddSubscriptionDialog() async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Subscription Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Subscription URL',
                hintText: 'https://example.com/sub.txt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Group name (optional)',
                hintText: 'My subscription',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              (urlController.text.trim(), nameController.text.trim()),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null || result.$1.isEmpty || !mounted) return;
    final ok = await context.read<VpnProvider>().addXraySubUrl(
          result.$1,
          name: result.$2.isEmpty ? null : result.$2,
        );
    if (mounted) _toast(ok ? 'Subscription group added' : 'Could not add subscription');
  }

  Future<void> _showAddServerDialog() async {
    final controller = TextEditingController();
    final clip = await Clipboard.getData('text/plain');
    final clipText = clip?.text ?? '';
    if (RegExp(r'^(vless|vmess|trojan|ss|4ws)://', caseSensitive: false)
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
              'trojan://, ss://) or 4win encrypted links (4ws://). '
              'One per line.',
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

  /// Update a SINGLE subscription group: clears its servers and re-downloads
  /// them from that sub link's URL.
  Future<void> _refreshOneGroup(
      VpnProvider provider, String groupKey, String title) async {
    final count = await provider.refreshXrayOneGroup(groupKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count >= 0
            ? '"$title" updated ($count configs)'
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
              onPressed: provider.xrayRefreshing ? null : _refreshFreeGroup,
            ),
          ),
          Consumer<VpnProvider>(
            builder: (context, provider, _) => IconButton(
              icon: provider.xrayGroupTesting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed),
              tooltip: 'Test all groups',
              onPressed: provider.xrayGroupTesting
                  ? null
                  : () {
                      provider.testAllXrayGroups();
                      _toast('Testing all servers…');
                    },
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

          // Group servers by their group name, preserving list order. Empty
          // group (individual user servers) is shown last as "My Servers".
          final groups = <String, List<XrayServer>>{};
          for (final s in all) {
            groups.putIfAbsent(s.group, () => []).add(s);
          }
          final individual = groups.remove('') ?? [];

          // Pin built-in default groups (Free, then Plus) FIRST — always on top
          // of the list — then the remaining (user) groups in their order.
          // A built-in group with NO servers simply isn't a key here, so an
          // empty Plus subscription is not shown at all.
          final orderedKeys = <String>[
            if (groups.containsKey(XrayServer.freeGroup)) XrayServer.freeGroup,
            if (groups.containsKey(XrayServer.plusGroup)) XrayServer.plusGroup,
            for (final k in groups.keys)
              if (!XrayServer.isBuiltInGroup(k)) k,
          ];

          // PERFORMANCE: keep only one lightweight descriptor per group. The
          // previous implementation allocated one _Row object per visible
          // server before ListView.builder could do its job. That made a 2k
          // group janky and made 10k groups impractical. The builder below
          // resolves an index to a server on demand, so off-screen configs do
          // not create widgets or row objects at all.
          const maxVisiblePerGroup = 10000;
          final specs = <_GroupSpec>[
            for (final key in orderedKeys)
              _GroupSpec(key, key, groups[key]!, true),
            if (individual.isNotEmpty)
              _GroupSpec('', 'My Servers', individual, false),
          ];
          int rowCountFor(_GroupSpec spec) {
            if (!_expandedGroups.contains(spec.key)) return 1;
            final shown = spec.servers.length > maxVisiblePerGroup
                ? maxVisiblePerGroup
                : spec.servers.length;
            return 1 + shown + (spec.servers.length > shown ? 1 : 0);
          }

          final itemCount = specs.fold<int>(0, (sum, spec) => sum + rowCountFor(spec));

          return RefreshIndicator(
            onRefresh: _refreshFreeGroup,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                var localIndex = index;
                for (final spec in specs) {
                  final count = rowCountFor(spec);
                  if (localIndex >= count) {
                    localIndex -= count;
                    continue;
                  }
                  final expanded = _expandedGroups.contains(spec.key);
                  if (localIndex == 0) {
                    return _buildGroupHeader(
                      provider: provider,
                      isDark: isDark,
                      accentIn: accent,
                      title: spec.title,
                      groupKey: spec.key,
                      servers: spec.servers,
                      locked: spec.locked,
                      expanded: expanded,
                    );
                  }
                  final serverIndex = localIndex - 1;
                  final shown = spec.servers.length > maxVisiblePerGroup
                      ? maxVisiblePerGroup
                      : spec.servers.length;
                  if (serverIndex < shown) {
                    final s = spec.servers[serverIndex];
                    final groupAccent = spec.key == XrayServer.plusGroup
                        ? const Color(0xFFE6B800)
                        : accent;
                    return _buildServerTile(
                      provider,
                      s,
                      provider.selectedXrayServer?.id == s.id,
                      isDark,
                      groupAccent,
                      key: ValueKey('xray-server-${s.id}'),
                      groupAccent: groupAccent,
                      groupLast: serverIndex == shown - 1 && spec.servers.length <= shown,
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '…and ${spec.servers.length - shown} more servers',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
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

  /// A collapsible group HEADER only (tap = select group, arrow = expand).
  /// The server tiles themselves are rendered as separate rows by the lazy
  /// ListView.builder in [build] so a huge group never builds all its tiles at
  /// once.
  Widget _buildGroupHeader({
    required VpnProvider provider,
    required bool isDark,
    required Color accentIn,
    required String title,
    required String groupKey,
    required List<XrayServer> servers,
    required bool locked,
    required bool expanded,
  }) {
    void onToggleExpand() => setState(() => _toggleExpanded(groupKey));
    // The Plus built-in group gets a distinctive GOLD frame; everything else
    // uses the passed-in (green) accent.
    final Color accent = groupKey == XrayServer.plusGroup
        ? const Color(0xFFE6B800)
        : accentIn;
    // Only this group's spinner shows while this group is being tested.
    final testing = provider.xrayGroupTestingFor(groupKey);
    final tcpTesting = provider.xrayGroupTcpTestingFor(groupKey);
    // A named group can be selected as a whole; a specific selected server in
    // this group also counts as "this group active".
    final groupSelected = locked && provider.xrayGroupSelectedFor(groupKey);
    final aServerInGroupSelected = servers
        .any((s) => provider.selectedXrayServer?.id == s.id);
    final highlight = groupSelected || aServerInGroupSelected;
    // A group is refreshable only if it's backed by a subscription URL — the
    // built-in free group or a user sub-link group. The user-pasted links
    // group ("My Sub Links") and individual servers have no source URL.
    final isRefreshable =
        locked && groupKey != XrayServerService.userLinksGroup;
    final isUserSubscription =
        isRefreshable && !XrayServer.isBuiltInGroup(groupKey);

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
          color: expanded
              ? accent.withValues(alpha: highlight ? 0.95 : 0.45)
              : (highlight ? accent : Colors.transparent),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // ---- Header ----
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: locked
                ? () => provider.selectXrayGroup(groupKey)
                : onToggleExpand,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                      !locked
                          ? Icons.folder
                          : (groupKey == XrayServer.plusGroup
                              ? Icons.workspace_premium
                              : (groupKey == XrayServer.freeGroup
                                  ? Icons.lock
                                  : Icons.cloud_outlined)),
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
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SizeTransition(
                                  sizeFactor: animation,
                                  axisAlignment: -1,
                                  child: child,
                                ),
                              ),
                          child: (testing || tcpTesting)
                              ? Row(
                                  key: const ValueKey('group-testing'),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.8,
                                        color: accent,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      tcpTesting
                                          ? 'TCP ping in progress…'
                                          : 'Ping in progress…',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  locked
                                      ? (groupSelected
                                          ? 'Selected — connects to the fastest server'
                                          : 'Tap to select • auto-picks fastest')
                                      : 'Tap to select a server',
                                  key: const ValueKey('group-idle'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: groupSelected
                                        ? accent
                                        : (isDark
                                            ? Colors.white54
                                            : Colors.black45),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  // Selected indicator for the whole free group
                  if (groupSelected)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.check_circle, color: accent),
                    ),
                  // Export whole group (copy all links to clipboard)
                  IconButton(
                    tooltip: 'Export group',
                    icon: Icon(Icons.copy_all, color: accent),
                    onPressed: () => _exportServers(servers, title),
                  ),
                  IconButton(
                    tooltip: 'Delete selected servers',
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => _confirmDeleteGroup(groupKey, title),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More group actions',
                    icon: Icon(Icons.more_vert, color: accent),
                    itemBuilder: (ctx) => [
                      if (isUserSubscription)
                        const PopupMenuItem(
                          value: 'edit_subscription',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit subscription'),
                          ),
                        ),
                      if (isRefreshable)
                        const PopupMenuItem(
                          value: 'refresh',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.refresh),
                            title: Text('Update group'),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'sort',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.sort),
                          title: Text('Sort by ping'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'url_ping',
                        enabled: !testing,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: testing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.speed),
                          title: const Text('URL ping all'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'tcp_ping',
                        enabled: !tcpTesting,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: tcpTesting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cable),
                          title: const Text('TCP ping all'),
                        ),
                      ),
                    ],
                    onSelected: (action) {
                      switch (action) {
                        case 'edit_subscription':
                          _editSubscriptionGroup(provider, groupKey, title);
                          break;
                        case 'refresh':
                          _refreshOneGroup(provider, groupKey, title);
                          break;
                        case 'sort':
                          provider.sortXrayGroupByPing(groupKey);
                          break;
                        case 'url_ping':
                          provider.testXrayServers(servers);
                          break;
                        case 'tcp_ping':
                          provider.testXrayTcpServers(servers);
                          break;
                      }
                    },
                  ),
                  // Expand / collapse arrow
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
          // Server tiles are rendered as separate lazy rows by the parent
          // ListView.builder (see [build]); the header stops here.
          if (expanded)
            Divider(
              height: 1,
              color: accent.withValues(alpha: 0.45),
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

  Widget _buildServerTile(
    VpnProvider provider,
    XrayServer s,
    bool selected,
    bool isDark,
    Color accent, {
    Key? key,
    Color? groupAccent,
    bool groupLast = false,
  }) {
    final testing = provider.xrayTestingIds.contains(s.id);
    final tcpTesting = provider.xrayTcpTestingIds.contains(s.id);
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: value,
          child: Opacity(opacity: value, child: child),
        ),
      ),
      child: Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: groupLast
            ? const BorderRadius.vertical(bottom: Radius.circular(14))
            : null,
        border: groupAccent == null
            ? null
            : Border(
                left: BorderSide(
                    color: groupAccent.withValues(alpha: 0.85), width: 2),
                right: BorderSide(
                    color: groupAccent.withValues(alpha: 0.85), width: 2),
                bottom: groupLast
                    ? BorderSide(
                        color: groupAccent.withValues(alpha: 0.85), width: 2)
                    : BorderSide.none,
              ),
      ),
      child: ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: accent.withValues(alpha: 0.15),
        child: Icon(Icons.dns, color: accent, size: 18),
      ),
      title: Text(
        s.remark.isEmpty ? s.address : s.remark,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${s.protocol.toUpperCase()} • ${s.fullAddress}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 5),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                if (testing || tcpTesting)
                  _testingBadge(tcpTesting ? 'TCP testing…' : 'Ping testing…')
                else
                  _pingBadge('Ping', s.ping),
              ],
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy link',
            icon: Icon(Icons.copy, color: accent, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyOneServer(s),
          ),
          PopupMenuButton<String>(
            tooltip: 'More server actions',
            icon: Icon(Icons.more_vert, color: accent),
            itemBuilder: (ctx) => [
              if (!s.encrypted &&
                  (s.group.isEmpty ||
                      s.group == XrayServerService.userLinksGroup))
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                  ),
                ),
              PopupMenuItem(
                value: 'url_ping',
                enabled: !testing,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: testing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.speed),
                  title: const Text('URL ping'),
                ),
              ),
              PopupMenuItem(
                value: 'tcp_ping',
                enabled: !tcpTesting,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: tcpTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cable),
                  title: const Text('TCP ping'),
                ),
              ),
            ],
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  _editServer(s);
                  break;
                case 'url_ping':
                  provider.measureXrayDelay(s);
                  break;
                case 'tcp_ping':
                  provider.measureXrayTcpPing(s);
                  break;
              }
            },
          ),
          if (selected)
            Icon(Icons.check_circle, color: accent)
          else
            const Icon(Icons.radio_button_unchecked, color: Colors.grey),
          if (s.group.isEmpty || s.group == XrayServerService.userLinksGroup)
            IconButton(
              tooltip: 'Delete server',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _confirmDeleteServer(s),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 8),
              child: Icon(Icons.lock_outline, color: Colors.grey, size: 18),
            ),
        ],
      ),
      onTap: () => provider.selectXrayServer(s),
    ),
      ),
    );
  }

  Widget _testingBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pingBadge(String label, int? ping) {
    final color = _pingColor(ping);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label ${_pingLabel(ping)}',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Kinds of flat rows in the lazy server ListView.
enum _RowKind { header, tile, more }

/// One descriptor per group. Individual server rows are resolved by index in
/// the ListView builder instead of being allocated up front.
class _GroupSpec {
  final String key;
  final String title;
  final List<XrayServer> servers;
  final bool locked;

  const _GroupSpec(this.key, this.title, this.servers, this.locked);
}

/// A single lightweight row descriptor used by the lazy [ListView.builder] in
/// [_XrayServersScreenState.build]. Building rows lazily (only what's on
/// screen) is what keeps a list of hundreds/thousands of servers smooth.
class _Row {
  final _RowKind kind;
  final String? groupKey;
  final String? title;
  final List<XrayServer>? servers;
  final XrayServer? server;
  final bool locked;
  final bool expanded;
  final Color? groupAccent;
  final bool groupLast;
  final int moreCount;

  _Row._({
    required this.kind,
    this.groupKey,
    this.title,
    this.servers,
    this.server,
    this.locked = false,
    this.expanded = false,
    this.groupAccent,
    this.groupLast = false,
    this.moreCount = 0,
  });

  factory _Row.header(String groupKey, String title,
          List<XrayServer> servers, bool locked, bool expanded) =>
      _Row._(
        kind: _RowKind.header,
        groupKey: groupKey,
        title: title,
        servers: servers,
        locked: locked,
        expanded: expanded,
      );

  factory _Row.tile(
    XrayServer server,
    bool locked, {
    String? groupKey,
    Color? groupAccent,
    bool groupLast = false,
  }) =>
      _Row._(
        kind: _RowKind.tile,
        server: server,
        locked: locked,
        groupKey: groupKey,
        groupAccent: groupAccent,
        groupLast: groupLast,
      );

  factory _Row.more(int count) =>
      _Row._(kind: _RowKind.more, moreCount: count);
}
