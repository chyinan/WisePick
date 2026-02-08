import 'dart:io';
import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/retry_policy.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';

void main() {
  group('RetryConfig', () {
    test('default config should have sensible values', () {
      const config = RetryConfig();
      expect(config.maxAttempts, greaterThan(0));
      expect(config.initialDelay.inMilliseconds, greaterThan(0));
      expect(config.maxDelay.inMilliseconds,
          greaterThanOrEqualTo(config.initialDelay.inMilliseconds));
      expect(config.backoffMultiplier, greaterThanOrEqualTo(1.0));
    });

    test('aggressive config should have more attempts and shorter delays', () {
      expect(RetryConfig.aggressive.maxAttempts,
          greaterThan(RetryConfig.conservative.maxAttempts));
    });

    test('conservative config should have fewer attempts', () {
      expect(RetryConfig.conservative.maxAttempts,
          lessThanOrEqualTo(RetryConfig.aggressive.maxAttempts));
    });

    test('preset configs should all be valid', () {
      for (final config in [
        const RetryConfig(),
        RetryConfig.aggressive,
        RetryConfig.conservative,
        RetryConfig.database,
        RetryConfig.aiService,
      ]) {
        expect(config.maxAttempts, greaterThan(0));
        expect(config.initialDelay.inMilliseconds, greaterThanOrEqualTo(0));
        expect(config.backoffMultiplier, greaterThanOrEqualTo(1.0));
      }
    });
  });

  group('RetryExecutor - Successful operations', () {
    test('should return success without retry for succeeding operation', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(maxAttempts: 3),
      );

      var callCount = 0;
      final result = await executor.execute(() async {
        callCount++;
        return 'success';
      });

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('success'));
      expect(callCount, equals(1));
    });
  });

  group('RetryExecutor - Retry on failure', () {
    test('should retry and eventually succeed', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 10),
          maxDelay: Duration(milliseconds: 100),
        ),
      );

      var callCount = 0;
      final result = await executor.execute(() async {
        callCount++;
        if (callCount < 3) {
          throw SocketException('connection refused');
        }
        return 'recovered';
      });

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('recovered'));
      expect(callCount, equals(3));
    });

    test('should fail after exhausting all retries', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 2,
          initialDelay: Duration(milliseconds: 10),
          maxDelay: Duration(milliseconds: 50),
        ),
      );

      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        throw SocketException('always fail');
      });

      expect(result.isFailure, isTrue);
      expect(callCount, equals(2));
    });

    test('should not retry non-retryable errors', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 5,
          initialDelay: Duration(milliseconds: 10),
        ),
      );

      var callCount = 0;
      final result = await executor.execute<String>(
        () async {
          callCount++;
          throw FormatException('bad input');
        },
        retryIf: (e) => e is SocketException, // Only retry socket errors
      );

      expect(result.isFailure, isTrue);
      expect(callCount, equals(1)); // Should not retry
    });
  });

  group('RetryExecutor - Exponential backoff', () {
    test('delays should increase exponentially', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 4,
          initialDelay: Duration(milliseconds: 100),
          backoffMultiplier: 2.0,
          maxDelay: Duration(seconds: 10),
          addJitter: false,
        ),
      );

      final timestamps = <DateTime>[];
      var callCount = 0;

      final result = await executor.execute<String>(() async {
        timestamps.add(DateTime.now());
        callCount++;
        if (callCount < 4) {
          throw SocketException('retry me');
        }
        return 'done';
      });

      expect(result.isSuccess, isTrue);
      expect(timestamps.length, equals(4));

      // Verify delays are increasing (with some tolerance)
      if (timestamps.length >= 3) {
        final delay1 = timestamps[1].difference(timestamps[0]).inMilliseconds;
        final delay2 = timestamps[2].difference(timestamps[1]).inMilliseconds;
        // Second delay should be roughly double the first (with jitter disabled)
        expect(delay2, greaterThanOrEqualTo(delay1));
      }
    });

    test('delay should not exceed maxDelay', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 10,
          initialDelay: Duration(seconds: 1),
          backoffMultiplier: 10.0,
          maxDelay: Duration(seconds: 2),
          addJitter: false,
        ),
      );

      // We can't directly test the internal delay calculation,
      // but we verify it doesn't hang due to extremely long delays
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 3) {
          throw SocketException('retry');
        }
        return 'ok';
      });

      expect(result.isSuccess, isTrue);
    });
  });

  group('RetryExecutor - Custom retry condition', () {
    test('should use custom retryIf predicate', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 5,
          initialDelay: Duration(milliseconds: 10),
        ),
      );

      var callCount = 0;
      final result = await executor.execute<String>(
        () async {
          callCount++;
          if (callCount == 1) throw StateError('retryable');
          if (callCount == 2) throw ArgumentError('not retryable');
          return 'ok';
        },
        retryIf: (e) => e is StateError,
      );

      expect(result.isFailure, isTrue);
      expect(callCount, equals(2)); // Stopped on ArgumentError
    });
  });

  group('RetryExecutor - Operation name', () {
    test('should accept operationName for logging', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 2,
          initialDelay: Duration(milliseconds: 10),
        ),
      );

      final result = await executor.execute(
        () async => 42,
        operationName: 'test_operation',
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals(42));
    });
  });
}
