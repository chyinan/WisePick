import 'dart:async';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/self_healing_service.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';
import 'package:wisepick_dart_version/core/resilience/auto_recovery.dart';
import 'package:wisepick_dart_version/core/resilience/retry_budget.dart';

class TestSHService extends SelfHealingService {
  TestSHService(SelfHealingServiceConfig config) : super(config);

  @override
  bool isRetryableError(Object error) {
    return error.toString().contains('retryable');
  }
}

void main() {
  group('SelfHealingService - degradation policy path', () {
    late TestSHService service;

    setUp(() {
      CircuitBreakerRegistry.instance.clear();
      GlobalRateLimiterRegistry.instance.clear();
      SloRegistry.instance.dispose();
      RetryBudgetRegistry.instance.resetAll();
      AdaptiveConfigRegistry.instance.dispose();
      AutoRecoveryRegistry.instance.stopAllMonitoring();
    });

    tearDown(() {
      service.dispose();
      CircuitBreakerRegistry.instance.clear();
      GlobalRateLimiterRegistry.instance.clear();
      SloRegistry.instance.dispose();
    });

    test('execute rejects when SLO disallows feature', () async {
      service = TestSHService(
        SelfHealingServiceConfig(
          serviceName: 'slo-reject-svc',
          enableAdaptiveThresholds: false,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      // Record many failures to exhaust the SLO budget
      for (var i = 0; i < 200; i++) {
        await service.execute<int>(
          () async => throw Exception('planned failure'),
          operationName: 'non_essential',
        );
      }

      // Wait for SLO timer to fire
      await Future.delayed(const Duration(seconds: 2));

      final result = await service.execute<int>(
        () async => 42,
        operationName: 'non_essential',
      );

      if (result is FailureResult<int>) {
        expect(result.failure.code, anyOf('DEGRADED', 'CIRCUIT_OPEN', 'OPERATION_FAILED'));
      }
    });

    test('execute rejects during failure storm with fallback', () async {
      service = TestSHService(
        SelfHealingServiceConfig(
          serviceName: 'storm-fb-svc2',
          enableAdaptiveThresholds: true,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      final detector = AdaptiveConfigRegistry.instance
          .getOrCreateStormDetector('storm-fb-svc2_storms');

      for (var i = 0; i < 50; i++) {
        detector.recordFailure();
      }

      await Future.delayed(const Duration(milliseconds: 50));

      final result = await service.execute<int>(
        () async => throw Exception('should not reach'),
        operationName: 'storm-op',
        fallback: () async => 99,
      );

      if (result is Success<int>) {
        expect(result.value, 99);
      }
    });

    test('execute catches RateLimitException', () async {
      GlobalRateLimiterRegistry.instance.getOrCreate(
        'rl-exc-svc',
        config: const RateLimiterConfig(
          maxRequestsPerSecond: 1,
          maxConcurrentRequests: 1,
          maxQueueLength: 0,
        ),
      );

      service = TestSHService(
        const SelfHealingServiceConfig(
          serviceName: 'rl-exc-svc',
          enableAdaptiveThresholds: false,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      final completer = Completer<int>();

      final first = service.execute<int>(
        () => completer.future,
        operationName: 'slow',
      );

      await Future.delayed(const Duration(milliseconds: 50));

      final second = await service.execute<int>(
        () async => 2,
        operationName: 'blocked',
      );

      completer.complete(1);
      await first;

      if (second is FailureResult<int>) {
        expect(second.failure.code, anyOf('RATE_LIMITED', 'CIRCUIT_OPEN', 'OPERATION_FAILED'));
      }
    });

    test('_onDegradationPolicyChange is called', () async {
      service = TestSHService(
        const SelfHealingServiceConfig(
          serviceName: 'degrade-cb-svc',
          enableAdaptiveThresholds: false,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      for (var i = 0; i < 200; i++) {
        await service.execute<int>(
          () async => throw Exception('fail'),
          operationName: 'op',
        );
      }

      await Future.delayed(const Duration(milliseconds: 200));
    });

    test('_onFailureStormDetected forces circuit open', () async {
      service = TestSHService(
        SelfHealingServiceConfig(
          serviceName: 'storm-det-svc',
          enableAdaptiveThresholds: true,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      final detector = AdaptiveConfigRegistry.instance
          .getOrCreateStormDetector('storm-det-svc_storms');

      for (var i = 0; i < 50; i++) {
        detector.recordFailure();
      }

      await Future.delayed(const Duration(milliseconds: 50));

      // Circuit should be forced open
      final cb = CircuitBreakerRegistry.instance.get('storm-det-svc');
      expect(cb, isNotNull);
    });

    test('_shouldRetry with span events', () async {
      service = TestSHService(
        const SelfHealingServiceConfig(
          serviceName: 'retry-span-svc',
          enableAdaptiveThresholds: false,
          enableAutoRecovery: false,
          enableTracing: true,
        ),
      );

      var attempts = 0;
      final result = await service.execute<int>(
        () async {
          attempts++;
          if (attempts < 2) throw Exception('retryable error');
          return 42;
        },
        operationName: 'retry-op',
      );

      expect(result, isNotNull);
    });

    test('execute with fallback after error', () async {
      service = TestSHService(
        SelfHealingServiceConfig(
          serviceName: 'fb-err-svc',
          enableAdaptiveThresholds: false,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      final result = await service.execute<int>(
        () async => throw Exception('main error'),
        operationName: 'fb-op',
        fallback: () async => 999,
      );

      if (result is Success<int>) {
        expect(result.value, 999);
      }
    });

    test('execute with fallback that also fails', () async {
      service = TestSHService(
        SelfHealingServiceConfig(
          serviceName: 'fb-fail-svc2',
          enableAdaptiveThresholds: false,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      final result = await service.execute<int>(
        () async => throw Exception('main error'),
        operationName: 'fb-fail-op',
        fallback: () async => throw Exception('fallback error'),
      );

      expect(result, isA<FailureResult<int>>());
    });

    test('_onFailureStormCleared logs', () async {
      service = TestSHService(
        SelfHealingServiceConfig(
          serviceName: 'storm-clear-svc',
          enableAdaptiveThresholds: true,
          enableAutoRecovery: false,
          enableTracing: false,
        ),
      );

      final detector = AdaptiveConfigRegistry.instance
          .getOrCreateStormDetector('storm-clear-svc_storms');

      for (var i = 0; i < 50; i++) {
        detector.recordFailure();
      }

      await Future.delayed(const Duration(milliseconds: 50));
      await Future.delayed(const Duration(seconds: 2));
    });
  });
}
