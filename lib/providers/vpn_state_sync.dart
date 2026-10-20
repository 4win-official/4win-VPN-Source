part of 'vpn_provider.dart';

extension _VpnStateSync on VpnProvider {
  bool _matchesNativeProtocol(String protocol) =>
      protocol == _selectedProtocol ||
      (protocol == 'xray' &&
          const {'xray', 'proxy', 'warp', 'mix'}.contains(_selectedProtocol));

  Future<void> _onNativeVpnState(MethodCall call) async {
    if (_mixDisposed || call.method != 'onDisconnected') return;
    final arguments = call.arguments;
    if (arguments is! Map || arguments['protocol'] is! String) return;
    if (!_matchesNativeProtocol(arguments['protocol'] as String)) return;
    if (_status == VpnConnectionStatus.disconnected) {
      // Invalidate a pending startup snapshot too: a notification stop can
      // arrive before the recreated UI has adopted the running service.
      _vpnStateRevision++;
      return;
    }
    if (_status == VpnConnectionStatus.disconnecting) return;
    // Use the manual stop path too: updating the label alone leaves Dart
    // retry loops and OpenVPN's health recovery able to restart the tunnel.
    await disconnect();
  }

  Future<void> _refreshNativeVpnState() async {
    if (_mixDisposed ||
        _status == VpnConnectionStatus.disconnecting ||
        (_status == VpnConnectionStatus.connecting &&
            !_nativeSessionRestored)) {
      return;
    }
    final protocol = _selectedProtocol;
    final revision = _vpnStateRevision;
    final status = _status;
    try {
      final state = await VpnProvider._vpnStateChannel
          .invokeMapMethod<String, dynamic>('getState', {'protocol': protocol});
      if (_mixDisposed ||
          revision != _vpnStateRevision ||
          protocol != _selectedProtocol ||
          status != _status ||
          state == null) {
        return;
      }
      // A fresh Dart provider starts disconnected even when Android still
      // owns a tunnel. Adopt only an explicit native snapshot, never a saved
      // UI flag; a running kill-switch/connecting service is not connected.
      if (status == VpnConnectionStatus.disconnected ||
          _nativeSessionRestored) {
        final connected = state['connected'] == true;
        final active =
            state['running'] == true || state['reconnecting'] == true;
        if (active && state['connected'] is bool) {
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
            // Do NOT attach recovery monitors: those can start/reconnect a
            // VPN. Native services retain ownership; this timer only reads.
            _nativeStateTimer ??= Timer.periodic(const Duration(seconds: 2), (
              _,
            ) {
              unawaited(_refreshNativeVpnState());
            });
            notifyListeners();
          }
          return;
        }
      }
      // Missing/failed status reads are not proof of a stop. A reconnect or
      // kill-switch service still owns the session and must not be torn down.
      if (state['running'] == false && state['reconnecting'] == false) {
        if (status == VpnConnectionStatus.disconnected) return;
        // A failed SSTP/Psiphon startup normally stops its native service. That
        // must not erase the persisted cause on resume. An explicit native
        // onDisconnected event still follows the manual stop path above.
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
