import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

/// 重试策略配置
class RetryConfig {
  /// 最大重试次数
  final int maxAttempts;

  /// 初始延迟时间
  final Duration initialDelay;

  /// 最大延迟时间
  final Duration maxDelay;

  /// 退避乘数
  final double backoffMultiplier;

  /// 是否添加随机抖动
  final bool addJitter;

  /// 可重试的异常类型判断函数
  final bool Function(Object error)? retryIf;

  /// 重试前的回调（可用于日志记录）
  final void Function(int attempt, Duration delay, Object error)? onRetry;

  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.addJitter = true,
    this.retryIf,
    this.onRetry,
  });

  /// 默认配置 - 适用于一般网络请求
  static const RetryConfig defaultConfig = RetryConfig();

  /// 激进重试 - 适用于关键操作
  static const RetryConfig aggressive = RetryConfig(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 200),
    maxDelay: Duration(seconds: 60),
  );

  /// 保守重试 - 适用于非关键操作
  static const RetryConfig conservative = RetryConfig(
    maxAttempts: 2,
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 10),
  );

  /// 数据库操作配置
  static const RetryConfig database = RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 100),
    maxDelay: Duration(seconds: 5),
    backoffMultiplier: 1.5,
  );

  /// AI 服务配置 - 较长超时
  static const RetryConfig aiService = RetryConfig(
    maxAttempts: 2,
    initialDelay: Duration(seconds: 2),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 2.0,
  );
}

/// 重试执行结果
class RetryResult<T> {
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
  final int attemptsMade;
  final Duration totalDuration;
  final bool wasRetried;

  const RetryResult._({
    this.value,
    this.error,
    this.stackTrace,
    required this.attemptsMade,
    required this.totalDuration,
    required this.wasRetried,
  });

  bool get isSuccess => error == null;
  bool get isFailure => error != null;

  /// 获取值，失败时抛出异常
  T getOrThrow() {
    if (error != null) {
      if (stackTrace != null) {
        Error.throwWithStackTrace(error!, stackTrace!);
      }
      throw error!;
    }
    return value as T;
  }

  /// 获取值，失败时返回默认值
  T getOrDefault(T defaultValue) {
    if (error != null) return defaultValue;
    return value as T;
  }

  /// 获取值，失败时执行函数获取默认值
  T getOrElse(T Function() orElse) {
    if (error != null) return orElse();
    return value as T;
  }

  /// 成功结果
  factory RetryResult.success(
    T value, {
    required int attemptsMade,
    required Duration totalDuration,
    bool wasRetried = false,
  }) {
    return RetryResult._(
      value: value,
      attemptsMade: attemptsMade,
      totalDuration: totalDuration,
      wasRetried: wasRetried,
    );
  }

  /// 失败结果
  factory RetryResult.failure(
    Object error, {
    StackTrace? stackTrace,
    required int attemptsMade,
    required Duration totalDuration,
    bool wasRetried = false,
  }) {
    return RetryResult._(
      error: error,
      stackTrace: stackTrace,
      attemptsMade: attemptsMade,
      totalDuration: totalDuration,
      wasRetried: wasRetried,
    );
  }
}

/// 带指数退避的重试执行器
class RetryExecutor {
  final RetryConfig config;
  final Random _random = Random();

  RetryExecutor({RetryConfig? config}) : config = config ?? const RetryConfig();

  /// 执行带重试的操作
  Future<RetryResult<T>> execute<T>(
    Future<T> Function() operation, {
    String? operationName,
    bool Function(Object error)? retryIf,
  }) async {
    // Guard: maxAttempts <= 0 means "no attempts" — return immediately
    // rather than force-unwrapping a null lastError below.
    if (config.maxAttempts <= 0) {
      return RetryResult.failure(
        StateError('RetryConfig.maxAttempts must be >= 1 (was ${config.maxAttempts})'),
        attemptsMade: 0,
        totalDuration: Duration.zero,
      );
    }

    final stopwatch = Stopwatch()..start();
    Object? lastError;
    StackTrace? lastStackTrace;
    int attempt = 0;

    while (attempt < config.maxAttempts) {
      attempt++;
      try {
        final result = await operation();
        stopwatch.stop();
        return RetryResult.success(
          result,
          attemptsMade: attempt,
          totalDuration: stopwatch.elapsed,
          wasRetried: attempt > 1,
        );
      } catch (e, stack) {
        lastError = e;
        lastStackTrace = stack;

        // 检查是否应该重试
        final shouldRetry = _shouldRetry(e, attempt, retryIf);
        if (!shouldRetry) {
          break;
        }

        // 计算延迟
        final delay = _calculateDelay(attempt);

        // 调用重试回调
        config.onRetry?.call(attempt, delay, e);

        // 记录重试日志
        _logRetry(operationName, attempt, delay, e);

        // 等待后重试
        await Future.delayed(delay);
      }
    }

    stopwatch.stop();
    return RetryResult.failure(
      lastError!,
      stackTrace: lastStackTrace,
      attemptsMade: attempt,
      totalDuration: stopwatch.elapsed,
      wasRetried: attempt > 1,
    );
  }

  /// 执行带重试的操作，失败时抛出异常
  Future<T> executeOrThrow<T>(
    Future<T> Function() operation, {
    String? operationName,
    bool Function(Object error)? retryIf,
  }) async {
    final result = await execute(
      operation,
      operationName: operationName,
      retryIf: retryIf,
    );
    return result.getOrThrow();
  }

  /// 判断是否应该重试
  bool _shouldRetry(Object error, int attempt, bool Function(Object)? retryIf) {
    // 已达最大尝试次数
    if (attempt >= config.maxAttempts) return false;

    // 使用自定义判断函数
    final customRetryIf = retryIf ?? config.retryIf;
    if (customRetryIf != null) {
      return customRetryIf(error);
    }

    // 默认：对常见可重试错误进行重试
    return _isRetryableError(error);
  }

  /// Determine whether [error] is retryable using type-safe checks.
  ///
  /// Prefers concrete exception types over fragile `toString()` matching
  /// to avoid false positives (e.g. a product price "429.99" matching "429").
  bool _isRetryableError(Object error) {
    // ── Type-safe checks (most reliable) ──

    // dart:io network errors
    if (error is SocketException || error is HttpException) return true;
    if (error is HandshakeException) return false; // SSL errors are not transient
    if (error is TimeoutException) return true;

    // HTTP status-code based retryability (works with any wrapper that
    // exposes a statusCode field, e.g. DioException.response?.statusCode).
    final statusCode = _extractStatusCode(error);
    if (statusCode != null) {
      // 429 Too Many Requests, 5xx server errors → retryable
      if (statusCode == 429 || (statusCode >= 500 && statusCode < 600)) {
        return true;
      }
      // Other 4xx client errors → not retryable
      if (statusCode >= 400 && statusCode < 500) {
        return false;
      }
    }

    // ── Fallback: conservative string matching for unknown error types ──
    final errorStr = error.toString().toLowerCase();

    // Network-layer keywords (unlikely to appear in business data)
    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('broken pipe') ||
        errorStr.contains('host not found') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('network is unreachable')) {
      return true;
    }

    // Database transient errors
    if (errorStr.contains('deadlock') ||
        errorStr.contains('lock wait') ||
        errorStr.contains('serialization failure')) {
      return true;
    }

    // Default: don't retry unknown errors
    return false;
  }

  /// Try to extract an HTTP status code from the error.
  /// Supports DioException and HttpException with status codes.
  int? _extractStatusCode(Object error) {
    // DioException (from package:dio) — accessed dynamically to avoid
    // a hard dependency on dio in this resilience module.
    try {
      final dynamic e = error;
      // ignore: avoid_dynamic_calls
      final response = e.response;
      if (response != null) {
        // ignore: avoid_dynamic_calls
        final code = response.statusCode;
        if (code is int) return code;
      }
    } catch (e) {
      // Expected when error doesn't have a response field (non-Dio errors)
    }
    return null;
  }

  /// 计算重试延迟（指数退避 + 抖动）
  Duration _calculateDelay(int attempt) {
    // 指数退避: initialDelay * (multiplier ^ (attempt - 1))
    final exponentialDelay = config.initialDelay.inMilliseconds *
        pow(config.backoffMultiplier, attempt - 1);

    // 限制最大延迟
    var delayMs = min(exponentialDelay, config.maxDelay.inMilliseconds).toInt();

    // 添加随机抖动 (±25%)
    if (config.addJitter) {
      final jitter = (delayMs * 0.25 * (_random.nextDouble() * 2 - 1)).toInt();
      delayMs += jitter;
    }

    return Duration(milliseconds: max(0, delayMs));
  }

  /// 记录重试日志
  void _logRetry(String? operationName, int attempt, Duration delay, Object error) {
    final opName = operationName ?? 'operation';
    dev.log(
      '$opName attempt $attempt/${config.maxAttempts} failed, '
      'retrying in ${delay.inMilliseconds}ms. Error: $error',
      name: 'RetryExecutor',
    );
  }
}

/// 便捷的重试函数
Future<RetryResult<T>> retry<T>(
  Future<T> Function() operation, {
  RetryConfig config = const RetryConfig(),
  String? operationName,
  bool Function(Object error)? retryIf,
}) {
  return RetryExecutor(config: config).execute(
    operation,
    operationName: operationName,
    retryIf: retryIf,
  );
}

/// 便捷的重试函数（失败时抛出异常）
Future<T> retryOrThrow<T>(
  Future<T> Function() operation, {
  RetryConfig config = const RetryConfig(),
  String? operationName,
  bool Function(Object error)? retryIf,
}) {
  return RetryExecutor(config: config).executeOrThrow(
    operation,
    operationName: operationName,
    retryIf: retryIf,
  );
}

/// 带超时的重试
Future<RetryResult<T>> retryWithTimeout<T>(
  Future<T> Function() operation, {
  required Duration timeout,
  RetryConfig config = const RetryConfig(),
  String? operationName,
}) async {
  return retry(
    () => operation().timeout(
      timeout,
      onTimeout: () => throw TimeoutException('Operation timed out', timeout),
    ),
    config: config,
    operationName: operationName,
  );
}
