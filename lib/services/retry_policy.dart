import 'dart:math';

/// Exponential-backoff retry policy (pure Dart, fully unit-testable).
///
/// [attempt] is the 0-based index of the attempt that is about to run:
/// attempt 0 runs immediately ([delayForAttempt] returns [Duration.zero]),
/// attempt 1 waits [initialDelay], attempt 2 waits `initialDelay * multiplier`,
/// and so on, capped at [maxDelay].
///
/// [maxAttempts] <= 0 means "retry forever" (used by the kill-switch monitor,
/// which must never give up while traffic is being blackholed).
class RetryPolicy {
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;

  const RetryPolicy({
    this.maxAttempts = 4,
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 60),
    this.multiplier = 2.0,
  }) : assert(multiplier >= 1.0);

  /// Fresh Psiphon connect taps: 4 attempts — now, +2s, +4s, +8s.
  static const RetryPolicy psiphonConnect = RetryPolicy(
    maxAttempts: 4,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 10),
  );

  /// Background health monitor without kill switch: 5 recovery attempts —
  /// +5s, +10s, +20s, +40s, +60s — then give up and report an error.
  static const RetryPolicy psiphonMonitor = RetryPolicy(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 5),
    maxDelay: Duration(seconds: 60),
  );

  /// Background health monitor WITH kill switch on: never give up, capped at
  /// one attempt per minute. Leaking traffic is worse than retrying forever.
  static const RetryPolicy psiphonMonitorKillSwitch = RetryPolicy(
    maxAttempts: 0,
    initialDelay: Duration(seconds: 5),
    maxDelay: Duration(seconds: 60),
  );

  bool shouldRetry(int attempt) {
    if (attempt < 0) return false;
    if (maxAttempts <= 0) return true; // unlimited
    return attempt < maxAttempts;
  }

  Duration delayForAttempt(int attempt) {
    if (attempt <= 0) return Duration.zero;
    final scaled =
        initialDelay.inMicroseconds * pow(multiplier, attempt - 1).toDouble();
    final micros =
        scaled.isFinite ? scaled.round() : maxDelay.inMicroseconds;
    final delay = Duration(microseconds: micros);
    return delay > maxDelay ? maxDelay : delay;
  }
}
