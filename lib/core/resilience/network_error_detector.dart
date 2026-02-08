import 'dart:io';

/// 网络错误类型
enum NetworkErrorType {
  /// 无网络连接
  noConnection,

  /// DNS 解析失败
  dnsFailure,

  /// 连接超时
  connectionTimeout,

  /// 连接被拒绝
  connectionRefused,

  /// 连接重置
  connectionReset,

  /// SSL/TLS 错误
  sslError,

  /// 服务器无响应
  serverUnreachable,

  /// 请求超时
  requestTimeout,

  /// 响应超时
  responseTimeout,

  /// 未知网络错误
  unknown,
}

/// 网络错误分析结果
class NetworkErrorAnalysis {
  final NetworkErrorType type;
  final String message;
  final bool isRetryable;
  final Duration suggestedRetryDelay;
  final String userFriendlyMessage;

  const NetworkErrorAnalysis({
    required this.type,
    required this.message,
    required this.isRetryable,
    required this.suggestedRetryDelay,
    required this.userFriendlyMessage,
  });

  factory NetworkErrorAnalysis.fromType(NetworkErrorType type, String originalMessage) {
    switch (type) {
      case NetworkErrorType.noConnection:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 5),
          userFriendlyMessage: '无网络连接，请检查您的网络设置',
        );
      case NetworkErrorType.dnsFailure:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 10),
          userFriendlyMessage: '无法解析服务器地址，请检查网络连接',
        );
      case NetworkErrorType.connectionTimeout:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 3),
          userFriendlyMessage: '连接超时，服务器可能繁忙，请稍后重试',
        );
      case NetworkErrorType.connectionRefused:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 30),
          userFriendlyMessage: '无法连接到服务器，服务可能暂时不可用',
        );
      case NetworkErrorType.connectionReset:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 2),
          userFriendlyMessage: '连接被重置，正在尝试重新连接',
        );
      case NetworkErrorType.sslError:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: false,
          suggestedRetryDelay: Duration.zero,
          userFriendlyMessage: '安全连接失败，请检查系统时间是否正确',
        );
      case NetworkErrorType.serverUnreachable:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 15),
          userFriendlyMessage: '服务器无法访问，请检查网络连接',
        );
      case NetworkErrorType.requestTimeout:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 5),
          userFriendlyMessage: '请求超时，请稍后重试',
        );
      case NetworkErrorType.responseTimeout:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 10),
          userFriendlyMessage: '服务器响应超时，请稍后重试',
        );
      case NetworkErrorType.unknown:
        return NetworkErrorAnalysis(
          type: type,
          message: originalMessage,
          isRetryable: true,
          suggestedRetryDelay: const Duration(seconds: 5),
          userFriendlyMessage: '网络错误，请稍后重试',
        );
    }
  }
}

/// 网络错误检测器
///
/// 用于分析和分类网络错误，提供更好的错误处理策略
class NetworkErrorDetector {
  /// 分析错误
  static NetworkErrorAnalysis analyze(Object error) {
    final type = detectType(error);
    return NetworkErrorAnalysis.fromType(type, error.toString());
  }

  /// 检测错误类型
  static NetworkErrorType detectType(Object error) {
    // 处理 SocketException
    if (error is SocketException) {
      return _analyzeSocketException(error);
    }

    // 处理 HttpException
    if (error is HttpException) {
      return _analyzeHttpException(error);
    }

    // 处理 HandshakeException (SSL)
    if (error is HandshakeException) {
      return NetworkErrorType.sslError;
    }

    // 处理字符串错误消息
    final errorStr = error.toString().toLowerCase();
    return _analyzeErrorString(errorStr);
  }

  /// 分析 SocketException
  static NetworkErrorType _analyzeSocketException(SocketException e) {
    final message = e.message.toLowerCase();
    final osErrorMessage = e.osError?.message.toLowerCase() ?? '';

    // 连接被拒绝
    if (message.contains('connection refused') ||
        osErrorMessage.contains('connection refused') ||
        e.osError?.errorCode == 111 || // Linux ECONNREFUSED
        e.osError?.errorCode == 10061) {
      // Windows WSAECONNREFUSED
      return NetworkErrorType.connectionRefused;
    }

    // 连接重置
    if (message.contains('connection reset') ||
        osErrorMessage.contains('connection reset') ||
        e.osError?.errorCode == 104 || // Linux ECONNRESET
        e.osError?.errorCode == 10054) {
      // Windows WSAECONNRESET
      return NetworkErrorType.connectionReset;
    }

    // 无网络
    if (message.contains('network is unreachable') ||
        osErrorMessage.contains('network is unreachable') ||
        e.osError?.errorCode == 101 || // Linux ENETUNREACH
        e.osError?.errorCode == 10051) {
      // Windows WSAENETUNREACH
      return NetworkErrorType.noConnection;
    }

    // DNS 解析失败
    if (message.contains('host not found') ||
        message.contains('failed host lookup') ||
        osErrorMessage.contains('no address') ||
        e.osError?.errorCode == -2 || // EAI_NONAME
        e.osError?.errorCode == 11001) {
      // Windows WSAHOST_NOT_FOUND
      return NetworkErrorType.dnsFailure;
    }

    // 连接超时
    if (message.contains('timed out') ||
        osErrorMessage.contains('timed out') ||
        e.osError?.errorCode == 110 || // Linux ETIMEDOUT
        e.osError?.errorCode == 10060) {
      // Windows WSAETIMEDOUT
      return NetworkErrorType.connectionTimeout;
    }

    return NetworkErrorType.unknown;
  }

  /// 分析 HttpException
  static NetworkErrorType _analyzeHttpException(HttpException e) {
    final message = e.message.toLowerCase();

    if (message.contains('connection closed')) {
      return NetworkErrorType.connectionReset;
    }

    if (message.contains('timed out')) {
      return NetworkErrorType.requestTimeout;
    }

    return NetworkErrorType.unknown;
  }

  /// 分析错误字符串
  static NetworkErrorType _analyzeErrorString(String errorStr) {
    // 超时相关
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      if (errorStr.contains('connection')) {
        return NetworkErrorType.connectionTimeout;
      }
      if (errorStr.contains('receive') || errorStr.contains('response')) {
        return NetworkErrorType.responseTimeout;
      }
      if (errorStr.contains('send') || errorStr.contains('request')) {
        return NetworkErrorType.requestTimeout;
      }
      return NetworkErrorType.connectionTimeout;
    }

    // 连接相关
    if (errorStr.contains('connection refused')) {
      return NetworkErrorType.connectionRefused;
    }
    if (errorStr.contains('connection reset') || errorStr.contains('broken pipe')) {
      return NetworkErrorType.connectionReset;
    }
    if (errorStr.contains('connection failed') || errorStr.contains('connection error')) {
      return NetworkErrorType.noConnection;
    }

    // DNS 相关
    if (errorStr.contains('host not found') ||
        errorStr.contains('dns') ||
        errorStr.contains('failed host lookup') ||
        errorStr.contains('no address associated')) {
      return NetworkErrorType.dnsFailure;
    }

    // SSL/TLS 相关
    if (errorStr.contains('ssl') ||
        errorStr.contains('tls') ||
        errorStr.contains('certificate') ||
        errorStr.contains('handshake')) {
      return NetworkErrorType.sslError;
    }

    // 网络不可达
    if (errorStr.contains('network is unreachable') ||
        errorStr.contains('no route to host') ||
        errorStr.contains('network unreachable')) {
      return NetworkErrorType.serverUnreachable;
    }

    // Socket 相关
    if (errorStr.contains('socketexception') || errorStr.contains('socket')) {
      return NetworkErrorType.noConnection;
    }

    return NetworkErrorType.unknown;
  }

  /// 判断错误是否为网络错误
  static bool isNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is HandshakeException) return true;

    final type = detectType(error);
    return type != NetworkErrorType.unknown;
  }

  /// 判断错误是否可重试
  static bool isRetryable(Object error) {
    final analysis = analyze(error);
    return analysis.isRetryable;
  }

  /// 获取建议的重试延迟
  static Duration getSuggestedRetryDelay(Object error) {
    final analysis = analyze(error);
    return analysis.suggestedRetryDelay;
  }

  /// 获取用户友好的错误消息
  static String getUserFriendlyMessage(Object error) {
    final analysis = analyze(error);
    return analysis.userFriendlyMessage;
  }
}

/// 便捷函数：判断是否为网络错误
bool isNetworkError(Object error) => NetworkErrorDetector.isNetworkError(error);

/// 便捷函数：判断网络错误是否可重试
bool isRetryableNetworkError(Object error) => NetworkErrorDetector.isRetryable(error);

/// 便捷函数：分析网络错误
NetworkErrorAnalysis analyzeNetworkError(Object error) => NetworkErrorDetector.analyze(error);
