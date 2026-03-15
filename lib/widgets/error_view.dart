import 'package:flutter/material.dart';

import '../core/error/app_error.dart';
import '../core/error/app_error_mapper.dart';
import '../core/error/app_error_ui.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ErrorView – full-page / section error widget
// ─────────────────────────────────────────────────────────────────────────────

/// A polished, full-section error view with categorized icon, friendly Chinese
/// message, and optional retry button.
///
/// Accepts **any** [Object] as [error] and maps it via [AppErrorMapper].
class ErrorView extends StatelessWidget {
  /// The raw error (Exception, DioException, AppError, etc.)
  final Object error;

  /// Callback when user taps "重试". Hidden when null or when the error is
  /// marked non-retryable.
  final VoidCallback? onRetry;

  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final appError =
        error is AppError ? error as AppError : AppErrorMapper.mapException(error);
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                appError.icon,
                size: 48,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '出错了',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appError.userMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null && appError.canRetry) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ErrorCard – inline card variant for sections / charts
// ─────────────────────────────────────────────────────────────────────────────

/// Inline error card for use inside scrollable sections (e.g. chart area,
/// analysis panel).
class ErrorCard extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  final double? height;

  const ErrorCard({
    super.key,
    required this.error,
    this.onRetry,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final appError =
        error is AppError ? error as AppError : AppErrorMapper.mapException(error);
    final theme = Theme.of(context);

    return Card(
      child: Container(
        height: height,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                appError.icon,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                '加载失败',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                appError.userMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null && appError.canRetry) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
