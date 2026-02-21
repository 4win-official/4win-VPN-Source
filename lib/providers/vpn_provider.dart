import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import '../models/vpn_server.dart';
import '../models/dns_server.dart';
import '../models/openvpn_config.dart';
import '../services/server_service.dart';
import '../services/vpn_service.dart';
import '../services/dns_service.dart';
import '../services/dns_vpn_connection.dart';
import '../services/openvpn_service.dart';
import '../services/openvpn_connection.dart';

// Re-export for convenience
export '../services/vpn_service.dart' show VpnConnectionStatus;

class VpnProvider with ChangeNotifier {
  final ServerService _serverService = ServerService();
  final VpnService _vpnService = VpnService();
  final DnsService _dnsService = DnsService();
  final OpenVpnService _openVpnService = OpenVpnService();
  
  // Expose VPN service for log access
  VpnService get vpnService => _vpnService;
  
  // Protocol selection: 'sstp', 'direct_dns', or 'openvpn'
  String _selectedProtocol = 'sstp';
  String get selectedProtocol => _selectedProtocol;
  
  // DNS servers
  List<DnsServer> _dnsServers = [];
  DnsServer? _selectedDnsServer;
  List<DnsServer> get dnsServers => _dnsServers;
  DnsServer? get selectedDnsServer => _selectedDnsServer;
  
  // OpenVPN configs
  List<OpenVpnConfig> _openVpnConfigs = [];
  OpenVpnConfig? _selectedOpenVpnConfig;
  List<OpenVpnConfig> get openVpnConfigs => _openVpnConfigs;
  OpenVpnConfig? get selectedOpenVpnConfig => _selectedOpenVpnConfig;

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
  bool _pingFailed = false; // تایم‌اوت 3 ثانیه برای پینگ
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
  bool get pingFailed => _pingFailed; // نمایش Failed در UI
  
  String get dataUsage {
    final download = _formatBytes(_totalDownloadBytes);
    final upload = _formatBytes(_totalUploadBytes);
    return '↓ $download  ↑ $upload';
  }

  VpnProvider() {
    _init();
    // بارگیری پروتکل انتخابی
    loadSelectedProtocol();
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
    // فقط دانلود - تست نشود
    // تست هنگام کلیک دکمه اتصال انجام می‌شود
    await loadServers(forceRefresh: true);
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
      
      // DNS mode: No data usage tracking (only ping)
      if (_selectedProtocol == 'direct_dns') {
        return; // Skip data usage for DNS
      }
      
      // SSTP mode: Get current traffic from VPN service
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
    // DNS mode: ping DNS server
    if (_selectedProtocol == 'direct_dns' && _selectedDnsServer != null) {
      try {
        _pingFailed = false;
        final ping = await _dnsService.testDnsConnectivity(_selectedDnsServer!)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => null,
            );
        _currentPing = ping;
      } catch (e) {
        _currentPing = null;
        _pingFailed = true;
      }
      notifyListeners();
      return;
    }
    
    // SSTP mode: ping VPN server
    if (_connectedServer == null) return;
    
    try {
      _pingFailed = false; // Reset قبل از تست جدید
      // تایم‌اوت 3 ثانیه برای پینگ
      final ping = await _serverService.testServerConnectivity(_connectedServer!)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              _pingFailed = true; // تایم‌اوت - نمایش Failed
              return null;
            },
          );
      _currentPing = ping;
      if (ping == null && !_pingFailed) {
        _pingFailed = true; // خطا در پینگ
      }
    } catch (e) {
      _currentPing = null; // خطا - پینگ موفق نبود
      _pingFailed = true; // نمایش Failed در UI
    }
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
      
      // حذف خطا - فقط Connecting نمایش داده شود
      if (_servers.isEmpty) {
        // بدون نمایش خطا - حلقه بی‌نهایت دوباره دانلود می‌کند
        _errorMessage = null;
      }
    } catch (e) {
      // حذف خطا - فقط Connecting نمایش داده شود
      _errorMessage = null;
      if (kDebugMode) {
        debugPrint('⚠️ خطا در بارگیری سرورها - دوباره تلاش می‌شود');
      }
    } finally {
      _isLoadingServers = false;
      notifyListeners();
    }
  }

  /// Test all servers in parallel با تایم‌اوت
  Future<void> testAllServers() async {
    if (_servers.isEmpty) return;

    _isLoadingServers = true;
    // حذف پیغام Testing - فقط Connecting نمایش داده شود
    _errorMessage = null;
    notifyListeners();

    try {
      // تایم‌اوت کلی 120 ثانیه (2 دقیقه) برای تست - اگه گیر کرد، skip میشه
      final testedServers = await _serverService.testServersInParallel(
        _servers,
        onProgress: (tested, total) {
          // حذف پیغام Testing - فقط Connecting در UI
          // پیشرفت تست فقط در debug log
          if (kDebugMode) {
            debugPrint('Testing $tested/$total servers...');
          }
        },
      ).timeout(
        const Duration(seconds: 120), // 2 دقیقه
        onTimeout: () {
          // اگه تایم‌اوت شد، لیست خام سرورها رو برگردون (بدون تست)
          if (kDebugMode) {
            debugPrint('⚠️ Testing timeout - using servers without ping test');
          }
          return _servers;
        },
      );

      _servers = testedServers;
      
      if (_servers.isNotEmpty) {
        _selectedServer = _servers.first; // بهترین سرور (کمترین ping)
        _errorMessage = null;
      } else {
        // حذف خطا - حلقه بی‌نهایت دوباره تست می‌کند
        _errorMessage = null;
      }
    } catch (e) {
      // حذف خطا - فقط Connecting نمایش داده شود
      _errorMessage = null;
      if (kDebugMode) {
        debugPrint('⚠️ خطا در تست سرورها - دوباره تلاش می‌شود');
      }
      // حتی با خطا، اگه سرور داریم ادامه بده
      if (_servers.isNotEmpty) {
        _selectedServer = _servers.first;
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
    // کمی تاخیر برای اطمینان از disconnect کامل
    await Future.delayed(const Duration(milliseconds: 500));
    
    // دوباره اتصال - connect خودش حلقه بی‌نهایت داره
    await connect();
  }

  /// Connect to selected or best server (one by one - RESTORED WORKING VERSION)
  Future<void> connect() async {
    if (_status == VpnConnectionStatus.connecting || _status == VpnConnectionStatus.connected) {
      return;
    }

    // ⚡ CRITICAL: Set to connecting immediately so user sees feedback
    _status = VpnConnectionStatus.connecting;
    notifyListeners();

    // 🔀 PROTOCOL DETECTION: Direct DNS, OpenVPN, or SSTP
    if (_selectedProtocol == 'direct_dns') {
      // ✅ Direct DNS: Use selected DNS server
      await _connectDirectDns();
      return;
    } else if (_selectedProtocol == 'openvpn') {
      // ✅ OpenVPN: Use selected OpenVPN config
      await _connectOpenVpn();
      return;
    }

    // ✅ SSTP: Original SSTP connection logic
    
    // 🔧 CHECK CUSTOM SERVER FIRST
    final prefs = await SharedPreferences.getInstance();
    final useCustomServer = prefs.getBool('use_custom_server') ?? false;
    
    if (useCustomServer) {
      // ✅ Use custom server only
      final customServerStr = prefs.getString('custom_server') ?? '';
      final customUsername = prefs.getString('custom_username') ?? '';
      final customPassword = prefs.getString('custom_password') ?? '';
      
      if (customServerStr.isNotEmpty) {
        // Parse custom server
        final parts = customServerStr.split(':');
        if (parts.length == 2) {
          final customServer = VpnServer(
            address: parts[0],
            port: int.tryParse(parts[1]) ?? 443,
            username: customUsername.isNotEmpty ? customUsername : 'vpn',
            password: customPassword.isNotEmpty ? customPassword : 'vpn',
          );
          
          _selectedServer = customServer;
          notifyListeners();
          
          try {
            // Request VPN permission
            final permissionGranted = await _vpnService.requestPermission();
            
            if (!permissionGranted) {
              _status = VpnConnectionStatus.error;
              _errorMessage = 'VPN permission denied';
              notifyListeners();
              return;
            }
            
            // Connect to custom server
            final success = await _vpnService.connect(customServer);
            
            if (success) {
              // Success!
              return;
            } else {
              _status = VpnConnectionStatus.error;
              _errorMessage = 'Failed to connect to custom server';
              notifyListeners();
              return;
            }
          } catch (e) {
            _status = VpnConnectionStatus.error;
            _errorMessage = 'Custom server error: $e';
            notifyListeners();
            return;
          }
        } else {
          _status = VpnConnectionStatus.error;
          _errorMessage = 'Invalid custom server format. Use: hostname:port';
          notifyListeners();
          return;
        }
      } else {
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Custom server is empty';
        notifyListeners();
        return;
      }
    }
    
    // ✅ If not using custom server, use server list
    // 1️⃣ If no servers → infinite loop: download → test → connect
    while (_servers.isEmpty) {
      await loadServers(forceRefresh: true);
      if (_servers.isEmpty) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
    }

    // 2️⃣ Test servers (batch by batch)
    await testAllServers();

    // 3️⃣ If still no servers after test → re-download and test
    while (_servers.isEmpty) {
      await loadServers(forceRefresh: true);
      if (_servers.isEmpty) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      await testAllServers();
    }

    // 4️⃣ Try connecting one by one (best ping first)
    for (var server in _servers) {
      _selectedServer = server;
      notifyListeners();
      
      try {
        // Request VPN permission first
        final permissionGranted = await _vpnService.requestPermission();
        
        if (!permissionGranted) {
          // No error message - just keep trying
          return;
        }
        
        final success = await _vpnService.connect(server);
        
        if (success) {
          // Success - exit loop
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Failed to connect to ${server.fullAddress}: $e');
        }
        // Continue to next server
        continue;
      }
    }

    // 5️⃣ If all failed → restart from beginning (infinite loop)
    if (_status != VpnConnectionStatus.connected) {
      // Re-download, test, and try again
      await connect();
    }
  }
  
  /// Connect via Direct DNS (separate from SSTP)
  Future<void> _connectDirectDns() async {
    // Check if DNS server is selected
    if (_selectedDnsServer == null) {
      // ✅ نمایش پیام به کاربر
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please select a DNS server from Server List first';
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint('⚠️ No DNS server selected - please choose from Server List');
      }
      return;
    }

    try {
      // Set status to connecting
      _status = VpnConnectionStatus.connecting;
      notifyListeners();

      // Request VPN permission
      final permissionGranted = await DnsVpnConnection.requestPermission();
      
      if (!permissionGranted) {
        _status = VpnConnectionStatus.disconnected;
        notifyListeners();
        return;
      }

      // Connect using selected DNS server
      await DnsVpnConnection.connect(
        primaryDns: _selectedDnsServer!.primaryDns,
        secondaryDns: _selectedDnsServer!.secondaryDns ?? '8.8.4.4',
      );

      // Update status to connected
      _status = VpnConnectionStatus.connected;
      _connectedServer = null; // DNS mode has no VPN server
      _startDurationTimer();
      notifyListeners();

      if (kDebugMode) {
        debugPrint('✅ Connected to DNS: ${_selectedDnsServer!.primaryDns}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to connect DNS: $e');
      }
      _status = VpnConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  /// Connect via OpenVPN
  Future<void> _connectOpenVpn() async {
    if (_selectedOpenVpnConfig == null) {
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please select an OpenVPN config first';
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint('❌ No OpenVPN config selected');
      }
      return;
    }

    try {
      _status = VpnConnectionStatus.connecting;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('🚀 Connecting to OpenVPN: ${_selectedOpenVpnConfig!.name}');
      }

      // ✅ Connection timeout watchdog (15 seconds)
      Timer? connectionTimeoutTimer;
      connectionTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (_status == VpnConnectionStatus.connecting) {
          if (kDebugMode) {
            debugPrint('⏱️ Connection timeout - still connecting after 15s');
          }
          _status = VpnConnectionStatus.error;
          _errorMessage = 'Connection timeout. Please try again or check server.';
          notifyListeners();
        }
      });

      // Initialize OpenVPN with stage callback
      OpenVpnConnection.onStageChanged = (VPNStage? stage) {
        if (kDebugMode) {
          debugPrint('🔵 OpenVPN Stage: $stage');
        }
        
        // Update status based on stage
        if (stage == VPNStage.connected) {
          connectionTimeoutTimer?.cancel(); // ✅ اتصال موفق - cancel timeout
          _status = VpnConnectionStatus.connected;
          _connectedServer = null; // OpenVPN mode has no traditional VPN server
          _errorMessage = null; // Clear any previous errors
          _startDurationTimer();
          _startPingTimer();
          notifyListeners();
        } else if (stage == VPNStage.disconnected) {
          connectionTimeoutTimer?.cancel();
          _status = VpnConnectionStatus.disconnected;
          _stopDurationTimer();
          _stopPingTimer();
          notifyListeners();
        } else if (stage == VPNStage.error) {
          connectionTimeoutTimer?.cancel();
          _status = VpnConnectionStatus.error;
          _errorMessage = 'Connection failed. Tap to retry.';
          _stopDurationTimer();
          _stopPingTimer();
          notifyListeners();
        } else if (stage == VPNStage.denied) {
          connectionTimeoutTimer?.cancel();
          _status = VpnConnectionStatus.error;
          _errorMessage = 'VPN permission denied';
          _stopDurationTimer();
          _stopPingTimer();
          notifyListeners();
        } else if (stage == VPNStage.connecting || 
                   stage == VPNStage.prepare || 
                   stage == VPNStage.authenticating) {
          _status = VpnConnectionStatus.connecting;
          notifyListeners();
        }
      };

      // Connect using OpenVPN with timeout
      final connected = await OpenVpnConnection.connect(_selectedOpenVpnConfig!).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('⏱️ OpenVPN connection timeout (30s)');
          }
          connectionTimeoutTimer?.cancel();
          return false;
        },
      );
      
      if (!connected) {
        connectionTimeoutTimer?.cancel();
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Failed to establish OpenVPN connection. Please check your config and try again.';
        notifyListeners();
      }
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('⏱️ OpenVPN connection timeout');
      }
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Connection timeout. Please try again.';
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to connect OpenVPN: $e');
      }
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Failed to connect: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    if (_status == VpnConnectionStatus.disconnecting || _status == VpnConnectionStatus.disconnected) {
      return;
    }

    _status = VpnConnectionStatus.disconnecting;
    notifyListeners();

    try {
      // Disconnect based on protocol
      if (_selectedProtocol == 'direct_dns') {
        await DnsVpnConnection.disconnect();
      } else if (_selectedProtocol == 'openvpn') {
        await OpenVpnConnection.disconnect();
        if (kDebugMode) {
          debugPrint('🔌 Disconnecting OpenVPN...');
        }
      } else {
        await _vpnService.disconnect();
      }
      
      _status = VpnConnectionStatus.disconnected;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Disconnect error: $e');
      }
      _status = VpnConnectionStatus.disconnected;
    }
    
    notifyListeners();
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
      // حذف ارور - همیشه Connecting باقی بماند
      // دوباره به اولین سرور برگرد و تلاش کن
      if (_servers.isNotEmpty) {
        _selectedServer = _servers.first;
      }
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

  // ==================== Direct DNS Protocol Methods ====================
  
  /// بارگیری پروتکل انتخابی از SharedPreferences
  Future<void> loadSelectedProtocol() async {
    _selectedProtocol = await _dnsService.getSelectedProtocol();
    notifyListeners();
  }
  
  /// تغییر پروتکل (SSTP یا Direct DNS)
  Future<void> switchProtocol(String protocol) async {
    if (_selectedProtocol == protocol) return;
    
    // اگر متصل است، ابتدا قطع کن
    if (isConnected || isConnecting) {
      await disconnect();
    }
    
    _selectedProtocol = protocol;
    await _dnsService.setSelectedProtocol(protocol);
    notifyListeners();
  }
  
  /// گرفتن تمام DNS servers
  Future<List<DnsServer>> getAllDnsServers() async {
    return await _dnsService.getAllDnsServers();
  }
  
  /// انتخاب DNS server و اتصال خودکار
  Future<void> selectDnsServerAndConnect(DnsServer server) async {
    _selectedDnsServer = server;
    notifyListeners();
    
    // اگه قبلاً متصل بود، قطع کن و دوباره وصل کن
    if (isConnected || isConnecting) {
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    // اتصال خودکار
    await connect();
  }
  
  /// تست همه DNS servers
  Future<List<DnsServer>> testAllDnsServers(List<DnsServer> servers) async {
    return await _dnsService.testDnsServersInParallel(
      servers,
      onProgress: (tested, total) {
        if (kDebugMode) {
          debugPrint('Testing DNS $tested/$total...');
        }
      },
    );
  }
  
  /// افزودن DNS سفارشی
  Future<void> addCustomDns(DnsServer server) async {
    await _dnsService.addCustomDns(server);
    _dnsServers = await _dnsService.getAllDnsServers();
    notifyListeners();
  }
  
  /// حذف DNS سفارشی
  Future<void> removeCustomDns(String primaryDns) async {
    await _dnsService.removeCustomDns(primaryDns);
    _dnsServers = await _dnsService.getAllDnsServers();
    notifyListeners();
  }
  
  /// انتخاب DNS و اتصال
  Future<void> selectDnsAndConnect(DnsServer server) async {
    _selectedDnsServer = server;
    
    // Save selected DNS
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_dns_primary', server.primaryDns);
    if (server.secondaryDns != null) {
      await prefs.setString('selected_dns_secondary', server.secondaryDns!);
    }
    
    notifyListeners();
    
    if (kDebugMode) {
      debugPrint('✅ DNS Server Selected: ${server.name} (${server.primaryDns})');
    }
    
    // Automatically connect
    await connect();
  }
  
  /// ==================== OpenVPN Methods ====================
  
  /// Load OpenVPN configs
  Future<void> loadOpenVpnConfigs() async {
    try {
      _openVpnConfigs = await _openVpnService.loadConfigs();
      
      // Load selected config
      final selectedName = await _openVpnService.getSelectedConfigName();
      if (selectedName != null) {
        _selectedOpenVpnConfig = _openVpnConfigs.firstWhere(
          (config) => config.name == selectedName,
          orElse: () => _openVpnConfigs.isNotEmpty ? _openVpnConfigs.first : null as OpenVpnConfig,
        );
      }
      
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint('✅ Loaded ${_openVpnConfigs.length} OpenVPN configs');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load OpenVPN configs: $e');
      }
    }
  }
  
  /// Select OpenVPN config and connect
  Future<void> selectOpenVpnConfigAndConnect(OpenVpnConfig config) async {
    _selectedOpenVpnConfig = config;
    
    // Save selected config
    await _openVpnService.setSelectedConfig(config.name);
    
    notifyListeners();
    
    if (kDebugMode) {
      debugPrint('✅ OpenVPN Config Selected: ${config.name}');
    }
    
    // Automatically connect
    await connect();
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
