import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import '../models/openvpn_config.dart';

/// OpenVPN Connection Handler
class OpenVpnConnection {
  static late OpenVPN _openvpn;
  static bool _initialized = false;
  static VPNStage? _currentStage;
  static String? _connectedConfigName;

  static DateTime? _connectRequestedAt;
  static bool _sawConnected = false;
  static int _generation = 0;
  static int get generation => _generation;
  static bool _userStopped = false;

  // Lightweight post-connect health monitor. It performs a small HEAD request
  // every 20 seconds and only starts recovery after two consecutive failures.
  // This avoids a busy loop and keeps the battery/network overhead tiny.
  static Timer? _healthTimer;
  static int _healthFailures = 0;
  static bool _healthRecoveryInProgress = false;
  static OpenVpnConfig? _lastConfig;
  static bool _lastForceBypassCert = false;

  static const MethodChannel _nativeChannel =
      MethodChannel('com.forwin.vpn/openvpn');

  static String? lastError;
  static bool authFailed = false;
  static void Function()? onAuthFailed;
  static void Function(VPNStage?)? onStageChanged;
  static bool _nativeStateHandlerAttached = false;
  static void Function(int bytesIn, int bytesOut)? onByteCount;

  static void beginSession() {
    authFailed = false;
  }

  static void _markAuthFailed() {
    if (authFailed) return;
    authFailed = true;
    lastError = 'Authentication failed. Wrong username or password.';
    _currentStage = VPNStage.error;
    _stopHealthMonitor();
    if (onAuthFailed != null) onAuthFailed!();
    if (onStageChanged != null) onStageChanged!(VPNStage.error);
  }

  static void _attachNativeStateHandler() {
    if (_nativeStateHandlerAttached) return;
    _nativeStateHandlerAttached = true;
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenVpnState') {
        final args = call.arguments;
        if (args is Map && args['authFailed'] == true) {
          _markAuthFailed();
        }
      }
      return null;
    });
  }

  static Future<void> initialize() async {
    _attachNativeStateHandler();
    if (_initialized) return;
    try {
      _openvpn = OpenVPN(
        onVpnStatusChanged: (data) {
          if (data != null) {
            final inB = int.tryParse((data.byteIn ?? '').toString()) ?? 0;
            final outB = int.tryParse((data.byteOut ?? '').toString()) ?? 0;
            onByteCount?.call(inB, outB);
          }
          if (kDebugMode && data != null) {
            debugPrint('🔵 OpenVPN Status: duration=${data.duration ?? "N/A"}, in=${data.byteIn ?? "N/A"}, out=${data.byteOut ?? "N/A"}');
          }
        },
        onVpnStageChanged: (VPNStage stage, String message) {
          if (kDebugMode) debugPrint('🔵 OpenVPN Stage: $stage — $message');
          final msg = message.toLowerCase();
          final stageStr = stage.toString().toLowerCase();
          if (msg.contains('auth_failed') ||
              msg.contains('authfailed') ||
              msg.contains('auth failed') ||
              msg.contains('auth-failure') ||
              msg.contains('authentication failed') ||
              stageStr.contains('auth_failed')) {
            _markAuthFailed();
            return;
          }

          if (stage == VPNStage.disconnected || stage == VPNStage.exiting) {
            final reqAt = _connectRequestedAt;
            final inGrace = reqAt != null &&
                DateTime.now().difference(reqAt) < const Duration(seconds: 12);
            if (inGrace && !_sawConnected) {
              if (kDebugMode) debugPrint('↳ ignoring spurious "$stage" during connect grace window');
              return;
            }
            _stopHealthMonitor();
          }

          if (stage == VPNStage.connected) {
            _sawConnected = true;
            _healthFailures = 0;
            _startHealthMonitor();
          }

          _currentStage = stage;
          onStageChanged?.call(stage);
        },
      );

      await _openvpn.initialize(
        groupIdentifier: 'group.com.forwin.vpn',
        providerBundleIdentifier: 'com.forwin.vpn.VPNExtension',
        localizedDescription: '4win VPN',
      );
      _initialized = true;
      if (kDebugMode) debugPrint('✅ OpenVPN initialized successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to initialize OpenVPN: $e');
      rethrow;
    }
  }

  /// Checks real internet reachability through the currently active tunnel.
  /// Two small endpoints are tried to reduce false positives from a blocked
  /// endpoint. No large response body is downloaded.
  static Future<bool> _hasInternet() async {
    const endpoints = <String>[
      'https://cp.cloudflare.com/generate_204',
      'https://www.google.com/generate_204',
    ];
    for (final raw in endpoints) {
      HttpClient? client;
      try {
        client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 4)
          ..idleTimeout = const Duration(seconds: 4);
        final request = await client.headUrl(Uri.parse(raw)).timeout(const Duration(seconds: 5));
        request.followRedirects = true;
        final response = await request.close().timeout(const Duration(seconds: 5));
        await response.drain<void>();
        client.close(force: true);
        if (response.statusCode >= 200 && response.statusCode < 400) return true;
      } catch (_) {
        client?.close(force: true);
      }
    }
    return false;
  }

  static void _startHealthMonitor() {
    _healthTimer?.cancel();
    _healthFailures = 0;
    _healthRecoveryInProgress = false;
    _healthTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _runHealthCheck();
    });
    // Do not immediately probe on connect; give the tunnel a short settling
    // period and let the first scheduled check happen after 20 seconds.
  }

  static void _stopHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _healthFailures = 0;
    _healthRecoveryInProgress = false;
  }

  static Future<void> _runHealthCheck() async {
    if (_userStopped || _currentStage != VPNStage.connected || _healthRecoveryInProgress) return;
    final ok = await _hasInternet();
    if (_userStopped || _currentStage != VPNStage.connected) return;
    if (ok) {
      _healthFailures = 0;
      return;
    }

    _healthFailures++;
    if (kDebugMode) debugPrint('⚠️ OpenVPN health check failed ($_healthFailures/2)');
    if (_healthFailures < 2 || _lastConfig == null) return;
    await _recoverConnection();
  }

  static Future<void> _recoverConnection() async {
    if (_healthRecoveryInProgress || _userStopped || _lastConfig == null) return;
    _healthRecoveryInProgress = true;
    final config = _lastConfig!;
    final bypass = _lastForceBypassCert;
    _stopHealthMonitor();

    if (kDebugMode) debugPrint('🔄 OpenVPN tunnel appears unhealthy; restarting connection');
    try {
      try {
        _openvpn.disconnect();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (_userStopped) return;
      await connect(config, forceBypassCert: bypass);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ OpenVPN automatic recovery failed: $e');
    } finally {
      _healthRecoveryInProgress = false;
    }
  }

  static Future<bool> precheckCertIssue(OpenVpnConfig config) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await _nativeChannel.invokeMethod<dynamic>(
          'validateConfig',
          {'config': config.normalizedConfig, 'name': config.name},
        );
        if (res is Map && res['ok'] != true) {
          final err = (res['error'] ?? '').toString().toLowerCase();
          return err.contains('cert') || err.contains('certificate');
        }
        return false;
      } on MissingPluginException {
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    return false;
  }

  static Future<bool> connect(
    OpenVpnConfig config, {
    bool forceBypassCert = false,
  }) async {
    final int myGen = ++_generation;
    _userStopped = false;
    _lastConfig = config;
    _lastForceBypassCert = forceBypassCert;
    try {
      _connectRequestedAt = DateTime.now();
      _sawConnected = false;
      await initialize();
      if (myGen != _generation || _userStopped) {
        if (kDebugMode) debugPrint('🚫 OpenVPN connect $myGen aborted (stale)');
        return false;
      }

      final username = config.effectiveUsername;
      final password = config.effectivePassword;
      final normalizedConfigContent = forceBypassCert
          ? config.configWithoutClientCert
          : config.normalizedConfig;

      if (!normalizedConfigContent.contains(RegExp(r'^\s*remote\s+\S+', multiLine: true))) {
        if (kDebugMode) debugPrint('❌ OpenVPN config has no remote line');
        return false;
      }

      if (kDebugMode) {
        debugPrint('🚀 Connecting to OpenVPN: ${config.name}');
        debugPrint('   Server: ${config.serverAddress}:${config.serverPort}');
        debugPrint('   Protocol: ${config.protocol}');
        debugPrint('   Username: ${username != null && username.isNotEmpty ? "Provided" : "Not provided"}');
        debugPrint('   Password: ${password != null && password.isNotEmpty ? "Provided" : "Not provided"}');
      }

      _connectRequestedAt = DateTime.now();
      _sawConnected = false;
      lastError = null;
      try {
        final res = await _nativeChannel.invokeMethod<dynamic>(
          'validateConfig',
          {'config': normalizedConfigContent, 'name': config.name},
        );
        if (res is Map && res['ok'] != true) {
          final err = (res['error'] ?? 'unknown').toString();
          lastError = err;
          if (kDebugMode) debugPrint('❌ OpenVPN config rejected by native parser: $err');
          if (err.startsWith('parse_error')) {
            onStageChanged?.call(VPNStage.error);
            return false;
          }
        }
      } on MissingPluginException {
        // Older native builds may not expose validateConfig.
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ OpenVPN native validate failed: $e');
      }

      if (myGen != _generation || _userStopped) {
        try { _openvpn.disconnect(); } catch (_) {}
        return false;
      }

      await _openvpn.connect(
        normalizedConfigContent,
        config.name,
        username: username,
        password: password,
        // openvpn_flutter 1.3.4 appends `client-cert-not-required` to the
        // *client* profile whenever this is false. That is a server-side option
        // removed in OpenVPN 2.5, so the core can reject an otherwise valid
        // profile. The profile content (including any explicit cert bypass)
        // already determines the client credentials; keep the plugin from
        // mutating it here.
        certIsRequired: true,
        bypassPackages: [],
      );
      _connectedConfigName = config.name;
      if (kDebugMode) debugPrint('✅ OpenVPN connect command sent successfully');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to connect OpenVPN: $e');
      _connectRequestedAt = null;
      onStageChanged?.call(VPNStage.error);
      return false;
    }
  }

  static Future<bool> disconnect({bool resetAuthState = true}) async {
    _generation++;
    _userStopped = true;
    _stopHealthMonitor();
    if (resetAuthState) authFailed = false;
    try {
      if (!_initialized) {
        _connectRequestedAt = null;
        _sawConnected = false;
        return true;
      }
      if (kDebugMode) debugPrint('🛑 Disconnecting OpenVPN...');
      _openvpn.disconnect();
      _connectedConfigName = null;
      _currentStage = null;
      _connectRequestedAt = null;
      _sawConnected = false;
      if (kDebugMode) debugPrint('✅ OpenVPN disconnected successfully');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to disconnect OpenVPN: $e');
      return false;
    }
  }

  static VPNStage? getCurrentStage() => _currentStage;
  static String? getConnectedConfigName() => _connectedConfigName;
  static bool isConnected() => _currentStage == VPNStage.connected;
  static bool isConnecting() =>
      _currentStage == VPNStage.connecting ||
      _currentStage == VPNStage.prepare ||
      _currentStage == VPNStage.authenticating;
  static bool isDisconnected() =>
      _currentStage == VPNStage.disconnected ||
      _currentStage == VPNStage.disconnecting ||
      _currentStage == null;

  static String getStageDisplayName(VPNStage? stage) {
    if (stage == null) return 'Disconnected';
    switch (stage) {
      case VPNStage.prepare: return 'Preparing...';
      case VPNStage.authenticating: return 'Authenticating...';
      case VPNStage.connecting: return 'Connecting...';
      case VPNStage.connected: return 'Connected';
      case VPNStage.disconnecting: return 'Disconnecting...';
      case VPNStage.disconnected: return 'Disconnected';
      case VPNStage.denied: return 'Connection Denied';
      case VPNStage.error: return 'Connection Error';
      case VPNStage.exiting: return 'Exiting...';
      default: return stage.toString();
    }
  }
}
