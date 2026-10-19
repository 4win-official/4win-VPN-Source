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

  /// Runs the advanced native DNS scanner over [ips], testing each with a real
  /// UDP DNS query + TCP/53 probe (concurrently). Returns the raw JSON string
  /// the native side produces (array of {ip, udpMs, tcpMs, reachable}), or
  /// null on failure. [domain] is the name queried during the probe.
  static Future<String?> scanDns(
    List<String> ips, {
    String domain = 'google.com',
    int parallel = 100,
    int port = 53,
    int timeoutMs = 2500,
  }) async {
    try {
      final result = await platform.invokeMethod('scanDns', {
        'ips': ips,
        'domain': domain,
        'parallel': parallel,
        'port': port,
        'timeoutMs': timeoutMs,
      });
      return result is String ? result : null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ DNS scan error: $e');
      }
      return null;
    }
  }

  /// Manually set the SSTP MTU. Writes the sstp_flutter plugin's PPP MTU value
  /// natively (into the plugin's default SharedPreferences) so the next connect
  /// really uses it. [mtu] should be in 1280..1500. Returns true on success.
  static Future<bool> setSstpMtu(int mtu) async {
    try {
      final result = await platform.invokeMethod('setSstpMtu', {'mtu': mtu});
      return result == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ setSstpMtu error: $e');
      }
      return false;
    }
  }

  /// REAL automatic MTU detection. Probes the path to [host] using DF-bit pings,
  /// binary-searching for the largest non-fragmenting size, converts it to a safe
  /// inner (PPP) MTU within [minMtu]..[maxMtu], persists it natively, and returns
  /// the detected MTU. Returns null on failure.
  static Future<int?> detectBestMtu(
    String host, {
    int minMtu = 1280,
    int maxMtu = 1500,
  }) async {
    try {
      final result = await platform.invokeMethod('detectBestMtu', {
        'host': host,
        'minMtu': minMtu,
        'maxMtu': maxMtu,
      });
      if (result is int) return result;
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ detectBestMtu error: $e');
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
