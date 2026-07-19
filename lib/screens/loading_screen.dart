import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/vpn_provider.dart';
import '../main.dart' show markHomeReady;
import 'home_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadServersAndNavigate();
  }

  /// خواندن خودکار نسخه اپ از pubspec (package_info)
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {
      // اگر خواندن نسخه ناموفق بود، چیزی نمایش نده
    }
  }

  Future<void> _loadServersAndNavigate() async {
    final provider = context.read<VpnProvider>();
    
    // درخواست اجازه نوتیفیکیشن
    await _requestNotificationPermission();

    // لود سرورهای Xray در کنار سرورهای SSTP (بدون بلاک کردن ناوبری).
    // ابتدا سرورهای ذخیره‌شده، سپس به‌روزرسانی گروه رایگان (با throttle داخلی).
    unawaited(() async {
      try {
        await provider.loadXrayServers();
        // در لود اسکرین فقط ساب‌لینک‌های پیش‌فرض (Free + Plus) آپدیت می‌شوند.
        // ساب‌لینک‌های کاربر دست‌نخورده می‌مانند و از دکمه‌ی رفرش سرور لیست
        // آپدیت می‌شوند. Plus فقط در صورتی نمایش داده می‌شود که سرور داشته باشد.
        await provider.refreshXrayFreeGroup(force: true, builtInOnly: true);
      } catch (_) {}
    }());

    // Wait for servers to load and test
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Wait until servers are loaded
    while (provider.isLoadingServers) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    // Navigate to home screen
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
      // Signal the .ovpn import flow that the stack has settled on Home, so it
      // can safely push the import screen without it being wiped.
      markHomeReady();
    }
  }

  Future<void> _requestNotificationPermission() async {
    // فقط برای Android 13+ نیاز به درخواست دارد
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white, // Pure black
      body: SafeArea(
        child: Stack(
          children: [
            Center(
          child: Consumer<VpnProvider>(
            builder: (context, provider, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo/Icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark 
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // App Name
                  Text(
                    '4win VPN',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Loading Indicator
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.white70 : Colors.black87,
                      ),
                      strokeWidth: 3,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Loading Text
                  Text(
                    provider.errorMessage ?? 'Loading server list...',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Server count progress
                  if (provider.servers.isNotEmpty)
                    Text(
                      'Testing ${provider.servers.length} servers...',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  

                ],
              );
            },
          ),
            ),

            // نمایش نسخه اپ پایین صفحه (خودکار از pubspec)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  _appVersion.isNotEmpty ? 'Version $_appVersion' : '',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
