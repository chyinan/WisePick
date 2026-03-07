/// Chaos Engineering Tests
///
/// Randomly inject:
/// - Latency spikes
/// - Service crashes (error injection)
/// - Packet loss (simulated via random failures)
/// - Corrupted responses
/// - Clock drift (simulated via time manipulation)
///
/// Verify:
/// - Circuit breakers activate correctly
/// - Retries don't amplify load
/// - Self-healing stabilizes system
/// - No cascading collapse occurs
///
/// Generates chaos test reports.
@Tags(['stress'])
library;

import 'dart:async';
import 'package:test/test.dart';

import 'package:wisepick_dart_version/core/reliability/chaos_engineering.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';
import 'package:wisepick_dart_version/core/resilience/retry_budget.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';
import 'package:wisepick_dart_version/core/resilience/auto_recovery.dart';

// ============================================================================
// Helper: Simulated resilient operation executor
// ============================================================================
class _SimulatedService {
  final CircuitBreaker circuitBreaker;
  final RetryBudget retryBudget;
  final FailureStormDetector stormDetector;
  final GlobalRateLimiter rateLimiter;

  int successCount = 0;
  int failureCount = 0;
  int rejectedCount = 0;
  int retryCount = 0;

  _SimulatedService({
    required this.circuitBreaker,
    required this.retryBudget,
    required this.stormDetector,
    required this.rateLimiter,
  });

  Future<Result<T>> execute<T>(
    Future<T> Function() operation, {
    int maxRetries = 2,
  }) async {
    // Check storm protection
    if (stormDetector.isInStorm) {
      rejectedCount++;
      return Result.failure(Failure(message: 'Storm protection', code: 'STORM'));
    }

    // Check circuit breaker
    if (!circuitBreaker.allowRequest()) {
      rejectedCount++;
      return Result.failure(Failure(message: 'Circuit open', code: 'CIRCUIT_OPEN'));
    }

    retryBudget.recordRequest();

    try {
      final result = await rateLimiter.execute(() async {
        // Attempt with retries
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
            if (attempt < maxRetries && retryBudget.tryAcquireRetryPermit()) {
              retryCount++;
              continue;
            }
            break;
          }
        }
        // All retries exhausted
        throw lastError ?? Exception('Unknown error');
      });
      return Result.success(result as T);
    } on RateLimitException {
      rejectedCount++;
      return Result.failure(Failure(message: 'Rate limited', code: 'RATE_LIMITED'));
    } catch (e) {
      circuitBreaker.recordFailure();
      stormDetector.recordFailure(
        errorType: e.runtimeType.toString(),
        service: 'test_service',
      );
      failureCount++;
      return Result.failure(Failure(message: e.toString(), code: 'FAILED'));
    }
  }

  Map<String, dynamic> report() => {
    'successes': successCount,
    'failures': failureCount,
    'rejected': rejectedCount,
    'retries': retryCount,
    'circuitState': circuitBreaker.state.name,
    'inStorm': stormDetector.isInStorm,
  };
}

void main() {
  // ========================================================================
  // 1. FaultInjector Unit Tests
  // ========================================================================
  group('Chaos - FaultInjector', () {
    late FaultInjector injector;

    setUp(() {
      injector = FaultInjector();
    });

    tearDown(() {
      if (injector.isEnabled) injector.disable();
    });

    test('should not inject when disabled', () async {
      await injector.maybeInjectFault(
        service: 'test',
        operation: 'op',
      );
      // No exception thrown
    });

    test('should throw StateError when injecting without enable', () {
      expect(
        () => injector.injectFault(const FaultConfig(type: FaultType.error)),
        throwsA(isA<StateError>()),
      );
    });

    test('should inject error fault with probability 1.0', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 1.0,
        errorMessage: 'chaos error',
      ));

      await expectLater(
        () => injector.maybeInjectFault(service: 'svc', operation: 'op'),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('should inject latency fault', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.latency,
        probability: 1.0,
        latencyDuration: Duration(milliseconds: 50),
      ));

      final sw = Stopwatch()..start();
      await injector.maybeInjectFault(service: 'svc', operation: 'op');
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(40));
    });

    test('should inject corruption fault', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.corruption,
        probability: 1.0,
      ));

      await expectLater(
        () => injector.maybeInjectFault(service: 'svc', operation: 'op'),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('should inject partition fault', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.partition,
        probability: 1.0,
      ));

      await expectLater(
        () => injector.maybeInjectFault(service: 'svc', operation: 'op'),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('should respect target service/operation filtering', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 1.0,
        targetService: 'target_svc',
        targetOperation: 'target_op',
      ));

      // Should NOT inject for different service
      await injector.maybeInjectFault(service: 'other_svc', operation: 'other_op');
      // No exception

      // SHOULD inject for matching service/operation
      await expectLater(
        () => injector.maybeInjectFault(service: 'target_svc', operation: 'target_op'),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('should support probability-based injection', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 0.0, // 0% chance
      ));

      // Should NOT inject with 0% probability
      await injector.maybeInjectFault(service: 'svc', operation: 'op');
      // No exception
    });

    test('removeFault should remove specific fault type', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(type: FaultType.error, probability: 1.0));
      injector.injectFault(const FaultConfig(type: FaultType.latency, probability: 1.0, latencyDuration: Duration(milliseconds: 10)));

      injector.removeFault(FaultType.error);

      // Error should be gone, latency should remain
      final sw = Stopwatch()..start();
      await injector.maybeInjectFault(service: 'svc', operation: 'op');
      sw.stop();

      // Only latency applied (no error thrown)
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(5));
    });

    test('clearFaults should remove all faults', () async {
      injector.enable();
      injector.injectFault(const FaultConfig(type: FaultType.error, probability: 1.0));
      injector.clearFaults();

      // No faults active
      await injector.maybeInjectFault(service: 'svc', operation: 'op');
      // No exception
    });

    test('disable should clear all state', () {
      injector.enable();
      injector.injectFault(const FaultConfig(type: FaultType.error));
      expect(injector.activeFaults, isNotEmpty);

      injector.disable();
      expect(injector.isEnabled, isFalse);
      expect(injector.activeFaults, isEmpty);
    });
  });

  // ========================================================================
  // 2. ChaosExperiment & ChaosExperimentRunner
  // ========================================================================
  group('Chaos - ChaosExperiment Model', () {
    test('should create experiment with all fields', () {
      final exp = ChaosExperiment(
        id: 'exp_1',
        name: 'latency_test',
        description: 'Test latency resilience',
        faults: [
          const FaultConfig(
            type: FaultType.latency,
            probability: 0.5,
            latencyDuration: Duration(seconds: 2),
          ),
        ],
        duration: const Duration(minutes: 5),
        hypothesis: {'expectation': 'circuit breaker opens within 30s'},
      );

      expect(exp.id, equals('exp_1'));
      expect(exp.name, equals('latency_test'));
      expect(exp.state, equals(ExperimentState.pending));
      expect(exp.faults.length, equals(1));
    });

    test('copyWith should create modified copy', () {
      final exp = ChaosExperiment(
        id: 'exp_1',
        name: 'test',
        description: 'desc',
        faults: [],
        duration: const Duration(minutes: 1),
      );

      final running = exp.copyWith(
        state: ExperimentState.running,
        startedAt: DateTime.now(),
      );

      expect(running.state, equals(ExperimentState.running));
      expect(running.startedAt, isNotNull);
      expect(running.id, equals('exp_1'));
    });

    test('toJson should serialize correctly', () {
      final exp = ChaosExperiment(
        id: 'exp_1',
        name: 'test',
        description: 'desc',
        faults: [const FaultConfig(type: FaultType.error, probability: 0.5)],
        duration: const Duration(seconds: 30),
      );

      final json = exp.toJson();
      expect(json['id'], equals('exp_1'));
      expect(json['name'], equals('test'));
      expect(json['state'], equals('pending'));
      expect(json['faults'], isA<List>());
      expect(json['faults'].length, equals(1));
    });
  });

  group('Chaos - ChaosExperimentRunner', () {
    late ChaosExperimentRunner runner;

    setUp(() {
      runner = ChaosExperimentRunner(
        maxExperimentDuration: const Duration(minutes: 5),
        maxConcurrentFaults: 3,
        maxErrorRateThreshold: 0.5,
      );
    });

    tearDown(() async {
      if (runner.isRunning) {
        await runner.emergencyAbort();
      }
      runner.injector.disable();
    });

    test('should register and start experiments', () async {
      final exp = ChaosExperiment(
        id: 'test_exp',
        name: 'test experiment',
        description: 'Test',
        faults: [const FaultConfig(type: FaultType.error, probability: 1.0)],
        duration: const Duration(milliseconds: 100),
      );

      runner.registerExperiment(exp);
      await runner.startExperiment('test_exp');

      expect(runner.isRunning, isTrue);
      expect(runner.currentExperiment?.name, equals('test experiment'));

      // Wait for auto-stop
      await Future.delayed(const Duration(milliseconds: 300));
    });

    test('should reject starting non-existent experiment', () {
      expect(
        () async => await runner.startExperiment('missing'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should reject starting when another is running', () async {
      final exp1 = ChaosExperiment(
        id: 'exp1',
        name: 'first',
        description: 'First',
        faults: [],
        duration: const Duration(seconds: 10),
      );
      final exp2 = ChaosExperiment(
        id: 'exp2',
        name: 'second',
        description: 'Second',
        faults: [],
        duration: const Duration(seconds: 10),
      );

      runner.registerExperiment(exp1);
      runner.registerExperiment(exp2);
      await runner.startExperiment('exp1');

      await expectLater(
        () async => await runner.startExperiment('exp2'),
        throwsA(isA<StateError>()),
      );
    });

    test('should reject experiments exceeding max duration', () {
      final exp = ChaosExperiment(
        id: 'long_exp',
        name: 'too long',
        description: 'Exceeds max',
        faults: [],
        duration: const Duration(hours: 1), // > 5 minutes
      );

      runner.registerExperiment(exp);

      expect(
        () async => await runner.startExperiment('long_exp'),
        throwsA(isA<StateError>()),
      );
    });

    test('should reject experiments exceeding max concurrent faults', () {
      final exp = ChaosExperiment(
        id: 'many_faults',
        name: 'too many faults',
        description: 'Exceeds max faults',
        faults: [
          const FaultConfig(type: FaultType.error),
          const FaultConfig(type: FaultType.latency),
          const FaultConfig(type: FaultType.timeout),
          const FaultConfig(type: FaultType.corruption), // 4th > max 3
        ],
        duration: const Duration(seconds: 10),
      );

      runner.registerExperiment(exp);

      expect(
        () async => await runner.startExperiment('many_faults'),
        throwsA(isA<StateError>()),
      );
    });

    test('emergency abort should stop experiment', () async {
      final exp = ChaosExperiment(
        id: 'abort_test',
        name: 'abort test',
        description: 'Test abort',
        faults: [const FaultConfig(type: FaultType.error, probability: 1.0)],
        duration: const Duration(seconds: 30),
      );

      runner.registerExperiment(exp);
      await runner.startExperiment('abort_test');
      expect(runner.isRunning, isTrue);

      await runner.emergencyAbort();
      expect(runner.isRunning, isFalse);
    });

    test('getStatus should return comprehensive status', () {
      final status = runner.getStatus();
      expect(status, isA<Map<String, dynamic>>());
      expect(status.containsKey('isRunning'), isTrue);
    });
  });

  // ========================================================================
  // 3. Chaos Scenarios - Circuit Breaker Activation
  // ========================================================================
  group('Chaos - Circuit Breaker Activation', () {
    test('circuit breaker should open when error injection causes failures', () async {
      final service = _SimulatedService(
        circuitBreaker: CircuitBreaker(
          name: 'chaos_cb',
          config: const CircuitBreakerConfig(
            failureThreshold: 3,
            failureRateThreshold: 0.5,
            resetTimeout: Duration(milliseconds: 500),
            windowSize: 10,
          ),
        ),
        retryBudget: RetryBudget(
          name: 'chaos_budget',
          config: const RetryBudgetConfig(minRetriesPerWindow: 5),
        ),
        stormDetector: FailureStormDetector(name: 'chaos_storm'),
        rateLimiter: GlobalRateLimiter(
          name: 'chaos_limiter',
          config: const RateLimiterConfig(
            maxConcurrentRequests: 10,
            maxQueueLength: 50,
          ),
        ),
      );

      // Execute 10 operations that always fail (simulating error injection)
      for (int i = 0; i < 10; i++) {
        await service.execute<String>(() async {
          throw InjectedFaultException(
            type: FaultType.error,
            message: 'chaos error',
          );
        });
      }

      final report = service.report();
      // ignore: avoid_print
      print('=== Circuit Breaker Activation Report ===');
      report.forEach((k, v) => print('  $k: $v')); // ignore: avoid_print

      // Circuit should be open after failures
      expect(service.circuitBreaker.state, equals(CircuitState.open));
      // Some requests should be rejected (after circuit opens)
      expect(report['rejected'], greaterThan(0));

      service.rateLimiter.dispose();
    });
  });

  // ========================================================================
  // 4. Chaos Scenarios - Retry Amplification Prevention
  // ========================================================================
  group('Chaos - Retry Amplification Prevention', () {
    test('retries should not amplify load during fault injection', () async {
      final budget = RetryBudget(
        name: 'amplification_test',
        config: const RetryBudgetConfig(
          maxRetryRatio: 0.2,
          minRetriesPerWindow: 3,
          windowDuration: Duration(seconds: 10),
          allowOverdraft: false,
        ),
      );

      // Record 50 requests
      for (int i = 0; i < 50; i++) {
        budget.recordRequest();
      }

      // Budget = max(3, ceil(50 * 0.2)) = max(3, 10) = 10
      var retriesAllowed = 0;
      for (int i = 0; i < 100; i++) {
        if (budget.tryAcquireRetryPermit()) {
          retriesAllowed++;
        }
      }

      // Only 10 retries should be allowed (not 100)
      expect(retriesAllowed, equals(10));

      // Retry rate should be bounded
      final rate = budget.currentRetryRate;
      // ignore: avoid_print
      print('=== Retry Amplification Report ===');
      // ignore: avoid_print
      print('  Retries allowed: $retriesAllowed / 100 attempted');
      // ignore: avoid_print
      print('  Retry rate: ${(rate * 100).toStringAsFixed(1)}%');

      expect(retriesAllowed, lessThanOrEqualTo(10));
    });
  });

  // ========================================================================
  // 5. Chaos Scenarios - Self-Healing Stabilization
  // ========================================================================
  group('Chaos - Self-Healing Stabilization', () {
    test('system should stabilize after fault injection ends', () async {
      final breaker = CircuitBreaker(
        name: 'heal_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 3,
          failureRateThreshold: 0.5,
          resetTimeout: Duration(milliseconds: 200),
          successThreshold: 2,
          windowSize: 10,
        ),
      );

      // Phase 1: Inject failures → circuit opens
      for (int i = 0; i < 5; i++) {
        breaker.recordFailure();
      }
      expect(breaker.state, equals(CircuitState.open));

      // Phase 2: Wait for reset + send successful probes
      await Future.delayed(const Duration(milliseconds: 300));
      expect(breaker.allowRequest(), isTrue); // half-open

      // Phase 3: Successful requests → circuit closes
      breaker.recordSuccess();
      breaker.recordSuccess();
      expect(breaker.state, equals(CircuitState.closed));

      // Phase 4: Verify fully recovered
      expect(breaker.allowRequest(), isTrue);

      // ignore: avoid_print
      print('=== Self-Healing Report ===');
      // ignore: avoid_print
      print('  Final state: ${breaker.state.name}');
      // ignore: avoid_print
      print('  System stabilized: ${breaker.state == CircuitState.closed}');
    });

    test('auto-recovery should execute recovery actions', () async {
      var recovered = false;
      final manager = AutoRecoveryManager(serviceName: 'chaos_heal');

      final recoveryAction = RecoveryAction(
        name: 'reset_connections',
        type: RecoveryActionType.resetCircuitBreaker,
        execute: () async {
          recovered = true;
          return true;
        },
        maxAttempts: 3,
        cooldown: const Duration(milliseconds: 50),
      );

      manager.addTrigger(RecoveryTrigger(
        name: 'high_failure',
        condition: () => true, // always trigger in test
        actions: [recoveryAction],
      ));

      // Start monitoring with a short interval to trigger quickly
      manager.startMonitoring(interval: const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 200));

      expect(recovered, isTrue);

      // ignore: avoid_print
      print('=== Auto-Recovery Report ===');
      // ignore: avoid_print
      print('  Recovery executed: $recovered');
      // ignore: avoid_print
      print('  State: ${manager.currentState.name}');

      manager.dispose();
    });
  });

  // ========================================================================
  // 6. Chaos Scenarios - No Cascading Collapse
  // ========================================================================
  group('Chaos - No Cascading Collapse', () {
    test('multiple services should not cascade collapse', () async {
      // Create 3 services with independent circuit breakers
      final services = List.generate(3, (i) => _SimulatedService(
        circuitBreaker: CircuitBreaker(
          name: 'cascade_svc_$i',
          config: const CircuitBreakerConfig(
            failureThreshold: 3,
            failureRateThreshold: 0.5,
            resetTimeout: Duration(milliseconds: 500),
            windowSize: 10,
          ),
        ),
        retryBudget: RetryBudget(
          name: 'cascade_budget_$i',
          config: const RetryBudgetConfig(
            minRetriesPerWindow: 2,
            maxRetryRatio: 0.1,
          ),
        ),
        stormDetector: FailureStormDetector(name: 'cascade_storm_$i'),
        rateLimiter: GlobalRateLimiter(
          name: 'cascade_limiter_$i',
          config: const RateLimiterConfig(
            maxConcurrentRequests: 5,
            maxQueueLength: 20,
          ),
        ),
      ));

      // Service 0 fails completely (simulating fault injection on one service)
      for (int i = 0; i < 10; i++) {
        await services[0].execute<String>(() async {
          throw Exception('Service 0 injected failure');
        });
      }

      // Services 1 and 2 should NOT be affected
      for (int i = 0; i < 5; i++) {
        final result1 = await services[1].execute(() async => 'ok');
        final result2 = await services[2].execute(() async => 'ok');
        expect(result1.isSuccess, isTrue);
        expect(result2.isSuccess, isTrue);
      }

      // ignore: avoid_print
      print('=== Cascading Collapse Prevention Report ===');
      for (int i = 0; i < 3; i++) {
        final r = services[i].report();
        // ignore: avoid_print
        print('  Service $i: circuit=${r['circuitState']}, success=${r['successes']}, fail=${r['failures']}');
      }

      // Service 0 should be open, others should be closed
      expect(services[0].circuitBreaker.state, equals(CircuitState.open));
      expect(services[1].circuitBreaker.state, equals(CircuitState.closed));
      expect(services[2].circuitBreaker.state, equals(CircuitState.closed));

      for (final s in services) {
        s.rateLimiter.dispose();
      }
    });
  });

  // ========================================================================
  // 7. FaultConfig Tests
  // ========================================================================
  group('Chaos - FaultConfig', () {
    test('matchesTarget with no filters should match everything', () {
      const config = FaultConfig(type: FaultType.error);
      expect(config.matchesTarget('any_service', 'any_op'), isTrue);
    });

    test('matchesTarget with service filter should filter', () {
      const config = FaultConfig(type: FaultType.error, targetService: 'svc_a');
      expect(config.matchesTarget('svc_a', 'any_op'), isTrue);
      expect(config.matchesTarget('svc_b', 'any_op'), isFalse);
    });

    test('matchesTarget with operation filter should filter', () {
      const config = FaultConfig(type: FaultType.error, targetOperation: 'op_a');
      expect(config.matchesTarget('any_svc', 'op_a'), isTrue);
      expect(config.matchesTarget('any_svc', 'op_b'), isFalse);
    });

    test('toJson should serialize all fields', () {
      const config = FaultConfig(
        type: FaultType.latency,
        probability: 0.5,
        latencyDuration: Duration(seconds: 2),
        errorMessage: 'test',
        targetService: 'svc',
        targetOperation: 'op',
        duration: Duration(minutes: 5),
      );

      final json = config.toJson();
      expect(json['type'], equals('latency'));
      expect(json['probability'], equals(0.5));
      expect(json['latencyMs'], equals(2000));
      expect(json['errorMessage'], equals('test'));
      expect(json['targetService'], equals('svc'));
      expect(json['targetOperation'], equals('op'));
      expect(json['durationMs'], equals(300000));
    });
  });

  // ========================================================================
  // 8. ExperimentResult Tests
  // ========================================================================
  group('Chaos - ExperimentResult', () {
    test('should create result with all fields', () {
      const result = ExperimentResult(
        experimentId: 'exp_1',
        success: true,
        summary: 'System handled latency injection well',
        metrics: {'p99_latency_ms': 250, 'error_rate': 0.02},
        observations: ['Circuit breaker activated at 3 failures'],
        recommendations: ['Increase timeout to 5s'],
        totalDuration: Duration(minutes: 5),
      );

      expect(result.success, isTrue);
      expect(result.summary, contains('latency'));
      expect(result.metrics['p99_latency_ms'], equals(250));
      expect(result.observations.length, equals(1));
      expect(result.recommendations.length, equals(1));
    });

    test('toJson should serialize correctly', () {
      const result = ExperimentResult(
        experimentId: 'exp_1',
        success: false,
        summary: 'Test failed',
        totalDuration: Duration(seconds: 30),
      );

      final json = result.toJson();
      expect(json['experimentId'], equals('exp_1'));
      expect(json['success'], isFalse);
      expect(json['summary'], equals('Test failed'));
      expect(json['totalDurationMs'], equals(30000));
    });
  });

  // ========================================================================
  // 9. InjectedFaultException Tests
  // ========================================================================
  group('Chaos - InjectedFaultException', () {
    test('should carry fault type and message', () {
      final ex = InjectedFaultException(
        type: FaultType.error,
        message: 'test error',
        experimentId: 'exp_1',
      );

      expect(ex.type, equals(FaultType.error));
      expect(ex.message, equals('test error'));
      expect(ex.experimentId, equals('exp_1'));
      expect(ex.toString(), contains('InjectedFault'));
      expect(ex.toString(), contains('error'));
    });
  });

  // ========================================================================
  // 10. ChaosEngineeringManager
  // ========================================================================
  group('Chaos - ChaosEngineeringManager', () {
    test('should be singleton', () {
      final a = ChaosEngineeringManager.instance;
      final b = ChaosEngineeringManager.instance;
      expect(identical(a, b), isTrue);
    });

    test('faultPoint should be no-op when disabled', () async {
      ChaosEngineeringManager.instance.disable();
      // Should not throw
      await ChaosEngineeringManager.instance.faultPoint(
        service: 'test',
        operation: 'op',
      );
    });

    test('getStatus should return current state', () {
      final status = ChaosEngineeringManager.instance.getStatus();
      expect(status.containsKey('enabled'), isTrue);
      expect(status.containsKey('runner'), isTrue);
    });
  });
}
