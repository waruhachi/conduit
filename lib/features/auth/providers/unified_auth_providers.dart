import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_state_manager.dart';
import '../../../core/providers/app_providers.dart';

/// Unified auth providers using the new auth state manager
/// These replace the old auth providers for better efficiency

/// Login action provider (schedules side-effect outside provider build)
final loginActionProvider = Provider.family<Future<bool>, Map<String, String>>(
  (ref, credentials) async {
    final authManager = ref.read(authStateManagerProvider.notifier);

    final username = credentials['username']!;
    final password = credentials['password']!;
    final rememberCredentials = credentials['remember'] == 'true';

    // Defer the mutation to avoid changing other providers during build
    return Future(() => authManager.login(
          username,
          password,
          rememberCredentials: rememberCredentials,
        ));
  },
);

/// Silent login action provider - returns a callback to run later
final silentLoginActionProvider = Provider<Future<bool> Function()>((ref) {
  final authManager = ref.read(authStateManagerProvider.notifier);
  return () => authManager.silentLogin();
});

/// Logout action provider - returns a callback to run later
final logoutActionProvider = Provider<Future<void> Function()>((ref) {
  final authManager = ref.read(authStateManagerProvider.notifier);
  return () => authManager.logout();
});

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

/// Helper provider to trigger auth refresh - returns a callback
final refreshAuthProvider = Provider<Future<void> Function()>((ref) {
  final authManager = ref.read(authStateManagerProvider.notifier);
  return () => authManager.refresh();
});

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
