import 'dart:async';

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';
import '../observability/distributed_tracing.dart';
import 'circuit_breaker.dart';
import 'global_rate_limiter.dart';
import 'retry_budget.dart';
import 'retry_policy.dart';
import 'result.dart';
import 'adaptive_config.dart';
import 'slo_manager.dart';
import 'auto_recovery.dart';

/// Configuration for self-healing service
class SelfHealingServiceConfig {
  final String serviceName;
  final List<SloTarget> sloTargets;
  final bool enableAdaptiveThresholds;
  final bool enableAutoRecovery;
  final bool enableTracing;
  final bool enableMetrics;
  final Duration adaptationInterval;

  const SelfHealingServiceConfig({
    required this.serviceName,
    this.sloTargets = const [],
    this.enableAdaptiveThresholds = true,
    this.enableAutoRecovery = true,
    this.enableTracing = true,
    this.enableMetrics = true,
    this.adaptationInterval = const Duration(seconds: 30),
  });

  /// Preset for AI services
  factory SelfHealingServiceConfig.aiService(String name) {
    return SelfHealingServiceConfig(
      serviceName: name,
      sloTargets: [
        SloTarget.availability(target: 0.995),
        SloTarget.latency(targetMs: 30000), // 30s for AI
        SloTarget.errorRate(target: 0.05), // 5% error rate
      ],
    );
  }

  /// Preset for database services
  factory SelfHealingServiceConfig.database(String name) {
    return SelfHealingServiceConfig(
      serviceName: name,
      sloTargets: [
        SloTarget.availability(target: 0.9999),
        SloTarget.latency(targetMs: 100),
        SloTarget.errorRate(target: 0.001),
      ],
    );
  }

  /// Preset for scraping services
  factory SelfHealingServiceConfig.scraper(String name) {
    return SelfHealingServiceConfig(
      serviceName: name,
      sloTargets: [
        SloTarget.availability(target: 0.99),
        SloTarget.latency(targetMs: 10000),
        SloTarget.errorRate(target: 0.1), // Scrapers can have higher error rates
      ],
    );
  }
}

/// Self-healing service base with adaptive resilience
abstract class SelfHealingService {
  final SelfHealingServiceConfig config;
  late final ModuleLogger _logger;

  // Core components
  late final CircuitBreaker _circuitBreaker;
  late final GlobalRateLimiter _rateLimiter;
  late final RetryBudget _retryBudget;
  late final RetryExecutor _retryExecutor;

  // Advanced components
  late final AdaptiveThresholdController _adaptiveController;
  late final SloManager _sloManager;
  late final AutoRecoveryManager _recoveryManager;
  late final FailureStormDetector _stormDetector;

  bool _initialized = false;
  Timer? _metricsTimer;

  SelfHealingService(this.config) {
    _initialize();
  }

  void _initialize() {
    if (_initialized) return;

    _logger = AppLogger.instance.module(config.serviceName);

    // Initialize adaptive controller first
    if (config.enableAdaptiveThresholds) {
      _adaptiveController = AdaptiveConfigRegistry.instance
          .getOrCreateController(config.serviceName);
    }

    // Initialize core components with adaptive config
    _circuitBreaker = CircuitBreakerRegistry.instance.getOrCreate(
      config.serviceName,
      config: config.enableAdaptiveThresholds
          ? _adaptiveController.getCircuitBreakerConfig()
          : const CircuitBreakerConfig(),
    );

    _rateLimiter = GlobalRateLimiterRegistry.instance.getOrCreate(
      config.serviceName,
      config: config.enableAdaptiveThresholds
          ? _adaptiveController.getRateLimiterConfig()
          : const RateLimiterConfig(),
    );

    _retryBudget = RetryBudgetRegistry.instance.getOrCreate(config.serviceName);

    _retryExecutor = RetryExecutor(
      config: config.enableAdaptiveThresholds
          ? _adaptiveController.getRetryConfig()
          : const RetryConfig(),
    );

    // Initialize SLO manager
    _sloManager = SloRegistry.instance.getOrCreate(
      config.serviceName,
      targets: config.sloTargets.isEmpty
          ? [
              SloTarget.availability(),
              SloTarget.latency(),
              SloTarget.errorRate(),
            ]
          : config.sloTargets,
      onPolicyChange: _onDegradationPolicyChange,
    );

    // Initialize auto recovery
    if (config.enableAutoRecovery) {
      _recoveryManager = AutoRecoveryRegistry.instance.getOrCreate(config.serviceName);
      _recoveryManager.addCircuitBreakerRecovery(_circuitBreaker);
      _setupCustomRecoveryActions();
      _recoveryManager.startMonitoring();
    }

    // Initialize storm detector
    _stormDetector = AdaptiveConfigRegistry.instance.getOrCreateStormDetector(
      '${config.serviceName}_storms',
      onStormDetected: _onFailureStormDetected,
      onStormCleared: _onFailureStormCleared,
    );

    // Start metrics collection
    if (config.enableMetrics) {
      _startMetricsCollection();
    }

    _initialized = true;
  }

  /// Override to add custom recovery actions
  void _setupCustomRecoveryActions() {}

  void _onDegradationPolicyChange(DegradationPolicy policy) {
    _logger.warning('Degradation policy changed: ${policy.level.name}');

    // Adjust rate limit based on policy
    // This would require re-creating the rate limiter with new config
    // For now, we just log it
    MetricsCollector.instance.setGauge(
      'degradation_level',
      policy.level.index.toDouble(),
      labels: MetricLabels().add('service', config.serviceName),
    );
  }

  void _onFailureStormDetected() {
    _logger.error('Failure storm detected - activating protective measures');

    // Force circuit breaker open during storm
    _circuitBreaker.forceOpen();

    MetricsCollector.instance.increment(
      'failure_storm_protection_activated',
      labels: MetricLabels().add('service', config.serviceName),
    );
  }

  void _onFailureStormCleared() {
    _logger.info('Failure storm cleared - resuming normal operations');

    // Don't automatically reset circuit breaker - let it recover naturally
    MetricsCollector.instance.increment(
      'failure_storm_cleared',
      labels: MetricLabels().add('service', config.serviceName),
    );
  }

  void _startMetricsCollection() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _collectAndReportMetrics();
    });
  }

  void _collectAndReportMetrics() {
    // Collect current metrics for adaptive tuning
    final cbStatus = _circuitBreaker.getStatus();
    final rlStats = _rateLimiter.getStats();

    final errorRate = (cbStatus['failures'] as int?) ?? 0;
    final total = (cbStatus['total'] as int?) ?? 1;
    final errorRatePercent = total > 0 ? errorRate / total : 0.0;

    if (config.enableAdaptiveThresholds) {
      _adaptiveController.recordMetrics(
        errorRate: errorRatePercent,
        latencyMs: 0, // Would need to track this separately
        requestsPerSecond: (rlStats['currentQps'] as double?) ?? 0,
      );
    }
  }

  /// Execute operation with full self-healing resilience
  Future<Result<T>> execute<T>(
    Future<T> Function() operation, {
    required String operationName,
    bool allowRetry = true,
    Future<T> Function()? fallback,
    Map<String, dynamic>? attributes,
  }) async {
    final fullOpName = '${config.serviceName}.$operationName';
    final stopwatch = Stopwatch()..start();

    // Check SLO-driven degradation
    if (!_sloManager.isFeatureAllowed(operationName)) {
      _logger.warning('Operation disabled by degradation policy: $operationName');
      if (fallback != null) {
        final result = await fallback();
        return Result.success(result);
      }
      return Result.failure(Failure(
        message: 'Operation disabled due to error budget exhaustion',
        code: 'DEGRADED',
      ));
    }

    // Check for failure storm
    if (_stormDetector.isInStorm) {
      _logger.warning('Rejecting during failure storm: $operationName');
      if (fallback != null) {
        final result = await fallback();
        return Result.success(result);
      }
      return Result.failure(Failure(
        message: 'Service in failure storm protection mode',
        code: 'STORM_PROTECTION',
      ));
    }

    // Execute with tracing if enabled
    if (config.enableTracing) {
      return Tracer.instance.trace(
        fullOpName,
        (span) async {
          span.setAttributes(attributes ?? {});
          return _executeWithResilience(
            operation,
            operationName: operationName,
            allowRetry: allowRetry,
            fallback: fallback,
            stopwatch: stopwatch,
            span: span,
          );
        },
        attributes: attributes,
      );
    }

    return _executeWithResilience(
      operation,
      operationName: operationName,
      allowRetry: allowRetry,
      fallback: fallback,
      stopwatch: stopwatch,
    );
  }

  Future<Result<T>> _executeWithResilience<T>(
    Future<T> Function() operation, {
    required String operationName,
    required bool allowRetry,
    required Stopwatch stopwatch,
    Future<T> Function()? fallback,
    Span? span,
  }) async {
    final fullOpName = '${config.serviceName}.$operationName';

    try {
      // Rate limiting
      return await _rateLimiter.execute(() async {
        // Circuit breaker check
        if (!_circuitBreaker.allowRequest()) {
          span?.addEvent('circuit_breaker_rejected');
          _logger.warning('Circuit open: $fullOpName');
          _recordOutcome(false, stopwatch.elapsed);

          if (fallback != null) {
            span?.addEvent('executing_fallback', {'reason': 'circuit_open'});
            final result = await fallback();
            return Result.success(result);
          }

          return Result.failure(Failure(
            message: 'Circuit breaker open',
            code: 'CIRCUIT_OPEN',
          ));
        }

        _retryBudget.recordRequest();

        try {
          T result;

          if (allowRetry) {
            final retryResult = await _retryExecutor.execute(
              operation,
              operationName: fullOpName,
              retryIf: (e) => _shouldRetry(e, span),
            );
            result = retryResult.getOrThrow();
          } else {
            result = await operation();
          }

          _circuitBreaker.recordSuccess();
          _recordOutcome(true, stopwatch.elapsed);
          span?.setAttribute('success', true);

          return Result.success(result);
        } catch (e, stack) {
          _circuitBreaker.recordFailure();
          _stormDetector.recordFailure(
            errorType: e.runtimeType.toString(),
            service: config.serviceName,
          );
          _recordOutcome(false, stopwatch.elapsed);

          span?.setError(e, stack);
          _logger.error('Operation failed: $fullOpName', error: e, stackTrace: stack);

          if (fallback != null) {
            span?.addEvent('executing_fallback', {'reason': 'error'});
            try {
              final result = await fallback();
              return Result.success(result);
            } catch (fallbackError) {
              _logger.error('Fallback failed: $fullOpName', error: fallbackError);
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
      span?.addEvent('rate_limited');
      _recordOutcome(false, stopwatch.elapsed);
      return Result.failure(Failure(
        message: e.message,
        code: 'RATE_LIMITED',
        error: e,
      ));
    }
  }

  bool _shouldRetry(Object error, Span? span) {
    if (!isRetryableError(error)) return false;

    final canRetry = _retryBudget.tryAcquireRetryPermit();
    if (canRetry) {
      span?.addEvent('retry_scheduled', {'error': error.toString()});
    } else {
      span?.addEvent('retry_budget_exhausted');
    }
    return canRetry;
  }

  void _recordOutcome(bool success, Duration duration) {
    _sloManager.recordRequest(success: success, latency: duration);

    if (config.enableMetrics) {
      MetricsCollector.instance.recordRequest(
        service: config.serviceName,
        operation: 'execute',
        success: success,
        duration: duration,
      );
    }
  }

  /// Override to define retryable errors
  bool isRetryableError(Object error);

  /// Get comprehensive service status
  Map<String, dynamic> getStatus() => {
        'service': config.serviceName,
        'circuitBreaker': _circuitBreaker.getStatus(),
        'rateLimiter': _rateLimiter.getStats(),
        'retryBudget': _retryBudget.getStats(),
        'slo': _sloManager.getStatus(),
        'stormDetector': _stormDetector.getStatus(),
        if (config.enableAutoRecovery) 'recovery': _recoveryManager.getStatus(),
        if (config.enableAdaptiveThresholds)
          'adaptiveConfig': _adaptiveController.getStatus(),
      };

  /// Force recovery attempt
  Future<bool> forceRecovery() async {
    if (!config.enableAutoRecovery) return false;
    return _recoveryManager.forceRecovery();
  }

  /// Reset all components
  void reset() {
    _circuitBreaker.reset();
    _rateLimiter.resetStats();
    _retryBudget.reset();
  }

  /// Dispose resources
  void dispose() {
    _metricsTimer?.cancel();
    if (config.enableAutoRecovery) {
      _recoveryManager.dispose();
    }
    if (config.enableAdaptiveThresholds) {
      _adaptiveController.dispose();
    }
  }

  // Protected accessors for subclasses
  ModuleLogger get logger => _logger;
  CircuitBreaker get circuitBreaker => _circuitBreaker;
  SloManager get sloManager => _sloManager;
  DegradationLevel get degradationLevel => _sloManager.degradationLevel;
}
