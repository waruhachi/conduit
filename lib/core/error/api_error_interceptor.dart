import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_error_handler.dart';
import 'api_error.dart';

/// Dio interceptor for automatic error handling and transformation
/// Converts all HTTP errors into standardized ApiError format
class ApiErrorInterceptor extends Interceptor {
  final ApiErrorHandler _errorHandler = ApiErrorHandler();
  final bool logErrors;
  final bool throwApiErrors;

  ApiErrorInterceptor({this.logErrors = true, this.throwApiErrors = true});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      // Transform the error into our standardized format
      final apiError = _errorHandler.transformError(
        err,
        endpoint: err.requestOptions.path,
        method: err.requestOptions.method,
      );

      if (logErrors) {
        _logApiError(apiError, err);
      }

      if (throwApiErrors) {
        // Replace the DioException with our ApiError
        final enhancedError = DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          type: err.type,
          error: apiError,
          message: apiError.message,
        );
        handler.reject(enhancedError);
      } else {
        // Store the ApiError in the response extra data
        if (err.response != null) {
          err.response!.extra['apiError'] = apiError;
        }
        handler.next(err);
      }
    } catch (e) {
      // Fallback if error transformation fails
      debugPrint('ApiErrorInterceptor: Failed to transform error: $e');
      handler.next(err);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Check for errors in successful responses (some APIs return errors with 200 status)
    if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
      final data = response.data as Map<String, dynamic>;

      // Check for error indicators in successful responses
      if (_isErrorResponse(data)) {
        final apiError = _errorHandler.transformError(
          data,
          endpoint: response.requestOptions.path,
          method: response.requestOptions.method,
        );

        if (logErrors) {
          debugPrint('🟡 API Error in successful response: $apiError');
        }

        // Store the error for later handling
        response.extra['apiError'] = apiError;
      }
    }

    handler.next(response);
  }

  /// Check if a successful response actually contains an error
  bool _isErrorResponse(Map<String, dynamic> data) {
    // Common error indicators in successful responses
    const errorIndicators = [
      'error',
      'errors',
      'error_message',
      'errorMessage',
      'success',
    ];

    for (final indicator in errorIndicators) {
      if (data.containsKey(indicator)) {
        final value = data[indicator];

        // Check for explicit error indicators
        if (indicator == 'success' && value == false) {
          return true;
        }

        // Check for error messages or arrays
        if (indicator != 'success' && value != null) {
          if (value is String && value.isNotEmpty) {
            return true;
          } else if (value is List && value.isNotEmpty) {
            return true;
          } else if (value is Map && value.isNotEmpty) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Log API error with structured information
  void _logApiError(ApiError apiError, DioException originalError) {
    if (!kDebugMode) return;

    final typeIcon = _getErrorTypeIcon(apiError.type);
    debugPrint('$typeIcon API Error [${apiError.type.name.toUpperCase()}]');
    debugPrint('  Method: ${apiError.method?.toUpperCase() ?? 'UNKNOWN'}');
    debugPrint('  Endpoint: ${apiError.endpoint ?? 'unknown'}');
    debugPrint('  Status: ${apiError.statusCode ?? 'N/A'}');
    debugPrint('  Message: ${apiError.message}');

    if (apiError.hasFieldErrors) {
      debugPrint('  Field Errors:');
      for (final entry in apiError.fieldErrors.entries) {
        final field = entry.key;
        final errors = entry.value;
        debugPrint('    $field: ${errors.join(', ')}');
      }
    }

    if (apiError.technical != null) {
      debugPrint('  Technical: ${apiError.technical}');
    }

    if (apiError.retryAfter != null) {
      debugPrint('  Retry After: ${apiError.retryAfter!.inSeconds}s');
    }

    // Log original error type for debugging
    debugPrint('  Original Type: ${originalError.type}');

    // Log request details if available
    final requestData = originalError.requestOptions.data;
    if (requestData != null && requestData.toString().length < 500) {
      debugPrint('  Request: $requestData');
    }

    // Log response data if available and not too large
    final responseData = originalError.response?.data;
    if (responseData != null && responseData.toString().length < 1000) {
      debugPrint('  Response: $responseData');
    }
  }

  /// Get emoji icon for error type
  String _getErrorTypeIcon(ApiErrorType type) {
    switch (type) {
      case ApiErrorType.network:
        return '🌐';
      case ApiErrorType.timeout:
        return '⏱️';
      case ApiErrorType.authentication:
        return '🔐';
      case ApiErrorType.authorization:
        return '🚫';
      case ApiErrorType.validation:
        return '✏️';
      case ApiErrorType.badRequest:
        return '❌';
      case ApiErrorType.notFound:
        return '🔍';
      case ApiErrorType.server:
        return '🔥';
      case ApiErrorType.rateLimit:
        return '🐌';
      case ApiErrorType.cancelled:
        return '🛑';
      case ApiErrorType.security:
        return '🔒';
      case ApiErrorType.unknown:
        return '❓';
    }
  }

  /// Extract ApiError from DioException if available
  static ApiError? extractApiError(DioException error) {
    return error.error is ApiError ? error.error as ApiError : null;
  }

  /// Extract ApiError from Response if available
  static ApiError? extractApiErrorFromResponse(Response response) {
    return response.extra['apiError'] as ApiError?;
  }

  /// Check if DioException contains an ApiError
  static bool hasApiError(DioException error) {
    return extractApiError(error) != null;
  }

  /// Get user-friendly message from DioException
  static String getUserMessage(DioException error) {
    final apiError = extractApiError(error);
    if (apiError != null) {
      return ApiErrorHandler().getUserMessage(apiError);
    }

    // Fallback to basic DioException handling
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout - please check your internet connection';
      case DioExceptionType.connectionError:
        return 'Network connection error - please check your internet connection';
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        if (statusCode == 401) {
          return 'Authentication failed - please sign in again';
        } else if (statusCode == 403) {
          return 'Access denied - you don\'t have permission for this action';
        } else if (statusCode == 404) {
          return 'The requested resource was not found';
        } else if (statusCode != null && statusCode >= 500) {
          return 'Server error occurred - please try again later';
        }
        return 'An error occurred with your request';
      case DioExceptionType.cancel:
        return 'Request was cancelled';
      case DioExceptionType.badCertificate:
        return 'Security certificate error - unable to verify server identity';
      case DioExceptionType.unknown:
        return 'An unexpected error occurred - please try again';
    }
  }
}
