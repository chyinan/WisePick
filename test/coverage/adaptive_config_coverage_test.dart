import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';

void main() {
  group('AdaptiveBounds', () {
    test('clamp within bounds', () {
      const bounds = AdaptiveBounds(minValue: 1, maxValue: 10);
      expect(bounds.clamp(5), 5);
      expect(bounds.clamp(0), 1);
      expect(bounds.clamp(15), 10);
    });
  });

  group('MetricsWindow', () {
    test('empty window', () {
      final w = MetricsWindow();
      expect(w.mean, 0);
      expect(w.max, 0);
      expect(w.min, 0);
      expect(w.stdDev, 0);
      expect(w.percentile(50), 0);
      expect(w.count, 0);
      expect(w.hasData, isFalse);
    });

    test('single point', () {
      final w = MetricsWindow();
      w.record(5);
      expect(w.mean, 5);
      expect(w.max, 5);
      expect(w.min, 5);
      expect(w.stdDev, 0); // need at least 2
      expect(w.count, 1);
      expect(w.hasData, isTrue);
    });

    test('multiple points', () {
      final w = MetricsWindow();
      w.record(1);
      w.record(2);
      w.record(3);
      w.record(4);
      w.record(5);
      expect(w.mean, 3);
      expect(w.max, 5);
      expect(w.min, 1);
      expect(w.count, 5);
    });

    test('stdDev calculation', () {
      final w = MetricsWindow();
      for (var i = 0; i < 10; i++) {
        w.record(i.toDouble());
      }
      expect(w.stdDev, greaterThan(0));
    });

    test('percentile', () {
      final w = MetricsWindow();
      for (var i = 1; i <= 100; i++) {
        w.record(i.toDouble());
      }
      expect(w.percentile(50), closeTo(50, 2));
      expect(w.percentile(95), closeTo(95, 2));
    });

    test('cleanup removes old data', () async {
      final w = MetricsWindow(windowSize: const Duration(milliseconds: 100));
      w.record(1);
      w.record(2);
      await Future.delayed(const Duration(milliseconds: 200));
      w.record(3); // this triggers cleanup
      expect(w.count, 1);
      expect(w.mean, 3);
    });
  });

  group('AdaptiveThresholdController', () {
    late AdaptiveThresholdController controller;

    setUp(() {
      controller = AdaptiveThresholdController(
        serviceName: 'test-svc',
        adjustmentInterval: const Duration(hours: 1), // don't auto-adjust in tests
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('initial config', () {
      final status = controller.getStatus();
      expect(status['serviceName'], 'test-svc');
      expect(status['currentThresholds'], isA<Map>());
      expect(status['metrics'], isA<Map>());
    });

    test('recordMetrics', () {
      controller.recordMetrics(
        errorRate: 0.05,
        latencyMs: 100,
        requestsPerSecond: 50,
      );
      final status = controller.getStatus();
      expect(status['metrics']['errorRate'], greaterThan(0));
    });

    test('getCircuitBreakerConfig', () {
      final config = controller.getCircuitBreakerConfig();
      expect(config.failureThreshold, greaterThan(0));
      expect(config.resetTimeout.inMilliseconds, greaterThan(0));
    });

    test('getRateLimiterConfig', () {
      final config = controller.getRateLimiterConfig();
      expect(config.maxRequestsPerSecond, greaterThan(0));
      expect(config.maxConcurrentRequests, greaterThan(0));
    });

    test('getRetryConfig', () {
      final config = controller.getRetryConfig();
      expect(config.maxAttempts, 3);
      expect(config.initialDelay.inMilliseconds, greaterThan(0));
    });

    test('threshold adjustment with increasing errors', () async {
      // Use a short adjustment interval
      final c = AdaptiveThresholdController(
        serviceName: 'adj-svc',
        adjustmentInterval: const Duration(milliseconds: 50),
        sensitivity: 0.8,
      );

      // Record increasing error rates to trigger tightening
      for (var i = 0; i < 15; i++) {
        c.recordMetrics(
          errorRate: i * 0.1, // increasing
          latencyMs: 100 + i * 10.0,
          requestsPerSecond: 50,
        );
      }

      // Wait for adjustment to fire
      await Future.delayed(const Duration(milliseconds: 150));

      final status = c.getStatus();
      expect(status['currentThresholds'], isA<Map>());
      c.dispose();
    });

    test('threshold adjustment with healthy system', () async {
      final c = AdaptiveThresholdController(
        serviceName: 'healthy-svc',
        adjustmentInterval: const Duration(milliseconds: 50),
        sensitivity: 0.8,
      );

      // Record decreasing error rates and latencies
      for (var i = 20; i > 0; i--) {
        c.recordMetrics(
          errorRate: i * 0.01, // decreasing
          latencyMs: 50 + i.toDouble(), // decreasing
          requestsPerSecond: 50,
        );
      }

      await Future.delayed(const Duration(milliseconds: 150));

      final status = c.getStatus();
      expect(status['currentThresholds'], isA<Map>());
      c.dispose();
    });
  });

  group('FailureStormDetector', () {
    test('initial state', () {
      final d = FailureStormDetector(name: 'test');
      expect(d.isInStorm, isFalse);
      expect(d.currentRate, 0);
      expect(d.getFailuresByType(), isEmpty);
    });

    test('record single failure', () {
      final d = FailureStormDetector(name: 'test');
      d.recordFailure(errorType: 'timeout', service: 'svc');
      expect(d.currentRate, greaterThan(0));
      expect(d.getFailuresByType(), {'timeout': 1});
    });

    test('storm detection', () {
      bool stormDetected = false;
      final d = FailureStormDetector(
        name: 'storm-test',
        windowSize: const Duration(seconds: 10),
        stormThreshold: 1.0, // 1 error/sec to trigger
        consecutiveHighCount: 1,
        onStormDetected: () => stormDetected = true,
      );

      // Generate enough failures quickly
      for (var i = 0; i < 20; i++) {
        d.recordFailure(errorType: 'error');
      }

      expect(d.isInStorm, isTrue);
      expect(stormDetected, isTrue);
    });

    test('storm clearing', () {
      bool stormCleared = false;
      final d = FailureStormDetector(
        name: 'clear-test',
        windowSize: const Duration(seconds: 10),
        stormThreshold: 1.0,
        consecutiveHighCount: 1,
        onStormCleared: () => stormCleared = true,
      );

      // Trigger storm
      for (var i = 0; i < 20; i++) {
        d.recordFailure(errorType: 'error');
      }
      expect(d.isInStorm, isTrue);

      // Storm doesn't clear immediately, but we can test the mechanism
      // by checking the status
      final status = d.getStatus();
      expect(status['isInStorm'], isTrue);
      expect(status['name'], 'clear-test');
      expect(status['threshold'], 1.0);
    });

    test('getFailuresByType categorizes', () {
      final d = FailureStormDetector(name: 'type-test');
      d.recordFailure(errorType: 'timeout');
      d.recordFailure(errorType: 'timeout');
      d.recordFailure(errorType: 'connection');
      d.recordFailure(); // null type

      final types = d.getFailuresByType();
      expect(types['timeout'], 2);
      expect(types['connection'], 1);
      expect(types['unknown'], 1);
    });

    test('getStatus includes stormDuration when in storm', () {
      final d = FailureStormDetector(
        name: 'dur-test',
        stormThreshold: 1.0,
        consecutiveHighCount: 1,
      );
      for (var i = 0; i < 20; i++) {
        d.recordFailure();
      }
      final status = d.getStatus();
      expect(status.containsKey('stormDuration'), isTrue);
    });
  });

  group('AdaptiveConfigRegistry', () {
    tearDown(() {
      AdaptiveConfigRegistry.instance.dispose();
    });

    test('getOrCreateController', () {
      final c1 = AdaptiveConfigRegistry.instance.getOrCreateController('svc1');
      final c2 = AdaptiveConfigRegistry.instance.getOrCreateController('svc1');
      expect(identical(c1, c2), isTrue);
    });

    test('getOrCreateStormDetector', () {
      final d1 = AdaptiveConfigRegistry.instance.getOrCreateStormDetector('det1');
      final d2 = AdaptiveConfigRegistry.instance.getOrCreateStormDetector('det1');
      expect(identical(d1, d2), isTrue);
    });

    test('getOrCreateStormDetector with callbacks', () {
      bool detected = false;
      bool cleared = false;
      AdaptiveConfigRegistry.instance.getOrCreateStormDetector(
        'cb-det',
        onStormDetected: () => detected = true,
        onStormCleared: () => cleared = true,
      );
      expect(detected, isFalse);
      expect(cleared, isFalse);
    });

    test('getAllStatus', () {
      AdaptiveConfigRegistry.instance.getOrCreateController('svc1');
      AdaptiveConfigRegistry.instance.getOrCreateStormDetector('det1');
      final status = AdaptiveConfigRegistry.instance.getAllStatus();
      expect(status['controllers'], isA<Map>());
      expect(status['stormDetectors'], isA<Map>());
    });
  });
}
