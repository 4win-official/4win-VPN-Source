part of 'vpn_provider.dart';

/// SSTP targets stay isolated from all other protocol selections. Testing is
/// TCP reachability, exactly as in the existing ServerService, not a tunnel test.
extension _SstpProviderLogic on VpnProvider {
  SstpServerGroup? _sstpGroup(String id) {
    for (final group in _sstpGroups) {
      if (group.id == id) return group;
    }
    return null;
  }

  bool get _sstpLocked =>
      isConnected ||
      isConnecting ||
      _status == VpnConnectionStatus.disconnecting;

  void _checkSstpEditable() {
    if (_sstpLocked) {
      throw StateError('Disconnect before changing SSTP servers.');
    }
    if (_sstpGroupTesting || _isLoadingServers) {
      throw StateError('Wait for the SSTP operation to finish.');
    }
  }

  void _syncSstpServers() {
    _servers = _sstpGroups.expand((group) => group.servers).toList();
    if (_sstpGroup(_sstpTargetGroup) == null) {
      _sstpTargetGroup = 'default';
      _sstpManualSelection = false;
      _selectedServer = null;
    }
    final old = _selectedServer;
    if (old != null) {
      final matches = _sstpGroup(_sstpTargetGroup)!.servers.where(
        (server) =>
            server.fullAddress == old.fullAddress &&
            server.username == old.username &&
            server.password == old.password,
      );
      _selectedServer = matches.isEmpty ? null : matches.first;
      if (_selectedServer == null) _sstpManualSelection = false;
    }
  }

  Future<void> _persistSstpSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sstp_selected_group', _sstpTargetGroup);
    if (_sstpManualSelection && _selectedServer != null) {
      await prefs.setString(
        'sstp_selected_server',
        _selectedServer!.fullAddress,
      );
      await prefs.setString(
        'sstp_selected_username',
        _selectedServer!.username,
      );
    } else {
      await prefs.remove('sstp_selected_server');
      await prefs.remove('sstp_selected_username');
    }
  }

  Future<void> _restoreSstpSelection() async {
    if (_sstpSelectionRestored) return;
    final prefs = await SharedPreferences.getInstance();
    _sstpTargetGroup = prefs.getString('sstp_selected_group') ?? 'default';
    final group = _sstpGroup(_sstpTargetGroup);
    if (group == null) _sstpTargetGroup = 'default';
    final address = prefs.getString('sstp_selected_server');
    final username = prefs.getString('sstp_selected_username');
    final matches = _sstpGroup(_sstpTargetGroup)!.servers.where(
      (server) =>
          server.fullAddress == address &&
          (username == null || server.username == username),
    );
    _selectedServer = matches.isEmpty ? null : matches.first;
    _sstpManualSelection = _selectedServer != null;
    _sstpSelectionRestored = true;
    // Obsolete settings cannot secretly override the new target selection.
    for (final key in const [
      'use_custom_server',
      'custom_server',
      'custom_username',
      'custom_password',
    ]) {
      await prefs.remove(key);
    }
    await _persistSstpSelection();
  }

  Future<void> _loadSstpServers({bool forceRefresh = false}) async {
    if (_sstpLoadOperation != null) return _sstpLoadOperation!;
    if (_sstpGroupTesting ||
        (_sstpGroups.isNotEmpty && (!forceRefresh || _sstpLocked))) {
      return;
    }
    final operation = _performSstpLoad(forceRefresh);
    _sstpLoadOperation = operation;
    try {
      await operation;
    } finally {
      _sstpLoadOperation = null;
    }
  }

  Future<void> _performSstpLoad(bool forceRefresh) async {
    _isLoadingServers = true;
    if (!_mixDisposed) notifyListeners();
    try {
      final groups = await _sstpStore.loadGroups(forceRefresh: forceRefresh);
      if (_mixDisposed) return;
      _sstpGroups = groups;
      _syncSstpServers();
      await _restoreSstpSelection();
    } catch (_) {
      if (_selectedProtocol == 'sstp') {
        _errorMessage = 'Could not load SSTP servers. Refresh to try again.';
      }
    } finally {
      _isLoadingServers = false;
      if (!_mixDisposed) notifyListeners();
    }
  }

  Future<void> _refreshSstpGroup(String id) async {
    _checkSstpEditable();
    _isLoadingServers = true;
    notifyListeners();
    try {
      _sstpGroups = await _sstpStore.refreshGroup(id);
      _syncSstpServers();
      await _persistSstpSelection();
    } finally {
      _isLoadingServers = false;
      if (!_mixDisposed) notifyListeners();
    }
  }

  Future<void> _addSstpGroup(
    String name,
    String content, {
    String username = 'vpn',
    String password = 'vpn',
  }) async {
    _checkSstpEditable();
    _isLoadingServers = true;
    notifyListeners();
    try {
      _sstpGroups = await _sstpStore.addGroup(
        name,
        content,
        username: username,
        password: password,
      );
      _syncSstpServers();
    } finally {
      _isLoadingServers = false;
      if (!_mixDisposed) notifyListeners();
    }
  }

  Future<void> _removeSstpGroup(String id) async {
    _checkSstpEditable();
    _isLoadingServers = true;
    notifyListeners();
    try {
      _sstpGroups = await _sstpStore.deleteGroup(id);
      _syncSstpServers();
      await _persistSstpSelection();
    } finally {
      _isLoadingServers = false;
      if (!_mixDisposed) notifyListeners();
    }
  }

  Future<void> _selectSstpGroup(String id) async {
    _checkSstpEditable();
    if (_sstpGroup(id) == null) throw ArgumentError('SSTP group not found.');
    _sstpTargetGroup = id;
    _sstpManualSelection = false;
    _selectedServer = null;
    await _testSstpTarget();
    if (!_mixDisposed) await _persistSstpSelection();
  }

  void _selectSstpServer(VpnServer server) {
    _checkSstpEditable();
    SstpServerGroup? owner;
    for (final group in _sstpGroups) {
      if (group.servers.contains(server)) {
        owner = group;
        break;
      }
    }
    if (owner == null) throw ArgumentError('SSTP server not found.');
    _sstpTargetGroup = owner.id;
    _sstpManualSelection = true;
    _selectedServer = server;
    _errorMessage = null;
    unawaited(_persistSstpSelection());
    notifyListeners();
  }

  Future<List<VpnServer>> _testSstpTarget() async {
    if (_sstpTestOperation != null) return _sstpTestOperation!;
    final operation = _performSstpTest();
    _sstpTestOperation = operation;
    try {
      return await operation;
    } finally {
      _sstpTestOperation = null;
    }
  }

  Future<List<VpnServer>> _performSstpTest() async {
    final group = _sstpGroup(_sstpTargetGroup);
    final targets = _sstpManualSelection
        ? [if (_selectedServer != null) _selectedServer!]
        : List<VpnServer>.of(group?.servers ?? []);
    _sstpGroupTesting = true;
    _sstpTestedCount = 0;
    _sstpTestTotal = targets.length;
    _errorMessage = null;
    for (final server in targets) {
      server.ping = null;
    }
    notifyListeners();
    try {
      final reachable = await _serverService.testServersInParallel(
        targets,
        onProgress: (tested, total) {
          if (_mixDisposed) return;
          _sstpTestedCount = tested;
          _sstpTestTotal = total;
          notifyListeners();
        },
      );
      if (_mixDisposed) return [];
      // Keep unreachable entries in the list so they can be tested again.
      for (final server in targets) {
        final matches = reachable.where(
          (result) =>
              result.fullAddress == server.fullAddress &&
              result.username == server.username &&
              result.password == server.password,
        );
        server.ping = matches.isEmpty ? -1 : matches.first.ping;
      }
      final sorted =
          targets.where((server) => (server.ping ?? -1) >= 0).toList()
            ..sort((a, b) => a.ping!.compareTo(b.ping!));
      if (!_sstpManualSelection) {
        _selectedServer = sorted.isEmpty ? null : sorted.first;
      }
      if (sorted.isEmpty && _selectedProtocol == 'sstp') {
        _errorMessage =
            'No reachable SSTP servers in this target. Refresh or try another group.';
      }
      return sorted;
    } finally {
      _sstpGroupTesting = false;
      if (!_mixDisposed) notifyListeners();
    }
  }

  Future<void> _connectSstp() async {
    final token = ++_sstpConnectGen;
    bool cancelled() =>
        _mixDisposed || token != _sstpConnectGen || _selectedProtocol != 'sstp';
    try {
      if (_sstpGroups.isEmpty || _sstpLoadOperation != null) {
        await loadServers();
      }
      if (cancelled()) return;
      final candidates = await _testSstpTarget();
      if (cancelled()) return;
      if (candidates.isEmpty) {
        _status = VpnConnectionStatus.error;
        _errorMessage ??=
            'No reachable SSTP servers. Refresh or choose another group.';
        notifyListeners();
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      if (cancelled()) return;
      final chosenDns = (prefs.getString('custom_dns') ?? '8.8.8.8').trim();
      final dnsCandidates = (prefs.getBool('deep_scan') ?? false)
          ? _deepScanDnsList()
          : [chosenDns.isEmpty ? '8.8.8.8' : chosenDns];
      var mtuMode = prefs.getString('mtu_mode') ?? 'off';
      var manualMtu = (prefs.getInt('manual_mtu') ?? 1400).clamp(1280, 1500);
      if ((prefs.getBool('sstp_fragment') ?? false) && mtuMode == 'off') {
        final size = prefs.getString('sstp_fragment_size') ?? '1-3';
        final first = int.tryParse(size.split('-').first.trim()) ?? 1;
        manualMtu = (1280 + (first.clamp(1, 6) - 1) * 20).clamp(1280, 1500);
        mtuMode = 'manual';
      }
      final granted = await _vpnService.requestPermission();
      if (cancelled()) return;
      if (!granted) {
        _status = VpnConnectionStatus.error;
        _errorMessage = 'VPN permission denied';
        notifyListeners();
        return;
      }
      for (final server in candidates) {
        _selectedServer = server;
        notifyListeners();
        for (final dns in dnsCandidates) {
          if (cancelled()) return;
          final operation = _vpnService.connect(
            server,
            dns: dns,
            mtuMode: mtuMode,
            manualMtu: manualMtu,
          );
          _sstpNativeOperation = operation;
          bool success;
          try {
            success = await operation;
          } finally {
            if (identical(_sstpNativeOperation, operation)) {
              _sstpNativeOperation = null;
            }
          }
          // disconnect() waits for native startup before stopping the tunnel.
          if (cancelled()) return;
          if (success) return;
        }
      }
      _status = VpnConnectionStatus.error;
      _errorMessage =
          'Failed to connect to SSTP servers. Select another target or retry.';
      notifyListeners();
    } catch (_) {
      if (cancelled()) return;
      _status = VpnConnectionStatus.error;
      _errorMessage = 'SSTP connection failed. Select another target or retry.';
      notifyListeners();
    }
  }
}
