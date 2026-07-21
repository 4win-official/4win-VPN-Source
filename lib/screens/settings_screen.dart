import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../models/dns_server.dart';
import 'slowdns_configs_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _dnsController = TextEditingController();
  final _customServerController = TextEditingController();
  final _customUsernameController = TextEditingController();
  final _customPasswordController = TextEditingController();
  int _concurrentTests = 100;
  bool _parallelConnection = false; // سوییچ اتصال موازی
  bool _killSwitch = false; // Kill Switch
  bool _useCustomServer = false; // سوییچ استفاده از سرور اختصاصی
  bool _deepScan = false; // اسکن عمیق (برای اینترنت ضعیف/محدودیت دولتی)
  String _mtuMode = 'off'; // حالت MTU: off | auto | manual
  final _mtuController = TextEditingController(text: '1400'); // مقدار دستی MTU

  // SSTP fragment (TLS ClientHello fragmentation toggle for SSTP)
  bool _sstpFragment = false;
  final _sstpFragSizeController = TextEditingController(text: '1-3');
  final _sstpFragIntervalController = TextEditingController(text: '10-20');

  // Xray fragment (moved here from the server list)
  bool _xrayFragment = false;
  final _xrayFragPacketsController = TextEditingController(text: 'tlshello');
  final _xrayFragLengthController = TextEditingController(text: '10-20');
  final _xrayFragIntervalController = TextEditingController(text: '10-20');
  final _xrayFakeHostController = TextEditingController();
  // Xray concurrent delay-test count (how many configs tested at once).
  int _xrayConcurrentTests = 300;
  // When on, the concurrent count is chosen automatically from the device's
  // CPU cores so stronger phones test more in parallel.
  bool _xrayAutoConcurrent = true;
  // How many times each server is re-tested when connecting to a whole group
  // (best ping wins). Range 1..5.
  int _xrayGroupTestRounds = 1;
  // Delay-test URL used by both the server-list test and the home-screen
  // 3-second ping. Default: http://www.google.com/gen_204
  final _xrayTestUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _dnsController.dispose();
    _customServerController.dispose();
    _customUsernameController.dispose();
    _customPasswordController.dispose();
    _mtuController.dispose();
    _sstpFragSizeController.dispose();
    _sstpFragIntervalController.dispose();
    _xrayFragPacketsController.dispose();
    _xrayFragLengthController.dispose();
    _xrayFragIntervalController.dispose();
    _xrayFakeHostController.dispose();
    _xrayTestUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dnsController.text = prefs.getString('custom_dns') ?? '8.8.8.8';
      _customServerController.text = prefs.getString('custom_server') ?? '';
      _customUsernameController.text = prefs.getString('custom_username') ?? '';
      _customPasswordController.text = prefs.getString('custom_password') ?? '';
      _concurrentTests = prefs.getInt('concurrent_tests') ?? 100;
      _parallelConnection = prefs.getBool('parallel_connection') ?? false;
      _killSwitch = prefs.getBool('kill_switch') ?? false;
      _useCustomServer = prefs.getBool('use_custom_server') ?? false;
      _deepScan = prefs.getBool('deep_scan') ?? false;
      // مهاجرت از سوییچ قدیمی auto_mtu به حالت سه‌گانه جدید
      final legacyAuto = prefs.getBool('auto_mtu');
      _mtuMode = prefs.getString('mtu_mode') ??
          (legacyAuto == true ? 'auto' : 'off');
      _mtuController.text = (prefs.getInt('manual_mtu') ?? 1400).toString();
      // SSTP fragment
      _sstpFragment = prefs.getBool('sstp_fragment') ?? false;
      _sstpFragSizeController.text =
          prefs.getString('sstp_fragment_size') ?? '1-3';
      _sstpFragIntervalController.text =
          prefs.getString('sstp_fragment_interval') ?? '10-20';
      // Xray fragment
      _xrayFragment = prefs.getBool('xray_fragment') ?? false;
      _xrayFragPacketsController.text =
          prefs.getString('xray_fragment_packets') ?? 'tlshello';
      _xrayFragLengthController.text =
          prefs.getString('xray_fragment_length') ?? '10-20';
      _xrayFragIntervalController.text =
          prefs.getString('xray_fragment_interval') ?? '10-20';
      _xrayFakeHostController.text =
          prefs.getString('xray_fragment_host') ?? '';
      _xrayConcurrentTests =
          (prefs.getInt('xray_concurrent_tests') ?? 300).clamp(1, 300);
      _xrayAutoConcurrent = prefs.getBool('xray_auto_concurrent') ?? true;
      _xrayGroupTestRounds =
          (prefs.getInt('xray_group_test_rounds') ?? 1).clamp(1, 5);
      _xrayTestUrlController.text =
          prefs.getString('xray_test_url') ?? 'http://www.google.com/gen_204';
    });
  }

  Future<void> _saveXrayConcurrentTests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('xray_concurrent_tests', _xrayConcurrentTests);
  }

  Future<void> _saveXrayGroupTestRounds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('xray_group_test_rounds', _xrayGroupTestRounds);
  }

  Future<void> _saveXrayAutoConcurrent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('xray_auto_concurrent', _xrayAutoConcurrent);
  }

  /// Persist the typed test URL. IMPORTANT: an empty field is NOT rewritten to
  /// the default here — otherwise the user could never clear it to type a new
  /// one (every keystroke that empties it would snap it back). Empty just
  /// removes the stored value (falls back to default at read time). The default
  /// text is only re-filled explicitly via the reset button.
  Future<void> _saveXrayTestUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = _xrayTestUrlController.text.trim();
    if (v.isEmpty) {
      await prefs.remove('xray_test_url');
    } else {
      await prefs.setString('xray_test_url', v);
    }
  }

  Future<void> _saveSstpFragment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sstp_fragment', _sstpFragment);
    await prefs.setString(
        'sstp_fragment_size',
        _sstpFragSizeController.text.trim().isEmpty
            ? '1-3'
            : _sstpFragSizeController.text.trim());
    await prefs.setString(
        'sstp_fragment_interval',
        _sstpFragIntervalController.text.trim().isEmpty
            ? '10-20'
            : _sstpFragIntervalController.text.trim());
  }

  Future<void> _saveXrayFragment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('xray_fragment', _xrayFragment);
    await prefs.setString(
        'xray_fragment_packets',
        _xrayFragPacketsController.text.trim().isEmpty
            ? 'tlshello'
            : _xrayFragPacketsController.text.trim());
    await prefs.setString(
        'xray_fragment_length',
        _xrayFragLengthController.text.trim().isEmpty
            ? '10-20'
            : _xrayFragLengthController.text.trim());
    await prefs.setString(
        'xray_fragment_interval',
        _xrayFragIntervalController.text.trim().isEmpty
            ? '10-20'
            : _xrayFragIntervalController.text.trim());
    await prefs.setString(
        'xray_fragment_host', _xrayFakeHostController.text.trim());
  }

  /// Returns the current Custom DNS value if it matches one of the known DNS
  /// servers (so the dropdown can highlight it), otherwise null.
  String? _selectedSstpDnsValue() {
    final current = _dnsController.text.trim();
    if (current.isEmpty) return null;
    final match = DnsServer.getPublicDnsServers()
        .any((d) => d.primaryDns == current);
    return match ? current : null;
  }

  /// Correct display name for each protocol
  String _protocolDisplayName(String protocol) {
    switch (protocol) {
      case 'sstp':
        return 'SSTP';
      case 'direct_dns':
        return 'DNS changer';
      case 'openvpn':
        return 'OpenVPN';
      case 'slowdns':
        return 'Slow DNS';
      case 'xray':
        return 'Xray';
      default:
        return protocol;
    }
  }

  /// Subscription links card: list user-added sub URLs + add/remove.
  Widget _buildSubLinksCard(bool isDark, VpnProvider provider) {
    const accent = Color(0xFF1DE9B6);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Subscription Links',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addSubLinkDialog(provider),
                icon: const Icon(Icons.add, size: 18, color: accent),
                label: const Text('Add', style: TextStyle(color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Add subscription URLs. Their servers are merged into the free '
            'group and refreshed on every app launch.',
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<String>>(
            future: provider.getXraySubUrls(),
            builder: (context, snap) {
              final urls = snap.data ?? [];
              if (urls.isEmpty) {
                return Text(
                  'No custom links added.',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }
              return FutureBuilder<Map<String, String>>(
                future: provider.getXraySubNames(),
                builder: (context, nameSnap) {
                  final names = nameSnap.data ?? const {};
                  return Column(
                    children: urls.map((u) {
                      final custom = names[u];
                      final hasName =
                          custom != null && custom.trim().isNotEmpty;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_outlined,
                            size: 18, color: accent),
                        title: Text(
                          hasName ? custom : u,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                hasName ? FontWeight.w600 : FontWeight.normal,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: hasName
                            ? Text(u,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black45,
                                ))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename',
                              icon: const Icon(Icons.edit_outlined,
                                  color: accent, size: 20),
                              onPressed: () =>
                                  _renameSubLinkDialog(provider, u, custom),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () async {
                                await provider.removeXraySubUrl(u);
                                if (mounted) setState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addSubLinkDialog(VpnProvider provider) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Subscription / Link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'https://example.com/sub.txt\nor vless:// , vmess:// , trojan:// , ss://',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    final ok = await provider.addXraySubUrl(url.trim());
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Subscription added & refreshed' : 'Invalid or duplicate link'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  /// Rename (or clear the name of) a subscription link so the user can tell
  /// which is which in the server list.
  Future<void> _renameSubLinkDialog(
      VpnProvider provider, String url, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Germany Fast, My VPS…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    await provider.setXraySubName(url, result);
    if (mounted) setState(() {});
  }

  /// Reusable fragment configuration card (used by both SSTP and Xray).
  Widget _buildFragmentCard({
    required bool isDark,
    required Color accent,
    required bool enabled,
    required TextEditingController sizeController,
    required TextEditingController intervalController,
    required ValueChanged<bool> onToggle,
    required VoidCallback onChanged,
    required String sizeLabel,
    String description =
        'Splits the TLS ClientHello into small delayed pieces so '
        'DPI/filtering cannot read the SNI.',
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: enabled
            ? accent.withValues(alpha: 0.08)
            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? accent.withValues(alpha: 0.5) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, color: enabled ? accent : Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fragment',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: accent,
                onChanged: onToggle,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: sizeController,
                    decoration: InputDecoration(
                      labelText: sizeLabel,
                      hintText: '1-3',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: intervalController,
                    decoration: const InputDecoration(
                      labelText: 'Interval (ms)',
                      hintText: '10-20',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Dedicated Xray fragment card with the REAL Xray freedom-fragment fields:
  /// Fakehost (fake SNI), Packets (tlshello / 1-3), Length, Interval.
  Widget _buildXrayFragmentCard(bool isDark) {
    const accent = Color(0xFF1DE9B6);
    final enabled = _xrayFragment;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: enabled
            ? accent.withValues(alpha: 0.08)
            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? accent.withValues(alpha: 0.5) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, color: enabled ? accent : Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fragment',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Real Xray TLS fragmentation (freedom + fragment). '
                      'Splits the ClientHello so DPI cannot read the SNI.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeThumbColor: accent,
                onChanged: (value) {
                  setState(() => _xrayFragment = value);
                  _saveXrayFragment();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value
                          ? '✂️ Xray Fragment enabled — applied on next connect'
                          : 'Xray Fragment disabled'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            // Fakehost (fake SNI) — overrides the TLS serverName.
            TextField(
              controller: _xrayFakeHostController,
              decoration: const InputDecoration(
                labelText: 'Fakehost (fake SNI, optional)',
                hintText: 'cloudflare.com',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _saveXrayFragment(),
            ),
            const SizedBox(height: 10),
            // Packets: tlshello or a write-range like 1-3.
            TextField(
              controller: _xrayFragPacketsController,
              decoration: const InputDecoration(
                labelText: 'Packets',
                hintText: 'tlshello  (or 1-3)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _saveXrayFragment(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _xrayFragLengthController,
                    decoration: const InputDecoration(
                      labelText: 'Length (byte)',
                      hintText: '10-20',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _saveXrayFragment(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _xrayFragIntervalController,
                    decoration: const InputDecoration(
                      labelText: 'Interval (ms)',
                      hintText: '10-20',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _saveXrayFragment(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_dns', _dnsController.text);
    await prefs.setString('custom_server', _customServerController.text);
    await prefs.setString('custom_username', _customUsernameController.text);
    await prefs.setString('custom_password', _customPasswordController.text);
    await prefs.setInt('concurrent_tests', _concurrentTests);
    await prefs.setBool('parallel_connection', _parallelConnection);
    await prefs.setBool('kill_switch', _killSwitch);
    await prefs.setBool('use_custom_server', _useCustomServer);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white, // Pure black
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<VpnProvider>(
          builder: (context, provider, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // SSTP-specific settings
                if (provider.selectedProtocol == 'sstp') ...[
                  _SettingsSection(
                    title: 'SSTP Settings',
                    children: [
                      // DNS server picker (same list as DNS changer servers).
                      // Disabled when Deep Scan is on (app tries every DNS automatically).
                      Text(
                        'DNS Server',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Opacity(
                        opacity: _deepScan ? 0.4 : 1.0,
                        child: IgnorePointer(
                          ignoring: _deepScan,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.black26,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: DropdownButton<String>(
                              value: _selectedSstpDnsValue(),
                              isExpanded: true,
                              underline: const SizedBox.shrink(),
                              dropdownColor:
                                  isDark ? const Color(0xFF1A1A1A) : Colors.white,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 14,
                              ),
                              hint: Text(
                                'Select a DNS server',
                                style: TextStyle(
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                              items: DnsServer.getPublicDnsServers().map((dns) {
                                return DropdownMenuItem<String>(
                                  value: dns.primaryDns,
                                  child: Text('${dns.name}  •  ${dns.primaryDns}'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _dnsController.text = value;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      if (_deepScan)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Disabled while Deep Scan is on — the app tests every DNS automatically.',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.black54,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _dnsController,
                        enabled: !_deepScan,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Custom DNS',
                          hintText: '8.8.8.8',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF00FF88) : Colors.blue,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // سوییچ استفاده از سرور اختصاصی
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Use Custom Server',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _useCustomServer 
                                      ? 'Connect only to custom server'
                                      : 'Use server list (automatic)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _useCustomServer,
                            onChanged: (value) {
                              setState(() {
                                _useCustomServer = value;
                              });
                            },
                            activeTrackColor: isDark ? const Color(0xFF00FF88) : Colors.blue,
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      TextField(
                        controller: _customServerController,
                        enabled: _useCustomServer,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Custom Server',
                          hintText: 'example.com:443',
                          helperText: 'Format: hostname:port',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          helperStyle: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF00FF88) : Colors.blue,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      TextField(
                        controller: _customUsernameController,
                        enabled: _useCustomServer,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Username (Optional)',
                          hintText: 'username',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF00FF88) : Colors.blue,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      TextField(
                        controller: _customPasswordController,
                        enabled: _useCustomServer,
                        obscureText: true,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Password (Optional)',
                          hintText: '••••••••',
                          labelStyle: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF00FF88) : Colors.blue,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Divider(color: isDark ? Colors.white12 : Colors.black12),
                      const SizedBox(height: 12),

                      // ⚙️ MTU - تنظیم واقعی MTU پروتکل SSTP (Off / Auto / Manual)
                      Row(
                        children: [
                          Icon(
                            Icons.tune,
                            color: _mtuMode != 'off'
                                ? (isDark ? const Color(0xFF00FF88) : Colors.blue)
                                : (isDark ? Colors.white38 : Colors.black38),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MTU',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _mtuMode == 'auto'
                                      ? 'Auto: detects the best MTU (1280–1500) before connecting'
                                      : _mtuMode == 'manual'
                                          ? 'Manual: uses your value (1280–1500)'
                                          : 'Off: default MTU (1500). Use Auto/Manual if data does not pass',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white38 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // انتخاب حالت MTU با سه دکمه
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'off', label: Text('Off')),
                          ButtonSegment(value: 'auto', label: Text('Auto')),
                          ButtonSegment(value: 'manual', label: Text('Manual')),
                        ],
                        selected: {_mtuMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) async {
                          final messenger = ScaffoldMessenger.of(context);
                          final mode = selection.first;
                          setState(() {
                            _mtuMode = mode;
                          });
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('mtu_mode', mode);
                          // پاکسازی فلگ قدیمی
                          await prefs.remove('auto_mtu');
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                mode == 'auto'
                                    ? '⚙️ Auto MTU on — best MTU detected on connect'
                                    : mode == 'manual'
                                        ? '⚙️ Manual MTU on — set your value below'
                                        : 'MTU set to default (1500)',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      // فیلد ورودی دستی MTU (فقط در حالت manual)
                      if (_mtuMode == 'manual') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _mtuController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: 'MTU value (1280 – 1500)',
                            labelStyle: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                            helperText: 'Lower values help when data does not pass',
                            helperStyle: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: isDark ? Colors.white24 : Colors.black26,
                              ),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                Icons.save,
                                color: isDark ? const Color(0xFF00FF88) : Colors.blue,
                              ),
                              tooltip: 'Save MTU',
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final parsed = int.tryParse(_mtuController.text.trim());
                                final value = (parsed ?? 1400).clamp(1280, 1500);
                                setState(() {
                                  _mtuController.text = value.toString();
                                });
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setInt('manual_mtu', value);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('MTU saved: $value (applied on next connect)'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Divider(color: isDark ? Colors.white12 : Colors.black12),
                      const SizedBox(height: 12),

                      // ✂️ Fragment - فرگمنت اختصاصی پروتکل SSTP
                      _buildFragmentCard(
                        isDark: isDark,
                        accent: const Color(0xFF00C2FF),
                        enabled: _sstpFragment,
                        sizeController: _sstpFragSizeController,
                        intervalController: _sstpFragIntervalController,
                        sizeLabel: 'Packet size',
                        description:
                            'Splits the SSTP handshake/TLS packets into small '
                            'delayed pieces so DPI/filtering cannot fingerprint the '
                            'connection. Applied on the next connect.',
                        onToggle: (value) {
                          setState(() => _sstpFragment = value);
                          _saveSstpFragment();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(value
                                  ? '✂️ SSTP Fragment enabled — applied on next connect'
                                  : 'SSTP Fragment disabled'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        onChanged: _saveSstpFragment,
                      ),
                      const SizedBox(height: 12),
                      Divider(color: isDark ? Colors.white12 : Colors.black12),
                      const SizedBox(height: 12),

                      // 🔍 Deep Scan - اسکن عمیق برای اینترنت ضعیف یا محدودیت دولتی
                      Row(
                        children: [
                          Icon(
                            Icons.travel_explore,
                            color: _deepScan
                                ? (isDark ? const Color(0xFF00FF88) : Colors.blue)
                                : (isDark ? Colors.white38 : Colors.black38),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Deep Scan',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _deepScan
                                      ? 'On: deeper scan, shorter timeout, more retries'
                                      : 'Turn on for weak internet or heavy censorship',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white38 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _deepScan,
                            onChanged: (value) async {
                              final messenger = ScaffoldMessenger.of(context);
                              setState(() {
                                _deepScan = value;
                              });
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('deep_scan', value);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value
                                        ? '🔍 Deep Scan enabled — scanning more thoroughly'
                                        : 'Deep Scan disabled',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            activeTrackColor:
                                isDark ? const Color(0xFF00FF88) : Colors.blue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(color: isDark ? Colors.white12 : Colors.black12),
                      const SizedBox(height: 12),

                      // ⚡ Parallel server test count (1–300)
                      Row(
                        children: [
                          Icon(
                            Icons.speed,
                            color: isDark
                                ? const Color(0xFF00FF88)
                                : Colors.blue,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Parallel Server Test',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'How many servers are tested at once (1–300). '
                                  'Higher = faster but heavier.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (isDark
                                      ? const Color(0xFF00FF88)
                                      : Colors.blue)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_concurrentTests',
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF00FF88)
                                    : Colors.blue,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _concurrentTests.toDouble().clamp(1, 300),
                        min: 1,
                        max: 300,
                        divisions: 299,
                        label: '$_concurrentTests',
                        activeColor:
                            isDark ? const Color(0xFF00FF88) : Colors.blue,
                        onChanged: (v) =>
                            setState(() => _concurrentTests = v.round()),
                        onChangeEnd: (v) async {
                          final prefs =
                              await SharedPreferences.getInstance();
                          await prefs.setInt(
                              'concurrent_tests', _concurrentTests);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                
                // DNS-specific settings
                if (provider.selectedProtocol == 'direct_dns') ...[
                  _SettingsSection(
                    title: 'DNS changer Settings',
                    children: [
                      Text(
                        'DNS servers can be managed from the Server List screen',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                
                // OpenVPN-specific settings
                if (provider.selectedProtocol == 'openvpn') ...[
                  _SettingsSection(
                    title: 'OpenVPN Settings',
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.pushNamed(context, '/openvpn-configs');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.vpn_key,
                                color: isDark ? Colors.blue[300] : Colors.blue,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Manage Configurations',
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Add, edit, or delete OpenVPN config files',
                                      style: TextStyle(
                                        color: isDark ? Colors.white70 : Colors.black54,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: isDark ? Colors.white38 : Colors.black26,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Slow DNS-specific settings
                if (provider.selectedProtocol == 'slowdns') ...[
                  _SettingsSection(
                    title: 'Slow DNS Settings',
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SlowDnsConfigsScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.dns_outlined,
                                color: isDark ? Colors.blue[300] : Colors.blue,
                                size: 24,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Manage Configurations',
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Add, edit, or delete Slow DNS configs',
                                      style: TextStyle(
                                        color: isDark ? Colors.white70 : Colors.black54,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: isDark ? Colors.white38 : Colors.black26,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Xray-specific settings
                if (provider.selectedProtocol == 'xray') ...[
                  _SettingsSection(
                    title: 'Xray Settings',
                    children: [
                      Text(
                        'Manage servers from the Xray Servers screen on the home '
                        'page. The fragment below applies to the active Xray '
                        'connection.',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      // ✂️ Fragment - فرگمنت واقعی TLS ClientHello مخصوص Xray
                      _buildXrayFragmentCard(isDark),
                      const SizedBox(height: 16),
                      // 🌐 Delay-test URL (server list + 3s home ping)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1DE9B6)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.link,
                                    color: Color(0xFF1DE9B6), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Delay Test URL',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Configs are tested by actually opening THIS site '
                              'through each server — both in the server list and '
                              'the 3-second home-screen ping. Enter any site '
                              '(e.g. https://eset.com) to check which configs can '
                              'reach it. Default: http://www.google.com/gen_204',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white60
                                    : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _xrayTestUrlController,
                              keyboardType: TextInputType.url,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'http://www.google.com/gen_204',
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.03),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.restore, size: 20),
                                  tooltip: 'Reset to default',
                                  color: const Color(0xFF1DE9B6),
                                  onPressed: () {
                                    setState(() {
                                      _xrayTestUrlController.text =
                                          'http://www.google.com/gen_204';
                                    });
                                    _saveXrayTestUrl();
                                  },
                                ),
                              ),
                              onChanged: (_) => _saveXrayTestUrl(),
                              onSubmitted: (_) => _saveXrayTestUrl(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ⚙️ Auto concurrent: pick the count from device power.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _xrayAutoConcurrent
                              ? const Color(0xFF1DE9B6).withValues(alpha: 0.10)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.03)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1DE9B6)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: Color(0xFF1DE9B6), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto (by device power)',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Automatically choose how many configs to '
                                    'test at once based on your phone\'s CPU. '
                                    'Stronger phones test more in parallel.',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _xrayAutoConcurrent,
                              activeThumbColor: const Color(0xFF1DE9B6),
                              onChanged: (v) {
                                setState(() => _xrayAutoConcurrent = v);
                                _saveXrayAutoConcurrent();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 🧪 Concurrent delay-test count (default 30, up to 300)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1DE9B6)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.speed,
                                    color: Color(0xFF1DE9B6), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Concurrent Delay Test',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1DE9B6)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_xrayConcurrentTests',
                                    style: const TextStyle(
                                      color: Color(0xFF1DE9B6),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'How many configs to ping-test at the same time '
                              'when testing a group. Higher = faster but needs '
                              'a more powerful phone. Default 30, max 300.',
                              style: TextStyle(
                                color:
                                    isDark ? Colors.white60 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            Slider(
                              value: _xrayConcurrentTests.toDouble(),
                              min: 1,
                              max: 300,
                              divisions: 299,
                              activeColor: const Color(0xFF1DE9B6),
                              label: '$_xrayConcurrentTests',
                              onChanged: _xrayAutoConcurrent
                                  ? null
                                  : (v) {
                                      setState(() =>
                                          _xrayConcurrentTests = v.round());
                                    },
                              onChangeEnd: _xrayAutoConcurrent
                                  ? null
                                  : (v) => _saveXrayConcurrentTests(),
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('1',
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                        fontSize: 11)),
                                Text('300',
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                        fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 🔁 Group test rounds (retest each server N times, pick best)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1DE9B6)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.repeat,
                                    color: Color(0xFF1DE9B6), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Group Test Rounds',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1DE9B6)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_xrayGroupTestRounds×',
                                    style: const TextStyle(
                                      color: Color(0xFF1DE9B6),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'When you connect to a whole group, each server is '
                              're-tested this many times and the fastest one is '
                              'used. Higher = more accurate best pick but slower. '
                              '1–5, default 1.',
                              style: TextStyle(
                                color:
                                    isDark ? Colors.white60 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            Slider(
                              value: _xrayGroupTestRounds.toDouble(),
                              min: 1,
                              max: 5,
                              divisions: 4,
                              activeColor: const Color(0xFF1DE9B6),
                              label: '$_xrayGroupTestRounds×',
                              onChanged: (v) => setState(
                                  () => _xrayGroupTestRounds = v.round()),
                              onChangeEnd: (v) => _saveXrayGroupTestRounds(),
                            ),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text('1',
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                        fontSize: 11)),
                                Text('5',
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                        fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 🔗 Subscription links
                      _buildSubLinksCard(isDark, provider),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Kill Switch
                _SettingsSection(
                  title: 'Security',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kill Switch',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _killSwitch
                                    ? 'Block internet if VPN disconnects'
                                    : 'Allow internet without VPN',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _killSwitch,
                          onChanged: (value) {
                            setState(() {
                              _killSwitch = value;
                            });
                          },
                          activeTrackColor: isDark ? const Color(0xFF00FF88) : Colors.blue,
                        ),
                      ],
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // App Info
                _SettingsSection(
                  title: 'About',
                  children: [
                    _InfoRow('Protocol', _protocolDisplayName(provider.selectedProtocol), isDark),
                    // Show servers only for SSTP
                    if (provider.selectedProtocol == 'sstp')
                      _InfoRow('Servers', '${provider.servers.length} available', isDark),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark 
                          ? const Color(0xFF00FF88)
                          : Colors.blue,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const _InfoRow(this.label, this.value, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
