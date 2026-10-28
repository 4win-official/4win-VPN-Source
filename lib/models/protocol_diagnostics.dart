enum ConnectionStepState { pending, running, complete, failed, unverified, skipped }

enum ConnectionAttemptOutcome {
  connecting,
  connected,
  failed,
  cancelled,
  disconnected,
}

class ConnectionDiagnosticStep {
  const ConnectionDiagnosticStep({
    required this.title,
    this.state = ConnectionStepState.pending,
    this.detail,
  });

  final String title;
  final ConnectionStepState state;
  final String? detail;

  ConnectionDiagnosticStep copyWith({
    ConnectionStepState? state,
    String? detail,
  }) => ConnectionDiagnosticStep(
    title: title,
    state: state ?? this.state,
    detail: detail ?? this.detail,
  );
}

/// One in-memory snapshot of a standalone connection attempt. A completed
/// service-start step deliberately does not imply remote reachability; those
/// checks remain separate, visibly unverified steps unless a real signal exists.
class ProtocolDiagnostics {
  ProtocolDiagnostics({
    required this.attemptId,
    required this.protocol,
    required this.displayName,
    required List<ConnectionDiagnosticStep> steps,
    this.proxyMode = false,
    this.outcome = ConnectionAttemptOutcome.connecting,
    this.message,
  }) : steps = List.unmodifiable(steps);

  factory ProtocolDiagnostics.begin({
    required String protocol,
    required String attemptId,
    required bool proxyMode,
  }) {
    final steps = switch (protocol) {
      'xray' when proxyMode => const [
        ConnectionDiagnosticStep(title: 'Xray server selection'),
        ConnectionDiagnosticStep(title: 'Xray config generation'),
        ConnectionDiagnosticStep(title: 'Local Xray Proxy service start request'),
        ConnectionDiagnosticStep(
          title: 'Upstream server reachability',
          state: ConnectionStepState.unverified,
          detail: 'Service startup alone does not prove that the remote server responds.',
        ),
      ],
      'xray' => const [
        ConnectionDiagnosticStep(title: 'Xray server selection'),
        ConnectionDiagnosticStep(title: 'Android VPN permission'),
        ConnectionDiagnosticStep(title: 'Xray config generation'),
        ConnectionDiagnosticStep(title: 'Xray core start request'),
        ConnectionDiagnosticStep(
          title: 'VPN service / TUN state',
          state: ConnectionStepState.unverified,
          detail: 'The Xray start request alone does not prove the service or tunnel is live.',
        ),
        ConnectionDiagnosticStep(
          title: 'Remote traffic through the tunnel',
          state: ConnectionStepState.unverified,
          detail: 'A running Xray service does not prove remote reachability.',
        ),
      ],
      'proxy' when proxyMode => const [
        ConnectionDiagnosticStep(title: 'Proxy server selection'),
        ConnectionDiagnosticStep(title: 'Proxy config generation'),
        ConnectionDiagnosticStep(title: 'Local Proxy service start request'),
        ConnectionDiagnosticStep(
          title: 'Upstream proxy reachability',
          state: ConnectionStepState.unverified,
          detail: 'Local service startup does not prove that the upstream proxy responds.',
        ),
      ],
      'proxy' => const [
        ConnectionDiagnosticStep(title: 'Proxy server selection'),
        ConnectionDiagnosticStep(title: 'Android VPN permission'),
        ConnectionDiagnosticStep(title: 'Proxy config generation'),
        ConnectionDiagnosticStep(title: 'Proxy engine start request'),
        ConnectionDiagnosticStep(
          title: 'VPN service / TUN state',
          state: ConnectionStepState.unverified,
          detail: 'The engine start request alone does not prove the service or tunnel is live.',
        ),
        ConnectionDiagnosticStep(
          title: 'Upstream proxy traffic',
          state: ConnectionStepState.unverified,
          detail: 'A running local engine does not prove upstream traffic.',
        ),
      ],
      'warp' => const [
        ConnectionDiagnosticStep(title: 'Android VPN permission'),
        ConnectionDiagnosticStep(title: 'WARP identity'),
        ConnectionDiagnosticStep(title: 'WARP config generation'),
        ConnectionDiagnosticStep(
          title: 'WARP handshake and data-plane validation',
        ),
      ],
      'openvpn' => const [
        ConnectionDiagnosticStep(title: 'OpenVPN config and credentials'),
        ConnectionDiagnosticStep(title: 'OpenVPN permission and negotiation'),
        ConnectionDiagnosticStep(title: 'OpenVPN tunnel connected'),
        ConnectionDiagnosticStep(
          title: 'Internet traffic through the tunnel',
          state: ConnectionStepState.unverified,
          detail: 'The OpenVPN connected event does not independently prove internet access.',
        ),
      ],
      'sstp' => const [
        ConnectionDiagnosticStep(title: 'SSTP server TCP reachability'),
        ConnectionDiagnosticStep(title: 'Android VPN permission'),
        ConnectionDiagnosticStep(title: 'SSTP / PPP negotiation'),
        ConnectionDiagnosticStep(title: 'SSTP session connected'),
        ConnectionDiagnosticStep(
          title: 'Internet traffic through the tunnel',
          state: ConnectionStepState.unverified,
          detail: 'A connected PPP session does not independently prove internet access.',
        ),
      ],
      'psiphon' => const [
        ConnectionDiagnosticStep(title: 'Psiphon service start'),
        ConnectionDiagnosticStep(title: 'Psiphon core and traffic bridge'),
        ConnectionDiagnosticStep(
          title: 'Internet traffic through the tunnel',
          state: ConnectionStepState.unverified,
          detail: 'Core and bridge readiness do not prove that an internet request succeeds.',
        ),
      ],
      'direct_dns' => const [
        ConnectionDiagnosticStep(title: 'DNS server selection'),
        ConnectionDiagnosticStep(title: 'Android VPN permission'),
        ConnectionDiagnosticStep(title: 'DNS VPN service start request'),
        ConnectionDiagnosticStep(
          title: 'DNS VPN interface active',
          state: ConnectionStepState.unverified,
          detail: 'The start request is not an independent native interface-state check.',
        ),
        ConnectionDiagnosticStep(
          title: 'Selected DNS server probe',
          state: ConnectionStepState.unverified,
          detail: 'No successful DNS-server probe has been recorded for this attempt.',
        ),
      ],
      'slowdns' => const [
        ConnectionDiagnosticStep(title: 'Slow DNS profile validation'),
        ConnectionDiagnosticStep(title: 'Android VPN permission'),
        ConnectionDiagnosticStep(title: 'Native DNS tunnel start'),
        ConnectionDiagnosticStep(title: 'Authenticated resolver tunnel'),
        ConnectionDiagnosticStep(
          title: 'Internet traffic through the tunnel',
          state: ConnectionStepState.unverified,
          detail: 'An authenticated DNS tunnel does not independently prove internet access.',
        ),
      ],
      _ => const [ConnectionDiagnosticStep(title: 'Connection setup')],
    };
    final name = switch (protocol) {
      'xray' => proxyMode ? 'Xray Proxy' : 'Xray',
      'proxy' => 'Proxy',
      'warp' => 'WARP',
      'openvpn' => 'OpenVPN',
      'sstp' => 'SSTP',
      'psiphon' => 'Psiphon',
      'direct_dns' => 'DNS changer',
      'slowdns' => 'Slow DNS',
      _ => protocol,
    };
    return ProtocolDiagnostics(
      attemptId: attemptId,
      protocol: protocol,
      displayName: name,
      proxyMode: proxyMode,
      steps: steps,
    );
  }

  final String attemptId;
  final String protocol;
  final String displayName;
  final bool proxyMode;
  final List<ConnectionDiagnosticStep> steps;
  final ConnectionAttemptOutcome outcome;
  final String? message;

  ProtocolDiagnostics updateStep(
    int index,
    ConnectionStepState state, {
    String? detail,
  }) {
    if (index < 0 || index >= steps.length) return this;
    final next = List<ConnectionDiagnosticStep>.of(steps);
    next[index] = next[index].copyWith(state: state, detail: detail);
    return _copyWith(steps: next);
  }

  ProtocolDiagnostics updateOutcome(
    ConnectionAttemptOutcome nextOutcome, {
    String? message,
  }) => _copyWith(outcome: nextOutcome, message: message);

  ProtocolDiagnostics failCurrent(String message) {
    if (outcome != ConnectionAttemptOutcome.connecting) return this;
    final next = List<ConnectionDiagnosticStep>.of(steps);
    final alreadyFailed = next.indexWhere(
      (step) => step.state == ConnectionStepState.failed,
    );
    if (alreadyFailed >= 0) {
      return _copyWith(
        steps: next,
        outcome: ConnectionAttemptOutcome.failed,
        message: message,
      );
    }
    final active = next.indexWhere(
      (step) => step.state == ConnectionStepState.running,
    );
    final firstPending = next.indexWhere(
      (step) => step.state == ConnectionStepState.pending,
    );
    final failed = active >= 0 ? active : firstPending;
    if (failed >= 0) {
      final previousDetail = next[failed].detail;
      next[failed] = next[failed].copyWith(
        state: ConnectionStepState.failed,
        detail: previousDetail == null || previousDetail.isEmpty
            ? message
            : '$previousDetail\n$message',
      );
    }
    return _copyWith(
      steps: next,
      outcome: ConnectionAttemptOutcome.failed,
      message: message,
    );
  }

  ProtocolDiagnostics failModeValidation(String message) => _copyWith(
    steps: [
      ConnectionDiagnosticStep(
        title: 'Connection mode validation',
        state: ConnectionStepState.failed,
        detail: message,
      ),
      ...steps.map(
        (step) => ConnectionDiagnosticStep(
          title: step.title,
          state: step.state == ConnectionStepState.unverified
              ? ConnectionStepState.unverified
              : ConnectionStepState.pending,
          detail: step.state == ConnectionStepState.unverified
              ? step.detail
              : null,
        ),
      ),
    ],
    outcome: ConnectionAttemptOutcome.failed,
    message: message,
  );

  ProtocolDiagnostics _copyWith({
    List<ConnectionDiagnosticStep>? steps,
    ConnectionAttemptOutcome? outcome,
    String? message,
  }) => ProtocolDiagnostics(
    attemptId: attemptId,
    protocol: protocol,
    displayName: displayName,
    proxyMode: proxyMode,
    steps: steps ?? this.steps,
    outcome: outcome ?? this.outcome,
    message: message ?? this.message,
  );
}
