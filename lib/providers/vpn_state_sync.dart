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
    if (_status == VpnConnectionStatus.disconnected ||
        _status == VpnConnectionStatus.disconnecting) {
      return;
    }
    // Use the manual stop path too: updating the label alone leaves Dart
    // retry loops and OpenVPN's health recovery able to restart the tunnel.
    await disconnect();
  }

  Future<void> _refreshNativeVpnState() async {
    if (_mixDisposed ||
        (_status != VpnConnectionStatus.connected &&
            _status != VpnConnectionStatus.error)) {
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
      // Missing/failed status reads are not proof of a stop. A reconnect or
      // kill-switch service still owns the session and must not be torn down.
      if (state['running'] == false && state['reconnecting'] == false) {
        // A failed Psiphon startup normally stops its native service. That
        // must not erase the persisted cause on resume. An explicit native
        // onDisconnected event still follows the manual stop path above.
        if (protocol == 'psiphon' && status == VpnConnectionStatus.error) {
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
