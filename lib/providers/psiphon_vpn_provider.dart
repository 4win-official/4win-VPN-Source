import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/psiphon_service.dart';
import 'vpn_provider.dart';

/// VpnProvider extension that gives Psiphon a real first-class connection path
/// without disturbing the existing protocol implementations.
class PsiphonVpnProvider extends VpnProvider {
  final PsiphonService _psiphon = PsiphonService();
  Timer? _psiphonMonitor;
  VpnConnectionStatus _psiphonStatus = VpnConnectionStatus.disconnected;
  Duration _psiphonDuration = Duration.zero;
  Timer? _psiphonDurationTimer;
  DateTime? _psiphonConnectedAt;

  PsiphonVpnProvider() {
    // Existing users keep their saved protocol. Fresh installs get Psiphon as
    // the default after the base provider has restored persisted state.
    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      try {
        final saved = selectedProtocol;
        if (saved == 'xray') {
          await switchProtocol('psiphon');
        }
      } catch (_) {}
    });
  }

  bool get _isPsiphon => selectedProtocol == 'psiphon';

  @override
  VpnConnectionStatus get status => _isPsiphon ? _psiphonStatus : super.status;

  @override
  bool get isConnected => _isPsiphon
      ? _psiphonStatus == VpnConnectionStatus.connected
      : super.isConnected;

  @override
  bool get isConnecting => _isPsiphon
      ? _psiphonStatus == VpnConnectionStatus.connecting
      : super.isConnecting;

  @override
  Duration get connectionDuration =>
      _isPsiphon ? _psiphonDuration : super.connectionDuration;

  @override
  Future<void> switchProtocol(String protocol) async {
    if (protocol != 'psiphon' && _isPsiphon) {
      await _stopPsiphon();
    }
    await super.switchProtocol(protocol);
    if (protocol == 'psiphon') {
      _psiphonStatus = VpnConnectionStatus.disconnected;
      _psiphonDuration = Duration.zero;
      notifyListeners();
    }
  }

  @override
  Future<void> connect({bool forceBypassCert = false}) async {
    if (!_isPsiphon) {
      await super.connect(forceBypassCert: forceBypassCert);
      return;
    }
    if (_psiphonStatus == VpnConnectionStatus.connecting ||
        _psiphonStatus == VpnConnectionStatus.connected) return;

    _psiphonStatus = VpnConnectionStatus.connecting;
    notifyListeners();
    try {
      final ok = await _psiphon.start();
      if (!ok) {
        _psiphonStatus = VpnConnectionStatus.error;
        notifyListeners();
        return;
      }
      _startPsiphonMonitor();
    } catch (e) {
      if (kDebugMode) debugPrint('Psiphon start failed: $e');
      _psiphonStatus = VpnConnectionStatus.error;
      notifyListeners();
    }
  }

  void _startPsiphonMonitor() {
    _psiphonMonitor?.cancel();
    _psiphonMonitor = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isPsiphon) return;
      try {
        final connected = await _psiphon.isConnected;
        final running = await _psiphon.isRunning;
        if (connected) {
          if (_psiphonStatus != VpnConnectionStatus.connected) {
            _psiphonStatus = VpnConnectionStatus.connected;
            _psiphonConnectedAt ??= DateTime.now();
            _startDuration();
            notifyListeners();
          }
        } else if (!running) {
          if (_psiphonStatus != VpnConnectionStatus.disconnected) {
            _psiphonStatus = VpnConnectionStatus.disconnected;
            _stopDuration();
            notifyListeners();
          }
        } else if (_psiphonStatus != VpnConnectionStatus.connecting) {
          _psiphonStatus = VpnConnectionStatus.connecting;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void _startDuration() {
    _psiphonDurationTimer?.cancel();
    _psiphonDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final started = _psiphonConnectedAt;
      if (started == null) return;
      _psiphonDuration = DateTime.now().difference(started);
      notifyListeners();
    });
  }

  void _stopDuration() {
    _psiphonDurationTimer?.cancel();
    _psiphonDurationTimer = null;
    _psiphonConnectedAt = null;
    _psiphonDuration = Duration.zero;
  }

  Future<void> _stopPsiphon() async {
    _psiphonMonitor?.cancel();
    _psiphonMonitor = null;
    _stopDuration();
    try {
      await _psiphon.stop();
    } catch (_) {}
    _psiphonStatus = VpnConnectionStatus.disconnected;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    if (!_isPsiphon) {
      await super.disconnect();
      return;
    }
    _psiphonStatus = VpnConnectionStatus.disconnecting;
    notifyListeners();
    await _stopPsiphon();
  }

  @override
  void dispose() {
    _psiphonMonitor?.cancel();
    _psiphonDurationTimer?.cancel();
    super.dispose();
  }
}
