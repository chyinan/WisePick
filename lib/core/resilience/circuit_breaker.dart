import 'dart:async';
import 'dart:developer' as dev;

/// 电路断路器状态
enum CircuitState {
  /// 关闭状态 - 正常运行
  closed,

  /// 打开状态 - 拒绝所有请求
  open,

  /// 半开状态 - 允许有限请求进行测试
  halfOpen,
}

/// 电路断路器配置
class CircuitBreakerConfig {
  /// 打开电路前的失败次数阈值
  final int failureThreshold;

  /// 打开电路前的失败率阈值 (0.0 - 1.0)
  final double failureRateThreshold;

  /// 统计窗口大小（请求数量）
  final int windowSize;

  /// 电路打开后的重置超时时间
  final Duration resetTimeout;

  /// 半开状态下允许的测试请求数量
  final int halfOpenRequests;

  /// 半开状态成功后关闭电路的阈值
  final int successThreshold;

  /// 是否记录详细日志
  final bool verbose;

  /// 电路打开时的回调
  final void Function()? onOpen;

  /// 电路关闭时的回调
  final void Function()? onClose;

  /// 电路半开时的回调
  final void Function()? onHalfOpen;

  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.failureRateThreshold = 0.5,
    this.windowSize = 10,
    this.resetTimeout = const Duration(seconds: 30),
    this.halfOpenRequests = 3,
    this.successThreshold = 2,
    this.verbose = false,
    this.onOpen,
    this.onClose,
    this.onHalfOpen,
  });

  /// 敏感配置 - 快速断开
  static const CircuitBreakerConfig sensitive = CircuitBreakerConfig(
    failureThreshold: 3,
    failureRateThreshold: 0.3,
    windowSize: 5,
    resetTimeout: Duration(seconds: 15),
  );

  /// 宽松配置 - 容忍更多失败
  static const CircuitBreakerConfig tolerant = CircuitBreakerConfig(
    failureThreshold: 10,
    failureRateThreshold: 0.7,
    windowSize: 20,
    resetTimeout: Duration(seconds: 60),
  );

  /// AI 服务配置 - 考虑 API 限流
  ///
  /// [successThreshold] must be ≤ [halfOpenRequests]; otherwise the circuit
  /// can never collect enough successes to close and will deadlock in
  /// half-open state.
  static const CircuitBreakerConfig aiService = CircuitBreakerConfig(
    failureThreshold: 3,
    failureRateThreshold: 0.5,
    windowSize: 10,
    resetTimeout: Duration(seconds: 60),
    halfOpenRequests: 1,
    successThreshold: 1,
  );
}

/// 电路断路器异常
class CircuitBreakerException implements Exception {
  final String message;
  final CircuitState state;
  final Duration? remainingTimeout;

  CircuitBreakerException({
    required this.message,
    required this.state,
    this.remainingTimeout,
  });

  @override
  String toString() {
    var msg = 'CircuitBreakerException: $message (state: ${state.name})';
    if (remainingTimeout != null) {
      msg += ', will reset in ${remainingTimeout!.inSeconds}s';
    }
    return msg;
  }
}

/// 请求结果记录
class _RequestResult {
  final bool success;
  final DateTime timestamp;

  _RequestResult({required this.success, required this.timestamp});
}

/// 电路断路器
///
/// 保护下游服务免受级联故障影响
class CircuitBreaker {
  final String name;
  final CircuitBreakerConfig config;

  CircuitState _state = CircuitState.closed;
  DateTime? _openedAt;
  int _halfOpenSuccesses = 0;
  int _halfOpenRequests = 0;
  final List<_RequestResult> _results = [];

  CircuitBreaker({
    required this.name,
    CircuitBreakerConfig? config,
  }) : config = config ?? const CircuitBreakerConfig();

  /// 当前状态
  CircuitState get state => _state;

  /// Check and acquire permission to send a request.
  ///
  /// This is a **mutating** method, not a pure getter — it may:
  /// - transition the state from [CircuitState.open] → [CircuitState.halfOpen]
  ///   when the reset timeout has elapsed;
  /// - increment the half-open request counter so the limit is enforced.
  ///
  /// Callers that only need a read-only status check should use [state] instead.
  bool allowRequest() {
    switch (_state) {
      case CircuitState.closed:
        return true;
      case CircuitState.open:
        // 检查是否应该转换为半开状态
        if (_shouldTransitionToHalfOpen()) {
          _transitionTo(CircuitState.halfOpen);
          _halfOpenRequests++; // count this probe request
          return true;
        }
        return false;
      case CircuitState.halfOpen:
        // 限制半开状态下的请求数
        if (_halfOpenRequests < config.halfOpenRequests) {
          _halfOpenRequests++;
          return true;
        }
        return false;
    }
  }

  /// 执行受保护的操作
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (!allowRequest()) {
      final remaining = _getRemainingTimeout();
      throw CircuitBreakerException(
        message: 'Circuit [$name] is open, rejecting request',
        state: _state,
        remainingTimeout: remaining,
      );
    }

    // _halfOpenRequests already incremented inside allowRequest()

    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  /// 尝试执行，失败时返回 null
  Future<T?> tryExecute<T>(Future<T> Function() operation) async {
    try {
      return await execute(operation);
    } catch (e) {
      if (e is CircuitBreakerException) {
        _log('Request rejected: ${e.message}');
      }
      return null;
    }
  }

  /// 执行带降级的操作
  Future<T> executeWithFallback<T>(
    Future<T> Function() operation,
    Future<T> Function() fallback,
  ) async {
    try {
      return await execute(operation);
    } catch (e) {
      _log('Executing fallback due to: $e');
      return await fallback();
    }
  }

  /// 记录成功
  void _onSuccess() {
    _recordResult(true);

    if (_state == CircuitState.halfOpen) {
      _halfOpenSuccesses++;
      _log('Half-open success: $_halfOpenSuccesses/${config.successThreshold}');

      // Clamp: if config.successThreshold > config.halfOpenRequests we can
      // never collect enough successes.  Use the smaller of the two to
      // avoid a permanent half-open deadlock.
      final effectiveThreshold =
          config.successThreshold <= config.halfOpenRequests
              ? config.successThreshold
              : config.halfOpenRequests;

      if (_halfOpenSuccesses >= effectiveThreshold) {
        _transitionTo(CircuitState.closed);
      }
    }
  }

  /// 记录失败
  void _onFailure() {
    _recordResult(false);

    if (_state == CircuitState.halfOpen) {
      // 半开状态下失败立即打开电路
      _transitionTo(CircuitState.open);
      return;
    }

    if (_state == CircuitState.closed) {
      // 检查是否应该打开电路
      if (_shouldOpenCircuit()) {
        _transitionTo(CircuitState.open);
      }
    }
  }

  /// 记录请求结果
  void _recordResult(bool success) {
    final now = DateTime.now();
    _results.add(_RequestResult(success: success, timestamp: now));

    // 保持窗口大小
    while (_results.length > config.windowSize) {
      _results.removeAt(0);
    }
  }

  /// 检查是否应该打开电路
  bool _shouldOpenCircuit() {
    // Guard: no data → cannot determine failure rate (also avoids 0/0 NaN
    // when windowSize is configured to 0).
    if (_results.isEmpty) {
      return false;
    }
    if (_results.length < config.windowSize ~/ 2) {
      // 样本不足
      return false;
    }

    // 计算最近的失败数
    final failures = _results.where((r) => !r.success).length;

    // 检查失败次数阈值
    if (failures >= config.failureThreshold) {
      _log('Failure threshold reached: $failures/${config.failureThreshold}');
      return true;
    }

    // 检查失败率阈值
    final failureRate = failures / _results.length;
    if (failureRate >= config.failureRateThreshold) {
      _log('Failure rate threshold reached: ${(failureRate * 100).toStringAsFixed(1)}%');
      return true;
    }

    return false;
  }

  /// 检查是否应该转换为半开状态
  bool _shouldTransitionToHalfOpen() {
    if (_openedAt == null) return false;
    return DateTime.now().difference(_openedAt!) >= config.resetTimeout;
  }

  /// 状态转换
  void _transitionTo(CircuitState newState) {
    final oldState = _state;
    _state = newState;

    _log('State transition: ${oldState.name} -> ${newState.name}');

    switch (newState) {
      case CircuitState.closed:
        _resetCounters();
        // Clear stale failure results on recovery to prevent immediate re-trip
        // from old window data that no longer reflects current health.
        if (oldState == CircuitState.halfOpen) {
          _results.clear();
        }
        config.onClose?.call();
        break;
      case CircuitState.open:
        _openedAt = DateTime.now();
        _resetCounters();
        config.onOpen?.call();
        break;
      case CircuitState.halfOpen:
        _halfOpenRequests = 0;
        _halfOpenSuccesses = 0;
        config.onHalfOpen?.call();
        break;
    }
  }

  /// 重置计数器
  void _resetCounters() {
    _halfOpenRequests = 0;
    _halfOpenSuccesses = 0;
  }

  /// 获取剩余超时时间
  Duration? _getRemainingTimeout() {
    if (_openedAt == null) return null;
    final elapsed = DateTime.now().difference(_openedAt!);
    final remaining = config.resetTimeout - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// 手动重置电路（用于测试或管理）
  void reset() {
    _transitionTo(CircuitState.closed);
    _results.clear();
    _openedAt = null;
    _log('Circuit manually reset');
  }

  /// 公开的成功记录方法（供外部调用）
  void recordSuccess() {
    _onSuccess();
  }

  /// 公开的失败记录方法（供外部调用）
  void recordFailure() {
    _onFailure();
  }

  /// 强制打开电路（用于维护模式）
  void forceOpen() {
    _transitionTo(CircuitState.open);
    _log('Circuit forcibly opened');
  }

  /// 获取状态摘要
  Map<String, dynamic> getStatus() {
    final failures = _results.where((r) => !r.success).length;
    final total = _results.length;
    final failureRate = total > 0 ? (failures / total * 100) : 0.0;

    return {
      'name': name,
      'state': _state.name,
      'failures': failures,
      'total': total,
      'failureRate': '${failureRate.toStringAsFixed(1)}%',
      'openedAt': _openedAt?.toIso8601String(),
      'remainingTimeout': _getRemainingTimeout()?.inSeconds,
      'halfOpenRequests': _halfOpenRequests,
      'halfOpenSuccesses': _halfOpenSuccesses,
    };
  }

  void _log(String message) {
    if (config.verbose) {
      dev.log(message, name: 'CircuitBreaker:$name');
    }
  }
}

/// 电路断路器注册表 - 管理多个断路器
class CircuitBreakerRegistry {
  static final CircuitBreakerRegistry _instance = CircuitBreakerRegistry._();
  static CircuitBreakerRegistry get instance => _instance;

  CircuitBreakerRegistry._();

  final Map<String, CircuitBreaker> _breakers = {};

  /// 获取或创建断路器
  CircuitBreaker getOrCreate(String name, {CircuitBreakerConfig? config}) {
    return _breakers.putIfAbsent(
      name,
      () => CircuitBreaker(name: name, config: config),
    );
  }

  /// 获取断路器
  CircuitBreaker? get(String name) => _breakers[name];

  /// 获取所有断路器状态
  Map<String, dynamic> getAllStatus() {
    return _breakers.map((name, breaker) => MapEntry(name, breaker.getStatus()));
  }

  /// 重置所有断路器
  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }

  /// 移除断路器
  void remove(String name) {
    _breakers.remove(name);
  }

  /// 清除所有断路器
  void clear() {
    _breakers.clear();
  }
}

/// 便捷函数：获取带电路断路器保护的执行
Future<T> withCircuitBreaker<T>(
  String name,
  Future<T> Function() operation, {
  CircuitBreakerConfig? config,
}) {
  final breaker = CircuitBreakerRegistry.instance.getOrCreate(name, config: config);
  return breaker.execute(operation);
}

/// 便捷函数：带降级的电路断路器执行
Future<T> withCircuitBreakerFallback<T>(
  String name,
  Future<T> Function() operation,
  Future<T> Function() fallback, {
  CircuitBreakerConfig? config,
}) {
  final breaker = CircuitBreakerRegistry.instance.getOrCreate(name, config: config);
  return breaker.executeWithFallback(operation, fallback);
}
