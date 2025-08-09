import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Consistent authentication interceptor for all API requests
/// Implements security requirements from OpenAPI specification
class ApiAuthInterceptor extends Interceptor {
  String? _authToken;

  // Callbacks for auth events
  void Function()? onAuthTokenInvalid;
  Future<void> Function()? onTokenInvalidated;

  // Public endpoints that don't require authentication
  static const Set<String> _publicEndpoints = {
    '/health',
    '/api/v1/auths/signin',
    '/api/v1/auths/signup',
    '/api/v1/auths/signup/enabled',
    '/api/v1/auths/trusted-header-auth',
    '/ollama/api/ps',
    '/ollama/api/version',
    '/docs',
    '/openapi.json',
    '/swagger',
    '/api/docs',
  };

  // Endpoints that have optional authentication (work without but better with)
  static const Set<String> _optionalAuthEndpoints = {
    '/api/models',
    '/api/v1/configs/models',
  };

  ApiAuthInterceptor({
    String? authToken,
    this.onAuthTokenInvalid,
    this.onTokenInvalidated,
  }) : _authToken = authToken;

  void updateAuthToken(String? token) {
    _authToken = token;
  }

  String? get authToken => _authToken;

  /// Check if endpoint requires authentication based on OpenAPI spec
  bool _requiresAuth(String path) {
    // Direct public endpoint match
    if (_publicEndpoints.contains(path)) {
      return false;
    }

    // Check for partial matches (e.g., /ollama/* endpoints)
    for (final publicPattern in _publicEndpoints) {
      if (publicPattern.endsWith('*') &&
          path.startsWith(
            publicPattern.substring(0, publicPattern.length - 1),
          )) {
        return false;
      }
    }

    // All other endpoints require authentication per OpenAPI spec
    return true;
  }

  /// Check if endpoint is better with auth but works without
  bool _hasOptionalAuth(String path) {
    return _optionalAuthEndpoints.contains(path);
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;
    final requiresAuth = _requiresAuth(path);
    final hasOptionalAuth = _hasOptionalAuth(path);

    debugPrint(
      'DEBUG: Auth interceptor for $path - requires: $requiresAuth, optional: $hasOptionalAuth, token present: ${_authToken != null}',
    );

    if (requiresAuth) {
      // Strictly required authentication
      if (_authToken == null || _authToken!.isEmpty) {
        final error = DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 401,
            data: {'detail': 'Authentication required for this endpoint'},
          ),
          type: DioExceptionType.badResponse,
        );
        handler.reject(error);
        return;
      }
      options.headers['Authorization'] = 'Bearer $_authToken';
    } else if (hasOptionalAuth &&
        _authToken != null &&
        _authToken!.isNotEmpty) {
      // Optional authentication - add if available
      options.headers['Authorization'] = 'Bearer $_authToken';
    }

    // Add other common headers for API consistency
    options.headers['Content-Type'] ??= 'application/json';
    options.headers['Accept'] ??= 'application/json';

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final statusCode = err.response?.statusCode;
    final path = err.requestOptions.path;

    // Handle authentication errors consistently
    if (statusCode == 401) {
      // 401 always indicates invalid/expired auth token
      debugPrint('DEBUG: 401 Unauthorized on $path - clearing auth token');
      _clearAuthToken();
    } else if (statusCode == 403) {
      // 403 on protected endpoints indicates insufficient permissions or invalid token
      final requiresAuth = _requiresAuth(path);
      final optionalAuth = _hasOptionalAuth(path);
      if (requiresAuth && !optionalAuth) {
        debugPrint(
          'DEBUG: 403 Forbidden on protected endpoint $path - clearing auth token',
        );
        _clearAuthToken();
      } else {
        debugPrint(
          'DEBUG: 403 Forbidden on public/optional endpoint $path - keeping auth token',
        );
      }
    }

    handler.next(err);
  }

  void _clearAuthToken() {
    _authToken = null;
    onAuthTokenInvalid?.call();
    onTokenInvalidated?.call();
  }
}
