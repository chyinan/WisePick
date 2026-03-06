/// Integration Stress Tests
///
/// Full end-to-end tests combining multiple resilience components:
/// - Circuit breaker + Rate limiter + Retry budget working together
/// - Strategy pipeline under sustained load
/// - Recovery workflow after system degradation
/// - Chaos experiment lifecycle
///
/// These tests validate that all components work correctly together
/// under realistic conditions.
library;

import 'dart:async';
import 'dart:math';
import 'package:test/test.dart';

import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';
import 'package:wisepick_dart_version/core/resilience/retry_budget.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';
import 'package:wisepick_dart_version/core/resilience/auto_recovery.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';
import 'package:wisepick_dart_version/core/observability/health_check.dart';
import 'package:wisepick_dart_version/core/reliability/resilience_strategy.dart';
import 'package:wisepick_dart_version/core/reliability/chaos_engineering.dart';

void main() {
  // ========================================================================
  // 1. Full Resilience Stack Integration
  // ========================================================================
  group('Integration - Full Resilience Stack', () {
    late CircuitBreaker circuitBreaker;
    late GlobalRateLimiter rateLimiter;
    late RetryBudget retryBudget;
    late SloManager sloManager;
    late FailureStormDetector stormDetector;
    late AdaptiveThresholdController adaptiveController;

    setUp(() {
      circuitBreaker = CircuitBreaker(
        name: 'integration_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 5,
          failureRateThreshold: 0.5,
          resetTimeout: Duration(milliseconds: 300),
          successThreshold: 2,
          windowSize: 20,
        ),
      );
      rateLimiter = GlobalRateLimiter(
        name: 'integration_rl',
        config: const RateLimiterConfig(
          maxRequestsPerSecond: 100,
          maxConcurrentRequests: 10,
          maxQueueLength: 50,
          waitTimeout: Duration(seconds: 3),
        ),
      );
      retryBudget = RetryBudget(
        name: 'integration_rb',
        config: const RetryBudgetConfig(
          maxRetryRatio: 0.2,
          minRetriesPerWindow: 5,
          windowDuration: Duration(seconds: 10),
        ),
      );
      sloManager = SloManager(
        serviceName: 'integration_slo',
        targets: [
          SloTarget.availability(target: 0.95),
          SloTarget.latency(targetMs: 500),
        ],
        checkInterval: const Duration(milliseconds: 10),
      );
      stormDetector = FailureStormDetector(name: 'integration_storm');
      adaptiveController = AdaptiveThresholdController(
        serviceName: 'integration_adaptive',
      );
    });

    tearDown(() {
      rateLimiter.dispose();
      sloManager.dispose();
    });

    test('should handle normal load through full stack', () async {
      var successes = 0;
      var failures = 0;

      for (int i = 0; i < 30; i++) {
        // Check storm protection
        if (stormDetector.isInStorm) {
          failures++;
          continue;
        }

        // Check circuit breaker
        if (!circuitBreaker.allowRequest()) {
          failures++;
          continue;
        }

        try {
          retryBudget.recordRequest();
          final result = await rateLimiter.execute(() async {
            await Future.delayed(const Duration(milliseconds: 5));
            return 'success';
          });

          circuitBreaker.recordSuccess();
          sloManager.recordRequest(
            success: true,
            latency: const Duration(milliseconds: 5),
          );
          successes++;
        } catch (e) {
          circuitBreaker.recordFailure();
          sloManager.recordRequest(success: false);
          failures++;
        }
      }

      expect(successes, greaterThan(20),
          reason: 'Most requests should succeed under normal load');
      expect(circuitBreaker.state, equals(CircuitState.closed));
      expect(stormDetector.isInStorm, isFalse);

      final budget = sloManager.getBudget('availability');
      expect(budget?.isExhausted, isFalse,
          reason: 'SLO budget should not be exhausted under normal load');
    });

    test('should degrade under failure load and recover', () async {
      // Phase 1: Normal operation
      for (int i = 0; i < 10; i++) {
        circuitBreaker.recordSuccess();
        sloManager.recordRequest(success: true, latency: const Duration(milliseconds: 10));
      }

      // Phase 2: Failures start
      for (int i = 0; i < 10; i++) {
        circuitBreaker.recordFailure();
        sloManager.recordRequest(success: false);
        stormDetector.recordFailure(
          errorType: 'Exception',
          service: 'integration',
        );
        adaptiveController.recordMetrics(
          errorRate: 1.0,
          latencyMs: 5000,
          requestsPerSecond: 5,
        );
      }

      // Circuit should be open
      expect(circuitBreaker.state, equals(CircuitState.open));

      // Phase 3: Wait for recovery
      await Future.delayed(const Duration(milliseconds: 400));

      // Circuit should transition to half-open
      expect(circuitBreaker.allowRequest(), isTrue);

      // Phase 4: Successful probes
      circuitBreaker.recordSuccess();
      circuitBreaker.recordSuccess();

      // Should be closed again
      expect(circuitBreaker.state, equals(CircuitState.closed));

      // Verify adaptive controller tracked the metrics
      final status = adaptiveController.getStatus();
      expect(status, isA<Map<String, dynamic>>());
    });

    test('adaptive controller + SLO should recommend degradation', () async {
      // Record high error rate
      for (int i = 0; i < 50; i++) {
        sloManager.recordRequest(success: false);
        adaptiveController.recordMetrics(
          errorRate: 0.8,
          latencyMs: 2000,
          requestsPerSecond: 10,
        );
      }

      final budget = sloManager.getBudget('availability');
      expect(budget!.isExhausted, isTrue);

      // Wait for SLO check timer to fire and update degradation policy
      await Future.delayed(const Duration(milliseconds: 50));

      // Non-essential features should be blocked
      expect(sloManager.isFeatureAllowed('non_essential'), isFalse);
    });
  });

  // ========================================================================
  // 2. Pipeline + Chaos Integration
  // ========================================================================
  group('Integration - Pipeline + Chaos', () {
    test('pipeline should survive chaos fault injection', () async {
      final pipeline = StrategyPipeline(name: 'chaos_pipeline');
      pipeline.addStrategy(TimeoutStrategy(timeout: const Duration(seconds: 2)));
      pipeline.addStrategy(BulkheadStrategy(maxConcurrent: 5));

      final injector = FaultInjector();
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.latency,
        probability: 0.3,
        latencyDuration: Duration(milliseconds: 50),
      ));

      var succeeded = 0;
      var failed = 0;

      for (int i = 0; i < 20; i++) {
        final result = await pipeline.execute<String>(
          () async {
            // Apply chaos fault
            await injector.maybeInjectFault(
              service: 'test',
              operation: 'op',
            );
            return 'ok';
          },
          serviceName: 'test',
          operationName: 'chaos_op_$i',
        );

        if (result.isSuccess) succeeded++;
        else failed++;
      }

      injector.disable();

      // Most should succeed (latency injection doesn't cause failures)
      expect(succeeded, greaterThan(10));

      // ignore: avoid_print
      print('=== Chaos Pipeline Report ===');
      // ignore: avoid_print
      print('  Succeeded: $succeeded / 20');
      // ignore: avoid_print
      print('  Failed: $failed / 20');
    });

    test('pipeline should degrade under error injection', () async {
      final cb = CircuitBreaker(
        name: 'chaos_cb',
        config: const CircuitBreakerConfig(
          failureThreshold: 3,
          failureRateThreshold: 0.5,
          windowSize: 10,
        ),
      );

      final pipeline = StrategyPipeline(name: 'error_chaos_pipeline');
      pipeline.addStrategy(CircuitBreakerStrategy(circuitBreaker: cb));
      pipeline.addStrategy(TimeoutStrategy(timeout: const Duration(seconds: 2)));

      final injector = FaultInjector();
      injector.enable();
      injector.injectFault(const FaultConfig(
        type: FaultType.error,
        probability: 1.0,
        errorMessage: 'chaos error',
      ));

      var failed = 0;
      for (int i = 0; i < 10; i++) {
        final result = await pipeline.execute<String>(
          () async {
            await injector.maybeInjectFault(
              service: 'test',
              operation: 'op',
            );
            return 'ok';
          },
          serviceName: 'test',
          operationName: 'error_op_$i',
        );
        if (!result.isSuccess) failed++;
      }

      injector.disable();

      // All should fail
      expect(failed, equals(10));
      // Circuit should be open
      expect(cb.state, equals(CircuitState.open));
    });
  });

  // ========================================================================
  // 3. Health Check + Recovery Integration
  // ========================================================================
  group('Integration - Health Check + Recovery', () {
    test('health check should detect degradation', () async {
      final registry = HealthCheckRegistry.instance;
      var isServiceHealthy = true;

      registry.register(
        'test_service',
        () async => ComponentHealth(
          name: 'test_service',
          status: isServiceHealthy ? HealthStatus.healthy : HealthStatus.unhealthy,
          message: isServiceHealthy ? 'OK' : 'Service degraded',
        ),
      );

      // Initially healthy
      var health = await registry.checkAll();
      expect(health.status, equals(HealthStatus.healthy));

      // Degrade
      isServiceHealthy = false;
      health = await registry.checkAll();
      expect(health.status, equals(HealthStatus.unhealthy));

      // Recover
      isServiceHealthy = true;
      health = await registry.checkAll();
      expect(health.status, equals(HealthStatus.healthy));
    });

    test('auto-recovery should respond to health degradation', () async {
      var serviceFixed = false;
      final manager = AutoRecoveryManager(serviceName: 'recovery_integration');

      final recoveryAction = RecoveryAction(
        type: RecoveryActionType.restartService,
        name: 'fix_service',
        execute: () async {
          serviceFixed = true;
          return true;
        },
        cooldown: const Duration(milliseconds: 50),
        maxAttempts: 3,
      );

      var triggerCondition = true;
      manager.addTrigger(RecoveryTrigger(
        name: 'service_degraded',
        condition: () => triggerCondition,
        actions: [recoveryAction],
      ));

      manager.startMonitoring(interval: const Duration(milliseconds: 50));

      // Wait for recovery
      await Future.delayed(const Duration(milliseconds: 200));
      expect(serviceFixed, isTrue);

      // Stop triggering
      triggerCondition = false;
      await Future.delayed(const Duration(milliseconds: 100));

      manager.dispose();
    });
  });

  // ========================================================================
  // 4. ChaosScenarios
  // ========================================================================
  group('Integration - ChaosScenarios', () {
    test('latencyStorm should create valid experiment', () {
      final exp = ChaosScenarios.latencyStorm(
        targetService: 'api',
        latency: const Duration(seconds: 1),
        probability: 0.5,
      );

      expect(exp.name, contains('延迟'));
      expect(exp.faults.length, equals(1));
      expect(exp.faults.first.type, equals(FaultType.latency));
      expect(exp.hypothesis, isNotEmpty);
    });

    test('randomErrors should create valid experiment', () {
      final exp = ChaosScenarios.randomErrors(
        targetService: 'api',
        probability: 0.3,
      );

      expect(exp.faults.length, equals(1));
      expect(exp.faults.first.type, equals(FaultType.error));
      expect(exp.faults.first.probability, equals(0.3));
    });

    test('dependencyFailure should create valid experiment', () {
      final exp = ChaosScenarios.dependencyFailure(
        dependencyService: 'database',
      );

      expect(exp.faults.length, equals(1));
      expect(exp.faults.first.type, equals(FaultType.partition));
      expect(exp.faults.first.probability, equals(1.0));
    });

    test('resourceExhaustion should create valid experiment', () {
      final exp = ChaosScenarios.resourceExhaustion(
        targetService: 'cache',
      );

      expect(exp.faults.length, equals(1));
      expect(exp.faults.first.type, equals(FaultType.resourceExhaustion));
    });

    test('cascadingFailure should create experiment for service chain', () {
      final exp = ChaosScenarios.cascadingFailure(
        serviceChain: ['frontend', 'api', 'database'],
      );

      expect(exp.faults.length, equals(3));
      // Probability should increase along the chain
      expect(exp.faults[0].probability, lessThan(exp.faults[2].probability));
    });

    test('comprehensiveResilience should create multi-fault experiment', () {
      final exp = ChaosScenarios.comprehensiveResilience(
        targetService: 'api',
      );

      expect(exp.faults.length, equals(3));
      final faultTypes = exp.faults.map((f) => f.type).toSet();
      expect(faultTypes, contains(FaultType.latency));
      expect(faultTypes, contains(FaultType.error));
      expect(faultTypes, contains(FaultType.rateLimitExceeded));
    });
  });

  // ========================================================================
  // 5. Full Chaos Experiment Lifecycle
  // ========================================================================
  group('Integration - Chaos Experiment Lifecycle', () {
    test('should complete a full experiment lifecycle', () async {
      var experimentStarted = false;
      var experimentEnded = false;
      ExperimentResult? finalResult;

      final runner = ChaosExperimentRunner(
        maxExperimentDuration: const Duration(minutes: 5),
        maxConcurrentFaults: 3,
        maxErrorRateThreshold: 0.8,
        onExperimentStart: (_) => experimentStarted = true,
        onExperimentEnd: (_, result) {
          experimentEnded = true;
          finalResult = result;
        },
      );

      // Define experiment
      final exp = ChaosExperiment(
        id: 'lifecycle_test',
        name: 'Lifecycle Test',
        description: 'Test full experiment lifecycle',
        faults: [
          const FaultConfig(
            type: FaultType.latency,
            probability: 0.5,
            latencyDuration: Duration(milliseconds: 10),
          ),
        ],
        duration: const Duration(milliseconds: 200),
        hypothesis: {'expected': 'system handles latency'},
      );

      runner.registerExperiment(exp);

      // Start
      await runner.startExperiment('lifecycle_test');
      expect(experimentStarted, isTrue);
      expect(runner.isRunning, isTrue);

      // Wait for completion
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify completion
      expect(experimentEnded, isTrue);
      expect(finalResult, isNotNull);
      expect(finalResult!.experimentId, equals('lifecycle_test'));

      // Verify experiment is stored
      final stored = runner.getExperiment('lifecycle_test');
      expect(stored, isNotNull);
      expect(stored!.state, equals(ExperimentState.completed));

      runner.injector.disable();
    });

    test('should abort experiment on emergency', () async {
      final runner = ChaosExperimentRunner(
        maxExperimentDuration: const Duration(minutes: 5),
      );

      final exp = ChaosExperiment(
        id: 'abort_lifecycle',
        name: 'Abort Test',
        description: 'Test emergency abort',
        faults: [const FaultConfig(type: FaultType.error, probability: 1.0)],
        duration: const Duration(seconds: 30),
      );

      runner.registerExperiment(exp);
      await runner.startExperiment('abort_lifecycle');

      expect(runner.isRunning, isTrue);
      await runner.emergencyAbort();
      expect(runner.isRunning, isFalse);
    });
  });

  // ========================================================================
  // 6. Metrics Integration
  // ========================================================================
  group('Integration - Metrics', () {
    test('all components should contribute to metrics', () async {
      final metrics = MetricsCollector.instance;
      metrics.reset();

      // Circuit breaker metrics
      final cb = CircuitBreaker(
        name: 'metrics_cb',
        config: const CircuitBreakerConfig(failureThreshold: 5, windowSize: 10),
      );
      cb.recordSuccess();
      cb.recordFailure();

      // Rate limiter metrics
      final rl = GlobalRateLimiter(
        name: 'metrics_rl',
        config: const RateLimiterConfig(maxConcurrentRequests: 5),
      );
      await rl.execute(() async => 'ok');

      // SLO metrics
      final slo = SloManager(
        serviceName: 'metrics_slo',
        targets: [SloTarget.availability(target: 0.99)],
        checkInterval: const Duration(seconds: 60),
      );
      slo.recordRequest(success: true);
      slo.recordRequest(success: false);

      // Verify metrics were collected
      final allMetrics = metrics.getAllMetrics();
      expect(allMetrics, isNotEmpty);

      rl.dispose();
      slo.dispose();
    });
  });

  // ========================================================================
  // 7. RecoveryStrategies Pre-built
  // ========================================================================
  group('Integration - RecoveryStrategies', () {
    test('exponentialReconnect should retry with backoff', () async {
      var attempts = 0;
      final action = RecoveryStrategies.exponentialReconnect(
        name: 'db_reconnect',
        connectFn: () async {
          attempts++;
          return attempts >= 2; // Succeed on 2nd attempt
        },
        initialDelay: const Duration(milliseconds: 10),
        maxDelay: const Duration(milliseconds: 100),
      );

      expect(action.type, equals(RecoveryActionType.reconnectDatabase));
      expect(action.maxAttempts, equals(10));

      // First attempt: fails (returns false)
      final result1 = await action.tryExecute();
      expect(result1, isFalse);
      expect(attempts, equals(1));

      // Wait for cooldown (0)
      await Future.delayed(const Duration(milliseconds: 20));

      // Second attempt: succeeds
      final result2 = await action.tryExecute();
      expect(result2, isTrue);
      expect(attempts, equals(2));
    });

    test('cacheRecovery should clear and optionally warmup', () async {
      var cleared = false;
      var warmedUp = false;

      final action = RecoveryStrategies.cacheRecovery(
        clearFn: () async => cleared = true,
        warmupFn: () async => warmedUp = true,
      );

      expect(action.type, equals(RecoveryActionType.clearCache));

      final result = await action.tryExecute();
      expect(result, isTrue);
      expect(cleared, isTrue);
      expect(warmedUp, isTrue);
    });

    test('loadShedding should gradually reduce load', () async {
      final loadFactors = <double>[];

      final action = RecoveryStrategies.loadShedding(
        setLoadFactor: (factor) => loadFactors.add(factor),
        targetFactor: 0.7,
        rampDuration: const Duration(milliseconds: 100),
      );

      expect(action.type, equals(RecoveryActionType.scaleDown));

      final result = await action.tryExecute();
      expect(result, isTrue);
      expect(loadFactors, isNotEmpty);
      // Load factors should be decreasing
      for (int i = 1; i < loadFactors.length; i++) {
        expect(loadFactors[i], lessThanOrEqualTo(loadFactors[i - 1] + 0.01));
      }
    });
  });
}
