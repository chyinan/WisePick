import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';
import 'package:wisepick_dart_version/core/observability/health_check.dart';
import 'package:wisepick_dart_version/core/logging/app_logger.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';

void main() {
  group('MetricsCollector - uncovered paths', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('getAllMetrics', () {
      MetricsCollector.instance.increment('test_counter');
      MetricsCollector.instance.setGauge('test_gauge', 42.0);
      MetricsCollector.instance.observeHistogram('test_hist', 10.0);

      final metrics = MetricsCollector.instance.getAllMetrics();
      expect(metrics, isNotEmpty);
      expect(metrics['counters'], isNotNull);
      expect(metrics['gauges'], isNotNull);
      expect(metrics['histograms'], isNotNull);
    });

    test('getHistogram null for unknown', () {
      final hist = MetricsCollector.instance.getHistogram('nonexistent');
      expect(hist, isNull);
    });

    test('getSummary with data', () {
      MetricsCollector.instance.increment(MetricsCollector.requestTotal);
      MetricsCollector.instance.increment(MetricsCollector.requestTotal);
      MetricsCollector.instance.increment(MetricsCollector.requestErrors);
      MetricsCollector.instance.observeHistogram(MetricsCollector.requestDuration, 1.5);

      final summary = MetricsCollector.instance.getSummary();
      expect(summary, isNotEmpty);
      expect(summary['requests'], isNotNull);
    });

    test('getSummary with latency histogram (covers p50/p95/p99)', () {
      for (var i = 0; i < 10; i++) {
        MetricsCollector.instance.increment(MetricsCollector.requestTotal);
      }
      for (var i = 0; i < 3; i++) {
        MetricsCollector.instance.increment(MetricsCollector.requestErrors);
      }
      for (var i = 0; i < 10; i++) {
        MetricsCollector.instance.observeHistogram(
          MetricsCollector.requestDuration,
          0.5 + i * 0.1,
        );
      }
      MetricsCollector.instance.increment(MetricsCollector.retryTotal);

      final summary = MetricsCollector.instance.getSummary();
      expect(summary['requests']?['total'], greaterThan(0));
      expect(summary['latency'], isNotNull);
      expect(summary['latency']?['mean'], isNotNull);
      expect(summary['latency']?['p50'], isNotNull);
      expect(summary['latency']?['p95'], isNotNull);
      expect(summary['latency']?['p99'], isNotNull);
    });

    test('recordRetry', () {
      MetricsCollector.instance.recordRetry(
        service: 'test-svc',
        operation: 'op1',
        attempt: 2,
        reason: 'timeout',
      );
      final metrics = MetricsCollector.instance.getAllMetrics();
      expect(metrics['counters'], isNotEmpty);
    });

    test('recordCacheAccess and cacheHitRate', () {
      MetricsCollector.instance.recordCacheAccess(cache: 'test', hit: true);
      MetricsCollector.instance.recordCacheAccess(cache: 'test', hit: false);
      MetricsCollector.instance.recordCacheAccess(cache: 'test', hit: true);
      final summary = MetricsCollector.instance.getSummary();
      expect(summary['cacheHitRate'], isNotNull);
      expect(summary['cacheHitRate'], isNot('N/A'));
    });
  });

  group('HealthCheckRegistry - uncovered paths', () {
    setUp(() {
      HealthCheckRegistry.instance.clear();
    });

    tearDown(() {
      HealthCheckRegistry.instance.clear();
      CircuitBreakerRegistry.instance.clear();
    });

    test('unregister', () async {
      HealthCheckRegistry.instance.register('tmp', () async {
        return ComponentHealth(
          name: 'tmp',
          status: HealthStatus.healthy,
          message: 'ok',
        );
      });

      HealthCheckRegistry.instance.unregister('tmp');
      // Verify it was unregistered by checking an unknown component
      final health = await HealthCheckRegistry.instance.check('tmp');
      expect(health.status, HealthStatus.unhealthy);
      expect(health.message, contains('not registered'));
    });

    test('check unknown component', () async {
      final health = await HealthCheckRegistry.instance.check('nonexistent');
      expect(health.status, HealthStatus.unhealthy);
    });

    test('threshold degraded', () async {
      HealthCheckRegistry.instance.register(
        'cpu',
        HealthCheckers.threshold(
          'cpu',
          () async => 85.0,
          warnThreshold: 80,
          criticalThreshold: 95,
        ),
      );

      final health = await HealthCheckRegistry.instance.check('cpu');
      expect(health.status, HealthStatus.degraded);
    });

    test('threshold critical', () async {
      HealthCheckRegistry.instance.register(
        'mem',
        HealthCheckers.threshold(
          'mem',
          () async => 98.0,
          warnThreshold: 80,
          criticalThreshold: 95,
        ),
      );

      final health = await HealthCheckRegistry.instance.check('mem');
      expect(health.status, HealthStatus.unhealthy);
    });

    test('threshold with error in getValue', () async {
      HealthCheckRegistry.instance.register(
        'err-metric',
        HealthCheckers.threshold(
          'err-metric',
          () async => throw Exception('metric error'),
          warnThreshold: 80,
          criticalThreshold: 95,
        ),
      );

      final health = await HealthCheckRegistry.instance.check('err-metric');
      expect(health.status, HealthStatus.unhealthy);
    });

    test('check with timeout', () async {
      HealthCheckRegistry.instance.register('slow-check', () async {
        await Future.delayed(const Duration(seconds: 5));
        return ComponentHealth(
          name: 'slow-check',
          status: HealthStatus.healthy,
          message: 'ok',
        );
      });

      final health = await HealthCheckRegistry.instance.check(
        'slow-check',
        timeout: const Duration(milliseconds: 100),
      );
      expect(health.status, HealthStatus.unhealthy);
      expect(health.message, contains('timed out'));
    });

    test('check with exception returns unhealthy', () async {
      HealthCheckRegistry.instance.register('throw-check', () {
        return Future<ComponentHealth>.error(Exception('check error'));
      });

      final health = await HealthCheckRegistry.instance.check('throw-check');
      expect(health.status, HealthStatus.unhealthy);
      expect(health.message, contains('check error'));
    });

    test('circuitBreaker open state', () async {
      final cb = CircuitBreakerRegistry.instance.getOrCreate(
        'hc-cb-test',
        config: const CircuitBreakerConfig(
          failureThreshold: 3,
          windowSize: 5,
          resetTimeout: Duration(seconds: 60),
        ),
      );

      // Need at least windowSize ~/ 2 = 2 results for shouldOpenCircuit
      for (var i = 0; i < 5; i++) {
        cb.recordFailure();
      }

      HealthCheckRegistry.instance.register(
        'cb-check',
        HealthCheckers.circuitBreaker(
          'cb-check',
          () => cb.getStatus(),
        ),
      );

      final health = await HealthCheckRegistry.instance.check('cb-check');
      expect(health.status, HealthStatus.unhealthy);

      CircuitBreakerRegistry.instance.clear();
    });
  });

  group('AppLogger - uncovered paths', () {
    test('log with module and error', () {
      final logger = AppLogger.instance.module('test-module');
      logger.error('test error', error: Exception('test'), stackTrace: StackTrace.current);
    });

    test('global logging functions', () {
      AppLogger.instance.module('global-test').debug('debug msg');
      AppLogger.instance.module('global-test').info('info msg');
      AppLogger.instance.module('global-test').warning('warn msg');
    });
  });

  group('AdaptiveConfig - uncovered paths', () {
    test('AdaptiveThresholdController adjustConfig with error rate trends', () {
      final controller = AdaptiveThresholdController(
        serviceName: 'adapt-svc',
      );

      for (var i = 0; i < 30; i++) {
        controller.recordMetrics(
          errorRate: 0.5,
          latencyMs: 500,
          requestsPerSecond: 100,
        );
      }

      final status = controller.getStatus();
      expect(status, isNotNull);
    });

    test('AdaptiveThresholdController adjustConfig with low throughput', () {
      final controller = AdaptiveThresholdController(
        serviceName: 'low-tp-svc',
      );

      for (var i = 0; i < 30; i++) {
        controller.recordMetrics(
          errorRate: 0.01,
          latencyMs: 100,
          requestsPerSecond: 0.5,
        );
      }

      final status = controller.getStatus();
      expect(status, isNotNull);
    });

    test('AdaptiveThresholdController adjustConfig with high latency', () {
      final controller = AdaptiveThresholdController(
        serviceName: 'hi-lat-svc',
      );

      for (var i = 0; i < 30; i++) {
        controller.recordMetrics(
          errorRate: 0.01,
          latencyMs: 5000,
          requestsPerSecond: 50,
        );
      }

      final status = controller.getStatus();
      expect(status, isNotNull);
    });

    test('AdaptiveConfigRegistry dispose', () {
      AdaptiveConfigRegistry.instance.getOrCreateController('dispose-svc');
      AdaptiveConfigRegistry.instance.dispose();
    });
  });
}
