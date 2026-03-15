import 'package:flutter/material.dart';

import 'app_error.dart';

/// Flutter UI extensions for [AppError] and [AppErrorMapper].
///
/// Kept separate so that [app_error.dart] and [app_error_mapper.dart] remain
/// pure-Dart and can be tested without the Flutter SDK.
extension AppErrorUI on AppError {
  IconData get icon => AppErrorIcons.forType(type);
}

class AppErrorIcons {
  AppErrorIcons._();

  static IconData forType(AppErrorType type) {
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
