import 'dart:async';
import 'dart:io';
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
  // نام گروهی که کاربر به‌عنوان مقصد انتخاب کرده (بدون انتخاب یک سرور مشخص).
  // در این حالت موقع اتصال، آن گروه تست و به بهترین سرورش وصل می‌شویم.
  String? _selectedXrayGroup;
  String? get selectedXrayGroup => _selectedXrayGroup;

  // The server actually in use this session (for a group target it's the one
  // picked as fastest; for a manual pick it equals _selectedXrayServer). Used
  // for the home "active config" label and session ping — NOT persisted.
  XrayServer? _activeXrayServer;
  XrayServer? get activeXrayServer => _activeXrayServer ?? _selectedXrayServer;
  bool get xrayFreeGroupSelected => _selectedXrayGroup != null;
  bool xrayGroupSelectedFor(String group) => _selectedXrayGroup == group;
  // ids of servers currently being delay-tested (for spinner UI)
  final Set<String> _xrayTestingIds = {};
  Set<String> get xrayTestingIds => _xrayTestingIds;
  // group names currently running a delay test (per-group spinner)
  final Set<String> _xrayTestingGroups = {};
  bool xrayGroupTestingFor(String group) =>
      _xrayTestingGroups.contains(group);
  bool _xrayGroupTesting = false;
  bool get xrayGroupTesting => _xrayGroupTesting;
  bool _xrayRefreshing = false;
  bool get xrayRefreshing => _xrayRefreshing;

  // Monotonic token bumped on every Xray connect start AND on disconnect. An
  // in-flight Xray connect (which may spend seconds delay-testing a whole
  // group) captures its token and bails out the moment the token changes — that
  // is what makes "tap power to cancel while connecting" actually stop the
  // group test and NOT connect afterwards.
  int _xrayConnectGen = 0;

  // Per-group refresh spinner (updating a single subscription link).
  final Set<String> _xrayRefreshingGroups = {};
  bool xrayGroupRefreshingFor(String group) =>
      _xrayRefreshingGroups.contains(group);
  
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

  /// Set by the UI. When an OpenVPN config REQUIRES username/password auth but
  /// none were supplied at import time, the connect path calls this so the UI
  /// can prompt the user for credentials (exactly like the official OpenVPN
  /// app, which asks at connect time). Returning null means the user cancelled
  /// → the connection is aborted. Returning a (user, pass) pair injects them.
  Future<({String username, String password})?> Function(OpenVpnConfig config)?
      onOpenVpnCredentialsRequired;

  List<VpnServer> _servers = [];
  VpnServer? _selectedServer;
  VpnServer? _connectedServer;
  VpnConnectionStatus _status = VpnConnectionStatus.disconnected;
  bool _isLoadingServers = false;
  String? _errorMessage;
  Timer? _errorAutoClearTimer;
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

  // Xray traffic polling (proxy uplink/downlink from the core)
  Timer? _xrayTrafficTimer;

  /// Auto-clear any error message 10 seconds after it appears, so stale errors
  /// never linger on screen (even after a successful reconnect). Called on
  /// every notifyListeners via the override below.
  void _syncErrorAutoClear() {
    final hasError = _errorMessage != null && _errorMessage!.isNotEmpty;
    if (hasError) {
      if (_errorAutoClearTimer == null || !_errorAutoClearTimer!.isActive) {
        _errorAutoClearTimer = Timer(const Duration(seconds: 10), () {
          _errorMessage = null;
          // If we're still sitting on an error state, drop back to disconnected.
          if (_status == VpnConnectionStatus.error) {
            _status = VpnConnectionStatus.disconnected;
          }
          notifyListeners();
        });
      }
    } else {
      _errorAutoClearTimer?.cancel();
      _errorAutoClearTimer = null;
    }
  }

  @override
  void notifyListeners() {
    _syncErrorAutoClear();
    super.notifyListeners();
  }

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
    // بارگیری پروتکل انتخابی و در صورت نیاز اتصال خودکار به آخرین سرور OpenVPN
    _startupRestore();
    // بارگیری سرورهای ایکس‌ری
    loadXrayServers();
  }

  /// On launch: restore the selected protocol and load the saved OpenVPN
  /// configs so the LAST selected config is remembered/preselected. We do NOT
  /// auto-connect — the user must press the power button to connect.
  Future<void> _startupRestore() async {
    await loadSelectedProtocol();
    try {
      await loadOpenVpnConfigs();
    } catch (_) {}
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
    
    // Apply the desired Xray default settings + wipe any stale ping results
    // from a previous session, THEN load/test servers (awaited so the ping
    // wipe finishes before anything reloads the stored servers).
    _applyXrayStartupState().whenComplete(_loadAndTestServers);
  }

  /// On every app launch: (1) force the intended Xray defaults — auto
  /// concurrent testing ON and fragment OFF — and (2) clear any pings that were
  /// persisted from a previous session so the user never sees stale results.
  /// Pings are only meaningful for the current session/connection.
  Future<void> _applyXrayStartupState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // (1) One-time default enforcement (both new and existing users). Runs
      // once per install unless the flag is missing.
      final applied = prefs.getBool('xray_defaults_v146') ?? false;
      if (!applied) {
        await prefs.setBool('xray_auto_concurrent', true); // auto-detect ON
        await prefs.setBool('xray_fragment', false); // fragment OFF
        await prefs.setBool('xray_defaults_v146', true);
      }

      // (2) Clear persisted pings so old (days-old) results don't linger. A
      // fresh test must be taken again this session. ping is mutable, so set it
      // directly (copyWith can't null it out).
      await _xrayService.clearAllPings();
      for (final s in _xrayServers) {
        s.ping = null;
      }
      _currentPing = null;
      notifyListeners();
    } catch (_) {}
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
      if (_selectedProtocol == 'direct_dns' ||
          _selectedProtocol == 'slowdns' ||
          _selectedProtocol == 'xray' ||
          _selectedProtocol == 'openvpn') {
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

  // Xray traffic: poll cumulative proxy up/down bytes from the running core
  // (same source v2rayNG uses) and feed the shared data-usage counters.
  void _startXrayTraffic() {
    _stopXrayTraffic();
    _totalDownloadBytes = 0;
    _totalUploadBytes = 0;
    _xrayTrafficTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!isConnected || _selectedProtocol != 'xray') {
        timer.cancel();
        return;
      }
      try {
        final stats = await XrayConnection.queryStats();
        _totalUploadBytes = stats['uplink'] ?? 0;
        _totalDownloadBytes = stats['downlink'] ?? 0;
        notifyListeners();
      } catch (_) {}
    });
  }

  void _stopXrayTraffic() {
    _xrayTrafficTimer?.cancel();
    _xrayTrafficTimer = null;
  }

  // Ping timer - every 3 seconds
  // Xray ping is MANUAL (tap-to-ping), not an automatic 3s timer. This flag is
  // true until the user taps the ping the first time after connecting, so the
  // UI can show a "click to ping" hint only once.
  bool _xrayPingAwaitingFirstTap = false;
  bool get xrayPingAwaitingFirstTap => _xrayPingAwaitingFirstTap;
  bool _xrayPinging = false;
  bool get xrayPinging => _xrayPinging;

  void _startPingTimer() {
    _stopPingTimer();

    // Xray: NO automatic timer — the user taps to ping (see manualXrayPing).
    // Show the "click to ping" hint until the first tap.
    if (_selectedProtocol == 'xray') {
      _xrayPingAwaitingFirstTap = true;
      _currentPing = null;
      _pingFailed = false;
      notifyListeners();
      return;
    }

    // Other protocols: keep the automatic 3-second ping.
    _updateCurrentPing();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _updateCurrentPing();
    });
  }

  /// Manual, tap-triggered ping for Xray. Runs a single real-delay measurement
  /// each time the user taps the ping indicator on the home screen.
  Future<void> manualXrayPing() async {
    if (_selectedProtocol != 'xray') return;
    if (_xrayPinging) return; // ignore rapid double taps
    _xrayPingAwaitingFirstTap = false;
    _xrayPinging = true;
    notifyListeners();
    try {
      await _updateCurrentPing();
    } finally {
      _xrayPinging = false;
      notifyListeners();
    }
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _currentPing = null;
    _xrayPingAwaitingFirstTap = false;
    _xrayPinging = false;
  }

  Future<void> _updateCurrentPing() async {
    // Xray mode: real delay through the active proxy config (v2rayNG style),
    // measured against gstatic's generate_204 like the v2ray app uses.
    if (_selectedProtocol == 'xray') {
      final server = activeXrayServer;
      if (server == null) {
        _currentPing = null;
        _pingFailed = true;
        notifyListeners();
        return;
      }
      try {
        _pingFailed = false;
        final config = await _buildDelayConfig(server);
        final testUrl = await getXrayTestUrl();
        final delay = await XrayConnection.measureDelay(
          config,
          url: testUrl,
        ).timeout(const Duration(seconds: 6), onTimeout: () => -1);
        if (delay >= 0) {
          _currentPing = delay;
          _pingFailed = false;
        } else {
          _currentPing = null;
          _pingFailed = true;
        }
      } catch (_) {
        _currentPing = null;
        _pingFailed = true;
      }
      notifyListeners();
      return;
    }

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
    
    // OpenVPN mode: TCP-ping the config's remote host:port (the tunnel is up,
    // so this round-trips through it — a good live latency indicator).
    if (_selectedProtocol == 'openvpn') {
      final cfg = _selectedOpenVpnConfig;
      final host = cfg?.serverAddress;
      final port = int.tryParse(cfg?.serverPort ?? '') ?? 1194;
      if (host == null || host.isEmpty) {
        _currentPing = null;
        _pingFailed = true;
        notifyListeners();
        return;
      }
      try {
        _pingFailed = false;
        final sw = Stopwatch()..start();
        final socket = await Socket.connect(host, port,
                timeout: const Duration(seconds: 5))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        socket.destroy();
        _currentPing = sw.elapsedMilliseconds;
        _pingFailed = false;
      } catch (_) {
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
  ///
  /// [forceBypassCert] — set when the user confirmed "connect anyway" after an
  /// OpenVPN certificate warning; passed through to the OpenVPN connect path.
  Future<void> connect({bool forceBypassCert = false}) async {
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
      await _connectOpenVpn(forceBypassCert: forceBypassCert);
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

  /// Connect via OpenVPN. Keeps retrying every 4 seconds (restarting the whole
  /// connect from scratch, silently — no UI churn) until it either connects OR
  /// hits a HARD auth failure (wrong user/pass). The client cert requirement is
  /// always bypassed (the user has already consented once).
  Future<void> _connectOpenVpn({bool forceBypassCert = false}) async {
    // Apply the global Traffic Compression toggle before building the config.
    try {
      final prefs = await SharedPreferences.getInstance();
      OpenVpnConfig.trafficCompressionEnabled =
          prefs.getBool('traffic_compression') ?? false;
    } catch (_) {}

    if (_selectedOpenVpnConfig == null) {
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please select an OpenVPN config first';
      notifyListeners();
      if (kDebugMode) debugPrint('❌ No OpenVPN config selected');
      return;
    }

    // ── Prompt for credentials at connect time (like the official app) ──
    // If the config requires username/password auth but none were entered at
    // import time (and none are embedded in the file), ask the user NOW rather
    // than firing a doomed connection that just retries forever.
    final cfg = _selectedOpenVpnConfig!;
    final hasUser = (cfg.effectiveUsername ?? '').isNotEmpty;
    final hasPass = (cfg.effectivePassword ?? '').isNotEmpty;
    if (cfg.requiresAuth && (!hasUser || !hasPass)) {
      final cb = onOpenVpnCredentialsRequired;
      if (cb != null) {
        final creds = await cb(cfg);
        if (creds == null) {
          // User cancelled the credentials prompt → abort cleanly.
          _status = VpnConnectionStatus.disconnected;
          notifyListeners();
          return;
        }
        // Persist the entered credentials on the config so subsequent
        // connects (and the retry loop) reuse them.
        final updated = OpenVpnConfig(
          name: cfg.name,
          config: cfg.config,
          username: creds.username,
          password: creds.password,
          addedAt: cfg.addedAt,
        );
        _selectedOpenVpnConfig = updated;
        try {
          await _openVpnService.updateConfig(updated);
        } catch (_) {}
        final idx = _openVpnConfigs.indexWhere((c) => c.name == cfg.name);
        if (idx >= 0) _openVpnConfigs[idx] = updated;
      }
    }

    // Tear down any prior/stale native session first.
    try {
      await OpenVpnConnection.disconnect();
    } catch (_) {}

    // Clear the session-sticky auth-failed flag EXACTLY once, now that this is
    // a fresh user-initiated connection. (The internal retry loop must NOT
    // clear it, so a late auth-failure isn't lost between attempts.)
    OpenVpnConnection.beginSession();

    _status = VpnConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    // The instant the native core reports an auth failure, stop the whole
    // retry cycle and surface the error — like the official OpenVPN app.
    // `_finishCurrentAttempt` lets the auth callback complete the in-flight
    // attempt's completer immediately (so we don't wait for the 4s watchdog).
    bool authAborted = false;
    void Function(bool)? finishCurrentAttempt;
    OpenVpnConnection.onAuthFailed = () {
      authAborted = true;
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Authentication failed. Wrong username or password.';
      _stopDurationTimer();
      _stopPingTimer();
      notifyListeners();
      finishCurrentAttempt?.call(false);
    };

    // Live traffic counters (persist across retries).
    OpenVpnConnection.onByteCount = (int bytesIn, int bytesOut) {
      _totalDownloadBytes = bytesIn;
      _totalUploadBytes = bytesOut;
      notifyListeners();
    };

    int attempt = 0;
    while (true) {
      attempt++;

      // Auth failed at any point → stop the whole cycle immediately.
      if (authAborted || OpenVpnConnection.authFailed) {
        OpenVpnConnection.onAuthFailed = null;
        OpenVpnConnection.onStageChanged = null;
        // Kill the native tunnel so ics-openvpn's own connect-retry does NOT
        // keep reconnecting behind our back and flip the UI back to
        // "connecting". (resetAuthState:true — this is a terminal stop.)
        try {
          await OpenVpnConnection.disconnect();
        } catch (_) {}
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Authentication failed. Wrong username or password.';
        _stopDurationTimer();
        _stopPingTimer();
        notifyListeners();
        return;
      }

      // Stop if the user cancelled meanwhile.
      if (_status == VpnConnectionStatus.disconnected ||
          _status == VpnConnectionStatus.disconnecting) {
        OpenVpnConnection.onAuthFailed = null;
        OpenVpnConnection.onStageChanged = null;
        return;
      }

      if (kDebugMode) {
        debugPrint('🚀 OpenVPN connect attempt $attempt: '
            '${_selectedOpenVpnConfig!.name}');
      }

      final completer = Completer<bool>();
      final int myGen = OpenVpnConnection.generation + 1;

      void finish(bool ok) {
        if (!completer.isCompleted) completer.complete(ok);
      }

      // Expose this attempt's finisher to the auth-failure callback.
      finishCurrentAttempt = finish;

      OpenVpnConnection.onStageChanged = (VPNStage? stage) {
        if (OpenVpnConnection.generation != myGen) return;
        if (kDebugMode) debugPrint('🔵 OpenVPN Stage: $stage');

        if (stage == VPNStage.connected) {
          _status = VpnConnectionStatus.connected;
          _connectedServer = null;
          _errorMessage = null;
          _startDurationTimer();
          _startPingTimer();
          notifyListeners();
          finish(true);
        } else if (stage == VPNStage.error || stage == VPNStage.denied) {
          finish(false);
        } else if (stage == VPNStage.disconnected) {
          // ignored — spurious ones filtered natively
        } else {
          // Keep the UI on "connecting" during the whole retry cycle.
          if (_status != VpnConnectionStatus.connected) {
            _status = VpnConnectionStatus.connecting;
            notifyListeners();
          }
        }
      };

      // Per-attempt watchdog: if the config hasn't reached "connected" within
      // 4s, time out, fully tear the tunnel down and restart from scratch —
      // silently (the UI stays on "connecting").
      final watchdog = Timer(const Duration(seconds: 4), () => finish(false));

      try {
        await OpenVpnConnection.connect(
          _selectedOpenVpnConfig!,
          // Always bypass the cert requirement (user consented once).
          forceBypassCert: true,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ attempt $attempt threw: $e');
        finish(false);
      }

      final ok = await completer.future;
      watchdog.cancel();

      if (ok) {
        OpenVpnConnection.onAuthFailed = null;
        if (kDebugMode) debugPrint('✅ OpenVPN connected on attempt $attempt');
        return;
      }

      // HARD auth failure → stop immediately and tell the user.
      if (authAborted || OpenVpnConnection.authFailed) {
        OpenVpnConnection.onAuthFailed = null;
        OpenVpnConnection.onStageChanged = null;
        // Kill the native tunnel so its own connect-retry can't restart the
        // "connecting" loop after we've decided auth failed.
        try {
          await OpenVpnConnection.disconnect();
        } catch (_) {}
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Authentication failed. Wrong username or password.';
        _stopDurationTimer();
        _stopPingTimer();
        notifyListeners();
        if (kDebugMode) debugPrint('🛑 Auth failed — stop retrying');
        return;
      }

      // User cancelled during the attempt.
      if (_status == VpnConnectionStatus.disconnected ||
          _status == VpnConnectionStatus.disconnecting) {
        OpenVpnConnection.onAuthFailed = null;
        return;
      }

      // Reset the native session and retry after 4s — silently (UI stays on
      // "connecting", no error shown). Do NOT clear the auth-failed state here,
      // so a wrong-password detected late (during teardown) still aborts.
      try {
        await OpenVpnConnection.disconnect(resetAuthState: false);
      } catch (_) {}
      if (authAborted || OpenVpnConnection.authFailed) {
        OpenVpnConnection.onAuthFailed = null;
        OpenVpnConnection.onStageChanged = null;
        try {
          await OpenVpnConnection.disconnect();
        } catch (_) {}
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Authentication failed. Wrong username or password.';
        _stopDurationTimer();
        _stopPingTimer();
        notifyListeners();
        return;
      }
      _status = VpnConnectionStatus.connecting;
      notifyListeners();
      // Short pause before the next attempt (UI still shows "connecting").
      await Future.delayed(const Duration(milliseconds: 800));
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
    final prefs = await SharedPreferences.getInstance();
    _selectedXrayGroup = prefs.getString('xray_selected_group');
    // If the selected group no longer exists, drop the selection.
    if (_selectedXrayGroup != null &&
        !_xrayServers.any((s) => s.group == _selectedXrayGroup)) {
      _selectedXrayGroup = null;
      await prefs.remove('xray_selected_group');
    }
    // When a whole GROUP is the target, there must be NO fixed selected server:
    // each connect re-tests the group and picks the current fastest. A specific
    // server is only remembered when the user manually chose one.
    if (_selectedXrayGroup != null) {
      _selectedXrayServer = null;
    } else {
      _selectedXrayServer = await _xrayService.getSelectedServer();
    }
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
  /// the group selection. If the VPN is already connected via Xray, cleanly
  /// switch: fully disconnect, then reconnect to the new server.
  Future<void> selectXrayServer(XrayServer server) async {
    _selectedXrayServer = server;
    _selectedXrayGroup = null;
    await _xrayService.setSelectedId(server.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('xray_selected_group');
    notifyListeners();
    await _reconnectXrayIfActive();
  }

  /// When Xray is the active protocol and currently connected/connecting,
  /// cleanly tear down the tunnel and bring it back up on the newly-selected
  /// server. No-op otherwise.
  Future<void> _reconnectXrayIfActive() async {
    if (_selectedProtocol != 'xray') return;
    if (_status != VpnConnectionStatus.connected &&
        _status != VpnConnectionStatus.connecting) {
      return;
    }
    if (_selectedXrayServer == null) return;
    // Full clean disconnect first.
    await disconnect();
    // Small settle delay so the old tunnel/core fully tears down.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Bring it back up on the new server.
    await connect();
  }

  /// Select a whole group as the connection target (no specific server). On
  /// connect, that group is delay-tested and the fastest working server used.
  Future<void> selectXrayGroup(String group) async {
    _selectedXrayGroup = group;
    _selectedXrayServer = null;
    await _xrayService.setSelectedId(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('xray_selected_group', group);
    notifyListeners();
  }

  /// Backwards-compatible helper: select the built-in free group.
  Future<void> selectXrayFreeGroup() =>
      selectXrayGroup(XrayServer.freeGroup);

  /// Subscription URL management (Xray settings).
  Future<List<String>> getXraySubUrls() => _xrayService.getSubUrls();

  /// Custom names the user assigned to each Xray subscription URL.
  Future<Map<String, String>> getXraySubNames() => _xrayService.getSubNames();

  /// The name currently shown for a sub URL (custom name or host fallback).
  Future<String> xraySubDisplayName(String url) =>
      _xrayService.groupNameForUrlAsync(url);

  /// Set/clear a custom display name for a subscription URL and refresh so the
  /// server list reflects the new group name.
  Future<void> setXraySubName(String url, String name) async {
    await _xrayService.setSubName(url, name);
    await loadXrayServers();
    notifyListeners();
  }

  /// Accepts an http subscription URL OR raw share link(s). Returns true if
  /// anything was added. Refreshes so the new entries show in the list.
  /// If [name] is given (and the input was a single http subscription URL),
  /// that custom name is assigned to the subscription right away.
  Future<bool> addXraySubUrl(String url, {String? name}) async {
    final trimmed = url.trim();
    final added = await _xrayService.addSubInput(trimmed);
    if (added > 0) {
      // Assign the custom name to the URL BEFORE refreshing, so the servers
      // are parsed straight into the correctly-named group.
      if (name != null &&
          name.trim().isNotEmpty &&
          trimmed.startsWith('http') &&
          !trimmed.contains(RegExp(r'[\r\n]'))) {
        await _xrayService.setSubName(trimmed, name.trim());
      }
      await refreshXrayFreeGroup(force: true);
    }
    return added > 0;
  }

  Future<void> removeXraySubUrl(String url) async {
    await _xrayService.removeSubUrl(url);
    await refreshXrayFreeGroup(force: true);
  }

  /// Change an existing subscription's URL (its custom name is kept). Refreshes
  /// so the new URL's servers are fetched. Returns false if the new URL is
  /// invalid or a duplicate.
  Future<bool> changeXraySubUrl(String oldUrl, String newUrl) async {
    final ok = await _xrayService.changeSubUrl(oldUrl, newUrl);
    if (ok) await refreshXrayFreeGroup(force: true);
    return ok;
  }

  /// Refresh the locked free subscription group from the server.
  /// [force] ignores the throttle window. Returns number of free servers.
  Future<int> refreshXrayFreeGroup(
      {bool force = false, bool builtInOnly = false}) async {
    _xrayRefreshing = true;
    notifyListeners();
    try {
      final count = await _xrayService.refreshFreeGroup(
        minInterval: force ? null : const Duration(hours: 6),
        builtInOnly: builtInOnly,
      );
      await loadXrayServers();
      return count;
    } finally {
      _xrayRefreshing = false;
      notifyListeners();
    }
  }

  /// Refresh a SINGLE subscription group: wipe its servers and re-download +
  /// re-parse them from that sub link's URL. Returns servers loaded, or -1 if
  /// the group can't be refreshed (not URL-backed / fetch failed).
  Future<int> refreshXrayOneGroup(String groupKey) async {
    if (_xrayRefreshingGroups.contains(groupKey)) return -1;
    _xrayRefreshingGroups.add(groupKey);
    notifyListeners();
    try {
      final count = await _xrayService.refreshOneGroup(groupKey);
      await loadXrayServers();
      return count;
    } finally {
      _xrayRefreshingGroups.remove(groupKey);
      notifyListeners();
    }
  }

  /// Read the concurrent delay-test count. When "auto" is on, pick a value
  /// from the device's CPU cores so stronger phones test more in parallel;
  /// otherwise use the user's manual slider value. Capped at 1..300.
  Future<int> getXrayConcurrentTests() async {
    final prefs = await SharedPreferences.getInstance();
    final auto = prefs.getBool('xray_auto_concurrent') ?? true;
    if (auto) {
      // ~24 parallel tests per CPU core (I/O-bound network probes), clamped.
      final cores = Platform.numberOfProcessors;
      return (cores * 24).clamp(30, 300);
    }
    final v = prefs.getInt('xray_concurrent_tests') ?? 300;
    return v.clamp(1, 300);
  }

  /// How many times each server is re-tested when connecting to a whole group,
  /// so the app can pick the best server more reliably. Range 1..5, default 1.
  Future<int> getXrayGroupTestRounds() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt('xray_group_test_rounds') ?? 1;
    return v.clamp(1, 5);
  }

  Future<void> setXrayGroupTestRounds(int rounds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('xray_group_test_rounds', rounds.clamp(1, 5));
    notifyListeners();
  }

  /// Default delay-test URL. Used by the server-list delay test and the
  /// 3-second home-screen ping. Changeable from Xray settings.
  static const String defaultXrayTestUrl = 'http://www.google.com/gen_204';

  /// Read the persisted Xray delay-test URL (falls back to the default).
  Future<String> getXrayTestUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('xray_test_url')?.trim();
    if (v == null || v.isEmpty) return defaultXrayTestUrl;
    return v;
  }

  /// Persist the Xray delay-test URL. Empty resets to the default.
  Future<void> setXrayTestUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final v = url.trim();
    if (v.isEmpty) {
      await prefs.remove('xray_test_url');
    } else {
      await prefs.setString('xray_test_url', v);
    }
    notifyListeners();
  }

  Future<String> _buildDelayConfig(XrayServer server) async {
    final prefs = await SharedPreferences.getInstance();
    final fragEnabled = prefs.getBool('xray_fragment') ?? false;
    final fragPackets = prefs.getString('xray_fragment_packets') ?? 'tlshello';
    final fragLength = prefs.getString('xray_fragment_length') ?? '10-20';
    final fragInterval = prefs.getString('xray_fragment_interval') ?? '10-20';
    final fragHost = prefs.getString('xray_fragment_host') ?? '';
    return XrayConfigBuilder.buildForDelayTest(
      server,
      fragmentEnabled: fragEnabled,
      fragmentPackets: fragPackets,
      fragmentLength: fragLength,
      fragmentInterval: fragInterval,
      fragmentHost: fragHost,
    );
  }

  /// Real-delay test (v2rayNG style) for a single server. Returns ms or -1.
  /// Persists the measured ping and updates the in-memory list.
  Future<int> measureXrayDelay(XrayServer server) async {
    _xrayTestingIds.add(server.id);
    notifyListeners();
    try {
      final config = await _buildDelayConfig(server);
      final testUrl = await getXrayTestUrl();
      final delay = await XrayConnection.measureDelay(config, url: testUrl);
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
  /// Concurrently delay-test [servers]. [rounds] (1..5) re-tests every server
  /// that many times and keeps the BEST (lowest positive) ping — used when
  /// connecting to a whole group so the "connect to fastest" choice is more
  /// reliable. Defaults to a single round.
  Future<void> testXrayServers(List<XrayServer> servers,
      {int rounds = 1}) async {
    if (servers.isEmpty || _xrayGroupTesting) return;
    _xrayGroupTesting = true;
    // Snapshot the connect token so a delay-test launched by a group connect
    // stops as soon as the user cancels (disconnect bumps _xrayConnectGen).
    final int testGen = _xrayConnectGen;
    // Mark only the group(s) these servers belong to as "testing" so the
    // spinner shows on the tapped group only, not every group.
    final groups = servers.map((s) => s.group).toSet();
    _xrayTestingGroups.addAll(groups);
    notifyListeners();
    try {
      final batchSize = await getXrayConcurrentTests();
      final testUrl = await getXrayTestUrl();
      final int totalRounds = rounds.clamp(1, 5);
      // Best ping seen per server across all rounds (lower positive = better).
      final results = <String, int?>{};

      // Precompute an id -> index map ONCE. Previously every result did
      // `indexWhere` over the whole list (O(n) each → O(n²) overall), which is
      // the main freeze when a subscription has thousands of servers.
      final indexById = <String, int>{};
      for (var i = 0; i < _xrayServers.length; i++) {
        indexById[_xrayServers[i].id] = i;
      }

      // Merge a fresh measurement into the best-so-far for a server.
      void mergeBest(String id, int ping) {
        final prev = results[id];
        if (ping > 0) {
          // Keep the lowest positive ping.
          if (prev == null || prev <= 0 || ping < prev) results[id] = ping;
        } else {
          // Only record failure if we have no positive result yet.
          if (prev == null) results[id] = -1;
        }
      }

      for (var round = 0; round < totalRounds; round++) {
        for (var i = 0; i < servers.length; i += batchSize) {
          // Abort the whole test if the user cancelled the connect meanwhile.
          if (testGen != _xrayConnectGen) {
            if (kDebugMode) debugPrint('🚫 group delay-test aborted (cancelled)');
            return;
          }
          final batch = servers.sublist(
              i, (i + batchSize).clamp(0, servers.length));
          for (final s in batch) {
            _xrayTestingIds.add(s.id);
          }
          notifyListeners();
          await Future.wait(batch.map((s) async {
            try {
              final config = await _buildDelayConfig(s);
              final delay =
                  await XrayConnection.measureDelay(config, url: testUrl);
              mergeBest(s.id, delay >= 0 ? delay : -1);
            } catch (_) {
              mergeBest(s.id, -1);
            } finally {
              _xrayTestingIds.remove(s.id);
            }
          }));
          // Apply the best-so-far pings in one pass, then a SINGLE notify.
          for (final s in batch) {
            final idx = indexById[s.id];
            if (idx != null && idx < _xrayServers.length) {
              _xrayServers[idx] =
                  _xrayServers[idx].copyWith(ping: results[s.id]);
            }
          }
          notifyListeners();
        }
      }
      await _xrayService.updatePings(results);
      await _sortXrayByPing();
    } finally {
      _xrayGroupTesting = false;
      _xrayTestingGroups.removeAll(groups);
      notifyListeners();
    }
  }

  /// Delay-test EVERY server across ALL groups at once.
  Future<void> testAllXrayGroups() async {
    if (_xrayGroupTesting) return;
    final all = List<XrayServer>.from(_xrayServers);
    await testXrayServers(all);
  }

  /// Sort servers so that lower (better) ping comes first within each group.
  /// Ordering key: working pings ascending, then untested, then failed last.
  /// The new order is persisted so "next server" walks best -> worst.
  Future<void> _sortXrayByPing() async {
    int rank(XrayServer s) {
      final p = s.ping;
      if (p == null) return 1; // untested -> middle
      if (p < 0) return 2; // failed -> last
      return 0; // working -> first
    }

    // Preserve group ordering; only sort servers WITHIN the same group.
    final order = <String, int>{};
    var next = 0;
    for (final s in _xrayServers) {
      order.putIfAbsent(s.group, () => next++);
    }
    _xrayServers.sort((a, b) {
      if (a.group != b.group) {
        return order[a.group]!.compareTo(order[b.group]!);
      }
      final ra = rank(a), rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      return (a.ping ?? 999999).compareTo(b.ping ?? 999999);
    });
    await _xrayService.saveServers(_xrayServers);
    notifyListeners();
  }

  /// Servers of the currently selected group (empty if none selected).
  List<XrayServer> _selectedGroupServers() {
    final g = _selectedXrayGroup;
    if (g == null) return const [];
    return _xrayServers.where((s) => s.group == g).toList();
  }

  /// "Next server": when a whole group is selected, move the selection to the
  /// next server in that (ping-sorted) group. No-op if a specific server was
  /// picked manually.
  Future<void> selectNextFreeServer() async {
    final group = _selectedGroupServers();
    if (group.isEmpty) return;
    // The reference "current" server must be the one that is ACTUALLY active,
    // not just `_selectedXrayServer`. When a whole group is selected, the
    // connect path picks the fastest server into `_activeXrayServer` while
    // `_selectedXrayServer` stays null — so using only `_selectedXrayServer?.id`
    // made the first "Next" tap start from index -1 → 0, i.e. re-select the
    // server we were already on (the classic "first Next does nothing" bug).
    // Prefer the active server's id, then the selected one.
    final curId = _activeXrayServer?.id ?? _selectedXrayServer?.id;
    var idx = group.indexWhere((s) => s.id == curId);
    idx = (idx + 1) % group.length; // wrap around; -1 -> 0
    final next = group[idx];
    _selectedXrayServer = next;
    await _xrayService.setSelectedId(next.id);
    notifyListeners();
    // If connected, cleanly switch the live tunnel to the new server.
    await _reconnectXrayIfActive();
  }

  /// Concurrently test the selected group and return its fastest working
  /// server (lowest positive ping). Returns null if none respond.
  Future<XrayServer?> _pickFastestFreeServer() async {
    final group = _selectedGroupServers();
    if (group.isEmpty) return null;
    final rounds = await getXrayGroupTestRounds();
    await testXrayServers(group, rounds: rounds);
    final g = _selectedXrayGroup;
    final working = _xrayServers
        .where((s) => s.group == g && (s.ping ?? -1) > 0)
        .toList()
      ..sort((a, b) => (a.ping ?? 999999).compareTo(b.ping ?? 999999));
    return working.isNotEmpty ? working.first : null;
  }

  /// Connect using the real Xray core (libv2ray / v2rayNG) with TLS
  /// ClientHello fragmentation enabled.
  Future<void> _connectXray() async {
    final groupHasServers = _selectedXrayGroup != null &&
        _xrayServers.any((s) => s.group == _selectedXrayGroup);
    if (_selectedXrayServer == null && !groupHasServers) {
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please add and select an Xray server first';
      notifyListeners();
      return;
    }

    // Capture this connect attempt's token. If the user taps power to cancel
    // (disconnect) while we're still delay-testing a group, the token changes
    // and every checkpoint below aborts cleanly instead of connecting anyway.
    final int myGen = ++_xrayConnectGen;
    bool cancelled() =>
        myGen != _xrayConnectGen ||
        _status == VpnConnectionStatus.disconnecting ||
        _status == VpnConnectionStatus.disconnected;

    try {
      _status = VpnConnectionStatus.connecting;
      notifyListeners();

      // The server we actually build the config for. For a GROUP target we pick
      // the fastest fresh each connect WITHOUT persisting it as the selected
      // server, so disconnect+reconnect always re-tests. For a manually-picked
      // server we use exactly that one.
      XrayServer? serverToConnect = _selectedXrayServer;
      if (_selectedXrayServer == null && groupHasServers) {
        final fastest = await _pickFastestFreeServer();
        // User cancelled while the group was being tested → stop, do NOT connect.
        if (cancelled()) {
          if (kDebugMode) debugPrint('🚫 Xray connect cancelled during test');
          return;
        }
        if (fastest != null) {
          serverToConnect = fastest; // session-only, NOT persisted
        } else {
          _status = VpnConnectionStatus.error;
          _errorMessage = 'No working server found in this group. Try again.';
          notifyListeners();
          return;
        }
      }

      // Read fragment settings (default OFF).
      final prefs = await SharedPreferences.getInstance();
      final fragEnabled = prefs.getBool('xray_fragment') ?? false;
      final fragPackets = prefs.getString('xray_fragment_packets') ?? 'tlshello';
      final fragLength = prefs.getString('xray_fragment_length') ?? '10-20';
      final fragInterval = prefs.getString('xray_fragment_interval') ?? '10-20';
      final fragHost = prefs.getString('xray_fragment_host') ?? '';
      final trafficCompression = prefs.getBool('traffic_compression') ?? false;

      if (cancelled()) {
        if (kDebugMode) debugPrint('🚫 Xray connect cancelled pre-permission');
        return;
      }

      // Request VPN permission.
      final granted = await XrayConnection.requestPermission();
      if (!granted) {
        _status = VpnConnectionStatus.error;
        _errorMessage = 'VPN permission denied';
        notifyListeners();
        return;
      }

      if (cancelled()) {
        if (kDebugMode) debugPrint('🚫 Xray connect cancelled pre-connect');
        return;
      }

      // Build the Xray JSON config (incl. TLS ClientHello fragment outbound).
      final configJson = XrayConfigBuilder.build(
        serverToConnect!,
        fragmentEnabled: fragEnabled,
        fragmentPackets: fragPackets,
        fragmentLength: fragLength,
        fragmentInterval: fragInterval,
        fragmentHost: fragHost,
        trafficCompression: trafficCompression,
      );

      if (kDebugMode) {
        debugPrint('🚀 Connecting Xray: ${serverToConnect.remark} '
            '(${serverToConnect.protocol}) fragment=$fragEnabled');
      }

      final connected = await XrayConnection.connect(configJson);
      // If the user cancelled meanwhile, tear the just-started tunnel down and
      // stay disconnected instead of flipping to "connected".
      if (cancelled()) {
        if (kDebugMode) debugPrint('🚫 Xray connected late after cancel — tearing down');
        try {
          await XrayConnection.disconnect();
        } catch (_) {}
        return;
      }
      if (connected) {
        _status = VpnConnectionStatus.connected;
        _connectedServer = null; // Xray mode
        _activeXrayServer = serverToConnect; // session-only (for label + ping)
        _errorMessage = null;
        _startDurationTimer();
        _startPingTimer(); // real ping via gstatic generate_204
        _startXrayTraffic(); // poll proxy up/down bytes from the core
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

    // Invalidate any in-flight Xray connect (e.g. a group delay-test in
    // progress) so it aborts instead of connecting after the user cancelled.
    _xrayConnectGen++;

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
        _stopPingTimer();
        _stopDurationTimer();
        _connectionDuration = Duration.zero;
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
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
        _stopPingTimer();
        _stopDurationTimer();
        _stopXrayTraffic();
        _connectionDuration = Duration.zero;
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
        // Drop the session server so a group target re-tests on next connect.
        _activeXrayServer = null;
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
      
      // Load selected config (null-safe: never cast null to OpenVpnConfig).
      final selectedName = await _openVpnService.getSelectedConfigName();
      if (selectedName != null && _openVpnConfigs.isNotEmpty) {
        OpenVpnConfig? match;
        for (final c in _openVpnConfigs) {
          if (c.name == selectedName) {
            match = c;
            break;
          }
        }
        _selectedOpenVpnConfig = match ?? _openVpnConfigs.first;
      } else if (_openVpnConfigs.isEmpty) {
        _selectedOpenVpnConfig = null;
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
  
  /// Select an OpenVPN config WITHOUT connecting. The user connects manually
  /// via the power button afterwards.
  Future<void> selectOpenVpnConfig(OpenVpnConfig config) async {
    _selectedOpenVpnConfig = config;
    await _openVpnService.setSelectedConfig(config.name);
    notifyListeners();
    if (kDebugMode) {
      debugPrint('✅ OpenVPN Config Selected (no auto-connect): ${config.name}');
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

    // 🔴 CRITICAL: connect() bails out immediately if _status is already
    // `connecting` or `connected`. That's exactly why tapping a server did
    // nothing — the user was already connected (to another protocol, another
    // OpenVPN config, or a stale/leftover session). So we ALWAYS tear the
    // current session down first, wait for it to settle, then reset the status
    // to `disconnected` before starting the fresh OpenVPN connection.
    if (_status == VpnConnectionStatus.connected ||
        _status == VpnConnectionStatus.connecting) {
      try {
        await disconnect();
      } catch (_) {}
      // Give the platform a moment to actually tear the tunnel down.
      await Future.delayed(const Duration(milliseconds: 400));
    }
    _status = VpnConnectionStatus.disconnected;
    _errorMessage = null;
    notifyListeners();

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
    _stopXrayTraffic();
    _vpnService.dispose();
    super.dispose();
  }
}
