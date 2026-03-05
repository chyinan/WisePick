import 'package:dio/dio.dart';

/// Categorized error types for chat AI interactions
enum ChatErrorType {
  /// No internet / DNS failure / connection refused
  network,

  /// Connection or receive timeout
  timeout,

  /// 401/403 – API key invalid or access denied
  auth,

  /// 429 – Too many requests / rate limited
  rateLimit,

  /// 500+ – Server-side failures
  serverError,

  /// Request was cancelled by the user
  cancelled,

  /// Catch-all for unmapped errors
  unknown,
}

/// Structured, user-facing chat error.
///
/// Implements [Exception] so it can be thrown or added as a stream error
/// and caught naturally in `await for` / `try-catch` blocks.
class ChatError implements Exception {
  final ChatErrorType type;
  final String userMessage;
  final String? technicalDetail;
  final bool canRetry;

  const ChatError({
    required this.type,
    required this.userMessage,
    this.technicalDetail,
    this.canRetry = true,
  });

  @override
  String toString() => 'ChatError(${type.name}): $userMessage';
}

/// Maps low-level exceptions to [ChatError] with friendly Chinese messages.
class ChatErrorMapper {
  ChatErrorMapper._();

  // ──────────────────────────── public API ────────────────────────────

  /// Map **any** exception/error to a [ChatError].
  static ChatError mapException(Object error) {
    if (error is ChatError) return error;
    if (error is DioException) return mapDioException(error);

    final msg = error.toString().toLowerCase();

    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable')) {
      return ChatError(
        type: ChatErrorType.network,
        userMessage: '网络连接失败，请检查您的网络设置后重试',
        technicalDetail: error.toString(),
      );
    }
    if (msg.contains('timeoutexception') || msg.contains('timed out')) {
      return ChatError(
        type: ChatErrorType.timeout,
        userMessage: '请求超时，请稍后重试',
        technicalDetail: error.toString(),
      );
    }
    if (msg.contains('handshakeexception') ||
        msg.contains('certificate_verify_failed') ||
        msg.contains('ssl')) {
      return ChatError(
        type: ChatErrorType.network,
        userMessage: '安全连接失败，请检查网络环境',
        technicalDetail: error.toString(),
      );
    }
    if (msg.contains('forbidden') || msg.contains('401') || msg.contains('403')) {
      return ChatError(
        type: ChatErrorType.auth,
        userMessage: 'AI 服务访问被拒绝，请检查 API 密钥配置',
        technicalDetail: error.toString(),
        canRetry: false,
      );
    }

    return ChatError(
      type: ChatErrorType.unknown,
      userMessage: 'AI 服务暂时不可用，请稍后重试',
      technicalDetail: error.toString(),
    );
  }

  /// Map a [DioException] to a [ChatError].
  static ChatError mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return ChatError(
          type: ChatErrorType.timeout,
          userMessage: '连接超时，请检查网络后重试',
          technicalDetail: e.message,
        );

      case DioExceptionType.receiveTimeout:
        return ChatError(
          type: ChatErrorType.timeout,
          userMessage: 'AI 响应超时，模型可能正忙，请稍后重试',
          technicalDetail: e.message,
        );

      case DioExceptionType.connectionError:
        return ChatError(
          type: ChatErrorType.network,
          userMessage: '无法连接到 AI 服务，请检查网络连接',
          technicalDetail: e.message,
        );

      case DioExceptionType.cancel:
        return const ChatError(
          type: ChatErrorType.cancelled,
          userMessage: '请求已取消',
          canRetry: false,
        );

      case DioExceptionType.badResponse:
        return _mapStatusCode(e.response?.statusCode, e);

      default:
        return ChatError(
          type: ChatErrorType.unknown,
          userMessage: 'AI 服务暂时不可用，请稍后重试',
          technicalDetail: e.message,
        );
    }
  }

  // ──────────────────────────── helpers ────────────────────────────

  static ChatError _mapStatusCode(int? code, [DioException? e]) {
    switch (code) {
      case 400:
        return ChatError(
          type: ChatErrorType.unknown,
          userMessage: '请求格式有误，请重新尝试',
          technicalDetail: 'HTTP 400: ${e?.message}',
        );
      case 401:
        return const ChatError(
          type: ChatErrorType.auth,
          userMessage: 'API 密钥无效或已过期，请在设置中更新',
          technicalDetail: 'HTTP 401',
          canRetry: false,
        );
      case 403:
        return const ChatError(
          type: ChatErrorType.auth,
          userMessage: 'AI 服务访问被拒绝，请检查 API 密钥权限',
          technicalDetail: 'HTTP 403',
          canRetry: false,
        );
      case 404:
        return const ChatError(
          type: ChatErrorType.serverError,
          userMessage: 'AI 服务地址不正确，请在设置中检查配置',
          technicalDetail: 'HTTP 404',
          canRetry: false,
        );
      case 429:
        return const ChatError(
          type: ChatErrorType.rateLimit,
          userMessage: '请求过于频繁，请稍等片刻后重试',
          technicalDetail: 'HTTP 429',
        );
      case 500:
      case 502:
      case 503:
        return ChatError(
          type: ChatErrorType.serverError,
          userMessage: 'AI 服务器暂时出现问题，请稍后重试',
          technicalDetail: 'HTTP $code',
        );
      case 504:
        return const ChatError(
          type: ChatErrorType.timeout,
          userMessage: 'AI 服务响应超时，请稍后重试',
          technicalDetail: 'HTTP 504',
        );
      default:
        return ChatError(
          type: ChatErrorType.unknown,
          userMessage: 'AI 服务暂时不可用（错误 $code），请稍后重试',
          technicalDetail: 'HTTP $code',
        );
    }
  }

  /// Returns a user-friendly icon string for the error type.
  static String iconForType(ChatErrorType type) {
    switch (type) {
      case ChatErrorType.network:
        return '🌐';
      case ChatErrorType.timeout:
        return '⏱️';
      case ChatErrorType.auth:
        return '🔑';
      case ChatErrorType.rateLimit:
        return '⏳';
      case ChatErrorType.serverError:
        return '🔧';
      case ChatErrorType.cancelled:
        return '✋';
      case ChatErrorType.unknown:
        return '⚠️';
    }
  }
}
