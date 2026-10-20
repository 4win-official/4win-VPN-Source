import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sstp_server_group.dart';
import '../models/vpn_server.dart';
import '../models/mix_strategy.dart';
import '../providers/vpn_provider.dart';
import '../widgets/animated_server_group.dart';
import '../widgets/four_win_loader.dart';

/// Grouped SSTP server picker. Group selection is deliberately separate from
/// the arrow: tapping a header starts the provider's fastest-server test.
class SstpServersScreen extends StatefulWidget {
  const SstpServersScreen({super.key, this.initialSelection, this.onSelected});

  final MixHop? initialSelection;
  final ValueChanged<MixHop>? onSelected;

  @override
  State<SstpServersScreen> createState() => _SstpServersScreenState();
}

class _SstpServersScreenState extends State<SstpServersScreen> {
  final Set<String> _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<VpnProvider>();
      // Do not replace an in-progress global test with an eager screen refresh.
      if (!p.sstpGroupTesting && !p.sstpRefreshing) {
        p.loadServers();
      }
    });
  }

  bool get _busy {
    final p = context.read<VpnProvider>();
    return p.sstpGroupTesting || p.sstpRefreshing;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _toast('Could not update SSTP servers. Please try again.');
    }
  }

  Future<void> _selectGroup(SstpServerGroup group) async {
    if (widget.onSelected != null) {
      widget.onSelected!(MixHop(protocol: 'sstp', group: group.id));
      return;
    }
    final p = context.read<VpnProvider>();
    if (p.isConnected || p.isConnecting) {
      _toast('Disconnect first to change the SSTP server.');
      return;
    }
    if (_busy) return;
    await _run(() => p.selectSstpGroup(group.id));
  }

  Future<void> _selectServer(VpnServer server) async {
    if (widget.onSelected != null) {
      final owner = context.read<VpnProvider>().sstpGroups.firstWhere(
        (g) => g.servers.contains(server),
      );
      widget.onSelected!(
        MixHop(protocol: 'sstp', serverId: server.fullAddress, group: owner.id),
      );
      return;
    }
    final p = context.read<VpnProvider>();
    if (p.isConnected || p.isConnecting) {
      _toast('Disconnect first to change the SSTP server.');
      return;
    }
    if (_busy) return;
    try {
      p.selectServer(server);
    } catch (_) {
      _toast('Could not select this server.');
    }
  }

  Future<void> _confirmDelete(SstpServerGroup group) async {
    if (group.isDefault || _busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Delete "${group.name}" and its servers?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await _run(() => context.read<VpnProvider>().removeSstpGroup(group.id));
    }
  }

  Future<void> _addGroup() async {
    if (_busy) return;
    final result = await showDialog<(String, String, String, String)?>(
      context: context,
      builder: (_) => const _SstpGroupDialog(),
    );
    if (!mounted) return;
    if (result == null || result.$1.isEmpty || result.$2.isEmpty) {
      if (result != null) {
        _toast('Enter a group name and server source.');
      }
      return;
    }
    await _run(
      () => context.read<VpnProvider>().addSstpGroup(
        result.$1,
        result.$2,
        username: result.$3.trim().isEmpty ? 'vpn' : result.$3.trim(),
        password: result.$4.isEmpty ? 'vpn' : result.$4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF00FF88) : Colors.blue;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSTP Servers'),
        actions: [
          Consumer<VpnProvider>(
            builder: (_, p, __) => IconButton(
              tooltip: 'Refresh default servers',
              onPressed:
                  p.sstpGroupTesting ||
                      p.sstpRefreshing ||
                      p.isConnected ||
                      p.isConnecting
                  ? null
                  : () => _run(() => p.loadServers(forceRefresh: true)),
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: Consumer<VpnProvider>(
        builder: (context, p, _) {
          final groups = p.sstpGroups;
          if (groups.isEmpty) return _empty(dark, accent);
          return RefreshIndicator(
            onRefresh: () => _run(() => p.loadServers(forceRefresh: true)),
            child: CustomScrollView(
              slivers: [
                if (p.sstpTestError != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Text(
                        p.sstpTestError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverMainAxisGroup(
                    slivers: groups
                        .map((g) => _group(p, g, dark, accent))
                        .toList(),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Consumer<VpnProvider>(
        builder: (_, p, __) => FloatingActionButton.extended(
          onPressed:
              p.sstpGroupTesting ||
                  p.sstpRefreshing ||
                  p.isConnected ||
                  p.isConnecting
              ? null
              : _addGroup,
          icon: const Icon(Icons.add),
          label: const Text('Add group'),
        ),
      ),
    );
  }

  Widget _group(VpnProvider p, SstpServerGroup g, bool dark, Color accent) {
    final open = _expanded.contains(g.id);
    final selected = widget.onSelected != null
        ? _isInitialGroup(g)
        : p.selectedSstpGroup == g.id ||
              g.servers.any((s) => _same(s, p.selectedServer));
    final busy =
        p.sstpGroupTesting ||
        p.sstpRefreshing ||
        p.isConnected ||
        p.isConnecting;
    final testing = g.servers.any(p.isSstpServerTesting);
    final progress = testing ? '${p.sstpTestedCount}/${p.sstpTestTotal}' : null;
    return AnimatedServerGroup(
      key: ValueKey('sstp-group-${g.id}'),
      expanded: open,
      backgroundColor: dark
          ? Colors.white.withValues(alpha: .04)
          : Colors.black.withValues(alpha: .03),
      collapsedBorderColor: selected ? accent : Colors.transparent,
      expandedBorderColor: accent.withValues(alpha: selected ? .95 : .45),
      header: InkWell(
        onTap: () => _selectGroup(g),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                g.isDefault ? Icons.lock_outline : Icons.cloud_outlined,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${g.name} (${g.servers.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (testing)
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: FourWinLoader(
                              strokeWidth: 1.8,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Testing $progress…',
                            style: TextStyle(fontSize: 11, color: accent),
                          ),
                        ],
                      )
                    else
                      Text(
                        selected
                            ? p.selectedSstpGroup == null
                                  ? 'Manual server selected'
                                  : p.selectedServer == null
                                  ? 'Selected — tap to test servers'
                                  : 'Selected — fastest server chosen'
                            : 'Tap to test and select fastest',
                        style: TextStyle(
                          fontSize: 11,
                          color: selected
                              ? accent
                              : (dark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: accent, size: 21),
              IconButton(
                tooltip: 'Test group latency',
                onPressed: busy
                    ? null
                    : () => _run(() => p.testSstpGroup(g.id)),
                icon: testing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: FourWinLoader(strokeWidth: 1.8, color: accent),
                      )
                    : const Icon(Icons.speed, size: 21),
              ),
              if (g.isDefault || g.subscriptionUrl != null)
                IconButton(
                  tooltip: 'Refresh group',
                  onPressed: busy
                      ? null
                      : () => _run(() => p.refreshSstpGroup(g.id)),
                  icon: const Icon(Icons.refresh, size: 21),
                ),
              if (!g.isDefault)
                IconButton(
                  tooltip: 'Delete group',
                  onPressed: busy ? null : () => _confirmDelete(g),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                ),
              IconButton(
                tooltip: open ? 'Collapse' : 'Expand',
                onPressed: () => setState(
                  () => open ? _expanded.remove(g.id) : _expanded.add(g.id),
                ),
                icon: Icon(
                  open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                ),
              ),
            ],
          ),
        ),
      ),
      itemCount: g.servers.length,
      itemBuilder: (_, i) => _serverTile(p, g, g.servers[i], accent, dark),
    );
  }

  Widget _serverTile(
    VpnProvider p,
    SstpServerGroup group,
    VpnServer s,
    Color accent,
    bool dark,
  ) {
    final selected = widget.onSelected != null
        ? _isInitialServer(group, s)
        : _same(s, p.selectedServer);
    final ping = s.ping;
    final testing = p.isSstpServerTesting(s);
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: accent.withValues(alpha: .15),
        child: Icon(Icons.dns, color: accent, size: 18),
      ),
      title: Text(
        s.fullAddress,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        testing
            ? 'Testing…'
            : ping == null
            ? 'Untested'
            : ping < 0
            ? 'Unreachable'
            : '$ping ms TCP connect',
        style: TextStyle(
          color: testing || (ping != null && ping >= 0) ? accent : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Test TCP latency',
            onPressed:
                testing ||
                    p.sstpGroupTesting ||
                    p.sstpRefreshing ||
                    p.isConnected ||
                    p.isConnecting
                ? null
                : () => _run(() => p.testSstpServer(group.id, s)),
            icon: testing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: FourWinLoader(strokeWidth: 1.8, color: accent),
                  )
                : const Icon(Icons.speed, size: 20),
          ),
          if (selected) Icon(Icons.check_circle, color: accent),
        ],
      ),
      onTap: () => _selectServer(s),
    );
  }

  bool _isInitialGroup(SstpServerGroup group) =>
      widget.initialSelection?.protocol == 'sstp' &&
      (widget.initialSelection?.group == group.id ||
          (widget.initialSelection?.group == null &&
              group.servers.any((s) => _isInitialServer(group, s))));

  bool _isInitialServer(SstpServerGroup group, VpnServer server) =>
      widget.initialSelection?.protocol == 'sstp' &&
      (widget.initialSelection?.group == null ||
          widget.initialSelection?.group == group.id) &&
      widget.initialSelection?.serverId == server.fullAddress;

  bool _same(VpnServer a, VpnServer? b) => identical(a, b);

  Widget _empty(bool dark, Color accent) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.vpn_key_outlined,
          size: 64,
          color: accent.withValues(alpha: .6),
        ),
        const SizedBox(height: 16),
        Text(
          'No SSTP servers yet',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: dark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Add a group or refresh the default group to load servers.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

/// Controllers belong to the dialog route and are disposed after its exit
/// animation, rather than as soon as showDialog's result completes.
class _SstpGroupDialog extends StatefulWidget {
  const _SstpGroupDialog();

  @override
  State<_SstpGroupDialog> createState() => _SstpGroupDialogState();
}

class _SstpGroupDialogState extends State<_SstpGroupDialog> {
  final name = TextEditingController();
  final content = TextEditingController();
  final username = TextEditingController(text: 'vpn');
  final password = TextEditingController(text: 'vpn');

  @override
  void dispose() {
    name.dispose();
    content.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add SSTP group'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: content,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Host:port lines or subscription URL',
              hintText: 'vpn.example.com:443\nhttps://example.com/servers.txt',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: username,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          name.text.trim(),
          content.text.trim(),
          username.text,
          password.text,
        )),
        child: const Text('Add'),
      ),
    ],
  );
}
