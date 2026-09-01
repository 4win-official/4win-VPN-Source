import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/psiphon_manager.dart';

class PsiphonProvider extends ChangeNotifier {
  bool _isRunning = false;
  bool _isConnected = false;
  String _selectedRegion = '';
  int _uplinkBytes = 0;
  int _downlinkBytes = 0;
  String _connectionStatus = 'Disconnected';
  String? _error;
  DateTime? _connectedAt;
  bool _isLoading = false;

  // Getters
  bool get isRunning => _isRunning;
  bool get isConnected => _isConnected;
  String get selectedRegion => _selectedRegion;
  int get uplinkBytes => _uplinkBytes;
  int get downlinkBytes => _downlinkBytes;
  String get connectionStatus => _connectionStatus;
  String? get error => _error;
  DateTime? get connectedAt => _connectedAt;
  bool get isLoading => _isLoading;

  // Formatted getters
  String get formattedUplink => PsiphonVpnManager.formatBytes(_uplinkBytes);
  String get formattedDownlink => PsiphonVpnManager.formatBytes(_downlinkBytes);
  String get formattedUploadSpeed {
    if (_connectedAt == null) return '0 B/s';
    final seconds =
        DateTime.now().difference(_connectedAt!).inSeconds.toDouble();
    if (seconds <= 0) return '0 B/s';
    final speed = _uplinkBytes / seconds;
    return '${PsiphonVpnManager.formatBytes(speed.toInt())}/s';
  }

  String get formattedDownloadSpeed {
    if (_connectedAt == null) return '0 B/s';
    final seconds =
        DateTime.now().difference(_connectedAt!).inSeconds.toDouble();
    if (seconds <= 0) return '0 B/s';
    final speed = _downlinkBytes / seconds;
    return '${PsiphonVpnManager.formatBytes(speed.toInt())}/s';
  }

  String get formattedConnectionTime {
    if (_connectedAt == null) return '0s';
    final duration = DateTime.now().difference(_connectedAt!);
    return PsiphonVpnManager.formatTime(duration.inMilliseconds);
  }

  List<String> get availableRegions => [
        'Auto',
        'US',
        'CA',
        'DE',
        'FR',
        'JP',
        'AU',
        'BR',
        'IN',
      ];

  PsiphonProvider() {
    _initializeConnection();
  }

  Future<void> _initializeConnection() async {
    _isRunning = await PsiphonVpnManager.isPsiphonRunning();
    _isConnected = await PsiphonVpnManager.isPsiphonConnected();
    if (_isConnected) {
      _connectedAt = DateTime.now();
      _connectionStatus = 'Connected';
    }
    notifyListeners();
    _startStatsPolling();
  }

  Future<void> startConnection(String region) async {
    _error = null;
    _isLoading = true;
    _connectionStatus = 'Preparing...';
    notifyListeners();

    try {
      // First prepare (request permission)
      final prepared = await PsiphonVpnManager.preparePsiphon();
      if (!prepared) {
        _connectionStatus = 'Permission pending...';
        notifyListeners();
        await Future.delayed(const Duration(seconds: 2));
      }

      // Start connection
      _connectionStatus = 'Connecting to Psiphon...';
      notifyListeners();

      final success = await PsiphonVpnManager.startPsiphon(
        egressRegion: region.toLowerCase() == 'auto' ? '' : region,
      );

      if (success) {
        _selectedRegion = region;
        _isRunning = true;
        _connectionStatus = 'Connecting...';
        _uplinkBytes = 0;
        _downlinkBytes = 0;
        _connectedAt = DateTime.now();
        await Future.delayed(const Duration(seconds: 2));
        _isConnected = true;
        _connectionStatus = 'Connected to $region';
      } else {
        _error = 'Failed to start Psiphon';
        _connectionStatus = 'Failed';
        _isRunning = false;
        _isConnected = false;
      }
    } catch (e) {
      _error = e.toString();
      _connectionStatus = 'Error';
      _isRunning = false;
      _isConnected = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> stopConnection() async {
    _error = null;
    _isLoading = true;
    _connectionStatus = 'Disconnecting...';
    notifyListeners();

    try {
      final success = await PsiphonVpnManager.stopPsiphon();
      if (success) {
        _isRunning = false;
        _isConnected = false;
        _connectionStatus = 'Disconnected';
        _connectedAt = null;
        _uplinkBytes = 0;
        _downlinkBytes = 0;
      } else {
        _error = 'Failed to stop Psiphon';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> reconnectConnection(String region) async {
    _error = null;
    _isLoading = true;
    _connectionStatus = 'Reconnecting...';
    notifyListeners();

    try {
      final success = await PsiphonVpnManager.reconnectPsiphon(
        egressRegion: region.toLowerCase() == 'auto' ? '' : region,
      );
      if (success) {
        _selectedRegion = region;
        _connectedAt = DateTime.now();
        _uplinkBytes = 0;
        _downlinkBytes = 0;
        await Future.delayed(const Duration(seconds: 2));
        _isConnected = true;
        _connectionStatus = 'Connected to $region';
      } else {
        _error = 'Failed to reconnect';
        _connectionStatus = 'Failed';
      }
    } catch (e) {
      _error = e.toString();
      _connectionStatus = 'Error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _startStatsPolling() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_isConnected) {
        try {
          final stats = await PsiphonVpnManager.queryTrafficStats();
          _uplinkBytes = stats['uplink'] ?? 0;
          _downlinkBytes = stats['downlink'] ?? 0;
          notifyListeners();
        } catch (e) {
          print('Error polling stats: $e');
        }
      }
      return _isConnected;
    });
  }
}
