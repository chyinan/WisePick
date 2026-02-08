import 'dart:async';

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';
import '../observability/health_check.dart';
import '../resilience/circuit_breaker.dart';
import '../resilience/global_rate_limiter.dart';
import '../resilience/slo_manager.dart';
import '../resilience/auto_recovery.dart';
import '../resilience/retry_policy.dart';
import 'predictive_load_manager.dart';
import 'root_cause_analyzer.dart';
import 'resilience_strategy.dart';
import 'chaos_engineering.dart';
import 'reliability_dashboard.dart';

/// 可靠性平台配置
class ReliabilityPlatformConfig {
  /// 是否启用预测性负载管理
  final bool enablePredictiveLoad;

  /// 是否启用自动根因分析
  final bool enableRootCauseAnalysis;

  /// 是否启用混沌工程 (生产环境谨慎)
  final bool enableChaosEngineering;

  /// 是否启用仪表盘
  final bool enableDashboard;

  /// 仪表盘刷新间隔
  final RefreshInterval dashboardRefreshInterval;

  /// 是否在启动时进行健康检查
  final bool healthCheckOnStartup;

  /// 全局超时配置
  final Duration defaultTimeout;

  /// 全局重试配置
  final RetryConfig defaultRetryConfig;

  /// 全局熔断器配置
  final CircuitBreakerConfig defaultCircuitBreakerConfig;

  /// 全局限流配置
  final RateLimiterConfig defaultRateLimiterConfig;

  const ReliabilityPlatformConfig({
    this.enablePredictiveLoad = true,
    this.enableRootCauseAnalysis = true,
    this.enableChaosEngineering = false,
    this.enableDashboard = true,
    this.dashboardRefreshInterval = RefreshInterval.normal,
    this.healthCheckOnStartup = true,
    this.defaultTimeout = const Duration(seconds: 30),
    this.defaultRetryConfig = const RetryConfig(),
    this.defaultCircuitBreakerConfig = const CircuitBreakerConfig(),
    this.defaultRateLimiterConfig = const RateLimiterConfig(),
  });

  /// 开发环境配置
  static const development = ReliabilityPlatformConfig(
    enablePredictiveLoad: true,
    enableRootCauseAnalysis: true,
    enableChaosEngineering: true,
    enableDashboard: true,
    dashboardRefreshInterval: RefreshInterval.fast,
    healthCheckOnStartup: false,
  );

  /// 生产环境配置
  static const production = ReliabilityPlatformConfig(
    enablePredictiveLoad: true,
    enableRootCauseAnalysis: true,
    enableChaosEngineering: false, // 生产环境默认禁用
    enableDashboard: true,
    dashboardRefreshInterval: RefreshInterval.normal,
    healthCheckOnStartup: true,
    defaultTimeout: Duration(seconds: 60),
    defaultCircuitBreakerConfig: CircuitBreakerConfig.tolerant,
  );

  /// 测试环境配置
  static const testing = ReliabilityPlatformConfig(
    enablePredictiveLoad: false,
    enableRootCauseAnalysis: false,
    enableChaosEngineering: false,
    enableDashboard: false,
    healthCheckOnStartup: false,
    defaultTimeout: Duration(seconds: 5),
  );
}

/// 服务注册信息
class ServiceRegistration {
  final String name;
  final List<SloTarget> sloTargets;
  final CircuitBreakerConfig? circuitBreakerConfig;
  final RateLimiterConfig? rateLimiterConfig;
  final RetryConfig? retryConfig;
  final List<String> dependencies;
  final bool criticalService;

  const ServiceRegistration({
    required this.name,
    this.sloTargets = const [],
    this.circuitBreakerConfig,
    this.rateLimiterConfig,
    this.retryConfig,
    this.dependencies = const [],
    this.criticalService = false,
  });
}

/// 可靠性平台状态
enum PlatformState {
  uninitialized,
  initializing,
  running,
  degraded,
  shuttingDown,
  stopped,
}

/// 云原生自愈可靠性平台
///
/// 整合所有可靠性组件，提供统一的平台级服务
class ReliabilityPlatform {
  static final ReliabilityPlatform _instance = ReliabilityPlatform._();
  static ReliabilityPlatform get instance => _instance;

  ReliabilityPlatform._();

  final ModuleLogger _logger = AppLogger.instance.module('ReliabilityPlatform');

  late ReliabilityPlatformConfig _config;
  PlatformState _state = PlatformState.uninitialized;
  final Map<String, ServiceRegistration> _registeredServices = {};
  final Map<String, StrategyPipeline> _servicePipelines = {};

  // 核心组件
  late final RootCauseAnalyzer _rootCauseAnalyzer;
  late final ReliabilityDashboard _dashboard;

  // 回调
  void Function(PlatformState, PlatformState)? onStateChange;
  void Function(String, Object, StackTrace?)? onGlobalError;
  void Function(RootCauseAnalysisResult)? onRootCauseAnalysis;

  PlatformState get state => _state;
  ReliabilityPlatformConfig get config => _config;
  bool get isRunning => _state == PlatformState.running;

  /// Reset platform to uninitialized state (for testing only)
  void resetForTesting() {
    _state = PlatformState.uninitialized;
    _registeredServices.clear();
    _servicePipelines.clear();
    CircuitBreakerRegistry.instance.clear();
    GlobalRateLimiterRegistry.instance.clear();
    StrategyRegistry.instance.clear();
  }

  /// 初始化平台
  Future<void> initialize({
    ReliabilityPlatformConfig config = const ReliabilityPlatformConfig(),
  }) async {
    if (_state != PlatformState.uninitialized) {
      _logger.warning('Platform already initialized');
      return;
    }

    _transitionTo(PlatformState.initializing);
    _config = config;

    _logger.info('Initializing Reliability Platform...');

    try {
      // 1. 初始化根因分析器
      if (config.enableRootCauseAnalysis) {
        _rootCauseAnalyzer = RootCauseAnalyzer(
          onAnalysisComplete: (result) {
            _logger.info('Root cause analysis completed: ${result.summary}');
            onRootCauseAnalysis?.call(result);
          },
        );
        RootCauseAnalyzerRegistry.instance.configure(
          onAnalysisComplete: onRootCauseAnalysis,
        );
      }

      // 2. 初始化仪表盘
      if (config.enableDashboard) {
        _dashboard = ReliabilityDashboard();
        _dashboard.startAutoRefresh(interval: config.dashboardRefreshInterval);
      }

      // 3. 启用混沌工程 (如果配置)
      if (config.enableChaosEngineering) {
        ChaosEngineeringManager.instance.enable();
        _logger.warning('Chaos engineering is ENABLED - use with caution');
      }

      // 4. 启动预测负载管理器
      if (config.enablePredictiveLoad) {
        PredictiveLoadManagerRegistry.instance.startAll();
      }

      // 5. 启动自动恢复
      AutoRecoveryRegistry.instance.startAllMonitoring();

      // 6. 健康检查
      if (config.healthCheckOnStartup) {
        await _performStartupHealthCheck();
      }

      _transitionTo(PlatformState.running);
      _logger.info('Reliability Platform initialized successfully');

      // 记录指标
      MetricsCollector.instance.increment('platform_initialized');

    } catch (e, stack) {
      _logger.error('Platform initialization failed', error: e, stackTrace: stack);
      _transitionTo(PlatformState.stopped);
      rethrow;
    }
  }

  /// 注册服务
  void registerService(ServiceRegistration registration) {
    if (_state != PlatformState.running && _state != PlatformState.initializing) {
      throw StateError('Platform is not running');
    }

    final name = registration.name;
    _registeredServices[name] = registration;

    _logger.info('Registering service: $name');

    // 1. 创建熔断器
    CircuitBreakerRegistry.instance.getOrCreate(
      name,
      config: registration.circuitBreakerConfig ?? _config.defaultCircuitBreakerConfig,
    );

    // 2. 创建限流器
    GlobalRateLimiterRegistry.instance.getOrCreate(
      name,
      config: registration.rateLimiterConfig ?? _config.defaultRateLimiterConfig,
    );

    // 3. 创建 SLO 管理器
    SloRegistry.instance.getOrCreate(
      name,
      targets: registration.sloTargets.isNotEmpty
          ? registration.sloTargets
          : [
              SloTarget.availability(),
              SloTarget.latency(),
              SloTarget.errorRate(),
            ],
    );

    // 4. 创建自动恢复管理器
    final recoveryManager = AutoRecoveryRegistry.instance.getOrCreate(name);
    final circuitBreaker = CircuitBreakerRegistry.instance.get(name);
    if (circuitBreaker != null) {
      recoveryManager.addCircuitBreakerRecovery(circuitBreaker);
    }

    // 5. 创建预测负载管理器
    if (_config.enablePredictiveLoad) {
      final loadManager = PredictiveLoadManagerRegistry.instance.getOrCreate(
        name,
        onActionRequired: (action, prediction) {
          _handlePredictiveLoadAction(name, action, prediction);
        },
      );
      loadManager.startPredictionEngine();
    }

    // 6. 注册依赖关系 (用于根因分析)
    if (_config.enableRootCauseAnalysis) {
      _rootCauseAnalyzer.registerDependency(
        name,
        upstreamDependencies: registration.dependencies,
      );
    }

    // 7. 创建策略管道
    _createServicePipeline(registration);

    // 8. 注册到仪表盘
    if (_config.enableDashboard) {
      _dashboard.registerService(name);
    }

    // 9. 注册健康检查
    _registerServiceHealthCheck(registration);

    _logger.info('Service registered: $name');
  }

  void _createServicePipeline(ServiceRegistration registration) {
    final pipeline = StrategyRegistry.instance.createDefault(
      registration.name,
      timeout: _config.defaultTimeout,
      maxConcurrent: 50,
      circuitBreaker: CircuitBreakerRegistry.instance.get(registration.name),
      rateLimiter: GlobalRateLimiterRegistry.instance.get(registration.name),
    );

    // 添加重试策略
    pipeline.addStrategy(RetryStrategy(
      retryExecutor: RetryExecutor(
        config: registration.retryConfig ?? _config.defaultRetryConfig,
      ),
    ));

    _servicePipelines[registration.name] = pipeline;
  }

  void _registerServiceHealthCheck(ServiceRegistration registration) {
    final name = registration.name;

    HealthCheckRegistry.instance.register(
      name,
      HealthCheckers.circuitBreaker(
        name,
        () => CircuitBreakerRegistry.instance.get(name)?.getStatus(),
      ),
    );
  }

  /// 执行带有完整弹性保护的操作
  Future<StrategyResult<T>> executeWithResilience<T>(
    String serviceName,
    String operationName,
    Future<T> Function() operation, {
    Map<String, dynamic>? attributes,
  }) async {
    final pipeline = _servicePipelines[serviceName];
    if (pipeline == null) {
      throw StateError('Service not registered: $serviceName');
    }

    final stopwatch = Stopwatch()..start();

    // 混沌工程故障注入点
    if (_config.enableChaosEngineering) {
      await ChaosEngineeringManager.instance.faultPoint(
        service: serviceName,
        operation: operationName,
      );
    }

    // 记录到预测负载管理器
    if (_config.enablePredictiveLoad) {
      final loadManager = PredictiveLoadManagerRegistry.instance.get(serviceName);
      loadManager?.recordRequestRate(1.0); // 简化处理
    }

    try {
      final result = await pipeline.execute<T>(
        operation,
        serviceName: serviceName,
        operationName: operationName,
        attributes: attributes,
      );

      stopwatch.stop();

      // 记录延迟
      if (_config.enablePredictiveLoad) {
        final loadManager = PredictiveLoadManagerRegistry.instance.get(serviceName);
        loadManager?.recordLatency(stopwatch.elapsed);
      }

      // 记录到 SLO
      SloRegistry.instance.getOrCreate(serviceName).recordRequest(
        success: result.isSuccess,
        latency: stopwatch.elapsed,
      );

      // 如果失败，记录到根因分析
      if (!result.isSuccess && _config.enableRootCauseAnalysis) {
        _rootCauseAnalyzer.recordError(
          service: serviceName,
          component: operationName,
          error: result.error ?? StateError('Unknown error'),
          stackTrace: result.stackTrace,
          attributes: attributes,
        );
      }

      return result;
    } catch (e, stack) {
      stopwatch.stop();

      // 记录错误
      if (_config.enableRootCauseAnalysis) {
        _rootCauseAnalyzer.recordError(
          service: serviceName,
          component: operationName,
          error: e,
          stackTrace: stack,
          attributes: attributes,
        );
      }

      onGlobalError?.call(serviceName, e, stack);

      return StrategyResult.failure(
        e,
        stackTrace: stack,
        strategy: 'platform_catch',
        executionTime: stopwatch.elapsed,
      );
    }
  }

  void _handlePredictiveLoadAction(
    String serviceName,
    LoadManagementAction action,
    LoadPrediction prediction,
  ) {
    _logger.warning(
      'Predictive load action for $serviceName: ${action.name}',
    );

    switch (action) {
      case LoadManagementAction.enableThrottling:
        // 动态调整限流
        final limiter = GlobalRateLimiterRegistry.instance.get(serviceName);
        if (limiter != null) {
          // 实际实现中可以动态调整限流配置
          _logger.info('Would enable throttling for $serviceName');
        }
        break;

      case LoadManagementAction.emergencyBrake:
        // 紧急制动 - 打开熔断器
        final cb = CircuitBreakerRegistry.instance.get(serviceName);
        cb?.forceOpen();
        _logger.error('Emergency brake activated for $serviceName');
        break;

      case LoadManagementAction.preWarm:
        _logger.info('Pre-warming suggested for $serviceName');
        break;

      case LoadManagementAction.shedLoad:
        _logger.warning('Load shedding recommended for $serviceName');
        break;

      default:
        break;
    }

    MetricsCollector.instance.increment(
      'predictive_load_action',
      labels: MetricLabels()
          .add('service', serviceName)
          .add('action', action.name),
    );
  }

  Future<void> _performStartupHealthCheck() async {
    _logger.info('Performing startup health check...');

    final result = await HealthCheckRegistry.instance.checkAll();

    if (result.status == HealthStatus.unhealthy) {
      _logger.error('Health check failed: ${result.components.where((c) => c.isUnhealthy).map((c) => c.name)}');
      // 不阻止启动，但记录警告
    } else if (result.status == HealthStatus.degraded) {
      _logger.warning('System starting in degraded state');
    } else {
      _logger.info('Health check passed');
    }
  }

  void _transitionTo(PlatformState newState) {
    final oldState = _state;
    _state = newState;

    _logger.info('Platform state: ${oldState.name} -> ${newState.name}');
    onStateChange?.call(oldState, newState);

    MetricsCollector.instance.setGauge(
      'platform_state',
      newState.index.toDouble(),
    );
  }

  /// 触发手动根因分析
  Future<RootCauseAnalysisResult> analyzeRootCause() async {
    if (!_config.enableRootCauseAnalysis) {
      throw StateError('Root cause analysis is not enabled');
    }
    return _rootCauseAnalyzer.analyze();
  }

  /// 获取仪表盘快照
  Future<DashboardSnapshot> getDashboardSnapshot() async {
    if (!_config.enableDashboard) {
      throw StateError('Dashboard is not enabled');
    }
    return _dashboard.refresh();
  }

  /// 运行混沌实验
  Future<void> runChaosExperiment(String experimentId) async {
    if (!_config.enableChaosEngineering) {
      throw StateError('Chaos engineering is not enabled');
    }
    await ChaosEngineeringManager.instance.runner.startExperiment(experimentId);
  }

  /// 停止混沌实验
  Future<ExperimentResult> stopChaosExperiment([String reason = 'Manual stop']) async {
    return ChaosEngineeringManager.instance.runner.stopExperiment(reason);
  }

  /// 紧急停止所有混沌实验
  Future<void> emergencyStopChaos() async {
    await ChaosEngineeringManager.instance.runner.emergencyAbort();
  }

  /// 获取平台状态摘要
  Map<String, dynamic> getStatus() {
    return {
      'state': _state.name,
      'config': {
        'enablePredictiveLoad': _config.enablePredictiveLoad,
        'enableRootCauseAnalysis': _config.enableRootCauseAnalysis,
        'enableChaosEngineering': _config.enableChaosEngineering,
        'enableDashboard': _config.enableDashboard,
      },
      'registeredServices': _registeredServices.keys.toList(),
      'circuitBreakers': CircuitBreakerRegistry.instance.getAllStatus(),
      'sloStatus': SloRegistry.instance.getAllStatus(),
      'recoveryStatus': AutoRecoveryRegistry.instance.getAllStatus(),
      if (_config.enablePredictiveLoad)
        'loadPredictions': PredictiveLoadManagerRegistry.instance.getAllStatus(),
      if (_config.enableRootCauseAnalysis)
        'rootCauseAnalyzer': _rootCauseAnalyzer.getStatus(),
      if (_config.enableChaosEngineering)
        'chaosEngineering': ChaosEngineeringManager.instance.getStatus(),
      if (_config.enableDashboard)
        'dashboard': _dashboard.latestSnapshot?.toJson(),
    };
  }

  /// 获取健康报告
  Future<Map<String, dynamic>> getHealthReport() async {
    final systemHealth = await HealthCheckRegistry.instance.checkAll();
    final metrics = MetricsCollector.instance.getSummary();

    return {
      'systemHealth': systemHealth.toJson(),
      'metrics': metrics,
      'services': _registeredServices.keys.map((name) {
        final cb = CircuitBreakerRegistry.instance.get(name);
        final slo = SloRegistry.instance.getOrCreate(name);
        final recovery = AutoRecoveryRegistry.instance.getOrCreate(name);

        return {
          'name': name,
          'circuitBreaker': cb?.getStatus(),
          'slo': slo.getStatus(),
          'recovery': recovery.getStatus(),
        };
      }).toList(),
    };
  }

  /// 重置所有组件
  void reset() {
    _logger.warning('Resetting all platform components');

    CircuitBreakerRegistry.instance.resetAll();
    SloRegistry.instance.dispose();
    AutoRecoveryRegistry.instance.stopAllMonitoring();
    PredictiveLoadManagerRegistry.instance.stopAll();

    if (_config.enableRootCauseAnalysis) {
      _rootCauseAnalyzer.clear();
    }

    MetricsCollector.instance.reset();

    _logger.info('Platform reset complete');
  }

  /// 优雅关闭
  Future<void> shutdown() async {
    if (_state == PlatformState.stopped) return;

    _transitionTo(PlatformState.shuttingDown);
    _logger.info('Shutting down Reliability Platform...');

    try {
      // 停止混沌实验
      if (_config.enableChaosEngineering) {
        await ChaosEngineeringManager.instance.runner.emergencyAbort();
        ChaosEngineeringManager.instance.disable();
      }

      // 停止仪表盘
      if (_config.enableDashboard) {
        _dashboard.dispose();
      }

      // 停止预测引擎
      PredictiveLoadManagerRegistry.instance.stopAll();

      // 停止自动恢复
      AutoRecoveryRegistry.instance.stopAllMonitoring();

      // 清理 SLO
      SloRegistry.instance.dispose();

      _transitionTo(PlatformState.stopped);
      _logger.info('Reliability Platform shutdown complete');

    } catch (e, stack) {
      _logger.error('Error during shutdown', error: e, stackTrace: stack);
      _transitionTo(PlatformState.stopped);
    }
  }
}

/// 便捷函数: 初始化可靠性平台
Future<void> initializeReliabilityPlatform({
  ReliabilityPlatformConfig config = const ReliabilityPlatformConfig(),
}) {
  return ReliabilityPlatform.instance.initialize(config: config);
}

/// 便捷函数: 注册服务
void registerReliableService(ServiceRegistration registration) {
  ReliabilityPlatform.instance.registerService(registration);
}

/// 便捷函数: 执行带弹性保护的操作
Future<StrategyResult<T>> executeReliably<T>(
  String serviceName,
  String operationName,
  Future<T> Function() operation, {
  Map<String, dynamic>? attributes,
}) {
  return ReliabilityPlatform.instance.executeWithResilience<T>(
    serviceName,
    operationName,
    operation,
    attributes: attributes,
  );
}
