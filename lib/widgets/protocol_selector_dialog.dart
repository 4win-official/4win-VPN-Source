// Protocol order: Xray, Psiphon, WARP, OpenVPN, SSTP, DNS changer, Proxy, Slow DNS.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import 'protocol_glass_surface.dart';
import '../screens/settings_screen.dart';
import '../screens/mix_strategies_screen.dart';

class ProtocolSelectorDialog extends StatelessWidget {
  const ProtocolSelectorDialog({super.key});

  void _openProtocolSettings(BuildContext context, String protocol) {
    if (protocol == 'mix') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MixStrategiesScreen()),
      );
      return;
    }
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
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(
            Icons.settings_outlined,
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
            ? FontWeight.w600
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
    String? badge,
  }) {
    final selected = provider.selectedProtocol == protocol;
    final ink = isDark ? const Color(0xFFF2F5F4) : const Color(0xFF202C2F);
    final secondaryInk = isDark
        ? const Color(0xFFCED6D5)
        : const Color(0xFF465457);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Ink(
          key: ValueKey('protocol-row-$protocol'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: selected
                  ? [
                      Colors.white.withValues(alpha: isDark ? 0.10 : 0.24),
                      Colors.white.withValues(alpha: isDark ? 0.025 : 0.06),
                    ]
                  : const [Colors.transparent, Colors.transparent],
            ),
            border: Border.all(
              width: 0.6,
              color: selected
                  ? Colors.white.withValues(alpha: isDark ? 0.34 : 0.72)
                  : Colors.transparent,
            ),
          ),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            contentPadding: const EdgeInsets.only(left: 12, right: 2),
            minLeadingWidth: 30,
            horizontalTitleGap: 10,
            leading: SizedBox(
              width: 34,
              height: 38,
              child: Icon(icon, color: ink.withValues(alpha: 0.82), size: 21),
            ),
            title: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _titleText(context, title, provider, isDark, protocol, 16),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: ink.withValues(alpha: 0.10)),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: secondaryInk,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: secondaryInk),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) Icon(Icons.check_rounded, color: ink, size: 20),
                _gearButton(
                  context,
                  isDark: isDark,
                  color: ink.withValues(alpha: 0.78),
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
        ),
      ),
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
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: ProtocolGlassSurface(
              isDark: isDark,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Close protocol selector',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 21),
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF334155),
                        ),
                        Expanded(
                          child: Text(
                            'Select Protocol',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      child: Text(
                        'Choose your connection',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF42536A),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        thickness: 2,
                        radius: const Radius.circular(2),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'mix',
                                title: 'Mix',
                                subtitle: 'Ordered, real multi-hop strategies',
                                icon: Icons.account_tree,
                              ),
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'xray',
                                title: 'Xray',
                                subtitle: 'Real Xray core + TLS fragment',
                                icon: Icons.rocket_launch,

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
                              ),
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'warp',
                                title: 'WARP',
                                subtitle: 'Cloudflare WireGuard tunnel',
                                icon: Icons.cloud_done,
                              ),
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'openvpn',
                                title: 'OpenVPN',
                                subtitle: 'Custom config support',
                                icon: Icons.shield,
                              ),
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'sstp',
                                title: 'SSTP',
                                subtitle: 'Automatic server selection',
                                icon: Icons.vpn_key,
                              ),
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'direct_dns',
                                title: 'DNS changer',
                                subtitle: 'Connect via DNS servers',
                                icon: Icons.dns,
                              ),
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'proxy',
                                title: 'Proxy',
                                subtitle: 'SOCKS4 / SOCKS5 / HTTP proxy',
                                icon: Icons.swap_horiz,
                              ),
                              _protocolTile(
                                context,
                                provider: vpnProvider,
                                isDark: isDark,
                                protocol: 'slowdns',
                                title: 'Slow DNS',
                                subtitle: 'DNS Tunneling for heavy censorship',
                                icon: Icons.cloud_queue,

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
        );
      },
    );
  }
}
