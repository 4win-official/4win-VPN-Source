part of 'vpn_provider.dart';

extension _VpnStateSync on VpnProvider {
  bool _matchesNativeProtocol(String protocol) =>
      protocol == _selectedProtocol ||
      (protocol == 'xray' &&
          const {'xray', 'proxy', 'warp', 'mix'}.contains(_selectedProtocol));

  void _ensureNativeStatePolling() {
    // Read-only for both locally started and restored sessions. Native services
    // keep ownership of reconnects, counters and the monotonic session clock.
    _nativeStateTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshNativeVpnState(metricsOnly: !_nativeSessionRestored));
    });
  }

  void _clearNativeSessionMetrics() {
    _nativeMetricsSessionId = null;
    _nativeElapsed = null;
    _nativeElapsedClock.stop();
    _nativeElapsedClock.reset();
    _nativeTrafficAuthoritative = false;
  }

  void _applyNativeSessionMetrics(Map<String, dynamic> state) {
    final id = state['sessionId'];
    if (id is! String || id.isEmpty) return;
    if (id != _nativeMetricsSessionId) {
      _clearNativeSessionMetrics();
      _nativeMetricsSessionId = id;
      _connectionDuration = Duration.zero;
      _totalDownloadBytes = 0;
      _totalUploadBytes = 0;
      _lastDownloadBytes = 0;
      _lastUploadBytes = 0;
    }
    final elapsed = state['elapsedMillis'];
    if (elapsed is num && elapsed.isFinite && elapsed >= 0) {
      _nativeElapsed = Duration(milliseconds: elapsed.toInt());
      _connectionDuration = _nativeElapsed!;
      _nativeElapsedClock.reset();
      _nativeElapsedClock.start();
    }
    final up = state['uplink'];
    final down = state['downlink'];
    if (up is num &&
        down is num &&
        up.isFinite &&
        down.isFinite &&
        up >= 0 &&
        down >= 0) {
      _nativeTrafficAuthoritative = true;
      _totalUploadBytes = up.toInt();
      _totalDownloadBytes = down.toInt();
    }
    // Missing counters are unknown, not zero. Keep the last valid measurement
    // for this session; never substitute whole-device traffic for VPN traffic.
  }

  Future<void> _onNativeVpnState(MethodCall call) async {
    if (_mixDisposed || call.method != 'onDisconnected') return;
    final arguments = call.arguments;
    if (arguments is! Map || arguments['protocol'] is! String) return;
    if (!_matchesNativeProtocol(arguments['protocol'] as String)) return;
    if (_status == VpnConnectionStatus.disconnected) {
      _vpnStateRevision++;
      _clearNativeSessionMetrics();
      return;
    }
    if (_status == VpnConnectionStatus.disconnecting) return;
    // Also cancel retry loops: merely changing the label could restart a VPN.
    await disconnect();
  }

  Future<void> _refreshNativeVpnState({bool metricsOnly = false}) async {
    if (_mixDisposed ||
        _status == VpnConnectionStatus.disconnecting ||
        (_status == VpnConnectionStatus.connecting &&
            !_nativeSessionRestored)) {
      return;
    }
    final protocol = _selectedProtocol;
    final revision = _vpnStateRevision;
    final status = _status;
    final read = ++_nativeStateRead;
    try {
      final state = await VpnProvider._vpnStateChannel
          .invokeMapMethod<String, dynamic>('getState', {'protocol': protocol});
      if (_mixDisposed ||
          revision != _vpnStateRevision ||
          read != _nativeStateRead ||
          protocol != _selectedProtocol ||
          status != _status ||
          state == null) {
        return;
      }
      final connected = state['connected'] == true;
      final active = state['running'] == true || state['reconnecting'] == true;
      if (active && state['connected'] is bool) {
        _applyNativeSessionMetrics(state);
        // A fresh provider may adopt an explicitly live native session. Local
        // connect/recovery flows retain their own state transitions.
        if (status == VpnConnectionStatus.disconnected ||
            _nativeSessionRestored) {
          final next = connected
              ? VpnConnectionStatus.connected
              : VpnConnectionStatus.connecting;
          if (!_nativeSessionRestored || next != _status) {
            _nativeSessionRestored = true;
            _status = next;
            _errorMessage = null;
            if (connected) {
              _startDurationTimer();
              if (const {'xray', 'proxy', 'warp', 'mix'}.contains(protocol)) {
                _startXrayTraffic();
              } else if (protocol == 'psiphon') {
                _startPsiphonTraffic();
              }
            } else {
              _stopDurationTimer();
              _stopXrayTraffic();
              _stopPsiphonTraffic();
            }
          }
          // Never attach recovery monitors when restoring a service.
          _ensureNativeStatePolling();
        }
        notifyListeners();
        return;
      }
      // A missing/failed read is not proof of a stop. A running blackhole or
      // reconnecting service must not be torn down.
      // Local connection/recovery paths already own state transitions. A
      // metrics timer must not stop a just-connected service on a stale read.
      if (metricsOnly) return;
      if (state['running'] == false && state['reconnecting'] == false) {
        if (status == VpnConnectionStatus.disconnected) return;
        if ((protocol == 'psiphon' || protocol == 'sstp') &&
            status == VpnConnectionStatus.error) {
          return;
        }
        await disconnect();
      }
    } on MissingPluginException {
      // Compatibility with platforms/builds without the native state bridge.
    } on PlatformException {
      // Leave the last known state intact when the native query fails.
    }
  }
}
