import 'dart:async';

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';
import '../observability/health_check.dart';
import 'circuit_breaker.dart';
import 'global_rate_limiter.dart';
import 'retry_budget.dart';
import 'retry_policy.dart';
import 'result.dart';

/// Configuration for resilient service
class ResilientServiceConfig {
  final String serviceName;
  final CircuitBreakerConfig? circuitBreakerConfig;
  final RateLimiterConfig? rateLimiterConfig;
  final RetryBudgetConfig? retryBudgetConfig;
  final RetryConfig? retryConfig;
  final bool enableMetrics;
  final bool enableHealthCheck;

  const ResilientServiceConfig({
    required this.serviceName,
    this.circuitBreakerConfig,
    this.rateLimiterConfig,
    this.retryBudgetConfig,
    this.retryConfig,
    this.enableMetrics = true,
    this.enableHealthCheck = true,
  });
}

/// Base class for services with built-in resilience patterns
abstract class ResilientServiceBase {
  final ResilientServiceConfig config;
  late final ModuleLogger _logger;
  late final CircuitBreaker _circuitBreaker;
  late final GlobalRateLimiter _rateLimiter;
  late final RetryBudget _retryBudget;
  late final RetryExecutor _retryExecutor;
  
  bool _initialized = false;

  ResilientServiceBase(this.config) {
    _initialize();
  }

  void _initialize() {
    if (_initialized) return;
    
    _logger = AppLogger.instance.module(config.serviceName);
    
    _circuitBreaker = CircuitBreakerRegistry.instance.getOrCreate(
      config.serviceName,
      config: config.circuitBreakerConfig ?? const CircuitBreakerConfig(),
    );
    
    _rateLimiter = GlobalRateLimiterRegistry.instance.getOrCreate(
      config.serviceName,
      config: config.rateLimiterConfig ?? const RateLimiterConfig(),
    );
    
    _retryBudget = RetryBudgetRegistry.instance.getOrCreate(
      config.serviceName,
      config: config.retryBudgetConfig ?? const RetryBudgetConfig(),
    );
    
    _retryExecutor = RetryExecutor(
      config: config.retryConfig ?? const RetryConfig(),
    );

    if (config.enableHealthCheck) {
      _registerHealthCheck();
    }

    _initialized = true;
  }

  void _registerHealthCheck() {
    HealthCheckRegistry.instance.register(
      config.serviceName,
      HealthCheckers.circuitBreaker(
        '${config.serviceName}_circuit',
        () => _circuitBreaker.getStatus(),
      ),
    );
  }

  /// Execute an operation with all resilience patterns applied
  Future<Result<T>> executeResilient<T>(
    Future<T> Function() operation, {
    required String operationName,
    bool allowRetry = true,
    Future<T> Function()? fallback,
  }) async {
    final fullOpName = '${config.serviceName}.$operationName';
    final stopwatch = Stopwatch()..start();

    try {
      // Rate limiting
      return await _rateLimiter.execute(() async {
        // Circuit breaker check
        if (!_circuitBreaker.allowRequest()) {
          _logger.warning('Circuit open, rejecting: $fullOpName');
          _recordMetrics(fullOpName, false, stopwatch.elapsed);
          
          if (fallback != null) {
            _logger.info('Executing fallback for: $fullOpName');
            final result = await fallback();
            return Result.success(result);
          }
          
          return Result.failure(Failure(
            message: 'Circuit breaker open for $fullOpName',
            code: 'CIRCUIT_OPEN',
          ));
        }

        // Record request for retry budget
        _retryBudget.recordRequest();

        try {
          T result;
          
          if (allowRetry) {
            // Execute with retry
            final retryResult = await _retryExecutor.execute(
              operation,
              operationName: fullOpName,
              retryIf: (e) => _shouldRetry(e),
            );
            result = retryResult.getOrThrow();
          } else {
            result = await operation();
          }

          _circuitBreaker.recordSuccess();
          _recordMetrics(fullOpName, true, stopwatch.elapsed);
          return Result.success(result);
          
        } catch (e, stack) {
          _circuitBreaker.recordFailure();
          _recordMetrics(fullOpName, false, stopwatch.elapsed);
          _logger.error('Operation failed: $fullOpName', error: e, stackTrace: stack);

          if (fallback != null) {
            _logger.info('Executing fallback after error: $fullOpName');
            try {
              final result = await fallback();
              return Result.success(result);
            } catch (fallbackError) {
              _logger.error('Fallback also failed: $fullOpName', error: fallbackError);
            }
          }

          return Result.failure(Failure(
            message: e.toString(),
            code: 'OPERATION_FAILED',
            error: e,
            stackTrace: stack,
          ));
        }
      }, operationName: fullOpName);
      
    } on RateLimitException catch (e) {
      _recordMetrics(fullOpName, false, stopwatch.elapsed);
      return Result.failure(Failure(
        message: e.message,
        code: 'RATE_LIMITED',
        error: e,
      ));
    }
  }

  /// Check if error is retryable and budget allows
  bool _shouldRetry(Object error) {
    if (!isRetryableError(error)) return false;
    return _retryBudget.tryAcquireRetryPermit();
  }

  /// Override to define which errors are retryable
  bool isRetryableError(Object error);

  void _recordMetrics(String operation, bool success, Duration duration) {
    if (!config.enableMetrics) return;
    
    MetricsCollector.instance.recordRequest(
      service: config.serviceName,
      operation: operation,
      success: success,
      duration: duration,
    );
  }

  /// Get service health status
  Map<String, dynamic> getHealthStatus() {
    return {
      'service': config.serviceName,
      'circuitBreaker': _circuitBreaker.getStatus(),
      'rateLimiter': _rateLimiter.getStats(),
      'retryBudget': _retryBudget.getStats(),
    };
  }

  /// Reset all resilience components
  void reset() {
    _circuitBreaker.reset();
    _rateLimiter.resetStats();
    _retryBudget.reset();
  }

  /// Logger for subclasses
  ModuleLogger get logger => _logger;
  
  /// Circuit breaker for subclasses
  CircuitBreaker get circuitBreaker => _circuitBreaker;
}

/// Mixin for adding resilience to existing services
mixin ResilientOperationsMixin {
  ModuleLogger get resilienceLogger;
  String get serviceName;

  CircuitBreaker? _mixinCircuitBreaker;
  GlobalRateLimiter? _mixinRateLimiter;
  RetryBudget? _mixinRetryBudget;

  CircuitBreaker get mixinCircuitBreaker {
    _mixinCircuitBreaker ??= CircuitBreakerRegistry.instance.getOrCreate(serviceName);
    return _mixinCircuitBreaker!;
  }

  GlobalRateLimiter get mixinRateLimiter {
    _mixinRateLimiter ??= GlobalRateLimiterRegistry.instance.getOrCreate(serviceName);
    return _mixinRateLimiter!;
  }

  RetryBudget get mixinRetryBudget {
    _mixinRetryBudget ??= RetryBudgetRegistry.instance.getOrCreate(serviceName);
    return _mixinRetryBudget!;
  }

  /// Execute with circuit breaker protection
  Future<T> withCircuitBreaker<T>(
    Future<T> Function() operation, {
    Future<T> Function()? fallback,
  }) async {
    return mixinCircuitBreaker.executeWithFallback(
      operation,
      fallback ?? () => throw StateError('No fallback provided'),
    );
  }

  /// Execute with rate limiting
  Future<T> withRateLimiting<T>(
    Future<T> Function() operation, {
    String? operationName,
  }) async {
    return mixinRateLimiter.execute(operation, operationName: operationName);
  }

  /// Check if retry is allowed
  bool canRetryOperation() => mixinRetryBudget.canRetry();

  /// Consume a retry permit
  bool consumeRetryPermit() => mixinRetryBudget.tryAcquireRetryPermit();
}
