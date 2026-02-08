import 'dart:async';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/reliability.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';

void main() {
  group('ReliabilityPlatform', () {
    tearDown(() async {
      // 清理状态
      if (ReliabilityPlatform.instance.state == PlatformState.running ||
          ReliabilityPlatform.instance.state == PlatformState.shuttingDown) {
        await ReliabilityPlatform.instance.shutdown();
      }
      ReliabilityPlatform.instance.resetForTesting();
      MetricsCollector.instance.reset();
    });

    test('should initialize platform with default config', () async {
      await initializeReliabilityPlatform(
        config: ReliabilityPlatformConfig.testing,
      );

      expect(ReliabilityPlatform.instance.state, equals(PlatformState.running));
    });

    test('should register service and create all components', () async {
      await initializeReliabilityPlatform(
        config: ReliabilityPlatformConfig.testing,
      );

      registerReliableService(ServiceRegistration(
        name: 'test_service',
        sloTargets: [
          SloTarget.availability(target: 0.99),
          SloTarget.latency(targetMs: 1000),
        ],
        criticalService: true,
      ));

      // Verify circuit breaker was created
      final cb = CircuitBreakerRegistry.instance.get('test_service');
      expect(cb, isNotNull);
      expect(cb!.state, equals(CircuitState.closed));

      // Verify SLO manager was created
      final slo = SloRegistry.instance.getOrCreate('test_service');
      expect(slo, isNotNull);
    });

    test('should execute operation with resilience protection', () async {
      await initializeReliabilityPlatform(
        config: ReliabilityPlatformConfig.testing,
      );

      registerReliableService(ServiceRegistration(
        name: 'test_service',
      ));

      var executed = false;
      final result = await executeReliably<String>(
        'test_service',
        'test_operation',
        () async {
          executed = true;
          return 'success';
        },
      );

      expect(executed, isTrue);
      expect(result.isSuccess, isTrue);
      expect(result.value, equals('success'));
    });

    test('should handle errors gracefully', () async {
      await initializeReliabilityPlatform(
        config: ReliabilityPlatformConfig.testing,
      );

      registerReliableService(ServiceRegistration(
        name: 'test_service',
      ));

      final result = await executeReliably<String>(
        'test_service',
        'failing_operation',
        () async {
          throw Exception('Test error');
        },
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isA<Exception>());
    });

    test('should provide platform status', () async {
      await initializeReliabilityPlatform(
        config: ReliabilityPlatformConfig.testing,
      );

      registerReliableService(ServiceRegistration(
        name: 'status_test_service',
      ));

      final status = ReliabilityPlatform.instance.getStatus();

      expect(status['state'], equals('running'));
      expect(status['registeredServices'], contains('status_test_service'));
    });
  });

  group('PredictiveLoadManager', () {
    late PredictiveLoadManager manager;

    setUp(() {
      manager = PredictiveLoadManager(
        serviceName: 'test_service',
        minDataPointsForPrediction: 5,
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('should record and track request rates', () {
      for (int i = 0; i < 10; i++) {
        manager.recordRequestRate(0.5 + i * 0.05);
      }

      final status = manager.getStatus();
      expect(status['dataPoints']['requestRate'], equals(10));
    });

    test('should analyze trend direction', () {
      // Increasing trend
      for (int i = 0; i < 20; i++) {
        manager.recordRequestRate(0.3 + i * 0.02);
      }

      final trend = manager.analyzeTrend();
      expect(trend.direction, equals(TrendDirection.increasing));
      expect(trend.slope, greaterThan(0));
    });

    test('should predict future load', () {
      // Add historical data
      for (int i = 0; i < 50; i++) {
        manager.recordRequestRate(0.4 + (i % 10) * 0.03);
      }

      final prediction = manager.predictLoad(const Duration(minutes: 5));

      expect(prediction.predictedLoad, greaterThanOrEqualTo(0));
      expect(prediction.predictedLoad, lessThanOrEqualTo(1));
      expect(prediction.confidenceLevel, greaterThan(0));
    });
  });

  group('RootCauseAnalyzer', () {
    late RootCauseAnalyzer analyzer;

    setUp(() {
      analyzer = RootCauseAnalyzer(
        correlationWindow: const Duration(minutes: 1),
        minEventsForAnalysis: 2,
      );
    });

    test('should record and correlate events', () async {
      analyzer.recordError(
        service: 'service_a',
        component: 'database',
        error: Exception('Connection timeout'),
      );

      analyzer.recordError(
        service: 'service_a',
        component: 'api',
        error: Exception('Upstream error'),
      );

      final result = await analyzer.analyze();

      expect(result.correlatedEvents.length, greaterThanOrEqualTo(2));
      expect(result.hypotheses, isNotEmpty);
    });

    test('should identify failure patterns', () async {
      // Simulate network-related errors
      for (int i = 0; i < 5; i++) {
        analyzer.recordEvent(IncidentEvent(
          id: 'evt_$i',
          timestamp: DateTime.now(),
          service: 'test_service',
          component: 'network',
          category: EventCategory.network,
          severity: EventSeverity.error,
          description: 'Connection timeout $i',
        ));
      }

      final result = await analyzer.analyze();

      // Should identify network-related pattern
      final hasNetworkHypothesis = result.hypotheses.any(
        (h) => h.category == EventCategory.network,
      );
      expect(hasNetworkHypothesis, isTrue);
    });

    test('should generate actionable suggestions', () async {
      analyzer.recordLatencyAnomaly(
        service: 'slow_service',
        operation: 'heavy_query',
        latency: const Duration(seconds: 10),
        threshold: const Duration(seconds: 2),
      );

      final result = await analyzer.analyze();

      // Should have suggestions
      final hasSuggestions = result.hypotheses.any(
        (h) => h.suggestedActions.isNotEmpty,
      );
      expect(hasSuggestions, isTrue);
    });
  });

  group('ResilienceStrategy', () {
    test('TimeoutStrategy should enforce timeout', () async {
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
          await Future.delayed(const Duration(milliseconds: 500));
          return 'late';
        },
        context,
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isA<TimeoutException>());
    });

    test('BulkheadStrategy should limit concurrency', () async {
      final strategy = BulkheadStrategy(
        maxConcurrent: 2,
        maxWaitTime: const Duration(milliseconds: 100),
      );

      final context = StrategyContext(
        serviceName: 'test',
        operationName: 'concurrent_op',
        startTime: DateTime.now(),
      );

      // Start 3 concurrent operations (max is 2)
      final futures = List.generate(3, (i) => strategy.execute<int>(
        () async {
          await Future.delayed(const Duration(milliseconds: 200));
          return i;
        },
        context,
      ));

      final results = await Future.wait(futures);

      // At least one should be rejected
      final rejected = results.where((r) => !r.isSuccess).length;
      expect(rejected, greaterThanOrEqualTo(1));
    });

    test('StrategyPipeline should chain strategies', () async {
      final pipeline = StrategyPipeline(name: 'test_pipeline')
        ..addStrategy(TimeoutStrategy(timeout: const Duration(seconds: 5)))
        ..addStrategy(BulkheadStrategy(maxConcurrent: 10));

      var executionCount = 0;
      final result = await pipeline.execute<String>(
        () async {
          executionCount++;
          return 'result';
        },
        serviceName: 'test',
        operationName: 'chained_op',
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, equals('result'));
      expect(executionCount, equals(1));
    });
  });

  group('ChaosEngineering', () {
    late ChaosExperimentRunner runner;

    setUp(() {
      runner = ChaosExperimentRunner(
        maxExperimentDuration: const Duration(seconds: 5),
        maxErrorRateThreshold: 0.8,
        maxConcurrentFaults: 3,
      );
    });

    tearDown(() async {
      await runner.emergencyAbort();
    });

    test('should register and manage experiments', () {
      final experiment = ChaosScenarios.latencyStorm(
        targetService: 'test_service',
        latency: const Duration(milliseconds: 100),
        duration: const Duration(seconds: 2),
      );

      runner.registerExperiment(experiment);

      expect(runner.getExperiment(experiment.id), isNotNull);
      expect(runner.getAllExperiments().length, equals(1));
    });

    test('should inject faults during experiment', () async {
      final experiment = ChaosScenarios.randomErrors(
        targetService: 'fault_test',
        probability: 1.0, // Always inject
        duration: const Duration(seconds: 2),
      );

      runner.registerExperiment(experiment);
      await runner.startExperiment(experiment.id);

      expect(runner.isRunning, isTrue);
      expect(runner.injector.isEnabled, isTrue);

      // Try to inject fault
      var faultInjected = false;
      try {
        await runner.injector.maybeInjectFault(
          service: 'fault_test',
          operation: 'test_op',
        );
      } on InjectedFaultException {
        faultInjected = true;
      }

      expect(faultInjected, isTrue);

      await runner.stopExperiment();
    });

    test('should provide predefined chaos scenarios', () {
      final latencyStorm = ChaosScenarios.latencyStorm(
        targetService: 'test',
      );
      expect(latencyStorm.faults.first.type, equals(FaultType.latency));

      final randomErrors = ChaosScenarios.randomErrors(
        targetService: 'test',
      );
      expect(randomErrors.faults.first.type, equals(FaultType.error));

      final dependencyFailure = ChaosScenarios.dependencyFailure(
        dependencyService: 'downstream',
      );
      expect(dependencyFailure.faults.first.type, equals(FaultType.partition));
    });
  });

  group('ReliabilityDashboard', () {
    late ReliabilityDashboard dashboard;

    setUp(() {
      dashboard = ReliabilityDashboard();
    });

    tearDown(() {
      dashboard.dispose();
    });

    test('should register services and refresh', () async {
      dashboard.registerService('service_a');
      dashboard.registerService('service_b');

      final snapshot = await dashboard.refresh();

      expect(snapshot.timestamp, isNotNull);
      expect(snapshot.healthScore, isNotNull);
    });

    test('should calculate health score', () async {
      final snapshot = await dashboard.refresh();

      expect(snapshot.healthScore.overallScore, greaterThanOrEqualTo(0));
      expect(snapshot.healthScore.overallScore, lessThanOrEqualTo(100));
      expect(snapshot.healthScore.grade, isNotNull);
    });

    test('should track alerts', () async {
      dashboard.registerService('alerting_service');

      // Force a refresh to potentially generate alerts
      await dashboard.refresh();

      // Alerts list should be accessible
      expect(dashboard.activeAlerts, isA<List<ReliabilityAlert>>());
    });

    test('should provide metrics stream', () async {
      final stream = dashboard.getMetricsStream(
        interval: const Duration(milliseconds: 50),
      );

      var count = 0;
      await for (final metrics in stream) {
        expect(metrics, isA<Map<String, dynamic>>());
        count++;
        if (count >= 2) break;
      }

      expect(count, equals(2));
    });
  });

  group('Integration', () {
    test('full reliability workflow', () async {
      // 1. Initialize platform
      await initializeReliabilityPlatform(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: true,
          enableRootCauseAnalysis: true,
          enableChaosEngineering: false,
          enableDashboard: true,
          healthCheckOnStartup: false,
          defaultTimeout: Duration(seconds: 5),
        ),
      );

      // 2. Register services
      registerReliableService(ServiceRegistration(
        name: 'api_service',
        sloTargets: [
          SloTarget.availability(target: 0.999),
          SloTarget.latency(targetMs: 200),
        ],
        dependencies: ['database', 'cache'],
        criticalService: true,
      ));

      // 3. Execute operations
      final results = <bool>[];
      for (int i = 0; i < 10; i++) {
        final result = await executeReliably<int>(
          'api_service',
          'process_request',
          () async {
            await Future.delayed(const Duration(milliseconds: 10));
            return i;
          },
        );
        results.add(result.isSuccess);
      }

      // 4. Verify all succeeded
      expect(results.every((r) => r), isTrue);

      // 5. Check status
      final status = ReliabilityPlatform.instance.getStatus();
      expect(status['state'], equals('running'));
      expect(status['registeredServices'], contains('api_service'));

      // 6. Get dashboard snapshot
      final snapshot = await ReliabilityPlatform.instance.getDashboardSnapshot();
      expect(snapshot.services.any((s) => s.serviceName == 'api_service'), isTrue);

      // 7. Shutdown
      await ReliabilityPlatform.instance.shutdown();
      expect(ReliabilityPlatform.instance.state, equals(PlatformState.stopped));
    });
  });
}
