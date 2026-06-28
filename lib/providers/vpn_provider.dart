import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import '../models/vpn_server.dart';
import '../models/dns_server.dart';
import '../models/openvpn_config.dart';
import '../models/slowdns_config.dart';
import '../services/server_service.dart';
import '../services/vpn_service.dart';
import '../services/dns_service.dart';
import '../services/dns_vpn_connection.dart';
import '../services/openvpn_service.dart';
import '../services/openvpn_connection.dart';
import '../services/slowdns_service.dart';
import '../models/xray_server.dart';
import '../services/xray_service.dart';
import '../services/xray_connection.dart';
import '../services/xray_config_builder.dart';

// Re-export for convenience
export '../services/vpn_service.dart' show VpnConnectionStatus;

class VpnProvider with ChangeNotifier {
  final ServerService _serverService = ServerService();
  final VpnService _vpnService = VpnService();
  final DnsService _dnsService = DnsService();
  final OpenVpnService _openVpnService = OpenVpnService();
  final SlowDnsService _slowDnsService = SlowDnsService();
  final XrayServerService _xrayService = XrayServerService();
  
  // Expose VPN service for log access
  VpnService get vpnService => _vpnService;
  
  // Protocol selection: 'sstp', 'direct_dns', 'openvpn', 'slowdns', or 'xray'
  String _selectedProtocol = 'xray';
  String get selectedProtocol => _selectedProtocol;

  // Xray (real Xray core / v2rayNG) servers
  List<XrayServer> _xrayServers = [];
  XrayServer? _selectedXrayServer;
  List<XrayServer> get xrayServers => _xrayServers;
  XrayServer? get selectedXrayServer => _selectedXrayServer;
  // وقتی کاربر «گروه رایگان» را به‌عنوان مقصد انتخاب کرده (بدون انتخاب یک سرور
  // مشخص). در این حالت موقع اتصال، گروه تست و به بهترین سرور وصل می‌شویم.
  bool _xrayFreeGroupSelected = false;
  bool get xrayFreeGroupSelected => _xrayFreeGroupSelected;
  // ids of servers currently being delay-tested (for spinner UI)
  final Set<String> _xrayTestingIds = {};
  Set<String> get xrayTestingIds => _xrayTestingIds;
  bool _xrayGroupTesting = false;
  bool get xrayGroupTesting => _xrayGroupTesting;
  bool _xrayRefreshing = false;
  bool get xrayRefreshing => _xrayRefreshing;
  
  // Slow DNS configs
  List<SlowDnsConfig> _slowDnsConfigs = [];
  SlowDnsConfig? _selectedSlowDnsConfig;
  List<SlowDnsConfig> get slowDnsConfigs => _slowDnsConfigs;
  SlowDnsConfig? get selectedSlowDnsConfig => _selectedSlowDnsConfig;
  
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

  // Direct DNS traffic baseline (TrafficStats - device-wide counters)
  int _dnsBaselineRxBytes = -1;
  int _dnsBaselineTxBytes = -1;
  
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
    // بارگیری سرورهای ایکس‌ری
    loadXrayServers();
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
      // برای direct_dns و slowdns سرویس SSTP فعال نیست و getConnectionDuration
      // مقدار null برمی‌گرداند؛ پس مدت‌زمان را خودمان به‌صورت دستی می‌شماریم.
      if (_selectedProtocol == 'direct_dns' || _selectedProtocol == 'slowdns') {
        _connectionDuration += const Duration(seconds: 1);
        notifyListeners();
        return;
      }
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
    // reset baseline در شروع هر اتصال جدید
    _dnsBaselineRxBytes = -1;
    _dnsBaselineTxBytes = -1;

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isConnected) {
        timer.cancel();
        return;
      }
      
      // Direct DNS mode: ترافیک رد و بدل شده با استفاده از TrafficStats دستگاه
      if (_selectedProtocol == 'direct_dns') {
        _updateDnsTraffic();
        return;
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

  // محاسبه ترافیک رد و بدل شده در حالت Direct DNS
  // از TrafficStats دستگاه استفاده می‌کنیم: مقدار اولیه را به عنوان baseline
  // ذخیره و سپس اختلاف نسبت به baseline را به عنوان ترافیک مصرفی محاسبه می‌کنیم
  Future<void> _updateDnsTraffic() async {
    try {
      final stats = await DnsVpnConnection.getStats();
      final rx = stats['rxBytes'] ?? 0;
      final tx = stats['txBytes'] ?? 0;

      if (rx <= 0 && tx <= 0) {
        return; // TrafficStats در دسترس نیست
      }

      // اولین خوانش: ثبت baseline
      if (_dnsBaselineRxBytes < 0 || _dnsBaselineTxBytes < 0) {
        _dnsBaselineRxBytes = rx;
        _dnsBaselineTxBytes = tx;
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
        notifyListeners();
        return;
      }

      // اختلاف نسبت به baseline = ترافیک از زمان اتصال
      final downloaded = rx - _dnsBaselineRxBytes;
      final uploaded = tx - _dnsBaselineTxBytes;
      _totalDownloadBytes = downloaded > 0 ? downloaded : 0;
      _totalUploadBytes = uploaded > 0 ? uploaded : 0;

      notifyListeners();
    } catch (_) {
      // در صورت خطا چیزی به‌روزرسانی نمی‌کنیم
    }
  }

  // Ping timer - every 3 seconds
  void _startPingTimer() {
    _stopPingTimer();
    
    // Get initial ping
    _updateCurrentPing();
    
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _updateCurrentPing();
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _currentPing = null;
  }

  Future<void> _updateCurrentPing() async {
    // DNS mode: پینگ به سرور DNS متصل‌شده (هر ۳ ثانیه، مثل دستور ping ترموکس)
    if (_selectedProtocol == 'direct_dns' && _selectedDnsServer != null) {
      final dnsIp = _selectedDnsServer!.primaryDns;
      try {
        _pingFailed = false;
        // پینگ native (ICMP + TCP + UDP) - حتی موقع فعال بودن VPN هم کار می‌کند
        int? ping = await DnsVpnConnection.pingDns(dnsIp).timeout(
          const Duration(seconds: 6),
          onTimeout: () => null,
        );
        // در صورت ناموفق بودن native، fallback به روش Dart
        ping ??= await _dnsService.testDnsConnectivity(_selectedDnsServer!).timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        );
        _currentPing = ping;
        _pingFailed = (ping == null);
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

    // 🔀 PROTOCOL DETECTION: Direct DNS, OpenVPN, Slow DNS, or SSTP
    if (_selectedProtocol == 'direct_dns') {
      // ✅ Direct DNS: Use selected DNS server
      await _connectDirectDns();
      return;
    } else if (_selectedProtocol == 'openvpn') {
      // ✅ OpenVPN: Use selected OpenVPN config
      await _connectOpenVpn();
      return;
    } else if (_selectedProtocol == 'slowdns') {
      // ✅ Slow DNS: Use selected Slow DNS config
      await _connectSlowDns();
      return;
    } else if (_selectedProtocol == 'xray') {
      // ✅ Xray (real Xray core): Use selected Xray server
      await _connectXray();
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

    // تنظیمات DNS برای اتصال SSTP
    final bool deepScan = prefs.getBool('deep_scan') ?? false;
    final String chosenDns = (prefs.getString('custom_dns') ?? '8.8.8.8').trim();

    // تنظیم MTU برای SSTP. سه حالت:
    //   'off'    : MTU پیش‌فرض (1500)
    //   'manual' : مقدار دستی واردشده توسط کاربر (1280..1500)
    //   'auto'   : تشخیص خودکار واقعی MTU با probe به سرور
    String mtuMode = prefs.getString('mtu_mode') ?? 'off';
    int manualMtu = (prefs.getInt('manual_mtu') ?? 1400).clamp(1280, 1500);

    // ✂️ SSTP Fragment: SSTP wraps PPP inside TLS, so we cannot fragment the
    // TLS ClientHello the way Xray does. The genuine, observable way to
    // "fragment" an SSTP tunnel is to shrink the inner PPP MTU so the wrapped
    // PPP frames are split into several smaller IP packets — this breaks up the
    // uniform packet-size fingerprint that some DPI boxes key on. We only apply
    // it when the user hasn't already chosen an explicit Manual/Auto MTU, so we
    // never override their MTU choice.
    final bool sstpFragment = prefs.getBool('sstp_fragment') ?? false;
    if (sstpFragment && mtuMode == 'off') {
      // Derive a smaller MTU from the configured fragment size. Larger sizes
      // -> less aggressive (bigger MTU); smaller sizes -> more aggressive.
      final String fragSize = prefs.getString('sstp_fragment_size') ?? '1-3';
      final int firstNum =
          int.tryParse(fragSize.split('-').first.trim()) ?? 1;
      // Map fragment "size" 1..6 to an MTU in the 1280..1380 range.
      final int fragMtu = (1280 + (firstNum.clamp(1, 6) - 1) * 20).clamp(1280, 1500);
      mtuMode = 'manual';
      manualMtu = fragMtu;
    }

    // در حالت Deep Scan هر سرور با چند DNS مختلف تست می‌شود (ممکن است یک سرور
    // با DNS گوگل و سرور دیگری با DNS کلادفلر کار کند). در حالت عادی فقط از
    // DNS انتخاب‌شده‌ی کاربر استفاده می‌شود.
    final List<String> dnsCandidates = deepScan
        ? _deepScanDnsList()
        : [chosenDns.isNotEmpty ? chosenDns : '8.8.8.8'];

    // 4️⃣ Try connecting one by one (best ping first)
    for (var server in _servers) {
      _selectedServer = server;
      notifyListeners();

      for (final dns in dnsCandidates) {
        try {
          // Request VPN permission first
          final permissionGranted = await _vpnService.requestPermission();

          if (!permissionGranted) {
            // No error message - just keep trying
            return;
          }

          final success = await _vpnService.connect(
            server,
            dns: dns,
            mtuMode: mtuMode,
            manualMtu: manualMtu,
          );

          if (success) {
            // Success - exit loop
            return;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed: ${server.fullAddress} via DNS $dns: $e');
          }
          // Continue to next DNS / next server
          continue;
        }
      }
    }

    // 5️⃣ If all failed → restart from beginning (infinite loop)
    if (_status != VpnConnectionStatus.connected) {
      // Re-download, test, and try again
      await connect();
    }
  }

  /// لیست DNS هایی که در حالت Deep Scan برای هر سرور امتحان می‌شوند.
  /// ترکیبی از DNS های جهانی و DNS های ضد تحریم ایرانی تا بیشترین شانس
  /// اتصال برای کاربرانِ با اینترنت محدودشده فراهم شود.
  List<String> _deepScanDnsList() {
    return const [
      '8.8.8.8',          // Google
      '1.1.1.1',          // Cloudflare
      '178.22.122.100',   // Shekan
      '185.51.200.2',     // Shekan secondary
      '10.202.10.10',     // Radar Game
      '10.202.10.202',    // Online.403
      '78.157.42.100',    // Electro
      '185.55.226.26',    // Begzar
      '208.67.222.222',   // OpenDNS
    ];
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
      // ✅ شروع پینگ خودکار به سرور DNS متصل (هر ۳ ثانیه در صفحه هوم)
      _startPingTimer();
      // ✅ شروع ردیابی ترافیک رد و بدل شده از زمان اتصال
      _updateRealDataUsage();
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

  /// Connect to Slow DNS
  Future<void> _connectSlowDns() async {
    if (_selectedSlowDnsConfig == null) {
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please select a Slow DNS config first';
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint('❌ No Slow DNS config selected');
      }
      return;
    }

    try {
      _status = VpnConnectionStatus.connecting;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('🌐 Connecting to Slow DNS: ${_selectedSlowDnsConfig!.name}');
        debugPrint('   Domain: ${_selectedSlowDnsConfig!.domain}');
        debugPrint('   Name Server: ${_selectedSlowDnsConfig!.nameServer}');
      }

      // Setup Slow DNS connection state callback
      SlowDnsConnection.onStateChanged = (bool connected, String message) {
        if (connected) {
          _status = VpnConnectionStatus.connected;
          _connectedServer = null; // Slow DNS mode
          _errorMessage = null;
          _startDurationTimer();
          _startPingTimer();
        } else {
          _status = VpnConnectionStatus.disconnected;
          _errorMessage = message;
          _stopDurationTimer();
          _stopPingTimer();
        }
        notifyListeners();
      };

      // Connect using Slow DNS
      final connected = await SlowDnsConnection.connect(_selectedSlowDnsConfig!);
      
      if (!connected) {
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Failed to connect. Check config and try again.';
        notifyListeners();
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to connect Slow DNS: $e');
      }
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Failed to connect: ${e.toString()}';
      notifyListeners();
    }
  }

  // ==================== Xray Protocol Methods ====================

  /// Load persisted Xray servers + currently selected one.
  Future<void> loadXrayServers() async {
    _xrayServers = await _xrayService.loadServers();
    _selectedXrayServer = await _xrayService.getSelectedServer();
    final prefs = await SharedPreferences.getInstance();
    _xrayFreeGroupSelected = prefs.getBool('xray_free_group_selected') ?? false;
    notifyListeners();
  }

  /// Add server(s) from share link(s). Returns count added.
  Future<int> addXrayServers(String raw) async {
    final added = await _xrayService.addFromLinks(raw);
    if (added > 0) {
      await loadXrayServers();
    }
    return added;
  }

  /// Remove an Xray server by id.
  Future<void> removeXrayServer(String id) async {
    await _xrayService.removeServer(id);
    await loadXrayServers();
  }

  /// Select an Xray server (for connecting). Picking a specific server clears
  /// the "free group" selection.
  Future<void> selectXrayServer(XrayServer server) async {
    _selectedXrayServer = server;
    _xrayFreeGroupSelected = false;
    await _xrayService.setSelectedId(server.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('xray_free_group_selected', false);
    notifyListeners();
  }

  /// Select the locked free group as the connection target (no specific
  /// server). On connect, the group is delay-tested and the fastest working
  /// server is used automatically.
  Future<void> selectXrayFreeGroup() async {
    _xrayFreeGroupSelected = true;
    _selectedXrayServer = null;
    await _xrayService.setSelectedId(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('xray_free_group_selected', true);
    notifyListeners();
  }

  /// Refresh the locked free subscription group from the server.
  /// [force] ignores the throttle window. Returns number of free servers.
  Future<int> refreshXrayFreeGroup({bool force = false}) async {
    _xrayRefreshing = true;
    notifyListeners();
    try {
      final count = await _xrayService.refreshFreeGroup(
        minInterval: force ? null : const Duration(hours: 6),
      );
      await loadXrayServers();
      return count;
    } finally {
      _xrayRefreshing = false;
      notifyListeners();
    }
  }

  /// Read the concurrent delay-test count from settings (default 30, max 300).
  Future<int> getXrayConcurrentTests() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('xray_concurrent_tests') ?? 300;
    return v.clamp(1, 300);
  }

  Future<String> _buildDelayConfig(XrayServer server) async {
    final prefs = await SharedPreferences.getInstance();
    final fragEnabled = prefs.getBool('xray_fragment') ?? false;
    final fragLength = prefs.getString('xray_fragment_length') ?? '1-3';
    final fragInterval = prefs.getString('xray_fragment_interval') ?? '10-20';
    return XrayConfigBuilder.buildForDelayTest(
      server,
      fragmentEnabled: fragEnabled,
      fragmentLength: fragLength,
      fragmentInterval: fragInterval,
    );
  }

  /// Real-delay test (v2rayNG style) for a single server. Returns ms or -1.
  /// Persists the measured ping and updates the in-memory list.
  Future<int> measureXrayDelay(XrayServer server) async {
    _xrayTestingIds.add(server.id);
    notifyListeners();
    try {
      final config = await _buildDelayConfig(server);
      final delay = await XrayConnection.measureDelay(config);
      await _xrayService.updatePing(server.id, delay >= 0 ? delay : -1);
      _applyPing(server.id, delay >= 0 ? delay : -1);
      return delay;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ measureXrayDelay: $e');
      return -1;
    } finally {
      _xrayTestingIds.remove(server.id);
      notifyListeners();
    }
  }

  void _applyPing(String id, int? ping) {
    final idx = _xrayServers.indexWhere((s) => s.id == id);
    if (idx >= 0) _xrayServers[idx] = _xrayServers[idx].copyWith(ping: ping);
  }

  /// Concurrently delay-test a list of servers in batches sized by the
  /// user's concurrent-test setting (default 30, up to 300). Updates pings
  /// live so the UI reflects results as they arrive.
  Future<void> testXrayServers(List<XrayServer> servers) async {
    if (servers.isEmpty || _xrayGroupTesting) return;
    _xrayGroupTesting = true;
    notifyListeners();
    try {
      final batchSize = await getXrayConcurrentTests();
      final results = <String, int?>{};
      for (var i = 0; i < servers.length; i += batchSize) {
        final batch = servers.sublist(
            i, (i + batchSize).clamp(0, servers.length));
        for (final s in batch) {
          _xrayTestingIds.add(s.id);
        }
        notifyListeners();
        await Future.wait(batch.map((s) async {
          try {
            final config = await _buildDelayConfig(s);
            final delay = await XrayConnection.measureDelay(config);
            final ping = delay >= 0 ? delay : -1;
            results[s.id] = ping;
            _applyPing(s.id, ping);
          } catch (_) {
            results[s.id] = -1;
            _applyPing(s.id, -1);
          } finally {
            _xrayTestingIds.remove(s.id);
          }
        }));
        notifyListeners();
      }
      await _xrayService.updatePings(results);
    } finally {
      _xrayGroupTesting = false;
      notifyListeners();
    }
  }

  /// Test the whole locked free group concurrently.
  Future<void> testXrayFreeGroup() async {
    final group = _xrayServers.where((s) => s.isLocked).toList();
    await testXrayServers(group);
  }

  /// Concurrently test the locked free group and return the fastest working
  /// server (lowest positive ping). Returns null if none respond.
  Future<XrayServer?> _pickFastestFreeServer() async {
    final group = _xrayServers.where((s) => s.isLocked).toList();
    if (group.isEmpty) return null;
    await testXrayServers(group);
    final working = _xrayServers
        .where((s) => s.isLocked && (s.ping ?? -1) > 0)
        .toList()
      ..sort((a, b) => (a.ping ?? 999999).compareTo(b.ping ?? 999999));
    return working.isNotEmpty ? working.first : null;
  }

  /// Connect using the real Xray core (libv2ray / v2rayNG) with TLS
  /// ClientHello fragmentation enabled.
  Future<void> _connectXray() async {
    final hasFreeGroup = _xrayServers.any((s) => s.isLocked);
    if (_selectedXrayServer == null && !(_xrayFreeGroupSelected && hasFreeGroup)) {
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please add and select an Xray server first';
      notifyListeners();
      return;
    }

    try {
      _status = VpnConnectionStatus.connecting;
      notifyListeners();

      // Only when the WHOLE free group is selected (not a specific server),
      // test the group concurrently and connect to the fastest. If the user
      // manually picked a specific server, connect to exactly that one.
      if (_xrayFreeGroupSelected && _selectedXrayServer == null) {
        final fastest = await _pickFastestFreeServer();
        if (fastest != null) {
          _selectedXrayServer = fastest;
          await _xrayService.setSelectedId(fastest.id);
        } else {
          _status = VpnConnectionStatus.error;
          _errorMessage = 'No working free server found. Try again later.';
          notifyListeners();
          return;
        }
      }

      // Read fragment settings (default OFF).
      final prefs = await SharedPreferences.getInstance();
      final fragEnabled = prefs.getBool('xray_fragment') ?? false;
      final fragLength = prefs.getString('xray_fragment_length') ?? '1-3';
      final fragInterval = prefs.getString('xray_fragment_interval') ?? '10-20';

      // Request VPN permission.
      final granted = await XrayConnection.requestPermission();
      if (!granted) {
        _status = VpnConnectionStatus.error;
        _errorMessage = 'VPN permission denied';
        notifyListeners();
        return;
      }

      // Build the Xray JSON config (incl. TLS ClientHello fragment outbound).
      final configJson = XrayConfigBuilder.build(
        _selectedXrayServer!,
        fragmentEnabled: fragEnabled,
        fragmentLength: fragLength,
        fragmentInterval: fragInterval,
      );

      if (kDebugMode) {
        debugPrint('🚀 Connecting Xray: ${_selectedXrayServer!.remark} '
            '(${_selectedXrayServer!.protocol}) fragment=$fragEnabled');
      }

      final connected = await XrayConnection.connect(configJson);
      if (connected) {
        _status = VpnConnectionStatus.connected;
        _connectedServer = null; // Xray mode
        _errorMessage = null;
        _startDurationTimer();
      } else {
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Failed to start Xray core';
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Xray connect failed: $e');
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
        // ✅ توقف تایمرهای پینگ و مدت زمان برای حالت DNS
        _stopPingTimer();
        _stopDurationTimer();
        _connectionDuration = Duration.zero;
        // ✅ ریست شمارنده‌های ترافیک
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
        _dnsBaselineRxBytes = -1;
        _dnsBaselineTxBytes = -1;
      } else if (_selectedProtocol == 'openvpn') {
        await OpenVpnConnection.disconnect();
        if (kDebugMode) {
          debugPrint('🔌 Disconnecting OpenVPN...');
        }
      } else if (_selectedProtocol == 'slowdns') {
        await SlowDnsConnection.disconnect();
        if (kDebugMode) {
          debugPrint('🔌 Disconnecting Slow DNS...');
        }
      } else if (_selectedProtocol == 'xray') {
        await XrayConnection.disconnect();
        _stopDurationTimer();
        _connectionDuration = Duration.zero;
        if (kDebugMode) {
          debugPrint('🔌 Disconnecting Xray...');
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

  /// Load Slow DNS configs from storage
  Future<void> loadSlowDnsConfigs() async {
    try {
      _slowDnsConfigs = await _slowDnsService.loadConfigs();

      final selectedName = await _slowDnsService.getSelectedConfigName();
      if (selectedName != null && _slowDnsConfigs.isNotEmpty) {
        try {
          _selectedSlowDnsConfig = _slowDnsConfigs.firstWhere(
            (config) => config.name == selectedName,
          );
        } catch (_) {
          _selectedSlowDnsConfig = _slowDnsConfigs.first;
        }
      }

      notifyListeners();

      if (kDebugMode) {
        debugPrint('✅ Loaded ${_slowDnsConfigs.length} Slow DNS configs');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load Slow DNS configs: $e');
      }
    }
  }

  /// Add a Slow DNS config
  Future<bool> addSlowDnsConfig(SlowDnsConfig config) async {
    final success = await _slowDnsService.addConfig(config);
    if (success) {
      await loadSlowDnsConfigs();
    }
    return success;
  }

  /// Remove a Slow DNS config by name
  Future<void> removeSlowDnsConfig(String name) async {
    await _slowDnsService.removeConfig(name);
    if (_selectedSlowDnsConfig?.name == name) {
      _selectedSlowDnsConfig = null;
    }
    await loadSlowDnsConfigs();
  }

  /// Select a Slow DNS config (without connecting)
  Future<void> selectSlowDnsConfig(SlowDnsConfig config) async {
    _selectedSlowDnsConfig = config;
    await _slowDnsService.setSelectedConfig(config.name);
    notifyListeners();

    if (kDebugMode) {
      debugPrint('✅ Slow DNS Config Selected: ${config.name}');
    }
  }

  /// Select a Slow DNS config and connect
  Future<void> selectSlowDnsConfigAndConnect(SlowDnsConfig config) async {
    await selectSlowDnsConfig(config);
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
