import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/four_win_loader.dart';

/// Split Tunneling: choose which apps go through the VPN (include mode) or which
/// apps bypass it (exclude mode). The selection + mode are persisted via
/// shared_preferences and applied natively in the VpnService builders
/// (see SplitTunnel.kt). NOTE: split tunneling applies to the VPN-mode
/// (system-tunnel) protocols; it has no effect in connection-mode "proxy".
class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  static const _channel = MethodChannel('com.forwin.vpn/apps');
  static const _modeKey = 'split_tunnel_mode'; // off | include | exclude
  static const _appsKey = 'split_tunnel_apps'; // comma-separated packages

  String _mode = 'off';
  final Set<String> _selected = {};
  List<Map<String, String>> _apps = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString(_modeKey) ?? 'off';
    final raw = prefs.getString(_appsKey) ?? '';
    _selected
      ..clear()
      ..addAll(raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    try {
      final res = await _channel.invokeMethod('getInstalledApps');
      final list = (res as List)
          .map((e) => (e as Map).map((k, v) => MapEntry('$k', '$v')))
          .toList();
      list.sort((a, b) =>
          (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));
      _apps = list;
    } catch (_) {
      _apps = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, _mode);
    // Persist a plain comma-separated string (read directly by SplitTunnel.kt).
    await prefs.setString(_appsKey, _selected.join(','));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Colors.tealAccent.shade700;
    final filtered = _apps.where((a) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return (a['name'] ?? '').toLowerCase().contains(q) ||
          (a['package'] ?? '').toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Split Tunneling')),
      body: _loading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FourWinLoader(
                      size: 52,
                      semanticsLabel: 'Loading installed apps',
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Loading installed apps…',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Please wait while the app list is prepared.',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose how per-app tunneling works:',
                        style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'off', label: Text('Off')),
                          ButtonSegment(
                              value: 'include', label: Text('Only selected')),
                          ButtonSegment(
                              value: 'exclude', label: Text('Bypass selected')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) async {
                          setState(() => _mode = s.first);
                          await _save();
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _mode == 'include'
                            ? 'Only the checked apps will use the VPN.'
                            : _mode == 'exclude'
                                ? 'The checked apps will bypass the VPN.'
                                : 'All apps use the VPN (no per-app filtering).',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search apps',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _apps.isEmpty
                      ? Center(
                          child: Text('No apps found',
                              style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45)),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final a = filtered[i];
                            final pkg = a['package'] ?? '';
                            final checked = _selected.contains(pkg);
                            return CheckboxListTile(
                              value: checked,
                              activeColor: accent,
                              dense: true,
                              enabled: _mode != 'off',
                              title: Text(a['name'] ?? pkg,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(pkg,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11)),
                              onChanged: (v) async {
                                setState(() {
                                  if (v == true) {
                                    _selected.add(pkg);
                                  } else {
                                    _selected.remove(pkg);
                                  }
                                });
                                await _save();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
