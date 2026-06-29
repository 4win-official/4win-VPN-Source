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
  final _xrayFragLengthController = TextEditingController(text: '1-3');
  final _xrayFragIntervalController = TextEditingController(text: '10-20');
  // Xray concurrent delay-test count (how many configs tested at once).
  int _xrayConcurrentTests = 300;

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
    _xrayFragLengthController.dispose();
    _xrayFragIntervalController.dispose();
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
      _xrayFragLengthController.text =
          prefs.getString('xray_fragment_length') ?? '1-3';
      _xrayFragIntervalController.text =
          prefs.getString('xray_fragment_interval') ?? '10-20';
      _xrayConcurrentTests =
          (prefs.getInt('xray_concurrent_tests') ?? 300).clamp(1, 300);
    });
  }

  Future<void> _saveXrayConcurrentTests() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('xray_concurrent_tests', _xrayConcurrentTests);
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
        'xray_fragment_length',
        _xrayFragLengthController.text.trim().isEmpty
            ? '1-3'
            : _xrayFragLengthController.text.trim());
    await prefs.setString(
        'xray_fragment_interval',
        _xrayFragIntervalController.text.trim().isEmpty
            ? '10-20'
            : _xrayFragIntervalController.text.trim());
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
              return Column(
                children: urls
                    .map((u) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.cloud_outlined,
                              size: 18, color: accent),
                          title: Text(u,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              await provider.removeXraySubUrl(u);
                              if (mounted) setState(() {});
                            },
                          ),
                        ))
                    .toList(),
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
        title: const Text('Add Subscription Link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://example.com/sub.txt',
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
                      // ✂️ Fragment - فرگمنت TLS ClientHello مخصوص Xray
                      _buildFragmentCard(
                        isDark: isDark,
                        accent: const Color(0xFF1DE9B6),
                        enabled: _xrayFragment,
                        sizeController: _xrayFragLengthController,
                        intervalController: _xrayFragIntervalController,
                        sizeLabel: 'Length',
                        onToggle: (value) {
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
                        onChanged: _saveXrayFragment,
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
                              onChanged: (v) {
                                setState(
                                    () => _xrayConcurrentTests = v.round());
                              },
                              onChangeEnd: (v) => _saveXrayConcurrentTests(),
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
