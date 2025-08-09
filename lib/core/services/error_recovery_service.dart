import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../shared/theme/theme_extensions.dart';

/// Enhanced error recovery service with retry strategies and user feedback
class ErrorRecoveryService {
  final Map<String, RetryConfig> _retryConfigs = {};
  final Map<String, DateTime> _lastRetryTimes = {};

  ErrorRecoveryService(Dio dio);

  /// Execute an operation with automatic retry and recovery
  Future<T> executeWithRecovery<T>({
    required String operationId,
    required Future<T> Function() operation,
    RetryConfig? retryConfig,
    RecoveryAction? recoveryAction,
  }) async {
    final config = retryConfig ?? RetryConfig.defaultConfig();
    _retryConfigs[operationId] = config;

    int attempts = 0;
    Exception? lastError;

    while (attempts < config.maxRetries) {
      try {
        final result = await operation();
        _clearRetryState(operationId);
        return result;
      } catch (error) {
        attempts++;
        lastError = error is Exception ? error : Exception(error.toString());

        final shouldRetry = _shouldRetry(error, attempts, config);
        if (!shouldRetry || attempts >= config.maxRetries) {
          break;
        }

        // Execute recovery action if provided
        if (recoveryAction != null) {
          try {
            await recoveryAction.execute(error, attempts);
          } catch (recoveryError) {
            // Recovery action failed, continue with retry
          }
        }

        // Wait before retry with exponential backoff
        final delay = _calculateRetryDelay(attempts, config);
        await Future.delayed(delay);
      }
    }

    _clearRetryState(operationId);
    throw ErrorRecoveryException(lastError!, attempts);
  }

  /// Check if we should retry based on error type and configuration
  bool _shouldRetry(dynamic error, int attempts, RetryConfig config) {
    if (attempts >= config.maxRetries) return false;

    // Check cooldown period
    final lastRetry = _lastRetryTimes[config.operationId];
    if (lastRetry != null) {
      final timeSinceLastRetry = DateTime.now().difference(lastRetry);
      if (timeSinceLastRetry < config.cooldownPeriod) {
        return false;
      }
    }

    // Network errors are usually retryable
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.badResponse:
          // Retry on server errors (5xx) but not client errors (4xx)
          final statusCode = error.response?.statusCode;
          return statusCode != null && statusCode >= 500;
        default:
          return false;
      }
    }

    // Check custom retry conditions
    return config.retryCondition?.call(error) ?? false;
  }

  Duration _calculateRetryDelay(int attempt, RetryConfig config) {
    if (config.retryStrategy == RetryStrategy.exponentialBackoff) {
      final baseDelay = config.baseDelay.inMilliseconds;
      final delay = baseDelay * pow(2, attempt - 1);
      final jitter = Random().nextDouble() * 0.1 * delay; // Add 10% jitter
      return Duration(milliseconds: (delay + jitter).round());
    } else {
      return config.baseDelay;
    }
  }

  void _clearRetryState(String operationId) {
    _retryConfigs.remove(operationId);
    _lastRetryTimes.remove(operationId);
  }

  /// Get user-friendly error message
  String getErrorMessage(dynamic error) {
    if (error is ErrorRecoveryException) {
      return _getRecoveryErrorMessage(error);
    }

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'The connection is taking too long. Please check your internet and try again.';
        case DioExceptionType.sendTimeout:
          return 'Failed to send your request. Please try again.';
        case DioExceptionType.receiveTimeout:
          return 'The server is taking too long to respond. Please try again.';
        case DioExceptionType.connectionError:
          return 'Unable to connect. Please check your internet connection.';
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          if (statusCode == 401) {
            return 'Your session has expired. Please sign in again.';
          } else if (statusCode == 403) {
            return 'You don\'t have permission to perform this action.';
          } else if (statusCode == 404) {
            return 'The requested resource was not found.';
          } else if (statusCode != null && statusCode >= 500) {
            return 'The server is experiencing issues. Please try again later.';
          }
          return 'Something went wrong with your request.';
        case DioExceptionType.cancel:
          return 'The request was cancelled.';
        case DioExceptionType.badCertificate:
          return 'There\'s a security issue with the connection.';
        case DioExceptionType.unknown:
          return 'Something unexpected happened. Please try again.';
      }
    }

    return error.toString();
  }

  String _getRecoveryErrorMessage(ErrorRecoveryException error) {
    final attempts = error.attempts;
    final originalError = getErrorMessage(error.originalError);

    return 'Failed after $attempts attempts: $originalError';
  }
}

/// Configuration for retry behavior
class RetryConfig {
  final String operationId;
  final int maxRetries;
  final Duration baseDelay;
  final Duration cooldownPeriod;
  final RetryStrategy retryStrategy;
  final bool Function(dynamic error)? retryCondition;

  const RetryConfig({
    required this.operationId,
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.cooldownPeriod = const Duration(seconds: 5),
    this.retryStrategy = RetryStrategy.exponentialBackoff,
    this.retryCondition,
  });

  static RetryConfig defaultConfig() => const RetryConfig(
    operationId: 'default',
    maxRetries: 3,
    baseDelay: Duration(seconds: 1),
    retryStrategy: RetryStrategy.exponentialBackoff,
  );

  static RetryConfig networkConfig() => const RetryConfig(
    operationId: 'network',
    maxRetries: 5,
    baseDelay: Duration(milliseconds: 500),
    retryStrategy: RetryStrategy.exponentialBackoff,
  );

  static RetryConfig chatConfig() => const RetryConfig(
    operationId: 'chat',
    maxRetries: 3,
    baseDelay: Duration(seconds: 2),
    retryStrategy: RetryStrategy.exponentialBackoff,
  );
}

enum RetryStrategy { fixed, exponentialBackoff }

/// Recovery action to execute between retries
abstract class RecoveryAction {
  Future<void> execute(dynamic error, int attempt);
}

/// Reconnect to server recovery action
class ReconnectAction extends RecoveryAction {
  final Future<void> Function() reconnectFunction;

  ReconnectAction(this.reconnectFunction);

  @override
  Future<void> execute(dynamic error, int attempt) async {
    if (attempt == 1) {
      // Only try to reconnect on the first retry
      await reconnectFunction();
    }
  }
}

/// Refresh token recovery action
class RefreshTokenAction extends RecoveryAction {
  final Future<void> Function() refreshFunction;

  RefreshTokenAction(this.refreshFunction);

  @override
  Future<void> execute(dynamic error, int attempt) async {
    if (error is DioException && error.response?.statusCode == 401) {
      await refreshFunction();
    }
  }
}

/// Clear cache recovery action
class ClearCacheAction extends RecoveryAction {
  final Future<void> Function() clearCacheFunction;

  ClearCacheAction(this.clearCacheFunction);

  @override
  Future<void> execute(dynamic error, int attempt) async {
    if (attempt == 2) {
      // Clear cache on second attempt
      await clearCacheFunction();
    }
  }
}

/// Error recovery exception
class ErrorRecoveryException implements Exception {
  final Exception originalError;
  final int attempts;

  const ErrorRecoveryException(this.originalError, this.attempts);

  @override
  String toString() =>
      'ErrorRecoveryException: $originalError (after $attempts attempts)';
}

/// Providers
final errorRecoveryServiceProvider = Provider<ErrorRecoveryService>((ref) {
  // This should use the same Dio instance as the API service
  final dio = Dio(); // Replace with actual Dio provider
  return ErrorRecoveryService(dio);
});

/// Error boundary widget for handling UI errors
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, VoidCallback retry)? errorBuilder;
  final void Function(Object error, StackTrace stackTrace)? onError;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.onError,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? error;
  StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return widget.errorBuilder?.call(error!, _retry) ??
          _buildDefaultErrorWidget();
    }

    return ErrorDetector(
      onError: (error, stackTrace) {
        setState(() {
          this.error = error;
          this.stackTrace = stackTrace;
        });
        widget.onError?.call(error, stackTrace);
      },
      child: widget.child,
    );
  }

  Widget _buildDefaultErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: Spacing.xxxl,
            color: context.conduitTheme.error,
          ),
          const SizedBox(height: Spacing.md),
          const Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.conduitTheme.textSecondary),
          ),
          const SizedBox(height: Spacing.md),
          ElevatedButton(onPressed: _retry, child: const Text('Try Again')),
        ],
      ),
    );
  }

  void _retry() {
    setState(() {
      error = null;
      stackTrace = null;
    });
  }
}

/// Widget to detect and handle errors in child widgets
class ErrorDetector extends StatefulWidget {
  final Widget child;
  final void Function(Object error, StackTrace stackTrace) onError;

  const ErrorDetector({super.key, required this.child, required this.onError});

  @override
  State<ErrorDetector> createState() => _ErrorDetectorState();
}

class _ErrorDetectorState extends State<ErrorDetector> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set up error handling
    FlutterError.onError = (details) {
      widget.onError(details.exception, details.stack ?? StackTrace.current);
    };
  }
}
