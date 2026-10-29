import 'xray_server.dart';

enum SimpleConnectionAttemptOutcome {
  connected,
  failed,
  permissionDenied,
  cancelled,
}

class SimpleConnectionAttempt {
  const SimpleConnectionAttempt({required this.protocol, this.xrayGroup});

  final String protocol;
  final String? xrayGroup;
}

/// One ordered fallback plan shared by the provider and its regression tests.
class SimpleConnectionPlan {
  static const List<SimpleConnectionAttempt> attempts = [
    SimpleConnectionAttempt(protocol: 'xray', xrayGroup: XrayServer.plusGroup),
    SimpleConnectionAttempt(protocol: 'warp'),
    SimpleConnectionAttempt(protocol: 'xray', xrayGroup: XrayServer.freeGroup),
  ];

  static Future<SimpleConnectionAttemptOutcome> execute(
    Future<SimpleConnectionAttemptOutcome> Function(
      SimpleConnectionAttempt attempt,
    ) runAttempt,
  ) async {
    for (final attempt in attempts) {
      final outcome = await runAttempt(attempt);
      if (outcome != SimpleConnectionAttemptOutcome.failed) return outcome;
    }
    return SimpleConnectionAttemptOutcome.failed;
  }

  /// Selects only from the requested built-in tier, never from a saved manual
  /// server/group and never based on ping. The native connect result decides
  /// whether the candidate works.
  static XrayServer? firstServerForGroup(
    Iterable<XrayServer> servers,
    String group,
  ) {
    for (final server in servers) {
      if (server.group == group) return server;
    }
    return null;
  }

  static XrayServer? resolveSimpleXrayTarget({
    required Iterable<XrayServer> servers,
    required String? simpleGroupOverride,
  }) {
    // Simple mode must never consult saved Advanced server/group selections.
    if (simpleGroupOverride == null) return null;
    return firstServerForGroup(servers, simpleGroupOverride);
  }
}

/// Holds the user's Advanced protocol while Simple mode temporarily uses a
/// different protocol. The saved value is consumed only after the Simple
/// tunnel stops (or the fallback sequence finishes unsuccessfully).
class SimpleConnectionSession {
  String? _savedAdvancedProtocol;

  bool get hasSavedAdvancedProtocol => _savedAdvancedProtocol != null;

  void captureAdvancedProtocol(String protocol) {
    _savedAdvancedProtocol ??= protocol;
  }

  String? restoreAdvancedProtocolIfStopped(
    String currentProtocol, {
    required bool simpleTunnelActive,
  }) {
    if (simpleTunnelActive || !hasSavedAdvancedProtocol) return null;
    return restoreAdvancedProtocol(currentProtocol);
  }

  String restoreAdvancedProtocol(String currentProtocol) {
    final savedProtocol = _savedAdvancedProtocol;
    _savedAdvancedProtocol = null;
    return savedProtocol ?? currentProtocol;
  }
}
