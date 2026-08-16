import 'dart:async';
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

  /// Timestamp of the last `connect()` request. Used to swallow the SPURIOUS
  /// `disconnected` stage the native core emits while it is still preparing /
  /// showing the VPN-consent dialog — that early `disconnected` was flipping the
  /// UI back to "disconnected" the instant the user tapped connect, so the
  /// tunnel never appeared to start. We ignore `disconnected` for a short grace
  /// window right after a connect request UNLESS we had already reached a real
  /// connected state.
  static DateTime? _connectRequestedAt;
  static bool _sawConnected = false;

  /// Monotonic token bumped on every connect() AND disconnect(). An in-flight
  /// connect captures its token; if disconnect() (or a newer connect) bumps it,
  /// the stale attempt is abandoned and its late connected/error callbacks are
  /// ignored. This is what makes "disconnect while connecting" actually stop the
  /// background attempt and keeps a failed config from poisoning later attempts.
  static int _generation = 0;
  static int get generation => _generation;
  static bool _userStopped = false;

  /// True once the tunnel has entered the "authenticating" phase (raw core
  /// state AUTH → plugin stage "authenticating"). ics-openvpn's bundled
  /// VPNHelper does NOT map the AUTH_FAILED core state to any plugin stage, so
  /// when the server rejects the credentials the plugin stays silent and just
  /// drops back to disconnected/reconnect/noprocess. We use that transition —
  /// "was authenticating, never reached connected, now dropping" — as a
  /// RELIABLE client-side auth-failure signal that does not depend on the flaky
  /// native AUTH_FAILED string reaching Dart.
  static bool _sawAuthenticating = false;

  /// Watchdog that fires if we sit in the "authenticating" phase too long
  /// without connecting — another strong wrong-credentials symptom (the server
  /// keeps renegotiating / the auth handshake never completes).
  static Timer? _authWatchdog;

  /// Native channel to validate an OpenVPN config with the REAL ics-openvpn
  /// parser/checkProfile before we hand it to the plugin (whose connect path
  /// silently swallows parse errors). Lets us surface the actual reason a
  /// config is rejected instead of a silent no-op.
  static const MethodChannel _nativeChannel =
      MethodChannel('com.forwin.vpn/openvpn');

  /// The last real error reported by native validation (for the UI/logs).
  static String? lastError;

  /// Set true when the core reports an authentication failure (wrong
  /// username/password). This is a HARD, non-retryable error — the caller must
  /// stop retrying immediately and tell the user their credentials are wrong,
  /// exactly like the official OpenVPN app.
  ///
  /// IMPORTANT: this flag is SESSION-STICKY. It is reset ONLY when the user
  /// starts a brand-new connection via [beginSession] (or on [disconnect]),
  /// NOT on each internal retry `connect()`. Otherwise an auth-failure that
  /// arrives slightly late (after the retry loop already started the next
  /// attempt) would be wiped by that attempt's reset and the loop would spin
  /// forever — which is exactly why wrong credentials were never detected.
  static bool authFailed = false;

  /// Optional callback fired the instant an auth failure is detected natively,
  /// so the retry loop can abort immediately instead of waiting for the next
  /// iteration. Set by the connect path.
  static void Function()? onAuthFailed;

  /// Reset per-user-connection state. Called by the provider at the very start
  /// of a user-initiated OpenVPN connect (before the retry loop), so the
  /// auth-failed flag is cleared exactly once per user action.
  static void beginSession() {
    authFailed = false;
    _sawAuthenticating = false;
    _authWatchdog?.cancel();
    _authWatchdog = null;
  }

  /// Central auth-failure trigger. Idempotent — sets the sticky flag, records
  /// the message, cancels the watchdog, notifies the retry loop and flips the
  /// stage to error exactly once.
  static void _markAuthFailed() {
    if (authFailed) return;
    authFailed = true;
    lastError = 'Authentication failed. Wrong username or password.';
    _currentStage = VPNStage.error;
    _authWatchdog?.cancel();
    _authWatchdog = null;
    if (onAuthFailed != null) onAuthFailed!();
    if (onStageChanged != null) onStageChanged!(VPNStage.error);
  }

  /// Callback for status changes
  static void Function(VPNStage?)? onStageChanged;

  /// True once we've attached the native OpenVPN state-channel handler.
  static bool _nativeStateHandlerAttached = false;

  /// Attach a handler on the native OPENVPN_CHANNEL so the app receives the
  /// authoritative ics-openvpn state events pushed from MainActivity
  /// ("onOpenVpnState"). The native side reports LEVEL_AUTH_FAILED directly, so
  /// this is the RELIABLE wrong-username/password signal (the plugin's own
  /// status-string mapping is lossy and was missing auth failures).
  static void _attachNativeStateHandler() {
    if (_nativeStateHandlerAttached) return;
    _nativeStateHandlerAttached = true;
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onOpenVpnState') {
        final args = call.arguments;
        if (args is Map) {
          final authFail = args['authFailed'] == true;
          if (authFail) {
            _markAuthFailed();
          }
        }
      }
      return null;
    });
  }

  /// Callback for live byte counters (bytesIn, bytesOut) reported by the core.
  static void Function(int bytesIn, int bytesOut)? onByteCount;
  
  /// Initialize OpenVPN
  static Future<void> initialize() async {
    // Always ensure the native state handler is attached (cheap, idempotent) so
    // auth-failure events are received even before/without full init.
    _attachNativeStateHandler();
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
            debugPrint('🔵 OpenVPN Stage: $stage — $message');
          }

          // 🔴 AUTH FAILURE detection FIRST (before any grace-window filtering),
          // because after "AUTH_FAILED" ics-openvpn quickly drops to NOPROCESS
          // (disconnected), which the grace window would otherwise swallow. The
          // raw native status string arrives in `message` (e.g. "AUTH_FAILED").
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

          // ── HEURISTIC auth-failure detection (the reliable path) ────────────
          // ics-openvpn's bundled VPNHelper maps the core AUTH state to the
          // plugin stage "authenticating" but has NO case for the AUTH_FAILED
          // core state — so on wrong credentials the plugin NEVER emits an
          // auth-failed stage/message; it silently drops back to
          // disconnected / no_connection / reconnect. We therefore infer the
          // failure from the transition:
          //   authenticating  →  (disconnected | noconnection | reconnect | error)
          // while we NEVER reached "connected". That transition, or repeatedly
          // bouncing on "authenticating", is a wrong-username/password.
          final isAuthStage = stageStr.contains('authenticating') ||
              (stageStr.contains('auth') && !stageStr.contains('failed'));
          if (stage == VPNStage.authenticating || isAuthStage) {
            _sawAuthenticating = true;
            // Arm/refresh a watchdog: if we are still stuck authenticating (or
            // bouncing through it) after 12s without ever connecting, treat it
            // as an auth failure and stop.
            _authWatchdog?.cancel();
            _authWatchdog = Timer(const Duration(seconds: 12), () {
              if (!_sawConnected && !authFailed) {
                if (kDebugMode) {
                  debugPrint('🛑 Stuck authenticating >12s → treat as auth fail');
                }
                _markAuthFailed();
              }
            });
          }

          // If we had entered the authenticating phase and now drop WITHOUT ever
          // having connected → the server rejected the credentials.
          final droppedAfterAuth = _sawAuthenticating &&
              !_sawConnected &&
              (stage == VPNStage.disconnected ||
                  stage == VPNStage.exiting ||
                  stage == VPNStage.error ||
                  stage == VPNStage.denied ||
                  stageStr.contains('noconnection') ||
                  stageStr.contains('no_connection') ||
                  stageStr.contains('noprocess') ||
                  stageStr.contains('disconnected'));
          if (droppedAfterAuth) {
            if (kDebugMode) {
              debugPrint('🛑 Dropped after authenticating (never connected) '
                  '→ auth failure');
            }
            _markAuthFailed();
            return;
          }

          // 🔴 CRITICAL: filter the SPURIOUS early `disconnected`.
          //
          // The native core emits `disconnected` (its DEFAULT status) as soon as
          // the engine is queried — which happens right when we call connect()
          // and while the system VPN-consent dialog is still on screen, BEFORE
          // the tunnel starts. Passing that through flipped our provider back to
          // "disconnected" instantly, so the connection appeared to never start.
          //
          // Rule: within a grace window after a connect request, ignore
          // `disconnected` (and `exiting`/`idle`) unless we had already reached
          // `connected`. Real connect stages (connecting/authenticating/
          // connected/error/denied) always pass through.
          if (stage == VPNStage.disconnected ||
              stage == VPNStage.exiting) {
            final reqAt = _connectRequestedAt;
            final inGrace = reqAt != null &&
                DateTime.now().difference(reqAt) <
                    const Duration(seconds: 12);
            if (inGrace && !_sawConnected) {
              if (kDebugMode) {
                debugPrint(
                    '   ↳ ignoring spurious "$stage" during connect grace window');
              }
              return; // do NOT propagate — this is the consent/prepare noise
            }
          }

          if (stage == VPNStage.connected) {
            _sawConnected = true;
            _sawAuthenticating = false;
            _authWatchdog?.cancel();
            _authWatchdog = null;
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
  
  /// Pre-flight check that runs the REAL native ics-openvpn parser
  /// (ConfigParser → convertProfile → checkProfile) and reports whether the
  /// config would be rejected due to a client-certificate problem — the same
  /// situation where the official OpenVPN app pops up a "connect anyway?"
  /// warning. Returns true when a cert-related error is detected.
  static Future<bool> precheckCertIssue(OpenVpnConfig config) async {
    // Try a few times: on the very first call right after app start the native
    // MethodChannel handler can still be wiring up, so a single attempt would
    // silently fail and we'd skip the warning dialog (the user then hit a
    // pointless timeout on the first tap). Retrying makes the check reliable on
    // the FIRST tap, matching the official app.
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
        // Got a definitive OK — no cert issue.
        return false;
      } on MissingPluginException {
        // Handler not registered yet — wait briefly and retry.
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    return false;
  }

  /// Connect to OpenVPN server.
  ///
  /// [forceBypassCert] — when true (the user pressed "connect anyway" after a
  /// certificate warning) every client-cert artifact is stripped from the
  /// config and the core is told the client cert is not required, so it
  /// connects with just username/password — exactly like the official app.
  static Future<bool> connect(
    OpenVpnConfig config, {
    bool forceBypassCert = false,
  }) async {
    final int myGen = ++_generation;
    _userStopped = false;
    // NOTE: do NOT reset `authFailed` here. It is session-sticky and cleared
    // only by beginSession()/disconnect(), so a late auth-failure from the
    // previous attempt isn't wiped by the next retry. See the field docs.
    try {
      // Open the grace window BEFORE initialize(), because initialize() itself
      // queries the engine and emits a `disconnected` default status that must
      // also be swallowed.
      _connectRequestedAt = DateTime.now();
      _sawConnected = false;

      await initialize();

      // If the user cancelled while we were initializing, abort cleanly.
      if (myGen != _generation || _userStopped) {
        if (kDebugMode) debugPrint('🚫 OpenVPN connect $myGen aborted (stale)');
        return false;
      }

      // Parse ONCE (the model caches these) — never in a rebuild path.
      final username = config.effectiveUsername;
      final password = config.effectivePassword;
      final normalizedConfigContent = forceBypassCert
          ? config.configWithoutClientCert
          : config.normalizedConfig;

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
      // ── The decisive change (learning from real ics-openvpn behaviour) ──
      //
      // openvpn_flutter 1.3.4 has this in connect():
      //     if (!certIsRequired) config += "client-cert-not-required";
      // It APPENDS that string to the raw config with NO newline. Worse, that
      // directive is UNKNOWN to ics-openvpn's ConfigParser, so at best it's
      // ignored and at worst it corrupts the final line (e.g. gluing onto the
      // closing tag of an inline <tls-crypt>/<ca> block), which makes the parser
      // build a profile with no enabled connection → checkProfile returns
      // `remote_no_server_selected` → the native side throws and NOTHING
      // connects. That exactly matches "works in the official app, not in ours".
      //
      // The official OpenVPN app feeds the config to the core VERBATIM. The auth
      // type (user/pass vs cert) is derived by the ConfigParser FROM THE CONFIG
      // ITSELF (`auth-user-pass` → user/pass; `<cert>`/`<key>` → cert), NOT from
      // this flag. So the correct, safe behaviour is to ALWAYS pass
      // certIsRequired: true — that is the ONLY value for which the plugin
      // leaves the config completely untouched. We then feed a clean, verbatim
      // config and let the core parse the real auth type. This is the fix.
      _connectRequestedAt = DateTime.now();
      _sawConnected = false;

      // ── Pre-flight: validate the config with the REAL native parser ──
      // This runs ConfigParser.parseConfig → convertProfile → checkProfile
      // exactly like the core does at connect time. If it fails we now SEE the
      // real reason (e.g. remote_no_server_selected, missing_tlsauth, a parse
      // error) instead of the plugin swallowing it. We surface it and abort
      // cleanly rather than firing a connect that will silently do nothing.
      lastError = null;
      try {
        final res = await _nativeChannel.invokeMethod<dynamic>(
          'validateConfig',
          {'config': normalizedConfigContent, 'name': config.name},
        );
        if (res is Map && res['ok'] != true) {
          final err = (res['error'] ?? 'unknown').toString();
          lastError = err;
          if (kDebugMode) {
            debugPrint('❌ OpenVPN config rejected by native parser: $err '
                '(authType=${res['authType']})');
          }
          // Do NOT abort on validation failure alone — some builds return a
          // benign resource-id mismatch. We only LOG it and continue so a
          // genuinely-valid config still connects. But if it is a hard parse
          // error we abort, because that will 100% fail natively.
          if (err.startsWith('parse_error')) {
            if (onStageChanged != null) onStageChanged!(VPNStage.error);
            return false;
          }
        } else if (kDebugMode) {
          debugPrint('✅ OpenVPN config passed native validation');
        }
      } on MissingPluginException {
        // Older build without the native validator — just continue.
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ OpenVPN native validate failed: $e');
      }

      // If the user tapped disconnect during validation, don't start the tunnel.
      if (myGen != _generation || _userStopped) {
        if (kDebugMode) debugPrint('🚫 OpenVPN connect $myGen aborted pre-start');
        try {
          _openvpn.disconnect();
        } catch (_) {}
        return false;
      }

      // AWAIT the native connect so a real parse/checkProfile error surfaces
      // here as an exception instead of becoming a swallowed unhandled async
      // error (which is why failures were previously invisible).
      await _openvpn.connect(
        normalizedConfigContent,
        config.name,
        username: username,
        password: password,
        // When the user chose to connect despite the cert warning we also tell
        // the plugin the client cert is NOT required (appends
        // client-cert-not-required), reinforcing the stripped config.
        certIsRequired: !forceBypassCert,
        bypassPackages: [],
      );

      _connectedConfigName = config.name;

      if (kDebugMode) {
        debugPrint('✅ OpenVPN connect command sent successfully');
      }

      return true;
    } catch (e) {
      // A real native failure (bad config, checkProfile error, etc.) lands here.
      if (kDebugMode) {
        debugPrint('❌ Failed to connect OpenVPN: $e');
      }
      _connectRequestedAt = null;
      if (onStageChanged != null) {
        onStageChanged!(VPNStage.error);
      }
      return false;
    }
  }
  
  /// Disconnect from OpenVPN
  static Future<bool> disconnect() async {
    // Invalidate any in-flight connect attempt so its late callbacks/results
    // are ignored and it stops trying in the background.
    _generation++;
    _userStopped = true;
    authFailed = false;
    _sawAuthenticating = false;
    _authWatchdog?.cancel();
    _authWatchdog = null;
    try {
      if (!_initialized) {
        _connectRequestedAt = null;
        _sawConnected = false;
        return true;
      }
      
      if (kDebugMode) {
        debugPrint('🛑 Disconnecting OpenVPN...');
      }
      
      _openvpn.disconnect();
      _connectedConfigName = null;
      _currentStage = null;
      _connectRequestedAt = null;
      _sawConnected = false;
      
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
