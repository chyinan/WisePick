import 'dart:async';
import 'dart:math' as math;

/// 指标类型
enum MetricType {
  counter, // 计数器（只增不减）
  gauge, // 瞬时值
  histogram, // 直方图（分布）
  timer, // 计时器
}

/// 指标标签
class MetricLabels {
  final Map<String, String> _labels;

  MetricLabels([Map<String, String>? labels]) : _labels = labels ?? {};

  MetricLabels add(String key, String value) {
    return MetricLabels({..._labels, key: value});
  }

  String toKey() {
    if (_labels.isEmpty) return '';
    final sorted = _labels.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => '${e.key}=${e.value}').join(',');
  }

  @override
  String toString() => toKey();
}

/// 直方图桶
class HistogramBucket {
  final double upperBound;
  int count = 0;

  HistogramBucket(this.upperBound);
}

/// 直方图数据
class HistogramData {
  final List<HistogramBucket> buckets;
  final List<double> _values = [];
  double _sum = 0;
  int _count = 0;

  /// Max number of raw values to retain for percentile calculations.
  /// Prevents unbounded memory growth over the app lifetime.
  static const int _maxRetainedValues = 10000;

  HistogramData({List<double>? boundaries})
      : buckets = (boundaries ?? _defaultBoundaries)
            .map((b) => HistogramBucket(b))
            .toList()
          ..add(HistogramBucket(double.infinity));

  static const _defaultBoundaries = [
    0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0
  ];

  void observe(double value) {
    _values.add(value);
    _sum += value;
    _count++;

    // Evict oldest values when exceeding cap to bound memory usage.
    // Bucket counts remain accurate (lifetime counters); percentiles
    // reflect only the most recent _maxRetainedValues observations.
    if (_values.length > _maxRetainedValues) {
      _values.removeAt(0);
    }

    for (final bucket in buckets) {
      if (value <= bucket.upperBound) {
        bucket.count++;
        break;
      }
    }
  }

  double get sum => _sum;
  int get count => _count;
  double get mean => _count > 0 ? _sum / _count : 0;

  double percentile(double p) {
    if (_values.isEmpty) return 0;
    final sorted = List<double>.from(_values)..sort();
    final index = ((sorted.length - 1) * p / 100).floor();
    return sorted[index];
  }

  double get p50 => percentile(50);
  double get p95 => percentile(95);
  double get p99 => percentile(99);
  double get min => _values.isEmpty ? 0 : _values.reduce(math.min);
  double get max => _values.isEmpty ? 0 : _values.reduce(math.max);

  Map<String, dynamic> toJson() => {
        'count': _count,
        'sum': _sum,
        'mean': mean,
        'min': min,
        'max': max,
        'p50': p50,
        'p95': p95,
        'p99': p99,
        'buckets': buckets.map((b) => {'le': b.upperBound, 'count': b.count}).toList(),
      };
}

/// 计时器上下文
class TimerContext {
  final Stopwatch _stopwatch = Stopwatch();
  final void Function(Duration) _onStop;

  TimerContext(this._onStop) {
    _stopwatch.start();
  }

  Duration stop() {
    _stopwatch.stop();
    final duration = _stopwatch.elapsed;
    _onStop(duration);
    return duration;
  }
}

/// 指标收集器
///
/// 提供系统级别的可观察性指标收集
class MetricsCollector {
  static final MetricsCollector _instance = MetricsCollector._();
  static MetricsCollector get instance => _instance;

  MetricsCollector._();

  final Map<String, int> _counters = {};
  final Map<String, double> _gauges = {};
  final Map<String, HistogramData> _histograms = {};

  // 预定义的指标名称
  static const requestTotal = 'request_total';
  static const requestDuration = 'request_duration_seconds';
  static const requestErrors = 'request_errors_total';
  static const retryTotal = 'retry_total';
  static const circuitBreakerState = 'circuit_breaker_state';
  static const connectionPoolActive = 'connection_pool_active';
  static const connectionPoolIdle = 'connection_pool_idle';
  static const cacheHits = 'cache_hits_total';
  static const cacheMisses = 'cache_misses_total';

  /// 增加计数器
  void increment(String name, {MetricLabels? labels, int delta = 1}) {
    final key = _buildKey(name, labels);
    _counters[key] = (_counters[key] ?? 0) + delta;
  }

  /// 获取计数器值
  int getCounter(String name, {MetricLabels? labels}) {
    final key = _buildKey(name, labels);
    return _counters[key] ?? 0;
  }

  /// 设置瞬时值
  void setGauge(String name, double value, {MetricLabels? labels}) {
    final key = _buildKey(name, labels);
    _gauges[key] = value;
  }

  /// 获取瞬时值
  double? getGauge(String name, {MetricLabels? labels}) {
    final key = _buildKey(name, labels);
    return _gauges[key];
  }

  /// 观察直方图值
  void observeHistogram(String name, double value, {MetricLabels? labels}) {
    final key = _buildKey(name, labels);
    _histograms.putIfAbsent(key, () => HistogramData()).observe(value);
  }

  /// 获取直方图数据
  HistogramData? getHistogram(String name, {MetricLabels? labels}) {
    final key = _buildKey(name, labels);
    return _histograms[key];
  }

  /// 记录请求延迟（秒）
  void recordLatency(String operation, Duration duration, {MetricLabels? labels}) {
    final effectiveLabels = (labels ?? MetricLabels()).add('operation', operation);
    observeHistogram(requestDuration, duration.inMicroseconds / 1000000, labels: effectiveLabels);
  }

  /// 开始计时
  TimerContext startTimer(String name, {MetricLabels? labels}) {
    return TimerContext((duration) {
      observeHistogram(name, duration.inMicroseconds / 1000000, labels: labels);
    });
  }

  /// 记录请求
  void recordRequest({
    required String service,
    required String operation,
    required bool success,
    Duration? duration,
  }) {
    final labels = MetricLabels()
        .add('service', service)
        .add('operation', operation)
        .add('status', success ? 'success' : 'error');

    increment(requestTotal, labels: labels);

    if (!success) {
      increment(requestErrors, labels: MetricLabels().add('service', service).add('operation', operation));
    }

    if (duration != null) {
      recordLatency('$service.$operation', duration);
    }
  }

  /// 记录重试
  void recordRetry({
    required String service,
    required String operation,
    required int attempt,
    required String reason,
  }) {
    final labels = MetricLabels()
        .add('service', service)
        .add('operation', operation)
        .add('attempt', attempt.toString())
        .add('reason', reason);

    increment(retryTotal, labels: labels);
  }

  /// 记录电路断路器状态变化
  void recordCircuitBreakerStateChange({
    required String name,
    required String state,
  }) {
    setGauge(
      circuitBreakerState,
      _circuitStateToValue(state),
      labels: MetricLabels().add('name', name),
    );
  }

  double _circuitStateToValue(String state) {
    switch (state) {
      case 'closed':
        return 0;
      case 'halfOpen':
        return 0.5;
      case 'open':
        return 1;
      default:
        return -1;
    }
  }

  /// 记录缓存命中/未命中
  void recordCacheAccess({required String cache, required bool hit}) {
    final labels = MetricLabels().add('cache', cache);
    if (hit) {
      increment(cacheHits, labels: labels);
    } else {
      increment(cacheMisses, labels: labels);
    }
  }

  /// 获取所有指标
  Map<String, dynamic> getAllMetrics() {
    return {
      'counters': Map<String, int>.from(_counters),
      'gauges': Map<String, double>.from(_gauges),
      'histograms': _histograms.map((key, value) => MapEntry(key, value.toJson())),
      'collectedAt': DateTime.now().toIso8601String(),
    };
  }

  /// 获取摘要
  Map<String, dynamic> getSummary() {
    final requestHistogram = getHistogram(requestDuration);
    final totalRequests = _sumCounters(requestTotal);
    final totalErrors = _sumCounters(requestErrors);

    return {
      'requests': {
        'total': totalRequests,
        'errors': totalErrors,
        'errorRate': totalRequests > 0 ? '${(totalErrors / totalRequests * 100).toStringAsFixed(2)}%' : '0%',
      },
      'latency': requestHistogram != null
          ? {
              'mean': '${requestHistogram.mean.toStringAsFixed(3)}s',
              'p50': '${requestHistogram.p50.toStringAsFixed(3)}s',
              'p95': '${requestHistogram.p95.toStringAsFixed(3)}s',
              'p99': '${requestHistogram.p99.toStringAsFixed(3)}s',
            }
          : null,
      'retries': _sumCounters(retryTotal),
      'cacheHitRate': _calculateCacheHitRate(),
    };
  }

  int _sumCounters(String prefix) {
    return _counters.entries
        .where((e) => e.key.startsWith(prefix))
        .fold(0, (sum, e) => sum + e.value);
  }

  String _calculateCacheHitRate() {
    final hits = _sumCounters(cacheHits);
    final misses = _sumCounters(cacheMisses);
    final total = hits + misses;
    if (total == 0) return 'N/A';
    return '${(hits / total * 100).toStringAsFixed(2)}%';
  }

  String _buildKey(String name, MetricLabels? labels) {
    final labelKey = labels?.toKey() ?? '';
    return labelKey.isEmpty ? name : '$name{$labelKey}';
  }

  /// 重置所有指标
  void reset() {
    _counters.clear();
    _gauges.clear();
    _histograms.clear();
  }
}

/// 便捷函数：记录请求
void recordRequest({
  required String service,
  required String operation,
  required bool success,
  Duration? duration,
}) {
  MetricsCollector.instance.recordRequest(
    service: service,
    operation: operation,
    success: success,
    duration: duration,
  );
}

/// 便捷函数：增加计数器
void incrementCounter(String name, {MetricLabels? labels}) {
  MetricsCollector.instance.increment(name, labels: labels);
}

/// 便捷函数：带计时执行
Future<T> withTimer<T>(
  String name,
  Future<T> Function() operation, {
  MetricLabels? labels,
}) async {
  final timer = MetricsCollector.instance.startTimer(name, labels: labels);
  try {
    return await operation();
  } finally {
    timer.stop();
  }
}
