import 'dart:async';
import 'dart:collection';
import 'dart:math';

/// 全局速率限制器配置
class RateLimiterConfig {
  /// 每秒最大请求数
  final int maxRequestsPerSecond;

  /// 最大并发请求数
  final int maxConcurrentRequests;

  /// 最大等待队列长度
  final int maxQueueLength;

  /// 等待超时
  final Duration waitTimeout;

  /// 是否启用背压
  final bool enableBackpressure;

  /// 背压阈值（队列长度达到此比例时开始降速）
  final double backpressureThreshold;

  const RateLimiterConfig({
    this.maxRequestsPerSecond = 10,
    this.maxConcurrentRequests = 5,
    this.maxQueueLength = 100,
    this.waitTimeout = const Duration(seconds: 30),
    this.enableBackpressure = true,
    this.backpressureThreshold = 0.7,
  });

  /// AI 服务配置（较低限制）
  static const aiService = RateLimiterConfig(
    maxRequestsPerSecond: 3,
    maxConcurrentRequests: 2,
    maxQueueLength: 20,
    waitTimeout: Duration(minutes: 2),
  );

  /// 爬虫服务配置
  static const scraper = RateLimiterConfig(
    maxRequestsPerSecond: 2,
    maxConcurrentRequests: 3,
    maxQueueLength: 50,
    waitTimeout: Duration(minutes: 1),
  );
}

/// 等待请求
class _WaitingRequest<T> {
  final Completer<T> completer;
  final Future<T> Function() operation;
  final DateTime enqueuedAt;
  final String? operationName;
  final Duration timeout;

  _WaitingRequest({
    required this.completer,
    required this.operation,
    required this.enqueuedAt,
    required this.timeout,
    this.operationName,
  });

  bool get isTimedOut => DateTime.now().difference(enqueuedAt) > timeout;
}

/// 速率限制异常
class RateLimitException implements Exception {
  final String message;
  final Duration? retryAfter;

  RateLimitException(this.message, {this.retryAfter});

  @override
  String toString() => 'RateLimitException: $message';
}

/// 全局速率限制器
///
/// 提供系统级别的请求速率控制，防止重试风暴和资源耗尽
class GlobalRateLimiter {
  final RateLimiterConfig config;
  final String name;

  final Queue<_WaitingRequest> _waitQueue = Queue();
  int _activeRequests = 0;
  final List<DateTime> _requestTimestamps = [];
  Timer? _processTimer;
  bool _disposed = false;

  // 统计
  int _totalRequests = 0;
  int _rejectedRequests = 0;
  int _timeoutRequests = 0;
  Duration _totalWaitTime = Duration.zero;

  GlobalRateLimiter({
    required this.name,
    RateLimiterConfig? config,
  }) : config = config ?? const RateLimiterConfig() {
    _startProcessing();
  }

  /// 当前活跃请求数
  int get activeRequests => _activeRequests;

  /// 等待队列长度
  int get queueLength => _waitQueue.length;

  /// 是否达到限制
  bool get isAtLimit => _activeRequests >= config.maxConcurrentRequests;

  /// 是否队列已满
  bool get isQueueFull => _waitQueue.length >= config.maxQueueLength;

  /// 获取当前 QPS
  double get currentQps {
    _cleanOldTimestamps();
    return _requestTimestamps.length.toDouble();
  }

  /// 执行受限制的操作
  Future<T> execute<T>(
    Future<T> Function() operation, {
    String? operationName,
    Duration? timeout,
  }) async {
    if (_disposed) {
      throw StateError('RateLimiter has been disposed');
    }

    _totalRequests++;
    final effectiveTimeout = timeout ?? config.waitTimeout;

    // 检查队列是否已满
    if (isQueueFull) {
      _rejectedRequests++;
      throw RateLimitException(
        '请求队列已满，请稍后重试',
        retryAfter: Duration(seconds: _estimateRetryAfter()),
      );
    }

    // 如果可以立即执行
    if (_canExecuteNow()) {
      return _executeNow(operation, operationName);
    }

    // 排队等待
    final completer = Completer<T>();
    final request = _WaitingRequest<T>(
      completer: completer,
      operation: operation,
      enqueuedAt: DateTime.now(),
      timeout: effectiveTimeout,
      operationName: operationName,
    );
    _waitQueue.add(request);

    // 设置超时
    final timer = Timer(effectiveTimeout, () {
      if (!completer.isCompleted) {
        _waitQueue.remove(request);
        _timeoutRequests++;
        completer.completeError(RateLimitException(
          '等待超时，请稍后重试',
          retryAfter: Duration(seconds: _estimateRetryAfter()),
        ));
      }
    });

    try {
      final result = await completer.future;
      timer.cancel();
      _totalWaitTime += DateTime.now().difference(request.enqueuedAt);
      return result;
    } catch (e) {
      timer.cancel();
      rethrow;
    }
  }

  /// 检查是否可以立即执行
  bool _canExecuteNow() {
    if (_activeRequests >= config.maxConcurrentRequests) {
      return false;
    }

    _cleanOldTimestamps();
    if (_requestTimestamps.length >= config.maxRequestsPerSecond) {
      return false;
    }

    return true;
  }

  /// 立即执行操作
  Future<T> _executeNow<T>(Future<T> Function() operation, String? operationName) async {
    _activeRequests++;
    _requestTimestamps.add(DateTime.now());

    try {
      final result = await operation();
      return result;
    } finally {
      // Defensive: prevent underflow in case of unexpected re-entrancy.
      if (_activeRequests > 0) {
        _activeRequests--;
      }
      _processQueue();
    }
  }

  /// 清理过期的时间戳
  void _cleanOldTimestamps() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 1));
    _requestTimestamps.removeWhere((t) => t.isBefore(cutoff));
  }

  /// 启动处理定时器
  void _startProcessing() {
    _processTimer?.cancel();
    _processTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _processQueue();
    });
  }

  /// 处理等待队列
  void _processQueue() {
    if (_disposed) return;

    // 清理超时的请求
    final timedOut = <_WaitingRequest>[];
    for (final request in _waitQueue) {
      if (request.isTimedOut && !request.completer.isCompleted) {
        timedOut.add(request);
        _timeoutRequests++;
        request.completer.completeError(RateLimitException('等待超时'));
      }
    }
    for (final r in timedOut) {
      _waitQueue.remove(r);
    }

    // 处理等待中的请求
    while (_waitQueue.isNotEmpty && _canExecuteNow()) {
      final request = _waitQueue.removeFirst();
      if (request.completer.isCompleted) continue;

      _executeNow(request.operation, request.operationName).then((result) {
        if (!request.completer.isCompleted) {
          request.completer.complete(result);
        }
      }).catchError((e) {
        if (!request.completer.isCompleted) {
          request.completer.completeError(e);
        }
      });
    }
  }

  /// 估算重试等待时间
  int _estimateRetryAfter() {
    final queueTime = _waitQueue.length / max(1, config.maxRequestsPerSecond);
    return max(1, queueTime.ceil());
  }

  /// 获取统计信息
  Map<String, dynamic> getStats() {
    return {
      'name': name,
      'activeRequests': _activeRequests,
      'queueLength': _waitQueue.length,
      'currentQps': currentQps,
      'totalRequests': _totalRequests,
      'rejectedRequests': _rejectedRequests,
      'timeoutRequests': _timeoutRequests,
      'avgWaitTime': _totalRequests > 0
          ? '${(_totalWaitTime.inMilliseconds / max(1, _totalRequests - _rejectedRequests)).toStringAsFixed(1)}ms'
          : '0ms',
      'config': {
        'maxRequestsPerSecond': config.maxRequestsPerSecond,
        'maxConcurrentRequests': config.maxConcurrentRequests,
        'maxQueueLength': config.maxQueueLength,
      },
    };
  }

  /// 重置统计
  void resetStats() {
    _totalRequests = 0;
    _rejectedRequests = 0;
    _timeoutRequests = 0;
    _totalWaitTime = Duration.zero;
  }

  /// 释放资源
  void dispose() {
    _disposed = true;
    _processTimer?.cancel();

    // 拒绝所有等待中的请求
    while (_waitQueue.isNotEmpty) {
      final request = _waitQueue.removeFirst();
      if (!request.completer.isCompleted) {
        request.completer.completeError(
          RateLimitException('速率限制器已关闭'),
        );
      }
    }
  }
}

/// 全局速率限制器注册表
class GlobalRateLimiterRegistry {
  static final GlobalRateLimiterRegistry _instance = GlobalRateLimiterRegistry._();
  static GlobalRateLimiterRegistry get instance => _instance;

  GlobalRateLimiterRegistry._();

  final Map<String, GlobalRateLimiter> _limiters = {};

  /// 获取或创建限制器
  GlobalRateLimiter getOrCreate(String name, {RateLimiterConfig? config}) {
    return _limiters.putIfAbsent(
      name,
      () => GlobalRateLimiter(name: name, config: config),
    );
  }

  /// 获取限制器
  GlobalRateLimiter? get(String name) => _limiters[name];

  /// 获取所有统计
  Map<String, dynamic> getAllStats() {
    return _limiters.map((name, limiter) => MapEntry(name, limiter.getStats()));
  }

  /// 释放所有
  void disposeAll() {
    for (final limiter in _limiters.values) {
      limiter.dispose();
    }
    _limiters.clear();
  }

  /// 清除所有限制器（用于测试）
  void clear() {
    disposeAll();
  }
}

/// 便捷函数：带速率限制执行
Future<T> withRateLimit<T>(
  String limiterName,
  Future<T> Function() operation, {
  RateLimiterConfig? config,
  String? operationName,
}) {
  final limiter = GlobalRateLimiterRegistry.instance.getOrCreate(limiterName, config: config);
  return limiter.execute(operation, operationName: operationName);
}
