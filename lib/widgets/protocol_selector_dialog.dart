import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/settings_screen.dart';

class ProtocolSelectorDialog extends StatelessWidget {
  const ProtocolSelectorDialog({super.key});

  /// Open the per-protocol settings page for [protocol].
  void _openProtocolSettings(BuildContext context, String protocol) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(initialProtocol: protocol),
      ),
    );
  }

  /// Open the GLOBAL settings (affect every protocol) + updates.
  void _openGlobalSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(generalOnly: true),
      ),
    );
  }

  /// A small round gear button used both at the top (global) and per-protocol.
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Consumer<VpnProvider>(
      builder: (context, vpnProvider, _) {
        return Dialog(
          backgroundColor: Colors.transparent,
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header: title + GLOBAL settings gear (affects all protocols).
                    Row(
                      children: [
                        const SizedBox(width: 34), // balance the trailing gear
                        Expanded(
                          child: Text(
                            'Select Protocol',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
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
                    const SizedBox(height: 12),

                    // Xray Option (real Xray core / v2rayNG) — DEFAULT, shown first
                    ListTile(
                      leading: Icon(
                        Icons.rocket_launch,
                        color: vpnProvider.selectedProtocol == 'xray'
                            ? Colors.tealAccent.shade700
                            : (isDark ? Colors.white54 : Colors.black54),
                        size: 28,
                      ),
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Xray',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight:
                                    vpnProvider.selectedProtocol == 'xray'
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.tealAccent.shade700
                                    .withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'Recommended',
                              style: TextStyle(
                                color: Colors.tealAccent.shade700,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'Real Xray core + TLS fragment',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (vpnProvider.selectedProtocol == 'xray')
                            Icon(Icons.check_circle,
                                color: Colors.tealAccent.shade700),
                          _gearButton(
                            context,
                            isDark: isDark,
                            tooltip: 'Xray settings',
                            onTap: () => _openProtocolSettings(context, 'xray'),
                          ),
                        ],
                      ),
                      onTap: () {
                        vpnProvider.switchProtocol('xray');
                        Navigator.pop(context); // Auto-close
                      },
                    ),

                    const Divider(height: 20),

                    // SSTP Option
                    ListTile(
                      leading: Icon(
                        Icons.vpn_key,
                        color: vpnProvider.selectedProtocol == 'sstp'
                            ? Colors.green
                            : (isDark ? Colors.white54 : Colors.black54),
                        size: 28,
                      ),
                      title: Text(
                        'SSTP',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: vpnProvider.selectedProtocol == 'sstp'
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        'Automatic server selection',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (vpnProvider.selectedProtocol == 'sstp')
                            const Icon(Icons.check_circle, color: Colors.green),
                          _gearButton(
                            context,
                            isDark: isDark,
                            tooltip: 'SSTP settings',
                            onTap: () => _openProtocolSettings(context, 'sstp'),
                          ),
                        ],
                      ),
                      onTap: () {
                        vpnProvider.switchProtocol('sstp');
                        Navigator.pop(context); // Auto-close
                      },
                    ),
                    
                    const Divider(height: 20),
                    
                    // Direct DNS Option
                    ListTile(
                      leading: Icon(
                        Icons.dns,
                        color: vpnProvider.selectedProtocol == 'direct_dns'
                            ? Colors.blue
                            : (isDark ? Colors.white54 : Colors.black54),
                        size: 28,
                      ),
                      title: Text(
                        'DNS changer',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: vpnProvider.selectedProtocol == 'direct_dns'
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        'Connect via DNS servers',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (vpnProvider.selectedProtocol == 'direct_dns')
                            const Icon(Icons.check_circle, color: Colors.blue),
                          _gearButton(
                            context,
                            isDark: isDark,
                            tooltip: 'DNS changer settings',
                            onTap: () =>
                                _openProtocolSettings(context, 'direct_dns'),
                          ),
                        ],
                      ),
                      onTap: () {
                        vpnProvider.switchProtocol('direct_dns');
                        Navigator.pop(context); // Auto-close
                      },
                    ),
                    
                    const Divider(height: 20),
                    
                    // OpenVPN Option
                    ListTile(
                      leading: Icon(
                        Icons.shield,
                        color: vpnProvider.selectedProtocol == 'openvpn'
                            ? Colors.purple
                            : (isDark ? Colors.white54 : Colors.black54),
                        size: 28,
                      ),
                      title: Text(
                        'OpenVPN',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: vpnProvider.selectedProtocol == 'openvpn'
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        'Custom config support',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (vpnProvider.selectedProtocol == 'openvpn')
                            const Icon(Icons.check_circle,
                                color: Colors.purple),
                          _gearButton(context,
                              isDark: isDark,
                              tooltip: 'OpenVPN settings',
                              onTap: () =>
                                  _openProtocolSettings(context, 'openvpn')),
                        ],
                      ),
                      onTap: () {
                        vpnProvider.switchProtocol('openvpn');
                        Navigator.pop(context); // Auto-close
                      },
                    ),
                    
                    const Divider(height: 20),
                    
                    // Slow DNS Option
                    ListTile(
                      leading: Icon(
                        Icons.cloud_queue,
                        color: vpnProvider.selectedProtocol == 'slowdns'
                            ? Colors.orange
                            : (isDark ? Colors.white54 : Colors.black54),
                        size: 28,
                      ),
                      title: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Slow DNS',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight:
                                    vpnProvider.selectedProtocol == 'slowdns'
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Beta badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'Beta',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        'DNS Tunneling for heavy censorship',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (vpnProvider.selectedProtocol == 'slowdns')
                            const Icon(Icons.check_circle,
                                color: Colors.orange),
                          _gearButton(context,
                              isDark: isDark,
                              tooltip: 'Slow DNS settings',
                              onTap: () =>
                                  _openProtocolSettings(context, 'slowdns')),
                        ],
                      ),
                      onTap: () {
                        vpnProvider.switchProtocol('slowdns');
                        Navigator.pop(context); // Auto-close
                      },
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
