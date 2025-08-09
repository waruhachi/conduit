import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api_error.dart';
import 'api_error_handler.dart';
import 'api_error_interceptor.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/theme_extensions.dart';

/// Enhanced error service with comprehensive error handling capabilities
/// Provides unified error management across the application
class EnhancedErrorService {
  static final EnhancedErrorService _instance =
      EnhancedErrorService._internal();
  factory EnhancedErrorService() => _instance;
  EnhancedErrorService._internal();

  final ApiErrorHandler _errorHandler = ApiErrorHandler();

  /// Transform any error into ApiError format
  ApiError transformError(
    dynamic error, {
    String? endpoint,
    String? method,
    Map<String, dynamic>? requestData,
  }) {
    return _errorHandler.transformError(
      error,
      endpoint: endpoint,
      method: method,
      requestData: requestData,
    );
  }

  /// Get user-friendly error message
  String getUserMessage(dynamic error) {
    if (error is ApiError) {
      return _errorHandler.getUserMessage(error);
    } else if (error is DioException) {
      return ApiErrorInterceptor.getUserMessage(error);
    } else {
      return _getGenericErrorMessage(error);
    }
  }

  /// Get technical error details for debugging
  String getTechnicalDetails(dynamic error) {
    if (error is ApiError) {
      return error.technical ?? error.toString();
    } else if (error is DioException) {
      final apiError = ApiErrorInterceptor.extractApiError(error);
      if (apiError != null) {
        return apiError.technical ?? apiError.toString();
      }
      return '${error.type}: ${error.message}';
    } else {
      return error.toString();
    }
  }

  /// Check if error is retryable
  bool isRetryable(dynamic error) {
    if (error is ApiError) {
      return _errorHandler.isRetryable(error);
    } else if (error is DioException) {
      final apiError = ApiErrorInterceptor.extractApiError(error);
      if (apiError != null) {
        return _errorHandler.isRetryable(apiError);
      }
      return _isDioErrorRetryable(error);
    }
    return false;
  }

  /// Get suggested retry delay
  Duration? getRetryDelay(dynamic error) {
    if (error is ApiError) {
      return _errorHandler.getRetryDelay(error);
    } else if (error is DioException) {
      final apiError = ApiErrorInterceptor.extractApiError(error);
      if (apiError != null) {
        return _errorHandler.getRetryDelay(apiError);
      }
      return _getDioRetryDelay(error);
    }
    return null;
  }

  /// Show error snackbar with appropriate styling and actions
  void showErrorSnackbar(
    BuildContext context,
    dynamic error, {
    VoidCallback? onRetry,
    Duration? duration,
    bool showTechnicalDetails = false,
  }) {
    final message = getUserMessage(error);
    final isRetryableError = isRetryable(error);
    final retryDelay = getRetryDelay(error);

    final snackBar = SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getErrorIcon(error),
                color: AppTheme.neutral50,
                size: IconSize.md,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: AppTheme.neutral50),
                ),
              ),
            ],
          ),
          if (showTechnicalDetails) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              getTechnicalDetails(error),
              style: TextStyle(
                color: AppTheme.neutral50.withValues(alpha: Alpha.strong),
                fontSize: AppTypography.labelMedium,
              ),
            ),
          ],
        ],
      ),
      backgroundColor: _getErrorColor(error),
      duration: duration ?? _getSnackbarDuration(error),
      action: isRetryableError && onRetry != null
          ? SnackBarAction(
              label: retryDelay != null && retryDelay.inSeconds > 5
                  ? 'Retry (${retryDelay.inSeconds}s)'
                  : 'Retry',
              textColor: AppTheme.neutral50,
              onPressed: onRetry,
            )
          : null,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Show error dialog with detailed information and recovery options
  Future<void> showErrorDialog(
    BuildContext context,
    dynamic error, {
    String? title,
    VoidCallback? onRetry,
    VoidCallback? onDismiss,
    bool showTechnicalDetails = false,
  }) async {
    final message = getUserMessage(error);
    final technicalDetails = getTechnicalDetails(error);
    final isRetryableError = isRetryable(error);

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(_getErrorIcon(error), color: _getErrorColor(error)),
              const SizedBox(width: Spacing.sm),
              Expanded(child: Text(title ?? _getErrorTitle(error))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (showTechnicalDetails) ...[
                const SizedBox(height: Spacing.md),
                const Text(
                  'Technical Details:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: Spacing.xs),
                Container(
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: AppTheme.neutral100,
                    borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                  ),
                  child: Text(
                    technicalDetails,
                    style: const TextStyle(
                      fontFamily: AppTypography.monospaceFontFamily,
                      fontSize: AppTypography.labelMedium,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (isRetryableError && onRetry != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onRetry();
                },
                child: const Text('Retry'),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDismiss?.call();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Build error widget for displaying in UI
  Widget buildErrorWidget(
    dynamic error, {
    VoidCallback? onRetry,
    bool showTechnicalDetails = false,
    EdgeInsets? padding,
  }) {
    final message = getUserMessage(error);
    final technicalDetails = getTechnicalDetails(error);
    final isRetryableError = isRetryable(error);

    return Container(
      padding: padding ?? const EdgeInsets.all(Spacing.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getErrorIcon(error),
            size: IconSize.xxl,
            color: _getErrorColor(error),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            _getErrorTitle(error),
            style: const TextStyle(
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.neutral600),
          ),
          if (showTechnicalDetails) ...[
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.xs),
              decoration: BoxDecoration(
                color: AppTheme.neutral100,
                borderRadius: BorderRadius.circular(AppBorderRadius.sm),
              ),
              child: Text(
                technicalDetails,
                style: const TextStyle(
                  fontFamily: AppTypography.monospaceFontFamily,
                  fontSize: AppTypography.labelMedium,
                ),
              ),
            ),
          ],
          if (isRetryableError && onRetry != null) ...[
            const SizedBox(height: Spacing.md),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ],
      ),
    );
  }

  /// Log error with structured information
  void logError(
    dynamic error, {
    String? context,
    Map<String, dynamic>? additionalData,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      final timestamp = DateTime.now().toIso8601String();
      debugPrint('🔴 ERROR [$timestamp] ${context ?? 'Unknown Context'}');
      debugPrint('  Message: ${getUserMessage(error)}');
      debugPrint('  Technical: ${getTechnicalDetails(error)}');

      if (additionalData != null && additionalData.isNotEmpty) {
        debugPrint('  Additional Data: $additionalData');
      }

      if (stackTrace != null) {
        debugPrint('  Stack Trace: $stackTrace');
      }
    }

    // In production, send to error tracking service
    // FirebaseCrashlytics.instance.recordError(error, stackTrace, context: context);
    // Sentry.captureException(error, stackTrace: stackTrace);
  }

  // Private helper methods

  String _getGenericErrorMessage(dynamic error) {
    if (error is Exception) {
      return 'An error occurred: ${error.toString()}';
    }
    return 'An unexpected error occurred';
  }

  bool _isDioErrorRetryable(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        return statusCode != null && statusCode >= 500;
      default:
        return false;
    }
  }

  Duration? _getDioRetryDelay(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const Duration(seconds: 5);
      case DioExceptionType.connectionError:
        return const Duration(seconds: 3);
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode != null && statusCode >= 500) {
          return const Duration(seconds: 10);
        }
        break;
      default:
        break;
    }
    return null;
  }

  IconData _getErrorIcon(dynamic error) {
    if (error is ApiError) {
      switch (error.type) {
        case ApiErrorType.network:
          return Icons.wifi_off;
        case ApiErrorType.timeout:
          return Icons.timer_off;
        case ApiErrorType.authentication:
          return Icons.lock;
        case ApiErrorType.authorization:
          return Icons.block;
        case ApiErrorType.validation:
          return Icons.edit_off;
        case ApiErrorType.badRequest:
          return Icons.error_outline;
        case ApiErrorType.notFound:
          return Icons.search_off;
        case ApiErrorType.server:
          return Icons.dns;
        case ApiErrorType.rateLimit:
          return Icons.speed;
        case ApiErrorType.cancelled:
          return Icons.cancel;
        case ApiErrorType.security:
          return Icons.security;
        case ApiErrorType.unknown:
          return Icons.help_outline;
      }
    }
    return Icons.error_outline;
  }

  Color _getErrorColor(dynamic error) {
    if (error is ApiError) {
      switch (error.type) {
        case ApiErrorType.network:
        case ApiErrorType.timeout:
          return AppTheme.warning;
        case ApiErrorType.authentication:
        case ApiErrorType.authorization:
          return AppTheme.error;
        case ApiErrorType.validation:
        case ApiErrorType.badRequest:
          return AppTheme.warning;
        case ApiErrorType.server:
          return AppTheme.error;
        case ApiErrorType.rateLimit:
          return AppTheme.info;
        default:
          return AppTheme.error;
      }
    }
    return AppTheme.error;
  }

  String _getErrorTitle(dynamic error) {
    if (error is ApiError) {
      switch (error.type) {
        case ApiErrorType.network:
          return 'Connection Problem';
        case ApiErrorType.timeout:
          return 'Request Timeout';
        case ApiErrorType.authentication:
          return 'Authentication Required';
        case ApiErrorType.authorization:
          return 'Access Denied';
        case ApiErrorType.validation:
          return 'Invalid Input';
        case ApiErrorType.badRequest:
          return 'Bad Request';
        case ApiErrorType.notFound:
          return 'Not Found';
        case ApiErrorType.server:
          return 'Server Error';
        case ApiErrorType.rateLimit:
          return 'Rate Limited';
        case ApiErrorType.cancelled:
          return 'Request Cancelled';
        case ApiErrorType.security:
          return 'Security Error';
        case ApiErrorType.unknown:
          return 'Unknown Error';
      }
    }
    return 'Error';
  }

  Duration _getSnackbarDuration(dynamic error) {
    if (error is ApiError) {
      switch (error.type) {
        case ApiErrorType.validation:
        case ApiErrorType.badRequest:
          return const Duration(seconds: 6); // Longer for validation errors
        case ApiErrorType.rateLimit:
          return const Duration(seconds: 8); // Longer for rate limits
        default:
          return const Duration(seconds: 4);
      }
    }
    return const Duration(seconds: 4);
  }
}

/// Global instance for easy access
final enhancedErrorService = EnhancedErrorService();
