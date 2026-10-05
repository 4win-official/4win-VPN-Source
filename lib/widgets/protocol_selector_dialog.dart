// Protocol order: Xray, Psiphon, WARP, OpenVPN, SSTP, DNS changer, Proxy, Slow DNS.
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/settings_screen.dart';

class ProtocolSelectorDialog extends StatelessWidget {
  const ProtocolSelectorDialog({super.key});

  void _openProtocolSettings(BuildContext context, String protocol) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(initialProtocol: protocol),
      ),
    );
  }

  void _openGlobalSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(generalOnly: true),
      ),
    );
  }

  Widget _gearButton(
    BuildContext context, {
    required VoidCallback onTap,
    required bool isDark,
    required String tooltip,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            Icons.settings,
            size: 22,
            color: color ?? (isDark ? Colors.white54 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _titleText(
    BuildContext context,
    String text,
    VpnProvider provider,
    bool isDark,
    String protocol,
    double fontSize,
  ) {
    return Text(
      text,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontWeight: provider.selectedProtocol == protocol
            ? FontWeight.bold
            : FontWeight.w500,
        fontSize: fontSize,
      ),
    );
  }

  Widget _protocolTile(
    BuildContext context, {
    required VpnProvider provider,
    required bool isDark,
    required String protocol,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    bool divider = true,
    String? badge,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            icon,
            color: provider.selectedProtocol == protocol
                ? accent
                : (isDark ? Colors.white54 : Colors.black54),
            size: 28,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _titleText(
                  context,
                  title,
                  provider,
                  isDark,
                  protocol,
                  16,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.selectedProtocol == protocol)
                Icon(Icons.check_circle, color: accent),
              _gearButton(
                context,
                isDark: isDark,
                tooltip: '$title settings',
                onTap: () => _openProtocolSettings(context, protocol),
              ),
            ],
          ),
          onTap: () {
            provider.switchProtocol(protocol);
            Navigator.pop(context);
          },
        ),
        if (divider) const Divider(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    final dialogHeight = (screen.height * 0.72).clamp(360.0, 620.0);
    final dialogWidth = (screen.width * 0.92).clamp(300.0, 440.0);

    return Consumer<VpnProvider>(
      builder: (context, vpnProvider, _) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A1A1A).withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.1),
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 34),
                          Expanded(
                            child: Text(
                              'Select Protocol',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          _gearButton(
                            context,
                            isDark: isDark,
                            tooltip: 'General settings (all protocols)',
                            color: isDark ? Colors.white : Colors.black87,
                            onTap: () => _openGlobalSettings(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: [
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'xray',
                                  title: 'Xray',
                                  subtitle: 'Real Xray core + TLS fragment',
                                  icon: Icons.rocket_launch,
                                  accent: Colors.tealAccent.shade700,
                                  badge: 'Default',
                                ),
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'psiphon',
                                  title: 'Psiphon',
                                  subtitle: 'Automatic server selection',
                                  icon: Icons.public,
                                  accent: Colors.deepPurple,
                                ),
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'warp',
                                  title: 'WARP',
                                  subtitle: 'Cloudflare WireGuard tunnel',
                                  icon: Icons.cloud_done,
                                  accent: const Color(0xFFF38020),
                                ),
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'openvpn',
                                  title: 'OpenVPN',
                                  subtitle: 'Custom config support',
                                  icon: Icons.shield,
                                  accent: Colors.purple,
                                ),
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'sstp',
                                  title: 'SSTP',
                                  subtitle: 'Automatic server selection',
                                  icon: Icons.vpn_key,
                                  accent: Colors.green,
                                ),
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'direct_dns',
                                  title: 'DNS changer',
                                  subtitle: 'Connect via DNS servers',
                                  icon: Icons.dns,
                                  accent: Colors.blue,
                                ),
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'proxy',
                                  title: 'Proxy',
                                  subtitle: 'SOCKS4 / SOCKS5 / HTTP proxy',
                                  icon: Icons.swap_horiz,
                                  accent: Colors.tealAccent.shade700,
                                ),
                                _protocolTile(
                                  context,
                                  provider: vpnProvider,
                                  isDark: isDark,
                                  protocol: 'slowdns',
                                  title: 'Slow DNS',
                                  subtitle: 'DNS Tunneling for heavy censorship',
                                  icon: Icons.cloud_queue,
                                  accent: Colors.orange,
                                  divider: false,
                                  badge: 'Beta',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
