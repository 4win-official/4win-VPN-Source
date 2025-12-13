import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/vpn_server.dart';
import '../services/server_service.dart';
import '../services/vpn_service.dart';

// Re-export for convenience
export '../services/vpn_service.dart' show VpnConnectionStatus;

class VpnProvider with ChangeNotifier {
  final ServerService _serverService = ServerService();
  final VpnService _vpnService = VpnService();
  
  // Expose VPN service for log access
  VpnService get vpnService => _vpnService;

  List<VpnServer> _servers = [];
  VpnServer? _selectedServer;
  VpnServer? _connectedServer;
  VpnConnectionStatus _status = VpnConnectionStatus.disconnected;
  bool _isLoadingServers = false;
  String? _errorMessage;
  StreamSubscription<VpnConnectionStatus>? _statusSubscription;
  Timer? _durationTimer;
  Duration _connectionDuration = Duration.zero;

  // Data usage tracking (cumulative total - not rate)
  int _totalDownloadBytes = 0;
  int _totalUploadBytes = 0;
  int _lastDownloadBytes = 0;
  int _lastUploadBytes = 0;
  
  // Ping tracking
  int? _currentPing;
  Timer? _pingTimer;

  // Getters
  List<VpnServer> get servers => _servers;
  VpnServer? get selectedServer => _selectedServer;
  VpnServer? get connectedServer => _connectedServer;
  VpnConnectionStatus get status => _status;
  bool get isLoadingServers => _isLoadingServers;
  String? get errorMessage => _errorMessage;
  Duration get connectionDuration => _connectionDuration;
  bool get isConnected => _status == VpnConnectionStatus.connected;
  bool get isConnecting => _status == VpnConnectionStatus.connecting;
  int? get currentPing => _currentPing;
  
  String get dataUsage {
    final download = _formatBytes(_totalDownloadBytes);
    final upload = _formatBytes(_totalUploadBytes);
    return '↓ $download  ↑ $upload';
  }

  VpnProvider() {
    _init();
  }

  void _updateStatus(VpnConnectionStatus status) {
    _status = status;
    notifyListeners();
  }

  void _init() {
    _statusSubscription = _vpnService.statusStream.listen((status) {
      _status = status;
      
      if (status == VpnConnectionStatus.connected) {
        _connectedServer = _vpnService.connectedServer;
        _startDurationTimer();
        _startPingTimer();
        _updateRealDataUsage();
      } else if (status == VpnConnectionStatus.disconnected) {
        _connectedServer = null;
        _stopDurationTimer();
        _stopPingTimer();
        _connectionDuration = Duration.zero;
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
        _lastDownloadBytes = 0;
        _lastUploadBytes = 0;
        _currentPing = null;
      } else if (status == VpnConnectionStatus.error) {
        // خطا در اتصال - تلاش برای سرور بعدی
        _handleConnectionError();
      }
      
      notifyListeners();
    });
    
    // IMPORTANT: Always refresh and test servers on app startup
    _loadAndTestServers();
  }
  
  Future<void> _loadAndTestServers() async {
    await loadServers(forceRefresh: true);
    
    // تست خودکار سرورها بعد از لود
    if (_servers.isNotEmpty) {
      await testAllServers();
    }
  }

  void _startDurationTimer() {
    _stopDurationTimer();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final duration = _vpnService.getConnectionDuration();
      if (duration != null) {
        _connectionDuration = duration;
        notifyListeners();
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  // Real data usage from VPN service (cumulative)
  void _updateRealDataUsage() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isConnected) {
        timer.cancel();
        return;
      }
      
      // Get current traffic from VPN service
      final currentDownload = _vpnService.downloadSpeed;
      final currentUpload = _vpnService.uploadSpeed;
      
      // Calculate difference and add to total
      if (_lastDownloadBytes > 0) {
        _totalDownloadBytes += (currentDownload - _lastDownloadBytes).abs();
      }
      if (_lastUploadBytes > 0) {
        _totalUploadBytes += (currentUpload - _lastUploadBytes).abs();
      }
      
      _lastDownloadBytes = currentDownload;
      _lastUploadBytes = currentUpload;
      
      notifyListeners();
    });
  }

  // Ping timer - every 5 seconds
  void _startPingTimer() {
    _stopPingTimer();
    
    // Get initial ping
    _updateCurrentPing();
    
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateCurrentPing();
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _currentPing = null;
  }

  Future<void> _updateCurrentPing() async {
    if (_connectedServer == null) return;
    
    final ping = await _serverService.testServerConnectivity(_connectedServer!);
    _currentPing = ping;
    notifyListeners();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Load servers from service
  Future<void> loadServers({bool forceRefresh = false}) async {
    _isLoadingServers = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _servers = await _serverService.fetchServers(forceRefresh: forceRefresh);
      
      if (_servers.isEmpty) {
        _errorMessage = 'No servers found';
      }
    } catch (e) {
      _errorMessage = 'Failed to load servers: $e';
      if (kDebugMode) {
        debugPrint('Error loading servers: $e');
      }
    } finally {
      _isLoadingServers = false;
      notifyListeners();
    }
  }

  /// Test all servers in parallel
  Future<void> testAllServers() async {
    if (_servers.isEmpty) return;

    _isLoadingServers = true;
    _errorMessage = 'Testing servers...';
    notifyListeners();

    try {
      final testedServers = await _serverService.testServersInParallel(
        _servers,
        onProgress: (tested, total) {
          _errorMessage = 'Testing $tested/$total servers...';
          notifyListeners();
        },
      );

      _servers = testedServers;
      
      if (_servers.isNotEmpty) {
        _selectedServer = _servers.first; // بهترین سرور (کمترین ping)
        _errorMessage = null;
      } else {
        _errorMessage = 'No reachable servers found';
      }
    } catch (e) {
      _errorMessage = 'Failed to test servers: $e';
      if (kDebugMode) {
        debugPrint('Error testing servers: $e');
      }
    } finally {
      _isLoadingServers = false;
      notifyListeners();
    }
  }

  /// Test all servers and find the best one
  Future<void> findBestServer() async {
    await testAllServers();
  }
  
  /// Handle connection error and try next server (بدون نمایش شمارش)
  void _handleConnectionError() async {
    if (_servers.isEmpty) return;
    
    // پیدا کردن سرور بعدی
    final currentIndex = _servers.indexWhere(
      (s) => s.fullAddress == _selectedServer?.fullAddress
    );
    
    if (currentIndex == -1 || currentIndex >= _servers.length - 1) {
      _errorMessage = 'All servers failed';
      _updateStatus(VpnConnectionStatus.error);
      return;
    }
    
    // سرور بعدی
    final nextServer = _servers[currentIndex + 1];
    
    // تلاش خودکار بدون نمایش پیام 3 ثانیه
    // فقط وضعیت connecting نمایش داده می‌شود
    _selectedServer = nextServer;
    
    // کمی تاخیر برای اطمینان از disconnect کامل
    await Future.delayed(const Duration(milliseconds: 500));
    
    await connect();
  }

  /// Connect to best server using parallel race (5 at a time)
  Future<void> connect() async {
    if (_status == VpnConnectionStatus.connecting || _status == VpnConnectionStatus.connected) {
      return;
    }

    // If no servers available, try to load
    if (_servers.isEmpty) {
      await findBestServer();
    }

    if (_servers.isEmpty) {
      _errorMessage = 'No server available';
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _updateStatus(VpnConnectionStatus.connecting);
    
    try {
      // Request VPN permission first
      final permissionGranted = await _vpnService.requestPermission();
      
      if (!permissionGranted) {
        _errorMessage = 'VPN permission denied';
        _updateStatus(VpnConnectionStatus.disconnected);
        return;
      }
      
      // Try to connect using parallel race method (5 servers at a time)
      final connectedServer = await _connectToFirstResponsive();
      
      if (connectedServer != null) {
        _selectedServer = connectedServer;
        final success = await _vpnService.connect(connectedServer);
        
        if (!success) {
          _errorMessage = 'Failed to connect';
          _updateStatus(VpnConnectionStatus.error);
        }
      } else {
        _errorMessage = 'All servers failed to respond';
        _updateStatus(VpnConnectionStatus.error);
      }
    } catch (e) {
      _errorMessage = 'Connection error: ${e.toString()}';
      if (kDebugMode) {
        debugPrint('VPN connection error: $e');
      }
      _updateStatus(VpnConnectionStatus.error);
    }
  }

  /// اتصال موازی به 5 سرور - اولین پاسخ برنده
  Future<VpnServer?> _connectToFirstResponsive() async {
    const batchSize = 5;
    
    for (int i = 0; i < _servers.length; i += batchSize) {
      final end = (i + batchSize < _servers.length) 
          ? i + batchSize 
          : _servers.length;
      
      final batch = _servers.sublist(i, end);
      
      if (kDebugMode) {
        debugPrint('🔄 Testing batch ${i ~/ batchSize + 1}: servers $i to ${end - 1}');
      }
      
      // تست موازی - اولین سرور که پاسخ داد برنده است
      try {
        final firstResponsive = await _raceServers(batch);
        
        if (firstResponsive != null) {
          if (kDebugMode) {
            debugPrint('✅ Winner: ${firstResponsive.fullAddress} (${firstResponsive.ping}ms)');
          }
          return firstResponsive;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Batch failed: $e');
        }
      }
    }
    
    return null;
  }

  /// Race بین چندین سرور - اولین پاسخ برنده
  Future<VpnServer?> _raceServers(List<VpnServer> servers) async {
    final futures = servers.map((server) => _tryConnectToServer(server));
    
    try {
      // اولین future که complete شود برنده است
      final winner = await Future.any(futures);
      return winner;
    } catch (e) {
      return null;
    }
  }

  /// تست اتصال به یک سرور
  Future<VpnServer?> _tryConnectToServer(VpnServer server) async {
    try {
      final ping = await _serverService.testServerConnectivity(server);
      
      if (ping != null && ping < 600) {
        // این سرور پاسخ داد - برنده شد!
        return server.copyWith(ping: ping);
      }
      
      // این سرور شکست خورد - future هرگز complete نمی‌شود
      return await Future.delayed(const Duration(hours: 1));
    } catch (e) {
      // خطا - future هرگز complete نمی‌شود
      return await Future.delayed(const Duration(hours: 1));
    }
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    if (_status == VpnConnectionStatus.disconnecting || _status == VpnConnectionStatus.disconnected) {
      return;
    }

    await _vpnService.disconnect();
  }

  /// Select a specific server
  void selectServer(VpnServer server) {
    _selectedServer = server;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Refresh servers
  Future<void> refreshServers() async {
    await _serverService.clearCache();
    await loadServers(forceRefresh: true);
  }

  /// Connect to next server in list
  Future<void> connectToNextServer() async {
    if (_servers.isEmpty || _selectedServer == null) return;
    
    // Find current server index
    final currentIndex = _servers.indexWhere(
      (s) => s.fullAddress == _selectedServer?.fullAddress
    );
    
    if (currentIndex == -1 || currentIndex >= _servers.length - 1) {
      _errorMessage = 'No more servers available';
      notifyListeners();
      return;
    }
    
    // Disconnect first
    await disconnect();
    
    // Wait for disconnect
    await Future.delayed(const Duration(seconds: 1));
    
    // Select next server
    _selectedServer = _servers[currentIndex + 1];
    notifyListeners();
    
    // Connect to next server
    await connect();
  }

  /// Reset state (called when app is paused and VPN is not connected)
  void resetState() {
    if (!isConnected) {
      _servers.clear();
      _selectedServer = null;
      _errorMessage = null;
      _connectionDuration = Duration.zero;
      _totalDownloadBytes = 0;
      _totalUploadBytes = 0;
      _lastDownloadBytes = 0;
      _lastUploadBytes = 0;
      notifyListeners();
      
      // Reload and test servers
      _loadAndTestServers();
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _stopDurationTimer();
    _stopPingTimer();
    _vpnService.dispose();
    super.dispose();
  }
}
