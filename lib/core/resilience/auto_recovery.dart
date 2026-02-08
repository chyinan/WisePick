import 'dart:async';
import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';
import 'circuit_breaker.dart';

/// Recovery action types
enum RecoveryActionType {
  resetCircuitBreaker,
  clearCache,
  reconnectDatabase,
  restartService,
  scaleDown,
  switchToFallback,
  notifyOperator,
  custom,
}

/// Recovery action definition
class RecoveryAction {
  final RecoveryActionType type;
  final String name;
  final Future<bool> Function() execute;
  final Duration cooldown;
  final int maxAttempts;

  DateTime? _lastAttempt;
  int _attemptCount = 0;
  bool _isExecuting = false;

  RecoveryAction({
    required this.type,
    required this.name,
    required this.execute,
    this.cooldown = const Duration(minutes: 5),
    this.maxAttempts = 3,
  });

  bool get canExecute {
    if (_isExecuting) return false;
    if (_attemptCount >= maxAttempts) return false;
    if (_lastAttempt != null) {
      final elapsed = DateTime.now().difference(_lastAttempt!);
      if (elapsed < cooldown) return false;
    }
    return true;
  }

  Duration? get cooldownRemaining {
    if (_lastAttempt == null) return null;
    final elapsed = DateTime.now().difference(_lastAttempt!);
    final remaining = cooldown - elapsed;
    return remaining.isNegative ? null : remaining;
  }

  Future<bool> tryExecute() async {
    if (!canExecute) return false;

    _isExecuting = true;
    _lastAttempt = DateTime.now();
    _attemptCount++;

    try {
      final success = await execute();
      return success;
    } finally {
      _isExecuting = false;
    }
  }

  void reset() {
    _attemptCount = 0;
    _lastAttempt = null;
  }

  Map<String, dynamic> getStatus() => {
        'name': name,
        'type': type.name,
        'attemptCount': _attemptCount,
        'maxAttempts': maxAttempts,
        'canExecute': canExecute,
        'cooldownRemaining': cooldownRemaining?.inSeconds,
        'isExecuting': _isExecuting,
      };
}

/// Health state
enum HealthState {
  healthy,
  degraded,
  unhealthy,
  recovering,
}

/// Recovery trigger condition
class RecoveryTrigger {
  final String name;
  final bool Function() condition;
  final List<RecoveryAction> actions;
  final Duration checkInterval;

  const RecoveryTrigger({
    required this.name,
    required this.condition,
    required this.actions,
    this.checkInterval = const Duration(seconds: 30),
  });
}

/// Auto recovery manager for a service
class AutoRecoveryManager {
  final String serviceName;
  final ModuleLogger _logger;
  final List<RecoveryTrigger> _triggers = [];

  Timer? _monitorTimer;
  HealthState _currentState = HealthState.healthy;
  DateTime? _unhealthySince;
  int _recoveryAttempts = 0;

  final void Function(HealthState oldState, HealthState newState)? onStateChange;
  final void Function(RecoveryAction action, bool success)? onRecoveryAttempt;

  AutoRecoveryManager({
    required this.serviceName,
    this.onStateChange,
    this.onRecoveryAttempt,
  }) : _logger = AppLogger.instance.module('AutoRecovery:$serviceName');

  HealthState get currentState => _currentState;
  bool get isHealthy => _currentState == HealthState.healthy;
  int get recoveryAttempts => _recoveryAttempts;

  /// Add a recovery trigger
  void addTrigger(RecoveryTrigger trigger) {
    _triggers.add(trigger);
  }

  /// Add common circuit breaker recovery
  void addCircuitBreakerRecovery(CircuitBreaker circuitBreaker) {
    addTrigger(RecoveryTrigger(
      name: 'circuit_breaker_recovery',
      condition: () => circuitBreaker.state == CircuitState.open,
      actions: [
        RecoveryAction(
          type: RecoveryActionType.resetCircuitBreaker,
          name: 'reset_${circuitBreaker.name}',
          execute: () async {
            // Wait for half-open transition naturally first
            await Future.delayed(const Duration(seconds: 30));
            if (circuitBreaker.state == CircuitState.open) {
              circuitBreaker.reset();
              return true;
            }
            return false;
          },
          cooldown: const Duration(minutes: 2),
          maxAttempts: 5,
        ),
      ],
    ));
  }

  /// Start monitoring
  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(interval, (_) => _checkHealth());
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> _checkHealth() async {
    bool needsRecovery = false;
    RecoveryTrigger? activeTrigger;

    for (final trigger in _triggers) {
      if (trigger.condition()) {
        needsRecovery = true;
        activeTrigger = trigger;
        break;
      }
    }

    if (needsRecovery && activeTrigger != null) {
      await _handleUnhealthyState(activeTrigger);
    } else if (_currentState != HealthState.healthy) {
      _transitionTo(HealthState.healthy);
      _recoveryAttempts = 0;
      _unhealthySince = null;

      // Reset all actions
      for (final trigger in _triggers) {
        for (final action in trigger.actions) {
          action.reset();
        }
      }
    }
  }

  Future<void> _handleUnhealthyState(RecoveryTrigger trigger) async {
    if (_currentState == HealthState.healthy) {
      _transitionTo(HealthState.unhealthy);
      _unhealthySince = DateTime.now();
    }

    // Try recovery actions
    _transitionTo(HealthState.recovering);

    for (final action in trigger.actions) {
      if (action.canExecute) {
        _logger.info('Attempting recovery: ${action.name}');
        _recoveryAttempts++;

        MetricsCollector.instance.increment(
          'recovery_attempt',
          labels: MetricLabels()
              .add('service', serviceName)
              .add('action', action.name),
        );

        try {
          final success = await action.tryExecute();
          onRecoveryAttempt?.call(action, success);

          if (success) {
            _logger.info('Recovery successful: ${action.name}');
            MetricsCollector.instance.increment(
              'recovery_success',
              labels: MetricLabels()
                  .add('service', serviceName)
                  .add('action', action.name),
            );
            return;
          } else {
            _logger.warning('Recovery action returned false: ${action.name}');
          }
        } catch (e, stack) {
          _logger.error('Recovery failed: ${action.name}', error: e, stackTrace: stack);
          MetricsCollector.instance.increment(
            'recovery_failure',
            labels: MetricLabels()
                .add('service', serviceName)
                .add('action', action.name),
          );
        }
      }
    }

    // All recovery attempts exhausted or on cooldown
    _transitionTo(HealthState.degraded);
  }

  void _transitionTo(HealthState newState) {
    if (_currentState == newState) return;
    final oldState = _currentState;
    _currentState = newState;
    _logger.info('State transition: ${oldState.name} -> ${newState.name}');
    onStateChange?.call(oldState, newState);

    MetricsCollector.instance.setGauge(
      'service_health_state',
      newState.index.toDouble(),
      labels: MetricLabels().add('service', serviceName),
    );
  }

  /// Force a recovery attempt
  Future<bool> forceRecovery() async {
    _logger.info('Forced recovery initiated');
    for (final trigger in _triggers) {
      for (final action in trigger.actions) {
        action.reset();
        try {
          final success = await action.tryExecute();
          if (success) {
            _transitionTo(HealthState.healthy);
            return true;
          }
        } catch (e, stack) {
          // tryExecute() propagates exceptions thrown by the underlying
          // action.execute() — catch them here to prevent one failing
          // action from aborting the entire forced-recovery loop.
          _logger.error('Forced recovery action failed: ${action.name}',
              error: e, stackTrace: stack);
        }
      }
    }
    return false;
  }

  Map<String, dynamic> getStatus() => {
        'serviceName': serviceName,
        'currentState': _currentState.name,
        'recoveryAttempts': _recoveryAttempts,
        'unhealthySince': _unhealthySince?.toIso8601String(),
        'triggers': _triggers
            .map((t) => {
                  'name': t.name,
                  'isTriggered': t.condition(),
                  'actions': t.actions.map((a) => a.getStatus()).toList(),
                })
            .toList(),
      };

  void dispose() => stopMonitoring();
}

/// Pre-built recovery strategies
class RecoveryStrategies {
  /// Exponential backoff reconnection
  static RecoveryAction exponentialReconnect({
    required String name,
    required Future<bool> Function() connectFn,
    Duration initialDelay = const Duration(seconds: 1),
    Duration maxDelay = const Duration(minutes: 5),
  }) {
    var currentDelay = initialDelay;

    return RecoveryAction(
      type: RecoveryActionType.reconnectDatabase,
      name: name,
      execute: () async {
        await Future.delayed(currentDelay);
        final success = await connectFn();
        if (!success) {
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * 2)
                .clamp(0, maxDelay.inMilliseconds),
          );
        } else {
          currentDelay = initialDelay;
        }
        return success;
      },
      cooldown: Duration.zero, // Managed internally
      maxAttempts: 10,
    );
  }

  /// Cache clear and warmup
  static RecoveryAction cacheRecovery({
    required Future<void> Function() clearFn,
    Future<void> Function()? warmupFn,
  }) {
    return RecoveryAction(
      type: RecoveryActionType.clearCache,
      name: 'cache_recovery',
      execute: () async {
        await clearFn();
        if (warmupFn != null) {
          await warmupFn();
        }
        return true;
      },
      cooldown: const Duration(minutes: 10),
      maxAttempts: 3,
    );
  }

  /// Gradual load shedding
  static RecoveryAction loadShedding({
    required void Function(double factor) setLoadFactor,
    double targetFactor = 0.5,
    Duration rampDuration = const Duration(minutes: 5),
  }) {
    return RecoveryAction(
      type: RecoveryActionType.scaleDown,
      name: 'load_shedding',
      execute: () async {
        // Gradually reduce load
        for (var factor = 1.0; factor >= targetFactor; factor -= 0.1) {
          setLoadFactor(factor);
          await Future.delayed(rampDuration ~/ 10);
        }
        return true;
      },
      cooldown: const Duration(minutes: 15),
      maxAttempts: 2,
    );
  }
}

/// Global auto recovery registry
class AutoRecoveryRegistry {
  static final AutoRecoveryRegistry _instance = AutoRecoveryRegistry._();
  static AutoRecoveryRegistry get instance => _instance;

  AutoRecoveryRegistry._();

  final Map<String, AutoRecoveryManager> _managers = {};

  AutoRecoveryManager getOrCreate(String serviceName) {
    return _managers.putIfAbsent(
      serviceName,
      () => AutoRecoveryManager(serviceName: serviceName),
    );
  }

  Map<String, dynamic> getAllStatus() =>
      _managers.map((k, v) => MapEntry(k, v.getStatus()));

  void startAllMonitoring() {
    for (final manager in _managers.values) {
      manager.startMonitoring();
    }
  }

  void stopAllMonitoring() {
    for (final manager in _managers.values) {
      manager.stopMonitoring();
    }
  }

  void dispose() {
    for (final manager in _managers.values) {
      manager.dispose();
    }
    _managers.clear();
  }
}
