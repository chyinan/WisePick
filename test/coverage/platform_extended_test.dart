import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/reliability_platform.dart';
import 'package:wisepick_dart_version/core/reliability/chaos_engineering.dart';
import 'package:wisepick_dart_version/core/reliability/predictive_load_manager.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';
import 'package:wisepick_dart_version/core/resilience/auto_recovery.dart';
import 'package:wisepick_dart_version/core/observability/health_check.dart';
import 'package:wisepick_dart_version/core/reliability/resilience_strategy.dart';

void main() {
  group('ReliabilityPlatform - uncovered paths', () {
    setUp(() {
      ReliabilityPlatform.instance.resetForTesting();
      HealthCheckRegistry.instance.clear();
      CircuitBreakerRegistry.instance.clear();
      GlobalRateLimiterRegistry.instance.clear();
      SloRegistry.instance.dispose();
      AutoRecoveryRegistry.instance.stopAllMonitoring();
      ChaosEngineeringManager.instance.runner.emergencyAbort();
      StrategyRegistry.instance.clear();
    });

    tearDown(() {
      try {
        ReliabilityPlatform.instance.resetForTesting();
      } catch (_) {}
      HealthCheckRegistry.instance.clear();
    });

    test('initialize with healthCheckOnStartup (healthy)', () async {
      HealthCheckRegistry.instance.register('test-health', () async {
        return ComponentHealth(
          name: 'test-health',
          status: HealthStatus.healthy,
          message: 'ok',
        );
      });

      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
          healthCheckOnStartup: true,
        ),
      );

      expect(ReliabilityPlatform.instance.isRunning, isTrue);
    });

    test('initialize with healthCheckOnStartup (unhealthy)', () async {
      HealthCheckRegistry.instance.register('unhealthy-cmp', () async {
        return ComponentHealth(
          name: 'unhealthy-cmp',
          status: HealthStatus.unhealthy,
          message: 'down',
        );
      });

      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
          healthCheckOnStartup: true,
        ),
      );

      expect(ReliabilityPlatform.instance.isRunning, isTrue);
    });

    test('initialize with healthCheckOnStartup (degraded)', () async {
      HealthCheckRegistry.instance.register('degraded-cmp', () async {
        return ComponentHealth(
          name: 'degraded-cmp',
          status: HealthStatus.degraded,
          message: 'slow',
        );
      });

      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
          healthCheckOnStartup: true,
        ),
      );

      expect(ReliabilityPlatform.instance.isRunning, isTrue);
    });

    test('analyzeRootCause when disabled throws', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enableRootCauseAnalysis: false,
          enablePredictiveLoad: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      expect(
        () => ReliabilityPlatform.instance.analyzeRootCause(),
        throwsA(isA<StateError>()),
      );
    });

    test('getDashboardSnapshot when disabled throws', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enableDashboard: false,
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
        ),
      );

      expect(
        () => ReliabilityPlatform.instance.getDashboardSnapshot(),
        throwsA(isA<StateError>()),
      );
    });

    test('runChaosExperiment when disabled throws', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enableChaosEngineering: false,
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableDashboard: false,
        ),
      );

      expect(
        () => ReliabilityPlatform.instance.runChaosExperiment('exp-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('stopChaosExperiment returns no experiment', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enableChaosEngineering: true,
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableDashboard: false,
        ),
      );

      final result = await ReliabilityPlatform.instance.stopChaosExperiment('test');
      expect(result.success, isFalse);
    });

    test('emergencyStopChaos works', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enableChaosEngineering: true,
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableDashboard: false,
        ),
      );

      await ReliabilityPlatform.instance.emergencyStopChaos();
    });

    test('executeWithResilience catches exceptions', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: true,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      ReliabilityPlatform.instance.registerService(
        const ServiceRegistration(name: 'err-svc'),
      );

      final result = await ReliabilityPlatform.instance.executeWithResilience<int>(
        'err-svc',
        'crash-op',
        () async => throw Exception('boom'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
    });

    test('registerService with predictive load', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: true,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      ReliabilityPlatform.instance.registerService(
        const ServiceRegistration(name: 'pred-svc'),
      );

      final manager = PredictiveLoadManagerRegistry.instance.get('pred-svc');
      expect(manager, isNotNull);
      manager?.stopPredictionEngine();
    });

    test('onStateChange callback', () async {
      final stateChanges = <String>[];
      ReliabilityPlatform.instance.onStateChange = (oldState, newState) {
        stateChanges.add('${oldState.name}->${newState.name}');
      };

      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      expect(stateChanges, isNotEmpty);
    });

    test('shutdown handles errors gracefully', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      await ReliabilityPlatform.instance.shutdown();
      expect(ReliabilityPlatform.instance.state, PlatformState.stopped);
    });
  });

  group('ReliabilityPlatform - predictive load actions', () {
    setUp(() {
      ReliabilityPlatform.instance.resetForTesting();
      HealthCheckRegistry.instance.clear();
      CircuitBreakerRegistry.instance.clear();
      GlobalRateLimiterRegistry.instance.clear();
      SloRegistry.instance.dispose();
      AutoRecoveryRegistry.instance.stopAllMonitoring();
      StrategyRegistry.instance.clear();
    });

    tearDown(() {
      try {
        ReliabilityPlatform.instance.resetForTesting();
      } catch (_) {}
      HealthCheckRegistry.instance.clear();
    });

    test('predictive load actions trigger through callback', () async {
      await ReliabilityPlatform.instance.initialize(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: true,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      ReliabilityPlatform.instance.registerService(
        const ServiceRegistration(name: 'action-svc'),
      );

      final manager = PredictiveLoadManagerRegistry.instance.get('action-svc');
      expect(manager, isNotNull);

      for (var i = 0; i < 20; i++) {
        manager!.recordRequestRate(100.0);
        manager.recordErrorRate(0.5);
        manager.recordResourceUsage(0.99);
      }

      manager!.stopPredictionEngine();
    });
  });

  group('convenience functions', () {
    setUp(() {
      ReliabilityPlatform.instance.resetForTesting();
      HealthCheckRegistry.instance.clear();
      CircuitBreakerRegistry.instance.clear();
      GlobalRateLimiterRegistry.instance.clear();
      SloRegistry.instance.dispose();
      AutoRecoveryRegistry.instance.stopAllMonitoring();
      StrategyRegistry.instance.clear();
    });

    tearDown(() {
      try {
        ReliabilityPlatform.instance.resetForTesting();
      } catch (_) {}
      HealthCheckRegistry.instance.clear();
    });

    test('initializeReliabilityPlatform', () async {
      await initializeReliabilityPlatform(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      expect(ReliabilityPlatform.instance.isRunning, isTrue);
    });

    test('registerReliableService', () async {
      await initializeReliabilityPlatform(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      registerReliableService(
        const ServiceRegistration(name: 'conv-svc'),
      );

      expect(ReliabilityPlatform.instance.getStatus()['registeredServices'],
          contains('conv-svc'));
    });

    test('executeReliably', () async {
      await initializeReliabilityPlatform(
        config: const ReliabilityPlatformConfig(
          enablePredictiveLoad: false,
          enableRootCauseAnalysis: false,
          enableChaosEngineering: false,
          enableDashboard: false,
        ),
      );

      registerReliableService(
        const ServiceRegistration(name: 'exec-svc'),
      );

      final result = await executeReliably<int>(
        'exec-svc',
        'my-op',
        () async => 42,
      );

      expect(result.isSuccess, isTrue);
      expect(result.value, 42);
    });
  });
}
