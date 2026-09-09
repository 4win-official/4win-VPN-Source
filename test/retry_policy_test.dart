import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_swift/services/retry_policy.dart';

void main() {
  group('RetryPolicy', () {
    test('first attempt runs immediately', () {
      const policy = RetryPolicy();
      expect(policy.delayForAttempt(0), Duration.zero);
      expect(policy.delayForAttempt(-1), Duration.zero);
    });

    test('delays grow exponentially', () {
      const policy = RetryPolicy(
        maxAttempts: 10,
        initialDelay: Duration(seconds: 2),
        maxDelay: Duration(seconds: 1000),
        multiplier: 2.0,
      );
      expect(policy.delayForAttempt(1), const Duration(seconds: 2));
      expect(policy.delayForAttempt(2), const Duration(seconds: 4));
      expect(policy.delayForAttempt(3), const Duration(seconds: 8));
      expect(policy.delayForAttempt(4), const Duration(seconds: 16));
    });

    test('delays are capped at maxDelay', () {
      const policy = RetryPolicy(
        maxAttempts: 10,
        initialDelay: Duration(seconds: 5),
        maxDelay: Duration(seconds: 60),
        multiplier: 2.0,
      );
      expect(policy.delayForAttempt(4), const Duration(seconds: 40));
      expect(policy.delayForAttempt(5), const Duration(seconds: 60));
      expect(policy.delayForAttempt(6), const Duration(seconds: 60));
      expect(policy.delayForAttempt(100), const Duration(seconds: 60));
    });

    test('shouldRetry respects maxAttempts', () {
      const policy = RetryPolicy(maxAttempts: 3);
      expect(policy.shouldRetry(-1), isFalse);
      expect(policy.shouldRetry(0), isTrue);
      expect(policy.shouldRetry(1), isTrue);
      expect(policy.shouldRetry(2), isTrue);
      expect(policy.shouldRetry(3), isFalse);
      expect(policy.shouldRetry(99), isFalse);
    });

    test('maxAttempts <= 0 retries forever', () {
      const policy = RetryPolicy(maxAttempts: 0);
      expect(policy.shouldRetry(0), isTrue);
      expect(policy.shouldRetry(1000), isTrue);
    });

    test('psiphonConnect preset: 4 attempts, now/+2s/+4s/+8s', () {
      const policy = RetryPolicy.psiphonConnect;
      expect(policy.maxAttempts, 4);
      expect(policy.delayForAttempt(0), Duration.zero);
      expect(policy.delayForAttempt(1), const Duration(seconds: 2));
      expect(policy.delayForAttempt(2), const Duration(seconds: 4));
      expect(policy.delayForAttempt(3), const Duration(seconds: 8));
      expect(policy.shouldRetry(3), isTrue);
      expect(policy.shouldRetry(4), isFalse);
    });

    test('psiphonMonitor preset: 5 attempts with 60s cap', () {
      const policy = RetryPolicy.psiphonMonitor;
      expect(policy.maxAttempts, 5);
      expect(policy.delayForAttempt(1), const Duration(seconds: 5));
      expect(policy.delayForAttempt(2), const Duration(seconds: 10));
      expect(policy.delayForAttempt(3), const Duration(seconds: 20));
      expect(policy.delayForAttempt(4), const Duration(seconds: 40));
      expect(policy.delayForAttempt(5), const Duration(seconds: 60));
      expect(policy.shouldRetry(4), isTrue);
      expect(policy.shouldRetry(5), isFalse);
    });

    test('psiphonMonitorKillSwitch preset: unlimited, capped at 60s', () {
      const policy = RetryPolicy.psiphonMonitorKillSwitch;
      expect(policy.shouldRetry(0), isTrue);
      expect(policy.shouldRetry(1000), isTrue);
      expect(policy.delayForAttempt(10), const Duration(seconds: 60));
    });
  });
}
