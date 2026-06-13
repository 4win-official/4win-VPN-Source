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

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
    });
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
      default:
        return protocol;
    }
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
