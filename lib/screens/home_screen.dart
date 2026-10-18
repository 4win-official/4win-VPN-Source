import 'mix_strategies_screen.dart';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/vpn_provider.dart';
import '../widgets/four_win_loader.dart';
import '../providers/theme_provider.dart';
import '../widgets/snow_animation.dart';
import '../widgets/snow_button_surface.dart';
import '../widgets/pixel_effect.dart';
import '../widgets/rain_animation.dart';
import '../widgets/rain_button_surface.dart';
import '../widgets/autumn_animation.dart';
import '../widgets/summer_animation.dart';
import '../widgets/heart_burst.dart';
import '../widgets/protocol_selector_dialog.dart';
import '../widgets/rainbow_heart_button.dart';
import 'donate_screen.dart';
import 'theme_selection_screen.dart';
import 'settings_screen.dart';
import 'guide_screen.dart';
import 'dns_servers_screen.dart';
import 'openvpn_configs_screen.dart';
import 'slowdns_configs_screen.dart';
import 'xray_servers_screen.dart';
import 'proxy_servers_screen.dart';
import 'secret_text_screen.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {

  final UpdateService _updateService = UpdateService();
  final GlobalKey _powerButtonKey = GlobalKey();

  // Pink-theme heart burst: incremented each time the VPN transitions to
  // "connected" so the HeartBurst widget plays a fresh one-shot animation.
  int _heartBurstTrigger = 0;
  VpnConnectionStatus? _lastStatusForHearts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // بررسی خودکار آپدیت هنگام ورود به اپ + نمایش راهنما در اولین اجرا
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Prompt for OpenVPN credentials at connect time when the config needs
      // them but none were entered at import (like the official OpenVPN app).
      if (mounted) {
        context.read<VpnProvider>().onOpenVpnCredentialsRequired =
            _promptOpenVpnCredentials;
      }
      await _maybeShowGuide();
      await _checkForUpdate();
    });
  }

  /// Shows a username/password dialog for an OpenVPN config that requires auth
  /// but has no stored credentials. Returns null if the user cancels.
  Future<({String username, String password})?> _promptOpenVpnCredentials(
      config) async {
    final userCtrl = TextEditingController(
        text: (config.effectiveUsername ?? '').toString());
    final passCtrl = TextEditingController(
        text: (config.effectivePassword ?? '').toString());
    bool obscure = true;
    final result =
        await showDialog<({String username, String password})?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Enter Credentials'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This config requires a username and password.',
                style: TextStyle(
                    fontSize: 13, color: Theme.of(ctx).hintColor),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: userCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () => setD(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final u = userCtrl.text.trim();
                final p = passCtrl.text;
                if (u.isEmpty || p.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Username and password are required')),
                  );
                  return;
                }
                Navigator.pop(ctx, (username: u, password: p));
              },
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  /// در اولین اجرای اپ، راهنمای تصویری به‌صورت خودکار نمایش داده می‌شود تا
  /// کاربر بداند تم را از کجا عوض کند و چطور به تنظیمات برود.
  Future<void> _maybeShowGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('guide_seen') ?? false;
      if (seen) return;
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const GuideScreen()),
      );
      await prefs.setBool('guide_seen', true);
    } catch (_) {
      // نمایش راهنما نباید مانع ادامه‌ی کار اپ شود
    }
  }

  /// بررسی خودکار آپدیت از طریق GitHub Releases و نمایش دیالوگ در صورت وجود نسخه جدید
  Future<void> _checkForUpdate() async {
    try {
      final updateInfo = await _updateService.checkForUpdate();
      if (updateInfo == null) return; // نسخه جدیدی نیست -> کاری نکن
      if (!mounted) return;

      final currentVersion = await _updateService.getCurrentVersion();
      if (!mounted) return;

      await UpdateDialog.show(
        context,
        updateInfo: updateInfo,
        currentVersion: currentVersion,
      );
    } catch (_) {
      // خطا در بررسی آپدیت را بی‌صدا رد کن - نباید تجربه کاربر مختل شود
    }
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
    
    final themeProvider = context.watch<ThemeProvider>();
    final isSnowTheme = themeProvider.selectedTheme == AppTheme.snow;
    final isPixelTheme = themeProvider.selectedTheme == AppTheme.pixel;
    final isPinkTheme = themeProvider.selectedTheme == AppTheme.pink;
    final isRainTheme = themeProvider.selectedTheme == AppTheme.rain;
    final isSummerTheme = themeProvider.selectedTheme == AppTheme.summer;
    final isAutumnTheme = themeProvider.selectedTheme == AppTheme.autumn;
    final isLiquidGlassTheme =
        themeProvider.selectedTheme == AppTheme.liquidGlass;
    
    // Theme-specific colors
    // تم صورتی اکنون نسخه روز و شب دارد:
    //  - روز: پس‌زمینه لاوندر روشن
    //  - شب: پس‌زمینه بنفش-صورتی تیره با لهجه‌های صورتی روشن
    Color bgColor;
    Color iconColor;
    Color textColor;
    if (isPinkTheme) {
      bgColor = isDark
          ? const Color(0xFF2A1A24) // صورتی-بنفش خیلی تیره (نسخه شب)
          : const Color(0xFFFFF0F5); // لاوندر صورتی روشن (نسخه روز)
      iconColor = isDark
          ? const Color(0xFFFF9EC4)
          : const Color(0xFFFF69B4);
      textColor = isDark
          ? const Color(0xFFFFB6D9)
          : const Color(0xFFFF1493);
    } else if (isSummerTheme) {
      // تابستانی همیشه لایت است: آسمان آبی روشن با ته‌رنگ گرم آفتابی
      bgColor = const Color(0xFFFFFDF5);
      iconColor = const Color(0xFFEF6C00); // نارنجی گرم
      textColor = const Color(0xFFE65100);
    } else if (isAutumnTheme) {
      bgColor = isDark
          ? const Color(0xFF20140B) // قهوه‌ای خیلی تیره
          : const Color(0xFFFFF3E6); // کرم گرم پاییزی
      iconColor = isDark
          ? const Color(0xFFE8A055)
          : const Color(0xFFC0392B);
      textColor = isDark
          ? const Color(0xFFF3C892)
          : const Color(0xFF8E4B10);
    } else if (isLiquidGlassTheme) {
      // لیکویید گلس: پس‌زمینه‌ی گرادیانی زیر لایه‌ی شیشه‌ای رندر می‌شود،
      // پس اینجا رنگ پایه‌ی ملایم می‌گذاریم.
      bgColor = isDark ? const Color(0xFF0B1020) : const Color(0xFFEAF0FF);
      iconColor = isDark ? Colors.white : const Color(0xFF1A2540);
      textColor = isDark ? Colors.white : const Color(0xFF10182B);
    } else {
      bgColor = isDark ? const Color(0xFF000000) : Colors.white;
      iconColor = isDark ? Colors.white70 : Colors.black54;
      textColor = isDark ? Colors.white : Colors.black87;
    }
    
    // تم پیکسلی می‌تونه دارک یا لایت باشه (بر خلاف تم برفی که فقط دارک است)

    // When the user picked a custom background (default theme only), let it show
    // through: make the Scaffold transparent instead of painting a solid color.
    final hasCustomBackground = themeProvider.customBackgroundPath != null &&
        themeProvider.customBackgroundPath!.isNotEmpty &&
        File(themeProvider.customBackgroundPath!).existsSync();

    return Scaffold(
      backgroundColor: (hasCustomBackground || isLiquidGlassTheme)
          ? Colors.transparent
          : bgColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, // شفاف - یکپارچه
        elevation: 0,
        // Quick Guide (help) icon sits as the AppBar leading, right in front of
        // the "4win VPN" title — up at the top, exactly where the user wants it.
        leadingWidth: 48,
        leading: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(Icons.help_outline, color: iconColor),
          tooltip: 'Quick Guide',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const GuideScreen()),
            );
          },
        ),
        titleSpacing: 0,
        title: Text(
          '4win VPN',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Secret Text tool — encode/decode text so only 4win VPN can read it.
          IconButton(
            icon: Icon(
              Icons.enhanced_encryption_outlined,
              color: iconColor,
            ),
            tooltip: 'Secret Text',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SecretTextScreen(),
                ),
              );
            },
          ),

          // Theme Selection Button
          IconButton(
            icon: Icon(
              Icons.palette_outlined,
              color: iconColor,
            ),
            tooltip: 'VPN Themes',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ThemeSelectionScreen(),
                ),
              );
            },
          ),
          
          // Dark/Light toggle removed from home — it now lives inside the Theme
          // selection screen (opened via the palette icon).

          // Donate button: liquid-glass heart with an occasional Support Us callout.
          RainbowHeartButton(
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
                        child: FourWinLoader(
                          strokeWidth: 2,
                          color: iconColor,
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
        top: false, // اجازه به محتوا برای رفتن زیر AppBar
        child: Consumer<VpnProvider>(
          builder: (context, provider, _) {
            // Detect the transition into "connected" so the Pink theme can fire
            // a one-shot heart burst. Done via a post-frame callback to keep the
            // build pure.
            if (provider.status != _lastStatusForHearts) {
              final justConnected = provider.status ==
                      VpnConnectionStatus.connected &&
                  _lastStatusForHearts != VpnConnectionStatus.connected;
              _lastStatusForHearts = provider.status;
              if (justConnected && isPinkTheme) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _heartBurstTrigger++);
                  }
                });
              }
            }

            // Custom user background — ONLY for the default (system) theme.
            // Separate image per day/night. Rendered behind everything.
            final customBg = themeProvider.customBackgroundPath;
            final hasCustomBg = customBg != null &&
                customBg.isNotEmpty &&
                File(customBg).existsSync();
            return Stack(
              children: [
                // Liquid Glass: gradient backdrop rendered behind the frosted
                // glass overlay so the blur has something to work with.
                if (isLiquidGlassTheme)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? const [
                                  Color(0xFF1B2A4A),
                                  Color(0xFF0B1020),
                                  Color(0xFF2A1B4A),
                                ]
                              : const [
                                  Color(0xFFBFD4FF),
                                  Color(0xFFEAF0FF),
                                  Color(0xFFDDCBFF),
                                ],
                        ),
                      ),
                    ),
                  ),
                if (isLiquidGlassTheme)
                  const Positioned.fill(
                    child: RepaintBoundary(child: _LiquidGlassBackdrop()),
                  ),

                if (hasCustomBg)
                  Positioned.fill(
                    child: Image.file(
                      File(customBg),
                      fit: BoxFit.cover,
                      // Cache decode size to the screen to save memory/CPU.
                      cacheWidth:
                          (MediaQuery.of(context).size.width *
                                  MediaQuery.of(context).devicePixelRatio)
                              .round(),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                // انیمیشن برف (فقط در تم برفی) — RepaintBoundary keeps the
                // continuous animation from repainting the rest of the tree.
                if (isSnowTheme)
                  const Positioned.fill(
                    child: RepaintBoundary(child: SnowAnimation()),
                  ),

                // افکت پیکسلی (فقط در تم پیکسلی)
                if (isPixelTheme)
                  const Positioned.fill(
                    child: RepaintBoundary(child: PixelEffect()),
                  ),

                // انیمیشن خورشید تابستانی (فقط لایت مود)
                if (isSummerTheme)
                  const Positioned.fill(
                    child: RepaintBoundary(child: SummerAnimation()),
                  ),

                // انیمیشن برگ‌ریزان پاییزی
                if (isAutumnTheme)
                  const Positioned.fill(
                    child: RepaintBoundary(child: AutumnAnimation()),
                  ),
                
                // نور ملایم از پایین صفحه - با انیمیشن نرم
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 800), // انیمیشن آهسته و نرم
                    curve: Curves.easeInOut,
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
                      child: Align(
                        // Center horizontally, but bias vertically slightly
                        // BELOW center so the power button sits centered and a
                        // touch lower, as requested.
                        alignment: const Alignment(0.0, 0.15),
                        child: Consumer<VpnProvider>(
                          builder: (context, provider, _) {
                    // Show loading when servers are being fetched on startup
                    if (provider.isLoadingServers && provider.servers.isEmpty) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const FourWinLoader(),
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
                    
                    // Standard centered layout:
                    //  - The power button is the fixed visual anchor and sits
                    //    in the true center of the screen (slightly below via
                    //    the Stack alignment used by the caller).
                    //  - Protocol selector + status text sit in a fixed-height
                    //    zone ABOVE the button.
                    //  - Stats / errors sit in a fixed-height zone BELOW the
                    //    button. Because both zones have fixed heights, the
                    //    button never moves when text appears or disappears.
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ===== TOP ZONE (fixed height): protocol + status =====
                        SizedBox(
                          height: 150,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Protocol Selector Button
                              Consumer<VpnProvider>(
                                builder: (context, vpnProvider, _) {
                                  return GestureDetector(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => const ProtocolSelectorDialog(),
                                      );
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 32),
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1A1A1A).withValues(alpha: 0.5)
                                            : Colors.white.withValues(alpha: 0.9),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.2)
                                              : Colors.black.withValues(alpha: 0.1),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                vpnProvider.selectedProtocol == 'mix'
                                                    ? Icons.account_tree
                                                    : vpnProvider.selectedProtocol == 'sstp'
                                                    ? Icons.vpn_key
                                                    : vpnProvider.selectedProtocol == 'openvpn'
                                                        ? Icons.shield
                                                        : vpnProvider.selectedProtocol == 'slowdns'
                                                            ? Icons.cloud_queue
                                                            : vpnProvider.selectedProtocol == 'xray'
                                                                ? Icons.rocket_launch
                                                                : vpnProvider.selectedProtocol == 'proxy'
                                                                    ? Icons.swap_horiz
                                                                    : vpnProvider.selectedProtocol == 'psiphon'
                                                                        ? Icons.public
                                                                        : vpnProvider.selectedProtocol == 'warp'
                                                                            ? Icons.cloud_done
                                                                            : Icons.dns,
                                                color: vpnProvider.selectedProtocol == 'mix'
                                                    ? Colors.cyan
                                                    : vpnProvider.selectedProtocol == 'sstp'
                                                    ? Colors.green
                                                    : vpnProvider.selectedProtocol == 'openvpn'
                                                        ? Colors.purple
                                                        : vpnProvider.selectedProtocol == 'slowdns'
                                                            ? Colors.orange
                                                            : vpnProvider.selectedProtocol == 'xray'
                                                                ? Colors.tealAccent.shade700
                                                                : vpnProvider.selectedProtocol == 'proxy'
                                                                    ? Colors.tealAccent.shade700
                                                                    : vpnProvider.selectedProtocol == 'psiphon'
                                                                        ? Colors.deepPurple
                                                                        : vpnProvider.selectedProtocol == 'warp'
                                                                            ? const Color(0xFFF38020)
                                                                            : Colors.blue,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Protocol: ${vpnProvider.selectedProtocol == "mix" ? "Mix · میکس" : vpnProvider.selectedProtocol == "sstp" ? "SSTP" : vpnProvider.selectedProtocol == "openvpn" ? "OpenVPN" : vpnProvider.selectedProtocol == "slowdns" ? "Slow DNS" : vpnProvider.selectedProtocol == "xray" ? "Xray" : vpnProvider.selectedProtocol == "proxy" ? "Proxy" : vpnProvider.selectedProtocol == "psiphon" ? "Psiphon" : vpnProvider.selectedProtocol == "warp" ? "WARP" : "DNS changer"}',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: isDark ? Colors.white : Colors.black87,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            size: 16,
                                            color: isDark ? Colors.white54 : Colors.black54,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 18),

                              // Connection Status Text
                              Text(
                                _getStatusText(provider.status),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              // Active Proxy server name (under the status text).
                              if (provider.selectedProtocol == 'proxy' &&
                                  provider.activeProxyServer != null) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 24),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.swap_horiz,
                                          size: 15,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black45),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          provider.activeProxyServer!.remark
                                                  .isEmpty
                                              ? provider
                                                  .activeProxyServer!.address
                                              : provider
                                                  .activeProxyServer!.remark,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // Active Xray config name (under the status text).
                              if (provider.selectedProtocol == 'xray' &&
                                  provider.activeXrayServer != null) ...[
                                const SizedBox(height: 6),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 24),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.dns,
                                          size: 15,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black45),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          provider.activeXrayServer!.remark.isEmpty
                                              ? provider.activeXrayServer!.address
                                              : provider.activeXrayServer!.remark,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // ===== CENTER: Connect Button (fixed, always centered) =====
                        Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            // Pink theme: colourful hearts burst from behind the
                            // button on connect, then fade out after a moment.
                            if (isPinkTheme)
                              HeartBurst(
                                trigger: _heartBurstTrigger == 0
                                    ? null
                                    : _heartBurstTrigger,
                                size: 340,
                              ),
                            GestureDetector(
                          onTap: () => _handleConnectTap(context, provider),
                          onLongPress: () => _handleLongPress(context),
                          child: Container(
                            key: _powerButtonKey,
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              // تم پیکسلی: مربع با گوشه‌های تیز
                              // تم عادی: دایره
                              shape: isPixelTheme ? BoxShape.rectangle : BoxShape.circle,
                              borderRadius: isPixelTheme ? BorderRadius.zero : null,
                              color: _getButtonColor(provider.status, isDark),
                              border: isPixelTheme 
                                  ? Border.all(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      width: 4,
                                    )
                                  : null,
                              boxShadow: isPixelTheme
                                  ? [
                                      // سایه پیکسلی (بدون blur)
                                      BoxShadow(
                                        offset: const Offset(8, 8),
                                        blurRadius: 0,
                                        color: Colors.black.withValues(alpha: 0.5),
                                      ),
                                    ]
                                  : isSnowTheme ? const [
                                      BoxShadow(
                                        color: Color(0x407AC9E8),
                                        blurRadius: 32,
                                        spreadRadius: 3,
                                      ),
                                      BoxShadow(
                                        color: Color(0x1FBAEFFF),
                                        blurRadius: 64,
                                        spreadRadius: 8,
                                      ),
                                    ]
                                  : isDark ? [
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
                            child: RainButtonSurface(
                              enabled: isRainTheme,
                              child: SnowButtonSurface(
                                enabled: isSnowTheme,
                                tint: _getButtonColor(provider.status, isDark),
                                child: Center(
                                  child: provider.isConnecting
                                      ? FourWinLoader(
                                          color: isDark ? Colors.black87 : Colors.white,
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
                          ),
                        ),
                          ],
                        ),

                        // ===== BOTTOM ZONE (fixed height): stats / errors =====
                        SizedBox(
                          height: 150,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                const SizedBox(height: 20),
                                // Data Usage Info
                                if (provider.isConnected &&
                                    (provider.selectedProtocol == 'sstp' ||
                                        provider.selectedProtocol == 'direct_dns' ||
                                        provider.selectedProtocol == 'xray' ||
                                        provider.selectedProtocol == 'proxy' ||
                                        provider.selectedProtocol == 'warp' ||
                                        provider.selectedProtocol == 'openvpn' ||
                                        provider.selectedProtocol == 'psiphon'))
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
                                    padding: const EdgeInsets.only(top: 12),
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
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: _buildPingIndicator(provider, isDark),
                                        ),
                                      ],
                                    ),
                                  ),
                                // Error Message
                                if (provider.errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12, left: 32, right: 32),
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
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            
            // Server Action Button (Next Server for SSTP, Server List for DNS)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Consumer<VpnProvider>(
                builder: (context, provider, _) {
                  if (provider.selectedProtocol == 'mix') {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(provider.selectedMixStrategy?.name ?? 'No strategy selected',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.account_tree),
                            label: const Text('استراتژی · Strategy'),
                            onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const MixStrategiesScreen())),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  // DNS: Always show "Server List" button
                  if (provider.selectedProtocol == 'direct_dns') {
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DnsServersScreen(),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.dns,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        label: Text(
                          'Server List',
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
                  }
                  
                  // OpenVPN: Always show "OpenVPN Configs" button
                  if (provider.selectedProtocol == 'openvpn') {
                    return SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const OpenVpnConfigsScreen(),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.shield,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        label: Text(
                          'OpenVPN Configs',
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
                  }
                  
                  // Slow DNS: Show DNS Scanner and Configs buttons
                  if (provider.selectedProtocol == 'slowdns') {
                    return Column(
                      children: [
                        // DNS Scanner button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SlowDnsConfigsScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.radar),
                            label: const Text(
                              'DNS Scanner & Configs',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.orange,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  
                  // Proxy: Always show "Proxy Servers" button (mirrors Xray).
                  if (provider.selectedProtocol == 'proxy') {
                    final showNext = provider.proxyGroupSelected;
                    final serverListBtn = ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ProxyServersScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text(
                        'Proxy Servers',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.tealAccent.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );

                    final nextBtn = OutlinedButton.icon(
                      onPressed: provider.isConnecting
                          ? null
                          : () async {
                              await provider.selectNextProxyServer();
                              final s = provider.selectedProxyServer;
                              if (!context.mounted || s == null) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Next: ${s.remark.isEmpty ? s.address : s.remark}'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                      icon: Icon(
                        Icons.skip_next,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      label: Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );

                    return Row(
                      children: [
                        Expanded(flex: showNext ? 3 : 1, child: serverListBtn),
                        if (showNext) ...[
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: nextBtn),
                        ],
                      ],
                    );
                  }

                  // Xray: Always show "Xray Servers" button
                  if (provider.selectedProtocol == 'xray') {
                    final showNext = provider.xrayFreeGroupSelected;
                    final serverListBtn = ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const XrayServersScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.rocket_launch),
                      label: const Text(
                        'Xray Servers',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.tealAccent.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );

                    final nextBtn = OutlinedButton.icon(
                      onPressed: provider.isConnecting
                          ? null
                          : () async {
                              await provider.selectNextFreeServer();
                              final s = provider.selectedXrayServer;
                              if (!context.mounted || s == null) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Next: ${s.remark.isEmpty ? s.address : s.remark}'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                      icon: Icon(
                        Icons.skip_next,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      label: Text(
                        'Next',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                            color:
                                isDark ? Colors.white24 : Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );

                    // Next Server sits NEXT TO the Server List button, and
                    // only when a whole group is selected as the target.
                    return Row(
                      children: [
                        Expanded(flex: showNext ? 3 : 1, child: serverListBtn),
                        if (showNext) ...[
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: nextBtn),
                        ],
                      ],
                    );
                  }

                  // Psiphon: automatic server selection, no server list/next
                  // button to show — Psiphon's tunnel core picks the server.
                  if (provider.selectedProtocol == 'psiphon') {
                    return const SizedBox.shrink();
                  }

                  // WARP: no user-picked server list and no manual "register"
                  // action — the app registers the Cloudflare identity by
                  // itself automatically (on first connect, and again by
                  // itself if a stored identity turns out to be unusable).
                  // This is a plain read-only status readout showing the
                  // Cloudflare edge endpoint currently in use, NOT a button.
                  if (provider.selectedProtocol == 'warp') {
                    final account = provider.warpAccount;
                    final label = provider.warpRegistering
                        ? 'Registering WARP identity…'
                        : account != null
                            ? 'WARP endpoint: ${account.peerEndpoint}'
                            : 'WARP (sets up automatically on connect)';
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: const Color(0xFFF38020).withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cloud_done,
                            color: Color(0xFFF38020),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // SSTP: Show "Next Server" only when connected
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
                // Airborne rain stays above the glow. The solid button masks
                // it, with RainButtonSurface painting impacts/runoff instead.
                // IgnorePointer preserves all controls underneath this layer.
                if (isRainTheme)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: RainAnimation(obstacleKey: _powerButtonKey),
                    ),
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
    final themeProvider = context.watch<ThemeProvider>();
    final isPinkTheme = themeProvider.selectedTheme == AppTheme.pink;
    
    // Pink theme: همه چی صورتی (با نسخه شب)
    if (isPinkTheme) {
      if (isDark) {
        // نسخه شب: رنگ‌های صورتی نئونی/درخشان روی پس‌زمینه تیره
        switch (status) {
          case VpnConnectionStatus.connected:
            return const Color(0xFFFF4FA3); // Neon pink
          case VpnConnectionStatus.connecting:
          case VpnConnectionStatus.disconnecting:
            return const Color(0xFFFF7FB6); // Bright hot pink
          case VpnConnectionStatus.disconnected:
            return const Color(0xFF6E3B52); // Muted dark pink
          case VpnConnectionStatus.error:
            return const Color(0xFFFF5C7A); // Bright crimson-pink
        }
      }
      switch (status) {
        case VpnConnectionStatus.connected:
          return const Color(0xFFFF1493); // Deep pink
        case VpnConnectionStatus.connecting:
        case VpnConnectionStatus.disconnecting:
          return const Color(0xFFFF69B4); // Hot pink
        case VpnConnectionStatus.disconnected:
          return const Color(0xFFFFB6C1); // Light pink
        case VpnConnectionStatus.error:
          return const Color(0xFFDC143C); // Crimson
      }
    }
    
    // Default theme colors
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

  /// The ping row under the timer. For Xray this is a tappable button
  /// (tap-to-ping); the first time it shows "click to ping". Every subsequent
  /// tap runs a fresh measurement. Other protocols keep the auto display.
  Widget _buildPingIndicator(VpnProvider provider, bool isDark) {
    final ping = provider.currentPing;

    if (provider.selectedProtocol == 'xray' || provider.selectedProtocol == 'warp') {
      final pinging = provider.xrayPinging;
      final awaitingFirst = provider.xrayPingAwaitingFirstTap;

      final Widget content;
      if (pinging) {
        content = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: FourWinLoader(
                strokeWidth: 2,
                color: isDark ? const Color(0xFF00FF88) : Colors.blue,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Pinging…',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      } else if (awaitingFirst && ping == null && !provider.pingFailed) {
        content = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app,
                size: 16, color: isDark ? Colors.white54 : Colors.black54),
            const SizedBox(width: 4),
            Text(
              'click to ping',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      } else {
        content = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.network_ping,
              size: 16,
              color: ping != null
                  ? _getPingColor(ping)
                  : (isDark ? Colors.white38 : Colors.black38),
            ),
            const SizedBox(width: 4),
            Text(
              ping != null
                  ? '${ping}ms'
                  : (provider.pingFailed ? 'Failed' : 'click to ping'),
              style: TextStyle(
                fontSize: 13,
                color: ping != null
                    ? _getPingColor(ping)
                    : (provider.pingFailed
                        ? Colors.redAccent
                        : (isDark ? Colors.white54 : Colors.black54)),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }

      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: pinging ? null : () => provider.manualXrayPing(),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: content,
        ),
      );
    }

    // Non-Xray: automatic ping display (unchanged behaviour).
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.network_ping,
          size: 16,
          color: ping != null
              ? _getPingColor(ping)
              : (isDark ? Colors.white38 : Colors.black38),
        ),
        const SizedBox(width: 4),
        Text(
          ping != null
              ? '${ping}ms'
              : (provider.pingFailed ? 'Failed' : 'Testing...'),
          style: TextStyle(
            fontSize: 13,
            color: ping != null
                ? _getPingColor(ping)
                : (provider.pingFailed
                    ? Colors.redAccent
                    : (isDark ? Colors.white38 : Colors.black38)),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
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
        return isDark ? Colors.grey : Colors.grey.shade400; // خاکستری وقتی وصل نیست
      case VpnConnectionStatus.error:
        return isDark ? const Color(0xFFFF4466) : Colors.red; // نئون قرمز فقط برای ارور
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
      // وقتی در حال اتصال است، اگر کاربر تپ کند، قطع شود
      provider.disconnect();
      return;
    }

    if (provider.isConnected) {
      provider.disconnect();
      return;
    }

    // Just connect. For OpenVPN the cert requirement is bypassed automatically
    // inside the provider (the user consents once by pressing connect), and it
    // retries silently every 4s until it connects or hits an auth failure.
    provider.connect();
  }

  void _handleLongPress(BuildContext context) async {
    // Show a quick rotating-gear indicator so the user knows a long-press is
    // taking them to settings (works for every protocol). After the short
    // animation we navigate to the Settings screen.
    HapticFeedback.mediumImpact();
    final navigator = Navigator.of(context);
    await _showSettingsTransition(context);
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  /// Displays a brief animated gear (cog) overlay indicating navigation to
  /// settings. Resolves after the animation completes (~700ms).
  Future<void> _showSettingsTransition(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dialogContext) => const _SettingsTransitionOverlay(),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

/// A short-lived overlay shown when the user long-presses the power button.
/// It displays a rotating gear (cog) with a scale/fade-in animation plus a
/// "Settings" label so the user understands they are heading to settings.
/// It automatically closes itself once the animation completes.
class _SettingsTransitionOverlay extends StatefulWidget {
  const _SettingsTransitionOverlay();

  @override
  State<_SettingsTransitionOverlay> createState() =>
      _SettingsTransitionOverlayState();
}

class _SettingsTransitionOverlayState extends State<_SettingsTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // Spin the gear ~1.25 turns while it appears.
    _rotation = Tween<double>(begin: 0.0, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _scale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _controller.forward().whenComplete(() {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FF88).withValues(alpha: 0.35),
                  blurRadius: 30,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _rotation,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _rotation.value * 2 * 3.1415926535,
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.settings,
                    size: 56,
                    color: Color(0xFF00FF88),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass overlay for the Liquid Glass theme. It blurs whatever is
/// rendered behind it (the gradient backdrop) and lays a subtle translucent
/// sheen + soft floating blobs on top, giving the modern "liquid glass" look.
class _LiquidGlassBackdrop extends StatefulWidget {
  const _LiquidGlassBackdrop();

  @override
  State<_LiquidGlassBackdrop> createState() => _LiquidGlassBackdropState();
}

class _LiquidGlassBackdropState extends State<_LiquidGlassBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Stack(
        children: [
          // Soft floating colour blobs behind the blur for depth.
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              return Stack(
                children: [
                  Positioned(
                    top: 80 + 40 * (0.5 - (t - 0.5).abs()),
                    left: -40,
                    child: _blob(
                        const Color(0xFF4FC3F7).withValues(alpha: 0.5), 220),
                  ),
                  Positioned(
                    bottom: 120 - 40 * (0.5 - (t - 0.5).abs()),
                    right: -50,
                    child: _blob(
                        const Color(0xFFB388FF).withValues(alpha: 0.5), 260),
                  ),
                ],
              );
            },
          ),
          // The blur layer (frosted glass).
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.06),
                          Colors.white.withValues(alpha: 0.02),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0.12),
                        ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }
}
