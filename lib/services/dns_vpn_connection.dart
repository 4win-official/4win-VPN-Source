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
}
