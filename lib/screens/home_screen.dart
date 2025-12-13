import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vpn_provider.dart';
import '../providers/theme_provider.dart';
import 'donate_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // Reset app when user exits (only if VPN is NOT connected)
    if (state == AppLifecycleState.paused) {
      final provider = context.read<VpnProvider>();
      if (!provider.isConnected) {
        provider.resetState();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        title: Text(
          '4win VPN',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Dark Mode Toggle
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              return IconButton(
                icon: Icon(
                  themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: iconColor,
                ),
                tooltip: 'Toggle Theme',
                onPressed: () => themeProvider.toggleTheme(),
              );
            },
          ),
          
          // Donate Button
          IconButton(
            icon: Icon(Icons.favorite_border, color: iconColor),
            tooltip: 'Support Us',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DonateScreen(),
                ),
              );
            },
          ),
          
          // Refresh Button
          Consumer<VpnProvider>(
            builder: (context, provider, _) {
              return IconButton(
                icon: provider.isLoadingServers
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                        ),
                      )
                    : Icon(Icons.refresh, color: iconColor),
                onPressed: provider.isLoadingServers
                    ? null
                    : () => provider.refreshServers(),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<VpnProvider>(
          builder: (context, provider, _) {
            return Stack(
              children: [
                // نور ملایم از پایین صفحه
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          _getGlowColor(provider.status, isDark).withValues(alpha: isDark ? 0.4 : 0.2),
                          _getGlowColor(provider.status, isDark).withValues(alpha: isDark ? 0.2 : 0.1),
                          _getGlowColor(provider.status, isDark).withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // محتوای اصلی
                Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Consumer<VpnProvider>(
                          builder: (context, provider, _) {
                    // Show loading when servers are being fetched on startup
                    if (provider.isLoadingServers && provider.servers.isEmpty) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white70 : Colors.black87),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Loading servers...',
                            style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white70 : Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                        ],
                      );
                    }
                    
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Connection Status Text
                        Text(
                          _getStatusText(provider.status),
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 40),
                        
                        // Connect Button
                        GestureDetector(
                          onTap: () => _handleConnectTap(context, provider),
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _getButtonColor(provider.status, isDark),
                              boxShadow: isDark ? [
                                // نئون گلو در dark mode
                                BoxShadow(
                                  color: _getButtonColor(provider.status, isDark).withValues(alpha: 0.6),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                                BoxShadow(
                                  color: _getButtonColor(provider.status, isDark).withValues(alpha: 0.4),
                                  blurRadius: 80,
                                  spreadRadius: 20,
                                ),
                              ] : [
                                BoxShadow(
                                  color: _getButtonColor(provider.status, isDark).withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Center(
                              child: provider.isConnecting
                                  ? CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        isDark ? Colors.black87 : Colors.white
                                      ),
                                      strokeWidth: 3,
                                    )
                                  : Icon(
                                      _getButtonIcon(provider.status),
                                      size: 80,
                                      color: isDark ? Colors.black87 : Colors.white,
                                    ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Data Usage Info
                        if (provider.isConnected)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              provider.dataUsage,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        
                        // Connection Duration
                        if (provider.isConnected && provider.connectionDuration.inSeconds > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              children: [
                                Text(
                                  _formatDuration(provider.connectionDuration),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? Colors.white54 : Colors.black54,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                // Show ping (همیشه نمایش داده شود)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.network_ping,
                                        size: 16,
                                        color: provider.currentPing != null 
                                            ? _getPingColor(provider.currentPing!)
                                            : (isDark ? Colors.white38 : Colors.black38),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        provider.currentPing != null 
                                            ? '${provider.currentPing}ms'
                                            : 'Testing...',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: provider.currentPing != null
                                              ? _getPingColor(provider.currentPing!)
                                              : (isDark ? Colors.white38 : Colors.black38),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        
                        // Error Message
                        if (provider.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16, left: 32, right: 32),
                            child: Text(
                              provider.errorMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.red[300]! : Colors.red,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            
            // Next Server Button (only show when connected)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Consumer<VpnProvider>(
                builder: (context, provider, _) {
                  if (!provider.isConnected) {
                    return const SizedBox.shrink();
                  }
                  
                  return SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: provider.isConnecting ? null : () => provider.connectToNextServer(),
                      icon: Icon(
                        Icons.skip_next,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      label: Text(
                        'Next Server',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _getStatusText(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return 'Connected';
      case VpnConnectionStatus.connecting:
        return 'Connecting...';
      case VpnConnectionStatus.disconnecting:
        return 'Disconnecting...';
      case VpnConnectionStatus.disconnected:
        return 'Disconnected';
      case VpnConnectionStatus.error:
        return 'Error';
    }
  }

  Color _getButtonColor(VpnConnectionStatus status, bool isDark) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return isDark ? const Color(0xFF00FF88) : const Color(0xFF4CAF50); // نئون سبز
      case VpnConnectionStatus.connecting:
      case VpnConnectionStatus.disconnecting:
        return isDark ? const Color(0xFFFF9944) : Colors.orange; // نئون نارنجی
      case VpnConnectionStatus.disconnected:
        return isDark ? Colors.white : Colors.black87; // سفید در dark mode
      case VpnConnectionStatus.error:
        return isDark ? const Color(0xFFFF4466) : Colors.red; // نئون قرمز
    }
  }

  Color _getPingColor(int ping) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (ping < 100) {
      return isDark ? const Color(0xFF00FF88) : Colors.green; // نئون سبز
    }
    if (ping < 200) {
      return isDark ? const Color(0xFF88FF44) : Colors.lightGreen; // نئون سبز روشن
    }
    if (ping < 400) {
      return isDark ? const Color(0xFFFF9944) : Colors.orange; // نئون نارنجی
    }
    return isDark ? const Color(0xFFFF4466) : Colors.red; // نئون قرمز
  }

  // رنگ نور ملایم از پایین صفحه
  Color _getGlowColor(VpnConnectionStatus status, bool isDark) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return isDark ? const Color(0xFF00FF88) : const Color(0xFF4CAF50); // نئون سبز
      case VpnConnectionStatus.connecting:
      case VpnConnectionStatus.disconnecting:
        return isDark ? const Color(0xFFFF9944) : Colors.orange; // نئون نارنجی
      case VpnConnectionStatus.disconnected:
      case VpnConnectionStatus.error:
        return isDark ? const Color(0xFFFF4466) : Colors.red; // نئون قرمز
    }
  }

  IconData _getButtonIcon(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return Icons.power_settings_new;
      case VpnConnectionStatus.connecting:
      case VpnConnectionStatus.disconnecting:
        return Icons.sync;
      case VpnConnectionStatus.disconnected:
        return Icons.power_settings_new;
      case VpnConnectionStatus.error:
        return Icons.error_outline;
    }
  }

  void _handleConnectTap(BuildContext context, VpnProvider provider) {
    if (provider.isConnecting) {
      return; // Do nothing while connecting
    }

    if (provider.isConnected) {
      provider.disconnect();
    } else {
      provider.connect();
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
