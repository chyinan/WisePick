import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/auto_recovery.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';

void main() {
  group('RecoveryActionType', () {
    test('all values', () {
      expect(RecoveryActionType.values, hasLength(8));
    });
  });

  group('RecoveryAction', () {
    test('can execute initially', () {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'test-action',
        execute: () async => true,
      );
      expect(action.canExecute, isTrue);
      expect(action.cooldownRemaining, isNull);
    });

    test('tryExecute success', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.clearCache,
        name: 'clear-cache',
        execute: () async => true,
      );
      final success = await action.tryExecute();
      expect(success, isTrue);
    });

    test('tryExecute failure', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'fail-action',
        execute: () async => false,
      );
      final success = await action.tryExecute();
      expect(success, isFalse);
    });

    test('tryExecute respects maxAttempts', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'limited',
        execute: () async => false,
        maxAttempts: 2,
        cooldown: Duration.zero,
      );
      await action.tryExecute();
      await action.tryExecute();
      // 3rd attempt blocked
      final result = await action.tryExecute();
      expect(result, isFalse); // canExecute is false
    });

    test('tryExecute respects cooldown', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'cooldown-action',
        execute: () async => true,
        cooldown: const Duration(hours: 1),
        maxAttempts: 10,
      );
      await action.tryExecute();
      final result = await action.tryExecute();
      expect(result, isFalse); // still in cooldown
    });

    test('cooldownRemaining returns remaining time', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'cd-test',
        execute: () async => true,
        cooldown: const Duration(hours: 1),
      );
      await action.tryExecute();
      expect(action.cooldownRemaining, isNotNull);
      expect(action.cooldownRemaining!.inMinutes, greaterThan(50));
    });

    test('reset clears state', () async {
      final action = RecoveryAction(
        type: RecoveryActionType.custom,
        name: 'reset-test',
        execute: () async => false,
        maxAttempts: 1,
        cooldown: Duration.zero,
      );
      await action.tryExecute();
      expect(action.canExecute, isFalse);
      action.reset();
      expect(action.canExecute, isTrue);
    });

    test('getStatus', () {
      final action = RecoveryAction(
        type: RecoveryActionType.restartService,
        name: 'restart',
        execute: () async => true,
        maxAttempts: 3,
      );
      final status = action.getStatus();
      expect(status['name'], 'restart');
      expect(status['type'], 'restartService');
      expect(status['attemptCount'], 0);
      expect(status['maxAttempts'], 3);
      expect(status['canExecute'], isTrue);
      expect(status['isExecuting'], isFalse);
    });
  });

  group('HealthState', () {
    test('all values', () {
      expect(HealthState.values, hasLength(4));
    });
  });

  group('RecoveryTrigger', () {
    test('construction', () {
      final trigger = RecoveryTrigger(
        name: 'test-trigger',
        condition: () => false,
        actions: [],
        checkInterval: const Duration(seconds: 10),
      );
      expect(trigger.name, 'test-trigger');
      expect(trigger.condition(), isFalse);
    });
  });

  group('AutoRecoveryManager', () {
    test('initial state', () {
      final manager = AutoRecoveryManager(serviceName: 'test-svc');
      expect(manager.currentState, HealthState.healthy);
      expect(manager.isHealthy, isTrue);
      expect(manager.recoveryAttempts, 0);
      manager.dispose();
    });

    test('addTrigger', () {
      final manager = AutoRecoveryManager(serviceName: 'test-svc');
      manager.addTrigger(RecoveryTrigger(
        name: 'test',
        condition: () => false,
        actions: [],
      ));
      final status = manager.getStatus();
      expect((status['triggers'] as List), hasLength(1));
      manager.dispose();
    });

    test('addCircuitBreakerRecovery', () {
      final cb = CircuitBreaker(name: 'test-cb');
      final manager = AutoRecoveryManager(serviceName: 'test-svc');
      manager.addCircuitBreakerRecovery(cb);
      final status = manager.getStatus();
      expect((status['triggers'] as List), hasLength(1));
      manager.dispose();
    });

    test('startMonitoring and stopMonitoring', () {
      final manager = AutoRecoveryManager(serviceName: 'test-svc');
      manager.startMonitoring(interval: const Duration(milliseconds: 50));
      manager.stopMonitoring();
      expect(manager.currentState, HealthState.healthy);
      manager.dispose();
    });

    test('monitoring detects unhealthy state', () async {
      HealthState? oldState;
      final manager = AutoRecoveryManager(
        serviceName: 'unhealthy-svc',
        onStateChange: (o, n) {
          oldState = o;
        },
      );

      var triggerCondition = false;
      manager.addTrigger(RecoveryTrigger(
        name: 'test-trigger',
        condition: () => triggerCondition,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'quick-fix',
            execute: () async => true,
            cooldown: Duration.zero,
          ),
        ],
      ));

      triggerCondition = true;
      manager.startMonitoring(interval: const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 200));

      expect(oldState, isNotNull);
      expect(manager.recoveryAttempts, greaterThan(0));
      manager.dispose();
    });

    test('recovery back to healthy', () async {
      final manager = AutoRecoveryManager(serviceName: 'recover-svc');
      var triggerCondition = true;

      manager.addTrigger(RecoveryTrigger(
        name: 'test',
        condition: () => triggerCondition,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'fix',
            execute: () async {
              triggerCondition = false; // fix the issue
              return true;
            },
            cooldown: Duration.zero,
          ),
        ],
      ));

      manager.startMonitoring(interval: const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 300));

      // After fix, should eventually return to healthy
      expect(manager.currentState, HealthState.healthy);
      manager.dispose();
    });

    test('recovery failure leads to degraded state', () async {
      final manager = AutoRecoveryManager(serviceName: 'degrade-svc');

      manager.addTrigger(RecoveryTrigger(
        name: 'test',
        condition: () => true, // always unhealthy
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'fail-fix',
            execute: () async => false, // always fails
            cooldown: Duration.zero,
            maxAttempts: 1,
          ),
        ],
      ));

      manager.startMonitoring(interval: const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 200));

      expect(manager.currentState, HealthState.degraded);
      manager.dispose();
    });

    test('recovery action throws exception', () async {
      final manager = AutoRecoveryManager(serviceName: 'err-svc');
      final errManager = AutoRecoveryManager(
        serviceName: 'err-svc2',
        onRecoveryAttempt: (a, s) {},
      );

      errManager.addTrigger(RecoveryTrigger(
        name: 'test',
        condition: () => true,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'throw-fix',
            execute: () async => throw Exception('recovery failed'),
            cooldown: Duration.zero,
            maxAttempts: 1,
          ),
        ],
      ));

      errManager.startMonitoring(interval: const Duration(milliseconds: 50));
      await Future.delayed(const Duration(milliseconds: 200));
      errManager.dispose();
      manager.dispose();
    });

    test('forceRecovery with no triggers', () async {
      final manager = AutoRecoveryManager(serviceName: 'empty-svc');
      final result = await manager.forceRecovery();
      expect(result, isFalse);
      manager.dispose();
    });

    test('forceRecovery success', () async {
      final manager = AutoRecoveryManager(serviceName: 'force-svc');
      manager.addTrigger(RecoveryTrigger(
        name: 'test',
        condition: () => false,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'force-fix',
            execute: () async => true,
            cooldown: Duration.zero,
          ),
        ],
      ));

      final result = await manager.forceRecovery();
      expect(result, isTrue);
      expect(manager.currentState, HealthState.healthy);
      manager.dispose();
    });

    test('forceRecovery with failing action', () async {
      final manager = AutoRecoveryManager(serviceName: 'force-fail-svc');
      manager.addTrigger(RecoveryTrigger(
        name: 'test',
        condition: () => false,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'always-fail',
            execute: () async => throw Exception('cannot recover'),
            cooldown: Duration.zero,
          ),
        ],
      ));

      final result = await manager.forceRecovery();
      expect(result, isFalse);
      manager.dispose();
    });

    test('getStatus', () {
      final manager = AutoRecoveryManager(serviceName: 'status-svc');
      manager.addTrigger(RecoveryTrigger(
        name: 'trigger1',
        condition: () => false,
        actions: [
          RecoveryAction(
            type: RecoveryActionType.custom,
            name: 'action1',
            execute: () async => true,
          ),
        ],
      ));

      final status = manager.getStatus();
      expect(status['serviceName'], 'status-svc');
      expect(status['currentState'], 'healthy');
      expect(status['recoveryAttempts'], 0);
      expect(status['unhealthySince'], isNull);
      expect(status['triggers'], isA<List>());
      manager.dispose();
    });
  });

  group('RecoveryStrategies', () {
    test('exponentialReconnect success', () async {
      final action = RecoveryStrategies.exponentialReconnect(
        name: 'reconnect-test',
        connectFn: () async => true,
        initialDelay: const Duration(milliseconds: 10),
      );
      expect(action.type, RecoveryActionType.reconnectDatabase);
      expect(action.maxAttempts, 10);

      final success = await action.tryExecute();
      expect(success, isTrue);
    });

    test('exponentialReconnect failure increases delay', () async {
      int attempts = 0;
      final action = RecoveryStrategies.exponentialReconnect(
        name: 'reconnect-fail',
        connectFn: () async {
          attempts++;
          return false;
        },
        initialDelay: const Duration(milliseconds: 10),
        maxDelay: const Duration(milliseconds: 1000),
      );

      await action.tryExecute();
      expect(attempts, 1);
    });

    test('cacheRecovery without warmup', () async {
      bool cleared = false;
      final action = RecoveryStrategies.cacheRecovery(
        clearFn: () async => cleared = true,
      );
      expect(action.type, RecoveryActionType.clearCache);
      expect(action.name, 'cache_recovery');

      final success = await action.tryExecute();
      expect(success, isTrue);
      expect(cleared, isTrue);
    });

    test('cacheRecovery with warmup', () async {
      bool warmedUp = false;
      final action = RecoveryStrategies.cacheRecovery(
        clearFn: () async {},
        warmupFn: () async => warmedUp = true,
      );

      final success = await action.tryExecute();
      expect(success, isTrue);
      expect(warmedUp, isTrue);
    });

    test('loadShedding', () async {
      double lastFactor = 1.0;
      final action = RecoveryStrategies.loadShedding(
        setLoadFactor: (f) => lastFactor = f,
        targetFactor: 0.5,
        rampDuration: const Duration(milliseconds: 100),
      );
      expect(action.type, RecoveryActionType.scaleDown);
      expect(action.maxAttempts, 2);

      final success = await action.tryExecute();
      expect(success, isTrue);
      expect(lastFactor, lessThanOrEqualTo(0.6));
    });
  });

  group('AutoRecoveryRegistry', () {
    tearDown(() {
      AutoRecoveryRegistry.instance.dispose();
    });

    test('getOrCreate', () {
      final m1 = AutoRecoveryRegistry.instance.getOrCreate('svc1');
      final m2 = AutoRecoveryRegistry.instance.getOrCreate('svc1');
      expect(identical(m1, m2), isTrue);
    });

    test('getAllStatus', () {
      AutoRecoveryRegistry.instance.getOrCreate('svc1');
      AutoRecoveryRegistry.instance.getOrCreate('svc2');
      final status = AutoRecoveryRegistry.instance.getAllStatus();
      expect(status, hasLength(2));
    });

    test('startAllMonitoring and stopAllMonitoring', () {
      AutoRecoveryRegistry.instance.getOrCreate('svc1');
      AutoRecoveryRegistry.instance.startAllMonitoring();
      AutoRecoveryRegistry.instance.stopAllMonitoring();
    });
  });
}
