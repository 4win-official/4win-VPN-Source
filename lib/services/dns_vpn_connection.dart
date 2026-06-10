import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class DnsVpnConnection {
  static const platform = MethodChannel('com.forwin.vpn/dns');
  
  /// Start DNS VPN with specified DNS servers
  static Future<bool> connect({
    required String primaryDns,
    String secondaryDns = '8.8.4.4',
  }) async {
    try {
      final result = await platform.invokeMethod('connectDns', {
        'primaryDns': primaryDns,
        'secondaryDns': secondaryDns,
      });
      return result == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ DNS VPN connect error: $e');
      }
      return false;
    }
  }
  
  /// Stop DNS VPN
  static Future<bool> disconnect() async {
    try {
      final result = await platform.invokeMethod('disconnectDns');
      return result == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ DNS VPN disconnect error: $e');
      }
      return false;
    }
  }
  
  /// Check if DNS VPN permission is granted
  static Future<bool> requestPermission() async {
    try {
      final result = await platform.invokeMethod('requestDnsPermission');
      return result == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ DNS VPN permission error: $e');
      }
      return false;
    }
  }

  /// پینگ واقعی به سرور DNS (به‌صورت native).
  /// این روش حتی وقتی VPN دایرکت DNS فعال است هم به‌درستی کار می‌کند.
  /// خروجی: تاخیر بر حسب میلی‌ثانیه، یا null در صورت ناموفق بودن.
  static Future<int?> pingDns(String dnsIp) async {
    try {
      final result = await platform.invokeMethod('pingDns', {'dnsIp': dnsIp});
      if (result is int && result >= 0) {
        return result;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ DNS ping error: $e');
      }
      return null;
    }
  }

  /// مجموع ترافیک رد و بدل شده دستگاه (بایت) را برمی‌گرداند
  /// خروجی: {'rxBytes': int, 'txBytes': int}
  static Future<Map<String, int>> getStats() async {
    try {
      final result = await platform.invokeMethod('getDnsStats');
      if (result is Map) {
        return {
          'rxBytes': (result['rxBytes'] as num?)?.toInt() ?? 0,
          'txBytes': (result['txBytes'] as num?)?.toInt() ?? 0,
        };
      }
      return {'rxBytes': 0, 'txBytes': 0};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ DNS VPN getStats error: $e');
      }
      return {'rxBytes': 0, 'txBytes': 0};
    }
  }
}
