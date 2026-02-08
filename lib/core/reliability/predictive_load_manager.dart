import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';

/// 时间序列数据点
class TimeSeriesPoint {
  final DateTime timestamp;
  final double value;
  final Map<String, dynamic>? metadata;

  const TimeSeriesPoint({
    required this.timestamp,
    required this.value,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'value': value,
        if (metadata != null) 'metadata': metadata,
      };
}

/// 负载预测结果
class LoadPrediction {
  final DateTime predictedTime;
  final double predictedLoad;
  final double confidenceLevel;
  final double lowerBound;
  final double upperBound;
  final String predictionMethod;
  final Map<String, dynamic> factors;

  const LoadPrediction({
    required this.predictedTime,
    required this.predictedLoad,
    required this.confidenceLevel,
    required this.lowerBound,
    required this.upperBound,
    required this.predictionMethod,
    this.factors = const {},
  });

  bool get isHighConfidence => confidenceLevel >= 0.8;
  bool get isHighLoad => predictedLoad > 0.7;
  double get uncertaintyRange => upperBound - lowerBound;

  Map<String, dynamic> toJson() => {
        'predictedTime': predictedTime.toIso8601String(),
        'predictedLoad': predictedLoad,
        'confidenceLevel': confidenceLevel,
        'lowerBound': lowerBound,
        'upperBound': upperBound,
        'predictionMethod': predictionMethod,
        'factors': factors,
      };
}

/// 趋势分析结果
class TrendAnalysis {
  final TrendDirection direction;
  final double slope;
  final double acceleration;
  final double rSquared;
  final Duration timeToThreshold;
  final double currentValue;
  final double projectedValue;

  const TrendAnalysis({
    required this.direction,
    required this.slope,
    required this.acceleration,
    required this.rSquared,
    required this.timeToThreshold,
    required this.currentValue,
    required this.projectedValue,
  });

  bool get isSignificant => rSquared >= 0.7;
  bool get isAccelerating => acceleration > 0.01;

  Map<String, dynamic> toJson() => {
        'direction': direction.name,
        'slope': slope,
        'acceleration': acceleration,
        'rSquared': rSquared,
        'timeToThresholdMinutes': timeToThreshold.inMinutes,
        'currentValue': currentValue,
        'projectedValue': projectedValue,
      };
}

enum TrendDirection { increasing, decreasing, stable, volatile }

/// 负载管理策略
enum LoadManagementAction {
  none,
  preWarm,
  scaleUp,
  activateCache,
  enableThrottling,
  shedLoad,
  emergencyBrake,
}

/// 预测性负载管理器
///
/// 基于时间序列分析和趋势预测的智能负载管理
class PredictiveLoadManager {
  final String serviceName;
  final ModuleLogger _logger;

  /// 历史数据存储
  final Queue<TimeSeriesPoint> _requestRateHistory = Queue();
  final Queue<TimeSeriesPoint> _latencyHistory = Queue();
  final Queue<TimeSeriesPoint> _errorRateHistory = Queue();
  final Queue<TimeSeriesPoint> _resourceUsageHistory = Queue();

  /// 配置参数
  final Duration historyWindow;
  final Duration predictionHorizon;
  final double highLoadThreshold;
  final double criticalLoadThreshold;
  final int minDataPointsForPrediction;

  /// 季节性模式检测
  final Map<int, List<double>> _hourlyPatterns = {};
  final Map<int, List<double>> _dailyPatterns = {};

  /// 回调函数
  final void Function(LoadManagementAction, LoadPrediction)? onActionRequired;
  final void Function(TrendAnalysis)? onTrendAlert;

  Timer? _predictionTimer;
  Timer? _patternLearningTimer;
  LoadPrediction? _latestPrediction;
  TrendAnalysis? _latestTrend;

  PredictiveLoadManager({
    required this.serviceName,
    this.historyWindow = const Duration(hours: 24),
    this.predictionHorizon = const Duration(minutes: 15),
    this.highLoadThreshold = 0.7,
    this.criticalLoadThreshold = 0.9,
    this.minDataPointsForPrediction = 30,
    this.onActionRequired,
    this.onTrendAlert,
  }) : _logger = AppLogger.instance.module('PredictiveLoad:$serviceName');

  LoadPrediction? get latestPrediction => _latestPrediction;
  TrendAnalysis? get latestTrend => _latestTrend;

  /// 记录请求速率
  void recordRequestRate(double requestsPerSecond) {
    _addToHistory(_requestRateHistory, requestsPerSecond);
    _updateHourlyPattern(requestsPerSecond);
  }

  /// 记录延迟
  void recordLatency(Duration latency) {
    _addToHistory(_latencyHistory, latency.inMilliseconds.toDouble());
  }

  /// 记录错误率
  void recordErrorRate(double errorRate) {
    _addToHistory(_errorRateHistory, errorRate);
  }

  /// 记录资源使用率 (0.0-1.0)
  void recordResourceUsage(double usage) {
    _addToHistory(_resourceUsageHistory, usage);
  }

  void _addToHistory(Queue<TimeSeriesPoint> queue, double value) {
    final now = DateTime.now();
    queue.add(TimeSeriesPoint(timestamp: now, value: value));

    // 清理过期数据
    final cutoff = now.subtract(historyWindow);
    while (queue.isNotEmpty && queue.first.timestamp.isBefore(cutoff)) {
      queue.removeFirst();
    }
  }

  void _updateHourlyPattern(double value) {
    final hour = DateTime.now().hour;
    _hourlyPatterns.putIfAbsent(hour, () => []);
    _hourlyPatterns[hour]!.add(value);

    // 限制每小时样本数量
    if (_hourlyPatterns[hour]!.length > 100) {
      _hourlyPatterns[hour]!.removeAt(0);
    }
  }

  /// 启动预测引擎
  void startPredictionEngine({Duration interval = const Duration(minutes: 1)}) {
    _predictionTimer?.cancel();
    _predictionTimer = Timer.periodic(interval, (_) => _runPredictionCycle());

    _patternLearningTimer?.cancel();
    _patternLearningTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _updateSeasonalPatterns(),
    );

    _logger.info('Prediction engine started');
  }

  void stopPredictionEngine() {
    _predictionTimer?.cancel();
    _patternLearningTimer?.cancel();
    _predictionTimer = null;
    _patternLearningTimer = null;
  }

  Future<void> _runPredictionCycle() async {
    try {
      // 1. 分析趋势
      _latestTrend = analyzeTrend();
      if (_latestTrend!.isSignificant) {
        onTrendAlert?.call(_latestTrend!);
      }

      // 2. 生成预测
      _latestPrediction = predictLoad(predictionHorizon);

      // 3. 确定必要动作
      final action = _determineAction(_latestPrediction!, _latestTrend!);
      if (action != LoadManagementAction.none) {
        _logger.warning('Action required: ${action.name}');
        onActionRequired?.call(action, _latestPrediction!);
      }

      // 4. 记录指标
      _recordPredictionMetrics();
    } catch (e, stack) {
      _logger.error('Prediction cycle failed', error: e, stackTrace: stack);
    }
  }

  /// 预测未来负载
  LoadPrediction predictLoad(Duration horizon) {
    final now = DateTime.now();
    final targetTime = now.add(horizon);

    if (_requestRateHistory.length < minDataPointsForPrediction) {
      return LoadPrediction(
        predictedTime: targetTime,
        predictedLoad: _getCurrentLoad(),
        confidenceLevel: 0.3,
        lowerBound: 0,
        upperBound: 1,
        predictionMethod: 'insufficient_data',
        factors: {'dataPoints': _requestRateHistory.length},
      );
    }

    // 多方法融合预测
    final ewmaPrediction = _exponentialMovingAverageForecast(horizon);
    final linearPrediction = _linearRegressionForecast(horizon);
    final seasonalPrediction = _seasonalForecast(targetTime);
    final holtwintersPrediction = _holtWintersForecast(horizon);

    // 加权融合
    final weights = _calculateMethodWeights();
    final fusedPrediction = (ewmaPrediction * weights['ewma']! +
            linearPrediction * weights['linear']! +
            seasonalPrediction * weights['seasonal']! +
            holtwintersPrediction * weights['holtwinters']!) /
        weights.values.reduce((a, b) => a + b);

    // 计算置信区间
    final stdDev = _calculateStdDev(_requestRateHistory);
    final confidenceLevel = _calculateConfidence();
    final margin = stdDev * 1.96 * (1 - confidenceLevel + 0.2);

    return LoadPrediction(
      predictedTime: targetTime,
      predictedLoad: fusedPrediction.clamp(0.0, 1.0),
      confidenceLevel: confidenceLevel,
      lowerBound: (fusedPrediction - margin).clamp(0.0, 1.0),
      upperBound: (fusedPrediction + margin).clamp(0.0, 1.0),
      predictionMethod: 'fusion',
      factors: {
        'ewma': ewmaPrediction,
        'linear': linearPrediction,
        'seasonal': seasonalPrediction,
        'holtWinters': holtwintersPrediction,
        'weights': weights,
      },
    );
  }

  /// 分析当前趋势
  TrendAnalysis analyzeTrend() {
    if (_requestRateHistory.length < 10) {
      return TrendAnalysis(
        direction: TrendDirection.stable,
        slope: 0,
        acceleration: 0,
        rSquared: 0,
        timeToThreshold: const Duration(hours: 999),
        currentValue: _getCurrentLoad(),
        projectedValue: _getCurrentLoad(),
      );
    }

    final points = _requestRateHistory.toList();
    final n = points.length;

    // 线性回归计算斜率
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += points[i].value;
      sumXY += i * points[i].value;
      sumX2 += i * i;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;

    // 计算R²
    final meanY = sumY / n;
    double ssTotal = 0, ssResidual = 0;
    for (int i = 0; i < n; i++) {
      final predicted = slope * i + intercept;
      ssTotal += math.pow(points[i].value - meanY, 2);
      ssResidual += math.pow(points[i].value - predicted, 2);
    }
    final rSquared = ssTotal > 0 ? 1 - (ssResidual / ssTotal) : 0.0;

    // 计算加速度 (二阶导数近似)
    double acceleration = 0;
    if (n >= 20) {
      final recentSlope = _calculateRecentSlope(points.sublist(n - 10));
      final previousSlope = _calculateRecentSlope(points.sublist(n - 20, n - 10));
      acceleration = recentSlope - previousSlope;
    }

    // 确定趋势方向
    TrendDirection direction;
    if (slope.abs() < 0.001) {
      direction = TrendDirection.stable;
    } else if (rSquared < 0.5) {
      direction = TrendDirection.volatile;
    } else if (slope > 0) {
      direction = TrendDirection.increasing;
    } else {
      direction = TrendDirection.decreasing;
    }

    // 计算到达阈值的时间
    final currentValue = points.last.value;
    final targetThreshold = criticalLoadThreshold;
    Duration timeToThreshold;
    if (slope <= 0 || currentValue >= targetThreshold) {
      timeToThreshold = Duration.zero;
    } else {
      final pointsToThreshold = (targetThreshold - currentValue) / slope;
      timeToThreshold = Duration(minutes: (pointsToThreshold * 1).round());
    }

    final projectedValue = currentValue + slope * 15; // 15分钟后

    return TrendAnalysis(
      direction: direction,
      slope: slope,
      acceleration: acceleration,
      rSquared: rSquared.clamp(0.0, 1.0),
      timeToThreshold: timeToThreshold,
      currentValue: currentValue,
      projectedValue: projectedValue.clamp(0.0, 1.0),
    );
  }

  double _calculateRecentSlope(List<TimeSeriesPoint> points) {
    if (points.length < 2) return 0;
    final n = points.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += points[i].value;
      sumXY += i * points[i].value;
      sumX2 += i * i;
    }
    return (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  }

  /// 指数加权移动平均预测
  double _exponentialMovingAverageForecast(Duration horizon) {
    if (_requestRateHistory.isEmpty) return 0;

    const alpha = 0.3;
    double ewma = _requestRateHistory.first.value;

    for (final point in _requestRateHistory) {
      ewma = alpha * point.value + (1 - alpha) * ewma;
    }

    // 简单外推
    final trend = _latestTrend?.slope ?? 0;
    final steps = horizon.inMinutes;
    return ewma + trend * steps;
  }

  /// 线性回归预测
  double _linearRegressionForecast(Duration horizon) {
    if (_requestRateHistory.length < 5) return _getCurrentLoad();

    final points = _requestRateHistory.toList();
    final n = points.length;

    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += points[i].value;
      sumXY += i * points[i].value;
      sumX2 += i * i;
    }

    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;

    final futureX = n + horizon.inMinutes;
    return slope * futureX + intercept;
  }

  /// 季节性预测
  double _seasonalForecast(DateTime targetTime) {
    final hour = targetTime.hour;
    final patterns = _hourlyPatterns[hour];

    if (patterns == null || patterns.isEmpty) {
      return _getCurrentLoad();
    }

    // 返回该小时的历史平均值
    return patterns.reduce((a, b) => a + b) / patterns.length;
  }

  /// Holt-Winters三重指数平滑预测
  double _holtWintersForecast(Duration horizon) {
    if (_requestRateHistory.length < 24) return _getCurrentLoad();

    const alpha = 0.2; // 水平平滑系数
    const beta = 0.1; // 趋势平滑系数
    const gamma = 0.3; // 季节性平滑系数
    const seasonLength = 24; // 假设24小时周期

    final data = _requestRateHistory.map((p) => p.value).toList();
    final n = data.length;

    // 初始化
    double level = data.take(seasonLength).reduce((a, b) => a + b) / seasonLength;
    double trend = 0;
    final seasonal = List<double>.filled(seasonLength, 1.0);

    // 初始化季节性因子
    for (int i = 0; i < seasonLength && i < n; i++) {
      seasonal[i] = data[i] / level;
    }

    // 迭代计算
    for (int i = seasonLength; i < n; i++) {
      final seasonIndex = i % seasonLength;
      final prevLevel = level;

      level = alpha * (data[i] / seasonal[seasonIndex]) +
          (1 - alpha) * (level + trend);
      trend = beta * (level - prevLevel) + (1 - beta) * trend;
      seasonal[seasonIndex] =
          gamma * (data[i] / level) + (1 - gamma) * seasonal[seasonIndex];
    }

    // 预测
    final steps = horizon.inMinutes ~/ 60;
    final futureSeasonIndex = (n + steps) % seasonLength;
    return (level + trend * steps) * seasonal[futureSeasonIndex];
  }

  Map<String, double> _calculateMethodWeights() {
    // 根据数据量和模式调整权重
    final hasEnoughData = _requestRateHistory.length >= 100;
    final hasSeasonalData = _hourlyPatterns.length >= 12;

    if (hasEnoughData && hasSeasonalData) {
      return {
        'ewma': 0.2,
        'linear': 0.2,
        'seasonal': 0.3,
        'holtwinters': 0.3,
      };
    } else if (hasEnoughData) {
      return {
        'ewma': 0.3,
        'linear': 0.3,
        'seasonal': 0.1,
        'holtwinters': 0.3,
      };
    } else {
      return {
        'ewma': 0.5,
        'linear': 0.3,
        'seasonal': 0.1,
        'holtwinters': 0.1,
      };
    }
  }

  double _calculateConfidence() {
    // 基于数据量和一致性计算置信度
    final dataPoints = _requestRateHistory.length;
    final dataConfidence = (dataPoints / 100).clamp(0.0, 0.5);

    final stdDev = _calculateStdDev(_requestRateHistory);
    final mean = _calculateMean(_requestRateHistory);
    final cv = mean > 0 ? stdDev / mean : 1.0;
    final stabilityConfidence = (1 - cv).clamp(0.0, 0.5);

    return (dataConfidence + stabilityConfidence).clamp(0.3, 0.95);
  }

  double _calculateStdDev(Queue<TimeSeriesPoint> data) {
    if (data.length < 2) return 0;
    final mean = _calculateMean(data);
    final variance =
        data.map((p) => math.pow(p.value - mean, 2)).reduce((a, b) => a + b) /
            data.length;
    return math.sqrt(variance);
  }

  double _calculateMean(Queue<TimeSeriesPoint> data) {
    if (data.isEmpty) return 0;
    return data.map((p) => p.value).reduce((a, b) => a + b) / data.length;
  }

  double _getCurrentLoad() {
    if (_requestRateHistory.isEmpty) return 0;
    return _requestRateHistory.last.value;
  }

  LoadManagementAction _determineAction(
    LoadPrediction prediction,
    TrendAnalysis trend,
  ) {
    // 紧急制动
    if (prediction.predictedLoad >= criticalLoadThreshold &&
        prediction.isHighConfidence) {
      return LoadManagementAction.emergencyBrake;
    }

    // 负载卸载
    if (prediction.predictedLoad >= 0.85 && trend.direction == TrendDirection.increasing) {
      return LoadManagementAction.shedLoad;
    }

    // 启用限流
    if (prediction.predictedLoad >= highLoadThreshold) {
      return LoadManagementAction.enableThrottling;
    }

    // 预热
    if (trend.direction == TrendDirection.increasing &&
        trend.timeToThreshold.inMinutes < 30 &&
        trend.timeToThreshold.inMinutes > 5) {
      return LoadManagementAction.preWarm;
    }

    // 扩容提示
    if (trend.direction == TrendDirection.increasing &&
        trend.isAccelerating &&
        prediction.predictedLoad > 0.5) {
      return LoadManagementAction.scaleUp;
    }

    // 激活缓存
    if (prediction.predictedLoad > 0.6 && _errorRateHistory.isNotEmpty) {
      final latestErrorRate =
          _errorRateHistory.isNotEmpty ? _errorRateHistory.last.value : 0;
      if (latestErrorRate > 0.05) {
        return LoadManagementAction.activateCache;
      }
    }

    return LoadManagementAction.none;
  }

  void _updateSeasonalPatterns() {
    // 计算每日模式
    final dayOfWeek = DateTime.now().weekday;
    final dayData =
        _requestRateHistory.where((p) => p.timestamp.weekday == dayOfWeek);

    if (dayData.isNotEmpty) {
      final avgForDay =
          dayData.map((p) => p.value).reduce((a, b) => a + b) / dayData.length;
      _dailyPatterns.putIfAbsent(dayOfWeek, () => []);
      _dailyPatterns[dayOfWeek]!.add(avgForDay);

      if (_dailyPatterns[dayOfWeek]!.length > 4) {
        _dailyPatterns[dayOfWeek]!.removeAt(0);
      }
    }
  }

  void _recordPredictionMetrics() {
    if (_latestPrediction != null) {
      MetricsCollector.instance.setGauge(
        'predicted_load',
        _latestPrediction!.predictedLoad,
        labels: MetricLabels().add('service', serviceName),
      );

      MetricsCollector.instance.setGauge(
        'prediction_confidence',
        _latestPrediction!.confidenceLevel,
        labels: MetricLabels().add('service', serviceName),
      );
    }

    if (_latestTrend != null) {
      MetricsCollector.instance.setGauge(
        'load_trend_slope',
        _latestTrend!.slope,
        labels: MetricLabels().add('service', serviceName),
      );
    }
  }

  /// 获取预测历史摘要
  Map<String, dynamic> getStatus() => {
        'serviceName': serviceName,
        'dataPoints': {
          'requestRate': _requestRateHistory.length,
          'latency': _latencyHistory.length,
          'errorRate': _errorRateHistory.length,
          'resourceUsage': _resourceUsageHistory.length,
        },
        'latestPrediction': _latestPrediction?.toJson(),
        'latestTrend': _latestTrend?.toJson(),
        'hourlyPatternsHours': _hourlyPatterns.keys.toList(),
        'currentLoad': _getCurrentLoad(),
      };

  /// 导出历史数据用于分析
  List<Map<String, dynamic>> exportHistory() {
    return _requestRateHistory.map((p) => p.toJson()).toList();
  }

  void dispose() {
    stopPredictionEngine();
  }
}

/// 预测负载管理器注册表
class PredictiveLoadManagerRegistry {
  static final PredictiveLoadManagerRegistry _instance =
      PredictiveLoadManagerRegistry._();
  static PredictiveLoadManagerRegistry get instance => _instance;

  PredictiveLoadManagerRegistry._();

  final Map<String, PredictiveLoadManager> _managers = {};

  PredictiveLoadManager getOrCreate(
    String serviceName, {
    Duration historyWindow = const Duration(hours: 24),
    Duration predictionHorizon = const Duration(minutes: 15),
    void Function(LoadManagementAction, LoadPrediction)? onActionRequired,
  }) {
    return _managers.putIfAbsent(
      serviceName,
      () => PredictiveLoadManager(
        serviceName: serviceName,
        historyWindow: historyWindow,
        predictionHorizon: predictionHorizon,
        onActionRequired: onActionRequired,
      ),
    );
  }

  PredictiveLoadManager? get(String serviceName) => _managers[serviceName];

  void startAll() {
    for (final manager in _managers.values) {
      manager.startPredictionEngine();
    }
  }

  void stopAll() {
    for (final manager in _managers.values) {
      manager.stopPredictionEngine();
    }
  }

  Map<String, dynamic> getAllStatus() =>
      _managers.map((k, v) => MapEntry(k, v.getStatus()));

  void dispose() {
    for (final manager in _managers.values) {
      manager.dispose();
    }
    _managers.clear();
  }
}
