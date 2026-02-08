import 'dart:async';

/// Health status enum
enum HealthStatus {
  healthy,
  degraded,
  unhealthy,
}

/// Individual component health result
class ComponentHealth {
  final String name;
  final HealthStatus status;
  final String? message;
  final Duration? latency;
  final Map<String, dynamic>? details;

  ComponentHealth({
    required this.name,
    required this.status,
    this.message,
    this.latency,
    this.details,
  });

  bool get isHealthy => status == HealthStatus.healthy;
  bool get isDegraded => status == HealthStatus.degraded;
  bool get isUnhealthy => status == HealthStatus.unhealthy;

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status.name,
        if (message != null) 'message': message,
        if (latency != null) 'latencyMs': latency!.inMilliseconds,
        if (details != null) 'details': details,
      };
}

/// Health check function signature
typedef HealthChecker = Future<ComponentHealth> Function();

/// Overall system health aggregation
class SystemHealth {
  final HealthStatus status;
  final List<ComponentHealth> components;
  final DateTime checkedAt;
  final Duration totalLatency;

  SystemHealth({
    required this.status,
    required this.components,
    required this.checkedAt,
    required this.totalLatency,
  });

  bool get isHealthy => status == HealthStatus.healthy;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'checkedAt': checkedAt.toIso8601String(),
        'totalLatencyMs': totalLatency.inMilliseconds,
        'components': components.map((c) => c.toJson()).toList(),
      };
}

/// Health check registry and executor
class HealthCheckRegistry {
  static final HealthCheckRegistry _instance = HealthCheckRegistry._();
  static HealthCheckRegistry get instance => _instance;

  HealthCheckRegistry._();

  final Map<String, HealthChecker> _checkers = {};
  final Duration _defaultTimeout = const Duration(seconds: 5);

  /// Register a health checker
  void register(String name, HealthChecker checker) {
    _checkers[name] = checker;
  }

  /// Unregister a health checker
  void unregister(String name) {
    _checkers.remove(name);
  }

  /// Run all health checks
  Future<SystemHealth> checkAll({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? _defaultTimeout;
    final startTime = DateTime.now();
    final results = <ComponentHealth>[];

    for (final entry in _checkers.entries) {
      try {
        final result = await entry.value().timeout(
              effectiveTimeout,
              onTimeout: () => ComponentHealth(
                name: entry.key,
                status: HealthStatus.unhealthy,
                message: 'Health check timed out',
              ),
            );
        results.add(result);
      } catch (e) {
        results.add(ComponentHealth(
          name: entry.key,
          status: HealthStatus.unhealthy,
          message: 'Health check failed: $e',
        ));
      }
    }

    final totalLatency = DateTime.now().difference(startTime);
    final overallStatus = _aggregateStatus(results);

    return SystemHealth(
      status: overallStatus,
      components: results,
      checkedAt: startTime,
      totalLatency: totalLatency,
    );
  }

  /// Check a single component
  Future<ComponentHealth> check(String name, {Duration? timeout}) async {
    final checker = _checkers[name];
    if (checker == null) {
      return ComponentHealth(
        name: name,
        status: HealthStatus.unhealthy,
        message: 'Component not registered',
      );
    }

    final effectiveTimeout = timeout ?? _defaultTimeout;
    try {
      return await checker().timeout(
        effectiveTimeout,
        onTimeout: () => ComponentHealth(
          name: name,
          status: HealthStatus.unhealthy,
          message: 'Health check timed out',
        ),
      );
    } catch (e) {
      return ComponentHealth(
        name: name,
        status: HealthStatus.unhealthy,
        message: 'Health check failed: $e',
      );
    }
  }

  /// Aggregate component statuses into overall status
  HealthStatus _aggregateStatus(List<ComponentHealth> results) {
    if (results.isEmpty) return HealthStatus.healthy;

    final hasUnhealthy = results.any((r) => r.isUnhealthy);
    final hasDegraded = results.any((r) => r.isDegraded);

    if (hasUnhealthy) return HealthStatus.unhealthy;
    if (hasDegraded) return HealthStatus.degraded;
    return HealthStatus.healthy;
  }

  /// Get registered component names
  List<String> get registeredComponents => _checkers.keys.toList();

  /// Clear all registered checkers
  void clear() => _checkers.clear();
}

/// Common health check builders
class HealthCheckers {
  /// Create a simple ping-style health check
  static HealthChecker ping(String name, Future<bool> Function() pingFn) {
    return () async {
      final sw = Stopwatch()..start();
      try {
        final ok = await pingFn();
        sw.stop();
        return ComponentHealth(
          name: name,
          status: ok ? HealthStatus.healthy : HealthStatus.unhealthy,
          latency: sw.elapsed,
        );
      } catch (e) {
        sw.stop();
        return ComponentHealth(
          name: name,
          status: HealthStatus.unhealthy,
          message: e.toString(),
          latency: sw.elapsed,
        );
      }
    };
  }

  /// Create a threshold-based health check
  static HealthChecker threshold(
    String name,
    Future<double> Function() valueFn, {
    double? warnThreshold,
    double? criticalThreshold,
    bool higherIsBetter = false,
  }) {
    return () async {
      final sw = Stopwatch()..start();
      try {
        final value = await valueFn();
        sw.stop();

        HealthStatus status = HealthStatus.healthy;
        String? message;

        if (criticalThreshold != null) {
          final isCritical = higherIsBetter
              ? value < criticalThreshold
              : value > criticalThreshold;
          if (isCritical) {
            status = HealthStatus.unhealthy;
            message = 'Value $value crossed critical threshold $criticalThreshold';
          }
        }

        if (status == HealthStatus.healthy && warnThreshold != null) {
          final isWarn = higherIsBetter
              ? value < warnThreshold
              : value > warnThreshold;
          if (isWarn) {
            status = HealthStatus.degraded;
            message = 'Value $value crossed warning threshold $warnThreshold';
          }
        }

        return ComponentHealth(
          name: name,
          status: status,
          message: message,
          latency: sw.elapsed,
          details: {'value': value},
        );
      } catch (e) {
        sw.stop();
        return ComponentHealth(
          name: name,
          status: HealthStatus.unhealthy,
          message: e.toString(),
          latency: sw.elapsed,
        );
      }
    };
  }

  /// Create a circuit breaker health check
  static HealthChecker circuitBreaker(
    String name,
    Map<String, dynamic>? Function() statusFn,
  ) {
    return () async {
      final status = statusFn();
      if (status == null) {
        return ComponentHealth(
          name: name,
          status: HealthStatus.healthy,
          message: 'Circuit breaker not configured',
        );
      }

      final state = status['state'] as String?;
      HealthStatus health;
      switch (state) {
        case 'closed':
          health = HealthStatus.healthy;
          break;
        case 'halfOpen':
          health = HealthStatus.degraded;
          break;
        case 'open':
          health = HealthStatus.unhealthy;
          break;
        default:
          health = HealthStatus.healthy;
      }

      return ComponentHealth(
        name: name,
        status: health,
        details: status,
      );
    };
  }
}

/// Convenience function to register health checks
void registerHealthCheck(String name, HealthChecker checker) {
  HealthCheckRegistry.instance.register(name, checker);
}

/// Convenience function to run all health checks
Future<SystemHealth> runHealthChecks({Duration? timeout}) {
  return HealthCheckRegistry.instance.checkAll(timeout: timeout);
}
