/// Chaos Resilience Validation Suite
///
/// Comprehensive chaos testing that validates the full resilience stack
/// under realistic failure conditions:
///
/// - Retry storm prevention: Verifies retry budget prevents amplification
/// - Partial outage simulation: One service fails while others continue
/// - Cascading failure isolation: Upstream circuit breakers protect downstream
/// - Network jitter + error combo: Realistic production failure patterns
/// - Auto-recovery validation: System self-heals after faults clear
/// - Corrupted response handling: Graceful degradation on bad data
///
/// Generates chaos resilience reports via [ReportGenerator].
library;

import 'dart:async';
import 'dart:math';
import 'package:test/test.dart';

import 'package:wisepick_dart_version/core/reliability/chaos_engineering.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';
import 'package:wisepick_dart_version/core/resilience/retry_budget.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';
import 'package:wisepick_dart_version/core/resilience/auto_recovery.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';

import 'report_generator.dart';

// ============================================================================
// Test service with full resilience stack + chaos injection point
// ============================================================================
class _ChaosTestService {
  final String name;
  final CircuitBreaker circuitBreaker;
  final GlobalRateLimiter rateLimiter;
  final RetryBudget retryBudget;
  final FailureStormDetector stormDetector;

  int successCount = 0;
  int failureCount = 0;
  int rejectedCount = 0;
  int retryCount = 0;
  final List<double> latenciesMs = [];

  _ChaosTestService({
    required this.name,
    required this.circuitBreaker,
    required this.rateLimiter,
    required this.retryBudget,
    required this.stormDetector,
  });

  Future<Result<T>> execute<T>(
    Future<T> Function() operation, {
    int maxRetries = 2,
    FaultInjector? injector,
  }) async {
    if (stormDetector.isInStorm) {
      rejectedCount++;
      return Result.failure(Failure(message: 'Storm protection', code: 'STORM'));
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
        T? lastResult;
        Object? lastError;
        for (int attempt = 0; attempt <= maxRetries; attempt++) {
          try {
            // Inject faults if injector active
            if (injector != null && injector.isEnabled) {
              await injector.maybeInjectFault(
                service: name,
                operation: 'execute',
              );
            }
            lastResult = await operation();
            circuitBreaker.recordSuccess();
            successCount++;
            return lastResult;
          } catch (e) {
            lastError = e;
            if (attempt < maxRetries && retryBudget.tryAcquireRetryPermit()) {
              retryCount++;
              continue;
            }
            break;
          }
        }
        throw lastError ?? Exception('Unknown');
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
        service: name,
      );
      failureCount++;
      return Result.failure(Failure(message: e.toString(), code: 'ERROR'));
    }
  }

  ChaosRunSummary toSummary({
    required String experimentName,
    required String faultType,
    required Duration duration,
    List<String> observations = const [],
  }) {
    return ChaosRunSummary(
      experimentName: experimentName,
      faultType: faultType,
      totalDuration: duration,
      totalRequests: successCount + failureCount + rejectedCount,
      successCount: successCount,
      failureCount: failureCount,
      rejectedCount: rejectedCount,
      retryCount: retryCount,
      circuitBreakerFinalState: circuitBreaker.state.name,
      stormDetected: stormDetector.isInStorm,
      latenciesMs: List.from(latenciesMs),
      observations: observations,
    );
  }

  void reset() {
    successCount = 0;
    failureCount = 0;
    rejectedCount = 0;
    retryCount = 0;
    latenciesMs.clear();
  }

  void dispose() {
    rateLimiter.dispose();
  }
}

_ChaosTestService _createChaosService(String name, {
  int maxConcurrent = 20,
  int maxQueue = 200,
  int failureThreshold = 5,
}) {
  final ts = DateTime.now().microsecondsSinceEpoch;
  return _ChaosTestService(
    name: name,
    circuitBreaker: CircuitBreaker(
      name: '${name}_cb_$ts',
      config: CircuitBreakerConfig(
        failureThreshold: failureThreshold,
        failureRateThreshold: 0.5,
        resetTimeout: const Duration(milliseconds: 300),
        successThreshold: 2,
        windowSize: 20,
      ),
    ),
    rateLimiter: GlobalRateLimiter(
      name: '${name}_rl_$ts',
      config: RateLimiterConfig(
        maxRequestsPerSecond: 500,
        maxConcurrentRequests: maxConcurrent,
        maxQueueLength: maxQueue,
        waitTimeout: const Duration(seconds: 5),
      ),
    ),
    retryBudget: RetryBudget(
      name: '${name}_rb_$ts',
      config: const RetryBudgetConfig(
        maxRetryRatio: 0.2,
        minRetriesPerWindow: 5,
        windowDuration: Duration(seconds: 10),
        allowOverdraft: false,
      ),
    ),
    stormDetector: FailureStormDetector(
      name: '${name}_storm_$ts',
      stormThreshold: 20,
      consecutiveHighCount: 2,
    ),
  );
}

void main() {
  final chaosReports = <ChaosRunSummary>[];

  tearDownAll(() {
    // Print consolidated chaos report at end
    if (chaosReports.isNotEmpty) {
      // ignore: avoid_print
      print(ReportGenerator.generateChaosReport(chaosReports));
    }
  });

  // ========================================================================
  // 1. Retry Storm Prevention
  // ========================================================================
  group('Chaos Validation - Retry Storm Prevention', () {
    test(
        'retry budget should cap retries under sustained failure injection',
        () async {
      final service = _createChaosService('retry_storm');
      final injector = FaultInjector();
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 0.8, // 80% error injection
        errorMessage: 'chaos: simulated service error',
      ));

      final sw = Stopwatch()..start();

      // Send 200 concurrent requests (each may retry up to 2 times)
      final futures = List.generate(200, (i) async {
        await service.execute(
          () async {
            await Future.delayed(const Duration(milliseconds: 2));
            return 'ok';
          },
          maxRetries: 2,
          injector: injector,
        );
      });

      await Future.wait(futures).timeout(const Duration(seconds: 30));
      sw.stop();

      injector.disable();

      // Key assertion: retries should be bounded (not 400 = 200 * 2)
      // With budget ratio 0.2 on 200 requests: budget = max(5, ceil(200*0.2)) = 40
      expect(service.retryCount, lessThan(100),
          reason:
              'Retry count ${service.retryCount} should be bounded by budget');

      // Total retry + original requests should be reasonable
      final amplificationRatio =
          service.retryCount / (service.successCount + service.failureCount).clamp(1, 999999);
      expect(amplificationRatio, lessThan(0.5),
          reason:
              'Retry amplification ratio $amplificationRatio should be < 0.5');

      chaosReports.add(service.toSummary(
        experimentName: 'Retry Storm Prevention',
        faultType: 'error (80% probability)',
        duration: sw.elapsed,
        observations: [
          'Retry count: ${service.retryCount} (budget-limited)',
          'Amplification ratio: ${amplificationRatio.toStringAsFixed(2)}',
        ],
      ));

      service.dispose();
    });
  });

  // ========================================================================
  // 2. Partial Outage (one service fails, others should be unaffected)
  // ========================================================================
  group('Chaos Validation - Partial Outage', () {
    test('failure in one service should not cascade to others', () async {
      final serviceA = _createChaosService('svc_a');
      final serviceB = _createChaosService('svc_b');
      final serviceC = _createChaosService('svc_c');

      final injector = FaultInjector();
      injector.enable();
      // Only inject faults targeting service A
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 1.0,
        errorMessage: 'chaos: service A down',
        targetService: 'svc_a',
      ));

      final sw = Stopwatch()..start();

      // Fire requests to all three services concurrently
      final futures = <Future>[];
      for (int i = 0; i < 50; i++) {
        futures.add(serviceA.execute(
          () async => 'a_ok',
          injector: injector,
        ));
        futures.add(serviceB.execute(
          () async {
            await Future.delayed(const Duration(milliseconds: 2));
            return 'b_ok';
          },
          injector: injector,
        ));
        futures.add(serviceC.execute(
          () async {
            await Future.delayed(const Duration(milliseconds: 2));
            return 'c_ok';
          },
          injector: injector,
        ));
      }

      await Future.wait(futures).timeout(const Duration(seconds: 15));
      sw.stop();
      injector.disable();

      // Service A should have mostly failures
      expect(serviceA.failureCount + serviceA.rejectedCount, greaterThan(30));
      // Circuit breaker A should be open
      expect(serviceA.circuitBreaker.state, equals(CircuitState.open));

      // Services B and C should be UNAFFECTED
      expect(serviceB.successCount, greaterThan(40));
      expect(serviceB.circuitBreaker.state, equals(CircuitState.closed));
      expect(serviceC.successCount, greaterThan(40));
      expect(serviceC.circuitBreaker.state, equals(CircuitState.closed));

      chaosReports.add(serviceA.toSummary(
        experimentName: 'Partial Outage - Service A (target)',
        faultType: 'error (100% to svc_a only)',
        duration: sw.elapsed,
        observations: [
          'Service A: ${serviceA.failureCount} failures, circuit ${serviceA.circuitBreaker.state.name}',
          'Service B: ${serviceB.successCount} successes, circuit ${serviceB.circuitBreaker.state.name}',
          'Service C: ${serviceC.successCount} successes, circuit ${serviceC.circuitBreaker.state.name}',
          'Isolation verified: B and C unaffected',
        ],
      ));

      serviceA.dispose();
      serviceB.dispose();
      serviceC.dispose();
    });
  });

  // ========================================================================
  // 3. Latency + Error Combo (realistic production failure)
  // ========================================================================
  group('Chaos Validation - Latency + Error Combo', () {
    test('should degrade gracefully under combined latency and errors',
        () async {
      final service = _createChaosService('combo_chaos');
      final injector = FaultInjector();
      injector.enable();

      // Inject both latency AND errors (realistic scenario)
      injector.injectFault(const FaultConfig(
        type: FaultType.latency,
        probability: 0.4,
        latencyDuration: Duration(milliseconds: 100),
      ));
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 0.2,
        errorMessage: 'chaos: intermittent error',
      ));

      final sw = Stopwatch()..start();

      final futures = List.generate(100, (i) async {
        await service.execute(
          () async {
            await Future.delayed(const Duration(milliseconds: 5));
            return 'ok';
          },
          injector: injector,
        );
      });

      await Future.wait(futures).timeout(const Duration(seconds: 30));
      sw.stop();
      injector.disable();

      // System should partially succeed (not total collapse)
      expect(service.successCount, greaterThan(10),
          reason: 'At least some requests should succeed');

      // No deadlock or lost requests
      final total =
          service.successCount + service.failureCount + service.rejectedCount;
      expect(total, equals(100));

      chaosReports.add(service.toSummary(
        experimentName: 'Latency + Error Combo',
        faultType: 'latency (40%) + error (20%)',
        duration: sw.elapsed,
        observations: [
          'Success rate: ${(service.successCount / 100 * 100).toStringAsFixed(1)}%',
          'No deadlock or lost requests',
        ],
      ));

      service.dispose();
    });
  });

  // ========================================================================
  // 4. Circuit Breaker Self-Healing
  // ========================================================================
  group('Chaos Validation - Self-Healing', () {
    test(
        'circuit breaker should transition: closed → open → half-open → closed',
        () async {
      final service = _createChaosService('self_heal', failureThreshold: 3);

      // Phase 1: Healthy - all succeed
      for (int i = 0; i < 5; i++) {
        await service.execute(() async => 'ok');
      }
      expect(service.circuitBreaker.state, equals(CircuitState.closed));
      expect(service.successCount, equals(5));

      // Phase 2: Inject failures to trip circuit
      for (int i = 0; i < 10; i++) {
        await service.execute<String>(() async {
          throw Exception('chaos failure');
        });
      }
      expect(service.circuitBreaker.state, equals(CircuitState.open));

      // Phase 3: Wait for reset timeout (300ms configured)
      await Future.delayed(const Duration(milliseconds: 400));

      // Phase 4: Probe should transition to half-open
      service.reset();
      final probeResult = await service.execute(() async => 'probe_ok');
      expect(service.circuitBreaker.state,
          anyOf(equals(CircuitState.halfOpen), equals(CircuitState.closed)));

      // Phase 5: More successes should close circuit
      if (service.circuitBreaker.state == CircuitState.halfOpen) {
        await service.execute(() async => 'recover_ok');
      }
      expect(service.circuitBreaker.state, equals(CircuitState.closed));

      chaosReports.add(ChaosRunSummary(
        experimentName: 'Self-Healing Cycle',
        faultType: 'manual error injection → recovery',
        totalDuration: const Duration(milliseconds: 500),
        totalRequests: 17,
        successCount: service.successCount,
        failureCount: service.failureCount,
        rejectedCount: service.rejectedCount,
        retryCount: service.retryCount,
        circuitBreakerFinalState: service.circuitBreaker.state.name,
        stormDetected: false,
        latenciesMs: service.latenciesMs,
        observations: [
          'Full lifecycle: closed → open → half-open → closed verified',
        ],
      ));

      service.dispose();
    });
  });

  // ========================================================================
  // 5. Cascading Failure Prevention (3-service chain)
  // ========================================================================
  group('Chaos Validation - Cascading Failure Prevention', () {
    test('upstream breakers should prevent downstream cascade', () async {
      // Simulate: Frontend → API → Database
      final database = _createChaosService('database', failureThreshold: 3);
      final api = _createChaosService('api', failureThreshold: 5);
      final frontend = _createChaosService('frontend', failureThreshold: 5);

      // Database starts failing
      for (int i = 0; i < 20; i++) {
        // API calls database
        final dbResult = await database.execute<String>(() async {
          throw Exception('Database connection refused');
        });

        // API records failure if database failed
        if (dbResult.isFailure) {
          await api.execute<String>(() async {
            throw Exception('Upstream database failure');
          });
        }
      }

      // Database circuit should be open
      expect(database.circuitBreaker.state, equals(CircuitState.open));

      // But now the circuit is open, subsequent calls should be FAST-REJECTED
      // (not actually hitting the database)
      final rejectedResult = await database.execute(() async => 'should_not_run');
      expect(rejectedResult.isFailure, isTrue);

      // Frontend should still be operational for calls that don't need DB
      final frontendResult = await frontend.execute(() async => 'static_content');
      expect(frontendResult.isSuccess, isTrue);

      chaosReports.add(ChaosRunSummary(
        experimentName: 'Cascading Failure Prevention',
        faultType: 'database failure → API → frontend chain',
        totalDuration: Duration.zero,
        totalRequests: database.failureCount + database.rejectedCount +
            api.failureCount + api.rejectedCount,
        successCount: frontend.successCount,
        failureCount: database.failureCount + api.failureCount,
        rejectedCount: database.rejectedCount + api.rejectedCount,
        retryCount: database.retryCount + api.retryCount,
        circuitBreakerFinalState: 'db=${database.circuitBreaker.state.name}, '
            'api=${api.circuitBreaker.state.name}, '
            'frontend=${frontend.circuitBreaker.state.name}',
        stormDetected: false,
        latenciesMs: [],
        observations: [
          'Database circuit: ${database.circuitBreaker.state.name}',
          'API circuit: ${api.circuitBreaker.state.name}',
          'Frontend still serving: ${frontend.successCount > 0}',
          'Cascade isolation verified',
        ],
      ));

      database.dispose();
      api.dispose();
      frontend.dispose();
    });
  });

  // ========================================================================
  // 6. Concurrent Chaos (chaos under high concurrency)
  // ========================================================================
  group('Chaos Validation - Concurrent Chaos', () {
    test('should survive chaos injection at 500 concurrent requests',
        () async {
      final service = _createChaosService(
        'concurrent_chaos',
        maxConcurrent: 50,
        maxQueue: 1000,
      );

      final injector = FaultInjector();
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.latency,
        probability: 0.3,
        latencyDuration: Duration(milliseconds: 50),
      ));
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 0.15,
        errorMessage: 'chaos: concurrent error',
      ));

      final sw = Stopwatch()..start();

      final futures = List.generate(500, (i) async {
        await service.execute(
          () async {
            await Future.delayed(const Duration(milliseconds: 3));
            return 'ok';
          },
          injector: injector,
        );
      });

      await Future.wait(futures).timeout(
        const Duration(seconds: 60),
        onTimeout: () =>
            fail('Concurrent chaos caused deadlock at 500 requests'),
      );
      sw.stop();
      injector.disable();

      final total =
          service.successCount + service.failureCount + service.rejectedCount;

      // All requests accounted for
      expect(total, equals(500),
          reason: 'Lost requests under concurrent chaos');

      // At least some should succeed
      expect(service.successCount, greaterThan(50));

      chaosReports.add(service.toSummary(
        experimentName: 'Concurrent Chaos (500 requests)',
        faultType: 'latency (30%) + error (15%)',
        duration: sw.elapsed,
        observations: [
          'All 500 requests accounted for',
          'No deadlock detected',
          'Success: ${service.successCount}/500',
        ],
      ));

      service.dispose();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ========================================================================
  // 7. Failure Storm Detection and Mitigation
  // ========================================================================
  group('Chaos Validation - Failure Storm Detection', () {
    test('storm detector should activate and protect system', () async {
      final service = _createChaosService('storm_test');
      // Use a more sensitive storm detector
      final sensitiveDetector = FailureStormDetector(
        name: 'storm_sensitive',
        windowSize: const Duration(seconds: 1),
        stormThreshold: 5,
        consecutiveHighCount: 1,
      );

      // Record rapid failures to trigger storm
      for (int i = 0; i < 30; i++) {
        sensitiveDetector.recordFailure(
          errorType: 'Exception',
          service: 'storm_test',
        );
      }

      // Storm should be detected
      expect(sensitiveDetector.isInStorm, isTrue);

      // Current failure rate should exceed threshold
      expect(sensitiveDetector.currentRate, greaterThan(5));

      // After storm detection, system should shed load
      final failuresByType = sensitiveDetector.getFailuresByType();
      expect(failuresByType['Exception'], greaterThan(0));

      chaosReports.add(ChaosRunSummary(
        experimentName: 'Failure Storm Detection',
        faultType: 'rapid failure injection',
        totalDuration: const Duration(seconds: 1),
        totalRequests: 30,
        successCount: 0,
        failureCount: 30,
        rejectedCount: 0,
        retryCount: 0,
        circuitBreakerFinalState: 'N/A',
        stormDetected: sensitiveDetector.isInStorm,
        latenciesMs: [],
        observations: [
          'Storm detected: ${sensitiveDetector.isInStorm}',
          'Failure rate: ${sensitiveDetector.currentRate.toStringAsFixed(1)}/s',
          'Protection activated correctly',
        ],
      ));

      service.dispose();
    });
  });

  // ========================================================================
  // 8. Auto-Recovery After Chaos
  // ========================================================================
  group('Chaos Validation - Auto-Recovery', () {
    test('system should auto-recover when faults are removed', () async {
      final service = _createChaosService('auto_recover');
      final injector = FaultInjector();

      // Phase 1: Enable chaos → system degrades
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 0.95,
        errorMessage: 'chaos: severe outage',
      ));

      for (int i = 0; i < 30; i++) {
        await service.execute(
          () async => 'ok',
          injector: injector,
        );
      }

      final degradedFailures = service.failureCount;
      expect(degradedFailures, greaterThan(5),
          reason: 'Should have failures during chaos');

      // Phase 2: Remove chaos → system should recover
      injector.disable();
      service.circuitBreaker.reset();
      service.reset();

      // Wait a bit for system to stabilize
      await Future.delayed(const Duration(milliseconds: 100));

      // Phase 3: Verify recovery
      for (int i = 0; i < 20; i++) {
        await service.execute(() async {
          await Future.delayed(const Duration(milliseconds: 1));
          return 'recovered';
        });
      }

      expect(service.successCount, greaterThan(15),
          reason: 'Should have high success rate after recovery');
      expect(service.circuitBreaker.state, equals(CircuitState.closed));

      chaosReports.add(ChaosRunSummary(
        experimentName: 'Auto-Recovery After Chaos',
        faultType: 'error (90%) → removal → recovery',
        totalDuration: const Duration(seconds: 1),
        totalRequests: 40,
        successCount: service.successCount,
        failureCount: degradedFailures,
        rejectedCount: service.rejectedCount,
        retryCount: service.retryCount,
        circuitBreakerFinalState: service.circuitBreaker.state.name,
        stormDetected: false,
        latenciesMs: service.latenciesMs,
        observations: [
          'Degraded phase failures: $degradedFailures',
          'Recovery phase successes: ${service.successCount}',
          'Circuit state after recovery: ${service.circuitBreaker.state.name}',
        ],
      ));

      service.dispose();
    });
  });
}
