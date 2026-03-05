import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'app_error.dart';

/// Maps low-level exceptions to [AppError] with friendly Chinese messages.
///
/// This is the global equivalent of `ChatErrorMapper` — generic messages
/// suitable for any feature, not AI-specific.
class AppErrorMapper {
  AppErrorMapper._();

  // ──────────────────────────── public API ────────────────────────────

  /// Map **any** exception/error to an [AppError].
  static AppError mapException(Object error) {
    if (error is AppError) return error;
    if (error is DioException) return mapDioException(error);

    final msg = error.toString().toLowerCase();

    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable')) {
      return AppError(
        type: AppErrorType.network,
        userMessage: '网络连接失败，请检查您的网络设置后重试',
        technicalDetail: error.toString(),
      );
    }
    if (msg.contains('timeoutexception') || msg.contains('timed out')) {
      return AppError(
        type: AppErrorType.timeout,
        userMessage: '请求超时，请稍后重试',
        technicalDetail: error.toString(),
      );
    }
    if (msg.contains('handshakeexception') ||
        msg.contains('certificate_verify_failed') ||
        msg.contains('ssl')) {
      return AppError(
        type: AppErrorType.network,
        userMessage: '安全连接失败，请检查网络环境',
        technicalDetail: error.toString(),
      );
    }
    if (msg.contains('forbidden') ||
        msg.contains('unauthorized') ||
        msg.contains('401') ||
        msg.contains('403')) {
      return AppError(
        type: AppErrorType.auth,
        userMessage: '访问被拒绝，请检查您的登录状态',
        technicalDetail: error.toString(),
        canRetry: false,
      );
    }

    return AppError(
      type: AppErrorType.unknown,
      userMessage: '操作失败，请稍后重试',
      technicalDetail: error.toString(),
    );
  }

  /// Map a [DioException] to an [AppError].
  static AppError mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return AppError(
          type: AppErrorType.timeout,
          userMessage: '连接超时，请检查网络后重试',
          technicalDetail: e.message,
        );

      case DioExceptionType.receiveTimeout:
        return AppError(
          type: AppErrorType.timeout,
          userMessage: '服务响应超时，请稍后重试',
          technicalDetail: e.message,
        );

      case DioExceptionType.connectionError:
        return AppError(
          type: AppErrorType.network,
          userMessage: '无法连接到服务器，请检查网络连接',
          technicalDetail: e.message,
        );

      case DioExceptionType.cancel:
        return const AppError(
          type: AppErrorType.cancelled,
          userMessage: '请求已取消',
          canRetry: false,
        );

      case DioExceptionType.badResponse:
        return _mapStatusCode(e.response?.statusCode, e);

      default:
        return AppError(
          type: AppErrorType.unknown,
          userMessage: '服务暂时不可用，请稍后重试',
          technicalDetail: e.message,
        );
    }
  }

  // ──────────────────────────── helpers ────────────────────────────

  static AppError _mapStatusCode(int? code, [DioException? e]) {
    switch (code) {
      case 400:
        return AppError(
          type: AppErrorType.validation,
          userMessage: '请求格式有误，请重新尝试',
          technicalDetail: 'HTTP 400: ${e?.message}',
          canRetry: false,
        );
      case 401:
        return const AppError(
          type: AppErrorType.auth,
          userMessage: '登录已过期，请重新登录',
          technicalDetail: 'HTTP 401',
          canRetry: false,
        );
      case 403:
        return const AppError(
          type: AppErrorType.auth,
          userMessage: '没有权限执行此操作',
          technicalDetail: 'HTTP 403',
          canRetry: false,
        );
      case 404:
        return const AppError(
          type: AppErrorType.serverError,
          userMessage: '请求的资源不存在',
          technicalDetail: 'HTTP 404',
          canRetry: false,
        );
      case 429:
        return const AppError(
          type: AppErrorType.rateLimit,
          userMessage: '请求过于频繁，请稍等片刻后重试',
          technicalDetail: 'HTTP 429',
        );
      case 500:
      case 502:
      case 503:
        return AppError(
          type: AppErrorType.serverError,
          userMessage: '服务器暂时出现问题，请稍后重试',
          technicalDetail: 'HTTP $code',
        );
      case 504:
        return const AppError(
          type: AppErrorType.timeout,
          userMessage: '服务响应超时，请稍后重试',
          technicalDetail: 'HTTP 504',
        );
      default:
        return AppError(
          type: AppErrorType.unknown,
          userMessage: '服务暂时不可用，请稍后重试',
          technicalDetail: 'HTTP $code',
        );
    }
  }

  /// Returns an appropriate [IconData] for the given error type.
  static IconData iconForType(AppErrorType type) {
    switch (type) {
      case AppErrorType.network:
        return Icons.wifi_off_rounded;
      case AppErrorType.timeout:
        return Icons.timer_off_rounded;
      case AppErrorType.auth:
        return Icons.key_off_rounded;
      case AppErrorType.rateLimit:
        return Icons.hourglass_top_rounded;
      case AppErrorType.serverError:
        return Icons.cloud_off_rounded;
      case AppErrorType.cancelled:
        return Icons.cancel_outlined;
      case AppErrorType.validation:
        return Icons.edit_off_rounded;
      case AppErrorType.unknown:
        return Icons.error_outline_rounded;
    }
  }
}
