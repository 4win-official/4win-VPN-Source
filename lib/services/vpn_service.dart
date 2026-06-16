import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sstp_flutter/sstp_flutter.dart';
import 'package:sstp_flutter/server.dart';
import 'package:sstp_flutter/android_configuration_sstp.dart';
import 'package:sstp_flutter/ios_configuration_sstp.dart';
import 'package:sstp_flutter/traffic.dart';
import 'package:sstp_flutter/ssl_versions.dart';
import '../models/vpn_server.dart';
import 'dns_vpn_connection.dart';

enum VpnConnectionStatus {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

class VpnService {
  final SstpFlutter _sstpFlutter = SstpFlutter();
  
  final _statusController = StreamController<VpnConnectionStatus>.broadcast();
  Stream<VpnConnectionStatus> get statusStream => _statusController.stream;
  
  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;
  
  VpnConnectionStatus _currentStatus = VpnConnectionStatus.disconnected;
  VpnConnectionStatus get currentStatus => _currentStatus;
  
  VpnServer? _connectedServer;
  VpnServer? get connectedServer => _connectedServer;
  
  DateTime? _connectionStartTime;
  DateTime? get connectionStartTime => _connectionStartTime;
  
  int _downloadSpeed = 0;
  int get downloadSpeed => _downloadSpeed;
  
  int _uploadSpeed = 0;
  int get uploadSpeed => _uploadSpeed;
  
  VpnService() {
    _initializeListener();
  }
  
  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logMessage = '[$timestamp] $message';
    
    if (kDebugMode) {
      debugPrint(logMessage);
    }
    
    _logController.add(logMessage);
  }
  
  void _initializeListener() {
    _addLog('VPN Service initialized');
    
    _sstpFlutter.onResult(
      onConnectedResult: (ConnectionTraffic traffic, Duration duration) {
        _addLog('✅ Connected! Duration: ${_formatDuration(duration)}');
        _addLog('📊 Download: ${_formatSpeed(traffic.downloadTraffic ?? 0)}');
        _addLog('📊 Upload: ${_formatSpeed(traffic.uploadTraffic ?? 0)}');
        
        _updateStatus(VpnConnectionStatus.connected);
        _connectionStartTime ??= DateTime.now();
        _downloadSpeed = traffic.downloadTraffic ?? 0;
        _uploadSpeed = traffic.uploadTraffic ?? 0;
      },
      onConnectingResult: () {
        _addLog('🔄 Connecting to VPN...');
        _updateStatus(VpnConnectionStatus.connecting);
      },
      onDisconnectedResult: () {
        _addLog('❌ Disconnected from VPN');
        _updateStatus(VpnConnectionStatus.disconnected);
        _connectionStartTime = null;
        _connectedServer = null;
        _downloadSpeed = 0;
        _uploadSpeed = 0;
      },
      onError: () {
        _addLog('⚠️ VPN connection error occurred');
        _updateStatus(VpnConnectionStatus.error);
        _connectionStartTime = null;
        _connectedServer = null;
      },
    );
  }
  
  void _updateStatus(VpnConnectionStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);
    }
  }
  
  /// Request VPN permission
  Future<bool> requestPermission() async {
    try {
      _addLog('📋 Requesting VPN permission...');
      await _sstpFlutter.takePermission();
      _addLog('✅ VPN permission granted');
      return true;
    } catch (e) {
      _addLog('❌ VPN permission denied: $e');
      return false;
    }
  }
  
  /// Connect to SSTP VPN server.
  ///
  /// MTU handling (all of these REALLY apply to the SSTP/PPP tunnel because they
  /// write the sstp_flutter plugin's `PPP_MTU` preference natively before the
  /// connect):
  ///   * [mtuMode] == 'off'    -> restore the plugin default (1500).
  ///   * [mtuMode] == 'manual' -> apply [manualMtu] (clamped to 1280..1500).
  ///   * [mtuMode] == 'auto'   -> run a REAL DF-bit path-MTU probe to the server
  ///                              and apply the detected value.
  Future<bool> connect(
    VpnServer server, {
    String dns = '8.8.8.8',
    String mtuMode = 'off',
    int manualMtu = 1400,
    String fragmentMode = 'off',
    int manualFragment = 1400,
  }) async {
    try {
      _addLog('🚀 Starting connection to ${server.fullAddress}');
      _addLog('   Server: ${server.address}');
      _addLog('   Port: ${server.port}');
      _addLog('   Username: ${server.username}');
      
      _updateStatus(VpnConnectionStatus.connecting);
      _connectedServer = server;

      // MTU tuning: applied natively to the SSTP/PPP tunnel before saving config.
      try {
        switch (mtuMode) {
          case 'manual':
            final m = manualMtu.clamp(1280, 1500);
            await DnsVpnConnection.setSstpMtu(m);
            _addLog('🔧 SSTP MTU set manually to $m');
            break;
          case 'auto':
            _addLog('🔎 Auto-detecting best MTU (DF-bit probe to ${server.address})...');
            final detected = await DnsVpnConnection.detectBestMtu(
              server.address,
              minMtu: 1280,
              maxMtu: 1500,
            );
            if (detected != null) {
              _addLog('✅ Auto MTU detected & applied: $detected');
            } else {
              // Probe failed (ICMP blocked) -> use a safe value.
              await DnsVpnConnection.setSstpMtu(1400);
              _addLog('⚠️ MTU probe failed, applied safe 1400');
            }
            break;
          default:
            await DnsVpnConnection.setSstpMtu(1500);
            _addLog('🔧 SSTP MTU set to default 1500');
        }
      } catch (e) {
        _addLog('⚠️ Failed to set MTU: $e');
      }

      // PPP fragmentation tuning (PPP MRU) — really applied to the SSTP tunnel.
      try {
        switch (fragmentMode) {
          case 'manual':
            final f = manualFragment.clamp(1280, 1500);
            await DnsVpnConnection.setSstpFragment(f);
            _addLog('🧩 SSTP fragment (MRU) set manually to $f');
            break;
          case 'auto':
            _addLog('🔎 Auto-detecting best fragment (MRU) to ${server.address}...');
            final detected = await DnsVpnConnection.detectBestFragment(
              server.address,
              minMru: 1280,
              maxMru: 1500,
            );
            if (detected != null) {
              _addLog('✅ Auto fragment detected & applied: $detected');
            } else {
              await DnsVpnConnection.setSstpFragment(1400);
              _addLog('⚠️ Fragment probe failed, applied safe 1400');
            }
            break;
          default:
            await DnsVpnConnection.setSstpFragment(1500);
            _addLog('🧩 SSTP fragment (MRU) set to default 1500');
        }
      } catch (e) {
        _addLog('⚠️ Failed to set fragment: $e');
      }
      
      // Create SSTP server configuration
      SSTPServer sstpServer = SSTPServer(
        host: server.address,
        port: server.port,
        username: server.username,
        password: server.password,
        androidConfiguration: SSTPAndroidConfiguration(
          verifyHostName: false,  // Don't verify hostname for public VPN servers
          useTrustedCert: false,  // Allow self-signed certificates
          verifySSLCert: false,   // Don't verify SSL cert for public servers
          sslVersion: SSLVersions.TLsv1_2,  // Use TLS 1.2
          showDisconnectOnNotification: true,
          notificationText: "4win VPN Connected",
        ),
        iosConfiguration: SSTPIOSConfiguration(
          enableMSCHAP2: true,
          enableCHAP: false,
          enablePAP: false,
          enableTLS: false,
        ),
      );
      
      _addLog('💾 Saving server configuration...');
      await _sstpFlutter.saveServerData(server: sstpServer);
      
      _addLog('🌐 Enabling DNS ($dns)...');
      await _sstpFlutter.enableDns(dns: dns);
      
      _addLog('🔌 Initiating VPN connection...');
      await _sstpFlutter.connectVpn();
      
      _addLog('⏳ Waiting for connection...');
      return true;
    } catch (e) {
      _addLog('❌ Connection failed: $e');
      _updateStatus(VpnConnectionStatus.error);
      _connectedServer = null;
      return false;
    }
  }
  
  /// Disconnect from VPN
  Future<void> disconnect() async {
    try {
      _addLog('🔌 Disconnecting from VPN...');
      _updateStatus(VpnConnectionStatus.disconnecting);
      
      await _sstpFlutter.disconnect();
      await _sstpFlutter.disableDNS();
      
      _addLog('✅ Disconnected successfully');
      _updateStatus(VpnConnectionStatus.disconnected);
      _connectionStartTime = null;
      _connectedServer = null;
      _downloadSpeed = 0;
      _uploadSpeed = 0;
    } catch (e) {
      _addLog('⚠️ Disconnect error: $e');
      _updateStatus(VpnConnectionStatus.error);
    }
  }
  
  /// Get connection duration
  Duration? getConnectionDuration() {
    if (_connectionStartTime == null || _currentStatus != VpnConnectionStatus.connected) {
      return null;
    }
    return DateTime.now().difference(_connectionStartTime!);
  }
  
  /// Check last connection status
  Future<String?> checkLastConnectionStatus() async {
    try {
      final status = await _sstpFlutter.checkLastConnectionStatus();
      _addLog('📊 Last connection status: $status');
      return status.toString();
    } catch (e) {
      _addLog('⚠️ Error checking status: $e');
      return null;
    }
  }
  
  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
  
  void dispose() {
    _statusController.close();
    _logController.close();
  }
}
