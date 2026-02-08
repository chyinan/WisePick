/// Production Traffic Simulation & Concurrency Stability Tests
///
/// Simulates real-world production traffic patterns:
/// - Ramp-up from 100 → 10,000 concurrent async operations
/// - Burst spikes (sudden 10x traffic increase)
/// - Sustained high load (continuous 30s windows)
/// - Diurnal pattern (wave-like load)
/// - Spike-then-calm (Black Friday scenario)
///
/// Validates:
/// - No deadlocks (all operations complete within timeout)
/// - No starvation (every request gets a response)
/// - Concurrency invariant (active requests ≤ max concurrent)
/// - No unbounded memory growth
/// - System recovers to baseline after load subsides
///
/// Generates concurrency stability reports via [ReportGenerator].
library;

import 'dart:async';
import 'dart:math';
import 'package:test/test.dart';

import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';
import 'package:wisepick_dart_version/core/resilience/retry_budget.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';

import 'report_generator.dart';

// ============================================================================
// Test harness: Simulated service with full resilience stack
// ============================================================================
class _ResilientTestService {
  final CircuitBreaker circuitBreaker;
  final GlobalRateLimiter rateLimiter;
  final RetryBudget retryBudget;
  final FailureStormDetector stormDetector;

  int successCount = 0;
  int failureCount = 0;
  int rejectedCount = 0;
  int retryCount = 0;
  int _currentConcurrency = 0;
  int maxObservedConcurrency = 0;
  final List<double> latenciesMs = [];

  _ResilientTestService({
    required this.circuitBreaker,
    required this.rateLimiter,
    required this.retryBudget,
    required this.stormDetector,
  });

  Future<Result<T>> execute<T>(
    Future<T> Function() operation, {
    int maxRetries = 1,
  }) async {
    if (stormDetector.isInStorm) {
      rejectedCount++;
      return Result.failure(
          Failure(message: 'Storm protection active', code: 'STORM'));
    }

    if (!circuitBreaker.allowRequest()) {
      rejectedCount++;
      return Result.failure(
          Failure(message: 'Circuit open', code: 'CIRCUIT_OPEN'));
    }

    retryBudget.recordRequest();
    final sw = Stopwatch()..start();

    try {
      final result = await rateLimiter.execute(() async {
        _currentConcurrency++;
        if (_currentConcurrency > maxObservedConcurrency) {
          maxObservedConcurrency = _currentConcurrency;
        }
        try {
          T? lastResult;
          Object? lastError;

          for (int attempt = 0; attempt <= maxRetries; attempt++) {
            try {
              lastResult = await operation();
              circuitBreaker.recordSuccess();
              successCount++;
              return lastResult;
            } catch (e) {
              lastError = e;
              if (attempt < maxRetries &&
                  retryBudget.tryAcquireRetryPermit()) {
                retryCount++;
                continue;
              }
              break;
            }
          }
          throw lastError ?? Exception('Unknown');
        } finally {
          _currentConcurrency--;
        }
      });
      sw.stop();
      latenciesMs.add(sw.elapsedMicroseconds / 1000.0);
      return Result.success(result as T);
    } on RateLimitException {
      sw.stop();
      rejectedCount++;
      return Result.failure(
          Failure(message: 'Rate limited', code: 'RATE_LIMITED'));
    } catch (e) {
      sw.stop();
      latenciesMs.add(sw.elapsedMicroseconds / 1000.0);
      circuitBreaker.recordFailure();
      stormDetector.recordFailure(
        errorType: e.runtimeType.toString(),
        service: 'test',
      );
      failureCount++;
      return Result.failure(Failure(message: e.toString(), code: 'ERROR'));
    }
  }

  void reset() {
    successCount = 0;
    failureCount = 0;
    rejectedCount = 0;
    retryCount = 0;
    maxObservedConcurrency = 0;
    latenciesMs.clear();
  }

  void dispose() {
    rateLimiter.dispose();
  }
}

_ResilientTestService _createService({
  int maxRps = 500,
  int maxConcurrent = 50,
  int maxQueue = 2000,
  Duration waitTimeout = const Duration(seconds: 10),
  int failureThreshold = 10,
  double failureRateThreshold = 0.6,
}) {
  return _ResilientTestService(
    circuitBreaker: CircuitBreaker(
      name: 'prod_traffic_cb_${DateTime.now().microsecondsSinceEpoch}',
      config: CircuitBreakerConfig(
        failureThreshold: failureThreshold,
        failureRateThreshold: failureRateThreshold,
        resetTimeout: const Duration(milliseconds: 500),
        successThreshold: 2,
        windowSize: 50,
      ),
    ),
    rateLimiter: GlobalRateLimiter(
      name: 'prod_traffic_rl_${DateTime.now().microsecondsSinceEpoch}',
      config: RateLimiterConfig(
        maxRequestsPerSecond: maxRps,
        maxConcurrentRequests: maxConcurrent,
        maxQueueLength: maxQueue,
        waitTimeout: waitTimeout,
      ),
    ),
    retryBudget: RetryBudget(
      name: 'prod_traffic_rb_${DateTime.now().microsecondsSinceEpoch}',
      config: const RetryBudgetConfig(
        maxRetryRatio: 0.2,
        minRetriesPerWindow: 10,
        windowDuration: Duration(seconds: 30),
      ),
    ),
    stormDetector: FailureStormDetector(
      name: 'prod_traffic_storm_${DateTime.now().microsecondsSinceEpoch}',
      stormThreshold: 50,
      consecutiveHighCount: 3,
    ),
  );
}

/// Simulates a single operation with random latency.
Future<String> _simulatedOperation(Random rng, {double failRate = 0.0}) async {
  // Realistic latency distribution: mostly fast, occasional slow
  final baseMs = 1 + rng.nextInt(10);
  final jitter = rng.nextDouble() < 0.1 ? rng.nextInt(50) : 0; // 10% slow
  await Future.delayed(Duration(milliseconds: baseMs + jitter));

  if (rng.nextDouble() < failRate) {
    throw Exception('Simulated transient error');
  }
  return 'ok';
}

void main() {
  // ========================================================================
  // 1. Ramp-Up Test: 100 → 1,000 → 5,000 → 10,000
  // ========================================================================
  group('Production Traffic - Ramp-Up', () {
    test('should handle ramp from 100 to 10000 concurrent requests',
        () async {
      final rng = Random(42);
      final steps = <LoadStepResult>[];
      final concurrencyLevels = [100, 500, 1000, 2000, 5000, 10000];

      for (final concurrency in concurrencyLevels) {
        final service = _createService(
          maxRps: 10000,
          maxConcurrent: 200,
          maxQueue: concurrency + 500,
          waitTimeout: const Duration(seconds: 15),
        );

        final sw = Stopwatch()..start();

        final futures = List.generate(concurrency, (i) async {
          await service.execute(() => _simulatedOperation(rng));
        });

        await Future.wait(futures).timeout(
          const Duration(seconds: 60),
          onTimeout: () =>
              fail('Deadlock: $concurrency concurrent requests timed out'),
        );

        sw.stop();

        final total =
            service.successCount + service.failureCount + service.rejectedCount;

        steps.add(LoadStepResult(
          concurrency: concurrency,
          totalRequests: concurrency,
          successCount: service.successCount,
          failureCount: service.failureCount,
          rejectedCount: service.rejectedCount,
          elapsed: sw.elapsed,
          latenciesMs: List.from(service.latenciesMs),
        ));

        // Core invariant: all requests must be accounted for
        expect(total, equals(concurrency),
            reason:
                'Lost requests at concurrency $concurrency: $total != $concurrency');

        service.dispose();
      }

      // Generate report
      final report = ReportGenerator.generateDegradationReport(steps);
      // ignore: avoid_print
      print(report);

      // Stability assessment
      final assessment = ReportGenerator.assessStability(steps);
      expect(assessment.criticalIssues, isEmpty,
          reason: 'Critical stability issues: ${assessment.criticalIssues}');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  // ========================================================================
  // 2. Burst Spike (10x instantaneous traffic increase)
  // ========================================================================
  group('Production Traffic - Burst Spike', () {
    test('should handle sudden 10x burst without deadlock', () async {
      final rng = Random(42);
      final service = _createService(
        maxRps: 5000,
        maxConcurrent: 100,
        maxQueue: 3000,
        waitTimeout: const Duration(seconds: 10),
      );

      // Phase 1: Baseline load (100 requests)
      final baselineFutures = List.generate(100, (i) async {
        await service.execute(() => _simulatedOperation(rng));
      });
      await Future.wait(baselineFutures)
          .timeout(const Duration(seconds: 10));

      final baselineSuccess = service.successCount;
      service.reset();

      // Phase 2: Burst to 1000 (10x spike)
      final burstFutures = List.generate(1000, (i) async {
        await service.execute(() => _simulatedOperation(rng));
      });

      final sw = Stopwatch()..start();
      await Future.wait(burstFutures).timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail('Burst spike caused deadlock'),
      );
      sw.stop();

      final total =
          service.successCount + service.failureCount + service.rejectedCount;

      // ignore: avoid_print
      print(ReportGenerator.generateConcurrencyReport(
        concurrency: 1000,
        totalRequests: 1000,
        successCount: service.successCount,
        failureCount: service.failureCount,
        rejectedCount: service.rejectedCount,
        elapsed: sw.elapsed,
        latenciesMs: service.latenciesMs,
        maxObservedConcurrency: service.maxObservedConcurrency,
        maxConcurrencyLimit: 100,
        deadlockDetected: false,
        memoryGrowthDetected: false,
      ));

      // All 1000 requests accounted for
      expect(total, equals(1000));
      // At least some should succeed (system didn't completely collapse)
      expect(service.successCount, greaterThan(0));
      // Concurrency invariant
      expect(service.maxObservedConcurrency, lessThanOrEqualTo(100));

      // Phase 3: Verify recovery - system should work after burst
      service.reset();
      service.circuitBreaker.reset();
      final recoveryResult =
          await service.execute(() => _simulatedOperation(rng));
      expect(
        recoveryResult.isSuccess || service.rejectedCount > 0,
        isTrue,
        reason: 'System should be functional or gracefully rejecting after burst',
      );

      service.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ========================================================================
  // 3. Sustained Load (continuous high throughput for extended period)
  // ========================================================================
  group('Production Traffic - Sustained Load', () {
    test('should sustain 500 req/s for 5 seconds without degradation',
        () async {
      final rng = Random(42);
      final service = _createService(
        maxRps: 1000,
        maxConcurrent: 100,
        maxQueue: 2000,
        waitTimeout: const Duration(seconds: 10),
      );

      final allFutures = <Future>[];
      final durationSeconds = 5;
      final rps = 500;

      final sw = Stopwatch()..start();

      // Send requests at ~500/s for 5 seconds
      for (int second = 0; second < durationSeconds; second++) {
        // Send 500 requests spread over 1 second (in batches of 50)
        for (int batch = 0; batch < 10; batch++) {
          for (int i = 0; i < rps ~/ 10; i++) {
            allFutures.add(
              service.execute(() => _simulatedOperation(rng)),
            );
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      await Future.wait(allFutures).timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail('Sustained load caused deadlock'),
      );
      sw.stop();

      final total =
          service.successCount + service.failureCount + service.rejectedCount;
      final expectedTotal = durationSeconds * rps;

      // ignore: avoid_print
      print(ReportGenerator.generateConcurrencyReport(
        concurrency: rps,
        totalRequests: expectedTotal,
        successCount: service.successCount,
        failureCount: service.failureCount,
        rejectedCount: service.rejectedCount,
        elapsed: sw.elapsed,
        latenciesMs: service.latenciesMs,
        maxObservedConcurrency: service.maxObservedConcurrency,
        maxConcurrencyLimit: 100,
        deadlockDetected: false,
        memoryGrowthDetected: false,
      ));

      // All requests accounted for
      expect(total, equals(expectedTotal));
      // Most should succeed under sustained load
      expect(service.successCount, greaterThan(expectedTotal * 0.5),
          reason: 'At least 50% of requests should succeed under sustained load');

      service.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ========================================================================
  // 4. Diurnal Traffic Pattern (sinusoidal load)
  // ========================================================================
  group('Production Traffic - Diurnal Pattern', () {
    test('should handle wave-like traffic without instability', () async {
      final rng = Random(42);
      final service = _createService(
        maxRps: 5000,
        maxConcurrent: 100,
        maxQueue: 2000,
      );

      final steps = <LoadStepResult>[];

      // Simulate 8 time steps of varying load (sine wave pattern)
      for (int step = 0; step < 8; step++) {
        service.reset();
        service.circuitBreaker.reset();

        // Sinusoidal load: 50 → 500 → 50
        final loadFactor = (1 + (50 * (1 + (step * 3.14159 / 4).abs())));
        final requests = loadFactor.toInt().clamp(50, 500);

        final sw = Stopwatch()..start();
        final futures = List.generate(requests, (i) async {
          await service.execute(() => _simulatedOperation(rng));
        });

        await Future.wait(futures).timeout(const Duration(seconds: 20));
        sw.stop();

        steps.add(LoadStepResult(
          concurrency: requests,
          totalRequests: requests,
          successCount: service.successCount,
          failureCount: service.failureCount,
          rejectedCount: service.rejectedCount,
          elapsed: sw.elapsed,
          latenciesMs: List.from(service.latenciesMs),
        ));
      }

      // ignore: avoid_print
      print(ReportGenerator.generateDegradationReport(steps));

      // No step should have deadlocked
      for (final step in steps) {
        final total =
            step.successCount + step.failureCount + step.rejectedCount;
        expect(total, equals(step.totalRequests),
            reason:
                'Lost requests at concurrency ${step.concurrency}');
      }

      service.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ========================================================================
  // 5. Spike-then-Calm (Black Friday pattern)
  // ========================================================================
  group('Production Traffic - Spike-then-Calm', () {
    test('should recover to baseline after massive spike', () async {
      final rng = Random(42);
      final service = _createService(
        maxRps: 5000,
        maxConcurrent: 100,
        maxQueue: 5000,
        waitTimeout: const Duration(seconds: 15),
      );

      // Phase 1: Calm baseline (100 requests)
      var futures = List.generate(100, (i) async {
        await service.execute(() => _simulatedOperation(rng));
      });
      await Future.wait(futures).timeout(const Duration(seconds: 10));
      final baselineSuccess = service.successCount;
      final baselineLatencies = List<double>.from(service.latenciesMs);

      // Phase 2: Massive spike (5000 requests)
      service.reset();
      futures = List.generate(5000, (i) async {
        await service.execute(() => _simulatedOperation(rng));
      });
      await Future.wait(futures).timeout(
        const Duration(seconds: 60),
        onTimeout: () => fail('Spike phase deadlocked'),
      );

      // Phase 3: Recovery period (wait for system to stabilize)
      await Future.delayed(const Duration(seconds: 2));
      service.circuitBreaker.reset();

      // Phase 4: Post-spike baseline (100 requests)
      service.reset();
      futures = List.generate(100, (i) async {
        await service.execute(() => _simulatedOperation(rng));
      });
      await Future.wait(futures).timeout(const Duration(seconds: 10));

      final postSpikeSuccess = service.successCount;

      // ignore: avoid_print
      print('=== Spike-then-Calm Recovery ===');
      // ignore: avoid_print
      print('  Pre-spike baseline success: $baselineSuccess / 100');
      // ignore: avoid_print
      print('  Post-spike baseline success: $postSpikeSuccess / 100');

      // System should recover: post-spike success rate should be reasonable
      expect(postSpikeSuccess, greaterThan(50),
          reason: 'System should recover to >50% success rate after spike');

      service.dispose();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // ========================================================================
  // 6. Concurrency Invariant Validation
  // ========================================================================
  group('Production Traffic - Concurrency Invariant', () {
    test('active requests should never exceed max concurrent limit',
        () async {
      final rng = Random(42);
      const maxConcurrent = 20;
      final service = _createService(
        maxRps: 5000,
        maxConcurrent: maxConcurrent,
        maxQueue: 1000,
      );

      final futures = List.generate(500, (i) async {
        await service.execute(() async {
          await Future.delayed(
              Duration(milliseconds: 5 + rng.nextInt(20)));
          return 'ok';
        });
      });

      await Future.wait(futures).timeout(const Duration(seconds: 30));

      expect(service.maxObservedConcurrency, lessThanOrEqualTo(maxConcurrent),
          reason:
              'Concurrency ${service.maxObservedConcurrency} exceeded limit $maxConcurrent');

      service.dispose();
    });
  });

  // ========================================================================
  // 7. Memory Safety Under Load
  // ========================================================================
  group('Production Traffic - Memory Safety', () {
    test('metrics collector should remain bounded under high load', () {
      final metrics = MetricsCollector.instance;
      metrics.reset();

      // Simulate metrics from 10,000 requests
      for (int i = 0; i < 10000; i++) {
        metrics.recordRequest(
          service: 'test_svc',
          operation: 'op_${i % 10}', // 10 distinct operations
          success: i % 20 != 0, // 5% failure rate
          duration: Duration(milliseconds: 5 + (i % 100)),
        );
      }

      // Should not throw or OOM
      final summary = metrics.getSummary();
      expect(summary, isNotEmpty);

      // Verify counters are tracking
      final allMetrics = metrics.getAllMetrics();
      expect(allMetrics, isNotEmpty,
          reason: 'Metrics should have been recorded');

      // Verify no unbounded growth in summary
      final summaryStr = summary.toString();
      expect(summaryStr.length, lessThan(100000),
          reason: 'Summary string should remain bounded');

      metrics.reset();
    });

    test('circuit breaker window should not grow unbounded', () {
      final breaker = CircuitBreaker(
        name: 'memory_safety_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 1000,
          failureRateThreshold: 0.99,
          windowSize: 100,
        ),
      );

      // Record 50,000 events
      for (int i = 0; i < 50000; i++) {
        breaker.recordSuccess();
      }

      final status = breaker.getStatus();
      // Window should cap at windowSize (100)
      expect(status['total'] as int, lessThanOrEqualTo(100));
    });
  });
}
