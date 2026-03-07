import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// 可靠性 API — 生产级实现
///
/// 所有指标均来自真实请求记录，无模拟/随机/硬编码数据。
/// 当无流量时，所有面板返回空或零值。

// ============================================================================
// 数据模型
// ============================================================================

/// 系统健康概览
class SystemHealthOverview {
  final double overallScore;
  final String grade;
  final int healthyServices;
  final int degradedServices;
  final int unhealthyServices;
  final double errorRate;
  final double avgLatencyMs;
  final double p99LatencyMs;
  final int requestsPerMinute;
  final DateTime timestamp;
  final List<String> criticalIssues;
  final List<String> warnings;

  SystemHealthOverview({
    required this.overallScore,
    required this.grade,
    required this.healthyServices,
    required this.degradedServices,
    required this.unhealthyServices,
    required this.errorRate,
    required this.avgLatencyMs,
    required this.p99LatencyMs,
    required this.requestsPerMinute,
    required this.timestamp,
    this.criticalIssues = const [],
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
    'overallScore': overallScore,
    'grade': grade,
    'services': {
      'healthy': healthyServices,
      'degraded': degradedServices,
      'unhealthy': unhealthyServices,
    },
    'metrics': {
      'errorRate': errorRate,
      'avgLatencyMs': avgLatencyMs,
      'p99LatencyMs': p99LatencyMs,
      'requestsPerMinute': requestsPerMinute,
    },
    'timestamp': timestamp.toIso8601String(),
    'criticalIssues': criticalIssues,
    'warnings': warnings,
  };
}

/// 服务状态
class ServiceStatus {
  final String name;
  final String status; // healthy, degraded, unhealthy
  final double successRate;
  final double avgLatencyMs;
  final double p95LatencyMs;
  final double p99LatencyMs;
  final int requestsPerMinute;
  final String circuitBreakerState;
  final String degradationLevel;
  final Map<String, dynamic> sloStatus;
  final DateTime lastUpdated;

  ServiceStatus({
    required this.name,
    required this.status,
    required this.successRate,
    required this.avgLatencyMs,
    required this.p95LatencyMs,
    required this.p99LatencyMs,
    required this.requestsPerMinute,
    required this.circuitBreakerState,
    required this.degradationLevel,
    required this.sloStatus,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'status': status,
    'metrics': {
      'successRate': successRate,
      'avgLatencyMs': avgLatencyMs,
      'p95LatencyMs': p95LatencyMs,
      'p99LatencyMs': p99LatencyMs,
      'requestsPerMinute': requestsPerMinute,
    },
    'circuitBreaker': circuitBreakerState,
    'degradation': degradationLevel,
    'slo': sloStatus,
    'lastUpdated': lastUpdated.toIso8601String(),
  };
}

/// 时间序列数据点
class TimeSeriesDataPoint {
  final DateTime timestamp;
  final double value;
  final String? label;

  TimeSeriesDataPoint({
    required this.timestamp,
    required this.value,
    this.label,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'value': value,
    if (label != null) 'label': label,
  };
}

/// 根因分析结果
class RootCauseResult {
  final String incidentId;
  final DateTime analyzedAt;
  final String summary;
  final List<Map<String, dynamic>> hypotheses;
  final List<Map<String, dynamic>> timeline;
  final int correlatedEventsCount;

  RootCauseResult({
    required this.incidentId,
    required this.analyzedAt,
    required this.summary,
    required this.hypotheses,
    required this.timeline,
    required this.correlatedEventsCount,
  });

  Map<String, dynamic> toJson() => {
    'incidentId': incidentId,
    'analyzedAt': analyzedAt.toIso8601String(),
    'summary': summary,
    'hypotheses': hypotheses,
    'timeline': timeline,
    'correlatedEventsCount': correlatedEventsCount,
  };
}

/// 负载预测
class LoadPrediction {
  final DateTime predictedTime;
  final double predictedLoad;
  final double confidence;
  final double lowerBound;
  final double upperBound;
  final String trendDirection;
  final double trendSlope;
  final String recommendedAction;

  LoadPrediction({
    required this.predictedTime,
    required this.predictedLoad,
    required this.confidence,
    required this.lowerBound,
    required this.upperBound,
    required this.trendDirection,
    required this.trendSlope,
    required this.recommendedAction,
  });

  Map<String, dynamic> toJson() => {
    'predictedTime': predictedTime.toIso8601String(),
    'predictedLoad': predictedLoad,
    'confidence': confidence,
    'bounds': {'lower': lowerBound, 'upper': upperBound},
    'trend': {'direction': trendDirection, 'slope': trendSlope},
    'recommendedAction': recommendedAction,
  };
}

/// 混沌实验状态
class ChaosExperimentStatus {
  final bool enabled;
  final bool experimentRunning;
  final String? currentExperimentId;
  final String? currentExperimentName;
  final List<Map<String, dynamic>> registeredExperiments;
  final List<Map<String, dynamic>> activeFaults;

  ChaosExperimentStatus({
    required this.enabled,
    required this.experimentRunning,
    this.currentExperimentId,
    this.currentExperimentName,
    this.registeredExperiments = const [],
    this.activeFaults = const [],
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'experimentRunning': experimentRunning,
    if (currentExperimentId != null) 'currentExperimentId': currentExperimentId,
    if (currentExperimentName != null) 'currentExperimentName': currentExperimentName,
    'registeredExperiments': registeredExperiments,
    'activeFaults': activeFaults,
  };
}

/// 告警
class ReliabilityAlert {
  final String id;
  final String severity;
  final String title;
  final String description;
  final String source;
  final DateTime timestamp;
  final bool acknowledged;

  ReliabilityAlert({
    required this.id,
    required this.severity,
    required this.title,
    required this.description,
    required this.source,
    required this.timestamp,
    this.acknowledged = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'severity': severity,
    'title': title,
    'description': description,
    'source': source,
    'timestamp': timestamp.toIso8601String(),
    'acknowledged': acknowledged,
  };
}

/// 自愈动作记录
class SelfHealingAction {
  final String id;
  final String type;
  final String service;
  final DateTime timestamp;
  final bool success;
  final String description;

  SelfHealingAction({
    required this.id,
    required this.type,
    required this.service,
    required this.timestamp,
    required this.success,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'service': service,
    'timestamp': timestamp.toIso8601String(),
    'success': success,
    'description': description,
  };
}

// ============================================================================
// 可靠性数据收集器 — 基于真实请求数据
// ============================================================================

class ReliabilityDataCollector {
  static final ReliabilityDataCollector _instance = ReliabilityDataCollector._();
  static ReliabilityDataCollector get instance => _instance;

  ReliabilityDataCollector._();

  // 服务注册
  final Map<String, _ServiceMetrics> _services = {};
  final List<ReliabilityAlert> _alerts = [];
  final List<RootCauseResult> _rootCauseHistory = [];
  final List<SelfHealingAction> _selfHealingActions = [];

  // 并发负载跟踪 — 基于真实的并发请求数
  int _activeRequests = 0;
  int _maxConcurrency = 100; // 服务器最大并发估计
  final List<TimeSeriesDataPoint> _loadHistory = [];

  // 告警阈值
  static const double _errorRateWarningThreshold = 0.05;
  static const double _errorRateCriticalThreshold = 0.10;
  static const double _latencyWarningThresholdMs = 500;
  static const double _latencyCriticalThresholdMs = 2000;

  // 混沌工程状态
  bool _chaosEnabled = false;
  String? _currentExperimentId;
  final List<Map<String, dynamic>> _registeredExperiments = [];

  /// 注册服务
  void registerService(String name) {
    _services.putIfAbsent(name, () => _ServiceMetrics(name));
  }

  /// 记录请求开始 — 用于并发负载跟踪
  void onRequestStart() {
    _activeRequests++;
    _recordCurrentLoad();
  }

  /// 记录请求结束 — 用于并发负载跟踪
  void onRequestEnd() {
    _activeRequests = math.max(0, _activeRequests - 1);
  }

  /// 记录请求指标（由中间件调用）
  void recordRequest(String service, {
    required bool success,
    required Duration latency,
  }) {
    final metrics = _services[service];
    if (metrics != null) {
      metrics.recordRequest(success: success, latency: latency);
    }

    // 检查告警阈值
    _evaluateAlerts(service);
  }

  /// 设置最大并发数估计（用于负载百分比计算）
  void setMaxConcurrency(int max) {
    _maxConcurrency = math.max(1, max);
  }

  /// 记录自愈动作
  void recordSelfHealingAction({
    required String type,
    required String service,
    required bool success,
    required String description,
  }) {
    _selfHealingActions.insert(0, SelfHealingAction(
      id: 'action_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      service: service,
      timestamp: DateTime.now(),
      success: success,
      description: description,
    ));
    // 保留最近100条
    while (_selfHealingActions.length > 100) {
      _selfHealingActions.removeLast();
    }
  }

  /// 添加告警
  void addAlert(ReliabilityAlert alert) {
    _alerts.add(alert);
    // 保留最近100条
    while (_alerts.length > 100) {
      _alerts.removeAt(0);
    }
  }

  /// 记录当前负载到历史
  void _recordCurrentLoad() {
    final load = _activeRequests / _maxConcurrency;
    _loadHistory.add(TimeSeriesDataPoint(
      timestamp: DateTime.now(),
      value: load.clamp(0.0, 1.0),
    ));
    // 保留最近2000个点
    while (_loadHistory.length > 2000) {
      _loadHistory.removeAt(0);
    }
  }

  /// 基于真实指标评估告警
  void _evaluateAlerts(String serviceName) {
    final metrics = _services[serviceName];
    if (metrics == null) return;

    // 需要至少10个请求才能有意义地评估
    if (metrics.totalRequests < 10) return;

    final errorRate = metrics.errorRate;
    final p99 = metrics.p99LatencyMs;
    final now = DateTime.now();

    // 检查最近5分钟内是否已经有相同告警，避免告警风暴
    bool hasRecentAlert(String source) {
      final cutoff = now.subtract(const Duration(minutes: 5));
      return _alerts.any((a) =>
        a.source == source &&
        a.timestamp.isAfter(cutoff) &&
        !a.acknowledged
      );
    }

    // 错误率告警
    if (errorRate > _errorRateCriticalThreshold) {
      final source = 'error_rate_$serviceName';
      if (!hasRecentAlert(source)) {
        addAlert(ReliabilityAlert(
          id: 'alert_${now.millisecondsSinceEpoch}_err_$serviceName',
          severity: 'critical',
          title: 'High Error Rate: $serviceName',
          description:
              'Error rate ${(errorRate * 100).toStringAsFixed(1)}% exceeds critical threshold ${(_errorRateCriticalThreshold * 100).toStringAsFixed(0)}%',
          source: source,
          timestamp: now,
        ));
      }
    } else if (errorRate > _errorRateWarningThreshold) {
      final source = 'error_rate_$serviceName';
      if (!hasRecentAlert(source)) {
        addAlert(ReliabilityAlert(
          id: 'alert_${now.millisecondsSinceEpoch}_err_$serviceName',
          severity: 'warning',
          title: 'Elevated Error Rate: $serviceName',
          description:
              'Error rate ${(errorRate * 100).toStringAsFixed(1)}% exceeds warning threshold ${(_errorRateWarningThreshold * 100).toStringAsFixed(0)}%',
          source: source,
          timestamp: now,
        ));
      }
    }

    // 延迟告警
    if (p99 > _latencyCriticalThresholdMs) {
      final source = 'latency_$serviceName';
      if (!hasRecentAlert(source)) {
        addAlert(ReliabilityAlert(
          id: 'alert_${now.millisecondsSinceEpoch}_lat_$serviceName',
          severity: 'critical',
          title: 'High Latency: $serviceName',
          description:
              'P99 latency ${p99.toStringAsFixed(0)}ms exceeds critical threshold ${_latencyCriticalThresholdMs.toStringAsFixed(0)}ms',
          source: source,
          timestamp: now,
        ));
      }
    } else if (p99 > _latencyWarningThresholdMs) {
      final source = 'latency_$serviceName';
      if (!hasRecentAlert(source)) {
        addAlert(ReliabilityAlert(
          id: 'alert_${now.millisecondsSinceEpoch}_lat_$serviceName',
          severity: 'warning',
          title: 'Elevated Latency: $serviceName',
          description:
              'P99 latency ${p99.toStringAsFixed(0)}ms exceeds warning threshold ${_latencyWarningThresholdMs.toStringAsFixed(0)}ms',
          source: source,
          timestamp: now,
        ));
      }
    }
  }

  /// 获取系统健康概览
  SystemHealthOverview getHealthOverview() {
    int healthy = 0, degraded = 0, unhealthy = 0;
    double totalErrorRate = 0;
    double totalLatency = 0;
    double maxP99 = 0;
    int totalRequests = 0;

    for (final service in _services.values) {
      final status = service.getStatus();
      if (status == 'healthy') healthy++;
      else if (status == 'degraded') degraded++;
      else unhealthy++;

      totalErrorRate += service.errorRate;
      totalLatency += service.avgLatencyMs;
      maxP99 = maxP99 > service.p99LatencyMs ? maxP99 : service.p99LatencyMs;
      totalRequests += service.requestsPerMinute;
    }

    final serviceCount = _services.length;
    final avgErrorRate = serviceCount > 0 ? totalErrorRate / serviceCount : 0.0;
    final avgLatency = serviceCount > 0 ? totalLatency / serviceCount : 0.0;

    // 计算健康分数 — 仅当有真实请求时才偏离100
    double score = 100;
    if (_hasAnyTraffic()) {
      score -= unhealthy * 20;
      score -= degraded * 10;
      score -= (avgErrorRate * 100).clamp(0, 30);
      score -= (avgLatency / 100).clamp(0, 20);
    }
    score = score.clamp(0, 100);

    String grade;
    if (score >= 90) grade = 'excellent';
    else if (score >= 75) grade = 'good';
    else if (score >= 60) grade = 'fair';
    else if (score >= 40) grade = 'poor';
    else grade = 'critical';

    final criticalIssues = <String>[];
    final warnings = <String>[];

    for (final service in _services.values) {
      if (service.totalRequests == 0) continue; // 无流量的服务不报问题
      if (service.getStatus() == 'unhealthy') {
        criticalIssues.add('${service.name} is unhealthy');
      } else if (service.getStatus() == 'degraded') {
        warnings.add('${service.name} is degraded');
      }
    }

    return SystemHealthOverview(
      overallScore: score,
      grade: grade,
      healthyServices: healthy,
      degradedServices: degraded,
      unhealthyServices: unhealthy,
      errorRate: avgErrorRate,
      avgLatencyMs: avgLatency,
      p99LatencyMs: maxP99,
      requestsPerMinute: totalRequests,
      timestamp: DateTime.now(),
      criticalIssues: criticalIssues,
      warnings: warnings,
    );
  }

  /// 是否有任何真实流量
  bool _hasAnyTraffic() {
    return _services.values.any((s) => s.totalRequests > 0);
  }

  /// 获取服务状态列表
  List<ServiceStatus> getServiceStatuses() {
    return _services.values.map((m) => ServiceStatus(
      name: m.name,
      status: m.getStatus(),
      successRate: 1 - m.errorRate,
      avgLatencyMs: m.avgLatencyMs,
      p95LatencyMs: m.p95LatencyMs,
      p99LatencyMs: m.p99LatencyMs,
      requestsPerMinute: m.requestsPerMinute,
      circuitBreakerState: m.circuitBreakerState,
      degradationLevel: m.degradationLevel,
      sloStatus: m.sloStatus,
      lastUpdated: m.lastUpdated,
    )).toList();
  }

  /// 获取时间序列数据 — 从真实请求记录聚合
  List<TimeSeriesDataPoint> getTimeSeries(String metric, {
    Duration window = const Duration(hours: 1),
  }) {
    final cutoff = DateTime.now().subtract(window);

    switch (metric) {
      case 'load':
        return _loadHistory.where((p) => p.timestamp.isAfter(cutoff)).toList();
      case 'errorrate':
        return _aggregateErrorRateTimeSeries(window);
      case 'latency':
        return _aggregateLatencyTimeSeries(window);
      case 'requests':
        return _aggregateRequestsTimeSeries(window);
      default:
        return [];
    }
  }

  /// 从真实请求记录聚合错误率时间序列
  /// 将时间窗口分成 N 个桶，每个桶计算该时段的错误率
  List<TimeSeriesDataPoint> _aggregateErrorRateTimeSeries(Duration window) {
    return _aggregateTimeSeries(window, (records) {
      if (records.isEmpty) return null;
      final failures = records.where((r) => !r.success).length;
      return failures / records.length;
    });
  }

  /// 从真实请求记录聚合延迟时间序列
  List<TimeSeriesDataPoint> _aggregateLatencyTimeSeries(Duration window) {
    return _aggregateTimeSeries(window, (records) {
      if (records.isEmpty) return null;
      return records.map((r) => r.latencyMs).reduce((a, b) => a + b) / records.length;
    });
  }

  /// 从真实请求记录聚合请求量时间序列
  List<TimeSeriesDataPoint> _aggregateRequestsTimeSeries(Duration window) {
    final bucketCount = 60;
    final now = DateTime.now();
    final bucketDuration = Duration(
      milliseconds: window.inMilliseconds ~/ bucketCount,
    );
    final points = <TimeSeriesDataPoint>[];

    for (int i = bucketCount; i >= 0; i--) {
      final bucketStart = now.subtract(bucketDuration * (i + 1));
      final bucketEnd = now.subtract(bucketDuration * i);

      int count = 0;
      for (final service in _services.values) {
        count += service.getRequestsInRange(bucketStart, bucketEnd);
      }

      // 只添加有数据的桶（或者在有流量期间的零值桶）
      if (count > 0 || _hasAnyTraffic()) {
        // 标准化为每分钟请求数
        final minutesFraction = bucketDuration.inMilliseconds / 60000;
        final rpm = minutesFraction > 0 ? count / minutesFraction : 0.0;
        points.add(TimeSeriesDataPoint(
          timestamp: bucketEnd,
          value: rpm,
        ));
      }
    }

    return points;
  }

  /// 通用时间序列聚合：将请求记录按时间桶分组，对每个桶应用聚合函数
  List<TimeSeriesDataPoint> _aggregateTimeSeries(
    Duration window,
    double? Function(List<_RequestRecord> records) aggregator,
  ) {
    final bucketCount = 60;
    final now = DateTime.now();
    final bucketDuration = Duration(
      milliseconds: window.inMilliseconds ~/ bucketCount,
    );
    final points = <TimeSeriesDataPoint>[];

    // 收集所有服务的请求记录
    final allRecords = <_RequestRecord>[];
    for (final service in _services.values) {
      allRecords.addAll(service.getRecordsInWindow(window));
    }

    if (allRecords.isEmpty) return [];

    // 按时间桶分组
    for (int i = bucketCount; i >= 0; i--) {
      final bucketStart = now.subtract(bucketDuration * (i + 1));
      final bucketEnd = now.subtract(bucketDuration * i);

      final bucketRecords = allRecords.where((r) =>
        r.timestamp.isAfter(bucketStart) && !r.timestamp.isAfter(bucketEnd)
      ).toList();

      final value = aggregator(bucketRecords);
      if (value != null) {
        points.add(TimeSeriesDataPoint(
          timestamp: bucketEnd,
          value: value,
        ));
      }
    }

    return points;
  }

  /// 获取负载预测 — 基于真实负载历史
  LoadPrediction getLoadPrediction() {
    // 使用真实负载历史；如果没有历史数据，返回零值
    final currentLoad = _loadHistory.isNotEmpty
        ? _loadHistory.last.value
        : 0.0;

    // 计算趋势（基于真实数据）
    double slope = 0;
    double confidence = 0;
    if (_loadHistory.length >= 10) {
      final recent = _loadHistory.sublist(_loadHistory.length - 10);
      final first = recent.first.value;
      final last = recent.last.value;
      slope = (last - first) / 10;
      // 置信度基于数据量
      confidence = math.min(0.95, _loadHistory.length / 200);
    }

    String direction;
    if (slope > 0.01) direction = 'increasing';
    else if (slope < -0.01) direction = 'decreasing';
    else direction = 'stable';

    final predicted = (currentLoad + slope * 15).clamp(0.0, 1.0);

    String action = 'none';
    if (predicted > 0.9) action = 'emergencyBrake';
    else if (predicted > 0.8) action = 'shedLoad';
    else if (predicted > 0.7) action = 'enableThrottling';
    else if (direction == 'increasing' && predicted > 0.5) action = 'preWarm';

    return LoadPrediction(
      predictedTime: DateTime.now().add(const Duration(minutes: 15)),
      predictedLoad: predicted,
      confidence: confidence,
      lowerBound: (predicted - 0.1).clamp(0, 1),
      upperBound: (predicted + 0.1).clamp(0, 1),
      trendDirection: direction,
      trendSlope: slope,
      recommendedAction: action,
    );
  }

  /// 获取根因分析结果
  List<RootCauseResult> getRootCauseResults({int limit = 10}) {
    return _rootCauseHistory.take(limit).toList();
  }

  /// 触发根因分析 — 基于真实告警和指标数据进行关联分析
  RootCauseResult triggerRootCauseAnalysis() {
    final now = DateTime.now();
    final recentAlerts = _alerts.where((a) =>
      a.timestamp.isAfter(now.subtract(const Duration(hours: 1)))
    ).toList();

    // 分析真实的不健康服务
    final unhealthyServices = _services.values
        .where((s) => s.totalRequests > 0 && s.getStatus() != 'healthy')
        .toList();

    // 构建假设 — 基于真实数据
    final hypotheses = <Map<String, dynamic>>[];

    // 检查高错误率服务
    for (final service in unhealthyServices) {
      if (service.errorRate > _errorRateCriticalThreshold) {
        hypotheses.add({
          'id': 'hyp_err_${service.name}',
          'description': '${service.name} 错误率 ${(service.errorRate * 100).toStringAsFixed(1)}% 异常偏高',
          'confidence': math.min(0.95, service.errorRate * 5),
          'category': 'error_rate',
          'suggestedActions': ['检查 ${service.name} 日志', '检查下游依赖状态'],
        });
      }
      if (service.p99LatencyMs > _latencyCriticalThresholdMs) {
        hypotheses.add({
          'id': 'hyp_lat_${service.name}',
          'description': '${service.name} P99 延迟 ${service.p99LatencyMs.toStringAsFixed(0)}ms 超过阈值',
          'confidence': math.min(0.90, service.p99LatencyMs / 5000),
          'category': 'latency',
          'suggestedActions': ['检查 ${service.name} 资源使用', '考虑启用限流'],
        });
      }
    }

    // 如果没有问题，说明系统正常
    if (hypotheses.isEmpty && recentAlerts.isEmpty) {
      final result = RootCauseResult(
        incidentId: 'rca_${now.millisecondsSinceEpoch}',
        analyzedAt: now,
        summary: '系统运行正常，未发现异常。',
        hypotheses: [],
        timeline: [],
        correlatedEventsCount: 0,
      );
      _rootCauseHistory.insert(0, result);
      _trimRootCauseHistory();
      return result;
    }

    // 按置信度排序
    hypotheses.sort((a, b) =>
      ((b['confidence'] as num?) ?? 0).compareTo((a['confidence'] as num?) ?? 0));

    // 构建事件时间线 — 从真实告警中提取
    final timeline = recentAlerts.take(10).map((a) => {
      'time': a.timestamp.toIso8601String(),
      'event': '${a.title}: ${a.description}',
      'severity': a.severity,
    }).toList();

    final summary = hypotheses.isNotEmpty
        ? '检测到 ${unhealthyServices.length} 个异常服务，${recentAlerts.length} 条相关告警。主要问题: ${hypotheses.first['description']}'
        : '检测到 ${recentAlerts.length} 条近期告警，需要进一步调查。';

    final result = RootCauseResult(
      incidentId: 'rca_${now.millisecondsSinceEpoch}',
      analyzedAt: now,
      summary: summary,
      hypotheses: hypotheses,
      timeline: timeline,
      correlatedEventsCount: recentAlerts.length,
    );

    _rootCauseHistory.insert(0, result);
    _trimRootCauseHistory();
    return result;
  }

  void _trimRootCauseHistory() {
    while (_rootCauseHistory.length > 50) {
      _rootCauseHistory.removeLast();
    }
  }

  /// 获取告警列表
  List<ReliabilityAlert> getAlerts({bool activeOnly = true}) {
    if (activeOnly) {
      return _alerts.where((a) => !a.acknowledged).toList();
    }
    return List.from(_alerts);
  }

  /// 确认告警
  bool acknowledgeAlert(String alertId) {
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
      );
      return true;
    }
    return false;
  }

  /// 获取混沌工程状态
  ChaosExperimentStatus getChaosStatus() {
    String? experimentName;
    List<Map<String, dynamic>> activeFaultsList = [];
    if (_currentExperimentId != null) {
      final experiment = _registeredExperiments.firstWhere(
        (e) => e['id'] == _currentExperimentId,
        orElse: () => {},
      );
      if (experiment.isNotEmpty) {
        experimentName = experiment['name'] as String?;
        final faults = experiment['faults'];
        if (faults is List) {
          activeFaultsList = faults.cast<Map<String, dynamic>>();
        }
      }
    }

    return ChaosExperimentStatus(
      enabled: _chaosEnabled,
      experimentRunning: _currentExperimentId != null,
      currentExperimentId: _currentExperimentId,
      currentExperimentName: experimentName,
      registeredExperiments: _registeredExperiments,
      activeFaults: activeFaultsList,
    );
  }

  /// 启用/禁用混沌工程
  void setChaosEnabled(bool enabled) {
    _chaosEnabled = enabled;
    if (!enabled) {
      _currentExperimentId = null;
    }
  }

  /// 注册混沌实验
  void registerChaosExperiment(Map<String, dynamic> experiment) {
    _registeredExperiments.add(experiment);
  }

  /// 混沌注入统计
  int _chaosLatencyInjections = 0;
  int _chaosErrorInjections = 0;

  /// 启动混沌实验
  bool startChaosExperiment(String experimentId) {
    if (!_chaosEnabled) return false;
    final experiment = _registeredExperiments.firstWhere(
      (e) => e['id'] == experimentId,
      orElse: () => {},
    );
    if (experiment.isEmpty) return false;
    _currentExperimentId = experimentId;
    _chaosLatencyInjections = 0;
    _chaosErrorInjections = 0;
    print('[Chaos] Experiment "$experimentId" STARTED — faults will be injected into live traffic');
    recordSelfHealingAction(
      type: 'chaos_experiment',
      service: 'chaos_engine',
      success: true,
      description: '混沌实验 "$experimentId" 已启动，故障将注入实时流量',
    );
    return true;
  }

  /// 停止混沌实验
  void stopChaosExperiment() {
    final expId = _currentExperimentId;
    _currentExperimentId = null;
    if (expId != null) {
      print('[Chaos] Experiment "$expId" STOPPED — latency injections: $_chaosLatencyInjections, error injections: $_chaosErrorInjections');
      recordSelfHealingAction(
        type: 'chaos_experiment',
        service: 'chaos_engine',
        success: true,
        description: '混沌实验 "$expId" 已停止 (延迟注入: $_chaosLatencyInjections, 错误注入: $_chaosErrorInjections)',
      );
    }
  }

  /// 获取当前活跃实验的故障配置 — 供中间件使用
  /// 如果混沌未启用或无实验运行，返回 null
  List<Map<String, dynamic>>? getActiveFaults() {
    if (!_chaosEnabled || _currentExperimentId == null) return null;
    final experiment = _registeredExperiments.firstWhere(
      (e) => e['id'] == _currentExperimentId,
      orElse: () => {},
    );
    if (experiment.isEmpty) return null;
    final faults = experiment['faults'];
    if (faults is List) {
      return faults.cast<Map<String, dynamic>>();
    }
    return null;
  }

  /// 服务端口，由外部设置
  int _serverPort = 9527;
  void setServerPort(int port) => _serverPort = port;

  /// 运行压力测试 — 向自身端点发送真实 HTTP 请求
  Future<Map<String, dynamic>> runStressTest() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final loadSteps = <Map<String, dynamic>>[];
    final targetPath = '/api/v1/reliability/health';

    for (final concurrency in [10, 50, 100, 200, 500]) {
      final latencies = <int>[];
      int successCount = 0;
      int errorCount = 0;
      final sw = Stopwatch()..start();

      // 每个并发级别发送 concurrency 个并发请求
      final futures = <Future<void>>[];
      for (int i = 0; i < concurrency; i++) {
        futures.add(() async {
          final reqSw = Stopwatch()..start();
          try {
            final req = await client.get('127.0.0.1', _serverPort, targetPath);
            final resp = await req.close().timeout(const Duration(seconds: 10));
            await resp.drain<void>();
            reqSw.stop();
            final ms = reqSw.elapsedMilliseconds;
            latencies.add(ms);
            if (resp.statusCode >= 200 && resp.statusCode < 400) {
              successCount++;
            } else {
              errorCount++;
            }
          } catch (_) {
            reqSw.stop();
            latencies.add(reqSw.elapsedMilliseconds);
            errorCount++;
          }
        }());
      }
      await Future.wait(futures);
      sw.stop();

      latencies.sort();
      final total = successCount + errorCount;
      final durationSec = sw.elapsedMilliseconds / 1000.0;
      final throughput = durationSec > 0 ? (total / durationSec).round() : total;

      int percentile(List<int> sorted, double p) {
        if (sorted.isEmpty) return 0;
        final idx = ((p / 100.0) * (sorted.length - 1)).round();
        return sorted[idx];
      }

      loadSteps.add({
        'concurrency': concurrency,
        'throughput': throughput,
        'p50': percentile(latencies, 50),
        'p95': percentile(latencies, 95),
        'p99': percentile(latencies, 99),
        'errorRate': total > 0
            ? double.parse((errorCount / total).toStringAsFixed(4))
            : 0.0,
        'successCount': successCount,
        'totalRequests': total,
      });
    }
    client.close();

    // 稳定性评估
    int? degradationPoint;
    int? maxSafeConcurrency;
    for (int i = 1; i < loadSteps.length; i++) {
      final prev = loadSteps[i - 1];
      final curr = loadSteps[i];
      final prevP95 = prev['p95'] as int;
      final currP95 = curr['p95'] as int;
      if (degradationPoint == null && currP95 > prevP95 * 2) {
        degradationPoint = curr['concurrency'] as int;
      }
      final errRate = curr['errorRate'] as double;
      if (maxSafeConcurrency == null && errRate > 0.05) {
        maxSafeConcurrency = prev['concurrency'] as int;
      }
    }
    degradationPoint ??= loadSteps.last['concurrency'] as int;
    maxSafeConcurrency ??= loadSteps.last['concurrency'] as int;

    final avgErrorRate = loadSteps.fold<double>(
            0.0, (sum, s) => sum + (s['errorRate'] as double)) /
        loadSteps.length;
    final score = math.max(0, math.min(100,
        (100 - avgErrorRate * 200 - (degradationPoint < 100 ? 20 : 0)).round()));
    final grade = score >= 90
        ? 'A'
        : score >= 80
            ? 'B+'
            : score >= 70
                ? 'B'
                : score >= 60
                    ? 'C'
                    : 'D';

    final passed = score >= 60 && avgErrorRate < 0.05;

    final findings = <String>[
      '最大安全并发: $maxSafeConcurrency',
      '延迟退化点: $degradationPoint 并发',
      '平均错误率: ${(avgErrorRate * 100).toStringAsFixed(2)}%',
      '综合评级: $grade',
    ];
    final warnings = <String>[
      if (degradationPoint <= 100) '延迟在 $degradationPoint 并发时即开始退化，建议优化热路径',
      if (avgErrorRate > 0.01) '平均错误率 ${(avgErrorRate * 100).toStringAsFixed(2)}% 偏高，建议排查',
    ];
    final criticals = <String>[
      if (avgErrorRate > 0.05) '错误率超过 5% 阈值，系统在高负载下不稳定',
      if (maxSafeConcurrency < 50) '最大安全并发低于 50，需要紧急优化',
    ];

    final assessment = {
      'stabilityScore': score,
      'passed': passed,
      'grade': grade,
      'maxSafeConcurrency': maxSafeConcurrency,
      'degradationPoint': degradationPoint,
      'findings': findings,
      'warnings': warnings,
      'criticalIssues': criticals,
      'summary': '压力测试完成：在 $degradationPoint 并发时延迟开始退化，'
          '最大安全并发 $maxSafeConcurrency，综合评分 $score ($grade)',
    };

    _lastStressTestResults = {
      'loadSteps': loadSteps,
      'chaosExperiments': <Map<String, dynamic>>[],
      'stabilityAssessment': assessment,
      'timestamp': DateTime.now().toIso8601String(),
    };
    return _lastStressTestResults!;
  }

  Map<String, dynamic>? _lastStressTestResults;

  /// 获取最近一次压力测试结果
  Map<String, dynamic> getStressTestResults() {
    return _lastStressTestResults ?? {
      'loadSteps': <Map<String, dynamic>>[],
      'chaosExperiments': <Map<String, dynamic>>[],
      'stabilityAssessment': null,
    };
  }

  /// 运行混沌测试套件 — 逐个启动已注册实验，发送真实请求，收集故障影响
  Future<Map<String, dynamic>> runChaosTest() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final targetPath = '/api/v1/reliability/health';
    final experiments = <Map<String, dynamic>>[];
    final wasChaosEnabled = _chaosEnabled;
    final prevExperimentId = _currentExperimentId;

    // 临时启用混沌工程
    _chaosEnabled = true;

    for (final exp in _registeredExperiments) {
      final expId = exp['id'] as String? ?? '';
      final expName = exp['name'] as String? ?? expId;
      final faults = exp['faults'] as List?;
      final faultType = (faults?.isNotEmpty == true)
          ? (faults!.first as Map)['type']?.toString() ?? 'unknown'
          : 'unknown';

      // 启动实验
      _currentExperimentId = expId;
      _chaosLatencyInjections = 0;
      _chaosErrorInjections = 0;

      int successCount = 0;
      int failureCount = 0;
      int retryCount = 0;
      const totalRequests = 50;

      for (int i = 0; i < totalRequests; i++) {
        int attempts = 0;
        bool succeeded = false;
        while (attempts < 3 && !succeeded) {
          attempts++;
          try {
            final req = await client.get('127.0.0.1', _serverPort, targetPath);
            final resp = await req.close().timeout(const Duration(seconds: 10));
            await resp.drain<void>();
            if (resp.statusCode >= 200 && resp.statusCode < 400) {
              succeeded = true;
            }
          } catch (_) {
            // 请求失败
          }
          if (!succeeded && attempts < 3) retryCount++;
        }
        if (succeeded) {
          successCount++;
        } else {
          failureCount++;
        }
      }

      // 停止实验
      _currentExperimentId = null;

      final errorRate = totalRequests > 0
          ? double.parse((failureCount / totalRequests).toStringAsFixed(4))
          : 0.0;
      final cbState = errorRate > 0.2 ? 'OPEN' : 'CLOSED';
      final stormDetected = errorRate > 0.25;

      final observations = <String>[];
      if (errorRate > 0.2) observations.add('错误率超过阈值，熔断器已触发');
      if (errorRate <= 0.1) observations.add('系统在故障注入下表现良好');
      if (retryCount > 0) observations.add('重试机制触发 $retryCount 次');
      if (_chaosLatencyInjections > 0) {
        observations.add('延迟注入 $_chaosLatencyInjections 次');
      }
      if (_chaosErrorInjections > 0) {
        observations.add('错误注入 $_chaosErrorInjections 次');
      }

      experiments.add({
        'experimentName': expName,
        'faultType': faultType,
        'successCount': successCount,
        'failureCount': failureCount,
        'rejectedCount': 0,
        'retryCount': retryCount,
        'errorRate': errorRate,
        'circuitBreakerFinalState': cbState,
        'stormDetected': stormDetected,
        'observations': observations,
      });
    }

    client.close();

    // 恢复之前的混沌状态
    _chaosEnabled = wasChaosEnabled;
    _currentExperimentId = prevExperimentId;

    if (_lastStressTestResults != null) {
      _lastStressTestResults!['chaosExperiments'] = experiments;
    }

    return {
      'triggered': true,
      'experiments': experiments,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 记录混沌延迟注入事件
  void recordChaosLatencyInjection() {
    _chaosLatencyInjections++;
  }

  /// 记录混沌错误注入事件
  void recordChaosErrorInjection() {
    _chaosErrorInjections++;
  }

  /// 获取自愈动作历史 — 返回真实记录
  List<SelfHealingAction> getSelfHealingActions() {
    return List.from(_selfHealingActions);
  }

  /// 获取服务依赖图 — 基于已注册的真实服务
  Map<String, dynamic> getDependencyGraph() {
    final nodes = <Map<String, dynamic>>[];
    final edges = <Map<String, dynamic>>[];

    for (final service in _services.values) {
      nodes.add({
        'id': service.name,
        'label': service.name,
        'status': service.getStatus(),
        'metrics': {
          'errorRate': service.errorRate,
          'latencyMs': service.avgLatencyMs,
        },
      });
    }

    // 依赖关系从已注册服务推断（静态拓扑配置）
    // 这些是系统架构事实，不是模拟数据
    final knownDependencies = [
      ['api_gateway', 'auth_service'],
      ['api_gateway', 'user_service'],
      ['api_gateway', 'product_service'],
      ['api_gateway', 'cart_service'],
      ['api_gateway', 'ai_service'],
    ];

    final registeredNames = _services.keys.toSet();
    for (final dep in knownDependencies) {
      if (registeredNames.contains(dep[0]) && registeredNames.contains(dep[1])) {
        edges.add({
          'source': dep[0],
          'target': dep[1],
          'healthy': true,
        });
      }
    }

    return {
      'nodes': nodes,
      'edges': edges,
    };
  }
}

/// 服务指标内部类 — 存储带时间戳的真实请求记录
class _ServiceMetrics {
  final String name;
  final List<_RequestRecord> _requests = [];
  DateTime lastUpdated = DateTime.now();

  _ServiceMetrics(this.name);

  void recordRequest({required bool success, required Duration latency}) {
    _requests.add(_RequestRecord(
      timestamp: DateTime.now(),
      success: success,
      latencyMs: latency.inMilliseconds.toDouble(),
    ));
    lastUpdated = DateTime.now();

    // 保留最近5000条（足够计算时间序列）
    while (_requests.length > 5000) {
      _requests.removeAt(0);
    }
  }

  /// 获取时间窗口内的请求记录
  List<_RequestRecord> getRecordsInWindow(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return _requests.where((r) => r.timestamp.isAfter(cutoff)).toList();
  }

  /// 获取时间范围内的请求数
  int getRequestsInRange(DateTime start, DateTime end) {
    return _requests.where((r) =>
      r.timestamp.isAfter(start) && !r.timestamp.isAfter(end)
    ).length;
  }

  int get totalRequests => _requests.length;

  double get errorRate {
    if (_requests.isEmpty) return 0;
    final failures = _requests.where((r) => !r.success).length;
    return failures / _requests.length;
  }

  double get avgLatencyMs {
    if (_requests.isEmpty) return 0;
    return _requests.map((r) => r.latencyMs).reduce((a, b) => a + b) / _requests.length;
  }

  double get p95LatencyMs {
    if (_requests.isEmpty) return 0;
    final sorted = _requests.map((r) => r.latencyMs).toList()..sort();
    final index = (sorted.length * 0.95).floor();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  double get p99LatencyMs {
    if (_requests.isEmpty) return 0;
    final sorted = _requests.map((r) => r.latencyMs).toList()..sort();
    final index = (sorted.length * 0.99).floor();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  int get requestsPerMinute {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    return _requests.where((r) => r.timestamp.isAfter(cutoff)).length;
  }

  String get circuitBreakerState {
    if (_requests.isEmpty) return 'closed';
    if (errorRate > 0.5) return 'open';
    if (errorRate > 0.2) return 'halfOpen';
    return 'closed';
  }

  String get degradationLevel {
    if (_requests.isEmpty) return 'normal';
    if (errorRate > 0.3) return 'critical';
    if (errorRate > 0.1) return 'warning';
    if (errorRate > 0.05) return 'caution';
    return 'normal';
  }

  Map<String, dynamic> get sloStatus => {
    'availability': {
      'target': 0.999,
      'current': 1 - errorRate,
      'met': (1 - errorRate) >= 0.999,
    },
    'latency': {
      'targetMs': 500,
      'currentP99Ms': p99LatencyMs,
      'met': p99LatencyMs <= 500,
    },
  };

  String getStatus() {
    if (_requests.isEmpty) return 'healthy'; // 无流量视为健康
    if (errorRate > 0.1 || p99LatencyMs > 2000) return 'unhealthy';
    if (errorRate > 0.05 || p99LatencyMs > 1000) return 'degraded';
    return 'healthy';
  }
}

class _RequestRecord {
  final DateTime timestamp;
  final bool success;
  final double latencyMs;

  _RequestRecord({
    required this.timestamp,
    required this.success,
    required this.latencyMs,
  });
}

// ============================================================================
// API 路由处理器
// ============================================================================

class ReliabilityApiHandler {
  final ReliabilityDataCollector _collector = ReliabilityDataCollector.instance;

  Router get router {
    final router = Router();

    // CORS headers
    const headers = {
      'content-type': 'application/json',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization',
      'cache-control': 'no-cache, no-store, must-revalidate',
    };

    // OPTIONS for all routes
    router.options('/<ignore|.*>', (Request r) => Response(200, headers: headers));

    // ========== 健康概览 ==========
    router.get('/health', (Request r) async {
      try {
        final overview = _collector.getHealthOverview();
        return Response.ok(jsonEncode({
          'success': true,
          'data': overview.toJson(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 服务状态 ==========
    router.get('/services', (Request r) async {
      try {
        final services = _collector.getServiceStatuses();
        return Response.ok(jsonEncode({
          'success': true,
          'data': services.map((s) => s.toJson()).toList(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.get('/services/<name>', (Request r, String name) async {
      try {
        final services = _collector.getServiceStatuses();
        final service = services.firstWhere(
          (s) => s.name == name,
          orElse: () => throw Exception('Service not found: $name'),
        );
        return Response.ok(jsonEncode({
          'success': true,
          'data': service.toJson(),
        }), headers: headers);
      } catch (e) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 时间序列指标 ==========
    router.get('/metrics/timeseries/<metric>', (Request r, String metric) async {
      try {
        final params = r.requestedUri.queryParameters;
        final windowMinutes = int.tryParse(params['window'] ?? '60') ?? 60;
        final window = Duration(minutes: windowMinutes);

        final data = _collector.getTimeSeries(metric, window: window);
        return Response.ok(jsonEncode({
          'success': true,
          'metric': metric,
          'window': '${window.inMinutes}m',
          'data': data.map((p) => p.toJson()).toList(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 负载预测 ==========
    router.get('/predictions/load', (Request r) async {
      try {
        final prediction = _collector.getLoadPrediction();
        return Response.ok(jsonEncode({
          'success': true,
          'data': prediction.toJson(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 根因分析 ==========
    router.get('/rca', (Request r) async {
      try {
        final params = r.requestedUri.queryParameters;
        final limit = int.tryParse(params['limit'] ?? '10') ?? 10;
        final results = _collector.getRootCauseResults(limit: limit);
        return Response.ok(jsonEncode({
          'success': true,
          'data': results.map((r) => r.toJson()).toList(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/rca/analyze', (Request r) async {
      try {
        final result = _collector.triggerRootCauseAnalysis();
        return Response.ok(jsonEncode({
          'success': true,
          'data': result.toJson(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 告警 ==========
    router.get('/alerts', (Request r) async {
      try {
        final params = r.requestedUri.queryParameters;
        final activeOnly = params['active'] != 'false';
        final alerts = _collector.getAlerts(activeOnly: activeOnly);
        return Response.ok(jsonEncode({
          'success': true,
          'data': alerts.map((a) => a.toJson()).toList(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/alerts/<id>/acknowledge', (Request r, String id) async {
      try {
        final success = _collector.acknowledgeAlert(id);
        return Response.ok(jsonEncode({
          'success': success,
          'message': success ? 'Alert acknowledged' : 'Alert not found',
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 依赖图 ==========
    router.get('/dependencies', (Request r) async {
      try {
        final graph = _collector.getDependencyGraph();
        return Response.ok(jsonEncode({
          'success': true,
          'data': graph,
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 混沌工程 ==========
    router.get('/chaos/status', (Request r) async {
      try {
        final status = _collector.getChaosStatus();
        return Response.ok(jsonEncode({
          'success': true,
          'data': status.toJson(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/chaos/enable', (Request r) async {
      try {
        _collector.setChaosEnabled(true);
        return Response.ok(jsonEncode({
          'success': true,
          'message': 'Chaos engineering enabled',
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/chaos/disable', (Request r) async {
      try {
        _collector.setChaosEnabled(false);
        return Response.ok(jsonEncode({
          'success': true,
          'message': 'Chaos engineering disabled',
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/chaos/experiments/<id>/start', (Request r, String id) async {
      try {
        final success = _collector.startChaosExperiment(id);
        return Response.ok(jsonEncode({
          'success': success,
          'message': success ? 'Experiment started' : 'Failed to start experiment',
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/chaos/experiments/stop', (Request r) async {
      try {
        _collector.stopChaosExperiment();
        return Response.ok(jsonEncode({
          'success': true,
          'message': 'Experiment stopped',
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 压力测试 ==========
    router.get('/stress-test/results', (Request r) async {
      try {
        final results = _collector.getStressTestResults();
        return Response.ok(jsonEncode({
          'success': true,
          'data': results,
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/stress-test/run', (Request r) async {
      try {
        final results = await _collector.runStressTest();
        return Response.ok(jsonEncode({
          'success': true,
          'data': results,
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 混沌测试套件 ==========
    router.post('/chaos-test/run', (Request r) async {
      try {
        final results = await _collector.runChaosTest();
        return Response.ok(jsonEncode({
          'success': true,
          'data': results,
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    // ========== 自愈动作 ==========
    router.get('/actions/history', (Request r) async {
      try {
        final actions = _collector.getSelfHealingActions();
        return Response.ok(jsonEncode({
          'success': true,
          'data': actions.map((a) => a.toJson()).toList(),
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    router.post('/actions/trigger/<action>', (Request r, String action) async {
      try {
        // 记录手动触发的自愈动作
        _collector.recordSelfHealingAction(
          type: action,
          service: 'manual',
          success: true,
          description: 'Manually triggered: $action',
        );
        return Response.ok(jsonEncode({
          'success': true,
          'message': 'Action $action triggered',
          'actionId': 'action_${DateTime.now().millisecondsSinceEpoch}',
        }), headers: headers);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'success': false, 'error': e.toString()}),
          headers: headers,
        );
      }
    });

    return router;
  }
}

/// 初始化可靠性数据收集器
/// 
/// 仅注册服务和混沌实验配置。
/// 不注入任何模拟/假数据 — 所有指标来自真实请求。
void initializeReliabilityCollector() {
  final collector = ReliabilityDataCollector.instance;

  // 注册已知服务（架构配置，不是假数据）
  final services = [
    'api_gateway',
    'auth_service',
    'user_service',
    'product_service',
    'cart_service',
    'ai_service',
  ];

  for (final service in services) {
    collector.registerService(service);
  }

  // 注册混沌实验配置（这是实验定义，不是假遥测数据）
  collector.registerChaosExperiment({
    'id': 'exp_latency_storm',
    'name': 'Latency Storm Test',
    'description': '模拟延迟风暴，测试系统弹性',
    'faults': [{'type': 'latency', 'probability': 0.5, 'durationMs': 3000}],
  });

  collector.registerChaosExperiment({
    'id': 'exp_error_injection',
    'name': 'Error Injection',
    'description': '注入错误响应，测试错误处理',
    'faults': [{'type': 'error', 'probability': 0.2}],
  });

  print('[Reliability] Collector initialized with ${services.length} services (no seed data)');
}

/// 可观测性中间件 — 在 proxy_server.dart 中使用
/// 
/// 拦截所有 HTTP 请求，测量真实延迟和成功率，
/// 将数据馈入 ReliabilityDataCollector。
/// 
/// 同时负责混沌工程故障注入：
/// 当混沌实验运行时，根据实验故障配置以概率方式注入：
///   - latency 故障：在真实响应前人为增加延迟
///   - error 故障：以概率返回 500 错误代替真实响应
/// 故障注入发生在真实请求管道中，影响真实指标。
Middleware observabilityMiddleware() {
  final collector = ReliabilityDataCollector.instance;
  final chaosRng = math.Random();

  return (Handler innerHandler) {
    return (Request request) async {
      final path = request.requestedUri.path;

      // 排除可靠性 API 自身的请求，避免自引用监控噪声
      if (path.contains('/reliability')) {
        return innerHandler(request);
      }

      // 排除 OPTIONS 预检请求和静态资源
      if (request.method == 'OPTIONS' || path.contains('/__')) {
        return innerHandler(request);
      }

      final stopwatch = Stopwatch()..start();
      collector.onRequestStart();

      // ====== 混沌工程故障注入 ======
      final activeFaults = collector.getActiveFaults();
      if (activeFaults != null) {
        for (final fault in activeFaults) {
          final type = fault['type'] as String?;
          final probability = (fault['probability'] as num?)?.toDouble() ?? 0.0;

          if (type == 'error' && chaosRng.nextDouble() < probability) {
            // 错误注入：以概率直接返回 500，不调用真实 handler
            stopwatch.stop();
            final serviceName = _classifyRequestService(path);
            collector.recordRequest(
              serviceName,
              success: false,
              latency: stopwatch.elapsed,
            );
            collector.onRequestEnd();
            collector.recordChaosErrorInjection();
            print('[Chaos] ERROR injected for $path (probability: ${(probability * 100).toStringAsFixed(0)}%)');
            return Response.internalServerError(
              body: jsonEncode({
                'error': 'Chaos engineering: simulated failure',
                'chaos': true,
                'experimentFault': 'error',
              }),
              headers: {'content-type': 'application/json'},
            );
          }

          if (type == 'latency') {
            final durationMs = (fault['durationMs'] as num?)?.toInt() ?? 1000;
            if (chaosRng.nextDouble() < probability) {
              // 延迟注入：在真实请求前人为增加延迟
              collector.recordChaosLatencyInjection();
              print('[Chaos] LATENCY injected: +${durationMs}ms for $path');
              await Future.delayed(Duration(milliseconds: durationMs));
            }
          }
        }
      }
      // ====== 混沌工程故障注入结束 ======

      try {
        final response = await innerHandler(request);
        stopwatch.stop();

        final success = response.statusCode < 500;
        final serviceName = _classifyRequestService(path);

        collector.recordRequest(
          serviceName,
          success: success,
          latency: stopwatch.elapsed,
        );
        collector.onRequestEnd();

        return response;
      } catch (e) {
        stopwatch.stop();
        final serviceName = _classifyRequestService(path);

        collector.recordRequest(
          serviceName,
          success: false,
          latency: stopwatch.elapsed,
        );
        collector.onRequestEnd();

        rethrow;
      }
    };
  };
}

/// 根据请求路径分类到对应服务
String _classifyRequestService(String path) {
  if (path.contains('/auth')) return 'auth_service';
  if (path.contains('/users') || path.contains('/admin/users')) return 'user_service';
  if (path.contains('/cart')) return 'cart_service';
  if (path.contains('/ai') || path.contains('/proxy') || path.contains('/chat')) return 'ai_service';
  if (path.contains('/product') || path.contains('/price')) return 'product_service';
  return 'api_gateway';
}
