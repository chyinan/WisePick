import 'dart:async';

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';
import '../observability/health_check.dart';
import '../resilience/circuit_breaker.dart';
import '../resilience/slo_manager.dart';
import 'predictive_load_manager.dart';
import 'chaos_engineering.dart';

/// 仪表盘数据刷新间隔
enum RefreshInterval {
  realtime(Duration(seconds: 1)),
  fast(Duration(seconds: 5)),
  normal(Duration(seconds: 15)),
  slow(Duration(seconds: 60));

  final Duration duration;
  const RefreshInterval(this.duration);
}

/// 系统总体健康评分
class SystemHealthScore {
  final double overallScore; // 0-100
  final double availabilityScore;
  final double latencyScore;
  final double errorRateScore;
  final double resourceScore;
  final DateTime calculatedAt;
  final HealthGrade grade;
  final List<String> criticalIssues;
  final List<String> warnings;

  const SystemHealthScore({
    required this.overallScore,
    required this.availabilityScore,
    required this.latencyScore,
    required this.errorRateScore,
    required this.resourceScore,
    required this.calculatedAt,
    required this.grade,
    this.criticalIssues = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
        'overallScore': overallScore,
        'grade': grade.name,
        'scores': {
          'availability': availabilityScore,
          'latency': latencyScore,
          'errorRate': errorRateScore,
          'resource': resourceScore,
        },
        'calculatedAt': calculatedAt.toIso8601String(),
        'criticalIssues': criticalIssues,
        'warnings': warnings,
      };
}

enum HealthGrade {
  excellent, // 90-100
  good, // 75-89
  fair, // 60-74
  poor, // 40-59
  critical, // 0-39
}

/// 服务状态摘要
class ServiceStatusSummary {
  final String serviceName;
  final ServiceStatus status;
  final double successRate;
  final Duration avgLatency;
  final Duration p95Latency;
  final Duration p99Latency;
  final int requestsPerMinute;
  final int activeConnections;
  final CircuitState? circuitBreakerState;
  final DegradationLevel? degradationLevel;
  final DateTime lastUpdated;

  const ServiceStatusSummary({
    required this.serviceName,
    required this.status,
    required this.successRate,
    required this.avgLatency,
    required this.p95Latency,
    required this.p99Latency,
    required this.requestsPerMinute,
    required this.activeConnections,
    this.circuitBreakerState,
    this.degradationLevel,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'serviceName': serviceName,
        'status': status.name,
        'successRate': '${(successRate * 100).toStringAsFixed(2)}%',
        'latency': {
          'avg': '${avgLatency.inMilliseconds}ms',
          'p95': '${p95Latency.inMilliseconds}ms',
          'p99': '${p99Latency.inMilliseconds}ms',
        },
        'requestsPerMinute': requestsPerMinute,
        'activeConnections': activeConnections,
        if (circuitBreakerState != null) 'circuitBreaker': circuitBreakerState!.name,
        if (degradationLevel != null) 'degradation': degradationLevel!.name,
        'lastUpdated': lastUpdated.toIso8601String(),
      };
}

enum ServiceStatus {
  healthy,
  degraded,
  unhealthy,
  unknown,
}

/// SLO 状态摘要
class SloStatusSummary {
  final String sloName;
  final double targetValue;
  final double currentValue;
  final double budgetRemaining;
  final double budgetConsumptionRate;
  final Duration estimatedExhaustionTime;
  final bool isAtRisk;
  final bool isViolated;

  const SloStatusSummary({
    required this.sloName,
    required this.targetValue,
    required this.currentValue,
    required this.budgetRemaining,
    required this.budgetConsumptionRate,
    required this.estimatedExhaustionTime,
    required this.isAtRisk,
    required this.isViolated,
  });

  Map<String, dynamic> toJson() => {
        'sloName': sloName,
        'target': targetValue,
        'current': currentValue,
        'budgetRemaining': '${(budgetRemaining * 100).toStringAsFixed(1)}%',
        'burnRate': '${budgetConsumptionRate.toStringAsFixed(2)}/hr',
        'estimatedExhaustion':
            estimatedExhaustionTime.isNegative ? 'N/A' : '${estimatedExhaustionTime.inMinutes}min',
        'isAtRisk': isAtRisk,
        'isViolated': isViolated,
      };
}

/// 告警信息
class ReliabilityAlert {
  final String id;
  final AlertSeverity severity;
  final String title;
  final String description;
  final String source;
  final DateTime timestamp;
  final bool acknowledged;
  final Map<String, dynamic> metadata;

  const ReliabilityAlert({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    required this.source,
    required this.timestamp,
    this.acknowledged = false,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity.name,
        'title': title,
        'description': description,
        'source': source,
        'timestamp': timestamp.toIso8601String(),
        'acknowledged': acknowledged,
        'metadata': metadata,
      };
}

enum AlertSeverity {
  info,
  warning,
  error,
  critical,
}

/// 仪表盘完整快照
class DashboardSnapshot {
  final DateTime timestamp;
  final SystemHealthScore healthScore;
  final List<ServiceStatusSummary> services;
  final List<SloStatusSummary> slos;
  final List<ReliabilityAlert> activeAlerts;
  final Map<String, dynamic> metrics;
  final Map<String, dynamic> predictions;
  final Map<String, dynamic> chaosStatus;

  const DashboardSnapshot({
    required this.timestamp,
    required this.healthScore,
    required this.services,
    required this.slos,
    required this.activeAlerts,
    required this.metrics,
    required this.predictions,
    required this.chaosStatus,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'healthScore': healthScore.toJson(),
        'services': services.map((s) => s.toJson()).toList(),
        'slos': slos.map((s) => s.toJson()).toList(),
        'activeAlerts': activeAlerts.map((a) => a.toJson()).toList(),
        'metrics': metrics,
        'predictions': predictions,
        'chaosStatus': chaosStatus,
      };
}

/// 可靠性仪表盘
class ReliabilityDashboard {
  final ModuleLogger _logger;
  final List<ReliabilityAlert> _alerts = [];
  final Map<String, Set<String>> _acknowledgedAlerts = {};

  Timer? _refreshTimer;
  DashboardSnapshot? _latestSnapshot;
  final StreamController<DashboardSnapshot> _snapshotController =
      StreamController.broadcast();

  // 数据源
  final List<String> _monitoredServices = [];

  // 告警阈值
  final double errorRateAlertThreshold;
  final Duration latencyAlertThreshold;
  final double budgetWarningThreshold;

  ReliabilityDashboard({
    this.errorRateAlertThreshold = 0.05,
    this.latencyAlertThreshold = const Duration(seconds: 5),
    this.budgetWarningThreshold = 0.2,
  }) : _logger = AppLogger.instance.module('ReliabilityDashboard');

  DashboardSnapshot? get latestSnapshot => _latestSnapshot;
  Stream<DashboardSnapshot> get snapshotStream => _snapshotController.stream;
  List<ReliabilityAlert> get activeAlerts =>
      _alerts.where((a) => !a.acknowledged).toList();

  /// 注册监控的服务
  void registerService(String serviceName) {
    if (!_monitoredServices.contains(serviceName)) {
      _monitoredServices.add(serviceName);
      _logger.info('Registered service for monitoring: $serviceName');
    }
  }

  /// 开始自动刷新
  void startAutoRefresh({RefreshInterval interval = RefreshInterval.normal}) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval.duration, (_) => refresh());
    _logger.info('Started auto-refresh at ${interval.name} interval');
  }

  /// 停止自动刷新
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 手动刷新
  Future<DashboardSnapshot> refresh() async {
    final stopwatch = Stopwatch()..start();

    try {
      // 收集所有数据
      final healthScore = await _calculateHealthScore();
      final services = await _collectServiceStatuses();
      final slos = _collectSloStatuses();
      final metrics = _collectMetrics();
      final predictions = _collectPredictions();
      final chaosStatus = _collectChaosStatus();

      // 检查告警条件
      _checkAlertConditions(healthScore, services, slos);

      stopwatch.stop();

      _latestSnapshot = DashboardSnapshot(
        timestamp: DateTime.now(),
        healthScore: healthScore,
        services: services,
        slos: slos,
        activeAlerts: activeAlerts,
        metrics: metrics,
        predictions: predictions,
        chaosStatus: chaosStatus,
      );

      _snapshotController.add(_latestSnapshot!);

      MetricsCollector.instance.observeHistogram(
        'dashboard_refresh_duration_seconds',
        stopwatch.elapsed.inMilliseconds / 1000,
      );

      return _latestSnapshot!;
    } catch (e, stack) {
      _logger.error('Dashboard refresh failed', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<SystemHealthScore> _calculateHealthScore() async {
    final criticalIssues = <String>[];
    final warnings = <String>[];

    // 可用性评分
    double availabilityScore = 100;
    final healthResult = await HealthCheckRegistry.instance.checkAll();
    final unhealthyComponents = healthResult.components
        .where((c) => c.status == HealthStatus.unhealthy)
        .toList();
    final degradedComponents = healthResult.components
        .where((c) => c.status == HealthStatus.degraded)
        .toList();

    availabilityScore -= unhealthyComponents.length * 20;
    availabilityScore -= degradedComponents.length * 10;

    for (final c in unhealthyComponents) {
      criticalIssues.add('${c.name} is unhealthy: ${c.message}');
    }
    for (final c in degradedComponents) {
      warnings.add('${c.name} is degraded: ${c.message}');
    }

    // 延迟评分
    double latencyScore = 100;
    final latencyHist = MetricsCollector.instance.getHistogram(
      MetricsCollector.requestDuration,
    );
    if (latencyHist != null && latencyHist.count > 0) {
      final p99 = latencyHist.p99;
      if (p99 > 10) {
        latencyScore -= 50;
        criticalIssues.add('P99 latency is extremely high: ${p99.toStringAsFixed(2)}s');
      } else if (p99 > 5) {
        latencyScore -= 30;
        warnings.add('P99 latency is high: ${p99.toStringAsFixed(2)}s');
      } else if (p99 > 2) {
        latencyScore -= 15;
      }
    }

    // 错误率评分
    double errorRateScore = 100;
    final summary = MetricsCollector.instance.getSummary();
    final errorRateStr = summary['requests']?['errorRate'] as String? ?? '0%';
    final errorRate =
        (double.tryParse(errorRateStr.replaceAll('%', '')) ?? 0) / 100;

    if (errorRate > 0.1) {
      errorRateScore -= 60;
      criticalIssues.add('Error rate is critical: $errorRateStr');
    } else if (errorRate > 0.05) {
      errorRateScore -= 30;
      warnings.add('Error rate is elevated: $errorRateStr');
    } else if (errorRate > 0.01) {
      errorRateScore -= 10;
    }

    // 资源评分
    double resourceScore = 100;
    final circuitBreakers = CircuitBreakerRegistry.instance.getAllStatus();
    final openBreakers = circuitBreakers.entries
        .where((e) => e.value['state'] == 'open')
        .toList();

    for (final breaker in openBreakers) {
      resourceScore -= 15;
      warnings.add('Circuit breaker ${breaker.key} is open');
    }

    // 计算总分
    final overallScore = (availabilityScore * 0.3 +
            latencyScore * 0.25 +
            errorRateScore * 0.3 +
            resourceScore * 0.15)
        .clamp(0.0, 100.0);

    // 确定等级
    HealthGrade grade;
    if (overallScore >= 90) {
      grade = HealthGrade.excellent;
    } else if (overallScore >= 75) {
      grade = HealthGrade.good;
    } else if (overallScore >= 60) {
      grade = HealthGrade.fair;
    } else if (overallScore >= 40) {
      grade = HealthGrade.poor;
    } else {
      grade = HealthGrade.critical;
    }

    return SystemHealthScore(
      overallScore: overallScore,
      availabilityScore: availabilityScore.clamp(0.0, 100.0),
      latencyScore: latencyScore.clamp(0.0, 100.0),
      errorRateScore: errorRateScore.clamp(0.0, 100.0),
      resourceScore: resourceScore.clamp(0.0, 100.0),
      calculatedAt: DateTime.now(),
      grade: grade,
      criticalIssues: criticalIssues,
      warnings: warnings,
    );
  }

  Future<List<ServiceStatusSummary>> _collectServiceStatuses() async {
    final statuses = <ServiceStatusSummary>[];

    for (final serviceName in _monitoredServices) {
      // 从熔断器获取状态
      final cb = CircuitBreakerRegistry.instance.get(serviceName);
      final cbStatus = cb?.getStatus();

      // 从 SLO 管理器获取数据
      final sloManager = SloRegistry.instance.getOrCreate(serviceName);

      // 计算指标
      final failures = (cbStatus?['failures'] as int?) ?? 0;
      final total = (cbStatus?['total'] as int?) ?? 0;
      final successRate = total > 0 ? (total - failures) / total : 1.0;

      // 从指标收集器获取延迟数据
      final latencyHist = MetricsCollector.instance.getHistogram(
        MetricsCollector.requestDuration,
        labels: MetricLabels().add('service', serviceName),
      );

      statuses.add(ServiceStatusSummary(
        serviceName: serviceName,
        status: _determineServiceStatus(cb, successRate),
        successRate: successRate,
        avgLatency: Duration(
          milliseconds: ((latencyHist?.mean ?? 0) * 1000).round(),
        ),
        p95Latency: Duration(
          milliseconds: ((latencyHist?.p95 ?? 0) * 1000).round(),
        ),
        p99Latency: Duration(
          milliseconds: ((latencyHist?.p99 ?? 0) * 1000).round(),
        ),
        requestsPerMinute: total,
        activeConnections: 0, // Would need connection pool tracking
        circuitBreakerState: cb?.state,
        degradationLevel: sloManager.degradationLevel,
        lastUpdated: DateTime.now(),
      ));
    }

    return statuses;
  }

  ServiceStatus _determineServiceStatus(
    CircuitBreaker? cb,
    double successRate,
  ) {
    if (cb?.state == CircuitState.open) {
      return ServiceStatus.unhealthy;
    }
    if (cb?.state == CircuitState.halfOpen || successRate < 0.95) {
      return ServiceStatus.degraded;
    }
    if (successRate >= 0.99) {
      return ServiceStatus.healthy;
    }
    return ServiceStatus.degraded;
  }

  List<SloStatusSummary> _collectSloStatuses() {
    final sloStatuses = <SloStatusSummary>[];
    final allStatus = SloRegistry.instance.getAllStatus();

    for (final entry in allStatus.entries) {
      final budgets = entry.value['budgets'] as Map<String, dynamic>? ?? {};

      for (final budgetEntry in budgets.entries) {
        final budget = budgetEntry.value as Map<String, dynamic>;

        sloStatuses.add(SloStatusSummary(
          sloName: '${entry.key}:${budgetEntry.key}',
          targetValue: (budget['target'] as num?)?.toDouble() ?? 0,
          currentValue: (budget['currentSli'] as num?)?.toDouble() ?? 0,
          budgetRemaining: (budget['remainingBudget'] as num?)?.toDouble() ?? 0,
          budgetConsumptionRate: _parseBurnRate(budget['burnRate'] as String?),
          estimatedExhaustionTime: _parseExhaustion(budget['projectedExhaustion'] as String?),
          isAtRisk: budget['isAtRisk'] as bool? ?? false,
          isViolated: budget['isExhausted'] as bool? ?? false,
        ));
      }
    }

    return sloStatuses;
  }

  double _parseBurnRate(String? rate) {
    if (rate == null) return 0;
    return double.tryParse(rate.replaceAll('/hr', '')) ?? 0;
  }

  Duration _parseExhaustion(String? time) {
    if (time == null) return const Duration(hours: -1);
    final minutes = int.tryParse(time.replaceAll('min', ''));
    if (minutes == null) return const Duration(hours: -1);
    return Duration(minutes: minutes);
  }

  Map<String, dynamic> _collectMetrics() {
    return MetricsCollector.instance.getAllMetrics();
  }

  Map<String, dynamic> _collectPredictions() {
    final predictions = <String, dynamic>{};

    final loadManagers = PredictiveLoadManagerRegistry.instance.getAllStatus();
    for (final entry in loadManagers.entries) {
      final prediction = entry.value['latestPrediction'];
      final trend = entry.value['latestTrend'];

      predictions[entry.key] = {
        'prediction': prediction,
        'trend': trend,
      };
    }

    return predictions;
  }

  Map<String, dynamic> _collectChaosStatus() {
    return ChaosEngineeringManager.instance.getStatus();
  }

  void _checkAlertConditions(
    SystemHealthScore healthScore,
    List<ServiceStatusSummary> services,
    List<SloStatusSummary> slos,
  ) {
    final now = DateTime.now();

    // 检查健康分数
    if (healthScore.grade == HealthGrade.critical) {
      _addAlert(ReliabilityAlert(
        id: 'health_critical_${now.millisecondsSinceEpoch}',
        severity: AlertSeverity.critical,
        title: 'System Health Critical',
        description: 'Overall system health score is ${healthScore.overallScore.toStringAsFixed(0)}%',
        source: 'health_check',
        timestamp: now,
      ));
    }

    // 检查服务状态
    for (final service in services) {
      if (service.status == ServiceStatus.unhealthy) {
        _addAlert(ReliabilityAlert(
          id: 'service_unhealthy_${service.serviceName}_${now.millisecondsSinceEpoch}',
          severity: AlertSeverity.critical,
          title: 'Service Unhealthy: ${service.serviceName}',
          description: 'Service ${service.serviceName} is unhealthy with ${(service.successRate * 100).toStringAsFixed(1)}% success rate',
          source: 'service_monitor',
          timestamp: now,
          metadata: {'serviceName': service.serviceName},
        ));
      }
    }

    // 检查 SLO
    for (final slo in slos) {
      if (slo.isViolated) {
        _addAlert(ReliabilityAlert(
          id: 'slo_violated_${slo.sloName}_${now.millisecondsSinceEpoch}',
          severity: AlertSeverity.critical,
          title: 'SLO Violated: ${slo.sloName}',
          description: 'Error budget exhausted for ${slo.sloName}',
          source: 'slo_manager',
          timestamp: now,
          metadata: {'sloName': slo.sloName},
        ));
      } else if (slo.isAtRisk) {
        _addAlert(ReliabilityAlert(
          id: 'slo_at_risk_${slo.sloName}_${now.millisecondsSinceEpoch}',
          severity: AlertSeverity.warning,
          title: 'SLO At Risk: ${slo.sloName}',
          description: 'Error budget for ${slo.sloName} is at risk',
          source: 'slo_manager',
          timestamp: now,
          metadata: {'sloName': slo.sloName},
        ));
      }
    }
  }

  void _addAlert(ReliabilityAlert alert) {
    // 避免重复告警 (同一来源的相似告警在5分钟内不重复)
    final recentSimilar = _alerts.any((a) =>
        a.source == alert.source &&
        a.title == alert.title &&
        DateTime.now().difference(a.timestamp).inMinutes < 5);

    if (!recentSimilar) {
      _alerts.add(alert);

      // 保留最近100条告警
      while (_alerts.length > 100) {
        _alerts.removeAt(0);
      }

      MetricsCollector.instance.increment(
        'reliability_alerts_generated',
        labels: MetricLabels()
            .add('severity', alert.severity.name)
            .add('source', alert.source),
      );
    }
  }

  /// 确认告警
  void acknowledgeAlert(String alertId) {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index >= 0) {
      final alert = _alerts[index];
      _alerts[index] = ReliabilityAlert(
        id: alert.id,
        severity: alert.severity,
        title: alert.title,
        description: alert.description,
        source: alert.source,
        timestamp: alert.timestamp,
        acknowledged: true,
        metadata: alert.metadata,
      );
    }
  }

  /// 清除所有已确认的告警
  void clearAcknowledgedAlerts() {
    _alerts.removeWhere((a) => a.acknowledged);
  }

  /// 获取实时指标流
  Stream<Map<String, dynamic>> getMetricsStream({
    Duration interval = const Duration(seconds: 1),
  }) async* {
    while (true) {
      await Future.delayed(interval);
      yield MetricsCollector.instance.getAllMetrics();
    }
  }

  /// 导出仪表盘数据
  Map<String, dynamic> exportData() {
    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'latestSnapshot': _latestSnapshot?.toJson(),
      'alertHistory': _alerts.map((a) => a.toJson()).toList(),
    };
  }

  void dispose() {
    stopAutoRefresh();
    _snapshotController.close();
  }
}

/// 全局仪表盘单例
class ReliabilityDashboardRegistry {
  static final ReliabilityDashboardRegistry _instance =
      ReliabilityDashboardRegistry._();
  static ReliabilityDashboardRegistry get instance => _instance;

  ReliabilityDashboardRegistry._();

  ReliabilityDashboard? _dashboard;

  ReliabilityDashboard get dashboard {
    _dashboard ??= ReliabilityDashboard();
    return _dashboard!;
  }

  void configure({
    double errorRateAlertThreshold = 0.05,
    Duration latencyAlertThreshold = const Duration(seconds: 5),
    double budgetWarningThreshold = 0.2,
  }) {
    _dashboard = ReliabilityDashboard(
      errorRateAlertThreshold: errorRateAlertThreshold,
      latencyAlertThreshold: latencyAlertThreshold,
      budgetWarningThreshold: budgetWarningThreshold,
    );
  }
}
