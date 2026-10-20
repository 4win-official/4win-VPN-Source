import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import '../models/vpn_server.dart';
import '../models/sstp_server_group.dart';
import '../services/sstp_server_store.dart';
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
import '../models/proxy_server.dart';
import '../services/proxy_service.dart';
import '../models/warp_account.dart';
import '../services/warp_service.dart';
import '../services/psiphon_service.dart';
import '../services/retry_policy.dart';
import '../services/connection_logger.dart';
import '../models/mix_strategy.dart';
import '../models/mix_diagnostics.dart';
import '../models/mix_block_exception.dart';
import '../services/mix_strategy_store.dart';
import '../services/mix_config_builder.dart';
import '../services/mix_plan_builder.dart';

// Re-export for convenience
export '../services/vpn_service.dart' show VpnConnectionStatus;
part 'mix_provider.dart';
part 'sstp_provider.dart';
part 'vpn_state_sync.dart';

class VpnProvider with ChangeNotifier, WidgetsBindingObserver {
  static const _vpnStateChannel = MethodChannel('com.forwin.vpn/vpn_state');
  int _vpnStateRevision = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshConnectionState());
    }
  }

  /// Reconcile missed notification actions without starting a connection.
  Future<void> refreshConnectionState() => _refreshNativeVpnState();
  final MixStrategyStore _mixStore = MixStrategyStore();
  List<MixStrategy> _mixStrategies = [];
  String? _selectedMixStrategyId;
  late final Future<void> _mixLoaded;
  Future<void>? _mixOperation;
  int _mixConnectGen = 0;
  Timer? _mixMonitor;
  Timer? _mixDiagnosticsTimer;
  MixDiagnostics? _mixDiagnostics;
  MixDiagnostics? get mixDiagnostics => _mixDiagnostics;
  bool _mixDisposed = false;
  Future<void>? _mixDisconnectOperation;
  List<MixStrategy> get mixStrategies => List.unmodifiable(_mixStrategies);
  String? get selectedMixStrategyId => _selectedMixStrategyId;
  MixStrategy? get selectedMixStrategy => _selectedMixStrategy;
  Future<void> saveMixStrategy(MixStrategy strategy) =>
      _saveMixStrategy(strategy);
  Future<void> deleteMixStrategy(String id) => _deleteMixStrategy(id);
  Future<void> selectMixStrategy(String id) => _selectMixStrategy(id);
  final ServerService _serverService;
  final SstpServerStore _sstpStore;
  List<SstpServerGroup> _sstpGroups = [];
  String _sstpTargetGroup = 'default';
  bool _sstpManualSelection = false;
  bool _sstpSelectionRestored = false;
  bool _sstpGroupTesting = false;
  String? _sstpTestError;
  final Set<String> _sstpTestingServers = <String>{};
  int _sstpTestedCount = 0;
  int _sstpTestTotal = 0;
  int _sstpConnectGen = 0;
  Future<void>? _sstpLoadOperation;
  Future<List<VpnServer>>? _sstpTestOperation;
  Future<bool>? _sstpNativeOperation;
  List<SstpServerGroup> get sstpGroups => List.unmodifiable(_sstpGroups);
  String? get selectedSstpGroup =>
      _sstpManualSelection ? null : _sstpTargetGroup;
  bool get sstpGroupTesting => _sstpGroupTesting;
  bool get sstpRefreshing => _isLoadingServers;
  int get sstpTestedCount => _sstpTestedCount;
  int get sstpTestTotal => _sstpTestTotal;
  String? get sstpTestError => _sstpTestError;
  bool isSstpServerTesting(VpnServer server) =>
      _sstpTestingServers.contains(server.fullAddress);
  Future<void> testSstpServer(String groupId, VpnServer server) =>
      _testSstpServer(groupId, server);
  Future<void> testSstpGroup(String groupId) => _testSstpGroup(groupId);
  Future<void> refreshSstpGroup(String id) => _refreshSstpGroup(id);
  Future<void> addSstpGroup(
    String name,
    String content, {
    String username = 'vpn',
    String password = 'vpn',
  }) => _addSstpGroup(name, content, username: username, password: password);
  Future<void> removeSstpGroup(String id) => _removeSstpGroup(id);
  Future<void> selectSstpGroup(String id) => _selectSstpGroup(id);
  final VpnService _vpnService = VpnService();
  final DnsService _dnsService = DnsService();
  final OpenVpnService _openVpnService = OpenVpnService();
  final SlowDnsService _slowDnsService = SlowDnsService();
  final XrayServerService _xrayService = XrayServerService();
  final ProxyServerService _proxyService = ProxyServerService();
  final PsiphonService _psiphonService = PsiphonService();
  String? _selectedPsiphonServerId;
  int _psiphonSelectionRevision = 0;
  String? get selectedPsiphonServerId => _selectedPsiphonServerId;

  Future<void> selectPsiphonServer(String? id) async {
    if (isConnected || isConnecting) {
      throw StateError('Disconnect before changing the Psiphon server.');
    }
    _psiphonSelectionRevision++;
    _selectedPsiphonServerId = id?.trim().isNotEmpty == true ? id!.trim() : null;
    final prefs = await SharedPreferences.getInstance();
    if (_selectedPsiphonServerId == null) {
      await prefs.remove('psiphon_selected_server_id');
    } else {
      await prefs.setString('psiphon_selected_server_id', _selectedPsiphonServerId!);
    }
    notifyListeners();
  }

  Timer? _psiphonMonitorTimer;
  Timer? _psiphonTrafficTimer;
  Timer? _psiphonLogTimer;
  bool _psiphonLogPumpActive = false;
  bool _psiphonMonitorBusy = false;
  int _psiphonFailCount = 0;
  int _psiphonConnectGen = 0;
  final Set<String> _psiphonLogSeen = <String>{};

  // Expose VPN service for log access
  VpnService get vpnService => _vpnService;

  // Protocol selection: 'sstp', 'direct_dns', 'openvpn', 'slowdns', 'xray',
  // 'proxy' (dedicated SOCKS4/SOCKS5/HTTP proxy protocol) or 'warp'.
  int _slowDnsConnectGen = 0;
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
  // Server ids currently running a direct TCP connect test.
  final Set<String> _xrayTcpTestingIds = {};
  Set<String> get xrayTcpTestingIds => _xrayTcpTestingIds;
  // group names currently running a delay test (per-group spinner)
  final Set<String> _xrayTestingGroups = {};
  final Set<String> _xrayTcpTestingGroups = {};
  bool xrayGroupTestingFor(String group) => _xrayTestingGroups.contains(group);
  bool xrayGroupTcpTestingFor(String group) =>
      _xrayTcpTestingGroups.contains(group);
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

  // ---------- Proxy protocol (dedicated SOCKS4/SOCKS5/HTTP) state ----------
  List<ProxyServer> _proxyServers = [];
  ProxyServer? _selectedProxyServer;
  List<ProxyServer> get proxyServers => _proxyServers;
  ProxyServer? get selectedProxyServer => _selectedProxyServer;
  String? _selectedProxyGroup;
  String? get selectedProxyGroup => _selectedProxyGroup;
  ProxyServer? _activeProxyServer;
  ProxyServer? get activeProxyServer =>
      _activeProxyServer ?? _selectedProxyServer;
  bool get proxyGroupSelected => _selectedProxyGroup != null;
  bool proxyGroupSelectedFor(String group) => _selectedProxyGroup == group;
  final Set<String> _proxyTestingIds = {};
  Set<String> get proxyTestingIds => _proxyTestingIds;
  final Set<String> _proxyTestingGroups = {};
  bool proxyGroupTestingFor(String group) =>
      _proxyTestingGroups.contains(group);
  bool _proxyGroupTesting = false;
  bool get proxyGroupTesting => _proxyGroupTesting;
  bool _proxyRefreshing = false;
  bool get proxyRefreshing => _proxyRefreshing;
  int _proxyConnectGen = 0;
  final Set<String> _proxyRefreshingGroups = {};
  bool proxyGroupRefreshingFor(String group) =>
      _proxyRefreshingGroups.contains(group);

  // WARP (Cloudflare WireGuard). Unlike Xray/Proxy there is no user-picked
  // server list — a single auto-registered device identity is reused across
  // connects, cached in memory after the first successful register/load.
  final WarpService _warpService = WarpService();
  WarpAccount? _warpAccount;
  WarpAccount? get warpAccount => _warpAccount;
  bool _warpRegistering = false;
  bool get warpRegistering => _warpRegistering;
  String? _warpError;
  String? get warpError => _warpError;
  int _warpConnectGen = 0;

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
    if (((_selectedProtocol == 'slowdns' || _selectedProtocol == 'psiphon') &&
            _status == VpnConnectionStatus.error) ||
        (_selectedProtocol == 'psiphon' &&
            _status == VpnConnectionStatus.connecting)) {
      // Its native TUN may deliberately remain a blackhole. Do not disguise
      // blocked traffic as an ordinary disconnected state after ten seconds.
      _errorAutoClearTimer?.cancel();
      _errorAutoClearTimer = null;
      return;
    }
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

  VpnProvider({ServerService? serverService, SstpServerStore? sstpStore})
    : _serverService = serverService ?? ServerService(),
      _sstpStore = sstpStore ?? SstpServerStore(serverService: serverService) {
    WidgetsBinding.instance.addObserver(this);
    _vpnStateChannel.setMethodCallHandler(_onNativeVpnState);
    _mixLoaded = _loadMixStrategies();
    _init();
    // بارگیری پروتکل انتخابی و در صورت نیاز اتصال خودکار به آخرین سرور OpenVPN
    _startupRestore();
    // بارگیری سرورهای ایکس‌ری
    loadXrayServers();
    // بارگیری سرورهای پراکسی
    loadProxyServers();
    // Load any previously-registered WARP identity (no-op if none yet).
    _loadWarpAccount();
  }

  /// Loads a previously-persisted WARP identity, if any, WITHOUT
  /// registering a new one. Registration only happens lazily on first
  /// WARP connect (see [_connectWarp]).
  Future<void> _loadWarpAccount() async {
    try {
      _warpAccount = await _warpService.getAccount();
      if (_warpAccount != null) notifyListeners();
    } catch (_) {}
  }

  /// On launch: restore the selected protocol and load the saved OpenVPN
  /// configs so the LAST selected config is remembered/preselected. We do NOT
  /// auto-connect — the user must press the power button to connect.
  Future<void> _startupRestore() async {
    await loadSelectedProtocol();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_psiphonSelectionRevision == 0) {
        _selectedPsiphonServerId = prefs.getString('psiphon_selected_server_id');
      }
      // One-time migration: Psiphon is the new default protocol. After this
      // migration the user's later protocol choices are preserved normally.
      final migrated = prefs.getBool('psiphon_default_v1') ?? false;
      if (!migrated) {
        _selectedProtocol = 'psiphon';
        await _dnsService.setSelectedProtocol('psiphon');
        await prefs.setBool('psiphon_default_v1', true);
        notifyListeners();
      }
      // One-time migration #2: Xray is now the new default protocol (faster,
      // no bundled Go-runtime overhead beyond what's already shared with
      // WARP). Runs exactly once per install, after the Psiphon migration
      // above, and forces everyone onto 'xray' a single time — mirroring
      // how the Psiphon migration itself was applied. Any protocol choice
      // the user makes AFTER this runs is preserved normally forever.
      final migratedXray = prefs.getBool('xray_default_v1') ?? false;
      if (!migratedXray) {
        _selectedProtocol = 'xray';
        await _dnsService.setSelectedProtocol('xray');
        await prefs.setBool('xray_default_v1', true);
        notifyListeners();
      }
    } catch (_) {}
    try {
      await loadOpenVpnConfigs();
    } catch (_) {}
  }

  void _init() {
    _statusSubscription = _vpnService.statusStream.listen((status) {
      if (_selectedProtocol != 'sstp' || _mixDisposed) return;
      if ((_status == VpnConnectionStatus.disconnecting ||
              _status == VpnConnectionStatus.disconnected) &&
          status != VpnConnectionStatus.disconnected) {
        return;
      }
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
        _errorMessage =
            'SSTP connection failed. Select another server or retry.';
      }

      notifyListeners();
    });

    // Forward SSTP engine logs into the unified connection log so the log
    // viewer shows every protocol (not just Psiphon) in one place.
    try {
      _vpnService.logStream.listen((line) {
        ConnectionLogger.instance.info('sstp', line);
      });
    } catch (_) {}

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
      await _proxyService.clearAllPings();
      for (final s in _proxyServers) {
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
          _selectedProtocol == 'warp' ||
          _selectedProtocol == 'openvpn' ||
          _selectedProtocol == 'psiphon' ||
          _selectedProtocol == 'mix') {
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
    _xrayTrafficTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (!isConnected ||
          (_selectedProtocol != 'xray' &&
              _selectedProtocol != 'proxy' &&
              _selectedProtocol != 'warp' &&
              _selectedProtocol != 'mix')) {
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

    // Xray / WARP: NO automatic timer — the user taps to ping (see
    // manualXrayPing). Both run the same Xray core under the hood, so they
    // share the exact same manual-ping mechanism. Show the "click to ping"
    // hint until the first tap.
    if (_selectedProtocol == 'xray' || _selectedProtocol == 'warp') {
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
    if (_selectedProtocol != 'xray' && _selectedProtocol != 'warp') return;
    if (_xrayPinging) return; // ignore rapid double taps
    _xrayPingAwaitingFirstTap = false;
    _xrayPinging = true;
    // Clear the previous result before every request. This makes repeated
    // taps visible even when the native WARP RTT happens to be unchanged.
    _currentPing = null;
    _pingFailed = false;
    notifyListeners();
    try {
      final started = Stopwatch()..start();
      await _updateCurrentPing();
      // Keep the loading state visible briefly. WARP currently exposes the
      // most recent validated RTT, so a repeated tap can otherwise complete
      // too quickly and look like the tap was ignored when the value is equal.
      final remaining = 220 - started.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
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

    // WARP uses Aether's already-running core. The native measureDelay branch
    // returns the endpoint handshake + HTTP data-plane RTT and never starts a
    // second Xray core.
    if (_selectedProtocol == 'warp') {
      final account = _warpAccount;
      if (account == null) {
        _currentPing = null;
        _pingFailed = true;
        notifyListeners();
        return;
      }
      try {
        // WARP is already running in Aether. Read its validated RTT directly;
        // the generic Xray delay path must not create a temporary core.
        final delay = await XrayConnection.measureWarpDelay().timeout(
          const Duration(seconds: 6),
          onTimeout: () => -1,
        );
        _currentPing = delay >= 0 ? delay : null;
        _pingFailed = delay < 0;
      } catch (_) {
        _currentPing = null;
        _pingFailed = true;
      }
      notifyListeners();
      return;
    }

    // Proxy mode: real delay through the active proxy (open-site style test).
    if (_selectedProtocol == 'proxy') {
      final server = activeProxyServer;
      if (server == null) {
        _currentPing = null;
        _pingFailed = true;
        notifyListeners();
        return;
      }
      try {
        _pingFailed = false;
        final config = XrayConfigBuilder.buildProxyServerDelayTest(server);
        final testUrl = await getProxyTestUrl();
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
        int? ping = await DnsVpnConnection.pingDns(
          dnsIp,
        ).timeout(const Duration(seconds: 6), onTimeout: () => null);
        // در صورت ناموفق بودن native، fallback به روش Dart
        ping ??= await _dnsService
            .testDnsConnectivity(_selectedDnsServer!)
            .timeout(const Duration(seconds: 4), onTimeout: () => null);
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
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 5),
        ).timeout(const Duration(seconds: 5));
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
      final ping = await _serverService
          .testServerConnectivity(_connectedServer!)
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

  /// Load the protected source and saved user groups without testing them.
  Future<void> loadServers({bool forceRefresh = false}) =>
      _loadSstpServers(forceRefresh: forceRefresh);

  /// Test only the current SSTP target, retaining all group members.
  Future<void> testAllServers() async {
    if (_sstpGroups.isEmpty) await loadServers();
    if (_sstpGroups.isEmpty || _sstpGroupTesting) return;
    await _testSstpTarget();
  }

  Future<void> findBestServer() => testAllServers();

  /// Connect to selected or best server (one by one - RESTORED WORKING VERSION)
  ///
  /// [forceBypassCert] — set when the user confirmed "connect anyway" after an
  /// OpenVPN certificate warning; passed through to the OpenVPN connect path.
  Future<void> connect({bool forceBypassCert = false}) async {
    if ((_selectedProtocol == 'mix' || _selectedProtocol == 'sstp') &&
        _status == VpnConnectionStatus.disconnecting)
      return;
    if (_status == VpnConnectionStatus.connecting ||
        _status == VpnConnectionStatus.connected) {
      return;
    }

    final revision = ++_vpnStateRevision;
    final sstpToken = _selectedProtocol == 'sstp' ? ++_sstpConnectGen : null;
    // ⚡ CRITICAL: Set to connecting immediately so user sees feedback
    _status = VpnConnectionStatus.connecting;
    notifyListeners();

    if (_selectedProtocol == 'mix') {
      final operation = _connectMix();
      _mixOperation = operation;
      try {
        await operation;
      } finally {
        if (identical(_mixOperation, operation)) _mixOperation = null;
      }
      return;
    }
    // 🌐 CONNECTION MODE (global). Proxy mode = run a LOCAL proxy on
    // 127.0.0.1:4444 with NO system tunnel / no VPN icon. Only Xray can do that;
    // SSTP / DNS-changer / OpenVPN / SlowDNS are IP-layer tunnel protocols that
    // can ONLY run as a system VPN, so in proxy mode we refuse them with a clear
    // message instead of silently falling back to a full VPN tunnel (which is
    // what made the setting look ignored).
    final modePrefs = await SharedPreferences.getInstance();
    if (_mixDisposed || revision != _vpnStateRevision) return;
    final proxyMode =
        (modePrefs.getString('connection_mode') ?? 'vpn') == 'proxy';
    // Xray, the dedicated Proxy protocol AND WARP all run the Xray core and
    // can serve a local proxy without a system tunnel; every other protocol
    // is an IP-layer VPN and cannot run in connection-mode "proxy".
    if (proxyMode &&
        _selectedProtocol != 'xray' &&
        _selectedProtocol != 'proxy' &&
        _selectedProtocol != 'warp') {
      _status = VpnConnectionStatus.error;
      _errorMessage =
          'Proxy mode only supports Xray. Switch to the Xray protocol, '
          'or turn on VPN mode in Settings to use this protocol.';
      notifyListeners();
      return;
    }

    // 🔀 PROTOCOL DETECTION: Psiphon, Direct DNS, OpenVPN, Slow DNS, or SSTP
    if (_selectedProtocol == 'psiphon') {
      await _connectPsiphon();
      return;
    } else if (_selectedProtocol == 'direct_dns') {
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
    } else if (_selectedProtocol == 'proxy') {
      // ✅ Proxy (real SOCKS4/SOCKS5/HTTP): Use selected proxy server
      await _connectProxy();
      return;
    } else if (_selectedProtocol == 'warp') {
      // ✅ WARP (Cloudflare WireGuard via Xray's wireguard outbound)
      await _connectWarp();
      return;
    }

    if (sstpToken == null ||
        sstpToken != _sstpConnectGen ||
        _selectedProtocol != 'sstp' ||
        _mixDisposed) {
      return;
    }
    await _connectSstp();
  }

  /// لیست DNS هایی که در حالت Deep Scan برای هر سرور امتحان می‌شوند.
  /// ترکیبی از DNS های جهانی و DNS های ضد تحریم ایرانی تا بیشترین شانس
  /// اتصال برای کاربرانِ با اینترنت محدودشده فراهم شود.
  List<String> _deepScanDnsList() {
    return const [
      '8.8.8.8', // Google
      '1.1.1.1', // Cloudflare
      '178.22.122.100', // Shekan
      '185.51.200.2', // Shekan secondary
      '10.202.10.10', // Radar Game
      '10.202.10.202', // Online.403
      '78.157.42.100', // Electro
      '185.55.226.26', // Begzar
      '208.67.222.222', // OpenDNS
    ];
  }

  /// Connect through the official Psiphon Android MobileLibrary.
  /// The native service owns the tunnel; this layer only coordinates UI state
  /// and performs a lightweight post-connect liveness check.
  /// Connect through the official Psiphon tunnel core.
  ///
  /// The native service (isolated `:psiphon` process) owns the tunnel; this
  /// layer coordinates UI state with exponential-backoff retries across
  /// attempts, merges native log lines into [ConnectionLogger], and respects
  /// the kill switch: with it ON, a final failure leaves the native blackhole
  /// engaged (traffic blocked, service alive for the monitor to heal);
  /// otherwise the service is stopped so traffic flows normally again.
  Future<void> _connectPsiphon() async {
    final gen = ++_psiphonConnectGen;
    bool cancelled() =>
        gen != _psiphonConnectGen ||
        _selectedProtocol != 'psiphon' ||
        _mixDisposed ||
        _status == VpnConnectionStatus.disconnected ||
        _status == VpnConnectionStatus.disconnecting;
    Future<void> cleanUpCancelledStart() async {
      // An old completion must not stop a newer Psiphon connection.
      if (_selectedProtocol != 'psiphon' ||
          _status == VpnConnectionStatus.disconnected ||
          _status == VpnConnectionStatus.disconnecting) {
        await _psiphonService.stop();
      }
    }

    _stopPsiphonMonitor();
    _psiphonFailCount = 0;
    _status = VpnConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();
    final log = ConnectionLogger.instance;
    log.info('psiphon', 'Connecting to Psiphon…');
    _startPsiphonLogPump();
    const policy = RetryPolicy.psiphonConnect;
    String failure = 'Psiphon connection timed out';
    String lastNativeStatus = '';
    try {
      final killSwitchEnabled = await isKillSwitchEnabled();
      if (cancelled()) return;
      for (var attempt = 0; policy.shouldRetry(attempt); attempt++) {
        if (cancelled()) return;
        if (attempt > 0) {
          final backoff = policy.delayForAttempt(attempt);
          _errorMessage =
              'Retrying… (attempt ${attempt + 1}/${policy.maxAttempts})';
          log.warning('psiphon', _errorMessage!);
          notifyListeners();
          await Future<void>.delayed(backoff);
          if (cancelled()) return;
        }

        // Native reconnect preserves the blocking TUN when kill switch is on.
        // Do not tear it down merely because the core is still searching.
        final started = attempt > 0
            ? await _psiphonService.reconnect()
            : await _psiphonService.start(targetServerId: _selectedPsiphonServerId);
        if (cancelled()) {
          await cleanUpCancelledStart();
          return;
        }
        if (!started) {
          failure =
              'Psiphon could not start. Approve VPN permission, then retry.';
          break;
        }

        var terminalFailure = false;
        for (var i = 0; i < 180; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (cancelled()) return;
          final connected = await _psiphonService.isConnected;
          if (cancelled()) return;
          if (connected) {
            _psiphonFailCount = 0;
            _status = VpnConnectionStatus.connected;
            _connectedServer = null;
            _errorMessage = null;
            log.success('psiphon', 'Core connected and traffic bridge active');
            _startDurationTimer();
            _startPingTimer();
            _startPsiphonTraffic();
            _startPsiphonMonitor();
            notifyListeners();
            return;
          }
          final nativeStatus = (await _psiphonService.statusText).trim();
          if (cancelled()) return;
          if (nativeStatus.isNotEmpty) lastNativeStatus = nativeStatus;
          // Do not hide deterministic startup/bridge failures behind minutes
          // of polling or overwrite their cause with our subsequent stop().
          if (nativeStatus.startsWith('Psiphon failed:') ||
              nativeStatus.startsWith('Psiphon traffic bridge failed') ||
              nativeStatus.startsWith('Psiphon bridge failed') ||
              nativeStatus == 'Psiphon tunnel core exited') {
            failure = nativeStatus;
            terminalFailure = true;
            break;
          }
          // A blocking TUN protects traffic while the core searches or
          // reconnects; it is not a failed connection attempt. Breaking here
          // used to burn all four retries before the core could recover.
          final blocking = await _psiphonService.isKillSwitchActive;
          if (cancelled()) return;
          final progress = [
            'Connecting to Psiphon (attempt ${attempt + 1}/${policy.maxAttempts})',
            if (nativeStatus.isNotEmpty) nativeStatus,
            if (blocking) 'Kill switch protecting traffic while connecting',
          ].join(' — ');
          if (_errorMessage != progress) {
            _errorMessage = progress;
            notifyListeners();
          }
        }
        if (terminalFailure) break;
        failure =
            'Psiphon connection timed out after '
            '${attempt + 1}/${policy.maxAttempts} attempts.'
            '${lastNativeStatus.isEmpty ? '' : ' Last status: $lastNativeStatus'}';
        log.warning('psiphon', 'Attempt ${attempt + 1}: no ready tunnel yet');
      }

      if (cancelled()) return;
      final blocking = await _psiphonService.isKillSwitchActive;
      final running = await _psiphonService.isRunning;
      if (cancelled()) return;
      // Preference selects recovery policy; native state alone supports a
      // claim that the blackhole is actually active.
      if (killSwitchEnabled && (blocking || running)) {
        _status = VpnConnectionStatus.error;
        _errorMessage = blocking
            ? '$failure — kill switch active, traffic blocked. Retry or disconnect.'
            : '$failure — VPN service remains active. Retry or disconnect.';
        _startPsiphonMonitor();
      } else {
        await _psiphonService.stop();
        if (cancelled()) return;
        _stopPsiphonLogPump();
        _status = VpnConnectionStatus.error;
        _errorMessage = failure;
      }
      log.error('psiphon', _errorMessage!);
      notifyListeners();
    } catch (e) {
      if (cancelled()) return;
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Psiphon connection failed: $e';
      log.error('psiphon', _errorMessage!);
      notifyListeners();
    }
  }

  /// Background liveness monitor: every 20s verifies the tunnel is still
  /// healthy and heals it with backoff. With the kill switch ON it retries
  /// forever (capped at 1/min); otherwise it gives up after 5 consecutive
  /// failures, stops the service and reports an error.
  void _startPsiphonMonitor() {
    _psiphonMonitorTimer?.cancel();
    _psiphonMonitorTimer = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) async {
      if (_selectedProtocol != 'psiphon' ||
          (_status != VpnConnectionStatus.connected &&
              _status != VpnConnectionStatus.connecting &&
              _status != VpnConnectionStatus.error)) {
        return;
      }
      if (_psiphonMonitorBusy) return; // a recovery is already in flight
      _psiphonMonitorBusy = true;
      final monitorGen = _psiphonConnectGen;
      bool monitorCancelled() =>
          monitorGen != _psiphonConnectGen ||
          _selectedProtocol != 'psiphon' ||
          _mixDisposed ||
          _status == VpnConnectionStatus.disconnected ||
          _status == VpnConnectionStatus.disconnecting;
      try {
        if (await _psiphonService.isReconnecting) return;
        final healthy = await _psiphonService.isConnected;
        if (monitorCancelled()) return;
        if (await _psiphonService.isReconnecting) return;
        if (healthy) {
          if (_status != VpnConnectionStatus.connected) {
            _psiphonFailCount = 0;
            _status = VpnConnectionStatus.connected;
            _errorMessage = null;
            _startDurationTimer();
            _startPsiphonTraffic();
            _startPingTimer();
            notifyListeners();
          } else if (_psiphonFailCount != 0) {
            _psiphonFailCount = 0;
          }
          return;
        }
        if (_status != VpnConnectionStatus.connected &&
            _status != VpnConnectionStatus.error &&
            _status != VpnConnectionStatus.connecting) {
          return; // user is disconnecting; leave it alone
        }

        _psiphonFailCount++;
        final killSwitch = await isKillSwitchEnabled();
        if (monitorCancelled()) return;
        if (await _psiphonService.isReconnecting) return;
        final policy = killSwitch
            ? RetryPolicy.psiphonMonitorKillSwitch
            : RetryPolicy.psiphonMonitor;
        final log = ConnectionLogger.instance;

        if (!policy.shouldRetry(_psiphonFailCount - 1)) {
          if (await _psiphonService.isReconnecting) return;
          log.error(
            'psiphon',
            'Connection lost — recovery failed ${_psiphonFailCount - 1} times, giving up',
          );
          try {
            await _psiphonService.stop();
          } catch (_) {}
          if (monitorCancelled()) return;
          _stopPsiphonTraffic();
          _stopPsiphonMonitor(); // stop ticking: terminal state reached
          _stopPsiphonLogPump();
          _status = VpnConnectionStatus.error;
          _errorMessage = 'Psiphon connection lost';
          notifyListeners();
          return;
        }

        final backoff = policy.delayForAttempt(_psiphonFailCount);
        log.warning(
          'psiphon',
          'Tunnel unhealthy — recovery attempt $_psiphonFailCount in ${backoff.inSeconds}s…',
        );
        _status = VpnConnectionStatus.connecting;
        _errorMessage =
            'Connection unstable — retrying (attempt $_psiphonFailCount)…';
        notifyListeners();
        await Future<void>.delayed(backoff);
        if (monitorCancelled() ||
            (_status != VpnConnectionStatus.connecting &&
                _status != VpnConnectionStatus.error)) {
          return;
        }
        if (await _psiphonService.isReconnecting) return;
        await _psiphonService.reconnect();
        if (monitorCancelled()) return;
        for (var i = 0; i < 180; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (monitorCancelled()) return;
          if (await _psiphonService.isReconnecting) return;
          final recovered = await _psiphonService.isConnected;
          if (monitorCancelled()) return;
          if (await _psiphonService.isReconnecting) return;
          if (recovered) {
            _psiphonFailCount = 0;
            _status = VpnConnectionStatus.connected;
            _errorMessage = null;
            log.success('psiphon', 'Tunnel recovered');
            _startDurationTimer();
            _startPsiphonTraffic();
            notifyListeners();
            return;
          }
        }
        log.warning('psiphon', 'Recovery attempt timed out — will retry');
        // Stay in `connecting` so the next tick keeps healing.
      } catch (_) {
      } finally {
        if (monitorGen == _psiphonConnectGen) _psiphonMonitorBusy = false;
      }
    });
  }

  void _stopPsiphonMonitor() {
    _psiphonMonitorTimer?.cancel();
    _psiphonMonitorTimer = null;
    _psiphonMonitorBusy = false;
  }

  /// Polls cumulative Psiphon tunnel bytes into the shared data-usage counters
  /// (same pattern as [_startXrayTraffic]).
  void _startPsiphonTraffic() {
    _stopPsiphonTraffic();
    _totalDownloadBytes = 0;
    _totalUploadBytes = 0;
    _psiphonTrafficTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (!isConnected || _selectedProtocol != 'psiphon') {
        timer.cancel();
        return;
      }
      try {
        final stats = await _psiphonService.queryStats();
        _totalUploadBytes = stats['uplink'] ?? 0;
        _totalDownloadBytes = stats['downlink'] ?? 0;
        notifyListeners();
      } catch (_) {}
    });
  }

  void _stopPsiphonTraffic() {
    _psiphonTrafficTimer?.cancel();
    _psiphonTrafficTimer = null;
  }

  /// Merges timestamped native lines from the `:psiphon` / `:psiphonbridge`
  /// processes into [ConnectionLogger] while a Psiphon session is active.
  /// Runs during connect attempts AND while connected (native lines keep
  /// arriving, e.g. network waits, region updates).
  void _startPsiphonLogPump() {
    _stopPsiphonLogPump();
    _psiphonLogPumpActive = true;
    _psiphonLogTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_psiphonLogPumpActive || _selectedProtocol != 'psiphon') return;
      try {
        final lines = await _psiphonService.getNativeLogs();
        if (lines.isEmpty) return;
        final log = ConnectionLogger.instance;
        for (final line in lines) {
          if (_psiphonLogSeen.contains(line)) continue;
          _psiphonLogSeen.add(line);
          if (_psiphonLogSeen.length > 400) {
            _psiphonLogSeen.remove(_psiphonLogSeen.first);
          }
          final lower = line.toLowerCase();
          if (lower.contains('fail') || lower.contains('error')) {
            log.error('psiphon', 'native: $line');
          } else if (lower.contains('kill switch') ||
              lower.contains('waiting for network') ||
              lower.contains('upstream proxy error')) {
            log.warning('psiphon', 'native: $line');
          } else if (lower.contains('connected') ||
              lower.contains('bridge confirmed') ||
              lower.contains('bridge active')) {
            log.success('psiphon', 'native: $line');
          } else {
            log.info('psiphon', 'native: $line');
          }
        }
      } catch (_) {}
    });
  }

  void _stopPsiphonLogPump() {
    _psiphonLogPumpActive = false;
    _psiphonLogTimer?.cancel();
    _psiphonLogTimer = null;
  }

  /// Whether the user enabled the kill switch in Settings.
  Future<bool> isKillSwitchEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('kill_switch') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Connect via Direct DNS (separate from SSTP)
  Future<void> _connectDirectDns() async {
    final revision = _vpnStateRevision;
    bool cancelled() => _mixDisposed || revision != _vpnStateRevision;
    // Check if DNS server is selected
    if (_selectedDnsServer == null) {
      // ✅ نمایش پیام به کاربر
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please select a DNS server from Server List first';
      notifyListeners();

      if (kDebugMode) {
        debugPrint(
          '⚠️ No DNS server selected - please choose from Server List',
        );
      }
      return;
    }

    try {
      // Set status to connecting
      _status = VpnConnectionStatus.connecting;
      notifyListeners();

      // Request VPN permission
      final permissionGranted = await DnsVpnConnection.requestPermission();
      if (cancelled()) return;

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
      if (cancelled()) return;

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
      if (cancelled()) return;
      _status = VpnConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  /// Connect via OpenVPN. Give each started attempt enough time for DNS, TLS
  /// and authentication before silently restarting it; stop immediately on a
  /// HARD auth failure (wrong user/pass). Client-certificate material is
  /// bypassed when explicitly requested or when the profile has none to keep.
  Future<void> _connectOpenVpn({bool forceBypassCert = false}) async {
    final revision = _vpnStateRevision;
    bool cancelled() => _mixDisposed || revision != _vpnStateRevision;
    // Apply the global Traffic Compression toggle before building the config.
    try {
      final prefs = await SharedPreferences.getInstance();
      OpenVpnConfig.trafficCompressionEnabled =
          prefs.getBool('traffic_compression') ?? false;
    } catch (_) {}
    if (cancelled()) return;

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
        if (cancelled()) return;
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

    if (cancelled()) return;
    // Tear down any prior/stale native session first.
    try {
      await OpenVpnConnection.disconnect();
    } catch (_) {}
    if (cancelled()) return;

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
    // attempt's completer immediately (so we don't wait for the watchdog).
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
        debugPrint(
          '🚀 OpenVPN connect attempt $attempt: '
          '${_selectedOpenVpnConfig!.name}',
        );
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

      // A VPN handshake can legitimately take longer than a few seconds, even
      // when the same profile connects quickly in another client. Keep the
      // longer timeout while allowing stage and auth failures to finish early.
      final watchdog = Timer(const Duration(seconds: 30), () => finish(false));

      try {
        await OpenVpnConnection.connect(
          _selectedOpenVpnConfig!,
          // This controls whether client-certificate material is stripped.
          // Inline PKCS#12 is recognized as a client credential too.
          forceBypassCert:
              forceBypassCert || !_selectedOpenVpnConfig!.hasClientCert,
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

      // Reset the native session and retry silently (UI stays on "connecting",
      // no error shown). Do NOT clear the auth-failed state here, so a
      // wrong-password detected late (during teardown) still aborts.
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

  /// Connect only after the native dnstt server passes authenticated probes.
  Future<void> _connectSlowDns() async {
    final config = _selectedSlowDnsConfig;
    if (config == null) {
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please select a Slow DNS config first';
      notifyListeners();
      return;
    }
    final generation = ++_slowDnsConnectGen;
    bool cancelled() =>
        generation != _slowDnsConnectGen ||
        _selectedProtocol != 'slowdns' ||
        _mixDisposed;
    _status = VpnConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();
    if (config.validationError != null) {
      _status = VpnConnectionStatus.error;
      _errorMessage = config.validationError;
      notifyListeners();
      return;
    }
    final granted = await SlowDnsConnection.requestPermission();
    if (cancelled()) return;
    if (!granted) {
      _status = VpnConnectionStatus.error;
      _errorMessage =
          SlowDnsConnection.lastError ??
          'Approve the VPN permission, then connect again.';
      notifyListeners();
      return;
    }
    SlowDnsConnection.onStateChanged = (connected, message) {
      if (cancelled()) return;
      if (connected) {
        _status = VpnConnectionStatus.connected;
        _connectedServer = null;
        _errorMessage = null;
        _startDurationTimer();
        // A direct ping from the excluded app UID is not tunnel latency.
        _stopPingTimer();
      } else {
        _status = VpnConnectionStatus.error;
        _errorMessage = message;
        _stopDurationTimer();
        _stopPingTimer();
      }
      notifyListeners();
    };
    final connected = await SlowDnsConnection.connect(config);
    if (cancelled()) return;
    if (!connected) {
      _status = VpnConnectionStatus.error;
      _errorMessage =
          SlowDnsConnection.lastError ?? 'Slow DNS connection failed.';
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

  Future<bool> updateXrayServer(XrayServer server) async {
    final ok = await _xrayService.updateServer(server);
    if (ok) await loadXrayServers();
    return ok;
  }

  Future<int> removeXrayGroupServers(String groupKey, String mode) async {
    final removed = await _xrayService.removeServersFromGroup(groupKey, mode);
    if (removed > 0) await loadXrayServers();
    return removed;
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
  Future<void> selectXrayFreeGroup() => selectXrayGroup(XrayServer.freeGroup);

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

  Future<String?> xraySubUrlForGroup(String groupKey) =>
      _xrayService.subUrlForGroup(groupKey);

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
  Future<int> refreshXrayFreeGroup({
    bool force = false,
    bool builtInOnly = false,
  }) async {
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

  /// Measures only the TCP connection latency to the server endpoint.
  /// This does not build an Xray config and does not use the HTTP test URL.
  Future<int> measureXrayTcpPing(XrayServer server) async {
    if (_xrayTcpTestingIds.contains(server.id)) return -1;
    _xrayTcpTestingIds.add(server.id);
    notifyListeners();
    Socket? socket;
    var delay = -1;
    try {
      final stopwatch = Stopwatch()..start();
      socket = await Socket.connect(
        server.address,
        server.port,
        timeout: const Duration(seconds: 6),
      );
      stopwatch.stop();
      delay = stopwatch.elapsedMilliseconds;
      await _xrayService.updatePing(server.id, delay);
      _applyPing(server.id, delay);
      return delay;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ measureXrayTcpPing: $e');
      await _xrayService.updatePing(server.id, -1);
      _applyPing(server.id, -1);
      return -1;
    } finally {
      socket?.destroy();
      _xrayTcpTestingIds.remove(server.id);
      notifyListeners();
    }
  }

  /// Runs direct TCP latency tests for every server in a group concurrently.
  Future<void> testXrayTcpServers(List<XrayServer> servers) async {
    if (servers.isEmpty) return;
    final groups = servers.map((s) => s.group).toSet();
    if (groups.any(_xrayTcpTestingGroups.contains)) return;
    _xrayTcpTestingGroups.addAll(groups);
    notifyListeners();
    try {
      await Future.wait(servers.map(measureXrayTcpPing));
    } finally {
      _xrayTcpTestingGroups.removeAll(groups);
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
  Future<void> testXrayServers(
    List<XrayServer> servers, {
    int rounds = 1,
  }) async {
    if (servers.isEmpty) return;
    final groups = servers.map((s) => s.group).toSet();
    // Different groups may run in parallel; prevent duplicate jobs for the
    // same group when its button is tapped repeatedly.
    if (groups.any(_xrayTestingGroups.contains)) return;
    _xrayGroupTesting = true;
    // Snapshot the connect token so a delay-test launched by a group connect
    // stops as soon as the user cancels (disconnect bumps _xrayConnectGen).
    final int testGen = _xrayConnectGen;
    // Mark only the group(s) these servers belong to as "testing" so the
    // spinner shows on the tapped group only, not every group.
    _xrayTestingGroups.addAll(groups);
    notifyListeners();
    try {
      final batchSize = await getXrayConcurrentTests();
      final testUrl = await getXrayTestUrl();
      final int totalRounds = rounds.clamp(1, 5);
      // Best ping seen per server across all rounds (lower positive = better).
      final results = <String, int?>{};

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
            if (kDebugMode)
              debugPrint('🚫 group delay-test aborted (cancelled)');
            return;
          }
          final batch = servers.sublist(
            i,
            (i + batchSize).clamp(0, servers.length),
          );
          for (final s in batch) {
            _xrayTestingIds.add(s.id);
          }
          notifyListeners();
          await Future.wait(
            batch.map((s) async {
              try {
                final config = await _buildDelayConfig(s);
                final delay = await XrayConnection.measureDelay(
                  config,
                  url: testUrl,
                );
                mergeBest(s.id, delay >= 0 ? delay : -1);
              } catch (_) {
                mergeBest(s.id, -1);
              } finally {
                _xrayTestingIds.remove(s.id);
              }
            }),
          );
          // Another group may finish and sort the shared list while this job
          // is running, so resolve ids against the current list every batch.
          final currentIndexById = <String, int>{};
          for (var j = 0; j < _xrayServers.length; j++) {
            currentIndexById[_xrayServers[j].id] = j;
          }
          // Apply the best-so-far pings in one pass, then a SINGLE notify.
          for (final s in batch) {
            final idx = currentIndexById[s.id];
            if (idx != null && idx < _xrayServers.length) {
              _xrayServers[idx] = _xrayServers[idx].copyWith(
                ping: results[s.id],
              );
            }
          }
          notifyListeners();
        }
      }
      await _sortXrayByPing();
    } finally {
      _xrayTestingGroups.removeAll(groups);
      _xrayGroupTesting = _xrayTestingGroups.isNotEmpty;
      notifyListeners();
    }
  }

  /// Delay-test EVERY server across ALL groups at once.
  Future<void> testAllXrayGroups() async {
    if (_xrayGroupTesting) return;
    final all = List<XrayServer>.from(_xrayServers);
    await testXrayServers(all);
  }

  /// Sorts only one Xray group by its latest measured ping. Working servers
  /// come first (lowest latency), followed by untested, then failed servers.
  Future<void> sortXrayGroupByPing(String groupKey) async {
    int rank(XrayServer s) {
      final p = s.ping;
      if (p == null) return 1;
      if (p < 0) return 2;
      return 0;
    }

    final indexes = <int>[];
    for (var i = 0; i < _xrayServers.length; i++) {
      if (_xrayServers[i].group == groupKey) indexes.add(i);
    }
    if (indexes.length < 2) return;
    final sorted = indexes.map((i) => _xrayServers[i]).toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        if (byRank != 0) return byRank;
        return (a.ping ?? 999999).compareTo(b.ping ?? 999999);
      });
    for (var i = 0; i < indexes.length; i++) {
      _xrayServers[indexes[i]] = sorted[i];
    }
    await _xrayService.saveServers(_xrayServers);
    notifyListeners();
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
    final working =
        _xrayServers.where((s) => s.group == g && (s.ping ?? -1) > 0).toList()
          ..sort((a, b) => (a.ping ?? 999999).compareTo(b.ping ?? 999999));
    return working.isNotEmpty ? working.first : null;
  }

  // ==================== Proxy Protocol Methods ====================
  //
  // The Proxy protocol connects to a REAL SOCKS4 / SOCKS5 / HTTP upstream. It
  // mirrors the Xray protocol's server-list UX but is a distinct feature (its
  // own server store, its own connect path). The connection itself runs through
  // the same native Xray core: the upstream proxy is turned into an Xray
  // socks/http OUTBOUND (see XrayConfigBuilder.buildForProxyServer).

  /// Load persisted Proxy servers + currently selected one/group.
  Future<void> loadProxyServers() async {
    _proxyServers = await _proxyService.loadServers();
    final prefs = await SharedPreferences.getInstance();
    _selectedProxyGroup = prefs.getString('proxy_selected_group');
    if (_selectedProxyGroup != null &&
        !_proxyServers.any((s) => s.group == _selectedProxyGroup)) {
      _selectedProxyGroup = null;
      await prefs.remove('proxy_selected_group');
    }
    if (_selectedProxyGroup != null) {
      _selectedProxyServer = null;
    } else {
      _selectedProxyServer = await _proxyService.getSelectedServer();
    }
    notifyListeners();
  }

  /// Add proxy server(s) from share link(s). Returns count added.
  Future<int> addProxyServers(String raw) async {
    final added = await _proxyService.addFromLinks(raw);
    if (added > 0) await loadProxyServers();
    return added;
  }

  Future<void> removeProxyServer(String id) async {
    await _proxyService.removeServer(id);
    await loadProxyServers();
  }

  Future<void> selectProxyServer(ProxyServer server) async {
    _selectedProxyServer = server;
    _selectedProxyGroup = null;
    await _proxyService.setSelectedId(server.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('proxy_selected_group');
    notifyListeners();
    await _reconnectProxyIfActive();
  }

  Future<void> _reconnectProxyIfActive() async {
    if (_selectedProtocol != 'proxy') return;
    if (_status != VpnConnectionStatus.connected &&
        _status != VpnConnectionStatus.connecting) {
      return;
    }
    if (_selectedProxyServer == null) return;
    await disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await connect();
  }

  Future<void> selectProxyGroup(String group) async {
    _selectedProxyGroup = group;
    _selectedProxyServer = null;
    await _proxyService.setSelectedId(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('proxy_selected_group', group);
    notifyListeners();
  }

  // ---- Proxy subscription management ----
  Future<List<String>> getProxySubUrls() => _proxyService.getSubUrls();
  Future<Map<String, String>> getProxySubNames() => _proxyService.getSubNames();
  Future<String> proxySubDisplayName(String url) =>
      _proxyService.groupNameForUrlAsync(url);

  Future<void> setProxySubName(String url, String name) async {
    await _proxyService.setSubName(url, name);
    await loadProxyServers();
    notifyListeners();
  }

  Future<bool> addProxySubUrl(String url, {String? name}) async {
    final trimmed = url.trim();
    final added = await _proxyService.addSubInput(trimmed);
    if (added > 0) {
      if (name != null &&
          name.trim().isNotEmpty &&
          trimmed.startsWith('http') &&
          !trimmed.contains(RegExp(r'[\r\n]'))) {
        await _proxyService.setSubName(trimmed, name.trim());
      }
      await refreshProxySubs(force: true);
    }
    return added > 0;
  }

  Future<void> removeProxySubUrl(String url) async {
    await _proxyService.removeSubUrl(url);
    await refreshProxySubs(force: true);
  }

  Future<bool> changeProxySubUrl(String oldUrl, String newUrl) async {
    final ok = await _proxyService.changeSubUrl(oldUrl, newUrl);
    if (ok) await refreshProxySubs(force: true);
    return ok;
  }

  /// Refresh ALL proxy subscription groups from their URLs.
  Future<int> refreshProxySubs({bool force = false}) async {
    _proxyRefreshing = true;
    notifyListeners();
    try {
      final count = await _proxyService.refreshAll(
        minInterval: force ? null : const Duration(hours: 6),
      );
      await loadProxyServers();
      return count;
    } finally {
      _proxyRefreshing = false;
      notifyListeners();
    }
  }

  /// Refresh a SINGLE proxy subscription group.
  Future<int> refreshProxyOneGroup(String groupKey) async {
    if (_proxyRefreshingGroups.contains(groupKey)) return -1;
    _proxyRefreshingGroups.add(groupKey);
    notifyListeners();
    try {
      final count = await _proxyService.refreshOneGroup(groupKey);
      await loadProxyServers();
      return count;
    } finally {
      _proxyRefreshingGroups.remove(groupKey);
      notifyListeners();
    }
  }

  void _applyProxyPing(String id, int? ping) {
    final idx = _proxyServers.indexWhere((s) => s.id == id);
    if (idx >= 0) _proxyServers[idx] = _proxyServers[idx].copyWith(ping: ping);
  }

  /// TEST TYPE 1 — plain PING test. Measures the TCP connect latency to the
  /// proxy's host:port directly (a normal reachability/ping check). Returns ms
  /// or -1 on failure. Persists the result.
  Future<int> pingProxyServer(ProxyServer server) async {
    _proxyTestingIds.add(server.id);
    notifyListeners();
    final sw = Stopwatch()..start();
    int result = -1;
    try {
      final socket = await Socket.connect(
        server.address,
        server.port,
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      result = sw.elapsedMilliseconds;
      socket.destroy();
    } catch (e) {
      result = -1;
      if (kDebugMode) debugPrint('⚠️ pingProxyServer: $e');
    } finally {
      await _proxyService.updatePing(server.id, result);
      _applyProxyPing(server.id, result);
      _proxyTestingIds.remove(server.id);
      notifyListeners();
    }
    return result;
  }

  /// TEST TYPE 2 — "open a site" test. Makes a REAL request through the proxy
  /// (via the Xray core's measureOutboundDelay) to the configured test site,
  /// proving the proxy actually works for browsing. Returns ms or -1. Persists
  /// the result (overwriting the ping value with the real-connectivity delay).
  Future<int> openSiteTestProxyServer(ProxyServer server) async {
    _proxyTestingIds.add(server.id);
    notifyListeners();
    int delay = -1;
    try {
      final config = XrayConfigBuilder.buildProxyServerDelayTest(server);
      final testUrl = await getProxyTestUrl();
      delay = await XrayConnection.measureDelay(config, url: testUrl);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ openSiteTestProxyServer: $e');
      delay = -1;
    } finally {
      await _proxyService.updatePing(server.id, delay >= 0 ? delay : -1);
      _applyProxyPing(server.id, delay >= 0 ? delay : -1);
      _proxyTestingIds.remove(server.id);
      notifyListeners();
    }
    return delay;
  }

  /// Concurrently open-site-test a list of proxy servers (used by the group /
  /// "test all" buttons and by the connect path to pick the fastest working
  /// proxy). Keeps the lowest positive delay.
  Future<void> testProxyServers(List<ProxyServer> servers) async {
    if (servers.isEmpty || _proxyGroupTesting) return;
    _proxyGroupTesting = true;
    final int testGen = _proxyConnectGen;
    final groups = servers.map((s) => s.group).toSet();
    _proxyTestingGroups.addAll(groups);
    notifyListeners();
    try {
      final testUrl = await getProxyTestUrl();
      const batchSize = 30;
      final results = <String, int?>{};
      final indexById = <String, int>{};
      for (var i = 0; i < _proxyServers.length; i++) {
        indexById[_proxyServers[i].id] = i;
      }
      for (var i = 0; i < servers.length; i += batchSize) {
        if (testGen != _proxyConnectGen) return;
        final batch = servers.sublist(
          i,
          (i + batchSize).clamp(0, servers.length),
        );
        for (final s in batch) {
          _proxyTestingIds.add(s.id);
        }
        notifyListeners();
        await Future.wait(
          batch.map((s) async {
            try {
              final config = XrayConfigBuilder.buildProxyServerDelayTest(s);
              final delay = await XrayConnection.measureDelay(
                config,
                url: testUrl,
              );
              results[s.id] = delay >= 0 ? delay : -1;
            } catch (_) {
              results[s.id] = -1;
            } finally {
              _proxyTestingIds.remove(s.id);
            }
          }),
        );
        for (final s in batch) {
          final idx = indexById[s.id];
          if (idx != null && idx < _proxyServers.length) {
            _proxyServers[idx] = _proxyServers[idx].copyWith(
              ping: results[s.id],
            );
          }
        }
        notifyListeners();
      }
      await _proxyService.updatePings(results);
      await _sortProxyByPing();
    } finally {
      _proxyGroupTesting = false;
      _proxyTestingGroups.removeAll(groups);
      notifyListeners();
    }
  }

  Future<void> testAllProxyGroups() async {
    if (_proxyGroupTesting) return;
    final all = List<ProxyServer>.from(_proxyServers);
    await testProxyServers(all);
  }

  Future<void> _sortProxyByPing() async {
    int rank(ProxyServer s) {
      final p = s.ping;
      if (p == null) return 1;
      if (p < 0) return 2;
      return 0;
    }

    final order = <String, int>{};
    var next = 0;
    for (final s in _proxyServers) {
      order.putIfAbsent(s.group, () => next++);
    }
    _proxyServers.sort((a, b) {
      if (a.group != b.group) {
        return order[a.group]!.compareTo(order[b.group]!);
      }
      final ra = rank(a), rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      return (a.ping ?? 999999).compareTo(b.ping ?? 999999);
    });
    await _proxyService.saveServers(_proxyServers);
    notifyListeners();
  }

  List<ProxyServer> _selectedProxyGroupServers() {
    final g = _selectedProxyGroup;
    if (g == null) return const [];
    return _proxyServers.where((s) => s.group == g).toList();
  }

  Future<void> selectNextProxyServer() async {
    final group = _selectedProxyGroupServers();
    if (group.isEmpty) return;
    final curId = _activeProxyServer?.id ?? _selectedProxyServer?.id;
    var idx = group.indexWhere((s) => s.id == curId);
    idx = (idx + 1) % group.length;
    final next = group[idx];
    _selectedProxyServer = next;
    await _proxyService.setSelectedId(next.id);
    notifyListeners();
    await _reconnectProxyIfActive();
  }

  Future<ProxyServer?> _pickFastestProxyServer() async {
    final group = _selectedProxyGroupServers();
    if (group.isEmpty) return null;
    await testProxyServers(group);
    final g = _selectedProxyGroup;
    final working =
        _proxyServers.where((s) => s.group == g && (s.ping ?? -1) > 0).toList()
          ..sort((a, b) => (a.ping ?? 999999).compareTo(b.ping ?? 999999));
    return working.isNotEmpty ? working.first : null;
  }

  /// The default open-site test URL for the Proxy protocol.
  static const String defaultProxyTestUrl = 'http://www.google.com/gen_204';

  Future<String> getProxyTestUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('proxy_test_url')?.trim();
    if (v == null || v.isEmpty) return defaultProxyTestUrl;
    return v;
  }

  Future<void> setProxyTestUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final v = url.trim();
    if (v.isEmpty) {
      await prefs.remove('proxy_test_url');
    } else {
      await prefs.setString('proxy_test_url', v);
    }
    notifyListeners();
  }

  /// Connect through the selected SOCKS4 / SOCKS5 / HTTP proxy. Runs the real
  /// Xray core with the upstream proxy as its outbound.
  Future<void> _connectProxy() async {
    final groupHasServers =
        _selectedProxyGroup != null &&
        _proxyServers.any((s) => s.group == _selectedProxyGroup);
    if (_selectedProxyServer == null && !groupHasServers) {
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Please add and select a proxy server first';
      notifyListeners();
      return;
    }

    final int myGen = ++_proxyConnectGen;
    bool cancelled() =>
        myGen != _proxyConnectGen ||
        _status == VpnConnectionStatus.disconnecting ||
        _status == VpnConnectionStatus.disconnected;

    try {
      _status = VpnConnectionStatus.connecting;
      notifyListeners();

      ProxyServer? serverToConnect = _selectedProxyServer;
      if (_selectedProxyServer == null && groupHasServers) {
        final fastest = await _pickFastestProxyServer();
        if (cancelled()) return;
        if (fastest != null) {
          serverToConnect = fastest;
        } else {
          _status = VpnConnectionStatus.error;
          _errorMessage = 'No working proxy found in this group. Try again.';
          notifyListeners();
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final proxyMode =
          (prefs.getString('connection_mode') ?? 'vpn') == 'proxy';

      if (cancelled()) return;

      if (!proxyMode) {
        final granted = await XrayConnection.requestPermission();
        if (!granted) {
          _status = VpnConnectionStatus.error;
          _errorMessage = 'VPN permission denied';
          notifyListeners();
          return;
        }
      }

      if (cancelled()) return;

      final configJson = XrayConfigBuilder.buildForProxyServer(
        serverToConnect!,
        proxyMode: proxyMode,
      );

      if (kDebugMode) {
        debugPrint(
          '🚀 Connecting Proxy: ${serverToConnect.remark} '
          '(${serverToConnect.protocol}) mode=${proxyMode ? "proxy" : "vpn"}',
        );
      }

      final connected = await XrayConnection.connect(
        configJson,
        proxyMode: proxyMode,
      );
      if (cancelled()) {
        try {
          await XrayConnection.disconnect();
        } catch (_) {}
        return;
      }
      if (connected) {
        _status = VpnConnectionStatus.connected;
        _connectedServer = null;
        _activeProxyServer = serverToConnect;
        _errorMessage = null;
        _startDurationTimer();
        _startPingTimer();
        _startXrayTraffic();
      } else {
        _status = VpnConnectionStatus.error;
        _errorMessage = 'Failed to start proxy connection';
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Proxy connect failed: $e');
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Failed to connect: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Connect using the real Xray core (libv2ray / v2rayNG) with TLS
  /// ClientHello fragmentation enabled.
  Future<void> _connectXray() async {
    final groupHasServers =
        _selectedXrayGroup != null &&
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
      final fragPackets =
          prefs.getString('xray_fragment_packets') ?? 'tlshello';
      final fragLength = prefs.getString('xray_fragment_length') ?? '10-20';
      final fragInterval = prefs.getString('xray_fragment_interval') ?? '10-20';
      final fragHost = prefs.getString('xray_fragment_host') ?? '';
      // Connection mode: 'vpn' (system tunnel) or 'proxy' (local 127.0.0.1:4444
      // SOCKS/HTTP, no VPN icon). Global setting shared by the whole app.
      final proxyMode =
          (prefs.getString('connection_mode') ?? 'vpn') == 'proxy';

      if (cancelled()) {
        if (kDebugMode) debugPrint('🚫 Xray connect cancelled pre-permission');
        return;
      }

      // Request VPN permission — ONLY needed for VPN (system-tunnel) mode.
      // Proxy mode establishes no VpnService interface, so no permission dialog.
      if (!proxyMode) {
        final granted = await XrayConnection.requestPermission();
        if (!granted) {
          _status = VpnConnectionStatus.error;
          _errorMessage = 'VPN permission denied';
          notifyListeners();
          return;
        }
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
        proxyMode: proxyMode,
      );

      if (kDebugMode) {
        debugPrint(
          '🚀 Connecting Xray: ${serverToConnect.remark} '
          '(${serverToConnect.protocol}) fragment=$fragEnabled '
          'mode=${proxyMode ? "proxy" : "vpn"}',
        );
      }

      final connected = await XrayConnection.connect(
        configJson,
        proxyMode: proxyMode,
      );
      // If the user cancelled meanwhile, tear the just-started tunnel down and
      // stay disconnected instead of flipping to "connected".
      if (cancelled()) {
        if (kDebugMode)
          debugPrint('🚫 Xray connected late after cancel — tearing down');
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

  /// Connect using Cloudflare WARP (WireGuard), routed through the same
  /// Xray core as the xray/proxy protocols (Xray's native library already
  /// implements the "wireguard" outbound — no separate native runtime).
  /// Unlike Xray/Proxy there is no server list and no user-facing "register"
  /// action: a single device identity is auto-registered with Cloudflare on
  /// first use and reused afterwards. Everything — registration, retrying a
  /// bad identity, picking a working endpoint — happens automatically here;
  /// the UI only ever displays the resulting endpoint, it never triggers it.
  Future<void> _connectWarp() async {
    final int myGen = ++_warpConnectGen;
    bool cancelled() =>
        myGen != _warpConnectGen ||
        _status == VpnConnectionStatus.disconnecting ||
        _status == VpnConnectionStatus.disconnected;

    try {
      _status = VpnConnectionStatus.connecting;
      _warpError = null;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      final proxyMode =
          (prefs.getString('connection_mode') ?? 'vpn') == 'proxy';

      if (!proxyMode) {
        final granted = await XrayConnection.requestPermission();
        if (!granted) {
          _status = VpnConnectionStatus.error;
          _errorMessage = 'VPN permission denied';
          notifyListeners();
          return;
        }
      }

      if (cancelled()) return;

      // Try to bring WARP up end-to-end (register-if-needed → connect →
      // verify real traffic actually flows). If verification fails — e.g.
      // a previously-registered identity/endpoint stopped working — wipe it
      // and register a brand-new one automatically, once, with zero user
      // interaction. This is the self-healing the protocol needs instead of
      // ever asking the user to press a "register" button.
      const maxAttempts = 2;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        if (cancelled()) return;

        WarpAccount account;
        try {
          if (_warpAccount != null && attempt == 1) {
            account = _warpAccount!;
          } else {
            _warpRegistering = true;
            notifyListeners();
            account = await _warpService.register(); // always fresh on retry
            _warpAccount = account;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ WARP registration failed: $e');
          _status = VpnConnectionStatus.error;
          _warpError = 'Could not register WARP identity: ${e.toString()}';
          _errorMessage = _warpError;
          notifyListeners();
          return;
        } finally {
          _warpRegistering = false;
        }

        if (cancelled()) return;

        final configJson = XrayConfigBuilder.buildForWarp(
          account,
          proxyMode: proxyMode,
        );

        if (kDebugMode) {
          debugPrint(
            '🚀 Connecting WARP (attempt $attempt): '
            '${account.addressV4} via ${account.peerEndpoint} '
            'mode=${proxyMode ? "proxy" : "vpn"}',
          );
        }

        final started = await XrayConnection.connect(
          configJson,
          proxyMode: proxyMode,
        );
        if (cancelled()) {
          try {
            await XrayConnection.disconnect();
          } catch (_) {}
          return;
        }
        if (!started) {
          if (attempt < maxAttempts) continue;
          _status = VpnConnectionStatus.error;
          _errorMessage = 'Failed to start WARP tunnel';
          notifyListeners();
          return;
        }

        if (cancelled()) {
          try {
            await XrayConnection.disconnect();
          } catch (_) {}
          return;
        }

        // XrayConnection.connect only returns after the service has accepted
        // the config. Do not call measureDelay here: it starts a second core,
        // and the concurrent WireGuard core is the native crash trigger.
        _status = VpnConnectionStatus.connected;
        _connectedServer = null;
        _errorMessage = null;
        _currentPing = null;
        _pingFailed = false;
        _startDurationTimer();
        _startPingTimer();
        _startXrayTraffic();
        notifyListeners();
        return;
      }

      // Exhausted retries.
      _status = VpnConnectionStatus.error;
      _warpError = 'WARP could not reach Cloudflare on this network';
      _errorMessage = _warpError;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ WARP connect failed: $e');
      _status = VpnConnectionStatus.error;
      _errorMessage = 'Failed to connect: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Disconnect from VPN
  Future<void> disconnect() async {
    if (_status == VpnConnectionStatus.disconnecting ||
        // Psiphon can deliberately remain alive in an error state with its
        // kill-switch blackhole engaged. Also clean it up when Dart reports
        // disconnected: the native service is isolated in another process,
        // so a stale Dart status must not prevent stop().
        (_status == VpnConnectionStatus.disconnected &&
            _selectedProtocol != 'slowdns' &&
            _selectedProtocol != 'psiphon')) {
      return;
    }

    final mixWasConnecting = _selectedProtocol == 'mix' && isConnecting;
    _vpnStateRevision++;
    _sstpConnectGen++;
    _mixConnectGen++;
    // Invalidate any in-flight Xray connect (e.g. a group delay-test in
    // progress) so it aborts instead of connecting after the user cancelled.
    _xrayConnectGen++;
    _proxyConnectGen++;
    _warpConnectGen++;

    _status = VpnConnectionStatus.disconnecting;
    notifyListeners();

    try {
      // Disconnect based on protocol
      if (_selectedProtocol == 'mix') {
        final operation = _disconnectMix(wasConnecting: mixWasConnecting);
        _mixDisconnectOperation = operation;
        try {
          await operation;
        } finally {
          _mixDisconnectOperation = null;
        }
      } else if (_selectedProtocol == 'psiphon') {
        _psiphonConnectGen++; // abort any in-flight connect/retry loop
        _stopPsiphonMonitor();
        _stopPsiphonTraffic();
        _stopPsiphonLogPump();
        ConnectionLogger.instance.info('psiphon', 'Disconnect requested');
        await _psiphonService.stop();
        _stopPingTimer();
        _stopDurationTimer();
        _connectionDuration = Duration.zero;
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
        if (kDebugMode) debugPrint('🔌 Disconnecting Psiphon...');
      } else if (_selectedProtocol == 'direct_dns') {
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
        _slowDnsConnectGen++;
        SlowDnsConnection.onStateChanged = null;
        await SlowDnsConnection.disconnect();
        _errorMessage = null;
        _connectionDuration = Duration.zero;
        _stopDurationTimer();
        _stopPingTimer();
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
      } else if (_selectedProtocol == 'proxy') {
        // Proxy protocol runs the same Xray core → same native disconnect.
        await XrayConnection.disconnect();
        _stopPingTimer();
        _stopDurationTimer();
        _stopXrayTraffic();
        _connectionDuration = Duration.zero;
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
        _activeProxyServer = null;
        if (kDebugMode) {
          debugPrint('🔌 Disconnecting Proxy...');
        }
      } else if (_selectedProtocol == 'warp') {
        // WARP runs the same Xray core → same native disconnect. The
        // registered identity itself is NOT cleared (kept in memory + on
        // disk) so the next connect reuses it instead of re-registering.
        await XrayConnection.disconnect();
        _stopPingTimer();
        _stopDurationTimer();
        _stopXrayTraffic();
        _connectionDuration = Duration.zero;
        _totalDownloadBytes = 0;
        _totalUploadBytes = 0;
        if (kDebugMode) {
          debugPrint('🔌 Disconnecting WARP...');
        }
      } else {
        try {
          await _sstpNativeOperation;
        } catch (_) {}
        await _vpnService.disconnect();
      }

      _status = VpnConnectionStatus.disconnected;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Disconnect error: $e');
      }
      _status = VpnConnectionStatus.disconnected;
    }

    if (_mixDisposed) return;
    // All stop paths (including notification stops) clear the same UI state.
    _stopDurationTimer();
    _stopPingTimer();
    _stopXrayTraffic();
    _connectedServer = null;
    _activeXrayServer = null;
    _activeProxyServer = null;
    _connectionDuration = Duration.zero;
    _currentPing = null;
    _pingFailed = false;
    _totalDownloadBytes = 0;
    _totalUploadBytes = 0;
    _lastDownloadBytes = 0;
    _lastUploadBytes = 0;
    _dnsBaselineRxBytes = -1;
    _dnsBaselineTxBytes = -1;
    _errorMessage = null;
    notifyListeners();
  }

  /// A manual target is tested normally on connect, never bypassing tests.
  void selectServer(VpnServer server) => _selectSstpServer(server);

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Refresh SSTP sources without touching other protocol selections.
  Future<void> refreshServers() => loadServers(forceRefresh: true);

  Future<void> connectToNextServer() async {
    if (_servers.isEmpty || _selectedServer == null) return;
    final current = _servers.indexOf(_selectedServer!);
    final next = _servers[(current + 1) % _servers.length];
    await disconnect();
    selectServer(next);
    await connect();
  }

  /// Keep persisted SSTP targets when returning from the background.
  void resetState() {
    // Returning from Settings must not erase the only explanation for a
    // failed Psiphon connection (including a retained kill-switch TUN).
    if (_selectedProtocol == 'psiphon' && _status == VpnConnectionStatus.error) {
      return;
    }
    if (!isConnected && !isConnecting && !_sstpGroupTesting) {
      _errorMessage = null;
      _connectionDuration = Duration.zero;
      _totalDownloadBytes = 0;
      _totalUploadBytes = 0;
      _lastDownloadBytes = 0;
      _lastUploadBytes = 0;
      notifyListeners();
      unawaited(loadServers());
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
    if (_selectedProtocol == 'mix' && _mixDisconnectOperation != null) {
      await _mixDisconnectOperation;
    }
    if (_selectedProtocol == protocol) return;

    // اگر متصل است، ابتدا قطع کن
    // Psiphon may keep its native service alive while Dart reports `error`
    // for kill-switch recovery. Always issue its idempotent stop before
    // switching away from it.
    if (isConnected ||
        isConnecting ||
        _selectedProtocol == 'slowdns' ||
        _selectedProtocol == 'psiphon') {
      await disconnect();
    }

    _vpnStateRevision++;
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
      debugPrint(
        '✅ DNS Server Selected: ${server.name} (${server.primaryDns})',
      );
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
    _mixDisposed = true;
    _vpnStateRevision++;
    WidgetsBinding.instance.removeObserver(this);
    _vpnStateChannel.setMethodCallHandler(null);
    _sstpConnectGen++;
    _slowDnsConnectGen++;
    SlowDnsConnection.detach();
    _mixConnectGen++;
    _mixMonitor?.cancel();
    _mixDiagnosticsTimer?.cancel();
    _errorAutoClearTimer?.cancel();
    _statusSubscription?.cancel();
    _stopDurationTimer();
    _stopPingTimer();
    _stopXrayTraffic();
    _stopPsiphonMonitor();
    _stopPsiphonTraffic();
    _stopPsiphonLogPump();
    _vpnService.dispose();
    super.dispose();
  }
}
