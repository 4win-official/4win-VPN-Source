part of 'vpn_provider.dart';

/// All Mix behavior is kept in this library part. No standalone selection,
/// account, connection settings or profile is modified by the strategy editor.
extension _MixProviderLogic on VpnProvider {
  MixStrategy? get _selectedMixStrategy {
    for (final strategy in _mixStrategies) {
      if (strategy.id == _selectedMixStrategyId) return strategy;
    }
    return null;
  }

  Future<void> _loadMixStrategies() async {
    try {
      _mixStrategies = await _mixStore.load();
      final id = await _mixStore.selectedId();
      _selectedMixStrategyId = _mixStrategies.any((item) => item.id == id)
          ? id
          : null;
      if (!_mixDisposed) notifyListeners();
    } catch (_) {
      // Mix storage must never prevent another protocol from starting.
    }
  }

  Future<void> _saveMixStrategy(MixStrategy strategy) async {
    await _mixLoaded;
    final error = strategy.validationError;
    if (error != null) throw FormatException(error);
    if (_selectedProtocol == 'mix' &&
        (isConnecting || isConnected) &&
        strategy.id == _selectedMixStrategyId) {
      throw StateError('Disconnect Mix before editing the active strategy.');
    }
    final updated = [
      ..._mixStrategies.where((item) => item.id != strategy.id),
      strategy,
    ];
    await _mixStore.save(updated);
    _mixStrategies = updated;
    if (_selectedMixStrategyId == null) {
      await _mixStore.select(strategy.id);
      _selectedMixStrategyId = strategy.id;
    }
    if (!_mixDisposed) notifyListeners();
  }

  Future<void> _deleteMixStrategy(String id) async {
    await _mixLoaded;
    if (_selectedProtocol == 'mix' &&
        _selectedMixStrategyId == id &&
        (isConnecting || isConnected)) {
      await disconnect();
    }
    final updated = _mixStrategies
        .where((strategy) => strategy.id != id)
        .toList();
    await _mixStore.save(updated);
    _mixStrategies = updated;
    if (_selectedMixStrategyId == id) {
      await _mixStore.select(null);
      _selectedMixStrategyId = null;
    }
    if (!_mixDisposed) notifyListeners();
  }

  Future<void> _selectMixStrategy(String id) async {
    await _mixLoaded;
    if (!_mixStrategies.any((strategy) => strategy.id == id)) {
      throw StateError('Strategy not found.');
    }
    if (id == _selectedMixStrategyId) return;
    if (_selectedProtocol == 'mix' && (isConnecting || isConnected)) {
      await disconnect();
    }
    await _mixStore.select(id);
    _selectedMixStrategyId = id;
    if (!_mixDisposed) notifyListeners();
  }

  Future<void> _connectMix() async {
    final generation = ++_mixConnectGen;
    bool cancelled() =>
        _mixDisposed ||
        generation != _mixConnectGen ||
        _selectedProtocol != 'mix' ||
        _status != VpnConnectionStatus.connecting;
    var started = false;
    try {
      await _mixLoaded;
      if (cancelled()) return;
      final strategy = selectedMixStrategy;
      if (strategy == null) {
        throw StateError('Open Strategy and select a Mix strategy first.');
      }
      final validation = strategy.validationError;
      if (validation != null) throw FormatException(validation);
      final prefs = await SharedPreferences.getInstance();
      if (cancelled()) return;
      // Mix is explicitly system-wide. Do not silently change the user's
      // global proxy-only preference or apply it to a supposedly full tunnel.
      if ((prefs.getString('connection_mode') ?? 'vpn') == 'proxy') {
        throw StateError(
          'Mix requires VPN mode. Change Connection mode in Settings.',
        );
      }
      final granted = await XrayConnection.requestPermission();
      if (cancelled()) return;
      if (!granted) {
        throw StateError('Grant VPN permission, then tap Connect again.');
      }
      final xray = await _xrayService.loadServers();
      final proxies = await _proxyService.loadServers();
      final dns = await _dnsService.getAllDnsServers();
      if (cancelled()) return;
      final usesNativeChain = strategy.hops.any(
        (hop) =>
            const {'warp', 'sstp', 'openvpn', 'psiphon'}.contains(hop.protocol),
      );
      int delay;
      if (usesNativeChain) {
        await loadServers(forceRefresh: true);
        final plan = MixPlanBuilder.build(
          strategy: strategy,
          xrayServers: xray,
          proxyServers: proxies,
          sstpServers: List<VpnServer>.of(_servers),
          openVpnConfigs: await _openVpnService.loadConfigs(),
          dnsServers: dns,
          warpAccount: await _warpService.getAccount(),
        );
        if (cancelled()) return;
        started = true;
        delay = await XrayConnection.connectMixPlan(plan);
        if (cancelled()) return;
        if (delay < 0) throw StateError('Could not start Mix.');
      } else {
        final config = MixConfigBuilder.build(
          strategy: strategy,
          xrayServers: xray,
          proxyServers: proxies,
          dnsServers: dns,
        );
        final probeConfig = MixConfigBuilder.build(
          strategy: strategy,
          xrayServers: xray,
          proxyServers: proxies,
          dnsServers: dns,
          delayTest: true,
        );
        ConnectionLogger.instance.info(
          'mix',
          'Testing complete chain (${strategy.hops.length} blocks)',
        );
        delay = await XrayConnection.measureDelay(
          probeConfig,
        ).timeout(const Duration(seconds: 20), onTimeout: () => -1);
        if (cancelled()) return;
        if (delay < 0) {
          throw StateError(
            'The complete chain failed its connection test. No tunnel was started.',
          );
        }
        started = true;
        final accepted = await XrayConnection.connectMix(config);
        if (cancelled()) return;
        if (!accepted) throw StateError('Could not start Mix.');
      }
      var running = false;
      for (var attempt = 0; attempt < 32; attempt++) {
        if (cancelled()) return;
        running = await XrayConnection.isRunning();
        if (running) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (cancelled()) return;
      if (!running) throw StateError('Mix core did not become ready.');
      _status = VpnConnectionStatus.connected;
      _connectedServer = null;
      _errorMessage = null;
      _currentPing = delay;
      _connectionDuration = Duration.zero;
      _startDurationTimer();
      _startXrayTraffic();
      ConnectionLogger.instance.info(
        'mix',
        'Chain running; end-to-end preflight: ${delay}ms',
      );
      _mixMonitor?.cancel();
      var checking = false;
      _mixMonitor = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (checking ||
            _mixDisposed ||
            generation != _mixConnectGen ||
            _selectedProtocol != 'mix' ||
            !isConnected) {
          return;
        }
        checking = true;
        final alive = await XrayConnection.isRunning();
        checking = false;
        if (_mixDisposed ||
            generation != _mixConnectGen ||
            _selectedProtocol != 'mix') {
          return;
        }
        if (!alive) {
          await disconnect();
          if (_mixDisposed || _selectedProtocol != 'mix') return;
          _status = VpnConnectionStatus.error;
          _errorMessage =
              'Mix tunnel stopped. Reconnect to retry the entire chain.';
          notifyListeners();
        }
      });
      notifyListeners();
    } catch (error) {
      if (cancelled()) return;
      if (started) {
        await XrayConnection.disconnectMixPlan();
        await XrayConnection.disconnect();
        started = false;
      }
      if (cancelled()) return;
      _status = VpnConnectionStatus.error;
      _errorMessage = error.toString().replaceFirst(
        RegExp(r'^(Bad state: |FormatException: )'),
        '',
      );
      ConnectionLogger.instance.error('mix', _errorMessage!);
      notifyListeners();
    } finally {
      // A late completion after cancellation must not resurrect the tunnel.
      // disconnect() drains this operation before another protocol may start.
      if (started && (generation != _mixConnectGen || _mixDisposed)) {
        await XrayConnection.disconnectMixPlan();
        await XrayConnection.disconnect();
      }
    }
  }

  Future<void> _disconnectMix() async {
    _mixMonitor?.cancel();
    _mixMonitor = null;
    await XrayConnection.disconnectMixPlan();
    final operation = _mixOperation;
    if (operation != null) await operation;
    await XrayConnection.disconnect();
    _stopDurationTimer();
    _stopPingTimer();
    _stopXrayTraffic();
    _connectionDuration = Duration.zero;
    _currentPing = null;
    _totalDownloadBytes = 0;
    _totalUploadBytes = 0;
  }
}
