import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';
import '../resilience/circuit_breaker.dart';

/// 事件严重程度
enum EventSeverity { info, warning, error, critical }

/// 事件类别
enum EventCategory {
  network,
  latency,
  error,
  resource,
  dependency,
  configuration,
  security,
  capacity,
}

/// 故障事件记录
class IncidentEvent {
  final String id;
  final DateTime timestamp;
  final String service;
  final String component;
  final EventCategory category;
  final EventSeverity severity;
  final String description;
  final Map<String, dynamic> attributes;
  final Duration? duration;
  final StackTrace? stackTrace;

  IncidentEvent({
    required this.id,
    required this.timestamp,
    required this.service,
    required this.component,
    required this.category,
    required this.severity,
    required this.description,
    this.attributes = const {},
    this.duration,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'service': service,
        'component': component,
        'category': category.name,
        'severity': severity.name,
        'description': description,
        'attributes': attributes,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
      };
}

/// 根因假设
class RootCauseHypothesis {
  final String id;
  final String description;
  final double confidence;
  final EventCategory category;
  final List<String> supportingEvidence;
  final List<String> suggestedActions;
  final Map<String, dynamic> metadata;

  const RootCauseHypothesis({
    required this.id,
    required this.description,
    required this.confidence,
    required this.category,
    this.supportingEvidence = const [],
    this.suggestedActions = const [],
    this.metadata = const {},
  });

  bool get isHighConfidence => confidence >= 0.7;
  bool get isMediumConfidence => confidence >= 0.4 && confidence < 0.7;
  bool get isLowConfidence => confidence < 0.4;

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'confidence': confidence,
        'confidenceLevel': isHighConfidence
            ? 'high'
            : isMediumConfidence
                ? 'medium'
                : 'low',
        'category': category.name,
        'supportingEvidence': supportingEvidence,
        'suggestedActions': suggestedActions,
        'metadata': metadata,
      };
}

/// 根因分析结果
class RootCauseAnalysisResult {
  final String incidentId;
  final DateTime analyzedAt;
  final Duration analysisTime;
  final List<RootCauseHypothesis> hypotheses;
  final List<IncidentEvent> correlatedEvents;
  final Map<String, dynamic> timeline;
  final String summary;

  const RootCauseAnalysisResult({
    required this.incidentId,
    required this.analyzedAt,
    required this.analysisTime,
    required this.hypotheses,
    required this.correlatedEvents,
    required this.timeline,
    required this.summary,
  });

  RootCauseHypothesis? get primaryCause =>
      hypotheses.isNotEmpty ? hypotheses.first : null;

  bool get hasConfidentCause =>
      hypotheses.any((h) => h.isHighConfidence);

  Map<String, dynamic> toJson() => {
        'incidentId': incidentId,
        'analyzedAt': analyzedAt.toIso8601String(),
        'analysisTimeMs': analysisTime.inMilliseconds,
        'summary': summary,
        'primaryCause': primaryCause?.toJson(),
        'hypotheses': hypotheses.map((h) => h.toJson()).toList(),
        'correlatedEventsCount': correlatedEvents.length,
        'timeline': timeline,
      };
}

/// 依赖关系图节点
class DependencyNode {
  final String service;
  final List<String> upstreamDependencies;
  final List<String> downstreamDependencies;
  final Map<String, double> healthScores;

  DependencyNode({
    required this.service,
    this.upstreamDependencies = const [],
    this.downstreamDependencies = const [],
    this.healthScores = const {},
  });
}

/// 相关性分析器
class CorrelationAnalyzer {
  /// 计算两个时间序列的皮尔逊相关系数
  static double pearsonCorrelation(List<double> x, List<double> y) {
    if (x.length != y.length || x.length < 2) return 0;

    final n = x.length;
    final meanX = x.reduce((a, b) => a + b) / n;
    final meanY = y.reduce((a, b) => a + b) / n;

    double numerator = 0;
    double sumX2 = 0;
    double sumY2 = 0;

    for (int i = 0; i < n; i++) {
      final dx = x[i] - meanX;
      final dy = y[i] - meanY;
      numerator += dx * dy;
      sumX2 += dx * dx;
      sumY2 += dy * dy;
    }

    final denominator = math.sqrt(sumX2 * sumY2);
    if (denominator == 0) return 0;

    return numerator / denominator;
  }

  /// 计算滞后相关性
  static Map<int, double> lagCorrelation(
    List<double> x,
    List<double> y, {
    int maxLag = 10,
  }) {
    final results = <int, double>{};

    for (int lag = -maxLag; lag <= maxLag; lag++) {
      final alignedX = <double>[];
      final alignedY = <double>[];

      for (int i = 0; i < x.length; i++) {
        final j = i + lag;
        if (j >= 0 && j < y.length) {
          alignedX.add(x[i]);
          alignedY.add(y[j]);
        }
      }

      if (alignedX.length >= 3) {
        results[lag] = pearsonCorrelation(alignedX, alignedY);
      }
    }

    return results;
  }

  /// 检测异常点
  static List<int> detectAnomalies(
    List<double> data, {
    double threshold = 2.0,
  }) {
    if (data.length < 5) return [];

    final mean = data.reduce((a, b) => a + b) / data.length;
    final variance =
        data.map((d) => math.pow(d - mean, 2)).reduce((a, b) => a + b) /
            data.length;
    final stdDev = math.sqrt(variance);

    final anomalies = <int>[];
    for (int i = 0; i < data.length; i++) {
      if ((data[i] - mean).abs() > threshold * stdDev) {
        anomalies.add(i);
      }
    }

    return anomalies;
  }
}

/// 故障模式识别器
class FailurePatternRecognizer {
  static const _patterns = <String, Map<String, dynamic>>{
    'cascading_failure': {
      'indicators': ['multiple_services_affected', 'sequential_failures'],
      'symptoms': [EventCategory.dependency, EventCategory.error],
    },
    'resource_exhaustion': {
      'indicators': ['gradual_degradation', 'high_resource_usage'],
      'symptoms': [EventCategory.resource, EventCategory.capacity],
    },
    'network_partition': {
      'indicators': ['connectivity_failures', 'timeout_spikes'],
      'symptoms': [EventCategory.network, EventCategory.latency],
    },
    'thundering_herd': {
      'indicators': ['sudden_load_spike', 'synchronized_requests'],
      'symptoms': [EventCategory.capacity, EventCategory.latency],
    },
    'configuration_drift': {
      'indicators': ['recent_deployment', 'config_mismatch'],
      'symptoms': [EventCategory.configuration, EventCategory.error],
    },
    'dependency_failure': {
      'indicators': ['external_service_error', 'timeout_increase'],
      'symptoms': [EventCategory.dependency, EventCategory.network],
    },
    'memory_leak': {
      'indicators': ['gradual_memory_increase', 'eventual_oom'],
      'symptoms': [EventCategory.resource],
    },
    'connection_pool_exhaustion': {
      'indicators': ['connection_wait_time', 'pool_full'],
      'symptoms': [EventCategory.resource, EventCategory.latency],
    },
  };

  /// 匹配故障模式
  static List<MapEntry<String, double>> matchPatterns(
    List<IncidentEvent> events,
  ) {
    final categoryCount = <EventCategory, int>{};
    for (final event in events) {
      categoryCount[event.category] =
          (categoryCount[event.category] ?? 0) + 1;
    }

    final matches = <String, double>{};

    for (final entry in _patterns.entries) {
      final pattern = entry.key;
      final config = entry.value;
      final symptoms = config['symptoms'] as List<EventCategory>;

      int matchedSymptoms = 0;
      for (final symptom in symptoms) {
        if (categoryCount.containsKey(symptom)) {
          matchedSymptoms++;
        }
      }

      if (matchedSymptoms > 0) {
        final confidence = matchedSymptoms / symptoms.length;
        matches[pattern] = confidence;
      }
    }

    // 按置信度排序
    final sorted = matches.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted;
  }

  /// 获取模式的建议动作
  static List<String> getSuggestedActions(String pattern) {
    switch (pattern) {
      case 'cascading_failure':
        return [
          '启用断路器保护下游服务',
          '实施隔离策略',
          '检查服务间超时配置',
        ];
      case 'resource_exhaustion':
        return [
          '增加资源配额',
          '实施负载卸载',
          '检查资源泄漏',
        ];
      case 'network_partition':
        return [
          '检查网络连接',
          '切换到备用网络路径',
          '启用本地缓存降级',
        ];
      case 'thundering_herd':
        return [
          '实施请求排队',
          '增加抖动延迟',
          '启用缓存预热',
        ];
      case 'configuration_drift':
        return [
          '验证配置一致性',
          '回滚最近变更',
          '检查环境变量',
        ];
      case 'dependency_failure':
        return [
          '检查外部服务状态',
          '启用降级回退',
          '增加重试间隔',
        ];
      case 'memory_leak':
        return [
          '分析堆内存快照',
          '重启受影响服务',
          '检查对象生命周期',
        ];
      case 'connection_pool_exhaustion':
        return [
          '增加连接池大小',
          '减少连接持有时间',
          '检查连接泄漏',
        ];
      default:
        return ['进行详细诊断'];
    }
  }
}

/// 自动化根因分析器
class RootCauseAnalyzer {
  final ModuleLogger _logger;

  /// 事件存储
  final Queue<IncidentEvent> _eventHistory = Queue();
  final Duration _eventRetention;

  /// 依赖图
  final Map<String, DependencyNode> _dependencyGraph = {};

  /// 分析配置
  final Duration correlationWindow;
  final int minEventsForAnalysis;
  final double correlationThreshold;

  /// 回调
  final void Function(RootCauseAnalysisResult)? onAnalysisComplete;

  /// 分析缓存
  final Map<String, RootCauseAnalysisResult> _analysisCache = {};

  RootCauseAnalyzer({
    Duration eventRetention = const Duration(hours: 6),
    this.correlationWindow = const Duration(minutes: 5),
    this.minEventsForAnalysis = 3,
    this.correlationThreshold = 0.6,
    this.onAnalysisComplete,
  })  : _eventRetention = eventRetention,
        _logger = AppLogger.instance.module('RootCauseAnalyzer');

  /// 注册服务依赖关系
  void registerDependency(
    String service, {
    List<String> upstreamDependencies = const [],
    List<String> downstreamDependencies = const [],
  }) {
    _dependencyGraph[service] = DependencyNode(
      service: service,
      upstreamDependencies: upstreamDependencies,
      downstreamDependencies: downstreamDependencies,
    );
  }

  /// 记录事件
  void recordEvent(IncidentEvent event) {
    _eventHistory.add(event);
    _cleanupOldEvents();

    // 检查是否需要触发分析
    _checkForAnalysisTrigger(event);

    MetricsCollector.instance.increment(
      'rca_events_recorded',
      labels: MetricLabels()
          .add('category', event.category.name)
          .add('severity', event.severity.name),
    );
  }

  /// 从异常创建事件
  void recordError({
    required String service,
    required String component,
    required Object error,
    StackTrace? stackTrace,
    Map<String, dynamic>? attributes,
  }) {
    final event = IncidentEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      service: service,
      component: component,
      category: _categorizeError(error),
      severity: _severityFromError(error),
      description: error.toString(),
      attributes: attributes ?? {},
      stackTrace: stackTrace,
    );

    recordEvent(event);
  }

  /// 从熔断器状态变化创建事件
  void recordCircuitBreakerEvent(CircuitBreaker breaker, CircuitState newState) {
    final event = IncidentEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      service: breaker.name,
      component: 'circuit_breaker',
      category: EventCategory.dependency,
      severity: newState == CircuitState.open
          ? EventSeverity.error
          : newState == CircuitState.halfOpen
              ? EventSeverity.warning
              : EventSeverity.info,
      description: '电路断路器状态变化: ${newState.name}',
      attributes: breaker.getStatus(),
    );

    recordEvent(event);
  }

  /// 记录延迟异常
  void recordLatencyAnomaly({
    required String service,
    required String operation,
    required Duration latency,
    required Duration threshold,
  }) {
    final event = IncidentEvent(
      id: _generateEventId(),
      timestamp: DateTime.now(),
      service: service,
      component: operation,
      category: EventCategory.latency,
      severity: latency.inMilliseconds > threshold.inMilliseconds * 3
          ? EventSeverity.critical
          : EventSeverity.warning,
      description:
          '延迟异常: ${latency.inMilliseconds}ms (阈值: ${threshold.inMilliseconds}ms)',
      duration: latency,
      attributes: {
        'latencyMs': latency.inMilliseconds,
        'thresholdMs': threshold.inMilliseconds,
        'ratio': latency.inMilliseconds / threshold.inMilliseconds,
      },
    );

    recordEvent(event);
  }

  void _cleanupOldEvents() {
    final cutoff = DateTime.now().subtract(_eventRetention);
    while (_eventHistory.isNotEmpty &&
        _eventHistory.first.timestamp.isBefore(cutoff)) {
      _eventHistory.removeFirst();
    }
  }

  void _checkForAnalysisTrigger(IncidentEvent event) {
    if (event.severity == EventSeverity.critical ||
        event.severity == EventSeverity.error) {
      // 检查最近是否有相关事件聚集
      final recentEvents = _getRecentEvents(correlationWindow);
      if (recentEvents.length >= minEventsForAnalysis) {
        // 触发自动分析
        analyze(recentEvents);
      }
    }
  }

  /// 执行根因分析
  Future<RootCauseAnalysisResult> analyze([List<IncidentEvent>? events]) async {
    final stopwatch = Stopwatch()..start();
    final targetEvents = events ?? _getRecentEvents(correlationWindow);

    _logger.info('开始根因分析，事件数量: ${targetEvents.length}');

    if (targetEvents.isEmpty) {
      return RootCauseAnalysisResult(
        incidentId: _generateEventId(),
        analyzedAt: DateTime.now(),
        analysisTime: stopwatch.elapsed,
        hypotheses: [],
        correlatedEvents: [],
        timeline: {},
        summary: '没有可分析的事件',
      );
    }

    // 1. 事件聚类和关联
    final correlatedEvents = _correlateEvents(targetEvents);

    // 2. 构建时间线
    final timeline = _buildTimeline(correlatedEvents);

    // 3. 识别故障模式
    final patterns = FailurePatternRecognizer.matchPatterns(correlatedEvents);

    // 4. 分析依赖链
    final dependencyAnalysis = _analyzeDependencyChain(correlatedEvents);

    // 5. 生成假设
    final hypotheses = _generateHypotheses(
      correlatedEvents,
      patterns,
      dependencyAnalysis,
    );

    // 6. 对假设进行排序
    hypotheses.sort((a, b) => b.confidence.compareTo(a.confidence));

    stopwatch.stop();

    final result = RootCauseAnalysisResult(
      incidentId: _generateEventId(),
      analyzedAt: DateTime.now(),
      analysisTime: stopwatch.elapsed,
      hypotheses: hypotheses,
      correlatedEvents: correlatedEvents,
      timeline: timeline,
      summary: _generateSummary(hypotheses, correlatedEvents),
    );

    // 缓存结果
    _analysisCache[result.incidentId] = result;

    // 回调
    onAnalysisComplete?.call(result);

    MetricsCollector.instance.increment('rca_analyses_completed');
    MetricsCollector.instance.observeHistogram(
      'rca_analysis_duration_seconds',
      stopwatch.elapsed.inMilliseconds / 1000,
    );

    return result;
  }

  List<IncidentEvent> _getRecentEvents(Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return _eventHistory
        .where((e) => e.timestamp.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  List<IncidentEvent> _correlateEvents(List<IncidentEvent> events) {
    if (events.length <= 1) return events;

    // 基于时间和服务进行聚类
    final clusters = <List<IncidentEvent>>[];
    var currentCluster = <IncidentEvent>[events.first];

    for (int i = 1; i < events.length; i++) {
      final prev = events[i - 1];
      final curr = events[i];

      // 时间间隔小于30秒或相同服务视为相关
      final timeDiff = curr.timestamp.difference(prev.timestamp);
      final sameService = curr.service == prev.service;

      if (timeDiff.inSeconds < 30 || sameService) {
        currentCluster.add(curr);
      } else {
        if (currentCluster.length >= 2) {
          clusters.add(currentCluster);
        }
        currentCluster = [curr];
      }
    }

    if (currentCluster.length >= 2) {
      clusters.add(currentCluster);
    }

    // 返回最大的相关事件簇
    if (clusters.isEmpty) return events;
    clusters.sort((a, b) => b.length.compareTo(a.length));
    return clusters.first;
  }

  Map<String, dynamic> _buildTimeline(List<IncidentEvent> events) {
    if (events.isEmpty) return {};

    final sorted = List<IncidentEvent>.from(events)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final timeline = <String, dynamic>{
      'startTime': sorted.first.timestamp.toIso8601String(),
      'endTime': sorted.last.timestamp.toIso8601String(),
      'durationMs':
          sorted.last.timestamp.difference(sorted.first.timestamp).inMilliseconds,
      'events': sorted
          .map((e) => {
                'time': e.timestamp.toIso8601String(),
                'relativeMs':
                    e.timestamp.difference(sorted.first.timestamp).inMilliseconds,
                'service': e.service,
                'category': e.category.name,
                'severity': e.severity.name,
                'description': e.description,
              })
          .toList(),
    };

    // 识别关键时间点
    final keyMoments = <Map<String, dynamic>>[];
    for (final event in sorted) {
      if (event.severity == EventSeverity.critical ||
          event.severity == EventSeverity.error) {
        keyMoments.add({
          'time': event.timestamp.toIso8601String(),
          'type': 'severity_spike',
          'event': event.description,
        });
      }
    }
    timeline['keyMoments'] = keyMoments;

    return timeline;
  }

  Map<String, dynamic> _analyzeDependencyChain(List<IncidentEvent> events) {
    final affectedServices = events.map((e) => e.service).toSet();
    final analysis = <String, dynamic>{
      'affectedServices': affectedServices.toList(),
    };

    // 查找可能的传播路径
    final propagationPaths = <List<String>>[];

    for (final service in affectedServices) {
      final node = _dependencyGraph[service];
      if (node == null) continue;

      // 检查上游依赖是否也受影响
      for (final upstream in node.upstreamDependencies) {
        if (affectedServices.contains(upstream)) {
          propagationPaths.add([upstream, service]);
        }
      }
    }

    analysis['propagationPaths'] = propagationPaths;

    // 识别可能的源头服务
    final potentialSources = affectedServices.where((s) {
      final node = _dependencyGraph[s];
      if (node == null) return true;
      // 如果上游依赖都正常，则可能是源头
      return !node.upstreamDependencies.any(affectedServices.contains);
    }).toList();

    analysis['potentialSources'] = potentialSources;

    return analysis;
  }

  List<RootCauseHypothesis> _generateHypotheses(
    List<IncidentEvent> events,
    List<MapEntry<String, double>> patterns,
    Map<String, dynamic> dependencyAnalysis,
  ) {
    final hypotheses = <RootCauseHypothesis>[];

    // 基于故障模式生成假设
    for (final pattern in patterns.take(3)) {
      final actions = FailurePatternRecognizer.getSuggestedActions(pattern.key);
      hypotheses.add(RootCauseHypothesis(
        id: 'pattern_${pattern.key}',
        description: _getPatternDescription(pattern.key),
        confidence: pattern.value,
        category: _getPatternCategory(pattern.key),
        supportingEvidence: events
            .where((e) => _eventMatchesPattern(e, pattern.key))
            .map((e) => e.description)
            .take(5)
            .toList(),
        suggestedActions: actions,
        metadata: {'pattern': pattern.key},
      ));
    }

    // 基于依赖分析生成假设
    final sources = dependencyAnalysis['potentialSources'] as List? ?? [];
    if (sources.isNotEmpty) {
      final sourceService = sources.first;
      final sourceEvents = events.where((e) => e.service == sourceService);

      if (sourceEvents.isNotEmpty) {
        hypotheses.add(RootCauseHypothesis(
          id: 'dependency_$sourceService',
          description: '服务 $sourceService 可能是故障源头',
          confidence: 0.7,
          category: EventCategory.dependency,
          supportingEvidence: [
            '首个受影响的服务',
            '位于依赖链顶端',
            ...sourceEvents.map((e) => e.description).take(3),
          ],
          suggestedActions: [
            '检查 $sourceService 的日志和指标',
            '验证 $sourceService 的外部依赖',
            '检查最近的配置或代码变更',
          ],
          metadata: {'sourceService': sourceService},
        ));
      }
    }

    // 基于错误类型生成假设
    final categoryCount = <EventCategory, int>{};
    for (final event in events) {
      categoryCount[event.category] =
          (categoryCount[event.category] ?? 0) + 1;
    }

    final dominantCategory = categoryCount.entries
        .reduce((a, b) => a.value > b.value ? a : b);

    if (dominantCategory.value >= events.length * 0.5) {
      hypotheses.add(RootCauseHypothesis(
        id: 'category_${dominantCategory.key.name}',
        description: _getCategoryDescription(dominantCategory.key),
        confidence: dominantCategory.value / events.length,
        category: dominantCategory.key,
        supportingEvidence: [
          '${dominantCategory.value}/${events.length} 事件属于此类别',
        ],
        suggestedActions: _getCategoryActions(dominantCategory.key),
      ));
    }

    return hypotheses;
  }

  String _generateSummary(
    List<RootCauseHypothesis> hypotheses,
    List<IncidentEvent> events,
  ) {
    if (hypotheses.isEmpty) {
      return '分析完成，但没有找到明确的根因假设。';
    }

    final primary = hypotheses.first;
    final buffer = StringBuffer();

    buffer.write('检测到 ${events.length} 个相关事件。');

    if (primary.isHighConfidence) {
      buffer.write('高置信度根因: ${primary.description} ');
      buffer.write('(${(primary.confidence * 100).toStringAsFixed(0)}%)。');
    } else if (primary.isMediumConfidence) {
      buffer.write('可能的根因: ${primary.description} ');
      buffer.write('(需要进一步调查)。');
    } else {
      buffer.write('低置信度假设，建议手动调查。');
    }

    if (primary.suggestedActions.isNotEmpty) {
      buffer.write(' 建议首先: ${primary.suggestedActions.first}');
    }

    return buffer.toString();
  }

  EventCategory _categorizeError(Object error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('socket')) {
      return EventCategory.network;
    }

    if (errorStr.contains('memory') ||
        errorStr.contains('heap') ||
        errorStr.contains('oom')) {
      return EventCategory.resource;
    }

    if (errorStr.contains('rate') || errorStr.contains('limit')) {
      return EventCategory.capacity;
    }

    if (errorStr.contains('auth') ||
        errorStr.contains('permission') ||
        errorStr.contains('forbidden')) {
      return EventCategory.security;
    }

    if (errorStr.contains('config') || errorStr.contains('setting')) {
      return EventCategory.configuration;
    }

    return EventCategory.error;
  }

  EventSeverity _severityFromError(Object error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('fatal') ||
        errorStr.contains('critical') ||
        errorStr.contains('crash')) {
      return EventSeverity.critical;
    }

    if (error is Error) {
      return EventSeverity.critical;
    }

    return EventSeverity.error;
  }

  String _getPatternDescription(String pattern) {
    switch (pattern) {
      case 'cascading_failure':
        return '级联故障: 上游服务故障导致下游服务连锁失败';
      case 'resource_exhaustion':
        return '资源耗尽: 系统资源(内存/CPU/连接)逐渐耗尽';
      case 'network_partition':
        return '网络分区: 网络连接问题导致服务不可达';
      case 'thundering_herd':
        return '惊群效应: 大量请求同时涌入导致系统过载';
      case 'configuration_drift':
        return '配置漂移: 配置不一致或错误导致异常';
      case 'dependency_failure':
        return '依赖故障: 外部服务或组件失败';
      case 'memory_leak':
        return '内存泄漏: 内存使用持续增长未释放';
      case 'connection_pool_exhaustion':
        return '连接池耗尽: 数据库/HTTP连接池资源不足';
      default:
        return '未知模式: $pattern';
    }
  }

  EventCategory _getPatternCategory(String pattern) {
    switch (pattern) {
      case 'cascading_failure':
      case 'dependency_failure':
        return EventCategory.dependency;
      case 'resource_exhaustion':
      case 'memory_leak':
      case 'connection_pool_exhaustion':
        return EventCategory.resource;
      case 'network_partition':
        return EventCategory.network;
      case 'thundering_herd':
        return EventCategory.capacity;
      case 'configuration_drift':
        return EventCategory.configuration;
      default:
        return EventCategory.error;
    }
  }

  bool _eventMatchesPattern(IncidentEvent event, String pattern) {
    switch (pattern) {
      case 'cascading_failure':
      case 'dependency_failure':
        return event.category == EventCategory.dependency ||
            event.category == EventCategory.error;
      case 'resource_exhaustion':
      case 'memory_leak':
      case 'connection_pool_exhaustion':
        return event.category == EventCategory.resource;
      case 'network_partition':
        return event.category == EventCategory.network;
      case 'thundering_herd':
        return event.category == EventCategory.capacity ||
            event.category == EventCategory.latency;
      case 'configuration_drift':
        return event.category == EventCategory.configuration;
      default:
        return false;
    }
  }

  String _getCategoryDescription(EventCategory category) {
    switch (category) {
      case EventCategory.network:
        return '网络相关问题主导: 连接超时或网络故障';
      case EventCategory.latency:
        return '延迟问题主导: 请求处理时间异常增加';
      case EventCategory.error:
        return '应用错误主导: 代码或逻辑问题';
      case EventCategory.resource:
        return '资源问题主导: 系统资源不足或泄漏';
      case EventCategory.dependency:
        return '依赖问题主导: 外部服务或组件故障';
      case EventCategory.configuration:
        return '配置问题主导: 配置错误或不一致';
      case EventCategory.security:
        return '安全问题主导: 认证或授权失败';
      case EventCategory.capacity:
        return '容量问题主导: 系统负载超出承受能力';
    }
  }

  List<String> _getCategoryActions(EventCategory category) {
    switch (category) {
      case EventCategory.network:
        return ['检查网络连接', '验证DNS解析', '检查防火墙规则'];
      case EventCategory.latency:
        return ['分析慢查询', '检查资源竞争', '优化热点代码路径'];
      case EventCategory.error:
        return ['检查错误日志', '验证输入数据', '回滚最近变更'];
      case EventCategory.resource:
        return ['监控资源使用', '增加资源配额', '检查资源泄漏'];
      case EventCategory.dependency:
        return ['检查依赖服务状态', '启用降级策略', '验证服务契约'];
      case EventCategory.configuration:
        return ['验证配置一致性', '检查环境变量', '对比生产配置'];
      case EventCategory.security:
        return ['检查认证凭据', '验证权限设置', '审查安全日志'];
      case EventCategory.capacity:
        return ['启用限流保护', '增加实例数量', '优化资源分配'];
    }
  }

  String _generateEventId() =>
      'evt_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';

  /// 获取分析历史
  RootCauseAnalysisResult? getAnalysis(String incidentId) =>
      _analysisCache[incidentId];

  /// 获取最近的分析结果
  List<RootCauseAnalysisResult> getRecentAnalyses({int limit = 10}) {
    final sorted = _analysisCache.values.toList()
      ..sort((a, b) => b.analyzedAt.compareTo(a.analyzedAt));
    return sorted.take(limit).toList();
  }

  /// 获取状态
  Map<String, dynamic> getStatus() => {
        'eventHistorySize': _eventHistory.length,
        'registeredDependencies': _dependencyGraph.keys.toList(),
        'cachedAnalyses': _analysisCache.length,
        'recentAnalysis': _analysisCache.isNotEmpty
            ? getRecentAnalyses(limit: 1).first.toJson()
            : null,
      };

  void clear() {
    _eventHistory.clear();
    _analysisCache.clear();
  }
}

/// 全局根因分析器单例
class RootCauseAnalyzerRegistry {
  static final RootCauseAnalyzerRegistry _instance = RootCauseAnalyzerRegistry._();
  static RootCauseAnalyzerRegistry get instance => _instance;

  RootCauseAnalyzerRegistry._();

  RootCauseAnalyzer? _analyzer;

  RootCauseAnalyzer get analyzer {
    _analyzer ??= RootCauseAnalyzer();
    return _analyzer!;
  }

  void configure({
    Duration eventRetention = const Duration(hours: 6),
    Duration correlationWindow = const Duration(minutes: 5),
    void Function(RootCauseAnalysisResult)? onAnalysisComplete,
  }) {
    _analyzer = RootCauseAnalyzer(
      eventRetention: eventRetention,
      correlationWindow: correlationWindow,
      onAnalysisComplete: onAnalysisComplete,
    );
  }
}
