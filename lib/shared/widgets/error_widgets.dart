import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';
import 'conduit_components.dart';

/// Enhanced error widget with production-grade design and better hierarchy
class ConduitErrorWidget extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final bool isCompact;

  const ConduitErrorWidget({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isCompact ? Spacing.md : Spacing.cardPadding),
      decoration: BoxDecoration(
        color: context.conduitTheme.errorBackground.withValues(
          alpha: Alpha.badgeBackground,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: Border.all(
          color: context.conduitTheme.error.withValues(alpha: Alpha.subtle),
          width: BorderWidth.standard,
        ),
        boxShadow: ConduitShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.error_outline,
            size: isCompact ? IconSize.large : IconSize.xl,
            color: context.conduitTheme.error,
          ),
          SizedBox(height: isCompact ? Spacing.sm : Spacing.md),
          Text(
            title,
            style: AppTypography.headlineSmallStyle.copyWith(
              color: context.conduitTheme.error,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isCompact ? Spacing.xs : Spacing.sm),
          Text(
            message,
            style: AppTypography.standard.copyWith(
              color: context.conduitTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: isCompact ? Spacing.md : Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: ConduitButton(
                text: actionLabel!,
                onPressed: onAction,
                isDestructive: true,
                isCompact: isCompact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Enhanced network error widget with better hierarchy
class NetworkErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? customMessage;
  final bool isCompact;

  const NetworkErrorWidget({
    super.key,
    this.onRetry,
    this.customMessage,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Connection Error',
      message:
          customMessage ??
          'Unable to connect to the server. Please check your internet connection and try again.',
      actionLabel: 'Retry',
      onAction: onRetry,
      icon: Icons.wifi_off,
      isCompact: isCompact,
    );
  }
}

/// Enhanced empty state widget with better hierarchy
class EmptyStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isCompact;

  const EmptyStateWidget({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isCompact ? Spacing.md : Spacing.cardPadding),
      decoration: BoxDecoration(
        color: context.conduitTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: Border.all(
          color: context.conduitTheme.cardBorder,
          width: BorderWidth.standard,
        ),
        boxShadow: ConduitShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.inbox_outlined,
            size: isCompact ? IconSize.large : IconSize.xxl,
            color: context.conduitTheme.iconSecondary,
          ),
          SizedBox(height: isCompact ? Spacing.sm : Spacing.md),
          Text(
            title,
            style: AppTypography.headlineSmallStyle.copyWith(
              color: context.conduitTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isCompact ? Spacing.xs : Spacing.sm),
          Text(
            message,
            style: AppTypography.standard.copyWith(
              color: context.conduitTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: isCompact ? Spacing.md : Spacing.lg),
            SizedBox(
              width: double.infinity,
              child: ConduitButton(
                text: actionLabel!,
                onPressed: onAction,
                isCompact: isCompact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Enhanced loading error widget with better hierarchy
class LoadingErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool isCompact;

  const LoadingErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Loading Failed',
      message: message,
      actionLabel: onRetry != null ? 'Try Again' : null,
      onAction: onRetry,
      icon: Icons.error_outline,
      isCompact: isCompact,
    );
  }
}

/// Enhanced validation error widget with better hierarchy
class ValidationErrorWidget extends StatelessWidget {
  final String fieldName;
  final String message;
  final VoidCallback? onFix;
  final bool isCompact;

  const ValidationErrorWidget({
    super.key,
    required this.fieldName,
    required this.message,
    this.onFix,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Invalid $fieldName',
      message: message,
      actionLabel: onFix != null ? 'Fix Now' : null,
      onAction: onFix,
      icon: Icons.warning_amber_outlined,
      isCompact: isCompact,
    );
  }
}

/// Enhanced permission error widget with better hierarchy
class PermissionErrorWidget extends StatelessWidget {
  final String permission;
  final String message;
  final VoidCallback? onGrant;
  final bool isCompact;

  const PermissionErrorWidget({
    super.key,
    required this.permission,
    required this.message,
    this.onGrant,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Permission Required',
      message: 'This app needs $permission permission to $message.',
      actionLabel: onGrant != null ? 'Grant Permission' : null,
      onAction: onGrant,
      icon: Icons.security,
      isCompact: isCompact,
    );
  }
}

/// Enhanced server error widget with better hierarchy
class ServerErrorWidget extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  final bool isCompact;

  const ServerErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Server Error',
      message: error,
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
      icon: Icons.cloud_off,
      isCompact: isCompact,
    );
  }
}

/// Enhanced file error widget with better hierarchy
class FileErrorWidget extends StatelessWidget {
  final String fileName;
  final String error;
  final VoidCallback? onRetry;
  final bool isCompact;

  const FileErrorWidget({
    super.key,
    required this.fileName,
    required this.error,
    this.onRetry,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'File Error',
      message: 'Failed to process $fileName: $error',
      actionLabel: onRetry != null ? 'Try Again' : null,
      onAction: onRetry,
      icon: Icons.file_present,
      isCompact: isCompact,
    );
  }
}

/// Enhanced authentication error widget with better hierarchy
class AuthErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onLogin;
  final bool isCompact;

  const AuthErrorWidget({
    super.key,
    required this.message,
    this.onLogin,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Authentication Required',
      message: message,
      actionLabel: onLogin != null ? 'Sign In' : null,
      onAction: onLogin,
      icon: Icons.lock_outline,
      isCompact: isCompact,
    );
  }
}

/// Enhanced offline error widget with better hierarchy
class OfflineErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool isCompact;

  const OfflineErrorWidget({
    super.key,
    this.message =
        'You\'re currently offline. Please check your internet connection.',
    this.onRetry,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Offline',
      message: message,
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
      icon: Icons.wifi_off,
      isCompact: isCompact,
    );
  }
}

/// Enhanced timeout error widget with better hierarchy
class TimeoutErrorWidget extends StatelessWidget {
  final String operation;
  final VoidCallback? onRetry;
  final bool isCompact;

  const TimeoutErrorWidget({
    super.key,
    required this.operation,
    this.onRetry,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitErrorWidget(
      title: 'Request Timeout',
      message: 'The $operation request timed out. Please try again.',
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
      icon: Icons.timer_off,
      isCompact: isCompact,
    );
  }
}
