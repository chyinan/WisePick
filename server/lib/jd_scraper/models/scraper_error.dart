/// 爬虫错误类型枚举
enum ScraperErrorType {
  /// Cookie 已过期
  cookieExpired,

  /// 需要登录
  loginRequired,

  /// 被反爬虫系统检测
  antiBotDetected,

  /// 网络错误
  networkError,

  /// 请求超时
  timeout,

  /// 商品未找到
  productNotFound,

  /// 未知错误
  unknown,
}

/// 爬虫异常类
class ScraperException implements Exception {
  final ScraperErrorType type;
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  ScraperException({
    required this.type,
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  /// 创建 Cookie 过期异常
  factory ScraperException.cookieExpired([String? message]) {
    return ScraperException(
      type: ScraperErrorType.cookieExpired,
      message: message ?? 'Cookie 已过期，需要重新登录',
    );
  }

  /// 创建登录要求异常
  factory ScraperException.loginRequired([String? message]) {
    return ScraperException(
      type: ScraperErrorType.loginRequired,
      message: message ?? '当前操作需要登录',
    );
  }

  /// 创建反爬虫检测异常
  factory ScraperException.antiBotDetected([String? message]) {
    return ScraperException(
      type: ScraperErrorType.antiBotDetected,
      message: message ?? '被反爬虫系统检测，请稍后重试',
    );
  }

  /// 创建网络错误异常
  factory ScraperException.networkError(dynamic error, [StackTrace? stack]) {
    return ScraperException(
      type: ScraperErrorType.networkError,
      message: '网络错误: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
    );
  }

  /// 创建超时异常
  factory ScraperException.timeout([String? message]) {
    return ScraperException(
      type: ScraperErrorType.timeout,
      message: message ?? '请求超时',
    );
  }

  /// 创建商品未找到异常
  factory ScraperException.productNotFound([String? message]) {
    return ScraperException(
      type: ScraperErrorType.productNotFound,
      message: message ?? '未找到该商品信息',
    );
  }

  /// 创建未知错误异常
  factory ScraperException.unknown(dynamic error, [StackTrace? stack]) {
    return ScraperException(
      type: ScraperErrorType.unknown,
      message: '未知错误: ${error.toString()}',
      originalError: error,
      stackTrace: stack,
    );
  }

  @override
  String toString() => 'ScraperException(${type.name}): $message';

  /// 转换为 Map 格式，便于 JSON 序列化
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'message': message,
        if (originalError != null) 'originalError': originalError.toString(),
      };
}
