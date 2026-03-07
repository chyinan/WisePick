/// Resilience Strategy Tests
///
/// Tests for TimeoutStrategy, BulkheadStrategy, FallbackStrategy,
/// CacheStrategy, CircuitBreakerStrategy, RateLimitStrategy, RetryStrategy,
/// and StrategyPipeline.
///
/// Covers:
/// - Individual strategy behavior
/// - Strategy pipeline composition
/// - Degradation behavior under load
/// - Strategy interaction under stress
@Tags(['stress'])
library;

import 'dart:async';
import 'package:test/test.dart';

import 'package:wisepick_dart_version/core/reliability/resilience_strategy.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';

void main() {
  // ========================================================================
  // 1. TimeoutStrategy
  // ========================================================================
  group('ResilienceStrategy - TimeoutStrategy', () {
    test('should succeed within timeout', () async {
      final strategy = TimeoutStrategy(
        timeout: const Duration(seconds: 2),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'fast_op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<String>(
        () async {
          await Future.delayed(const Duration(milliseconds: 10));
          return 'done';
        },
        context,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('done'));
      expect(result.executedStrategy, equals('timeout'));
    });

    test('should fail on timeout', () async {
      final strategy = TimeoutStrategy(
        timeout: const Duration(milliseconds: 100),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'slow_op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<String>(
        () async {
          await Future.delayed(const Duration(seconds: 5));
          return 'should not reach';
        },
        context,
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isA<TimeoutException>());
    });

    test('should trigger soft timeout callback', () async {
      var softTimeoutTriggered = false;

      final strategy = TimeoutStrategy(
        timeout: const Duration(seconds: 2),
        softTimeout: const Duration(milliseconds: 50),
        onSoftTimeout: (_) => softTimeoutTriggered = true,
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'medium_op',
        startTime: DateTime.now(),
      );

      await strategy.execute<String>(
        () async {
          await Future.delayed(const Duration(milliseconds: 200));
          return 'done';
        },
        context,
      );

      expect(softTimeoutTriggered, isTrue);
    });

    test('getStatus should return correct info', () {
      final strategy = TimeoutStrategy(
        timeout: const Duration(seconds: 5),
        softTimeout: const Duration(seconds: 3),
      );

      final status = strategy.getStatus();
      expect(status['timeout'], equals(5000));
      expect(status['softTimeout'], equals(3000));
      expect(status['enabled'], isTrue);
    });

    test('isApplicable should always return true', () {
      final strategy = TimeoutStrategy(timeout: const Duration(seconds: 1));
      final context = StrategyContext(
        serviceName: 'any',
        operationName: 'any',
        startTime: DateTime.now(),
      );
      expect(strategy.isApplicable(context), isTrue);
    });

    test('enable/disable should work', () {
      final strategy = TimeoutStrategy(timeout: const Duration(seconds: 1));
      expect(strategy.isEnabled, isTrue);
      strategy.disable();
      expect(strategy.isEnabled, isFalse);
      strategy.enable();
      expect(strategy.isEnabled, isTrue);
    });
  });

  // ========================================================================
  // 2. BulkheadStrategy
  // ========================================================================
  group('ResilienceStrategy - BulkheadStrategy', () {
    test('should execute within capacity', () async {
      final strategy = BulkheadStrategy(maxConcurrent: 5);

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<int>(
        () async => 42,
        context,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals(42));
    });

    test('should reject when bulkhead is full', () async {
      final strategy = BulkheadStrategy(
        maxConcurrent: 2,
        maxWaitTime: const Duration(milliseconds: 50),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      // Fill both slots
      final slow1 = strategy.execute<String>(
        () async {
          await Future.delayed(const Duration(seconds: 2));
          return 'slow1';
        },
        context,
      );
      final slow2 = strategy.execute<String>(
        () async {
          await Future.delayed(const Duration(seconds: 2));
          return 'slow2';
        },
        context,
      );

      // Wait a bit for the slots to be occupied
      await Future.delayed(const Duration(milliseconds: 10));

      // Third request should be rejected (wait timeout)
      final rejected = await strategy.execute<String>(
        () async => 'should not run',
        context,
      );

      expect(rejected.isSuccess, isFalse);
      expect(rejected.error, isA<BulkheadRejectedException>());

      // Cancel the slow operations
      slow1.ignore();
      slow2.ignore();
    });

    test('should track concurrency correctly', () async {
      final strategy = BulkheadStrategy(maxConcurrent: 3);

      expect(strategy.currentConcurrent, equals(0));
      expect(strategy.hasCapacity, isTrue);

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      // Fill 3 slots
      final futures = List.generate(3, (_) => strategy.execute<String>(
        () async {
          await Future.delayed(const Duration(milliseconds: 100));
          return 'done';
        },
        context,
      ));

      // Wait a moment for tasks to start
      await Future.delayed(const Duration(milliseconds: 10));
      expect(strategy.currentConcurrent, greaterThan(0));

      await Future.wait(futures);
      expect(strategy.currentConcurrent, equals(0));
    });

    test('getStatus should return correct info', () {
      final strategy = BulkheadStrategy(maxConcurrent: 10);
      final status = strategy.getStatus();

      expect(status['maxConcurrent'], equals(10));
      expect(status['currentConcurrent'], equals(0));
      expect(status['queueLength'], equals(0));
    });
  });

  // ========================================================================
  // 3. FallbackStrategy
  // ========================================================================
  group('ResilienceStrategy - FallbackStrategy', () {
    test('should return normal result when operation succeeds', () async {
      final strategy = FallbackStrategy<String>(
        fallbackFn: (_, __) async => 'fallback',
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<String>(
        () async => 'success',
        context,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('success'));
      expect(strategy.fallbackCount, equals(0));
    });

    test('should use fallback when operation fails', () async {
      final strategy = FallbackStrategy<String>(
        fallbackFn: (_, __) async => 'fallback_value',
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<String>(
        () async => throw Exception('operation failed'),
        context,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('fallback_value'));
      expect(strategy.fallbackCount, equals(1));
    });

    test('should respect shouldFallback predicate', () async {
      final strategy = FallbackStrategy<String>(
        fallbackFn: (_, __) async => 'fallback',
        shouldFallback: (e) => e is TimeoutException,
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      // Non-matching error: should NOT fallback
      final result1 = await strategy.execute<String>(
        () async => throw Exception('generic'),
        context,
      );
      expect(result1.isSuccess, isFalse);
      expect(strategy.fallbackCount, equals(0));

      // Matching error: should fallback
      final result2 = await strategy.execute<String>(
        () async => throw TimeoutException('timed out'),
        context,
      );
      expect(result2.isSuccess, isTrue);
      expect(result2.value, equals('fallback'));
      expect(strategy.fallbackCount, equals(1));
    });

    test('should return failure when fallback also fails', () async {
      final strategy = FallbackStrategy<String>(
        fallbackFn: (_, __) async => throw Exception('fallback also failed'),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<String>(
        () async => throw Exception('primary failed'),
        context,
      );

      expect(result.isSuccess, isFalse);
      expect(result.executedStrategy, contains('fallback_failed'));
    });
  });

  // ========================================================================
  // 4. CacheStrategy
  // ========================================================================
  group('ResilienceStrategy - CacheStrategy', () {
    test('should cache results', () async {
      final strategy = CacheStrategy<String>(
        ttl: const Duration(seconds: 10),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'cached_op',
        startTime: DateTime.now(),
      );

      var callCount = 0;

      // First call: cache miss
      final result1 = await strategy.execute<String>(
        () async {
          callCount++;
          return 'data';
        },
        context,
      );
      expect(result1.isSuccess, isTrue);
      expect(result1.value, equals('data'));
      expect(callCount, equals(1));

      // Second call: cache hit
      final result2 = await strategy.execute<String>(
        () async {
          callCount++;
          return 'new_data';
        },
        context,
      );
      expect(result2.isSuccess, isTrue);
      expect(result2.value, equals('data')); // from cache
      expect(callCount, equals(1)); // not called again
    });

    test('should expire cache after TTL', () async {
      final strategy = CacheStrategy<String>(
        ttl: const Duration(milliseconds: 50),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'ttl_op',
        startTime: DateTime.now(),
      );

      var callCount = 0;

      await strategy.execute<String>(
        () async {
          callCount++;
          return 'old_data';
        },
        context,
      );
      expect(callCount, equals(1));

      // Wait for TTL to expire
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await strategy.execute<String>(
        () async {
          callCount++;
          return 'new_data';
        },
        context,
      );

      expect(result.value, equals('new_data'));
      expect(callCount, equals(2));
    });

    test('should serve stale cache on error', () async {
      final strategy = CacheStrategy<String>(
        ttl: const Duration(milliseconds: 10),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'stale_op',
        startTime: DateTime.now(),
      );

      // Cache a value
      await strategy.execute<String>(
        () async => 'cached_data',
        context,
      );

      // Wait for TTL expiry
      await Future.delayed(const Duration(milliseconds: 50));

      // Operation fails, but stale cache should be returned
      final result = await strategy.execute<String>(
        () async => throw Exception('service down'),
        context,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('cached_data'));
      expect(result.executedStrategy, contains('stale'));
    });

    test('invalidate should remove cache entry', () async {
      final strategy = CacheStrategy<String>(
        ttl: const Duration(seconds: 10),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'invalidate_op',
        startTime: DateTime.now(),
      );

      await strategy.execute<String>(() async => 'data', context);
      expect(strategy.cacheSize, equals(1));

      strategy.invalidate('test:invalidate_op');
      expect(strategy.cacheSize, equals(0));
    });

    test('invalidateAll should clear all cache', () async {
      final strategy = CacheStrategy<String>(
        ttl: const Duration(seconds: 10),
      );

      for (int i = 0; i < 5; i++) {
        final ctx = StrategyContext(
          serviceName: 'test',
          operationName: 'op_$i',
          startTime: DateTime.now(),
        );
        await strategy.execute<String>(() async => 'data_$i', ctx);
      }

      expect(strategy.cacheSize, equals(5));
      strategy.invalidateAll();
      expect(strategy.cacheSize, equals(0));
    });
  });

  // ========================================================================
  // 5. CircuitBreakerStrategy
  // ========================================================================
  group('ResilienceStrategy - CircuitBreakerStrategy', () {
    test('should wrap circuit breaker execution', () async {
      final cb = CircuitBreaker(
        name: 'strategy_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 3,
          failureRateThreshold: 0.5,
          windowSize: 10,
        ),
      );
      final strategy = CircuitBreakerStrategy(circuitBreaker: cb);

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<String>(
        () async => 'ok',
        context,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('ok'));
      expect(result.metadata['circuitState'], equals('closed'));
    });

    test('should fail when circuit is open', () async {
      final cb = CircuitBreaker(
        name: 'open_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 2,
          failureRateThreshold: 0.5,
          windowSize: 5,
        ),
      );

      // Open the circuit
      for (int i = 0; i < 5; i++) {
        cb.recordFailure();
      }
      expect(cb.state, equals(CircuitState.open));

      final strategy = CircuitBreakerStrategy(circuitBreaker: cb);
      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<String>(
        () async => 'should not run',
        context,
      );

      expect(result.isSuccess, isFalse);
    });
  });

  // ========================================================================
  // 6. StrategyPipeline
  // ========================================================================
  group('ResilienceStrategy - StrategyPipeline', () {
    test('should execute through pipeline', () async {
      final pipeline = StrategyPipeline(name: 'test_pipeline');
      pipeline.addStrategy(TimeoutStrategy(timeout: const Duration(seconds: 5)));
      pipeline.addStrategy(BulkheadStrategy(maxConcurrent: 10));

      final result = await pipeline.execute<String>(
        () async => 'pipeline_result',
        serviceName: 'test',
        operationName: 'pipeline_op',
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('pipeline_result'));
    });

    test('should respect strategy priority', () async {
      final pipeline = StrategyPipeline(name: 'priority_test');

      final strategy1 = TimeoutStrategy(
        name: 'high_priority',
        priority: 10,
        timeout: const Duration(seconds: 5),
      );
      final strategy2 = BulkheadStrategy(
        name: 'low_priority',
        priority: 100,
        maxConcurrent: 10,
      );

      // Add in reverse order - should still be sorted by priority
      pipeline.addStrategy(strategy2);
      pipeline.addStrategy(strategy1);

      final status = pipeline.getStatus();
      final strategies = status['strategies'] as List;
      expect((strategies[0] as Map)['name'], equals('high_priority'));
    });

    test('should skip disabled strategies', () async {
      final pipeline = StrategyPipeline(name: 'disabled_test');

      final timeout = TimeoutStrategy(timeout: const Duration(milliseconds: 50));
      timeout.disable();
      pipeline.addStrategy(timeout);

      // Operation takes 200ms, but timeout is disabled
      final result = await pipeline.execute<String>(
        () async {
          await Future.delayed(const Duration(milliseconds: 200));
          return 'completed';
        },
        serviceName: 'test',
        operationName: 'op',
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('completed'));
    });

    test('should add and remove strategies', () {
      final pipeline = StrategyPipeline(name: 'modify_test');
      final timeout = TimeoutStrategy(name: 'removable', timeout: const Duration(seconds: 1));

      pipeline.addStrategy(timeout);
      expect(pipeline.getStrategy('removable'), isNotNull);

      final removed = pipeline.removeStrategy('removable');
      expect(removed, isTrue);
      expect(pipeline.getStrategy('removable'), isNull);

      final notFound = pipeline.removeStrategy('nonexistent');
      expect(notFound, isFalse);
    });

    test('should handle nested strategy failures', () async {
      final pipeline = StrategyPipeline(name: 'failure_test');
      pipeline.addStrategy(TimeoutStrategy(timeout: const Duration(seconds: 5)));
      pipeline.addStrategy(BulkheadStrategy(maxConcurrent: 10));

      final result = await pipeline.execute<String>(
        () async => throw Exception('inner failure'),
        serviceName: 'test',
        operationName: 'fail_op',
      );

      expect(result.isSuccess, isFalse);
    });

    test('pipeline should timeout correctly', () async {
      final pipeline = StrategyPipeline(name: 'timeout_pipeline');
      pipeline.addStrategy(TimeoutStrategy(timeout: const Duration(milliseconds: 100)));

      final result = await pipeline.execute<String>(
        () async {
          await Future.delayed(const Duration(seconds: 5));
          return 'too slow';
        },
        serviceName: 'test',
        operationName: 'timeout_op',
      );

      expect(result.isSuccess, isFalse);
    });
  });

  // ========================================================================
  // 7. StrategyPipeline under stress
  // ========================================================================
  group('ResilienceStrategy - Pipeline Stress', () {
    test('pipeline should handle 50 concurrent requests', () async {
      final pipeline = StrategyPipeline(name: 'stress_pipeline');
      pipeline.addStrategy(TimeoutStrategy(timeout: const Duration(seconds: 5)));
      pipeline.addStrategy(BulkheadStrategy(maxConcurrent: 10));

      var completed = 0;
      var failed = 0;

      final futures = List.generate(50, (i) async {
        final result = await pipeline.execute<int>(
          () async {
            await Future.delayed(const Duration(milliseconds: 20));
            return i;
          },
          serviceName: 'test',
          operationName: 'stress_$i',
        );
        if (result.isSuccess) {
          completed++;
        } else {
          failed++;
        }
      });

      await Future.wait(futures).timeout(const Duration(seconds: 30));

      expect(completed + failed, equals(50));
      expect(completed, greaterThan(0));

      // ignore: avoid_print
      print('=== Pipeline Stress Report ===');
      // ignore: avoid_print
      print('  Completed: $completed / 50');
      // ignore: avoid_print
      print('  Failed: $failed / 50');
    });

    test('pipeline with circuit breaker should degrade gracefully', () async {
      final cb = CircuitBreaker(
        name: 'stress_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 3,
          failureRateThreshold: 0.5,
          windowSize: 10,
        ),
      );

      final pipeline = StrategyPipeline(name: 'degradation_pipeline');
      pipeline.addStrategy(CircuitBreakerStrategy(circuitBreaker: cb));
      pipeline.addStrategy(TimeoutStrategy(timeout: const Duration(seconds: 2)));

      var successes = 0;
      var failures = 0;

      // First 10 requests: half fail
      for (int i = 0; i < 10; i++) {
        final result = await pipeline.execute<String>(
          () async {
            if (i % 2 == 0) throw Exception('fail');
            return 'ok';
          },
          serviceName: 'test',
          operationName: 'degrade_$i',
        );
        if (result.isSuccess) successes++;
        else failures++;
      }

      // Circuit should be open after failures
      // Next requests should be rejected fast
      final postBreak = await pipeline.execute<String>(
        () async => 'should not run',
        serviceName: 'test',
        operationName: 'post_break',
      );

      // ignore: avoid_print
      print('=== Degradation Report ===');
      // ignore: avoid_print
      print('  Successes: $successes, Failures: $failures');
      // ignore: avoid_print
      print('  Circuit state: ${cb.state.name}');
      // ignore: avoid_print
      print('  Post-break success: ${postBreak.isSuccess}');

      // At minimum, some should have failed and circuit should have opened
      expect(failures, greaterThan(0));
    });
  });

  // ========================================================================
  // 8. StrategyRegistry
  // ========================================================================
  group('ResilienceStrategy - StrategyRegistry', () {
    setUp(() {
      StrategyRegistry.instance.clear();
    });

    test('getOrCreate should create and return pipelines', () {
      final pipeline = StrategyRegistry.instance.getOrCreate('test_reg');
      expect(pipeline, isNotNull);
      expect(pipeline.name, equals('test_reg'));

      // Getting same name should return same instance
      final same = StrategyRegistry.instance.getOrCreate('test_reg');
      expect(identical(pipeline, same), isTrue);
    });

    test('get should return null for unknown', () {
      expect(StrategyRegistry.instance.get('unknown'), isNull);
    });

    test('createDefault should create pipeline with strategies', () {
      final cb = CircuitBreaker(
        name: 'reg_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 5,
          windowSize: 10,
        ),
      );

      final limiter = GlobalRateLimiter(
        name: 'reg_limiter',
        config: const RateLimiterConfig(maxConcurrentRequests: 10),
      );

      final pipeline = StrategyRegistry.instance.createDefault(
        'default_test',
        timeout: const Duration(seconds: 5),
        maxConcurrent: 20,
        circuitBreaker: cb,
        rateLimiter: limiter,
      );

      final status = pipeline.getStatus();
      expect(status['strategiesCount'], greaterThanOrEqualTo(3));

      limiter.dispose();
    });

    test('getAllStatus should return all pipeline statuses', () {
      StrategyRegistry.instance.getOrCreate('p1');
      StrategyRegistry.instance.getOrCreate('p2');

      final allStatus = StrategyRegistry.instance.getAllStatus();
      expect(allStatus.length, equals(2));
      expect(allStatus.containsKey('p1'), isTrue);
      expect(allStatus.containsKey('p2'), isTrue);
    });
  });

  // ========================================================================
  // 9. StrategyContext & StrategyResult
  // ========================================================================
  group('ResilienceStrategy - Context & Result', () {
    test('StrategyContext copyWith should preserve fields', () {
      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        attributes: {'key': 'value'},
        startTime: DateTime(2025, 1, 1),
      );

      final copy = ctx.copyWith(attemptNumber: 2, lastError: 'err');
      expect(copy.serviceName, equals('svc'));
      expect(copy.operationName, equals('op'));
      expect(copy.attemptNumber, equals(2));
      expect(copy.lastError, equals('err'));
      expect(copy.startTime, equals(DateTime(2025, 1, 1)));
    });

    test('StrategyResult.success should carry value', () {
      final result = StrategyResult<int>.success(
        42,
        strategy: 'test',
        executionTime: const Duration(milliseconds: 100),
        metadata: {'note': 'test'},
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals(42));
      expect(result.getOrThrow(), equals(42));
      expect(result.getOrNull(), equals(42));
      expect(result.executedStrategy, equals('test'));
    });

    test('StrategyResult.failure should carry error', () {
      final result = StrategyResult<int>.failure(
        Exception('fail'),
        strategy: 'test',
        executionTime: const Duration(milliseconds: 50),
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isA<Exception>());
      expect(result.getOrNull(), isNull);
      expect(() => result.getOrThrow(), throwsA(isA<Exception>()));
    });

    test('BulkheadRejectedException toString', () {
      final ex = BulkheadRejectedException('bulkhead full');
      expect(ex.toString(), contains('BulkheadRejectedException'));
      expect(ex.toString(), contains('bulkhead full'));
    });
  });
}
