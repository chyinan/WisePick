import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';

void main() {
  group('CircuitBreakerConfig', () {
    test('default config should have sensible defaults', () {
      const config = CircuitBreakerConfig();
      expect(config.failureThreshold, greaterThan(0));
      expect(config.resetTimeout.inSeconds, greaterThan(0));
      expect(config.halfOpenRequests, greaterThan(0));
      expect(config.successThreshold, greaterThan(0));
      expect(config.windowSize, greaterThan(0));
    });

    test('sensitive config should have lower thresholds', () {
      expect(CircuitBreakerConfig.sensitive.failureThreshold,
          lessThan(const CircuitBreakerConfig().failureThreshold));
    });

    test('tolerant config should have higher thresholds', () {
      expect(CircuitBreakerConfig.tolerant.failureThreshold,
          greaterThan(const CircuitBreakerConfig().failureThreshold));
    });
  });

  group('CircuitBreaker - State Transitions', () {
    late CircuitBreaker breaker;

    setUp(() {
      breaker = CircuitBreaker(
        name: 'test_breaker',
        config: const CircuitBreakerConfig(
          failureThreshold: 3,
          failureRateThreshold: 0.5,
          resetTimeout: Duration(milliseconds: 200),
          halfOpenRequests: 2,
          successThreshold: 2,
          windowSize: 6, // Need at least 3 results (6 ~/ 2 = 3)
        ),
      );
    });

    test('should start in closed state', () {
      expect(breaker.state, equals(CircuitState.closed));
    });

    test('should stay closed on success', () {
      breaker.recordSuccess();
      breaker.recordSuccess();
      breaker.recordSuccess();
      expect(breaker.state, equals(CircuitState.closed));
    });

    test('should allow requests when closed', () {
      expect(breaker.allowRequest(), isTrue);
    });

    test('should open after reaching failure threshold', () {
      for (int i = 0; i < 3; i++) {
        breaker.recordFailure();
      }
      expect(breaker.state, equals(CircuitState.open));
    });

    test('should not allow requests when open', () {
      for (int i = 0; i < 3; i++) {
        breaker.recordFailure();
      }
      expect(breaker.state, equals(CircuitState.open));
      expect(breaker.allowRequest(), isFalse);
    });

    test('should transition to half-open after reset timeout', () async {
      for (int i = 0; i < 3; i++) {
        breaker.recordFailure();
      }
      expect(breaker.state, equals(CircuitState.open));

      // Wait for reset timeout
      await Future.delayed(const Duration(milliseconds: 300));

      // Should now allow probe requests (half-open)
      expect(breaker.allowRequest(), isTrue);
      expect(breaker.state, equals(CircuitState.halfOpen));
    });

    test('should close from half-open on sufficient successes', () async {
      for (int i = 0; i < 3; i++) {
        breaker.recordFailure();
      }

      await Future.delayed(const Duration(milliseconds: 300));
      breaker.allowRequest(); // transition to half-open

      // Record successes in half-open to close the breaker
      // successThreshold = 2
      breaker.recordSuccess();
      breaker.recordSuccess();
      expect(breaker.state, equals(CircuitState.closed));
    });

    test('should reopen from half-open on failure', () async {
      for (int i = 0; i < 3; i++) {
        breaker.recordFailure();
      }

      await Future.delayed(const Duration(milliseconds: 300));
      breaker.allowRequest(); // transition to half-open

      breaker.recordFailure();
      expect(breaker.state, equals(CircuitState.open));
    });

    test('reset should return to closed state', () {
      for (int i = 0; i < 3; i++) {
        breaker.recordFailure();
      }
      expect(breaker.state, equals(CircuitState.open));

      breaker.reset();
      expect(breaker.state, equals(CircuitState.closed));
      expect(breaker.allowRequest(), isTrue);
    });

    test('forceOpen should open the circuit breaker', () {
      expect(breaker.state, equals(CircuitState.closed));
      breaker.forceOpen();
      expect(breaker.state, equals(CircuitState.open));
      expect(breaker.allowRequest(), isFalse);
    });
  });

  group('CircuitBreaker - execute', () {
    late CircuitBreaker breaker;

    setUp(() {
      breaker = CircuitBreaker(
        name: 'execute_test',
        config: const CircuitBreakerConfig(
          failureThreshold: 2,
          resetTimeout: Duration(milliseconds: 100),
          windowSize: 4, // Need at least 2 results (4 ~/ 2 = 2)
        ),
      );
    });

    test('should execute and return result on success', () async {
      final result = await breaker.execute(() async => 'success');
      expect(result, equals('success'));
    });

    test('should throw CircuitBreakerException when open', () async {
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.state, equals(CircuitState.open));

      await expectLater(
        () => breaker.execute(() async => 'test'),
        throwsA(isA<CircuitBreakerException>()),
      );
    });

    test('should record failure on exception during execute', () async {
      try {
        await breaker.execute(() async => throw Exception('fail'));
      } catch (_) {}

      try {
        await breaker.execute(() async => throw Exception('fail'));
      } catch (_) {}

      expect(breaker.state, equals(CircuitState.open));
    });

    test('tryExecute should return null when circuit is open', () async {
      breaker.forceOpen();
      final result = await breaker.tryExecute(() async => 'test');
      expect(result, isNull);
    });

    test('executeWithFallback should use fallback when open', () async {
      breaker.forceOpen();
      final result = await breaker.executeWithFallback(
        () async => 'primary',
        () async => 'fallback',
      );
      expect(result, equals('fallback'));
    });
  });

  group('CircuitBreaker - getStatus', () {
    test('should return comprehensive status', () {
      final breaker = CircuitBreaker(
        name: 'status_test',
        config: const CircuitBreakerConfig(failureThreshold: 5),
      );

      breaker.recordSuccess();
      breaker.recordSuccess();
      breaker.recordFailure();

      final status = breaker.getStatus();
      expect(status['name'], equals('status_test'));
      expect(status['state'], equals('closed'));
      expect(status.containsKey('failures'), isTrue);
      expect(status.containsKey('total'), isTrue);
      expect(status.containsKey('failureRate'), isTrue);
    });
  });

  group('CircuitBreakerRegistry', () {
    tearDown(() {
      CircuitBreakerRegistry.instance.resetAll();
      CircuitBreakerRegistry.instance.clear();
    });

    test('should create and retrieve circuit breakers by name', () {
      final cb = CircuitBreakerRegistry.instance.getOrCreate('service_a');
      expect(cb, isNotNull);
      expect(cb.name, equals('service_a'));

      final cb2 = CircuitBreakerRegistry.instance.getOrCreate('service_a');
      expect(identical(cb, cb2), isTrue);
    });

    test('should return null for non-existent breaker', () {
      final cb = CircuitBreakerRegistry.instance.get('non_existent');
      expect(cb, isNull);
    });

    test('should return all statuses', () {
      CircuitBreakerRegistry.instance.getOrCreate('svc1');
      CircuitBreakerRegistry.instance.getOrCreate('svc2');

      final statuses = CircuitBreakerRegistry.instance.getAllStatus();
      expect(statuses.containsKey('svc1'), isTrue);
      expect(statuses.containsKey('svc2'), isTrue);
    });

    test('remove should delete a specific breaker', () {
      CircuitBreakerRegistry.instance.getOrCreate('temp');
      expect(CircuitBreakerRegistry.instance.get('temp'), isNotNull);

      CircuitBreakerRegistry.instance.remove('temp');
      expect(CircuitBreakerRegistry.instance.get('temp'), isNull);
    });
  });

  group('Convenience functions', () {
    tearDown(() {
      CircuitBreakerRegistry.instance.resetAll();
      CircuitBreakerRegistry.instance.clear();
    });

    test('withCircuitBreaker should execute operation', () async {
      final result = await withCircuitBreaker(
        'test_conv',
        () async => 'result',
      );
      expect(result, equals('result'));
    });

    test('withCircuitBreakerFallback should use fallback on failure', () async {
      // Force open the circuit first
      final breaker = CircuitBreakerRegistry.instance.getOrCreate(
        'fallback_test',
        config: const CircuitBreakerConfig(
          failureThreshold: 1,
          windowSize: 2,
        ),
      );
      breaker.forceOpen();

      final result = await withCircuitBreakerFallback(
        'fallback_test',
        () async => 'primary',
        () async => 'fallback',
      );
      expect(result, equals('fallback'));
    });
  });
}
