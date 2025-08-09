import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/navigation_service.dart';
import 'core/widgets/error_boundary.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/app_providers.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_extensions.dart';
import 'shared/widgets/offline_indicator.dart';
import 'features/auth/views/connect_signin_page.dart';
import 'features/auth/providers/unified_auth_providers.dart';
import 'core/auth/auth_state_manager.dart';
import 'package:flutter/cupertino.dart';
import 'features/onboarding/views/onboarding_sheet.dart';
import 'features/chat/views/chat_page.dart';
import 'features/navigation/views/splash_launcher_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sharedPrefs = await SharedPreferences.getInstance();
  const secureStorage = FlutterSecureStorage();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        secureStorageProvider.overrideWithValue(secureStorage),
      ],
      child: const ConduitApp(),
    ),
  );
}

class ConduitApp extends ConsumerStatefulWidget {
  const ConduitApp({super.key});

  @override
  ConsumerState<ConduitApp> createState() => _ConduitAppState();
}

class _ConduitAppState extends ConsumerState<ConduitApp> {
  bool _attemptedSilentAutoLogin = false;
  @override
  void initState() {
    super.initState();
    _initializeAppState();
  }

  Widget _buildInitialLoadingSkeleton(BuildContext context) {
    // Replace skeleton with branded splash during initialization
    return const SplashLauncherPage();
  }

  void _initializeAppState() {
    // Initialize unified auth state manager and API integration synchronously
    // This ensures auth state is loaded before first widget build
    debugPrint('DEBUG: Initializing unified auth system');

    // Initialize auth state manager (will handle token validation automatically)
    ref.read(authStateManagerProvider);

    // Ensure API service auth integration is active
    ref.read(authApiIntegrationProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Use select to watch only the specific themeMode property to reduce rebuilds
    final themeMode = ref.watch(themeModeProvider.select((mode) => mode));

    // Reduced debug noise - only log when necessary
    // debugPrint('DEBUG: Building app');

    // Determine the current theme based on themeMode
    // Default to Conduit brand theme globally
    final currentTheme = themeMode == ThemeMode.dark
        ? AppTheme.conduitDarkTheme
        : themeMode == ThemeMode.light
        ? AppTheme.conduitLightTheme
        : MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? AppTheme.conduitDarkTheme
        : AppTheme.conduitLightTheme;

    return AnimatedThemeWrapper(
      theme: currentTheme,
      duration: AnimationDuration.medium,
      child: ErrorBoundary(
        child: MaterialApp(
          title: 'Conduit',
          theme: AppTheme.conduitLightTheme,
          darkTheme: AppTheme.conduitDarkTheme,
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          navigatorKey: NavigationService.navigatorKey,
          builder: (context, child) {
            // Keep a subtle fade for navigation transitions only
            final wrapped = OfflineIndicator(
              child: child ?? const SizedBox.shrink(),
            );
            return wrapped;
          },
          home: _getInitialPageWithReactiveState(),
          onGenerateRoute: NavigationService.generateRoute,
          navigatorObservers: [_NavigationObserver()],
        ),
      ),
    );
  }

  Widget _getInitialPageWithReactiveState() {
    return Consumer(
      builder: (context, ref, child) {
        // Watch for server connection state changes
        final activeServerAsync = ref.watch(activeServerProvider);
        final reviewerMode = ref.watch(reviewerModeProvider);

        if (reviewerMode) {
          // In reviewer mode, skip server/auth flows and go to chat
          NavigationService.setCurrentRoute(Routes.chat);
          return const ChatPage();
        }

        return activeServerAsync.when(
          data: (activeServer) {
            if (activeServer == null) {
              return const ConnectAndSignInPage();
            }

            // Server is connected, now check authentication reactively
            final authNavState = ref.watch(authNavigationStateProvider);

            if (authNavState == AuthNavigationState.needsLogin) {
              // Try one-shot silent login if credentials are saved
              if (!_attemptedSilentAutoLogin) {
                _attemptedSilentAutoLogin = true;
                Future.microtask(() async {
                  try {
                    final hasCreds = await ref.read(
                      hasSavedCredentialsProvider2.future,
                    );
                    if (hasCreds) {
                      await ref.read(silentLoginActionProvider);
                    }
                  } catch (_) {
                    // Ignore errors, fallback to showing unified page
                  }
                });
              }
              return const ConnectAndSignInPage();
            }

            if (authNavState == AuthNavigationState.loading) {
              return _buildInitialLoadingSkeleton(context);
            }

            if (authNavState == AuthNavigationState.error) {
              return _buildErrorState(
                ref.watch(authErrorProvider3) ?? 'Authentication error',
              );
            }

            // User is authenticated, navigate directly to chat page
            _initializeBackgroundResources(ref);

            // Set the current route for navigation tracking
            NavigationService.setCurrentRoute(Routes.chat);

            return const ChatPage();
          },
          loading: () => _buildInitialLoadingSkeleton(context),
          error: (error, stackTrace) {
            debugPrint('DEBUG: Server provider error: $error');
            return _buildErrorState('Server connection failed: $error');
          },
        );
      },
    );
  }

  void _initializeBackgroundResources(WidgetRef ref) {
    // Initialize resources in the background without blocking UI
    Future.microtask(() async {
      try {
        // Get the API service
        final api = ref.read(apiServiceProvider);
        if (api == null) {
          debugPrint(
            'DEBUG: API service not available for background initialization',
          );
          return;
        }

        // Explicitly get the current auth token and set it on the API service
        final authToken = ref.read(authTokenProvider3);
        if (authToken != null && authToken.isNotEmpty) {
          api.updateAuthToken(authToken);
          debugPrint('DEBUG: Background - Set auth token on API service');
        } else {
          debugPrint('DEBUG: Background - No auth token available yet');
          return;
        }

        // Initialize the token updater for future updates
        ref.read(apiTokenUpdaterProvider);

        // Load models and set default in background
        await ref.read(defaultModelProvider.future);
        debugPrint('DEBUG: Background initialization completed');

        // Onboarding: show once if not seen
        final storage = ref.read(optimizedStorageServiceProvider);
        final seen = await storage.getOnboardingSeen();
        if (!seen && mounted) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final navContext = NavigationService.navigatorKey.currentContext;
            if (!mounted || navContext == null) return;
            _showOnboarding(navContext);
            await storage.setOnboardingSeen(true);
          });
        }
      } catch (e) {
        debugPrint('DEBUG: Background initialization failed: $e');
        // Don't throw - this is background initialization
      }
    });
  }

  void _showOnboarding(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppBorderRadius.modal),
          ),
          boxShadow: ConduitShadows.modal,
        ),
        child: const OnboardingSheet(),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Scaffold(
      backgroundColor: context.conduitTheme.surfaceBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: IconSize.xxl + Spacing.md,
                color: context.conduitTheme.error,
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'Initialization Failed',
                style: TextStyle(
                  fontSize: AppTypography.headlineLarge,
                  fontWeight: FontWeight.bold,
                  color: context.conduitTheme.textPrimary,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                error,
                style: TextStyle(color: context.conduitTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.lg),
              ElevatedButton(
                onPressed: () {
                  // Restart the app
                  WidgetsBinding.instance.reassembleApplication();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.conduitTheme.buttonPrimary,
                  foregroundColor: context.conduitTheme.buttonPrimaryText,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    // Log navigation for debugging and analytics
    debugPrint('DEBUG: Navigation - Pushed: ${route.settings.name}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    debugPrint('DEBUG: Navigation - Popped: ${route.settings.name}');
  }
}
