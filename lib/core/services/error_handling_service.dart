import 'package:flutter/material.dart';
import '../../shared/theme/theme_extensions.dart';
import '../../shared/widgets/themed_dialogs.dart';
import 'user_friendly_error_handler.dart';

class ErrorHandlingService {
  static final _userFriendlyHandler = UserFriendlyErrorHandler();

  static String getErrorMessage(dynamic error) {
    // Use the enhanced user-friendly error handler
    return _userFriendlyHandler.getUserMessage(error);
  }

  /// Get recovery actions for an error
  static List<ErrorRecoveryAction> getRecoveryActions(dynamic error) {
    return _userFriendlyHandler.getRecoveryActions(error);
  }

  static void showErrorSnackBar(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
    String? customMessage,
  }) {
    if (customMessage != null) {
      // Use custom message if provided
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(customMessage),
          backgroundColor: context.conduitTheme.error,
          behavior: SnackBarBehavior.floating,
          action: onRetry != null
              ? SnackBarAction(
                  label: 'Retry',
                  textColor: context.conduitTheme.textInverse,
                  onPressed: onRetry,
                )
              : null,
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      // Use enhanced error handler
      _userFriendlyHandler.showErrorSnackbar(context, error, onRetry: onRetry);
    }
  }

  /// Show enhanced error dialog with recovery options
  static Future<void> showErrorDialog(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
    bool showDetails = false,
  }) async {
    return _userFriendlyHandler.showErrorDialog(
      context,
      error,
      onRetry: onRetry,
      showDetails: showDetails,
    );
  }

  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.conduitTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }

  static Future<bool> showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
  }) async {
    return await ThemedDialogs.confirm(
      context,
      title: title,
      message: content,
      confirmText: confirmText,
      cancelText: cancelText,
      isDestructive: isDestructive,
    );
  }

  static Widget buildErrorWidget({
    required String message,
    VoidCallback? onRetry,
    IconData? icon,
    dynamic error,
  }) {
    if (error != null) {
      // Use enhanced error handler for full error objects
      return _userFriendlyHandler.buildErrorWidget(error, onRetry: onRetry);
    }

    // Fallback to legacy implementation for string messages
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon ?? Icons.error_outline,
                  size: Spacing.xxxl,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Something went wrong',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: Spacing.lg),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build enhanced error widget with recovery actions
  static Widget buildEnhancedErrorWidget(
    dynamic error, {
    VoidCallback? onRetry,
    VoidCallback? onDismiss,
    bool showDetails = false,
  }) {
    return _userFriendlyHandler.buildErrorWidget(
      error,
      onRetry: onRetry,
      onDismiss: onDismiss,
      showDetails: showDetails,
    );
  }

  static Widget buildLoadingWidget({String? message}) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: theme.colorScheme.primary),
                if (message != null) ...[
                  const SizedBox(height: Spacing.md),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget buildEmptyStateWidget({
    required String title,
    required String message,
    IconData? icon,
    Widget? action,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon ?? Icons.inbox_outlined,
                  size: Spacing.xxxl,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...[
                  const SizedBox(height: Spacing.lg),
                  action,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
