import 'dart:async';
import 'dart:math' as math;

import '../observability/metrics_collector.dart';
import 'circuit_breaker.dart';
import 'global_rate_limiter.dart';
import 'retry_policy.dart';

/// Configuration bounds for adaptive tuning
class AdaptiveBounds {
  final double minValue;
  final double maxValue;
  final double stepSize;

  const AdaptiveBounds({
    required this.minValue,
    required this.maxValue,
    this.stepSize = 0.1,
  });

  double clamp(double value) => value.clamp(minValue, maxValue);
}

/// Metrics window for analysis
class MetricsWindow {
  final Duration windowSize;
  final List<_MetricPoint> _points = [];

  MetricsWindow({this.windowSize = const Duration(minutes: 5)});

  void record(double value) {
    _cleanup();
    _points.add(_MetricPoint(DateTime.now(), value));
  }

  void _cleanup() {
    final cutoff = DateTime.now().subtract(windowSize);
    _points.removeWhere((p) => p.timestamp.isBefore(cutoff));
  }

  double get mean {
    if (_points.isEmpty) return 0;
    return _points.map((p) => p.value).reduce((a, b) => a + b) / _points.length;
  }

  double get max => _points.isEmpty ? 0 : _points.map((p) => p.value).reduce(math.max);
  double get min => _points.isEmpty ? 0 : _points.map((p) => p.value).reduce(math.min);

  double get stdDev {
    if (_points.length < 2) return 0;
    final avg = mean;
    final sumSq = _points.map((p) => math.pow(p.value - avg, 2)).reduce((a, b) => a + b);
    return math.sqrt(sumSq / _points.length);
  }

  double percentile(double p) {
    if (_points.isEmpty) return 0;
    final sorted = _points.map((pt) => pt.value).toList()..sort();
    final index = ((sorted.length - 1) * p / 100).floor();
    return sorted[index];
  }

  int get count => _points.length;
  bool get hasData => _points.isNotEmpty;
}

class _MetricPoint {
  final DateTime timestamp;
  final double value;
  _MetricPoint(this.timestamp, this.value);
}

/// Adaptive threshold controller
class AdaptiveThresholdController {
  final String serviceName;
  final MetricsWindow _errorRateWindow = MetricsWindow();
  final MetricsWindow _latencyWindow = MetricsWindow();
  final MetricsWindow _throughputWindow = MetricsWindow();

  // Current adaptive values
  double _currentFailureThreshold = 5;
  double _currentRateLimit = 10;
  double _currentRetryDelay = 1000; // ms

  // Bounds
  final AdaptiveBounds _failureBounds = const AdaptiveBounds(minValue: 2, maxValue: 20);
  final AdaptiveBounds _rateLimitBounds = const AdaptiveBounds(minValue: 1, maxValue: 100);
  final AdaptiveBounds _retryDelayBounds = const AdaptiveBounds(minValue: 100, maxValue: 30000);

  // Tuning parameters
  final double _sensitivity;
  final Duration _adjustmentInterval;
  Timer? _adjustmentTimer;

  AdaptiveThresholdController({
    required this.serviceName,
    double sensitivity = 0.5,
    Duration adjustmentInterval = const Duration(seconds: 30),
  })  : _sensitivity = sensitivity,
        _adjustmentInterval = adjustmentInterval {
    _startAutoTuning();
  }

  /// Record metrics for adaptation
  void recordMetrics({
    required double errorRate,
    required double latencyMs,
    required double requestsPerSecond,
  }) {
    _errorRateWindow.record(errorRate);
    _latencyWindow.record(latencyMs);
    _throughputWindow.record(requestsPerSecond);
  }

  void _startAutoTuning() {
    _adjustmentTimer?.cancel();
    _adjustmentTimer = Timer.periodic(_adjustmentInterval, (_) => _adjustThresholds());
  }

  void _adjustThresholds() {
    if (!_errorRateWindow.hasData) return;

    final errorTrend = _calculateTrend(_errorRateWindow);
    final latencyTrend = _calculateTrend(_latencyWindow);

    // Adaptive logic: if errors increasing, tighten thresholds
    if (errorTrend > 0.1) {
      // Errors increasing - be more conservative
      _currentFailureThreshold = _failureBounds.clamp(
        _currentFailureThreshold * (1 - _sensitivity * 0.2),
      );
      _currentRateLimit = _rateLimitBounds.clamp(
        _currentRateLimit * (1 - _sensitivity * 0.3),
      );
      _currentRetryDelay = _retryDelayBounds.clamp(
        _currentRetryDelay * (1 + _sensitivity * 0.5),
      );
    } else if (errorTrend < -0.1 && latencyTrend < 0) {
      // System healthy - relax constraints
      _currentFailureThreshold = _failureBounds.clamp(
        _currentFailureThreshold * (1 + _sensitivity * 0.1),
      );
      _currentRateLimit = _rateLimitBounds.clamp(
        _currentRateLimit * (1 + _sensitivity * 0.2),
      );
      _currentRetryDelay = _retryDelayBounds.clamp(
        _currentRetryDelay * (1 - _sensitivity * 0.2),
      );
    }

    // Record adaptation event
    MetricsCollector.instance.setGauge(
      'adaptive_failure_threshold',
      _currentFailureThreshold,
      labels: MetricLabels().add('service', serviceName),
    );
  }

  double _calculateTrend(MetricsWindow window) {
    if (window.count < 10) return 0;
    // Simple trend: compare recent vs older values
    final recent = window.percentile(75);
    final older = window.percentile(25);
    // Guard against near-zero divisor to prevent extreme trend amplification
    // from floating-point noise.
    if (older.abs() < 1e-6) return 0;
    // Clamp to prevent wild threshold adjustments from outlier percentiles.
    return ((recent - older) / older).clamp(-10.0, 10.0);
  }

  /// Get current adaptive circuit breaker config
  CircuitBreakerConfig getCircuitBreakerConfig() {
    return CircuitBreakerConfig(
      failureThreshold: _currentFailureThreshold.round(),
      failureRateThreshold: 0.5,
      resetTimeout: Duration(milliseconds: (_currentRetryDelay * 10).round()),
    );
  }

  /// Get current adaptive rate limiter config
  RateLimiterConfig getRateLimiterConfig() {
    return RateLimiterConfig(
      maxRequestsPerSecond: _currentRateLimit.round(),
      maxConcurrentRequests: (_currentRateLimit / 2).round().clamp(1, 50),
    );
  }

  /// Get current adaptive retry config
  RetryConfig getRetryConfig() {
    return RetryConfig(
      maxAttempts: 3,
      initialDelay: Duration(milliseconds: _currentRetryDelay.round()),
      maxDelay: Duration(milliseconds: (_currentRetryDelay * 16).round()),
    );
  }

  Map<String, dynamic> getStatus() => {
        'serviceName': serviceName,
        'currentThresholds': {
          'failureThreshold': _currentFailureThreshold,
          'rateLimit': _currentRateLimit,
          'retryDelayMs': _currentRetryDelay,
        },
        'metrics': {
          'errorRate': _errorRateWindow.mean,
          'latencyP50': _latencyWindow.percentile(50),
          'latencyP95': _latencyWindow.percentile(95),
          'throughput': _throughputWindow.mean,
        },
      };

  void dispose() => _adjustmentTimer?.cancel();
}

/// Failure storm detector
class FailureStormDetector {
  final String name;
  final Duration windowSize;
  final double stormThreshold; // errors per second threshold
  final int consecutiveHighCount; // how many windows to trigger storm

  final List<_FailureEvent> _events = [];
  int _consecutiveHigh = 0;
  bool _isInStorm = false;
  DateTime? _stormStartedAt;

  final void Function()? onStormDetected;
  final void Function()? onStormCleared;

  FailureStormDetector({
    required this.name,
    this.windowSize = const Duration(seconds: 10),
    this.stormThreshold = 10,
    this.consecutiveHighCount = 3,
    this.onStormDetected,
    this.onStormCleared,
  });

  /// Record a failure event
  void recordFailure({String? errorType, String? service}) {
    _cleanup();
    _events.add(_FailureEvent(
      timestamp: DateTime.now(),
      errorType: errorType,
      service: service,
    ));
    _checkForStorm();
  }

  void _cleanup() {
    final cutoff = DateTime.now().subtract(windowSize * 3);
    _events.removeWhere((e) => e.timestamp.isBefore(cutoff));
  }

  void _checkForStorm() {
    final now = DateTime.now();
    final windowStart = now.subtract(windowSize);
    final recentCount = _events.where((e) => e.timestamp.isAfter(windowStart)).length;
    // Use milliseconds to avoid integer truncation to 0 for sub-second windows.
    final windowSec = windowSize.inMilliseconds / 1000.0;
    if (windowSec <= 0) return; // safety: malformed window
    final rate = recentCount / windowSec;

    if (rate >= stormThreshold) {
      _consecutiveHigh++;
      if (_consecutiveHigh >= consecutiveHighCount && !_isInStorm) {
        _isInStorm = true;
        _stormStartedAt = now;
        onStormDetected?.call();
        MetricsCollector.instance.increment(
          'failure_storm_detected',
          labels: MetricLabels().add('detector', name),
        );
      }
    } else {
      if (_consecutiveHigh > 0) _consecutiveHigh--;
      if (_consecutiveHigh == 0 && _isInStorm) {
        _isInStorm = false;
        onStormCleared?.call();
        MetricsCollector.instance.increment(
          'failure_storm_cleared',
          labels: MetricLabels().add('detector', name),
        );
      }
    }
  }

  /// Whether system is currently in a failure storm
  bool get isInStorm => _isInStorm;

  /// Current failure rate per second
  double get currentRate {
    final now = DateTime.now();
    final windowStart = now.subtract(windowSize);
    final count = _events.where((e) => e.timestamp.isAfter(windowStart)).length;
    final windowSec = windowSize.inMilliseconds / 1000.0;
    if (windowSec <= 0) return 0;
    return count / windowSec;
  }

  /// Get failure distribution by type
  Map<String, int> getFailuresByType() {
    final result = <String, int>{};
    for (final event in _events) {
      final type = event.errorType ?? 'unknown';
      result[type] = (result[type] ?? 0) + 1;
    }
    return result;
  }

  Map<String, dynamic> getStatus() => {
        'name': name,
        'isInStorm': _isInStorm,
        'currentRate': currentRate,
        'threshold': stormThreshold,
        'consecutiveHigh': _consecutiveHigh,
        if (_stormStartedAt != null) 'stormDuration': DateTime.now().difference(_stormStartedAt!).inSeconds,
        'failuresByType': getFailuresByType(),
      };
}

class _FailureEvent {
  final DateTime timestamp;
  final String? errorType;
  final String? service;
  _FailureEvent({required this.timestamp, this.errorType, this.service});
}

/// Global adaptive config registry
class AdaptiveConfigRegistry {
  static final AdaptiveConfigRegistry _instance = AdaptiveConfigRegistry._();
  static AdaptiveConfigRegistry get instance => _instance;

  AdaptiveConfigRegistry._();

  final Map<String, AdaptiveThresholdController> _controllers = {};
  final Map<String, FailureStormDetector> _stormDetectors = {};

  AdaptiveThresholdController getOrCreateController(String serviceName) {
    return _controllers.putIfAbsent(
      serviceName,
      () => AdaptiveThresholdController(serviceName: serviceName),
    );
  }

  FailureStormDetector getOrCreateStormDetector(
    String name, {
    void Function()? onStormDetected,
    void Function()? onStormCleared,
  }) {
    return _stormDetectors.putIfAbsent(
      name,
      () => FailureStormDetector(
        name: name,
        onStormDetected: onStormDetected,
        onStormCleared: onStormCleared,
      ),
    );
  }

  Map<String, dynamic> getAllStatus() => {
        'controllers': _controllers.map((k, v) => MapEntry(k, v.getStatus())),
        'stormDetectors': _stormDetectors.map((k, v) => MapEntry(k, v.getStatus())),
      };

  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
  }
}
