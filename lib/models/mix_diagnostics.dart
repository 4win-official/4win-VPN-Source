import 'mix_strategy.dart';

enum MixBlockState { pending, starting, ready, verified, failed, unverified }

/// An attempt owns a frozen copy of the configured chain, never a filtered
/// transport-only list. Ready means initialized, not individually reachable.
class MixDiagnostics {
  MixDiagnostics({
    required this.attemptId,
    required this.strategyId,
    required this.strategyName,
    required List<MixHop> hops,
    required List<MixBlockState> states,
    List<String?>? details,
    this.phase = 'Preparing chain',
    this.message,
  }) : hops = List.unmodifiable(hops),
       states = List.unmodifiable(states),
       details = List.unmodifiable(
         details ?? List<String?>.filled(hops.length, null),
       );

  factory MixDiagnostics.begin(MixStrategy strategy, String attemptId) =>
      MixDiagnostics(
        attemptId: attemptId,
        strategyId: strategy.id,
        strategyName: strategy.name,
        hops: strategy.hops,
        states: List.filled(strategy.hops.length, MixBlockState.pending),
      );

  final String attemptId;
  final String strategyId;
  final String strategyName;
  final List<MixHop> hops;
  final List<MixBlockState> states;
  final List<String?> details;
  final String phase;
  final String? message;

  MixDiagnostics update({
    String? phase,
    String? message,
    List<MixBlockState>? states,
    List<String?>? details,
  }) => MixDiagnostics(
    attemptId: attemptId,
    strategyId: strategyId,
    strategyName: strategyName,
    hops: hops,
    states: states ?? this.states,
    details: details ?? this.details,
    phase: phase ?? this.phase,
    message: message,
  );

  /// Ignore stale, incomplete or malformed native snapshots in their entirety.
  MixDiagnostics applyNative(Map<dynamic, dynamic> snapshot) {
    if (snapshot['attemptId'] != attemptId) return this;
    final blocks = snapshot['blocks'];
    if (blocks is! List || blocks.length != hops.length) return this;
    final next = List<MixBlockState>.filled(hops.length, MixBlockState.pending);
    final nextDetails = List<String?>.filled(hops.length, null);
    final seen = <int>{};
    for (final block in blocks) {
      if (block is! Map) return this;
      final index = block['index'];
      if (index is! int ||
          index < 0 ||
          index >= hops.length ||
          !seen.add(index)) {
        return this;
      }
      final state = switch (block['state']) {
        'pending' => MixBlockState.pending,
        'starting' => MixBlockState.starting,
        'ready' => MixBlockState.ready,
        'verified' => MixBlockState.verified,
        'failed' => MixBlockState.failed,
        _ => null,
      };
      if (state == null) return this;
      next[index] = state;
      final detail = block['detail'];
      if (detail != null && detail is! String) return this;
      nextDetails[index] = detail as String?;
    }
    final nextPhase = snapshot['phase'] is String
        ? snapshot['phase'] as String
        : phase;
    final nextMessage = (snapshot['message'] ?? snapshot['error']) == null
        ? null
        : (next.contains(MixBlockState.failed)
              ? 'The highlighted block reported an error.'
              : 'The failing block could not be identified reliably.');
    if (nextPhase == phase &&
        nextMessage == message &&
        List.generate(
          next.length,
          (i) => next[i] == states[i],
        ).every((v) => v) &&
        List.generate(
          nextDetails.length,
          (i) => nextDetails[i] == details[i],
      ).every((v) => v)) {
      return this;
    }
    return update(
      states: next,
      details: nextDetails,
      phase: nextPhase,
      message: nextMessage,
    );
  }
}
