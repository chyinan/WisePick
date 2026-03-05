import 'package:flutter/material.dart';

import '../core/error/app_error.dart';
import '../core/error/app_error_mapper.dart';

/// Show a user-friendly error snackbar with categorized icon.
///
/// Accepts **any** [Object] as [error] and maps it via [AppErrorMapper].
void showErrorSnackBar(BuildContext context, Object error) {
  final appError =
      error is AppError ? error as AppError : AppErrorMapper.mapException(error);

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(appError.icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(appError.userMessage)),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// Show a success feedback snackbar.
void showSuccessSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// Show an informational snackbar (neutral color).
void showInfoSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
