import 'dart:async';

import '../logging/app_logger.dart';
import '../observability/metrics_collector.dart';
import '../resilience/circuit_breaker.dart';
import '../resilience/global_rate_limiter.dart';
import '../resilience/retry_policy.dart';

/// 策略执行上下文
class StrategyContext {
  final String serviceName;
  final String operationName;
  final Map<String, dynamic> attributes;
  final int attemptNumber;
  final DateTime startTime;
  final Object? lastError;
  final Duration? lastLatency;

  const StrategyContext({
    required this.serviceName,
    required this.operationName,
    this.attributes = const {},
    this.attemptNumber = 1,
    required this.startTime,
    this.lastError,
    this.lastLatency,
  });

  StrategyContext copyWith({
    int? attemptNumber,
    Object? lastError,
    Duration? lastLatency,
  }) {
    return StrategyContext(
      serviceName: serviceName,
      operationName: operationName,
      attributes: attributes,
      attemptNumber: attemptNumber ?? this.attemptNumber,
      startTime: startTime,
      lastError: lastError ?? this.lastError,
      lastLatency: lastLatency ?? this.lastLatency,
    );
  }
}

/// 策略执行结果
class StrategyResult<T> {
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
  final bool isSuccess;
  final String executedStrategy;
  final Duration executionTime;
  final Map<String, dynamic> metadata;

  const StrategyResult._({
    this.value,
    this.error,
    this.stackTrace,
    required this.isSuccess,
    required this.executedStrategy,
    required this.executionTime,
    this.metadata = const {},
  });

  factory StrategyResult.success(
    T value, {
    required String strategy,
    required Duration executionTime,
    Map<String, dynamic>? metadata,
  }) {
    return StrategyResult._(
      value: value,
      isSuccess: true,
      executedStrategy: strategy,
      executionTime: executionTime,
      metadata: metadata ?? {},
    );
  }

  factory StrategyResult.failure(
    Object error, {
    StackTrace? stackTrace,
    required String strategy,
    required Duration executionTime,
    Map<String, dynamic>? metadata,
  }) {
    return StrategyResult._(
      error: error,
      stackTrace: stackTrace,
      isSuccess: false,
      executedStrategy: strategy,
      executionTime: executionTime,
      metadata: metadata ?? {},
    );
  }

  T getOrThrow() {
    if (isSuccess && value != null) return value as T;
    if (error != null) throw error!;
    throw StateError('No value and no error in StrategyResult');
  }

  T? getOrNull() => isSuccess ? value : null;
}

/// 弹性策略基类
abstract class ResilienceStrategy {
  final String name;
  final int priority; // 优先级，数字越小优先级越高
  bool _enabled = true;

  ResilienceStrategy({
    required this.name,
    this.priority = 100,
  });

  bool get isEnabled => _enabled;

  void enable() => _enabled = true;
  void disable() => _enabled = false;

  /// 判断策略是否适用于当前上下文
  bool isApplicable(StrategyContext context);

  /// 执行策略
  Future<StrategyResult<T>> execute<T>(
    Future<T> Function() operation,
    StrategyContext context,
  );

  /// 获取策略状态
  Map<String, dynamic> getStatus();
}

/// 超时策略
class TimeoutStrategy extends ResilienceStrategy {
  final Duration timeout;
  final Duration? softTimeout;
  final void Function(StrategyContext)? onSoftTimeout;

  TimeoutStrategy({
    super.name = 'timeout',
    super.priority = 10,
    required this.timeout,
    this.softTimeout,
    this.onSoftTimeout,
  });

  @override
  bool isApplicable(StrategyContext context) => true;

  @override
  Future<StrategyResult<T>> execute<T>(
    Future<T> Function() operation,
    StrategyContext context,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 软超时警告
      if (softTimeout != null && onSoftTimeout != null) {
        Timer(softTimeout!, () {
          if (stopwatch.isRunning) {
            onSoftTimeout!(context);
          }
        });
      }

      final result = await operation().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            'Operation ${context.operationName} timed out after ${timeout.inMilliseconds}ms',
            timeout,
          );
        },
      );

      stopwatch.stop();
      return StrategyResult.success(
        result,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    } catch (e, stack) {
      stopwatch.stop();
      return StrategyResult.failure(
        e,
        stackTrace: stack,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    }
  }

  @override
  Map<String, dynamic> getStatus() => {
        'name': name,
        'enabled': isEnabled,
        'timeout': timeout.inMilliseconds,
        'softTimeout': softTimeout?.inMilliseconds,
      };
}

/// 隔板策略 (Bulkhead)
class BulkheadStrategy extends ResilienceStrategy {
  final int maxConcurrent;
  final Duration maxWaitTime;
  int _currentConcurrent = 0;
  final _waitQueue = <Completer<void>>[];

  BulkheadStrategy({
    super.name = 'bulkhead',
    super.priority = 20,
    required this.maxConcurrent,
    this.maxWaitTime = const Duration(seconds: 30),
  });

  int get currentConcurrent => _currentConcurrent;
  int get queueLength => _waitQueue.length;
  bool get hasCapacity => _currentConcurrent < maxConcurrent;

  @override
  bool isApplicable(StrategyContext context) => true;

  @override
  Future<StrategyResult<T>> execute<T>(
    Future<T> Function() operation,
    StrategyContext context,
  ) async {
    final stopwatch = Stopwatch()..start();

    // 尝试获取执行槽位
    final acquired = await _tryAcquire();
    if (!acquired) {
      stopwatch.stop();
      return StrategyResult.failure(
        BulkheadRejectedException(
          'Bulkhead $name full: $_currentConcurrent/$maxConcurrent concurrent, '
          '${_waitQueue.length} waiting',
        ),
        strategy: name,
        executionTime: stopwatch.elapsed,
        metadata: {
          'currentConcurrent': _currentConcurrent,
          'maxConcurrent': maxConcurrent,
          'queueLength': _waitQueue.length,
        },
      );
    }

    try {
      final result = await operation();
      stopwatch.stop();
      return StrategyResult.success(
        result,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    } catch (e, stack) {
      stopwatch.stop();
      return StrategyResult.failure(
        e,
        stackTrace: stack,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    } finally {
      _release();
    }
  }

  Future<bool> _tryAcquire() async {
    if (_currentConcurrent < maxConcurrent) {
      _currentConcurrent++;
      return true;
    }

    // 加入等待队列
    final completer = Completer<void>();
    _waitQueue.add(completer);

    try {
      await completer.future.timeout(maxWaitTime);
      return true;
    } on TimeoutException {
      _waitQueue.remove(completer);
      return false;
    }
  }

  void _release() {
    _currentConcurrent--;

    // 唤醒等待的请求
    if (_waitQueue.isNotEmpty && _currentConcurrent < maxConcurrent) {
      final next = _waitQueue.removeAt(0);
      _currentConcurrent++;
      next.complete();
    }
  }

  @override
  Map<String, dynamic> getStatus() => {
        'name': name,
        'enabled': isEnabled,
        'currentConcurrent': _currentConcurrent,
        'maxConcurrent': maxConcurrent,
        'queueLength': _waitQueue.length,
        'utilization': '${(_currentConcurrent / maxConcurrent * 100).toStringAsFixed(1)}%',
      };
}

class BulkheadRejectedException implements Exception {
  final String message;
  BulkheadRejectedException(this.message);

  @override
  String toString() => 'BulkheadRejectedException: $message';
}

/// 降级策略
class FallbackStrategy<T> extends ResilienceStrategy {
  final Future<T> Function(StrategyContext, Object?) fallbackFn;
  final bool Function(Object)? shouldFallback;
  int _fallbackCount = 0;

  FallbackStrategy({
    super.name = 'fallback',
    super.priority = 90,
    required this.fallbackFn,
    this.shouldFallback,
  });

  int get fallbackCount => _fallbackCount;

  @override
  bool isApplicable(StrategyContext context) => true;

  @override
  Future<StrategyResult<R>> execute<R>(
    Future<R> Function() operation,
    StrategyContext context,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await operation();
      stopwatch.stop();
      return StrategyResult.success(
        result,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    } catch (e, stack) {
      // 检查是否应该执行降级
      if (shouldFallback != null && !shouldFallback!(e)) {
        stopwatch.stop();
        return StrategyResult.failure(
          e,
          stackTrace: stack,
          strategy: name,
          executionTime: stopwatch.elapsed,
        );
      }

      try {
        _fallbackCount++;
        final fallbackResult = await fallbackFn(context, e) as R;
        stopwatch.stop();
        return StrategyResult.success(
          fallbackResult,
          strategy: '$name(fallback)',
          executionTime: stopwatch.elapsed,
          metadata: {'originalError': e.toString(), 'usedFallback': true},
        );
      } catch (fallbackError, fallbackStack) {
        stopwatch.stop();
        return StrategyResult.failure(
          fallbackError,
          stackTrace: fallbackStack,
          strategy: '$name(fallback_failed)',
          executionTime: stopwatch.elapsed,
          metadata: {'originalError': e.toString()},
        );
      }
    }
  }

  @override
  Map<String, dynamic> getStatus() => {
        'name': name,
        'enabled': isEnabled,
        'fallbackCount': _fallbackCount,
      };
}

/// 缓存策略
class CacheStrategy<T> extends ResilienceStrategy {
  final Duration ttl;
  final String Function(StrategyContext)? cacheKeyBuilder;
  final Map<String, _CacheEntry<T>> _cache = {};
  final int maxEntries;

  CacheStrategy({
    super.name = 'cache',
    super.priority = 5,
    required this.ttl,
    this.cacheKeyBuilder,
    this.maxEntries = 1000,
  });

  int get cacheSize => _cache.length;
  int get hitCount => _cache.values.where((e) => e.hitCount > 0).fold(0, (a, e) => a + e.hitCount);

  @override
  bool isApplicable(StrategyContext context) => true;

  @override
  Future<StrategyResult<R>> execute<R>(
    Future<R> Function() operation,
    StrategyContext context,
  ) async {
    final stopwatch = Stopwatch()..start();
    final key = cacheKeyBuilder?.call(context) ??
        '${context.serviceName}:${context.operationName}';

    // 检查缓存
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      cached.hitCount++;
      stopwatch.stop();

      MetricsCollector.instance.recordCacheAccess(cache: name, hit: true);

      return StrategyResult.success(
        cached.value as R,
        strategy: '$name(hit)',
        executionTime: stopwatch.elapsed,
        metadata: {'cacheHit': true, 'cacheAge': cached.age.inMilliseconds},
      );
    }

    MetricsCollector.instance.recordCacheAccess(cache: name, hit: false);

    try {
      final result = await operation();

      // 存入缓存
      _evictIfNeeded();
      _cache[key] = _CacheEntry(result as T, ttl);

      stopwatch.stop();
      return StrategyResult.success(
        result,
        strategy: '$name(miss)',
        executionTime: stopwatch.elapsed,
        metadata: {'cacheHit': false},
      );
    } catch (e, stack) {
      // 如果有过期缓存，在错误时返回
      if (cached != null) {
        cached.hitCount++;
        stopwatch.stop();
        return StrategyResult.success(
          cached.value as R,
          strategy: '$name(stale)',
          executionTime: stopwatch.elapsed,
          metadata: {'cacheStale': true, 'originalError': e.toString()},
        );
      }

      stopwatch.stop();
      return StrategyResult.failure(
        e,
        stackTrace: stack,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    }
  }

  void _evictIfNeeded() {
    // 清理过期条目
    _cache.removeWhere((_, v) => v.isExpired);

    // 如果还是满了，清理最旧的
    if (_cache.length >= maxEntries) {
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.createdAt.isBefore(b.value.createdAt) ? a : b,
      );
      _cache.remove(oldest.key);
    }
  }

  void invalidate(String key) => _cache.remove(key);
  void invalidateAll() => _cache.clear();

  @override
  Map<String, dynamic> getStatus() => {
        'name': name,
        'enabled': isEnabled,
        'cacheSize': _cache.length,
        'maxEntries': maxEntries,
        'ttlMs': ttl.inMilliseconds,
        'totalHits': hitCount,
      };
}

class _CacheEntry<T> {
  final T value;
  final DateTime createdAt;
  final Duration ttl;
  int hitCount = 0;

  _CacheEntry(this.value, this.ttl) : createdAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt) > ttl;
  Duration get age => DateTime.now().difference(createdAt);
}

/// 熔断器策略适配器
class CircuitBreakerStrategy extends ResilienceStrategy {
  final CircuitBreaker circuitBreaker;

  CircuitBreakerStrategy({
    required this.circuitBreaker,
    super.priority = 15,
  }) : super(name: 'circuit_breaker_${circuitBreaker.name}');

  @override
  bool isApplicable(StrategyContext context) => true;

  @override
  Future<StrategyResult<T>> execute<T>(
    Future<T> Function() operation,
    StrategyContext context,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await circuitBreaker.execute(operation);
      stopwatch.stop();
      return StrategyResult.success(
        result,
        strategy: name,
        executionTime: stopwatch.elapsed,
        metadata: {'circuitState': circuitBreaker.state.name},
      );
    } catch (e, stack) {
      stopwatch.stop();
      return StrategyResult.failure(
        e,
        stackTrace: stack,
        strategy: name,
        executionTime: stopwatch.elapsed,
        metadata: {'circuitState': circuitBreaker.state.name},
      );
    }
  }

  @override
  Map<String, dynamic> getStatus() => {
        'name': name,
        'enabled': isEnabled,
        ...circuitBreaker.getStatus(),
      };
}

/// 限流策略适配器
class RateLimitStrategy extends ResilienceStrategy {
  final GlobalRateLimiter rateLimiter;

  RateLimitStrategy({
    required this.rateLimiter,
    super.priority = 5,
  }) : super(name: 'rate_limit_${rateLimiter.name}');

  @override
  bool isApplicable(StrategyContext context) => true;

  @override
  Future<StrategyResult<T>> execute<T>(
    Future<T> Function() operation,
    StrategyContext context,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await rateLimiter.execute(
        operation,
        operationName: context.operationName,
      );
      stopwatch.stop();
      return StrategyResult.success(
        result,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    } catch (e, stack) {
      stopwatch.stop();
      return StrategyResult.failure(
        e,
        stackTrace: stack,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    }
  }

  @override
  Map<String, dynamic> getStatus() => {
        'name': name,
        'enabled': isEnabled,
        ...rateLimiter.getStats(),
      };
}

/// 重试策略适配器
class RetryStrategy extends ResilienceStrategy {
  final RetryExecutor retryExecutor;
  final bool Function(Object)? retryIf;

  RetryStrategy({
    required this.retryExecutor,
    this.retryIf,
    super.priority = 80,
  }) : super(name: 'retry');

  @override
  bool isApplicable(StrategyContext context) => true;

  @override
  Future<StrategyResult<T>> execute<T>(
    Future<T> Function() operation,
    StrategyContext context,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await retryExecutor.execute(
        operation,
        operationName: context.operationName,
        retryIf: retryIf,
      );

      stopwatch.stop();

      if (result.isSuccess) {
        return StrategyResult.success(
          result.getOrThrow(),
          strategy: name,
          executionTime: stopwatch.elapsed,
        );
      } else {
        return StrategyResult.failure(
          result.error ?? StateError('Retry failed'),
          strategy: name,
          executionTime: stopwatch.elapsed,
        );
      }
    } catch (e, stack) {
      stopwatch.stop();
      return StrategyResult.failure(
        e,
        stackTrace: stack,
        strategy: name,
        executionTime: stopwatch.elapsed,
      );
    }
  }

  @override
  Map<String, dynamic> getStatus() => {
        'name': name,
        'enabled': isEnabled,
      };
}

/// 策略组合器 - 按优先级链式执行策略
class StrategyPipeline {
  final String name;
  final List<ResilienceStrategy> _strategies = [];
  final ModuleLogger _logger;

  StrategyPipeline({required this.name})
      : _logger = AppLogger.instance.module('StrategyPipeline:$name');

  /// 添加策略
  StrategyPipeline addStrategy(ResilienceStrategy strategy) {
    _strategies.add(strategy);
    // 按优先级排序
    _strategies.sort((a, b) => a.priority.compareTo(b.priority));
    return this;
  }

  /// 移除策略
  bool removeStrategy(String strategyName) {
    final index = _strategies.indexWhere((s) => s.name == strategyName);
    if (index >= 0) {
      _strategies.removeAt(index);
      return true;
    }
    return false;
  }

  /// 获取策略
  ResilienceStrategy? getStrategy(String strategyName) {
    try {
      return _strategies.firstWhere((s) => s.name == strategyName);
    } on StateError {
      return null;
    }
  }

  /// 执行策略管道
  Future<StrategyResult<T>> execute<T>(
    Future<T> Function() operation, {
    required String serviceName,
    required String operationName,
    Map<String, dynamic>? attributes,
  }) async {
    final context = StrategyContext(
      serviceName: serviceName,
      operationName: operationName,
      attributes: attributes ?? {},
      startTime: DateTime.now(),
    );

    // 构建嵌套执行函数
    Future<StrategyResult<T>> executeWithStrategies(
      int index,
      Future<T> Function() op,
    ) async {
      // 找到下一个适用且启用的策略
      while (index < _strategies.length) {
        final strategy = _strategies[index];
        if (strategy.isEnabled && strategy.isApplicable(context)) {
          break;
        }
        index++;
      }

      if (index >= _strategies.length) {
        // 没有更多策略，直接执行
        final stopwatch = Stopwatch()..start();
        try {
          final result = await op();
          stopwatch.stop();
          return StrategyResult.success(
            result,
            strategy: 'direct',
            executionTime: stopwatch.elapsed,
          );
        } catch (e, stack) {
          stopwatch.stop();
          return StrategyResult.failure(
            e,
            stackTrace: stack,
            strategy: 'direct',
            executionTime: stopwatch.elapsed,
          );
        }
      }

      final strategy = _strategies[index];

      // 执行当前策略，包装下一层
      return strategy.execute<T>(
        () async {
          final innerResult = await executeWithStrategies(index + 1, op);
          if (innerResult.isSuccess) {
            return innerResult.value as T;
          } else {
            throw innerResult.error!;
          }
        },
        context,
      );
    }

    final result = await executeWithStrategies(0, operation);

    // 记录指标
    MetricsCollector.instance.recordRequest(
      service: serviceName,
      operation: operationName,
      success: result.isSuccess,
      duration: result.executionTime,
    );

    return result;
  }

  /// 获取管道状态
  Map<String, dynamic> getStatus() => {
        'name': name,
        'strategiesCount': _strategies.length,
        'strategies': _strategies.map((s) => s.getStatus()).toList(),
      };
}

/// 策略注册表
class StrategyRegistry {
  static final StrategyRegistry _instance = StrategyRegistry._();
  static StrategyRegistry get instance => _instance;

  StrategyRegistry._();

  final Map<String, StrategyPipeline> _pipelines = {};

  /// 获取或创建策略管道
  StrategyPipeline getOrCreate(String name) {
    return _pipelines.putIfAbsent(name, () => StrategyPipeline(name: name));
  }

  /// 获取策略管道
  StrategyPipeline? get(String name) => _pipelines[name];

  /// 创建默认管道配置
  StrategyPipeline createDefault(
    String name, {
    Duration timeout = const Duration(seconds: 30),
    int maxConcurrent = 50,
    CircuitBreaker? circuitBreaker,
    GlobalRateLimiter? rateLimiter,
  }) {
    final pipeline = StrategyPipeline(name: name);

    // 限流 (最高优先级)
    if (rateLimiter != null) {
      pipeline.addStrategy(RateLimitStrategy(rateLimiter: rateLimiter));
    }

    // 超时
    pipeline.addStrategy(TimeoutStrategy(timeout: timeout));

    // 熔断
    if (circuitBreaker != null) {
      pipeline.addStrategy(CircuitBreakerStrategy(circuitBreaker: circuitBreaker));
    }

    // 隔板
    pipeline.addStrategy(BulkheadStrategy(maxConcurrent: maxConcurrent));

    _pipelines[name] = pipeline;
    return pipeline;
  }

  /// 获取所有管道状态
  Map<String, dynamic> getAllStatus() =>
      _pipelines.map((k, v) => MapEntry(k, v.getStatus()));

  void clear() => _pipelines.clear();
}
