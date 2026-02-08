import 'dart:async';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/chaos_engineering.dart';
import 'package:wisepick_dart_version/core/reliability/resilience_strategy.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';
import 'package:wisepick_dart_version/core/resilience/retry_policy.dart';

void main() {
  group('ChaosExperiment - uncovered paths', () {
    test('copyWith state', () {
      final exp = ChaosExperiment(
        id: 'exp-1',
        name: 'test',
        description: 'desc',
        faults: [
          FaultConfig(
            type: FaultType.latency,
            probability: 1.0,
            targetService: 'svc',
          ),
        ],
        duration: const Duration(minutes: 5),
      );

      final updated = exp.copyWith(state: ExperimentState.running);
      expect(updated.state, ExperimentState.running);
      expect(updated.id, 'exp-1');
    });
  });

  group('FaultInjector - fault types', () {
    late FaultInjector injector;

    setUp(() {
      injector = FaultInjector();
      injector.enable();
    });

    tearDown(() {
      injector.disable();
    });

    test('inject corruption fault', () async {
      injector.injectFault(FaultConfig(
        type: FaultType.corruption,
        probability: 1.0,
        targetService: 'svc1',
      ));

      expect(
        () => injector.maybeInjectFault(
          service: 'svc1',
          operation: 'op',
          experimentId: 'exp1',
        ),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('inject partition fault', () async {
      injector.injectFault(FaultConfig(
        type: FaultType.partition,
        probability: 1.0,
        targetService: 'svc1',
      ));

      expect(
        () => injector.maybeInjectFault(
          service: 'svc1',
          operation: 'op',
          experimentId: 'exp1',
        ),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('inject resourceExhaustion fault', () async {
      injector.injectFault(FaultConfig(
        type: FaultType.resourceExhaustion,
        probability: 1.0,
        targetService: 'svc1',
      ));

      expect(
        () => injector.maybeInjectFault(
          service: 'svc1',
          operation: 'op',
          experimentId: 'exp1',
        ),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('inject rateLimitExceeded fault', () async {
      injector.injectFault(FaultConfig(
        type: FaultType.rateLimitExceeded,
        probability: 1.0,
        targetService: 'svc1',
      ));

      expect(
        () => injector.maybeInjectFault(
          service: 'svc1',
          operation: 'op',
          experimentId: 'exp1',
        ),
        throwsA(isA<InjectedFaultException>()),
      );
    });

    test('inject circuitOpen fault', () async {
      injector.injectFault(FaultConfig(
        type: FaultType.circuitOpen,
        probability: 1.0,
        targetService: 'svc1',
      ));

      expect(
        () => injector.maybeInjectFault(
          service: 'svc1',
          operation: 'op',
          experimentId: 'exp1',
        ),
        throwsA(isA<InjectedFaultException>()),
      );
    });
  });

  group('ChaosExperimentRunner - uncovered paths', () {
    late ChaosExperimentRunner runner;

    setUp(() {
      runner = ChaosExperimentRunner();
      MetricsCollector.instance.reset();
    });

    test('stopExperiment when no experiment running', () async {
      final result = await runner.stopExperiment();
      expect(result.success, isFalse);
      expect(result.summary, 'No experiment running');
    });

    test('experiment result analysis with safety violation', () async {
      runner.registerExperiment(ChaosExperiment(
        id: 'safety-exp',
        name: 'safety test',
        description: 'test safety',
        faults: [
          FaultConfig(
            type: FaultType.error,
            probability: 0.0,
            targetService: 'svc1',
          ),
        ],
        duration: const Duration(seconds: 1),
      ));

      await runner.startExperiment('safety-exp');
      await Future.delayed(const Duration(milliseconds: 100));

      final result = await runner.stopExperiment('Safety violation: Error rate exceeded');
      expect(result.success, isFalse);
    });

    test('experiment result analysis with duration completed', () async {
      runner.registerExperiment(ChaosExperiment(
        id: 'duration-exp',
        name: 'duration test',
        description: 'test duration',
        faults: [
          FaultConfig(
            type: FaultType.latency,
            probability: 0.0,
            targetService: 'svc1',
            latencyDuration: const Duration(milliseconds: 1),
          ),
        ],
        duration: const Duration(seconds: 30),
      ));

      await runner.startExperiment('duration-exp');
      await Future.delayed(const Duration(milliseconds: 50));

      final result = await runner.stopExperiment('Duration completed');
      expect(result.observations, contains('延迟注入测试完成'));
    });

    test('experiment analysis with timeout fault', () async {
      runner.registerExperiment(ChaosExperiment(
        id: 'timeout-exp',
        name: 'timeout test',
        description: 'test timeout fault result',
        faults: [
          FaultConfig(
            type: FaultType.timeout,
            probability: 0.0,
            targetService: 'svc1',
          ),
        ],
        duration: const Duration(seconds: 30),
      ));

      await runner.startExperiment('timeout-exp');
      await Future.delayed(const Duration(milliseconds: 50));
      final result = await runner.stopExperiment('Duration completed');
      expect(result.observations, contains('超时模拟测试完成'));
    });

    test('experiment analysis with partition fault', () async {
      runner.registerExperiment(ChaosExperiment(
        id: 'partition-exp',
        name: 'partition test',
        description: 'test partition fault result',
        faults: [
          FaultConfig(
            type: FaultType.partition,
            probability: 0.0,
            targetService: 'svc1',
          ),
        ],
        duration: const Duration(seconds: 30),
      ));

      await runner.startExperiment('partition-exp');
      await Future.delayed(const Duration(milliseconds: 50));
      final result = await runner.stopExperiment('Duration completed');
      expect(result.observations, contains('网络分区模拟完成'));
    });

    test('experiment analysis with default fault type', () async {
      runner.registerExperiment(ChaosExperiment(
        id: 'default-exp',
        name: 'default test',
        description: 'test default fault result',
        faults: [
          FaultConfig(
            type: FaultType.resourceExhaustion,
            probability: 0.0,
            targetService: 'svc1',
          ),
        ],
        duration: const Duration(seconds: 30),
      ));

      await runner.startExperiment('default-exp');
      await Future.delayed(const Duration(milliseconds: 50));
      final result = await runner.stopExperiment('Duration completed');
      expect(result.observations.any((o) => o.contains('故障注入测试')), isTrue);
    });
  });

  group('ChaosEngineeringManager - uncovered paths', () {
    test('faultPoint when not enabled', () async {
      ChaosEngineeringManager.instance.disable();
      await ChaosEngineeringManager.instance.faultPoint(
        service: 'svc',
        operation: 'op',
      );
    });

    test('faultPoint when enabled but not running', () async {
      ChaosEngineeringManager.instance.enable();
      await ChaosEngineeringManager.instance.faultPoint(
        service: 'svc',
        operation: 'op',
      );
      ChaosEngineeringManager.instance.disable();
    });
  });

  group('StrategyContext - uncovered paths', () {
    test('copyWith attemptNumber and lastError', () {
      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final copy = ctx.copyWith(
        attemptNumber: 3,
        lastError: Exception('test'),
        lastLatency: const Duration(milliseconds: 500),
      );

      expect(copy.attemptNumber, 3);
      expect(copy.lastError, isA<Exception>());
      expect(copy.lastLatency, const Duration(milliseconds: 500));
    });
  });

  group('StrategyResult - uncovered paths', () {
    test('getOrThrow with failure throws the error', () {
      final result = StrategyResult<int>.failure(
        Exception('oops'),
        strategy: 'test',
        executionTime: Duration.zero,
      );

      expect(() => result.getOrThrow(), throwsA(isA<Exception>()));
    });

    test('getOrNull returns null on failure', () {
      final result = StrategyResult<int>.failure(
        Exception('oops'),
        strategy: 'test',
        executionTime: Duration.zero,
      );

      expect(result.getOrNull(), isNull);
    });

    test('getOrThrow with success returns value', () {
      final result = StrategyResult<int>.success(
        42,
        strategy: 'test',
        executionTime: Duration.zero,
      );

      expect(result.getOrThrow(), 42);
    });
  });

  group('FallbackStrategy - uncovered paths', () {
    test('shouldFallback returns false', () async {
      final strategy = FallbackStrategy(
        fallbackFn: (ctx, err) async => 0,
        shouldFallback: (error) => false,
      );

      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        startTime: DateTime.now(),
      );
      final result = await strategy.execute<int>(
        () async => throw Exception('test'),
        ctx,
      );

      expect(result.isSuccess, isFalse);
    });

    test('fallback function throws', () async {
      final strategy = FallbackStrategy(
        fallbackFn: (ctx, err) async => throw Exception('fallback error'),
      );

      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        startTime: DateTime.now(),
      );
      final result = await strategy.execute<int>(
        () async => throw Exception('main error'),
        ctx,
      );

      expect(result.isSuccess, isFalse);
      expect(result.executedStrategy, contains('fallback'));
    });

    test('getStatus', () {
      final strategy = FallbackStrategy(
        fallbackFn: (ctx, err) async => 0,
      );

      final status = strategy.getStatus();
      expect(status['name'], 'fallback');
      expect(status['fallbackCount'], 0);
    });
  });

  group('CacheStrategy - uncovered paths', () {
    test('stale cache on error', () async {
      final strategy = CacheStrategy<int>(
        ttl: const Duration(milliseconds: 50),
        maxEntries: 10,
      );

      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result1 = await strategy.execute<int>(
        () async => 42,
        ctx,
      );
      expect(result1.value, 42);

      await Future.delayed(const Duration(milliseconds: 100));

      final result2 = await strategy.execute<int>(
        () async => throw Exception('error'),
        ctx,
      );

      expect(result2.isSuccess, isTrue);
      expect(result2.value, 42);
      expect(result2.metadata['cacheStale'], isTrue);
    });

    test('cache miss on error', () async {
      final strategy = CacheStrategy<int>(
        ttl: const Duration(seconds: 60),
        maxEntries: 10,
      );

      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        startTime: DateTime.now(),
      );

      final result = await strategy.execute<int>(
        () async => throw Exception('error'),
        ctx,
      );

      expect(result.isSuccess, isFalse);
    });

    test('eviction when full', () async {
      final strategy = CacheStrategy<int>(
        ttl: const Duration(seconds: 60),
        maxEntries: 2,
      );

      for (var i = 0; i < 3; i++) {
        final ctx = StrategyContext(
          serviceName: 'svc',
          operationName: 'op$i',
          startTime: DateTime.now(),
        );
        await strategy.execute<int>(() async => i, ctx);
      }

      final status = strategy.getStatus();
      expect(status['cacheSize'], lessThanOrEqualTo(2));
    });

    test('getStatus', () {
      final strategy = CacheStrategy<int>(
        ttl: const Duration(seconds: 60),
        maxEntries: 100,
      );

      final status = strategy.getStatus();
      expect(status['name'], 'cache');
      expect(status['maxEntries'], 100);
      expect(status['cacheSize'], 0);
      expect(status['ttlMs'], 60000);
    });

    test('invalidate and invalidateAll', () async {
      final strategy = CacheStrategy<int>(
        ttl: const Duration(seconds: 60),
        maxEntries: 10,
      );

      final ctx1 = StrategyContext(
        serviceName: 'svc',
        operationName: 'op1',
        startTime: DateTime.now(),
      );
      final ctx2 = StrategyContext(
        serviceName: 'svc',
        operationName: 'op2',
        startTime: DateTime.now(),
      );

      await strategy.execute<int>(() async => 1, ctx1);
      await strategy.execute<int>(() async => 2, ctx2);

      strategy.invalidate('svc:op1');
      strategy.invalidateAll();

      expect(strategy.getStatus()['cacheSize'], 0);
    });
  });

  group('RetryStrategy - uncovered paths', () {
    test('execute throws error', () async {
      final strategy = RetryStrategy(
        retryExecutor: RetryExecutor(
          config: const RetryConfig(maxAttempts: 1),
        ),
      );

      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        startTime: DateTime.now(),
      );
      final result = await strategy.execute<int>(
        () async => throw Exception('direct error'),
        ctx,
      );

      expect(result.isSuccess, isFalse);
    });

    test('execute success through retry', () async {
      var attempts = 0;
      final strategy = RetryStrategy(
        retryExecutor: RetryExecutor(
          config: const RetryConfig(
            maxAttempts: 3,
            initialDelay: Duration(milliseconds: 10),
          ),
        ),
        retryIf: (e) => true,
      );

      final ctx = StrategyContext(
        serviceName: 'svc',
        operationName: 'op',
        startTime: DateTime.now(),
      );
      final result = await strategy.execute<int>(
        () async {
          attempts++;
          if (attempts < 2) throw Exception('retry me');
          return 42;
        },
        ctx,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, 42);
    });

    test('getStatus', () {
      final strategy = RetryStrategy(
        retryExecutor: RetryExecutor(
          config: const RetryConfig(maxAttempts: 1),
        ),
      );

      final status = strategy.getStatus();
      expect(status['name'], 'retry');
    });
  });

  group('BulkheadStrategy - uncovered paths', () {
    test('hasCapacity', () {
      final strategy = BulkheadStrategy(maxConcurrent: 5);
      expect(strategy.hasCapacity, isTrue);
      expect(strategy.currentConcurrent, 0);
      expect(strategy.queueLength, 0);
    });
  });
}
