import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/four_win_loader.dart';

/// Split Tunneling: choose which apps go through the VPN or bypass it.
/// The selection and mode are persisted via shared_preferences and applied
/// natively by the standalone Android VpnService builders (see SplitTunnel.kt).
/// Split tunneling applies to VPN-mode protocols, not connection-mode proxies.
class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  static const _channel = MethodChannel('com.forwin.vpn/apps');
  static const _modeKey = 'split_tunnel_mode'; // include | exclude
  static const _appsKey = 'split_tunnel_apps'; // comma-separated packages
  static const _optOutKey = 'split_tunnel_banking_opt_outs';
  static const _modeMigratedKey = 'split_tunnel_mode_migrated_v1';

  // Authoritative default-bypass package list; keep in sync with SplitTunnel.kt
  // and the explicit AndroidManifest.xml package visibility declarations.
  static const Set<String> _defaultBypassPackages = {
    'com.isc.bminew',
    'com.isc.bsinew',
    'mob.banking.android.pasargad',
    'com.adpdigital.mbs.ayande',
    'com.pmb.mobile',
    'com.bmelat.mobile',
    'com.bpm.sekeh',
    'com.refahbank.dpi.android',
    'com.refah.superapp',
    'com.parsmobapp',
    'com.ada.mbank.mehr',
    'com.rahand.qkids',
    'com.rahand.qbank',
    'com.tosan.dara.sina',
    'com.tosan.dara.sepah',
    'ir.stts.bjt',
    'com.maskanmobilebank',
    'com.bki.mobilebanking.android',
    'com.citydi.hplus',
    'ir.mobillet.app',
    'mob.banking.android.resalat',
    'ir.stsepehr.hamrahcard',
    'com.farazpardazan.enbank',
    'ir.tes.sarmayeh',
    'co.nilin.faraznative',
    'com.tosan.dara.day',
    'digital.neobank',
    'ir.omidbank',
    'com.gostaresh.mobilebank.boilerplate',
    'com.samanpr.blu',
    'co.redbank.app',
    'app.rbmain.a',
    'ir.sep.sesoot',
    'mobi.mmdt.ott',
    'mobi.mmdt.ottplus',
    'ir.eitaa.messenger',
    'ir.resaneh1.iptv',
    'com.app.shadplus',
    'com.bestapps.shadimadareswebbrowser',
  };

  String _mode = 'exclude';
  final Set<String> _selected = {};
  final Set<String> _optedOut = {};
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
    final savedMode = prefs.getString(_modeKey);
    final modeMigrated = prefs.getBool(_modeMigratedKey) ?? false;

    // Old "off" and "include" settings could tunnel the default checked apps.
    // Migrate existing installs once to the safer bypass-selected default;
    // after migration, an explicit user choice of Only selected is retained.
    _mode = modeMigrated && savedMode == 'include' ? 'include' : 'exclude';

    final raw = prefs.getString(_appsKey) ?? '';
    _selected
      ..clear()
      ..addAll(raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty));
    _optedOut
      ..clear()
      ..addAll((prefs.getString(_optOutKey) ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && _defaultBypassPackages.contains(e)));

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

    // Add newly installed default-bypass packages without replacing any saved
    // non-bank selections. A separate opt-out list lets the owner uncheck them
    // without the native defaulting logic adding them back.
    for (final app in _apps) {
      final package = app['package'] ?? '';
      if (_defaultBypassPackages.contains(package) &&
          !_optedOut.contains(package)) {
        _selected.add(package);
      }
    }
    _selected.removeAll(_optedOut);

    await prefs.setString(_optOutKey, (_optedOut.toList()..sort()).join(','));
    await prefs.setString(_modeKey, _mode);
    await prefs.setBool(_modeMigratedKey, true);
    await prefs.setString(_appsKey, _selected.join(','));

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // Persist plain comma-separated strings read by the native VPN services.
    await prefs.setString(_optOutKey, (_optedOut.toList()..sort()).join(','));
    await prefs.setString(_modeKey, _mode);
    await prefs.setBool(_modeMigratedKey, true);
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
      appBar: AppBar(title: const LocalizedText('Split Tunneling')),
      body: _loading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FourWinLoader(
                      size: 52,
                      semanticsLabel: context.l10n.text('Loading installed apps'),
                    ),
                    const SizedBox(height: 20),
                    LocalizedText(
                      'Loading installed apps…',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    LocalizedText(
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
                      LocalizedText(
                        'Choose how per-app tunneling works:',
                        style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'include',
                            label: LocalizedText('Only selected'),
                          ),
                          ButtonSegment(
                            value: 'exclude',
                            label: LocalizedText('Bypass selected'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) async {
                          setState(() => _mode = s.first);
                          await _save();
                        },
                      ),
                      const SizedBox(height: 8),
                      LocalizedText(
                        _mode == 'include'
                            ? 'Only the checked apps will use the VPN.'
                            : 'The checked apps will bypass the VPN.',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: context.l10n.text('Search apps'),
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
                          child: LocalizedText(
                            'No apps found',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
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
                                    _optedOut.remove(pkg);
                                  } else {
                                    _selected.remove(pkg);
                                    if (_defaultBypassPackages.contains(pkg)) {
                                      _optedOut.add(pkg);
                                    }
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
