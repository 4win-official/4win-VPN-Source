import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dns_server.dart';
import '../models/mix_strategy.dart';
import '../models/proxy_server.dart';
import '../models/xray_server.dart';
import '../models/openvpn_config.dart';
import '../models/vpn_server.dart';
import '../providers/vpn_provider.dart';

class MixStrategyEditorScreen extends StatefulWidget {
  const MixStrategyEditorScreen({super.key, this.existingStrategy});
  final MixStrategy? existingStrategy;
  @override
  State<MixStrategyEditorScreen> createState() =>
      _MixStrategyEditorScreenState();
}

class _MixStrategyEditorScreenState extends State<MixStrategyEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _relayHost;
  late final TextEditingController _relayPort;
  late final TextEditingController _relayServerName;
  late final TextEditingController _relayToken;
  late List<MixHop> _hops;
  late final String _id;
  bool _saving = false;
  late bool _relayEnabled;
  String? _error;
  Future<List<DnsServer>>? _dnsFuture;

  @override
  void initState() {
    super.initState();
    final old = widget.existingStrategy;
    _id = old?.id ?? 'mix_${DateTime.now().microsecondsSinceEpoch}';
    _name = TextEditingController(text: old?.name ?? '');
    final relay = old?.udpRelay;
    _relayEnabled = relay != null;
    _relayHost = TextEditingController(text: relay?.host ?? '');
    _relayPort = TextEditingController(text: relay?.port.toString() ?? '');
    _relayServerName = TextEditingController(text: relay?.serverName ?? '');
    _relayToken = TextEditingController(text: relay?.token ?? '');
    _hops = List<MixHop>.from(old?.hops ?? const <MixHop>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    _relayHost.dispose();
    _relayPort.dispose();
    _relayServerName.dispose();
    _relayToken.dispose();
    super.dispose();
  }

  MixStrategy get _strategy => MixStrategy(
    id: _id,
    name: _name.text,
    hops: _hops,
    udpRelay: _relayEnabled
        ? MixUdpRelay(
            host: _relayHost.text,
            port: int.tryParse(_relayPort.text) ?? 0,
            token: _relayToken.text,
            serverName: _relayServerName.text.isEmpty
                ? _relayHost.text
                : _relayServerName.text,
          )
        : null,
  );

  void _append(String protocol) {
    if (_hops.length >= MixStrategy.maxBlocks) {
      setState(
        () => _error = 'At most ${MixStrategy.maxBlocks} blocks are supported.',
      );
      return;
    }
    setState(() => _hops.add(MixHop(protocol: protocol)));
    _chooseReference(_hops.length - 1);
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final strategy = _strategy;
    final error = strategy.validationError;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<VpnProvider>().saveMixStrategy(strategy);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save strategy: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseReference(int index) async {
    if (index < 0 || index >= _hops.length) return;
    final hop = _hops[index];
    if (hop.protocol == 'direct_dns') {
      _dnsFuture ??= context.read<VpnProvider>().getAllDnsServers();
      final dns = await _dnsFuture!;
      if (!mounted) return;
      final selected = await showModalBottomSheet<MixHop>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ReferenceSheet(
          title: 'Choose DNS',
          children: dns
              .map(
                (d) => ListTile(
                  leading: const Icon(Icons.dns),
                  title: Text(d.name),
                  subtitle: Text(d.primaryDns),
                  onTap: () => Navigator.pop(
                    context,
                    MixHop(protocol: 'direct_dns', serverId: d.primaryDns),
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (selected != null && mounted) setState(() => _hops[index] = selected);
      return;
    }
    final provider = context.read<VpnProvider>();
    if (hop.protocol == 'xray') {
      final groups =
          provider.xrayServers
              .map((s) => s.group)
              .where((g) => g.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final selected = await _serverSheet<XrayServer>(
        title: 'Choose Xray server or group',
        groups: groups,
        servers: provider.xrayServers,
        label: (s) => s.remark,
        onServer: (s) => MixHop(protocol: 'xray', serverId: s.id),
        onGroup: (g) => MixHop(protocol: 'xray', group: g),
      );
      if (selected != null && mounted) setState(() => _hops[index] = selected);
    } else if (hop.protocol == 'proxy') {
      final groups =
          provider.proxyServers
              .map((s) => s.group)
              .where((g) => g.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final selected = await _serverSheet<ProxyServer>(
        title: 'Choose Proxy server or group',
        groups: groups,
        servers: provider.proxyServers,
        label: (s) => s.remark,
        onServer: (s) => MixHop(protocol: 'proxy', serverId: s.id),
        onGroup: (g) => MixHop(protocol: 'proxy', group: g),
      );
      if (selected != null && mounted) setState(() => _hops[index] = selected);
    } else if (hop.protocol == 'sstp') {
      final selected = await _serverSheet<VpnServer>(
        title: 'Choose SSTP server',
        groups: const [],
        servers: provider.servers,
        label: (s) => s.fullAddress,
        onServer: (s) => MixHop(protocol: 'sstp', serverId: s.fullAddress),
        onGroup: (_) => throw StateError('SSTP has no groups'),
      );
      if (selected != null && mounted) setState(() => _hops[index] = selected);
    } else if (hop.protocol == 'openvpn') {
      final selected = await _configSheet<OpenVpnConfig>(
        title: 'Choose OpenVPN config',
        values: provider.openVpnConfigs,
        label: (c) => c.name,
        value: (c) => MixHop(protocol: 'openvpn', serverId: c.name),
      );
      if (selected != null && mounted) setState(() => _hops[index] = selected);
    } else if (hop.protocol == 'warp' || hop.protocol == 'psiphon') {
      final selected = await showModalBottomSheet<MixHop>(
        context: context,
        builder: (_) => _ReferenceSheet(
          title: hop.protocol == 'warp'
              ? 'Choose WARP account'
              : 'Choose Psiphon profile',
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(
                hop.protocol == 'warp'
                    ? (provider.warpAccount == null
                          ? 'No registered WARP account'
                          : 'Current WARP account')
                    : 'Current Psiphon profile',
              ),
              enabled: hop.protocol != 'warp' || provider.warpAccount != null,
              onTap: () => Navigator.pop(
                context,
                MixHop(protocol: hop.protocol, serverId: 'default'),
              ),
            ),
          ],
        ),
      );
      if (selected != null && mounted) setState(() => _hops[index] = selected);
    }
  }

  Future<MixHop?> _configSheet<T>({
    required String title,
    required List<T> values,
    required String Function(T) label,
    required MixHop Function(T) value,
  }) => showModalBottomSheet<MixHop>(
    context: context,
    builder: (_) => _ReferenceSheet(
      title: title,
      children: values
          .map(
            (v) => ListTile(
              title: Text(label(v)),
              onTap: () => Navigator.pop(context, value(v)),
            ),
          )
          .toList(),
    ),
  );

  Future<MixHop?> _serverSheet<T>({
    required String title,
    required List<String> groups,
    required List<T> servers,
    required String Function(T) label,
    required MixHop Function(T) onServer,
    required MixHop Function(String) onGroup,
  }) {
    return showModalBottomSheet<MixHop>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReferenceSheet(
        title: title,
        children: [
          if (groups.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'GROUPS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            ...groups.map(
              (g) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(g),
                onTap: () => Navigator.pop(context, onGroup(g)),
              ),
            ),
            const Divider(),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SERVERS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          ...servers.map(
            (s) => ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(label(s)),
              onTap: () => Navigator.pop(context, onServer(s)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? Colors.black : const Color(0xfff4f5f8),
      appBar: AppBar(
        title: Text(
          widget.existingStrategy == null
              ? 'New Mix Strategy'
              : 'Edit Mix Strategy',
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Strategy name',
                      hintText: 'e.g. Gaming route',
                      prefixIcon: Icon(Icons.edit_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ExpansionTile(
                      initiallyExpanded: _relayEnabled,
                      leading: const Icon(Icons.security_outlined),
                      title: const Text('Optional UDP-over-TLS relay'),
                      subtitle: const Text('For UDP behind Psiphon or HTTP'),
                      children: [
                        SwitchListTile(
                          title: const Text('Enable UDP relay'),
                          value: _relayEnabled,
                          onChanged: (enabled) =>
                              setState(() => _relayEnabled = enabled),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Requires your own running relay server with a trusted TLS certificate. UDP crosses the selected tunnel to this additional server; if the final block is Psiphon or HTTP, UDP exits from the relay, while TCP still exits from that block. Standalone protocols are unchanged.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        TextField(
                          controller: _relayHost,
                          decoration: const InputDecoration(
                            labelText: 'Relay host (IP or hostname)',
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        TextField(
                          controller: _relayPort,
                          decoration: const InputDecoration(
                            labelText: 'Relay port',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        TextField(
                          controller: _relayServerName,
                          decoration: const InputDecoration(
                            labelText: 'TLS server name (defaults to host)',
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        TextField(
                          controller: _relayToken,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Auth token',
                            helperText: '32–256 printable ASCII characters',
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() {
                              _relayEnabled = false;
                              _relayHost.clear();
                              _relayPort.clear();
                              _relayServerName.clear();
                              _relayToken.clear();
                            }),
                            child: const Text('Disable relay'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GridCanvas(
                    hops: _hops,
                    onAppend: _append,
                    onTap: _chooseReference,
                    onRemove: (i) => setState(() => _hops.removeAt(i)),
                    onReorder: (old, next) => setState(() {
                      if (next > old) next--;
                      final item = _hops.removeAt(old);
                      _hops.insert(next, item);
                    }),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'ADD PROTOCOL BLOCK  (${_hops.length}/${MixStrategy.maxBlocks})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MixStrategy.protocols.entries.map((entry) {
                      final locked = _hops.length >= MixStrategy.maxBlocks;
                      return Draggable<String>(
                        data: entry.key,
                        feedback: Material(
                          color: Colors.transparent,
                          child: _PaletteChip(
                            label: entry.value,
                            locked: locked,
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: .35,
                          child: _PaletteChip(
                            label: entry.value,
                            locked: locked,
                          ),
                        ),
                        child: _PaletteChip(
                          label: entry.value,
                          locked: locked,
                          onTap: () => _append(entry.key),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tap or drag a chip to append; hold a block to reorder. DNS is a resolver at the selected position, not a tunnel: DNS first resolves on the physical link; multiple DNS blocks are allowed, and the last DNS is effective for app queries. DNS does not have to be last; tunnel order and scoped prefixes stay intact.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridCanvas extends StatelessWidget {
  const _GridCanvas({
    required this.hops,
    required this.onAppend,
    required this.onTap,
    required this.onRemove,
    required this.onReorder,
  });
  final List<MixHop> hops;
  final ValueChanged<String> onAppend;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onRemove;
  final void Function(int, int) onReorder;
  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (_) => hops.length < MixStrategy.maxBlocks,
    onAcceptWithDetails: (d) {
      if (hops.length < MixStrategy.maxBlocks) onAppend(d.data);
    },
    builder: (context, candidates, _) => Container(
      constraints: const BoxConstraints(minHeight: 270),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff050608),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
      ),
      child: Column(
        children: [
          _GridNode(
            icon: Icons.smartphone,
            title: 'START',
            subtitle: 'This device',
            color: Colors.cyanAccent,
          ),
          const _GridLine(),
          if (hops.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Drop or add a protocol block',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ...hops.asMap().entries.map(
            (entry) => _GridHop(
              index: entry.key,
              hop: entry.value,
              onTap: onTap,
              onRemove: onRemove,
              onReorder: onReorder,
            ),
          ),
          const _GridLine(),
          const _GridNode(
            icon: Icons.public,
            title: 'INTERNET',
            subtitle: 'Exit',
            color: Colors.greenAccent,
          ),
        ],
      ),
    ),
  );
}

class _GridHop extends StatelessWidget {
  const _GridHop({
    required this.index,
    required this.hop,
    required this.onTap,
    required this.onRemove,
    required this.onReorder,
  });
  final int index;
  final MixHop hop;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onRemove;
  final void Function(int, int) onReorder;
  @override
  Widget build(BuildContext context) {
    final title = MixStrategy.protocols[hop.protocol] ?? hop.protocol;
    final ref = hop.group != null
        ? 'Group: ${hop.group}'
        : (hop.serverId ?? 'Choose a reference');
    return Column(
      children: [
        _GridLine(),
        LongPressDraggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: _GridNode(
              icon: Icons.hub,
              title: title,
              subtitle: ref,
              color: Colors.amberAccent,
            ),
          ),
          childWhenDragging: Opacity(
            opacity: .3,
            child: _GridBlock(
              index: index,
              title: title,
              subtitle: ref,
              onTap: onTap,
              onRemove: onRemove,
            ),
          ),
          child: DragTarget<int>(
            onAcceptWithDetails: (d) => onReorder(d.data, index),
            builder: (_, __, ___) => _GridBlock(
              index: index,
              title: title,
              subtitle: ref,
              onTap: onTap,
              onRemove: onRemove,
            ),
          ),
        ),
      ],
    );
  }
}

class _GridBlock extends StatelessWidget {
  const _GridBlock({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onRemove,
  });
  final int index;
  final String title, subtitle;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onRemove;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onTap(index),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xff171b22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: .55)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hub, color: Colors.amberAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => onRemove(index),
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
          ),
        ],
      ),
    ),
  );
}

class _GridNode extends StatelessWidget {
  const _GridNode({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final IconData icon;
  final String title, subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .55)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );
}

class _GridLine extends StatelessWidget {
  const _GridLine();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: Center(child: Container(width: 2, color: Colors.white24)),
  );
}

class _PaletteChip extends StatelessWidget {
  const _PaletteChip({required this.label, this.locked = false, this.onTap});
  final String label;
  final bool locked;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(locked ? Icons.lock_outline : Icons.add, size: 16),
    label: Text(label),
    onPressed: locked
        ? () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 50 blocks reached.')),
          )
        : onTap,
  );
}

class _ReferenceSheet extends StatelessWidget {
  const _ReferenceSheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: .65,
      maxChildSize: .92,
      builder: (_, controller) => Material(
        child: ListView(
          controller: controller,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    ),
  );
}
