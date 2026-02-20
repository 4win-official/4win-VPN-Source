import 'package:flutter/foundation.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import '../models/openvpn_config.dart';

/// OpenVPN Connection Handler
class OpenVpnConnection {
  static late OpenVPN _openvpn;
  static bool _initialized = false;
  static VPNStage? _currentStage;
  static String? _connectedConfigName;
  
  /// Callback for status changes
  static void Function(VPNStage?)? onStageChanged;
  
  /// Initialize OpenVPN
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      _openvpn = OpenVPN(
        onVpnStatusChanged: (data) {
          if (kDebugMode) {
            debugPrint('🔵 OpenVPN Status Changed:');
            if (data != null) {
              debugPrint('   Duration: ${data.duration ?? "N/A"}');
              debugPrint('   Byte In: ${data.byteIn ?? "N/A"}');
              debugPrint('   Byte Out: ${data.byteOut ?? "N/A"}');
            }
          }
        },
        onVpnStageChanged: (VPNStage stage, String message) {
          if (kDebugMode) {
            debugPrint('🔵 OpenVPN Stage: $stage');
            debugPrint('   Message: $message');
          }
          _currentStage = stage;
          if (onStageChanged != null) {
            onStageChanged!(stage);
          }
        },
      );
      
      // Initialize for Android (no group identifier needed)
      await _openvpn.initialize(
        groupIdentifier: 'group.com.forwin.vpn',
        providerBundleIdentifier: 'com.forwin.vpn.VPNExtension',
        localizedDescription: '4win VPN',
      );
      
      _initialized = true;
      
      if (kDebugMode) {
        debugPrint('✅ OpenVPN initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to initialize OpenVPN: $e');
      }
      rethrow;
    }
  }
  
  /// Connect to OpenVPN server
  static Future<bool> connect(OpenVpnConfig config) async {
    try {
      await initialize();
      
      // ✅ استفاده از effectiveUsername و effectivePassword
      // اولویت با username/password embedded در فایل است
      final username = config.effectiveUsername;
      final password = config.effectivePassword;
      
      if (kDebugMode) {
        debugPrint('🚀 Connecting to OpenVPN: ${config.name}');
        debugPrint('   Server: ${config.serverAddress}:${config.serverPort}');
        debugPrint('   Protocol: ${config.protocol}');
        debugPrint('   Username: ${username != null && username.isNotEmpty ? "✅ Provided (${username.substring(0, username.length > 3 ? 3 : username.length)}***)" : "❌ Not provided"}');
        debugPrint('   Password: ${password != null && password.isNotEmpty ? "✅ Provided (${password.length} chars)" : "❌ Not provided"}');
        if (config.embeddedUsername != null) {
          debugPrint('   📄 Credentials extracted from config file');
        }
        
        // Log first 500 chars of config for debugging
        final configPreview = config.config.length > 500 
            ? '${config.config.substring(0, 500)}...' 
            : config.config;
        debugPrint('📝 Config preview (first 500 chars):');
        debugPrint(configPreview);
      }
      
      // ✅ Request Android VPN permission first
      try {
        final permissionGranted = await _openvpn.requestPermissionAndroid();
        if (kDebugMode) {
          debugPrint('📱 Android VPN permission: ${permissionGranted ? "✅ Granted" : "❌ Denied"}');
        }
        
        if (!permissionGranted) {
          if (kDebugMode) {
            debugPrint('❌ VPN permission denied by user');
          }
          return false;
        }
      } catch (e) {
        // Permission request not available on iOS or error
        if (kDebugMode) {
          debugPrint('⚠️ Permission request error (might be iOS): $e');
        }
      }
      
      // ✅ Connect after permission granted
      _openvpn.connect(
        config.config,
        config.name,
        username: username,
        password: password,
        certIsRequired: false, // برای جلوگیری از stuck شدن در iOS
        bypassPackages: [], // لیست اپ‌هایی که نباید از VPN استفاده کنند
      );
      
      _connectedConfigName = config.name;
      
      if (kDebugMode) {
        debugPrint('✅ OpenVPN connect command sent successfully');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to connect OpenVPN: $e');
      }
      return false;
    }
  }
  
  /// Disconnect from OpenVPN
  static Future<bool> disconnect() async {
    try {
      if (!_initialized) {
        return true;
      }
      
      if (kDebugMode) {
        debugPrint('🛑 Disconnecting OpenVPN...');
      }
      
      _openvpn.disconnect();
      _connectedConfigName = null;
      _currentStage = null;
      
      if (kDebugMode) {
        debugPrint('✅ OpenVPN disconnected successfully');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to disconnect OpenVPN: $e');
      }
      return false;
    }
  }
  
  /// Get current connection stage
  static VPNStage? getCurrentStage() {
    return _currentStage;
  }
  
  /// Get connected config name
  static String? getConnectedConfigName() {
    return _connectedConfigName;
  }
  
  /// Check if connected
  static bool isConnected() {
    return _currentStage == VPNStage.connected;
  }
  
  /// Check if connecting
  static bool isConnecting() {
    return _currentStage == VPNStage.connecting ||
           _currentStage == VPNStage.prepare ||
           _currentStage == VPNStage.authenticating;
  }
  
  /// Check if disconnected
  static bool isDisconnected() {
    return _currentStage == VPNStage.disconnected ||
           _currentStage == VPNStage.disconnecting ||
           _currentStage == null;
  }
  
  /// Get stage display name
  static String getStageDisplayName(VPNStage? stage) {
    if (stage == null) return 'Disconnected';
    
    switch (stage) {
      case VPNStage.prepare:
        return 'Preparing...';
      case VPNStage.authenticating:
        return 'Authenticating...';
      case VPNStage.connecting:
        return 'Connecting...';
      case VPNStage.connected:
        return 'Connected';
      case VPNStage.disconnecting:
        return 'Disconnecting...';
      case VPNStage.disconnected:
        return 'Disconnected';
      case VPNStage.denied:
        return 'Connection Denied';
      case VPNStage.error:
        return 'Connection Error';
      case VPNStage.exiting:
        return 'Exiting...';
      default:
        return stage.toString();
    }
  }
}
