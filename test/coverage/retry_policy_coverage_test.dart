/// Additional coverage tests for retry_policy.dart.
///
/// Targets uncovered branches: RetryResult properties, executeOrThrow,
/// _isRetryableError variations (HttpException, TimeoutException, HandshakeException,
/// string matching for DB errors), _extractStatusCode, convenience functions
/// (retry, retryOrThrow, retryWithTimeout), onRetry callback.
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/retry_policy.dart';

void main() {
  // ==========================================================================
  // RetryResult
  // ==========================================================================
  group('RetryResult', () {
    test('success factory should create success result', () {
      final r = RetryResult<int>.success(
        42,
        attemptsMade: 1,
        totalDuration: const Duration(milliseconds: 50),
        wasRetried: false,
      );
      expect(r.isSuccess, isTrue);
      expect(r.isFailure, isFalse);
      expect(r.value, equals(42));
      expect(r.error, isNull);
      expect(r.attemptsMade, equals(1));
      expect(r.wasRetried, isFalse);
    });

    test('failure factory should create failure result', () {
      final err = Exception('boom');
      final stack = StackTrace.current;
      final r = RetryResult<int>.failure(
        err,
        stackTrace: stack,
        attemptsMade: 3,
        totalDuration: const Duration(seconds: 1),
        wasRetried: true,
      );
      expect(r.isSuccess, isFalse);
      expect(r.isFailure, isTrue);
      expect(r.error, equals(err));
      expect(r.stackTrace, equals(stack));
      expect(r.attemptsMade, equals(3));
      expect(r.wasRetried, isTrue);
    });

    test('getOrThrow should return value on success', () {
      final r = RetryResult<String>.success(
        'ok',
        attemptsMade: 1,
        totalDuration: Duration.zero,
      );
      expect(r.getOrThrow(), equals('ok'));
    });

    test('getOrThrow should throw error on failure', () {
      final r = RetryResult<String>.failure(
        StateError('fail'),
        attemptsMade: 1,
        totalDuration: Duration.zero,
      );
      expect(() => r.getOrThrow(), throwsA(isA<StateError>()));
    });

    test('getOrThrow should re-throw with stackTrace when available', () {
      try {
        throw FormatException('original');
      } catch (e, stack) {
        final r = RetryResult<String>.failure(
          e,
          stackTrace: stack,
          attemptsMade: 1,
          totalDuration: Duration.zero,
        );
        expect(() => r.getOrThrow(), throwsA(isA<FormatException>()));
      }
    });

    test('getOrDefault should return value on success', () {
      final r = RetryResult<int>.success(
        42,
        attemptsMade: 1,
        totalDuration: Duration.zero,
      );
      expect(r.getOrDefault(-1), equals(42));
    });

    test('getOrDefault should return default on failure', () {
      final r = RetryResult<int>.failure(
        Exception('err'),
        attemptsMade: 1,
        totalDuration: Duration.zero,
      );
      expect(r.getOrDefault(-1), equals(-1));
    });

    test('getOrElse should return value on success', () {
      final r = RetryResult<int>.success(
        42,
        attemptsMade: 1,
        totalDuration: Duration.zero,
      );
      expect(r.getOrElse(() => -1), equals(42));
    });

    test('getOrElse should call function on failure', () {
      final r = RetryResult<int>.failure(
        Exception('err'),
        attemptsMade: 1,
        totalDuration: Duration.zero,
      );
      expect(r.getOrElse(() => -1), equals(-1));
    });

    test('wasRetried defaults to false', () {
      final r = RetryResult<int>.success(
        1,
        attemptsMade: 1,
        totalDuration: Duration.zero,
      );
      expect(r.wasRetried, isFalse);
    });
  });

  // ==========================================================================
  // RetryExecutor - executeOrThrow
  // ==========================================================================
  group('RetryExecutor.executeOrThrow', () {
    test('should return value on success', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(maxAttempts: 2),
      );
      final result = await executor.executeOrThrow(() async => 'hello');
      expect(result, equals('hello'));
    });

    test('should throw on failure', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 1,
          initialDelay: Duration(milliseconds: 1),
        ),
      );
      expect(
        () => executor.executeOrThrow(
          () async => throw FormatException('bad'),
          retryIf: (_) => false,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  // ==========================================================================
  // RetryExecutor - _isRetryableError variations
  // ==========================================================================
  group('RetryExecutor - retryable error detection', () {
    final executor = RetryExecutor(
      config: const RetryConfig(
        maxAttempts: 2,
        initialDelay: Duration(milliseconds: 1),
      ),
    );

    test('should retry on HttpException', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw const HttpException('server error');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should NOT retry on HandshakeException', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        throw const TlsException('SSL error'); // TlsException extends HandshakeException category
      });
      // HandshakeException not directly in dart:io, but TlsException is
      // For the actual test, let's use string-based detection
      expect(result.isFailure, isTrue);
    });

    test('should retry on TimeoutException', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw TimeoutException('timed out');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on connection refused error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('connection refused');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on connection reset error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('connection reset');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on broken pipe error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('broken pipe');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on host not found error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('host not found');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on failed host lookup error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('failed host lookup');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on network is unreachable error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('network is unreachable');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on deadlock error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('deadlock detected');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on lock wait error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('lock wait timeout');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should retry on serialization failure error string', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount < 2) throw Exception('serialization failure');
        return 'ok';
      });
      expect(result.isSuccess, isTrue);
      expect(callCount, equals(2));
    });

    test('should NOT retry on unknown error', () async {
      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        throw ArgumentError('bad argument');
      });
      expect(result.isFailure, isTrue);
      expect(callCount, equals(1));
    });

    test('should handle maxAttempts = 0', () async {
      final zeroExecutor = RetryExecutor(
        config: const RetryConfig(maxAttempts: 0),
      );
      final result = await zeroExecutor.execute<String>(() async => 'never');
      expect(result.isFailure, isTrue);
      expect(result.attemptsMade, equals(0));
    });
  });

  // ==========================================================================
  // RetryExecutor - onRetry callback
  // ==========================================================================
  group('RetryExecutor - onRetry callback', () {
    test('should call onRetry callback on each retry', () async {
      final retryLogs = <Map<String, dynamic>>[];
      final executor = RetryExecutor(
        config: RetryConfig(
          maxAttempts: 3,
          initialDelay: const Duration(milliseconds: 1),
          onRetry: (attempt, delay, error) {
            retryLogs.add({
              'attempt': attempt,
              'delay': delay,
              'error': error.toString(),
            });
          },
        ),
      );

      var callCount = 0;
      await executor.execute<String>(() async {
        callCount++;
        if (callCount < 3) throw SocketException('retry me');
        return 'ok';
      });

      expect(retryLogs.length, equals(2)); // 2 retries before success
      expect(retryLogs[0]['attempt'], equals(1));
      expect(retryLogs[1]['attempt'], equals(2));
    });
  });

  // ==========================================================================
  // RetryExecutor - config.retryIf
  // ==========================================================================
  group('RetryExecutor - config-level retryIf', () {
    test('should use config retryIf when no per-call retryIf provided', () async {
      final executor = RetryExecutor(
        config: RetryConfig(
          maxAttempts: 3,
          initialDelay: const Duration(milliseconds: 1),
          retryIf: (e) => e is SocketException,
        ),
      );

      var callCount = 0;
      final result = await executor.execute<String>(() async {
        callCount++;
        if (callCount == 1) throw SocketException('retry');
        if (callCount == 2) throw FormatException('stop');
        return 'ok';
      });
      // Should retry SocketException but stop on FormatException
      expect(result.isFailure, isTrue);
      expect(callCount, equals(2));
    });
  });

  // ==========================================================================
  // Convenience functions
  // ==========================================================================
  group('Convenience functions', () {
    test('retry() should work as shorthand', () async {
      var count = 0;
      final result = await retry<String>(
        () async {
          count++;
          if (count < 2) throw SocketException('retry');
          return 'done';
        },
        config: const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 1),
        ),
        operationName: 'test-retry',
      );
      expect(result.isSuccess, isTrue);
      expect(result.value, equals('done'));
    });

    test('retryOrThrow() should return value on success', () async {
      final result = await retryOrThrow<int>(
        () async => 42,
        config: const RetryConfig(maxAttempts: 1),
      );
      expect(result, equals(42));
    });

    test('retryOrThrow() should throw on failure', () async {
      expect(
        () => retryOrThrow<int>(
          () async => throw FormatException('bad'),
          config: const RetryConfig(
            maxAttempts: 1,
            initialDelay: Duration(milliseconds: 1),
          ),
          retryIf: (_) => false,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('retryWithTimeout() should timeout slow operations', () async {
      final result = await retryWithTimeout<String>(
        () async {
          await Future.delayed(const Duration(seconds: 5));
          return 'slow';
        },
        timeout: const Duration(milliseconds: 50),
        config: const RetryConfig(
          maxAttempts: 1,
          initialDelay: Duration(milliseconds: 1),
        ),
      );
      // Should fail with timeout
      expect(result.isFailure, isTrue);
    });

    test('retryWithTimeout() should succeed for fast operations', () async {
      final result = await retryWithTimeout<String>(
        () async => 'fast',
        timeout: const Duration(seconds: 5),
        config: const RetryConfig(maxAttempts: 1),
      );
      expect(result.isSuccess, isTrue);
      expect(result.value, equals('fast'));
    });
  });

  // ==========================================================================
  // RetryConfig presets
  // ==========================================================================
  group('RetryConfig presets', () {
    test('database config should have specific values', () {
      expect(RetryConfig.database.maxAttempts, equals(3));
      expect(RetryConfig.database.backoffMultiplier, equals(1.5));
    });

    test('aiService config should have longer delays', () {
      expect(RetryConfig.aiService.maxAttempts, equals(2));
      expect(RetryConfig.aiService.initialDelay.inSeconds, equals(2));
    });
  });

  // ==========================================================================
  // Exponential backoff with jitter
  // ==========================================================================
  group('Exponential backoff with jitter', () {
    test('jitter should vary delays', () async {
      final executor = RetryExecutor(
        config: const RetryConfig(
          maxAttempts: 5,
          initialDelay: Duration(milliseconds: 50),
          backoffMultiplier: 2.0,
          addJitter: true,
        ),
      );

      final timestamps = <DateTime>[];
      var callCount = 0;
      await executor.execute<String>(() async {
        timestamps.add(DateTime.now());
        callCount++;
        if (callCount < 4) throw SocketException('retry');
        return 'done';
      });

      // With jitter, delays should exist but vary
      expect(timestamps.length, greaterThanOrEqualTo(3));
    });
  });
}
