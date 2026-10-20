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
    if (_mixDiagnostics?.strategyId == strategy.id) _mixDiagnostics = null;
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
    if (_mixDiagnostics?.strategyId == id) _mixDiagnostics = null;
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
    _mixDiagnostics = null;
    if (!_mixDisposed) notifyListeners();
  }

  Future<void> _readMixDiagnostics(int generation) async {
    final snapshot = await XrayConnection.getMixDiagnostics();
    if (_mixDisposed ||
        generation != _mixConnectGen ||
        _selectedProtocol != 'mix' ||
        snapshot == null) {
      return;
    }
    final current = _mixDiagnostics;
    if (current == null ||
        const {
          'Chain failed',
          'Chain stopped',
          'Connection cancelled',
          'Disconnected',
        }.contains(current.phase)) {
      return;
    }
    final next = current.applyNative(snapshot);
    if (!identical(current, next)) {
      _mixDiagnostics = next;
      notifyListeners();
    }
  }

  void _setMixDiagnosticPhase(String phase, {bool unverified = false}) {
    final current = _mixDiagnostics;
    if (current == null) return;
    _mixDiagnostics = current.update(
      phase: phase,
      states: unverified
          ? List.filled(current.hops.length, MixBlockState.unverified)
          : null,
    );
    if (!_mixDisposed) notifyListeners();
  }

  Future<void> _connectMix() async {
    final generation = ++_mixConnectGen;
    _mixDiagnosticsTimer?.cancel();
    _mixDiagnostics = null;
    bool cancelled() =>
        _mixDisposed ||
        generation != _mixConnectGen ||
        _selectedProtocol != 'mix' ||
        _status != VpnConnectionStatus.connecting;
    var started = false;
    var nativeDiagnostics = false;
    try {
      await _mixLoaded;
      if (cancelled()) return;
      final strategy = selectedMixStrategy;
      if (strategy == null) {
        throw StateError('Open Strategy and select a Mix strategy first.');
      }
      _mixDiagnostics = MixDiagnostics.begin(
        strategy,
        '${DateTime.now().microsecondsSinceEpoch}-$generation',
      );
      notifyListeners();
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
      final usesNativeChain =
          strategy.udpRelay != null ||
          strategy.hops.any(
            (hop) =>
                const {
                  'warp',
                  'sstp',
                  'openvpn',
                  'psiphon',
                }.contains(hop.protocol) ||
                (hop.protocol == 'proxy' &&
                    proxies.any(
                      (proxy) =>
                          proxy.protocol == 'socks4' &&
                          (proxy.id == hop.serverId ||
                              ((hop.group?.isNotEmpty ?? false) &&
                                  proxy.group == hop.group)),
                    )),
          );
      int delay;
      if (usesNativeChain) {
        // Keep the picker's loaded groups and latency results. Loading an
        // unloaded catalog is enough; connecting must not replace selections.
        await loadServers();
        final plan = MixPlanBuilder.build(
          strategy: strategy,
          xrayServers: xray,
          proxyServers: proxies,
          sstpServers: List<VpnServer>.of(_servers),
          sstpGroups: List<SstpServerGroup>.of(_sstpGroups),
          openVpnConfigs: await _openVpnService.loadConfigs(),
          dnsServers: dns,
          warpAccount: await _warpService.getAccount(),
        );
        if (cancelled()) return;
        plan['diagnosticsAttemptId'] = _mixDiagnostics!.attemptId;
        nativeDiagnostics = true;
        _setMixDiagnosticPhase('Starting native chain', unverified: true);
        var reading = false;
        _mixDiagnosticsTimer = Timer.periodic(
          const Duration(milliseconds: 300),
          (_) async {
            if (reading) return;
            reading = true;
            try {
              await _readMixDiagnostics(generation);
            } finally {
              reading = false;
            }
          },
        );
        started = true;
        delay = await XrayConnection.connectMixPlan(plan);
        await _readMixDiagnostics(generation);
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
        _setMixDiagnosticPhase(
          'Testing complete chain — individual blocks not observable',
          unverified: true,
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
      _setMixDiagnosticPhase('Connected — complete-chain test passed');
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
        // MixCoordinatorService can briefly report !isRunning while it tears
        // down and starts the next request. Do not turn that into an error.
        if (await XrayConnection.isReconnecting()) {
          checking = false;
          return;
        }
        final alive = await XrayConnection.isRunning();
        checking = false;
        if (_mixDisposed ||
            generation != _mixConnectGen ||
            _selectedProtocol != 'mix') {
          return;
        }
        if (!alive) {
          // Reconnect may have started while isRunning was in flight.
          if (await XrayConnection.isReconnecting()) return;
          if (_mixDisposed ||
              generation != _mixConnectGen ||
              _selectedProtocol != 'mix' ||
              !isConnected) {
            return;
          }
          await _readMixDiagnostics(generation);
          _mixDiagnosticsTimer?.cancel();
          final diagnostics = _mixDiagnostics;
          await disconnect();
          _mixDiagnostics = diagnostics?.update(
            phase: 'Chain stopped',
            message:
                'The tunnel stopped. A failing block may not be identifiable.',
          );
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
      _mixDiagnosticsTimer?.cancel();
      if (nativeDiagnostics) await _readMixDiagnostics(generation);
      if (cancelled()) return;
      final diagnostic = _mixDiagnostics;
      if (diagnostic != null) {
        final states = List<MixBlockState>.of(diagnostic.states);
        if (error is MixBlockException &&
            error.index >= 0 &&
            error.index < states.length) {
          states[error.index] = MixBlockState.failed;
        }
        _mixDiagnostics = diagnostic.update(
          phase: 'Chain failed',
          states: states,
          message: states.contains(MixBlockState.failed)
              ? 'The highlighted block reported an error. Initialized blocks are not proof of remote reachability.'
              : 'The failing block could not be identified reliably. No block was bypassed.',
        );
      }
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

  Future<void> _disconnectMix({bool wasConnecting = false}) async {
    _mixDiagnosticsTimer?.cancel();
    final diagnostic = _mixDiagnostics;
    if (diagnostic != null && diagnostic.phase != 'Chain failed') {
      _mixDiagnostics = diagnostic.update(
        phase: wasConnecting ? 'Connection cancelled' : 'Disconnected',
        states: diagnostic.states
            .map(
              (state) => state == MixBlockState.starting
                  ? MixBlockState.unverified
                  : state,
            )
            .toList(),
        message: 'Showing the last observed attempt, not a live tunnel.',
      );
    }
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
