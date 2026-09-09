import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Severity of a [ConnectionLogEntry].
enum ConnectionLogLevel { info, success, warning, error }

/// One timestamped line in the unified connection log.
class ConnectionLogEntry {
  final DateTime time;
  final String protocol; // e.g. 'psiphon', 'xray', 'sstp', 'app'
  final ConnectionLogLevel level;
  final String message;

  const ConnectionLogEntry({
    required this.time,
    required this.protocol,
    required this.level,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'p': protocol,
        'l': level.index,
        'm': message,
      };

  factory ConnectionLogEntry.fromJson(Map<String, dynamic> json) {
    final levelIndex = (json['l'] as num?)?.toInt() ?? 0;
    return ConnectionLogEntry(
      time: DateTime.tryParse(json['t'] as String? ?? '') ?? DateTime.now(),
      protocol: json['p'] as String? ?? 'app',
      level: levelIndex >= 0 && levelIndex < ConnectionLogLevel.values.length
          ? ConnectionLogLevel.values[levelIndex]
          : ConnectionLogLevel.info,
      message: json['m'] as String? ?? '',
    );
  }

  /// Short `HH:mm:ss` stamp for the log viewer.
  String get timeStamp {
    final t = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// App-wide, in-memory ring buffer of connection events (all protocols +
/// native Psiphon service lines), exposed as a [ChangeNotifier] for the log
/// viewer screen.
///
/// The tail of the log is also persisted to SharedPreferences (throttled), so
/// the events *before* a crash/restart are still visible afterwards.
class ConnectionLogger extends ChangeNotifier {
  static final ConnectionLogger instance = ConnectionLogger._internal();

  ConnectionLogger._internal();

  static const int maxEntries = 500;
  static const int persistEntries = 200;
  static const int maxMessageLength = 500;
  static const String _prefsKey = 'connection_logs_v1';
  static const Duration _persistThrottle = Duration(seconds: 2);

  final List<ConnectionLogEntry> _entries = [];
  DateTime? _lastPersist;
  Timer? _pendingPersist;
  bool _loaded = false;

  List<ConnectionLogEntry> get entries => List.unmodifiable(_entries);

  bool get isLoaded => _loaded;

  /// Protocols currently present in the log (for filter chips).
  List<String> get protocols {
    final set = <String>{};
    for (final e in _entries) {
      set.add(e.protocol);
    }
    final list = set.toList()..sort();
    return list;
  }

  void log(String protocol, String message,
      [ConnectionLogLevel level = ConnectionLogLevel.info]) {
    final trimmed =
        message.length > maxMessageLength ? message.substring(0, maxMessageLength) : message;
    _entries.add(ConnectionLogEntry(
      time: DateTime.now(),
      protocol: protocol,
      level: level,
      message: trimmed,
    ));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
    _schedulePersist();
  }

  void info(String protocol, String message) =>
      log(protocol, message, ConnectionLogLevel.info);

  void success(String protocol, String message) =>
      log(protocol, message, ConnectionLogLevel.success);

  void warning(String protocol, String message) =>
      log(protocol, message, ConnectionLogLevel.warning);

  void error(String protocol, String message) =>
      log(protocol, message, ConnectionLogLevel.error);

  Future<void> clear() async {
    _entries.clear();
    _pendingPersist?.cancel();
    _pendingPersist = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// Loads the persisted tail (from before the last restart) once.
  Future<void> loadPersisted() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(ConnectionLogEntry.fromJson)
          .toList();
      if (list.isEmpty) return;
      _entries.addAll(list);
      if (_entries.length > maxEntries) {
        _entries.removeRange(0, _entries.length - maxEntries);
      }
      notifyListeners();
    } catch (_) {}
  }

  void _schedulePersist() {
    final now = DateTime.now();
    if (_lastPersist != null &&
        now.difference(_lastPersist!) < _persistThrottle) {
      // Throttled: persist once shortly after logging settles.
      _pendingPersist ??= Timer(_persistThrottle, () {
        _pendingPersist = null;
        _persist();
      });
      return;
    }
    _persist();
  }

  Future<void> _persist() async {
    _lastPersist = DateTime.now();
    try {
      final tail = _entries.length > persistEntries
          ? _entries.sublist(_entries.length - persistEntries)
          : _entries;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(tail.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// Visible for tests: bypass the singleton for isolation.
  @visibleForTesting
  static ConnectionLogger detached() => ConnectionLogger._internal();
}
