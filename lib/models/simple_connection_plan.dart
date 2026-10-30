import 'xray_server.dart';

enum SimpleConnectionAttemptOutcome {
  connected,
  failed,
  permissionDenied,
  cancelled,
}

class SimpleConnectionAttempt {
  const SimpleConnectionAttempt({
    required this.protocol,
    this.xrayGroup,
    this.xrayServerId,
  });

  final String protocol;
  final String? xrayGroup;
  final String? xrayServerId;
}

/// One ordered fallback plan shared by the provider and its regression tests.
class SimpleConnectionPlan {
  static const List<SimpleConnectionAttempt> attempts = [
    SimpleConnectionAttempt(protocol: 'warp'),
    SimpleConnectionAttempt(protocol: 'xray', xrayGroup: XrayServer.plusGroup),
    SimpleConnectionAttempt(protocol: 'xray', xrayGroup: XrayServer.freeGroup),
  ];

  static Future<SimpleConnectionAttemptOutcome> execute(
    Future<SimpleConnectionAttemptOutcome> Function(
      SimpleConnectionAttempt attempt,
    ) runAttempt, {
    List<SimpleConnectionAttempt>? plan,
  }) async {
    for (final attempt in plan ?? attempts) {
      final outcome = await runAttempt(attempt);
      if (outcome != SimpleConnectionAttemptOutcome.failed) return outcome;
    }
    return SimpleConnectionAttemptOutcome.failed;
  }

  static List<SimpleConnectionAttempt> xrayTargetsForGroup(
    String group,
    Iterable<XrayServer> servers,
  ) => servers
      .where((server) => server.group == group)
      .map(
        (server) => SimpleConnectionAttempt(
          protocol: 'xray',
          xrayGroup: group,
          xrayServerId: server.id,
        ),
      )
      .toList();

  /// Returns the next user-feedback cycle without changing Advanced selections.
  /// WARP advances to Plus, Plus advances to Free, and a Free target advances
  /// to the next Free server before wrapping through WARP and Plus.
  static List<SimpleConnectionAttempt> cycleAfter({
    required SimpleConnectionAttempt current,
    required Iterable<XrayServer> freeServers,
  }) {
    const warp = SimpleConnectionAttempt(protocol: 'warp');
    const plusGroup = SimpleConnectionAttempt(
      protocol: 'xray',
      xrayGroup: XrayServer.plusGroup,
    );
    const freeGroup = SimpleConnectionAttempt(
      protocol: 'xray',
      xrayGroup: XrayServer.freeGroup,
    );

    final freeTargets = freeServers
        .where((server) => server.group == XrayServer.freeGroup)
        .map(
          (server) => SimpleConnectionAttempt(
            protocol: 'xray',
            xrayGroup: XrayServer.freeGroup,
            xrayServerId: server.id,
          ),
        )
        .toList();

    if (current.protocol == 'warp') return [plusGroup, freeGroup, warp];
    if (current.protocol != 'xray') return attempts;
    if (current.xrayGroup == XrayServer.plusGroup) {
      return [freeGroup, warp, plusGroup];
    }
    if (current.xrayGroup != XrayServer.freeGroup) return attempts;

    final currentIndex = freeTargets.indexWhere(
      (attempt) => attempt.xrayServerId == current.xrayServerId,
    );
    if (currentIndex < 0) return [...freeTargets, warp, plusGroup];
    return [
      ...freeTargets.skip(currentIndex + 1),
      warp,
      plusGroup,
      ...freeTargets.take(currentIndex + 1),
    ];
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

/// Tracks whether the user approved the current, persisted Simple connection.
/// A later connection always receives a new session ID and asks again.
class SimpleConnectionFeedbackState {
  String? _activeSessionId;
  String? _satisfiedSessionId;
  String? _leftAppSessionId;

  String? get activeSessionId => _activeSessionId;
  String? get satisfiedSessionId => _satisfiedSessionId;
  String? get leftAppSessionId => _leftAppSessionId;
  bool get needsFeedback =>
      _activeSessionId != null && _activeSessionId != _satisfiedSessionId;
  bool get feedbackReadyOnReturn =>
      needsFeedback && _leftAppSessionId == _activeSessionId;

  void restore({
    String? activeSessionId,
    String? satisfiedSessionId,
    String? leftAppSessionId,
  }) {
    _activeSessionId = activeSessionId;
    _satisfiedSessionId = satisfiedSessionId;
    _leftAppSessionId = leftAppSessionId;
  }

  void beginSession(String sessionId) {
    _activeSessionId = sessionId;
    _satisfiedSessionId = null;
    _leftAppSessionId = null;
  }

  bool markAppLeft() {
    if (!needsFeedback) return false;
    _leftAppSessionId = _activeSessionId;
    return true;
  }

  bool markSatisfied() {
    final sessionId = _activeSessionId;
    if (sessionId == null) return false;
    _satisfiedSessionId = sessionId;
    _leftAppSessionId = null;
    return true;
  }

  void clearSatisfiedMarker() {
    _satisfiedSessionId = null;
  }

  void clear() {
    _activeSessionId = null;
    _satisfiedSessionId = null;
    _leftAppSessionId = null;
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
