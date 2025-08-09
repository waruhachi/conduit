import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_validator.dart';
import 'validation_result.dart';

/// Dio interceptor for automatic API validation
/// Validates requests and responses against OpenAPI schemas
class ValidationInterceptor extends Interceptor {
  final ApiValidator _validator = ApiValidator();
  final bool enableRequestValidation;
  final bool enableResponseValidation;
  final bool throwOnValidationError;
  final bool logValidationResults;

  ValidationInterceptor({
    this.enableRequestValidation = true,
    this.enableResponseValidation = true,
    this.throwOnValidationError = false,
    this.logValidationResults = true,
  });

  /// Initialize the validator
  Future<void> initialize() async {
    await _validator.initialize();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enableRequestValidation && options.data != null) {
      try {
        final result = _validator.validateRequest(
          options.data,
          options.path,
          method: options.method,
        );

        if (logValidationResults) {
          _logValidationResult(result, 'REQUEST', options.path, options.method);
        }

        if (!result.isValid && throwOnValidationError) {
          throw ValidationException(result);
        }

        // Transform data if validation succeeded
        if (result.isValid && options.data is Map<String, dynamic>) {
          options.data = _validator.transformForApi(
            options.data as Map<String, dynamic>,
          );
        }
      } catch (e) {
        if (e is ValidationException) {
          handler.reject(
            DioException(
              requestOptions: options,
              error: e,
              type: DioExceptionType.unknown,
              message: 'Request validation failed: ${e.result.message}',
            ),
          );
          return;
        } else {
          debugPrint('ValidationInterceptor: Request validation error: $e');
        }
      }
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (enableResponseValidation && response.data != null) {
      try {
        final result = _validator.validateResponse(
          response.data,
          response.requestOptions.path,
          method: response.requestOptions.method,
          statusCode: response.statusCode,
        );

        if (logValidationResults) {
          _logValidationResult(
            result,
            'RESPONSE',
            response.requestOptions.path,
            response.requestOptions.method,
            statusCode: response.statusCode,
          );
        }

        if (!result.isValid && throwOnValidationError) {
          throw ValidationException(result);
        }

        // Transform data if validation succeeded and data is available
        if (result.isValid && result.data != null) {
          response.data = result.data;
        } else if (result.isValid && response.data is Map<String, dynamic>) {
          response.data = _validator.transformFromApi(
            response.data as Map<String, dynamic>,
          );
        }

        // Store validation result in response for debugging
        if (kDebugMode) {
          response.extra['validationResult'] = result;
        }
      } catch (e) {
        if (e is ValidationException) {
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: e,
              type: DioExceptionType.unknown,
              message: 'Response validation failed: ${e.result.message}',
            ),
          );
          return;
        } else {
          debugPrint('ValidationInterceptor: Response validation error: $e');
        }
      }
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Try to validate error responses too
    if (enableResponseValidation && err.response?.data != null) {
      try {
        final result = _validator.validateResponse(
          err.response!.data,
          err.requestOptions.path,
          method: err.requestOptions.method,
          statusCode: err.response!.statusCode,
        );

        if (logValidationResults) {
          _logValidationResult(
            result,
            'ERROR_RESPONSE',
            err.requestOptions.path,
            err.requestOptions.method,
            statusCode: err.response!.statusCode,
          );
        }

        // Transform error response data
        if (result.isValid && result.data != null) {
          err.response!.data = result.data;
        } else if (result.isValid &&
            err.response!.data is Map<String, dynamic>) {
          err.response!.data = _validator.transformFromApi(
            err.response!.data as Map<String, dynamic>,
          );
        }

        // Store validation result for debugging
        if (kDebugMode) {
          err.response!.extra['validationResult'] = result;
        }
      } catch (e) {
        debugPrint(
          'ValidationInterceptor: Error response validation failed: $e',
        );
      }
    }

    handler.next(err);
  }

  /// Log validation results in a structured format
  void _logValidationResult(
    ValidationResult result,
    String type,
    String path,
    String method, {
    int? statusCode,
  }) {
    if (!logValidationResults) return;

    final statusText = statusCode != null ? ' ($statusCode)' : '';
    final icon = result.isValid ? '✅' : '❌';

    debugPrint(
      '$icon Validation $type: ${method.toUpperCase()} $path$statusText - ${result.status.name}',
    );

    if (result.hasErrors) {
      debugPrint('   Errors: ${result.errors.join(', ')}');
    }

    if (result.hasWarnings) {
      debugPrint('   Warnings: ${result.warnings.join(', ')}');
    }

    if (result.message.isNotEmpty &&
        result.status != ValidationStatus.success) {
      debugPrint('   Message: ${result.message}');
    }
  }

  /// Get validation statistics
  Map<String, dynamic> getStats() {
    return {
      'requestValidationEnabled': enableRequestValidation,
      'responseValidationEnabled': enableResponseValidation,
      'throwOnError': throwOnValidationError,
      'loggingEnabled': logValidationResults,
      'validatorInitialized': _validator.isInitialized,
    };
  }
}
