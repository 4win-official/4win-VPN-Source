import 'dart:io';
import 'package:flutter/services.dart';
import '../models/psiphon_server.dart';

/// Dart bridge to the native Psiphon VPN service (`com.forwin.vpn/psiphon`).
///
/// The native service runs in the dedicated `:psiphon` process; all state
/// reads are served from the main-process [PsiphonStatusStore] cache, which is
/// fed by cross-process broadcasts (with a staleness guard, so a dead service
/// process reads back as disconnected instead of sticking on "connected").
///
/// Every method is total: platform errors / missing plugins degrade to safe
/// defaults instead of throwing, so callers can poll from timers safely.
class PsiphonService {
  static const MethodChannel _channel = MethodChannel('com.forwin.vpn/psiphon');

  /// Requests VPN permission if needed. On first run, waits for the system
  /// consent result; false means denial, Activity loss, or a platform error.
  /// An already-granted permission resolves immediately.
  Future<bool> prepare() async {
    try {
      return await _channel.invokeMethod<bool>('prepare') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> start({String egressRegion = '', String? targetServerId}) async {
    try {
      if (!await prepare()) return false;
      return await _channel.invokeMethod<bool>('start', {
            'egressRegion': egressRegion,
            if (targetServerId != null) 'targetServerId': targetServerId,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      return await _channel.invokeMethod<bool>('stop') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Synchronizes the saved preference with the isolated native Psiphon process.
  /// A live update lets disabling the switch release an existing blackhole.
  Future<bool> setKillSwitchEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('updateKillSwitch', {
            'enabled': enabled,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reconnect() async {
    try {
      return await _channel.invokeMethod<bool>('reconnect') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isRunning async {
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isConnected async {
    try {
      return await _channel.invokeMethod<bool>('isConnected') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Last status text emitted by the native Psiphon service. This is useful
  /// for distinguishing a terminal native startup error from a slow startup.
  Future<String> get statusText async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getStatus');
      if (raw is String) return raw;
      if (raw is Map) {
        return (raw['statusText'] ?? raw['status'] ?? raw['text'] ?? '')
            .toString();
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// True while the native service is temporarily restoring the tunnel.
  /// Older native builds return a status string, so treat those as false.
  Future<bool> get isReconnecting async {
    try {
      final raw = await _channel.invokeMethod<Object?>('getStatus');
      return raw is Map && raw['reconnecting'] == true;
    } catch (_) {
      return false;
    }
  }

  /// True when the native kill-switch blackhole is holding the TUN interface
  /// (tunnel down, traffic blocked, service alive).
  Future<bool> get isKillSwitchActive async {
    try {
      return await _channel.invokeMethod<bool>('isKillSwitchActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cumulative tunnel bytes since connect: `{'uplink': int, 'downlink': int}`.
  Future<Map<String, int>> queryStats() async {
    try {
      final raw = await _channel.invokeMethod<Map>('queryStats');
      if (raw == null) return const {'uplink': 0, 'downlink': 0};
      int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return {
        'uplink': asInt(raw['uplink']),
        'downlink': asInt(raw['downlink']),
      };
    } catch (_) {
      return const {'uplink': 0, 'downlink': 0};
    }
  }

  /// Timestamped native log lines buffered by the `:psiphon` process
  /// (plus `[bridge]` lines from the `:psiphonbridge` process).
  Future<List<String>> getNativeLogs() async {
    try {
      final raw = await _channel.invokeMethod<List>('getPsiphonLogs');
      if (raw == null) return const [];
      return raw.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Exit servers (egress regions) the Psiphon tunnel core last reported as
  /// available: `{'count': int, 'regions': List<String>}` (e.g. US, DE, NL…).
  ///
  /// The core only reports while the tunnel is running, so before the first
  /// connect this returns count 0 with an empty list. Total: degrades to
  /// zero/empty on any platform error.
  Future<Map<String, dynamic>> getServers() async {
    try {
      final raw = await _channel.invokeMethod<Map>('getPsiphonServers');
      if (raw == null) return const {'count': 0, 'regions': <String>[]};
      int asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      final regions =
          (raw['regions'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[];
      var count = asInt(raw['count']);
      if (count == 0 && regions.isNotEmpty) count = regions.length;
      return {'count': count, 'regions': regions};
    } catch (_) {
      return const {'count': 0, 'regions': <String>[]};
    }
  }

  /// Signed cached/bundled server metadata, distinct from runtime exit regions.
  Future<PsiphonServerList> getServerList() async {
    try {
      final raw = await _channel.invokeMethod<Map>('getServerList');
      if (raw != null) return PsiphonServerList.fromMap(raw);
    } catch (_) {
      // The UI may retry without affecting an active connection.
    }
    return const PsiphonServerList(
      error: 'Unable to read the verified server list.',
    );
  }

  /// Explicit manual refresh; native code verifies and atomically publishes off-thread.
  Future<PsiphonRefreshResult> refreshServerListNow() async {
    try {
      final raw = await _channel.invokeMethod<Map>('refreshServerListNow');
      if (raw != null) {
        return PsiphonRefreshResult(
          updated: raw['updated'] == true,
          busy: raw['busy'] == true,
          error: raw['error']?.toString(),
        );
      }
    } catch (_) {
      // Failed/manual maintenance must not stop the VPN or discard cached rows.
    }
    return const PsiphonRefreshResult(
      error: 'Refresh unavailable. The last valid list is unchanged.',
    );
  }

  /// TCP connect time only: no Psiphon authentication, VPN delay or ICMP measurement.
  /// Uses normal app routing and never bypasses a VPN or kill switch.
  Future<int?> testServerLatency(PsiphonServer server) async {
    final address = InternetAddress.tryParse(server.ipAddress);
    final port = server.port;
    if (address == null || port == null || port < 1 || port > 65535) {
      return null;
    }
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      socket = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 3),
      );
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      stopwatch.stop();
      socket?.destroy();
    }
  }
}
