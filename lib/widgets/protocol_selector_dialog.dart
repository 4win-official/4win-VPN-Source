import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/settings_screen.dart';

class ProtocolSelectorDialog extends StatelessWidget {
  const ProtocolSelectorDialog({super.key});

  void _openProtocolSettings(BuildContext context, String protocol) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(initialProtocol: protocol)));
  }

  void _openGlobalSettings(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen(generalOnly: true)));
  }

  Widget _gearButton(BuildContext context, {required VoidCallback onTap, required bool isDark, required String tooltip, Color? color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.settings, size: 22, color: color ?? (isDark ? Colors.white54 : Colors.black54)),
        ),
      ),
    );
  }

  Widget _titleText(BuildContext context, String text, VpnProvider provider, bool isDark, String protocol, double fontSize) {
    return Text(text, style: TextStyle(
      color: isDark ? Colors.white : Colors.black87,
      fontWeight: provider.selectedProtocol == protocol ? FontWeight.bold : FontWeight.w500,
      fontSize: fontSize,
    ));
  }

  Widget _protocolTile(BuildContext context, VpnProvider provider, bool isDark, {
    required String protocol,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    bool settings = true,
  }) {
    final selected = provider.selectedProtocol == protocol;
    return ListTile(
      leading: Icon(icon, color: selected ? accent : (isDark ? Colors.white54 : Colors.black54), size: 28),
      title: _titleText(context, title, provider, isDark, protocol, 16),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) Icon(Icons.check_circle, color: accent),
          if (settings) _gearButton(context, isDark: isDark, tooltip: '$title settings', onTap: () => _openProtocolSettings(context, protocol)),
        ],
      ),
      onTap: () {
        provider.switchProtocol(protocol);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<VpnProvider>(
      builder: (context, vpnProvider, _) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A1A).withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.1), width: 1.5),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    const SizedBox(width: 34),
                    Expanded(child: Text('Select Protocol', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))),
                    _gearButton(context, isDark: isDark, tooltip: 'General settings (all protocols)', color: isDark ? Colors.white : Colors.black87, onTap: () => _openGlobalSettings(context)),
                  ]),
                  const SizedBox(height: 12),
                  _protocolTile(context, vpnProvider, isDark, protocol: 'psiphon', title: 'Psiphon', subtitle: 'Automatic server discovery and selection', icon: Icons.public, accent: Colors.tealAccent.shade700, settings: false),
                  const Divider(height: 20),
                  _protocolTile(context, vpnProvider, isDark, protocol: 'xray', title: 'Xray', subtitle: 'Real Xray core + TLS fragment', icon: Icons.rocket_launch, accent: Colors.tealAccent.shade700),
                  const Divider(height: 20),
                  _protocolTile(context, vpnProvider, isDark, protocol: 'proxy', title: 'Proxy', subtitle: 'Real SOCKS4 / SOCKS5 / HTTP proxy', icon: Icons.swap_horiz, accent: Colors.tealAccent.shade700),
                  const Divider(height: 20),
                  _protocolTile(context, vpnProvider, isDark, protocol: 'sstp', title: 'SSTP', subtitle: 'Automatic server selection', icon: Icons.vpn_key, accent: Colors.green),
                  const Divider(height: 20),
                  _protocolTile(context, vpnProvider, isDark, protocol: 'direct_dns', title: 'DNS changer', subtitle: 'Connect via DNS servers', icon: Icons.dns, accent: Colors.blue),
                  const Divider(height: 20),
                  _protocolTile(context, vpnProvider, isDark, protocol: 'openvpn', title: 'OpenVPN', subtitle: 'Custom config support', icon: Icons.shield, accent: Colors.purple),
                  const Divider(height: 20),
                  _protocolTile(context, vpnProvider, isDark, protocol: 'slowdns', title: 'Slow DNS', subtitle: 'DNS Tunneling for heavy censorship', icon: Icons.cloud_queue, accent: Colors.orange),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
