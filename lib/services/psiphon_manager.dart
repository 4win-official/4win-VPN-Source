import 'package:flutter/services.dart';
import 'dart:async';

class PsiphonVpnManager {
  static const platform = MethodChannel('com.forwin.vpn/psiphon');
  static const String _channelName = 'com.forwin.vpn/psiphon';
  
  /// Request VPN permission from user
  /// Returns true if already granted, false if user needs to approve
  static Future<bool> preparePsiphon() async {
    try {
      final bool result = await platform.invokeMethod('prepare');
      return result;
    } catch (e) {
      print('Error preparing Psiphon: $e');
      return false;
    }
  }

  /// Start Psiphon VPN connection
  /// [egressRegion] - Target region (e.g., 'US', 'CA', 'DE', '' for auto)
  static Future<bool> startPsiphon({String egressRegion = ''}) async {
    try {
      final bool result = await platform.invokeMethod(
        'start',
        {'egressRegion': egressRegion},
      );
      return result;
    } catch (e) {
      print('Error starting Psiphon: $e');
      return false;
    }
  }

  /// Stop Psiphon VPN connection
  static Future<bool> stopPsiphon() async {
    try {
      final bool result = await platform.invokeMethod('stop');
      return result;
    } catch (e) {
      print('Error stopping Psiphon: $e');
      return false;
    }
  }

  /// Reconnect Psiphon VPN
  /// [egressRegion] - Target region
  static Future<bool> reconnectPsiphon({String egressRegion = ''}) async {
    try {
      final bool result = await platform.invokeMethod(
        'reconnect',
        {'egressRegion': egressRegion},
      );
      return result;
    } catch (e) {
      print('Error reconnecting Psiphon: $e');
      return false;
    }
  }

  /// Check if Psiphon service is running
  static Future<bool> isPsiphonRunning() async {
    try {
      final bool result = await platform.invokeMethod('isRunning');
      return result;
    } catch (e) {
      print('Error checking if Psiphon is running: $e');
      return false;
    }
  }

  /// Check if Psiphon tunnel is connected
  static Future<bool> isPsiphonConnected() async {
    try {
      final bool result = await platform.invokeMethod('isConnected');
      return result;
    } catch (e) {
      print('Error checking if Psiphon is connected: $e');
      return false;
    }
  }

  /// Query traffic statistics
  /// Returns map with 'uplink' and 'downlink' in bytes
  static Future<Map<String, dynamic>> queryTrafficStats() async {
    try {
      final Map<dynamic, dynamic> result =
          await platform.invokeMethod('queryStats');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      print('Error querying Psiphon stats: $e');
      return {'uplink': 0, 'downlink': 0};
    }
  }

  /// Format bytes to human readable format
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = (bytes.toString().length ~/ 3).toInt();
    double size = bytes / (1024 * (i == 0 ? 1 : i));
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  /// Convert milliseconds to human readable format
  static String formatTime(int milliseconds) {
    int seconds = milliseconds ~/ 1000;
    int minutes = seconds ~/ 60;
    int hours = minutes ~/ 60;
    int days = hours ~/ 24;

    if (days > 0) return '$days day${days > 1 ? 's' : ''}';
    if (hours > 0) return '$hours hour${hours > 1 ? 's' : ''}';
    if (minutes > 0) return '$minutes min${minutes > 1 ? 's' : ''}';
    return '$seconds sec${seconds > 1 ? 's' : ''}';
  }
}
