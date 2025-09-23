import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_state_manager.dart';
import '../../../core/providers/app_providers.dart';

/// Unified auth providers using the new auth state manager
/// These replace the old auth providers for better efficiency

/// Imperative auth actions wrapper to avoid side-effects during provider build
class AuthActions {
  final Ref _ref;
  AuthActions(this._ref);

  AuthStateManager get _auth => _ref.read(authStateManagerProvider.notifier);

  Future<bool> login(
    String username,
    String password, {
    bool rememberCredentials = false,
  }) {
    // Defer mutation to a microtask to avoid provider-build side-effects
    return Future(
      () => _auth.login(
        username,
        password,
        rememberCredentials: rememberCredentials,
      ),
    );
  }

  Future<bool> loginWithApiKey(
    String apiKey, {
    bool rememberCredentials = false,
  }) {
    return Future(
      () => _auth.loginWithApiKey(
        apiKey,
        rememberCredentials: rememberCredentials,
      ),
    );
  }

  Future<bool> silentLogin() {
    return Future(() => _auth.silentLogin());
  }

  Future<void> logout() {
    return Future(() => _auth.logout());
  }

  Future<void> refresh() {
    return Future(() => _auth.refresh());
  }
}

final authActionsProvider = Provider<AuthActions>((ref) => AuthActions(ref));

// Legacy action providers have been replaced by `authActionsProvider`

/// Check if saved credentials exist
final hasSavedCredentialsProvider2 = FutureProvider<bool>((ref) async {
  final authManager = ref.read(authStateManagerProvider.notifier);
  return await authManager.hasSavedCredentials();
});

/// Computed providers for UI consumption
/// These automatically update when auth state changes

final isAuthenticatedProvider2 = Provider<bool>((ref) {
  return ref.watch(
    authStateManagerProvider.select((state) => state.isAuthenticated),
  );
});

final authTokenProvider3 = Provider<String?>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.token));
});

final currentUserProvider2 = Provider<dynamic>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.user));
});

final authErrorProvider3 = Provider<String?>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.error));
});

final isAuthLoadingProvider2 = Provider<bool>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.isLoading));
});

final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authStateManagerProvider.select((state) => state.status));
});

// Use `ref.read(authActionsProvider).refresh()` instead of refresh providers

/// Provider to watch for auth state changes and update API service
final authApiIntegrationProvider = Provider<void>((ref) {
  ref.listen(authTokenProvider3, (previous, next) {
    final api = ref.read(apiServiceProvider);
    if (api != null && next != null && next.isNotEmpty) {
      api.updateAuthToken(next);
    }
  });
});

/// Navigation helper provider - determines where user should go
final authNavigationStateProvider = Provider<AuthNavigationState>((ref) {
  final authState = ref.watch(authStateManagerProvider);

  switch (authState.status) {
    case AuthStatus.initial:
    case AuthStatus.loading:
      return AuthNavigationState.loading;
    case AuthStatus.authenticated:
      return AuthNavigationState.authenticated;
    case AuthStatus.unauthenticated:
    case AuthStatus.tokenExpired:
      return AuthNavigationState.needsLogin;
    case AuthStatus.error:
      return AuthNavigationState.error;
  }
});

enum AuthNavigationState { loading, authenticated, needsLogin, error }
