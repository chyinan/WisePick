import 'package:flutter/material.dart';

/// Categorized error types for the entire application.
///
/// Mirrors [ChatErrorType] but is usable across all modules — not just chat.
enum AppErrorType {
  /// No internet / DNS failure / connection refused
  network,

  /// Connection or receive timeout
  timeout,

  /// 401/403 – Authentication / authorization failure
  auth,

  /// 429 – Too many requests / rate limited
  rateLimit,

  /// 500+ – Server-side failures
  serverError,

  /// Request was cancelled by the user
  cancelled,

  /// Input validation / bad-request failure
  validation,

  /// Catch-all for unmapped errors
  unknown,
}

/// Structured, user-facing error.
///
/// Implements [Exception] so it can be thrown or caught naturally.
/// UI layers should always display [userMessage] – never [technicalDetail].
class AppError implements Exception {
  final AppErrorType type;
  final String userMessage;
  final String? technicalDetail;
  final bool canRetry;

  const AppError({
    required this.type,
    required this.userMessage,
    this.technicalDetail,
    this.canRetry = true,
  });

  /// Convenience getter for the appropriate icon.
  IconData get icon {
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

  @override
  String toString() => 'AppError(${type.name}): $userMessage';
}
