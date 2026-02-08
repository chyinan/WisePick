import 'dart:async';
import 'dart:math' as math;

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';

/// 故障类型
enum FaultType {
  latency, // 延迟注入
  error, // 错误注入
  timeout, // 超时模拟
  corruption, // 数据损坏
  partition, // 网络分区
  resourceExhaustion, // 资源耗尽
  rateLimitExceeded, // 限流超限
  circuitOpen, // 断路器打开
}

/// 故障注入配置
class FaultConfig {
  final FaultType type;
  final double probability; // 0.0 - 1.0
  final Duration? latencyDuration;
  final String? errorMessage;
  final String? targetService;
  final String? targetOperation;
  final Duration? duration; // 故障持续时间

  const FaultConfig({
    required this.type,
    this.probability = 1.0,
    this.latencyDuration,
    this.errorMessage,
    this.targetService,
    this.targetOperation,
    this.duration,
  });

  bool matchesTarget(String service, String operation) {
    if (targetService != null && targetService != service) return false;
    if (targetOperation != null && targetOperation != operation) return false;
    return true;
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'probability': probability,
        if (latencyDuration != null) 'latencyMs': latencyDuration!.inMilliseconds,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (targetService != null) 'targetService': targetService,
        if (targetOperation != null) 'targetOperation': targetOperation,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
      };
}

/// 混沌实验定义
class ChaosExperiment {
  final String id;
  final String name;
  final String description;
  final List<FaultConfig> faults;
  final Duration duration;
  final ExperimentState state;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Map<String, dynamic> hypothesis;
  final Map<String, dynamic> results;

  ChaosExperiment({
    required this.id,
    required this.name,
    required this.description,
    required this.faults,
    required this.duration,
    this.state = ExperimentState.pending,
    this.startedAt,
    this.endedAt,
    this.hypothesis = const {},
    this.results = const {},
  });

  ChaosExperiment copyWith({
    ExperimentState? state,
    DateTime? startedAt,
    DateTime? endedAt,
    Map<String, dynamic>? results,
  }) {
    return ChaosExperiment(
      id: id,
      name: name,
      description: description,
      faults: faults,
      duration: duration,
      state: state ?? this.state,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      hypothesis: hypothesis,
      results: results ?? this.results,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'state': state.name,
        'durationMs': duration.inMilliseconds,
        'faults': faults.map((f) => f.toJson()).toList(),
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        'hypothesis': hypothesis,
        'results': results,
      };
}

enum ExperimentState {
  pending,
  running,
  completed,
  aborted,
  failed,
}

/// 混沌实验结果
class ExperimentResult {
  final String experimentId;
  final bool success;
  final String summary;
  final Map<String, dynamic> metrics;
  final List<String> observations;
  final List<String> recommendations;
  final Duration totalDuration;

  const ExperimentResult({
    required this.experimentId,
    required this.success,
    required this.summary,
    this.metrics = const {},
    this.observations = const [],
    this.recommendations = const [],
    required this.totalDuration,
  });

  Map<String, dynamic> toJson() => {
        'experimentId': experimentId,
        'success': success,
        'summary': summary,
        'metrics': metrics,
        'observations': observations,
        'recommendations': recommendations,
        'totalDurationMs': totalDuration.inMilliseconds,
      };
}

/// 故障注入异常
class InjectedFaultException implements Exception {
  final FaultType type;
  final String message;
  final String? experimentId;

  InjectedFaultException({
    required this.type,
    required this.message,
    this.experimentId,
  });

  @override
  String toString() => 'InjectedFault(${type.name}): $message';
}

/// 故障注入器
class FaultInjector {
  final _random = math.Random();
  final List<FaultConfig> _activeFaults = [];
  final Map<String, DateTime> _faultExpiry = {};
  bool _enabled = false;

  bool get isEnabled => _enabled;
  List<FaultConfig> get activeFaults => List.unmodifiable(_activeFaults);

  /// 启用故障注入
  void enable() => _enabled = true;

  /// 禁用故障注入
  void disable() {
    _enabled = false;
    _activeFaults.clear();
    _faultExpiry.clear();
  }

  /// 注入故障
  void injectFault(FaultConfig fault) {
    if (!_enabled) {
      throw StateError('Fault injector is not enabled');
    }

    _activeFaults.add(fault);

    if (fault.duration != null) {
      final faultId = 'fault_${DateTime.now().millisecondsSinceEpoch}';
      _faultExpiry[faultId] = DateTime.now().add(fault.duration!);
    }

    MetricsCollector.instance.increment(
      'chaos_fault_injected',
      labels: MetricLabels().add('type', fault.type.name),
    );
  }

  /// 移除故障
  void removeFault(FaultType type) {
    _activeFaults.removeWhere((f) => f.type == type);
  }

  /// 清除所有故障
  void clearFaults() {
    _activeFaults.clear();
    _faultExpiry.clear();
  }

  /// 清理过期故障
  void _cleanupExpired() {
    final now = DateTime.now();
    _faultExpiry.removeWhere((_, expiry) => expiry.isBefore(now));

    // 这里简化处理：如果没有带过期时间的故障，保留所有故障
    // 实际实现中需要更精确地跟踪每个故障
  }

  /// 在操作前检查并应用故障
  Future<void> maybeInjectFault({
    required String service,
    required String operation,
    String? experimentId,
  }) async {
    if (!_enabled) return;

    _cleanupExpired();

    for (final fault in _activeFaults) {
      if (!fault.matchesTarget(service, operation)) continue;

      // 根据概率决定是否注入
      if (_random.nextDouble() > fault.probability) continue;

      await _applyFault(fault, service, operation, experimentId);
    }
  }

  Future<void> _applyFault(
    FaultConfig fault,
    String service,
    String operation,
    String? experimentId,
  ) async {
    MetricsCollector.instance.increment(
      'chaos_fault_applied',
      labels: MetricLabels()
          .add('type', fault.type.name)
          .add('service', service)
          .add('operation', operation),
    );

    switch (fault.type) {
      case FaultType.latency:
        final delay = fault.latencyDuration ?? const Duration(seconds: 2);
        await Future.delayed(delay);
        break;

      case FaultType.error:
        throw InjectedFaultException(
          type: fault.type,
          message: fault.errorMessage ?? 'Injected error for $service.$operation',
          experimentId: experimentId,
        );

      case FaultType.timeout:
        // 延迟足够长的时间来触发超时
        final delay = fault.latencyDuration ?? const Duration(minutes: 5);
        await Future.delayed(delay);
        break;

      case FaultType.corruption:
        // 由调用方处理数据损坏场景
        throw InjectedFaultException(
          type: fault.type,
          message: fault.errorMessage ?? 'Data corruption simulated',
          experimentId: experimentId,
        );

      case FaultType.partition:
        throw InjectedFaultException(
          type: fault.type,
          message: 'Network partition simulated for $service',
          experimentId: experimentId,
        );

      case FaultType.resourceExhaustion:
        throw InjectedFaultException(
          type: fault.type,
          message: 'Resource exhaustion simulated',
          experimentId: experimentId,
        );

      case FaultType.rateLimitExceeded:
        throw InjectedFaultException(
          type: fault.type,
          message: 'Rate limit exceeded (simulated)',
          experimentId: experimentId,
        );

      case FaultType.circuitOpen:
        throw InjectedFaultException(
          type: fault.type,
          message: 'Circuit breaker open (simulated)',
          experimentId: experimentId,
        );
    }
  }
}

/// 混沌实验运行器
class ChaosExperimentRunner {
  final ModuleLogger _logger;
  final FaultInjector _injector = FaultInjector();
  final Map<String, ChaosExperiment> _experiments = {};
  ChaosExperiment? _currentExperiment;
  Timer? _experimentTimer;

  // 回调
  final void Function(ChaosExperiment)? onExperimentStart;
  final void Function(ChaosExperiment, ExperimentResult)? onExperimentEnd;
  final void Function(String)? onSafetyViolation;

  // 安全约束
  final Duration maxExperimentDuration;
  final double maxErrorRateThreshold;
  final int maxConcurrentFaults;

  ChaosExperimentRunner({
    this.onExperimentStart,
    this.onExperimentEnd,
    this.onSafetyViolation,
    this.maxExperimentDuration = const Duration(minutes: 30),
    this.maxErrorRateThreshold = 0.5,
    this.maxConcurrentFaults = 3,
  }) : _logger = AppLogger.instance.module('ChaosExperiment');

  FaultInjector get injector => _injector;
  ChaosExperiment? get currentExperiment => _currentExperiment;
  bool get isRunning => _currentExperiment?.state == ExperimentState.running;

  /// 注册实验
  void registerExperiment(ChaosExperiment experiment) {
    _experiments[experiment.id] = experiment;
    _logger.info('Registered experiment: ${experiment.name}');
  }

  /// 启动实验
  Future<void> startExperiment(String experimentId) async {
    final experiment = _experiments[experimentId];
    if (experiment == null) {
      throw ArgumentError('Experiment not found: $experimentId');
    }

    if (isRunning) {
      throw StateError('Another experiment is already running');
    }

    // 验证安全约束
    if (experiment.duration > maxExperimentDuration) {
      throw StateError(
        'Experiment duration exceeds maximum allowed: ${maxExperimentDuration.inMinutes}min',
      );
    }

    if (experiment.faults.length > maxConcurrentFaults) {
      throw StateError(
        'Too many concurrent faults: ${experiment.faults.length} > $maxConcurrentFaults',
      );
    }

    // 更新状态
    _currentExperiment = experiment.copyWith(
      state: ExperimentState.running,
      startedAt: DateTime.now(),
    );
    _experiments[experimentId] = _currentExperiment!;

    _logger.warning('Starting chaos experiment: ${experiment.name}');

    // 启用注入器并添加故障
    _injector.enable();
    for (final fault in experiment.faults) {
      _injector.injectFault(fault);
    }

    // 回调
    onExperimentStart?.call(_currentExperiment!);

    // 设置自动结束定时器
    _experimentTimer = Timer(experiment.duration, () {
      stopExperiment('Duration completed');
    });

    // 启动安全监控
    _startSafetyMonitor();

    MetricsCollector.instance.increment('chaos_experiment_started');
  }

  /// 停止实验
  Future<ExperimentResult> stopExperiment([String reason = 'Manual stop']) async {
    _experimentTimer?.cancel();

    if (_currentExperiment == null) {
      return ExperimentResult(
        experimentId: 'none',
        success: false,
        summary: 'No experiment running',
        totalDuration: Duration.zero,
      );
    }

    final experiment = _currentExperiment!;
    final duration = DateTime.now().difference(experiment.startedAt!);

    _injector.clearFaults();
    _injector.disable();

    // 收集结果
    final result = _collectResults(experiment, duration, reason);

    // 更新状态
    _currentExperiment = experiment.copyWith(
      state: reason.contains('Safety') ? ExperimentState.aborted : ExperimentState.completed,
      endedAt: DateTime.now(),
      results: result.toJson(),
    );
    _experiments[experiment.id] = _currentExperiment!;

    _logger.info('Experiment stopped: ${experiment.name}, reason: $reason');

    // 回调
    onExperimentEnd?.call(_currentExperiment!, result);

    _currentExperiment = null;

    MetricsCollector.instance.increment(
      'chaos_experiment_completed',
      labels: MetricLabels().add('result', result.success ? 'success' : 'failure'),
    );

    return result;
  }

  /// 紧急中止
  Future<void> emergencyAbort() async {
    _logger.error('EMERGENCY ABORT initiated');
    _injector.disable();
    _experimentTimer?.cancel();

    if (_currentExperiment != null) {
      await stopExperiment('Emergency abort');
    }

    MetricsCollector.instance.increment('chaos_emergency_abort');
  }

  ExperimentResult _collectResults(
    ChaosExperiment experiment,
    Duration duration,
    String stopReason,
  ) {
    final observations = <String>[];
    final recommendations = <String>[];
    final metrics = <String, dynamic>{};

    // 收集指标
    final allMetrics = MetricsCollector.instance.getAllMetrics();
    metrics['metricsSnapshot'] = allMetrics;

    // 分析结果
    bool success = true;

    if (stopReason.contains('Safety violation')) {
      success = false;
      observations.add('实验因安全违规而终止');
      recommendations.add('检查系统弹性配置');
    }

    if (stopReason.contains('Duration completed')) {
      observations.add('实验按计划完成');
    }

    // 根据故障类型添加观察
    for (final fault in experiment.faults) {
      switch (fault.type) {
        case FaultType.latency:
          observations.add('延迟注入测试完成');
          recommendations.add('验证超时配置是否合理');
          break;
        case FaultType.error:
          observations.add('错误注入测试完成');
          recommendations.add('验证错误处理和重试逻辑');
          break;
        case FaultType.timeout:
          observations.add('超时模拟测试完成');
          recommendations.add('检查断路器是否正确触发');
          break;
        case FaultType.partition:
          observations.add('网络分区模拟完成');
          recommendations.add('验证降级策略有效性');
          break;
        default:
          observations.add('故障注入测试: ${fault.type.name}');
      }
    }

    return ExperimentResult(
      experimentId: experiment.id,
      success: success,
      summary: success
          ? '实验成功完成，系统展现了预期的弹性行为'
          : '实验发现潜在问题，请查看详细观察和建议',
      metrics: metrics,
      observations: observations,
      recommendations: recommendations,
      totalDuration: duration,
    );
  }

  void _startSafetyMonitor() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentExperiment == null) {
        timer.cancel();
        return;
      }

      // 检查错误率
      final summary = MetricsCollector.instance.getSummary();
      final errorRateStr = summary['requests']?['errorRate'] as String? ?? '0%';
      final errorRate =
          double.tryParse(errorRateStr.replaceAll('%', '')) ?? 0 / 100;

      if (errorRate > maxErrorRateThreshold) {
        onSafetyViolation?.call('Error rate exceeded: $errorRateStr');
        stopExperiment('Safety violation: Error rate exceeded');
        timer.cancel();
      }
    });
  }

  /// 获取实验
  ChaosExperiment? getExperiment(String id) => _experiments[id];

  /// 获取所有实验
  List<ChaosExperiment> getAllExperiments() => _experiments.values.toList();

  /// 获取状态
  Map<String, dynamic> getStatus() => {
        'isRunning': isRunning,
        'currentExperiment': _currentExperiment?.toJson(),
        'injectorEnabled': _injector.isEnabled,
        'activeFaults': _injector.activeFaults.map((f) => f.toJson()).toList(),
        'registeredExperiments': _experiments.keys.toList(),
      };
}

/// 预置混沌实验场景
class ChaosScenarios {
  /// 延迟风暴测试
  static ChaosExperiment latencyStorm({
    required String targetService,
    Duration latency = const Duration(seconds: 3),
    double probability = 0.5,
    Duration duration = const Duration(minutes: 5),
  }) {
    return ChaosExperiment(
      id: 'latency_storm_${DateTime.now().millisecondsSinceEpoch}',
      name: '延迟风暴测试',
      description: '模拟延迟风暴，测试系统在高延迟下的行为',
      faults: [
        FaultConfig(
          type: FaultType.latency,
          probability: probability,
          latencyDuration: latency,
          targetService: targetService,
          duration: duration,
        ),
      ],
      duration: duration,
      hypothesis: {
        'expected': '系统应该触发超时保护和断路器',
        'acceptableDegradation': '响应时间增加但服务不应崩溃',
      },
    );
  }

  /// 随机错误注入
  static ChaosExperiment randomErrors({
    required String targetService,
    double probability = 0.2,
    Duration duration = const Duration(minutes: 5),
  }) {
    return ChaosExperiment(
      id: 'random_errors_${DateTime.now().millisecondsSinceEpoch}',
      name: '随机错误注入',
      description: '随机注入错误，测试错误处理和重试逻辑',
      faults: [
        FaultConfig(
          type: FaultType.error,
          probability: probability,
          errorMessage: '混沌注入随机错误',
          targetService: targetService,
          duration: duration,
        ),
      ],
      duration: duration,
      hypothesis: {
        'expected': '重试机制应该能够恢复大部分请求',
        'acceptableErrorRate': '最终错误率应低于${probability * 0.5}',
      },
    );
  }

  /// 依赖服务故障
  static ChaosExperiment dependencyFailure({
    required String dependencyService,
    Duration duration = const Duration(minutes: 5),
  }) {
    return ChaosExperiment(
      id: 'dependency_failure_${DateTime.now().millisecondsSinceEpoch}',
      name: '依赖服务故障测试',
      description: '模拟依赖服务完全不可用',
      faults: [
        FaultConfig(
          type: FaultType.partition,
          probability: 1.0,
          targetService: dependencyService,
          duration: duration,
        ),
      ],
      duration: duration,
      hypothesis: {
        'expected': '断路器应该打开，降级策略应该生效',
        'acceptableBehavior': '返回缓存数据或优雅降级响应',
      },
    );
  }

  /// 资源耗尽测试
  static ChaosExperiment resourceExhaustion({
    required String targetService,
    Duration duration = const Duration(minutes: 3),
  }) {
    return ChaosExperiment(
      id: 'resource_exhaustion_${DateTime.now().millisecondsSinceEpoch}',
      name: '资源耗尽测试',
      description: '模拟资源耗尽场景',
      faults: [
        FaultConfig(
          type: FaultType.resourceExhaustion,
          probability: 1.0,
          targetService: targetService,
          duration: duration,
        ),
      ],
      duration: duration,
      hypothesis: {
        'expected': '系统应该实施负载卸载和背压',
        'acceptableBehavior': '拒绝新请求但不崩溃',
      },
    );
  }

  /// 级联故障测试
  static ChaosExperiment cascadingFailure({
    required List<String> serviceChain,
    Duration duration = const Duration(minutes: 5),
  }) {
    final faults = <FaultConfig>[];
    for (int i = 0; i < serviceChain.length; i++) {
      faults.add(FaultConfig(
        type: FaultType.error,
        probability: 0.3 + (i * 0.1), // 越后端概率越高
        targetService: serviceChain[i],
        duration: duration,
      ));
    }

    return ChaosExperiment(
      id: 'cascading_failure_${DateTime.now().millisecondsSinceEpoch}',
      name: '级联故障测试',
      description: '测试级联故障场景下的隔离能力',
      faults: faults,
      duration: duration,
      hypothesis: {
        'expected': '隔板和断路器应该防止故障传播',
        'serviceChain': serviceChain,
      },
    );
  }

  /// 综合弹性测试
  static ChaosExperiment comprehensiveResilience({
    required String targetService,
    Duration duration = const Duration(minutes: 10),
  }) {
    return ChaosExperiment(
      id: 'comprehensive_${DateTime.now().millisecondsSinceEpoch}',
      name: '综合弹性测试',
      description: '综合测试所有弹性机制',
      faults: [
        FaultConfig(
          type: FaultType.latency,
          probability: 0.3,
          latencyDuration: const Duration(seconds: 2),
          targetService: targetService,
          duration: duration,
        ),
        FaultConfig(
          type: FaultType.error,
          probability: 0.15,
          targetService: targetService,
          duration: duration,
        ),
        FaultConfig(
          type: FaultType.rateLimitExceeded,
          probability: 0.1,
          targetService: targetService,
          duration: duration,
        ),
      ],
      duration: duration,
      hypothesis: {
        'expected': '所有弹性机制协同工作',
        'acceptableAvailability': '>=95%',
      },
    );
  }
}

/// 全局混沌工程管理器
class ChaosEngineeringManager {
  static final ChaosEngineeringManager _instance = ChaosEngineeringManager._();
  static ChaosEngineeringManager get instance => _instance;

  ChaosEngineeringManager._();

  ChaosExperimentRunner? _runner;
  bool _chaosEnabled = false;

  bool get isEnabled => _chaosEnabled;
  ChaosExperimentRunner get runner {
    _runner ??= ChaosExperimentRunner();
    return _runner!;
  }

  /// 启用混沌工程 (生产环境应谨慎)
  void enable() {
    _chaosEnabled = true;
    AppLogger.instance
        .module('ChaosEngineering')
        .warning('Chaos engineering ENABLED');
  }

  /// 禁用混沌工程
  void disable() {
    _chaosEnabled = false;
    runner.emergencyAbort();
    AppLogger.instance
        .module('ChaosEngineering')
        .info('Chaos engineering disabled');
  }

  /// 在操作中注入故障点
  Future<void> faultPoint({
    required String service,
    required String operation,
  }) async {
    if (!_chaosEnabled) return;
    if (!runner.isRunning) return;

    await runner.injector.maybeInjectFault(
      service: service,
      operation: operation,
      experimentId: runner.currentExperiment?.id,
    );
  }

  Map<String, dynamic> getStatus() => {
        'enabled': _chaosEnabled,
        'runner': runner.getStatus(),
      };
}
