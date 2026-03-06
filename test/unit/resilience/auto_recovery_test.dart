import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/auto_recovery.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';

void main() {
  group('RecoveryAction', () {
    test('should be executable initially', () {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'test_action',
        execute: () async => true,
      );
      expect(action.canExecute, isTrue);
    });

    test('should respect max attempts', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'limited_action',
        execute: () async => false,
        maxAttempts: 2,
        cooldown: Duration.zero,
      );

      await action.tryExecute();
      await action.tryExecute();
      expect(action.canExecute, isFalse);
    });

    test('should respect cooldown', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'cooldown_action',
        execute: () async => true,
        cooldown: const Duration(seconds: 60),
        maxAttempts: 10,
      );

      await action.tryExecute();
      expect(action.canExecute, isFalse); // Still in cooldown

      // Cooldown remaining should be positive
      expect(action.cooldownRemaining, isNotNull);
      expect(action.cooldownRemaining!.inSeconds, greaterThan(0));
    });

    test('reset should clear attempt count and cooldown', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'reset_action',
        execute: () async => true,
        maxAttempts: 1,
        cooldown: const Duration(seconds: 60),
      );

      await action.tryExecute();
      expect(action.canExecute, isFalse);

      action.reset();
      expect(action.canExecute, isTrue);
    });

    test('getStatus should return comprehensive info', () {
      final action = RecoveryAction(
        type: RecoveryActionType.clearCache,
        name: 'status_action',
        execute: () async => true,
        maxAttempts: 5,
      );

      final status = action.getStatus();
      expect(status['name'], equals('status_action'));
      expect(status['type'], equals('clearCache'));
      expect(status['maxAttempts'], equals(5));
      expect(status['canExecute'], isTrue);
    });

    test('should not allow concurrent execution', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'concurrent_test',
        execute: () async {
          await Future.delayed(const Duration(milliseconds: 100));
          return true;
        },
        cooldown: Duration.zero,
        maxAttempts: 10,
      );

      // Start first execution
      final future1 = action.tryExecute();
      await Future.delayed(const Duration(milliseconds: 10));

      // Second should fail because first is still running
      expect(action.canExecute, isFalse);

      await future1;
    });
  });

  group('AutoRecoveryManager', () {
    late AutoRecoveryManager manager;

    setUp(() {
      manager = AutoRecoveryManager(serviceName: 'test_recovery');
    });

    tearDown(() {
      manager.dispose();
    });

    test('should start in healthy state', () {
      expect(manager.currentState, equals(HealthState.healthy));
      expect(manager.isHealthy, isTrue);
    });

    test('should track recovery attempts', () {
      expect(manager.recoveryAttempts, equals(0));
    });

    test('should add triggers', () {
      var condition = false;
      manager.addTrigger(RecoveryTrigger(
        name: 'test_trigger',
        condition: () => condition,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'test',
            execute: () async => true,
          ),
        ],
      ));

      final status = manager.getStatus();
      expect(status['triggers'], isA<List>());
      expect((status['triggers'] as List).length, equals(1));
    });

    test('should add circuit breaker recovery', () {
      final cb = CircuitBreaker(
        name: 'test_cb',
        config: const CircuitBreakerConfig(failureThreshold: 3),
      );

      manager.addCircuitBreakerRecovery(cb);

      final status = manager.getStatus();
      final triggers = status['triggers'] as List;
      expect(triggers.isNotEmpty, isTrue);
    });

    test('getStatus should return comprehensive info', () {
      final status = manager.getStatus();
      expect(status['serviceName'], equals('test_recovery'));
      expect(status['currentState'], equals('healthy'));
      expect(status['recoveryAttempts'], equals(0));
    });

    test('should notify on state changes', () async {
      final stateChanges = <HealthState>[];
      final managerWithCallback = AutoRecoveryManager(
        serviceName: 'callback_test',
        onStateChange: (old, newState) => stateChanges.add(newState),
      );

      var condition = true;
      var actionResult = true;
      managerWithCallback.addTrigger(RecoveryTrigger(
        name: 'test_trigger',
        condition: () => condition,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'test_fix',
            execute: () async => actionResult,
            cooldown: Duration.zero,
          ),
        ],
      ));

      managerWithCallback.startMonitoring(
        interval: const Duration(milliseconds: 50),
      );

      // Wait for monitoring to detect unhealthy state
      await Future.delayed(const Duration(milliseconds: 200));

      managerWithCallback.dispose();

      // Should have transitioned through states
      expect(stateChanges, isNotEmpty);
    });
  });

  group('RecoveryStrategies', () {
    test('cacheRecovery should clear and warmup', () async {
      var cleared = false;
      var warmedUp = false;

      final action = RecoveryStrategies.cacheRecovery(
        clearFn: () async => cleared = true,
        warmupFn: () async => warmedUp = true,
      );

      final result = await action.tryExecute();
      expect(result, isTrue);
      expect(cleared, isTrue);
      expect(warmedUp, isTrue);
    });

    test('cacheRecovery without warmup should only clear', () async {
      var cleared = false;

      final action = RecoveryStrategies.cacheRecovery(
        clearFn: () async => cleared = true,
      );

      final result = await action.tryExecute();
      expect(result, isTrue);
      expect(cleared, isTrue);
    });

    test('loadShedding should gradually reduce load', () async {
      final factors = <double>[];
      final action = RecoveryStrategies.loadShedding(
        setLoadFactor: (f) => factors.add(f),
        targetFactor: 0.8,
        rampDuration: const Duration(milliseconds: 100),
      );

      await action.tryExecute();
      expect(factors, isNotEmpty);
      // Should have decreasing factors
      for (int i = 1; i < factors.length; i++) {
        expect(factors[i], lessThanOrEqualTo(factors[i - 1]));
      }
    });
  });

  group('AutoRecoveryRegistry', () {
    tearDown(() {
      AutoRecoveryRegistry.instance.dispose();
    });

    test('should create and retrieve managers', () {
      final manager = AutoRecoveryRegistry.instance.getOrCreate('svc_a');
      expect(manager, isNotNull);

      final same = AutoRecoveryRegistry.instance.getOrCreate('svc_a');
      expect(identical(manager, same), isTrue);
    });

    test('getAllStatus should return all statuses', () {
      AutoRecoveryRegistry.instance.getOrCreate('x');
      AutoRecoveryRegistry.instance.getOrCreate('y');

      final status = AutoRecoveryRegistry.instance.getAllStatus();
      expect(status.containsKey('x'), isTrue);
      expect(status.containsKey('y'), isTrue);
    });
  });
}
