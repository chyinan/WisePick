/// 统一的操作结果类型
///
/// 用于替代抛出异常的错误处理模式，使错误处理更加显式和可控
sealed class Result<T> {
  const Result();

  /// 创建成功结果
  factory Result.success(T value) = Success<T>;

  /// 创建失败结果
  factory Result.failure(Failure failure) = FailureResult<T>;

  /// 从可能抛出异常的操作创建结果
  static Future<Result<T>> fromAsync<T>(Future<T> Function() operation) async {
    try {
      final value = await operation();
      return Result.success(value);
    } catch (e, stack) {
      return Result.failure(Failure(
        message: e.toString(),
        error: e,
        stackTrace: stack,
      ));
    }
  }

  /// 从同步操作创建结果
  static Result<T> fromSync<T>(T Function() operation) {
    try {
      final value = operation();
      return Result.success(value);
    } catch (e, stack) {
      return Result.failure(Failure(
        message: e.toString(),
        error: e,
        stackTrace: stack,
      ));
    }
  }

  /// 是否成功
  bool get isSuccess => this is Success<T>;

  /// 是否失败
  bool get isFailure => this is FailureResult<T>;

  /// 获取值（成功时）
  T? get valueOrNull => isSuccess ? (this as Success<T>).value : null;

  /// 获取错误（失败时）
  Failure? get failureOrNull => isFailure ? (this as FailureResult<T>).failure : null;

  /// 获取值，失败时抛出异常
  T getOrThrow() {
    if (this is Success<T>) {
      return (this as Success<T>).value;
    }
    final failure = (this as FailureResult<T>).failure;
    if (failure.stackTrace != null && failure.error != null) {
      Error.throwWithStackTrace(failure.error!, failure.stackTrace!);
    }
    throw failure.error ?? Exception(failure.message);
  }

  /// 获取值，失败时返回默认值
  T getOrDefault(T defaultValue) {
    if (this is Success<T>) {
      return (this as Success<T>).value;
    }
    return defaultValue;
  }

  /// 获取值，失败时执行函数获取默认值
  T getOrElse(T Function(Failure failure) orElse) {
    if (this is Success<T>) {
      return (this as Success<T>).value;
    }
    return orElse((this as FailureResult<T>).failure);
  }

  /// 映射成功值
  Result<R> map<R>(R Function(T value) mapper) {
    if (this is Success<T>) {
      return Result.success(mapper((this as Success<T>).value));
    }
    return Result.failure((this as FailureResult<T>).failure);
  }

  /// 异步映射成功值
  Future<Result<R>> mapAsync<R>(Future<R> Function(T value) mapper) async {
    if (this is Success<T>) {
      try {
        final mapped = await mapper((this as Success<T>).value);
        return Result.success(mapped);
      } catch (e, stack) {
        return Result.failure(Failure(
          message: e.toString(),
          error: e,
          stackTrace: stack,
        ));
      }
    }
    return Result.failure((this as FailureResult<T>).failure);
  }

  /// 扁平映射
  Result<R> flatMap<R>(Result<R> Function(T value) mapper) {
    if (this is Success<T>) {
      return mapper((this as Success<T>).value);
    }
    return Result.failure((this as FailureResult<T>).failure);
  }

  /// 处理成功
  Result<T> onSuccess(void Function(T value) action) {
    if (this is Success<T>) {
      action((this as Success<T>).value);
    }
    return this;
  }

  /// 处理失败
  Result<T> onFailure(void Function(Failure failure) action) {
    if (this is FailureResult<T>) {
      action((this as FailureResult<T>).failure);
    }
    return this;
  }

  /// 恢复：失败时尝试使用备选值
  Result<T> recover(T Function(Failure failure) recovery) {
    if (this is FailureResult<T>) {
      try {
        return Result.success(recovery((this as FailureResult<T>).failure));
      } catch (e, stack) {
        return Result.failure(Failure(
          message: e.toString(),
          error: e,
          stackTrace: stack,
        ));
      }
    }
    return this;
  }

  /// 异步恢复
  Future<Result<T>> recoverAsync(Future<T> Function(Failure failure) recovery) async {
    if (this is FailureResult<T>) {
      try {
        final value = await recovery((this as FailureResult<T>).failure);
        return Result.success(value);
      } catch (e, stack) {
        return Result.failure(Failure(
          message: e.toString(),
          error: e,
          stackTrace: stack,
        ));
      }
    }
    return this;
  }

  /// 模式匹配
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    if (this is Success<T>) {
      return onSuccess((this as Success<T>).value);
    }
    return onFailure((this as FailureResult<T>).failure);
  }
}

/// 成功结果
class Success<T> extends Result<T> {
  final T value;

  const Success(this.value);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Success<T> && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// 失败结果
class FailureResult<T> extends Result<T> {
  final Failure failure;

  const FailureResult(this.failure);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FailureResult<T> && other.failure == failure;
  }

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Failure($failure)';
}

/// 失败详情
class Failure {
  /// 错误消息
  final String message;

  /// 错误代码
  final String? code;

  /// 原始错误对象
  final Object? error;

  /// 堆栈跟踪
  final StackTrace? stackTrace;

  /// 额外上下文信息
  final Map<String, dynamic>? context;

  /// 是否可重试
  final bool retryable;

  const Failure({
    required this.message,
    this.code,
    this.error,
    this.stackTrace,
    this.context,
    this.retryable = true,
  });

  /// 网络错误
  factory Failure.network({
    String message = '网络连接失败',
    Object? error,
    StackTrace? stackTrace,
  }) {
    return Failure(
      message: message,
      code: 'NETWORK_ERROR',
      error: error,
      stackTrace: stackTrace,
      retryable: true,
    );
  }

  /// 超时错误
  factory Failure.timeout({
    String message = '请求超时',
    Object? error,
    StackTrace? stackTrace,
  }) {
    return Failure(
      message: message,
      code: 'TIMEOUT',
      error: error,
      stackTrace: stackTrace,
      retryable: true,
    );
  }

  /// 认证错误
  factory Failure.authentication({
    String message = '认证失败',
    Object? error,
    StackTrace? stackTrace,
  }) {
    return Failure(
      message: message,
      code: 'AUTH_ERROR',
      error: error,
      stackTrace: stackTrace,
      retryable: false,
    );
  }

  /// 验证错误
  factory Failure.validation({
    required String message,
    Map<String, dynamic>? context,
  }) {
    return Failure(
      message: message,
      code: 'VALIDATION_ERROR',
      context: context,
      retryable: false,
    );
  }

  /// 服务器错误
  factory Failure.server({
    String message = '服务器错误',
    Object? error,
    StackTrace? stackTrace,
  }) {
    return Failure(
      message: message,
      code: 'SERVER_ERROR',
      error: error,
      stackTrace: stackTrace,
      retryable: true,
    );
  }

  /// 未知错误
  factory Failure.unknown({
    String message = '未知错误',
    Object? error,
    StackTrace? stackTrace,
  }) {
    return Failure(
      message: message,
      code: 'UNKNOWN_ERROR',
      error: error,
      stackTrace: stackTrace,
      retryable: false,
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toJson() => {
        'message': message,
        if (code != null) 'code': code,
        if (error != null) 'error': error.toString(),
        if (context != null) 'context': context,
        'retryable': retryable,
      };

  @override
  String toString() => 'Failure(${code ?? 'UNKNOWN'}: $message)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Failure && other.message == message && other.code == code;
  }

  @override
  int get hashCode => Object.hash(message, code);
}

/// 空值结果 - 用于不返回值的操作
typedef UnitResult = Result<Unit>;

/// 空值单位类型
class Unit {
  const Unit._();
  static const Unit instance = Unit._();
}

/// 创建成功的空值结果
UnitResult unitSuccess() => Result.success(Unit.instance);

/// 创建失败的空值结果
UnitResult unitFailure(Failure failure) => Result.failure(failure);
