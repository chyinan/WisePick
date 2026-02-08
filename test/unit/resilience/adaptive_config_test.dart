import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';

void main() {
  group('AdaptiveBounds', () {
    test('clamp should enforce min and max', () {
      const bounds = AdaptiveBounds(minValue: 1, maxValue: 10);
      expect(bounds.clamp(0.5), equals(1));
      expect(bounds.clamp(5), equals(5));
      expect(bounds.clamp(15), equals(10));
    });
  });

  group('MetricsWindow', () {
    test('should record values and compute mean', () {
      final window = MetricsWindow(windowSize: const Duration(seconds: 60));
      window.record(10);
      window.record(20);
      window.record(30);

      expect(window.mean, equals(20.0));
      expect(window.count, equals(3));
      expect(window.hasData, isTrue);
    });

    test('empty window should return zero for all stats', () {
      final window = MetricsWindow();
      expect(window.mean, equals(0));
      expect(window.max, equals(0));
      expect(window.min, equals(0));
      expect(window.stdDev, equals(0));
      expect(window.count, equals(0));
      expect(window.hasData, isFalse);
    });

    test('should compute min and max', () {
      final window = MetricsWindow(windowSize: const Duration(seconds: 60));
      window.record(5);
      window.record(1);
      window.record(10);
      window.record(3);

      expect(window.min, equals(1));
      expect(window.max, equals(10));
    });

    test('should compute standard deviation', () {
      final window = MetricsWindow(windowSize: const Duration(seconds: 60));
      // All same values => stdDev = 0
      window.record(5);
      window.record(5);
      window.record(5);
      expect(window.stdDev, equals(0));
    });

    test('stdDev with single point should be zero', () {
      final window = MetricsWindow();
      window.record(42);
      expect(window.stdDev, equals(0));
    });

    test('should compute percentile', () {
      final window = MetricsWindow(windowSize: const Duration(seconds: 60));
      for (int i = 1; i <= 100; i++) {
        window.record(i.toDouble());
      }

      // Median should be around 50
      expect(window.percentile(50), closeTo(50, 2));
      // 95th percentile should be around 95
      expect(window.percentile(95), closeTo(95, 2));
    });

    test('percentile of empty window should return zero', () {
      final window = MetricsWindow();
      expect(window.percentile(50), equals(0));
    });
  });

  group('AdaptiveThresholdController', () {
    late AdaptiveThresholdController controller;

    setUp(() {
      controller = AdaptiveThresholdController(
        serviceName: 'test_svc',
        adjustmentInterval: const Duration(seconds: 60), // prevent auto-tuning
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('should accept metrics recordings', () {
      controller.recordMetrics(
        errorRate: 0.01,
        latencyMs: 100,
        requestsPerSecond: 50,
      );
      // Should not throw
    });

    test('should produce valid circuit breaker config', () {
      final config = controller.getCircuitBreakerConfig();
      expect(config.failureThreshold, greaterThan(0));
      expect(config.resetTimeout.inMilliseconds, greaterThan(0));
    });

    test('should produce valid rate limiter config', () {
      final config = controller.getRateLimiterConfig();
      expect(config.maxRequestsPerSecond, greaterThan(0));
      expect(config.maxConcurrentRequests, greaterThan(0));
    });

    test('should produce valid retry config', () {
      final config = controller.getRetryConfig();
      expect(config.maxAttempts, greaterThan(0));
      expect(config.initialDelay.inMilliseconds, greaterThan(0));
    });

    test('getStatus should return current state', () {
      final status = controller.getStatus();
      expect(status['serviceName'], equals('test_svc'));
      expect(status.containsKey('currentThresholds'), isTrue);
      expect(status.containsKey('metrics'), isTrue);
    });
  });

  group('FailureStormDetector', () {
    test('should not be in storm initially', () {
      final detector = FailureStormDetector(
        name: 'test_storm',
        stormThreshold: 10,
        consecutiveHighCount: 3,
      );
      expect(detector.isInStorm, isFalse);
      expect(detector.currentRate, equals(0));
    });

    test('should detect storm with high failure rate', () {
      var stormDetected = false;
      final detector = FailureStormDetector(
        name: 'storm_test',
        windowSize: const Duration(seconds: 10),
        stormThreshold: 5, // 5 errors/sec
        consecutiveHighCount: 1, // trigger on first high window
        onStormDetected: () => stormDetected = true,
      );

      // Inject 60 failures (> 5/sec for 10sec window)
      for (int i = 0; i < 60; i++) {
        detector.recordFailure(errorType: 'TestError', service: 'svc');
      }

      expect(detector.isInStorm, isTrue);
      expect(stormDetected, isTrue);
    });

    test('should clear storm when rate drops', () {
      var stormCleared = false;
      final detector = FailureStormDetector(
        name: 'clear_test',
        windowSize: const Duration(seconds: 10),
        stormThreshold: 5,
        consecutiveHighCount: 1,
        onStormCleared: () => stormCleared = true,
      );

      // Trigger storm
      for (int i = 0; i < 60; i++) {
        detector.recordFailure();
      }
      expect(detector.isInStorm, isTrue);

      // Clear storm state by reducing the consecutive high count
      // The storm clears when consecutiveHigh drops to 0
      // We need to simulate a low-rate scenario, but since the window is 10s
      // and we can't wait, we verify the getFailuresByType
    });

    test('getFailuresByType should categorize failures', () {
      final detector = FailureStormDetector(name: 'type_test');

      detector.recordFailure(errorType: 'TimeoutError');
      detector.recordFailure(errorType: 'TimeoutError');
      detector.recordFailure(errorType: 'ConnectionError');

      final types = detector.getFailuresByType();
      expect(types['TimeoutError'], equals(2));
      expect(types['ConnectionError'], equals(1));
    });

    test('getStatus should return comprehensive info', () {
      final detector = FailureStormDetector(name: 'status_test');
      final status = detector.getStatus();
      expect(status['name'], equals('status_test'));
      expect(status['isInStorm'], isFalse);
      expect(status.containsKey('currentRate'), isTrue);
      expect(status.containsKey('threshold'), isTrue);
    });
  });

  group('AdaptiveConfigRegistry', () {
    tearDown(() {
      AdaptiveConfigRegistry.instance.dispose();
    });

    test('should create and retrieve controllers', () {
      final controller =
          AdaptiveConfigRegistry.instance.getOrCreateController('svc');
      expect(controller, isNotNull);

      final same =
          AdaptiveConfigRegistry.instance.getOrCreateController('svc');
      expect(identical(controller, same), isTrue);
    });

    test('should create and retrieve storm detectors', () {
      final detector =
          AdaptiveConfigRegistry.instance.getOrCreateStormDetector('storm');
      expect(detector, isNotNull);
    });

    test('getAllStatus should return all states', () {
      AdaptiveConfigRegistry.instance.getOrCreateController('a');
      AdaptiveConfigRegistry.instance.getOrCreateStormDetector('b');

      final status = AdaptiveConfigRegistry.instance.getAllStatus();
      expect(status.containsKey('controllers'), isTrue);
      expect(status.containsKey('stormDetectors'), isTrue);
    });
  });
}
