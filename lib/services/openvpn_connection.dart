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

  /// Callback for live byte counters (bytesIn, bytesOut) reported by the core.
  static void Function(int bytesIn, int bytesOut)? onByteCount;
  
  /// Initialize OpenVPN
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      _openvpn = OpenVPN(
        onVpnStatusChanged: (data) {
          if (data != null) {
            // byteIn/byteOut arrive as strings from the core; parse defensively.
            final inB = int.tryParse((data.byteIn ?? '').toString()) ?? 0;
            final outB = int.tryParse((data.byteOut ?? '').toString()) ?? 0;
            if (onByteCount != null) onByteCount!(inB, outB);
          }
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

      // Parse ONCE (the model caches these) — never in a rebuild path.
      final username = config.effectiveUsername;
      final password = config.effectivePassword;
      final normalizedConfigContent = config.normalizedConfig;

      // Basic sanity check: a config with no `remote` line can never connect
      // and can wedge the native core. Fail fast with a clear message instead
      // of freezing on a hopeless attempt.
      if (!normalizedConfigContent
          .contains(RegExp(r'^\s*remote\s+\S+', multiLine: true))) {
        if (kDebugMode) debugPrint('❌ OpenVPN config has no remote line');
        return false;
      }
      
      if (kDebugMode) {
        debugPrint('🚀 Connecting to OpenVPN: ${config.name}');
        debugPrint('   Server: ${config.serverAddress}:${config.serverPort}');
        debugPrint('   Protocol: ${config.protocol}');
        debugPrint('   Username: ${username != null && username.isNotEmpty ? "✅ Provided (${username.substring(0, username.length > 3 ? 3 : username.length)}***)" : "❌ Not provided"}');
        debugPrint('   Password: ${password != null && password.isNotEmpty ? "✅ Provided (${password.length} chars)" : "❌ Not provided"}');
        if (config.embeddedUsername != null) {
          debugPrint('   📄 Credentials extracted from config file');
        }
        if (username != null && username.isNotEmpty) {
          debugPrint('   🔐 Credentials will be injected into config');
        }
        
        // Log first 500 chars of normalized config for debugging
        final configPreview = normalizedConfigContent.length > 500 
            ? '${normalizedConfigContent.substring(0, 500)}...' 
            : normalizedConfigContent;
        debugPrint('📝 Normalized config preview (first 500 chars):');
        debugPrint(configPreview);
      }
      
      // 🔴 CRITICAL FIX — the real reason "the file connects the official
      // OpenVPN app but not ours":
      //
      // We USED to call `requestPermissionAndroid()` first and, if it returned
      // false, ABORT with `return false`. But on Android that method returns
      // false IMMEDIATELY when the system VPN-consent dialog is shown — before
      // the user taps "OK". So the very first connection (or any time consent
      // was revoked) aborted instantly and never started, while the consent
      // dialog was still on screen. Even after the user granted consent, our
      // code had already bailed, so nothing connected.
      //
      // The plugin's native `connect` handler already does the correct
      // prepare → startActivityForResult → onActivityResult(connectWhileGranted)
      // dance itself: it stores the config in static fields, shows the consent
      // dialog if needed, and starts the tunnel once consent returns. So we
      // must call `connect(...)` DIRECTLY and let the native side own the
      // permission flow — exactly like the official app does. Do NOT gate it on
      // a pre-check that races the dialog.
      //
      // openvpn_flutter 1.3.4 quirk: when certIsRequired == false it does
      //   config += "client-cert-not-required";
      // i.e. it APPENDS that text to the config WITHOUT a newline, gluing it
      // onto whatever the last line is. That only breaks things when the config
      // does NOT already end in a newline. `normalizedConfig` now guarantees a
      // trailing newline, so the appended directive lands cleanly on its own
      // line — which is exactly what ics-openvpn expects for username/password
      // (no client-cert) profiles.
      //
      // We pass certIsRequired based on whether the config actually carries a
      // client certificate:
      //   • has client cert  → certIsRequired: true  → plugin leaves config
      //     untouched (the cert is used).
      //   • no client cert    → certIsRequired: false → plugin appends the
      //     client-cert-not-required directive on its own line, so the core
      //     doesn't stall waiting for a certificate.
      // This mirrors the plugin's own tested happy path and is why the tunnel
      // now actually establishes.
      final needsCert = config.hasClientCert;
      _openvpn.connect(
        normalizedConfigContent,
        config.name,
        username: username,
        password: password,
        certIsRequired: needsCert,
        bypassPackages: [],
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
