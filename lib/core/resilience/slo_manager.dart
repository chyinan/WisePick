import 'dart:async';
import 'dart:math' as math;

import '../observability/metrics_collector.dart';

/// SLO target definition
class SloTarget {
  final String name;
  final double targetValue; // e.g., 0.999 for 99.9%
  final Duration window; // rolling window
  final SloType type;

  const SloTarget({
    required this.name,
    required this.targetValue,
    required this.window,
    required this.type,
  });

  /// Common SLO presets
  static SloTarget availability({
    String name = 'availability',
    double target = 0.999,
    Duration window = const Duration(days: 30),
  }) =>
      SloTarget(name: name, targetValue: target, window: window, type: SloType.availability);

  static SloTarget latency({
    String name = 'latency_p99',
    double targetMs = 500,
    Duration window = const Duration(hours: 1),
  }) =>
      SloTarget(name: name, targetValue: targetMs, window: window, type: SloType.latency);

  static SloTarget errorRate({
    String name = 'error_rate',
    double target = 0.001, // 0.1%
    Duration window = const Duration(hours: 1),
  }) =>
      SloTarget(name: name, targetValue: target, window: window, type: SloType.errorRate);
}

enum SloType { availability, latency, errorRate, throughput }

/// Error budget status
class ErrorBudget {
  final SloTarget slo;
  final int totalRequests;
  final int failedRequests;
  final double currentSli; // Service Level Indicator
  final DateTime windowStart;

  ErrorBudget({
    required this.slo,
    required this.totalRequests,
    required this.failedRequests,
    required this.currentSli,
    required this.windowStart,
  });

  /// Total error budget (allowed failures)
  double get totalBudget {
    switch (slo.type) {
      case SloType.availability:
      case SloType.errorRate:
        return (1 - slo.targetValue) * totalRequests;
      default:
        return slo.targetValue;
    }
  }

  /// Consumed error budget
  double get consumedBudget => failedRequests.toDouble();

  /// Remaining error budget
  double get remainingBudget => math.max(0, totalBudget - consumedBudget);

  /// Budget consumption percentage (0-100+)
  double get consumptionPercent {
    if (totalBudget <= 0) return 0;
    return (consumedBudget / totalBudget) * 100;
  }

  /// Whether budget is exhausted
  bool get isExhausted => remainingBudget <= 0;

  /// Whether budget is at risk (>80% consumed)
  bool get isAtRisk => consumptionPercent >= 80;

  /// Whether SLO is being met
  bool get isMeetingSlo => currentSli >= slo.targetValue;

  /// Time remaining in window
  Duration get windowRemaining {
    final elapsed = DateTime.now().difference(windowStart);
    final remaining = slo.window - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Budget burn rate (consumption per hour)
  double get burnRate {
    final elapsed = DateTime.now().difference(windowStart);
    if (elapsed.inMinutes < 1) return 0;
    return consumedBudget / (elapsed.inMinutes / 60);
  }

  /// Projected budget exhaustion time
  Duration? get projectedExhaustionTime {
    if (burnRate <= 0 || remainingBudget <= 0) return null;
    final hoursRemaining = remainingBudget / burnRate;
    return Duration(minutes: (hoursRemaining * 60).round());
  }

  Map<String, dynamic> toJson() => {
        'slo': slo.name,
        'target': slo.targetValue,
        'currentSli': currentSli,
        'totalRequests': totalRequests,
        'failedRequests': failedRequests,
        'totalBudget': totalBudget,
        'consumedBudget': consumedBudget,
        'remainingBudget': remainingBudget,
        'consumptionPercent': '${consumptionPercent.toStringAsFixed(1)}%',
        'isExhausted': isExhausted,
        'isAtRisk': isAtRisk,
        'isMeetingSlo': isMeetingSlo,
        'burnRate': '${burnRate.toStringAsFixed(2)}/hr',
        if (projectedExhaustionTime != null)
          'projectedExhaustion': '${projectedExhaustionTime!.inMinutes}min',
      };
}

/// Degradation policy based on error budget
enum DegradationLevel {
  normal, // Full functionality
  caution, // Budget at risk - reduce non-critical operations
  warning, // Budget low - disable risky features
  critical, // Budget exhausted - minimal operations only
}

/// SLO-driven degradation policy
class DegradationPolicy {
  final DegradationLevel level;
  final Set<String> disabledFeatures;
  final double rateLimitMultiplier; // 1.0 = normal, 0.5 = 50% rate
  final bool allowRiskyOperations;
  final bool enableAggressiveCaching;
  final String message;

  const DegradationPolicy({
    required this.level,
    this.disabledFeatures = const {},
    this.rateLimitMultiplier = 1.0,
    this.allowRiskyOperations = true,
    this.enableAggressiveCaching = false,
    this.message = '',
  });

  static DegradationPolicy fromBudget(ErrorBudget budget) {
    if (budget.isExhausted) {
      return DegradationPolicy(
        level: DegradationLevel.critical,
        disabledFeatures: {'non_essential', 'analytics', 'recommendations'},
        rateLimitMultiplier: 0.25,
        allowRiskyOperations: false,
        enableAggressiveCaching: true,
        message: 'Error budget exhausted - critical mode',
      );
    } else if (budget.consumptionPercent >= 90) {
      return DegradationPolicy(
        level: DegradationLevel.warning,
        disabledFeatures: {'recommendations', 'analytics'},
        rateLimitMultiplier: 0.5,
        allowRiskyOperations: false,
        enableAggressiveCaching: true,
        message: 'Error budget critical - reduced functionality',
      );
    } else if (budget.isAtRisk) {
      return DegradationPolicy(
        level: DegradationLevel.caution,
        disabledFeatures: {'analytics'},
        rateLimitMultiplier: 0.75,
        allowRiskyOperations: true,
        enableAggressiveCaching: false,
        message: 'Error budget at risk - caution mode',
      );
    }

    return const DegradationPolicy(
      level: DegradationLevel.normal,
      message: 'Operating normally',
    );
  }

  bool isFeatureEnabled(String feature) => !disabledFeatures.contains(feature);

  Map<String, dynamic> toJson() => {
        'level': level.name,
        'disabledFeatures': disabledFeatures.toList(),
        'rateLimitMultiplier': rateLimitMultiplier,
        'allowRiskyOperations': allowRiskyOperations,
        'enableAggressiveCaching': enableAggressiveCaching,
        'message': message,
      };
}

/// SLO Manager - tracks SLOs and manages error budgets
class SloManager {
  final String serviceName;
  final List<SloTarget> targets;
  final Duration checkInterval;

  final Map<String, _SloTracker> _trackers = {};
  Timer? _checkTimer;
  DegradationPolicy _currentPolicy = const DegradationPolicy(
    level: DegradationLevel.normal,
    message: 'Initializing',
  );

  final void Function(DegradationPolicy)? onPolicyChange;
  final void Function(String sloName, ErrorBudget budget)? onBudgetAlert;

  SloManager({
    required this.serviceName,
    required this.targets,
    this.checkInterval = const Duration(seconds: 30),
    this.onPolicyChange,
    this.onBudgetAlert,
  }) {
    for (final target in targets) {
      _trackers[target.name] = _SloTracker(target);
    }
    _startChecking();
  }

  DegradationPolicy get currentPolicy => _currentPolicy;
  DegradationLevel get degradationLevel => _currentPolicy.level;

  /// Record a request outcome
  void recordRequest({
    required bool success,
    Duration? latency,
    String? sloName,
  }) {
    // Record to specific SLO or all relevant ones
    for (final tracker in _trackers.values) {
      if (sloName != null && tracker.target.name != sloName) continue;

      switch (tracker.target.type) {
        case SloType.availability:
        case SloType.errorRate:
          tracker.recordOutcome(success);
          break;
        case SloType.latency:
          if (latency != null) {
            tracker.recordLatency(latency.inMilliseconds.toDouble());
          }
          break;
        case SloType.throughput:
          tracker.recordOutcome(true);
          break;
      }
    }
  }

  void _startChecking() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(checkInterval, (_) => _checkBudgets());
  }

  void _checkBudgets() {
    DegradationLevel worstLevel = DegradationLevel.normal;
    ErrorBudget? worstBudget;

    for (final tracker in _trackers.values) {
      final budget = tracker.getErrorBudget();

      // Record metrics
      MetricsCollector.instance.setGauge(
        'slo_budget_remaining',
        budget.remainingBudget,
        labels: MetricLabels().add('slo', tracker.target.name),
      );

      // Check for alerts
      if (budget.isAtRisk) {
        onBudgetAlert?.call(tracker.target.name, budget);
      }

      // Track worst degradation level
      final policy = DegradationPolicy.fromBudget(budget);
      if (policy.level.index > worstLevel.index) {
        worstLevel = policy.level;
        worstBudget = budget;
      }
    }

    // Update policy if changed
    if (worstBudget != null) {
      final newPolicy = DegradationPolicy.fromBudget(worstBudget);
      if (newPolicy.level != _currentPolicy.level) {
        _currentPolicy = newPolicy;
        onPolicyChange?.call(newPolicy);
      }
    }
  }

  /// Get error budget for specific SLO
  ErrorBudget? getBudget(String sloName) => _trackers[sloName]?.getErrorBudget();

  /// Get all error budgets
  Map<String, ErrorBudget> getAllBudgets() =>
      _trackers.map((name, tracker) => MapEntry(name, tracker.getErrorBudget()));

  /// Check if feature is allowed under current policy
  bool isFeatureAllowed(String feature) => _currentPolicy.isFeatureEnabled(feature);

  /// Get effective rate limit multiplier
  double get rateLimitMultiplier => _currentPolicy.rateLimitMultiplier;

  Map<String, dynamic> getStatus() => {
        'serviceName': serviceName,
        'currentPolicy': _currentPolicy.toJson(),
        'budgets': getAllBudgets().map((k, v) => MapEntry(k, v.toJson())),
      };

  void dispose() => _checkTimer?.cancel();
}

/// Internal SLO tracker
class _SloTracker {
  final SloTarget target;
  final List<_RequestRecord> _records = [];

  /// Maximum number of records to retain.
  /// Prevents unbounded memory growth for long-window SLOs (e.g. 30-day availability).
  /// The SLI calculation remains accurate over the retained sample.
  static const int _maxRecords = 50000;

  _SloTracker(this.target);

  void recordOutcome(bool success) {
    _cleanup();
    _records.add(_RequestRecord(
      timestamp: DateTime.now(),
      success: success,
    ));
  }

  void recordLatency(double latencyMs) {
    _cleanup();
    _records.add(_RequestRecord(
      timestamp: DateTime.now(),
      success: latencyMs <= target.targetValue,
      latencyMs: latencyMs,
    ));
  }

  void _cleanup() {
    final cutoff = DateTime.now().subtract(target.window);
    _records.removeWhere((r) => r.timestamp.isBefore(cutoff));

    // If still over cap after time-based pruning, drop oldest records
    if (_records.length > _maxRecords) {
      _records.removeRange(0, _records.length - _maxRecords);
    }
  }

  ErrorBudget getErrorBudget() {
    _cleanup();

    final total = _records.length;
    final failed = _records.where((r) => !r.success).length;
    final sli = total > 0 ? (total - failed) / total : 1.0;

    final windowStart = _records.isNotEmpty
        ? _records.first.timestamp
        : DateTime.now().subtract(target.window);

    return ErrorBudget(
      slo: target,
      totalRequests: total,
      failedRequests: failed,
      currentSli: sli,
      windowStart: windowStart,
    );
  }
}

class _RequestRecord {
  final DateTime timestamp;
  final bool success;
  final double? latencyMs;

  _RequestRecord({
    required this.timestamp,
    required this.success,
    this.latencyMs,
  });
}

/// Global SLO registry
class SloRegistry {
  static final SloRegistry _instance = SloRegistry._();
  static SloRegistry get instance => _instance;

  SloRegistry._();

  final Map<String, SloManager> _managers = {};

  SloManager getOrCreate(
    String serviceName, {
    List<SloTarget>? targets,
    void Function(DegradationPolicy)? onPolicyChange,
  }) {
    return _managers.putIfAbsent(
      serviceName,
      () => SloManager(
        serviceName: serviceName,
        targets: targets ??
            [
              SloTarget.availability(),
              SloTarget.latency(),
              SloTarget.errorRate(),
            ],
        onPolicyChange: onPolicyChange,
      ),
    );
  }

  Map<String, dynamic> getAllStatus() =>
      _managers.map((k, v) => MapEntry(k, v.getStatus()));

  void dispose() {
    for (final manager in _managers.values) {
      manager.dispose();
    }
  }
}
