import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Types are used through app_providers.dart
import '../providers/app_providers.dart';
import '../models/user.dart';
import 'token_validator.dart';
import 'auth_cache_manager.dart';

/// Comprehensive auth state representation
@immutable
class AuthState {
  const AuthState({
    required this.status,
    this.token,
    this.user,
    this.error,
    this.isLoading = false,
  });

  final AuthStatus status;
  final String? token;
  final dynamic user; // Replace with proper User type
  final String? error;
  final bool isLoading;

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && token != null;
  bool get hasValidToken => token != null && token!.isNotEmpty;
  bool get needsLogin =>
      status == AuthStatus.unauthenticated || status == AuthStatus.tokenExpired;

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    dynamic user,
    String? error,
    bool? isLoading,
    bool clearToken = false,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: clearToken ? null : (token ?? this.token),
      user: clearUser ? null : (user ?? this.user),
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthState &&
        other.status == status &&
        other.token == token &&
        other.user == user &&
        other.error == error &&
        other.isLoading == isLoading;
  }

  @override
  int get hashCode => Object.hash(status, token, user, error, isLoading);

  @override
  String toString() =>
      'AuthState(status: $status, hasToken: ${token != null}, hasUser: ${user != null}, error: $error, isLoading: $isLoading)';
}

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  tokenExpired,
  error,
}

/// Unified auth state manager - single source of truth for all auth operations
class AuthStateManager extends StateNotifier<AuthState> {
  AuthStateManager(this._ref)
    : super(const AuthState(status: AuthStatus.initial)) {
    _initialize();
  }

  final Ref _ref;
  final AuthCacheManager _cacheManager = AuthCacheManager();

  /// Initialize auth state from storage
  Future<void> _initialize() async {
    state = state.copyWith(status: AuthStatus.loading, isLoading: true);

    try {
      final storage = _ref.read(optimizedStorageServiceProvider);
      final token = await storage.getAuthToken();

      if (token != null && token.isNotEmpty) {
        // Validate token before setting authenticated state
        final isValid = await _validateToken(token);
        if (isValid) {
          state = state.copyWith(
            status: AuthStatus.authenticated,
            token: token,
            isLoading: false,
            clearError: true,
          );

          // Update API service with token
          _updateApiServiceToken(token);

          // Load user data in background
          _loadUserData();
        } else {
          // Token is invalid, clear it
          await storage.deleteAuthToken();
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            isLoading: false,
            clearToken: true,
            clearError: true,
          );
        }
      } else {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          isLoading: false,
          clearToken: true,
          clearError: true,
        );
      }
    } catch (e) {
      debugPrint('ERROR: Auth initialization failed: $e');
      state = state.copyWith(
        status: AuthStatus.error,
        error: 'Failed to initialize auth: $e',
        isLoading: false,
      );
    }
  }

  /// Perform login with credentials
  Future<bool> login(
    String username,
    String password, {
    bool rememberCredentials = false,
  }) async {
    state = state.copyWith(
      status: AuthStatus.loading,
      isLoading: true,
      clearError: true,
    );

    try {
      // Ensure API service is available (active server/provider rebuild race)
      await _ensureApiServiceAvailable();
      final api = _ref.read(apiServiceProvider);
      if (api == null) {
        throw Exception('No server connection available');
      }

      // Perform login API call
      final response = await api.login(username, password);

      // Extract and validate token
      final token = response['token'] ?? response['access_token'];
      if (token == null || token.toString().trim().isEmpty) {
        throw Exception('No authentication token received');
      }

      final tokenStr = token.toString();
      if (!_isValidTokenFormat(tokenStr)) {
        throw Exception('Invalid authentication token format');
      }

      // Save token to storage
      final storage = _ref.read(optimizedStorageServiceProvider);
      await storage.saveAuthToken(tokenStr);

      // Save credentials if requested
      if (rememberCredentials) {
        final activeServer = await _ref.read(activeServerProvider.future);
        if (activeServer != null) {
          await storage.saveCredentials(
            serverId: activeServer.id,
            username: username,
            password: password,
          );
          await storage.setRememberCredentials(true);
        }
      }

      // Update state and API service
      state = state.copyWith(
        status: AuthStatus.authenticated,
        token: tokenStr,
        isLoading: false,
        clearError: true,
      );

      _updateApiServiceToken(tokenStr);

      // Cache the successful auth state
      _cacheManager.cacheAuthState(state);

      // Load user data in background
      _loadUserData();

      debugPrint('DEBUG: Login successful');
      return true;
    } catch (e) {
      debugPrint('ERROR: Login failed: $e');
      state = state.copyWith(
        status: AuthStatus.error,
        error: e.toString(),
        isLoading: false,
        clearToken: true,
      );
      return false;
    }
  }

  /// Wait briefly until the API service becomes available
  Future<void> _ensureApiServiceAvailable({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final api = _ref.read(apiServiceProvider);
      if (api != null) return;
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Perform silent auto-login with saved credentials
  Future<bool> silentLogin() async {
    state = state.copyWith(
      status: AuthStatus.loading,
      isLoading: true,
      clearError: true,
    );

    try {
      final storage = _ref.read(optimizedStorageServiceProvider);
      final savedCredentials = await storage.getSavedCredentials();

      if (savedCredentials == null) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          isLoading: false,
          clearError: true,
        );
        return false;
      }

      final serverId = savedCredentials['serverId']!;
      final username = savedCredentials['username']!;
      final password = savedCredentials['password']!;

      // Set active server if needed
      await storage.setActiveServerId(serverId);
      _ref.invalidate(activeServerProvider);

      // Wait for server connection
      final activeServer = await _ref.read(activeServerProvider.future);
      if (activeServer == null) {
        await storage.setActiveServerId(null);
        state = state.copyWith(
          status: AuthStatus.error,
          error: 'Server configuration not found',
          isLoading: false,
        );
        return false;
      }

      // Attempt login
      return await login(username, password, rememberCredentials: false);
    } catch (e) {
      debugPrint('ERROR: Silent login failed: $e');

      // Clear invalid credentials on auth errors
      if (e.toString().contains('401') ||
          e.toString().contains('403') ||
          e.toString().contains('authentication') ||
          e.toString().contains('unauthorized')) {
        final storage = _ref.read(optimizedStorageServiceProvider);
        await storage.deleteSavedCredentials();
      }

      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: e.toString(),
        isLoading: false,
        clearToken: true,
      );
      return false;
    }
  }

  /// Handle token invalidation (called by API service)
  Future<void> onTokenInvalidated() async {
    debugPrint('DEBUG: Auth token invalidated');

    // Clear token from storage
    final storage = _ref.read(optimizedStorageServiceProvider);
    await storage.deleteAuthToken();

    // Update state
    state = state.copyWith(
      status: AuthStatus.tokenExpired,
      clearToken: true,
      clearUser: true,
      clearError: true,
    );

    // Attempt silent re-login if credentials are available
    final hasCredentials = await storage.getSavedCredentials() != null;
    if (hasCredentials) {
      debugPrint('DEBUG: Attempting silent re-login after token invalidation');
      await silentLogin();
    }
  }

  /// Logout user
  Future<void> logout() async {
    state = state.copyWith(status: AuthStatus.loading, isLoading: true);

    try {
      // Call server logout if possible
      final api = _ref.read(apiServiceProvider);
      if (api != null) {
        try {
          await api.logout();
        } catch (e) {
          debugPrint('Warning: Server logout failed: $e');
        }
      }

      // Clear all local auth data
      final storage = _ref.read(optimizedStorageServiceProvider);
      await storage.clearAuthData();

      // Update state
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        clearToken: true,
        clearUser: true,
        clearError: true,
      );

      debugPrint('DEBUG: Logout complete');
    } catch (e) {
      debugPrint('ERROR: Logout failed: $e');
      // Even if logout fails, clear local state
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        clearToken: true,
        clearUser: true,
        error: 'Logout error: $e',
      );
    }
  }

  /// Load user data in background with JWT extraction fallback
  Future<void> _loadUserData() async {
    try {
      // First try to extract user info from JWT token if available
      if (state.token != null) {
        final jwtUserInfo = TokenValidator.extractUserInfo(state.token!);
        if (jwtUserInfo != null) {
          debugPrint('DEBUG: Extracted user info from JWT token');
          state = state.copyWith(user: jwtUserInfo);

          // Still try to load from server in background for complete data
          Future.microtask(() => _loadServerUserData());
          return;
        }
      }

      // Fall back to server data loading
      await _loadServerUserData();
    } catch (e) {
      debugPrint('Warning: Failed to load user data: $e');
      // Don't update state on user data load failure
    }
  }

  /// Load complete user data from server
  Future<void> _loadServerUserData() async {
    try {
      final api = _ref.read(apiServiceProvider);
      if (api != null && state.isAuthenticated) {
        // Check if we already have user data from token validation
        if (state.user != null) {
          debugPrint(
            'DEBUG: User data already available from token validation',
          );
          return;
        }

        final user = await api.getCurrentUser();
        state = state.copyWith(user: user);
        debugPrint('DEBUG: Loaded complete user data from server');
      }
    } catch (e) {
      debugPrint('Warning: Failed to load server user data: $e');
      // Don't update state on server data load failure - keep JWT data if available
    }
  }

  /// Update API service with current token
  void _updateApiServiceToken(String token) {
    final api = _ref.read(apiServiceProvider);
    api?.updateAuthToken(token);
  }

  /// Validate token format using advanced validation
  bool _isValidTokenFormat(String token) {
    final result = TokenValidator.validateTokenFormat(token);
    return result.isValid;
  }

  /// Validate token with comprehensive validation (format + server)
  Future<bool> _validateToken(String token) async {
    // Check cache first
    final cachedResult = TokenValidationCache.getCachedResult(token);
    if (cachedResult != null) {
      debugPrint(
        'DEBUG: Using cached token validation result: ${cachedResult.isValid}',
      );
      return cachedResult.isValid;
    }

    // Fast format validation first
    final formatResult = TokenValidator.validateTokenFormat(token);
    if (!formatResult.isValid) {
      debugPrint('DEBUG: Token format invalid: ${formatResult.message}');
      TokenValidationCache.cacheResult(token, formatResult);
      return false;
    }

    // If format is valid but token is expiring soon, try server validation
    if (formatResult.isExpiringSoon) {
      debugPrint('DEBUG: Token expiring soon, validating with server');
    }

    // Server validation (async with timeout)
    try {
      final api = _ref.read(apiServiceProvider);
      if (api == null) {
        debugPrint('DEBUG: No API service available for token validation');
        return formatResult.isValid; // Fall back to format validation
      }

      User? validationUser;
      final serverResult = await TokenValidator.validateTokenWithServer(
        token,
        () async {
          // Update API with token for validation
          api.updateAuthToken(token);
          // Try to fetch user data as validation
          validationUser = await api.getCurrentUser();
          return validationUser!;
        },
      );

      // Store the user data if validation was successful
      if (serverResult.isValid &&
          validationUser != null &&
          state.isAuthenticated) {
        state = state.copyWith(user: validationUser);
        debugPrint('DEBUG: Cached user data from token validation');
      }

      TokenValidationCache.cacheResult(token, serverResult);

      debugPrint(
        'DEBUG: Server token validation: ${serverResult.isValid} - ${serverResult.message}',
      );
      return serverResult.isValid;
    } catch (e) {
      debugPrint('DEBUG: Token server validation failed: $e');
      // On network error, fall back to format validation if it was valid
      return formatResult.isValid;
    }
  }

  /// Check if user has saved credentials (with caching)
  Future<bool> hasSavedCredentials() async {
    // Check cache first
    final cachedResult = _cacheManager.getCachedCredentialsExist();
    if (cachedResult != null) {
      return cachedResult;
    }

    try {
      final storage = _ref.read(optimizedStorageServiceProvider);
      final hasCredentials = await storage.hasCredentials();

      // Cache the result
      _cacheManager.cacheCredentialsExist(hasCredentials);

      return hasCredentials;
    } catch (e) {
      return false;
    }
  }

  /// Refresh current auth state
  Future<void> refresh() async {
    // Clear cache before refresh to ensure fresh data
    _cacheManager.clearAuthCache();
    TokenValidationCache.clearCache();

    await _initialize();
  }

  /// Clean up expired caches (called periodically)
  void cleanupCaches() {
    _cacheManager.cleanExpiredCache();
    _cacheManager.optimizeCache();
  }

  /// Get performance statistics
  Map<String, dynamic> getPerformanceStats() {
    return {
      'authCache': _cacheManager.getCacheStats(),
      'tokenValidationCache': 'Managed by TokenValidationCache',
      'storageCache': 'Managed by OptimizedStorageService',
    };
  }
}

/// Provider for the unified auth state manager
final authStateManagerProvider =
    StateNotifierProvider<AuthStateManager, AuthState>((ref) {
      return AuthStateManager(ref);
    });

/// Computed providers for common auth state queries
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(
    authStateManagerProvider.select((state) => state.isAuthenticated),
  );
});

final authTokenProvider2 = Provider<String?>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.token));
});

final authUserProvider = Provider<dynamic>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.user));
});

final authErrorProvider2 = Provider<String?>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.error));
});

final isAuthLoadingProvider = Provider<bool>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.isLoading));
});
