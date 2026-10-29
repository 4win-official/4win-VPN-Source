import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
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
    ).showSnackBar(SnackBar(content: LocalizedText(message)));
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
    final isSingleServer = _isSingleServerEntry(group);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: LocalizedText(isSingleServer ? 'Delete server?' : 'Delete group?'),
        content: LocalizedText(
          isSingleServer
              ? 'Delete "${group.servers.single.fullAddress}"?'
              : 'Delete "${group.name}" and its servers?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const LocalizedText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const LocalizedText('Delete'),
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

  Future<void> _addServer() async {
    if (_busy) return;
    final result = await showDialog<(String, int, String, String)?>(
      context: context,
      builder: (_) => const _SstpServerDialog(),
    );
    if (!mounted || result == null) return;
    await _run(
      () => context.read<VpnProvider>().addSstpServer(
        result.$1,
        result.$2,
        username: result.$3,
        password: result.$4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = dark ? const Color(0xFF00FF88) : Colors.blue;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('SSTP Servers'),
        actions: [
          Consumer<VpnProvider>(
            builder: (_, p, __) => IconButton(
              tooltip: context.l10n.text('Refresh default servers'),
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
          Consumer<VpnProvider>(
            builder: (_, p, __) => PopupMenuButton<String>(
              tooltip: context.l10n.text('Add SSTP entry'),
              enabled:
                  !p.sstpGroupTesting &&
                  !p.sstpRefreshing &&
                  !p.isConnected &&
                  !p.isConnecting,
              onSelected: (value) {
                if (value == 'server') {
                  _addServer();
                } else {
                  _addGroup();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'server', child: LocalizedText('Add server')),
                PopupMenuItem(value: 'group', child: LocalizedText('Add group')),
              ],
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
                          LocalizedText(
                            'Testing $progress…',
                            style: TextStyle(fontSize: 11, color: accent),
                          ),
                        ],
                      )
                    else
                      LocalizedText(
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
                tooltip: context.l10n.text(testing ? 'Stop test' : 'Test group latency'),
                onPressed: testing
                    ? p.cancelSstpTest
                    : busy
                        ? null
                        : () => _run(() => p.testSstpGroup(g.id)),
                icon: testing
                    ? const Icon(Icons.close, color: Colors.redAccent, size: 20)
                    : const Icon(Icons.speed, size: 21),
              ),
              if (g.isDefault || g.subscriptionUrl != null)
                IconButton(
                  tooltip: context.l10n.text('Refresh group'),
                  onPressed: busy
                      ? null
                      : () => _run(() => p.refreshSstpGroup(g.id)),
                  icon: const Icon(Icons.refresh, size: 21),
                ),
              if (!g.isDefault)
                IconButton(
                  tooltip: context.l10n.text(_isSingleServerEntry(g)
                      ? 'Delete server'
                      : 'Delete group'),
                  onPressed: busy ? null : () => _confirmDelete(g),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                ),
              IconButton(
                tooltip: context.l10n.text(open ? 'Collapse' : 'Expand'),
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
      subtitle: LocalizedText(
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
            tooltip: context.l10n.text('Test TCP latency'),
            onPressed: testing
                ? p.cancelSstpTest
                : p.sstpGroupTesting ||
                      p.sstpRefreshing ||
                      p.isConnected ||
                      p.isConnecting
                    ? null
                    : () => _run(() => p.testSstpServer(group.id, s)),
            icon: testing
                ? const Icon(Icons.close, color: Colors.redAccent, size: 20)
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

  bool _isSingleServerEntry(SstpServerGroup group) =>
      !group.isDefault &&
      group.subscriptionUrl == null &&
      group.servers.length == 1 &&
      group.name == group.servers.single.fullAddress;

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
        LocalizedText(
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
          child: LocalizedText(
            'Add a server or group, or refresh the default group to load servers.',
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
    title: const LocalizedText('Add SSTP group'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: context.l10n.text('Group name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: content,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: context.l10n.text('Host:port lines or subscription URL'),
              hintText: context.l10n.text('vpn.example.com:443\nhttps://example.com/servers.txt'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: username,
            decoration: InputDecoration(labelText: context.l10n.text('Username')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(labelText: context.l10n.text('Password')),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const LocalizedText('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          name.text.trim(),
          content.text.trim(),
          username.text,
          password.text,
        )),
        child: const LocalizedText('Add'),
      ),
    ],
  );
}

class _SstpServerDialog extends StatefulWidget {
  const _SstpServerDialog();

  @override
  State<_SstpServerDialog> createState() => _SstpServerDialogState();
}

class _SstpServerDialogState extends State<_SstpServerDialog> {
  final formKey = GlobalKey<FormState>();
  final host = TextEditingController();
  final port = TextEditingController(text: '443');
  final username = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    host.dispose();
    port.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const LocalizedText('Add SSTP server'),
    content: SingleChildScrollView(
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: host,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: context.l10n.text('Host')),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Enter a host.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: context.l10n.text('Port')),
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                return parsed != null && parsed >= 1 && parsed <= 65535
                    ? null
                    : 'Enter a port from 1 to 65535.';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: username,
              decoration: InputDecoration(labelText: context.l10n.text('Username')),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Enter a username.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: context.l10n.text('Password')),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Enter a password.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const LocalizedText('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(context, (
            host.text.trim(),
            int.parse(port.text.trim()),
            username.text.trim(),
            password.text,
          ));
        },
        child: const LocalizedText('Add server'),
      ),
    ],
  );
}
