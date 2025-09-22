import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/widgets/error_boundary.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/app_providers.dart';
import 'core/router/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_extensions.dart';
import 'shared/widgets/offline_indicator.dart';
import 'features/auth/providers/unified_auth_providers.dart';
import 'core/auth/auth_state_manager.dart';
import 'core/utils/debug_logger.dart';

import 'package:conduit/l10n/app_localizations.dart';
import 'core/services/share_receiver_service.dart';
import 'core/providers/app_startup_providers.dart';
import 'core/models/server_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable edge-to-edge globally (back-compat on pre-Android 15)
  // Pairs with Activity's EdgeToEdge.enable and our SafeArea usage.
  // Do not block first frame on system UI mode; apply shortly after startup
  // ignore: discarded_futures
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final sharedPrefs = await SharedPreferences.getInstance();
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'conduit_secure_prefs',
      preferencesKeyPrefix: 'conduit_',
      resetOnError: false,
    ),
    iOptions: IOSOptions(
      accountName: 'conduit_secure_storage',
      synchronizable: false,
    ),
  );

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
  ProviderSubscription<AuthNavigationState>? _authNavSubscription;
  ProviderSubscription<AsyncValue<ServerConfig?>>? _activeServerSubscription;
  @override
  void initState() {
    super.initState();
    // Defer heavy provider initialization to after first frame to render UI sooner
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAppState());

    _authNavSubscription = ref.listenManual<AuthNavigationState>(
      authNavigationStateProvider,
      (previous, next) {
        if (next == AuthNavigationState.needsLogin) {
          _maybeAttemptSilentLogin();
        } else {
          _attemptedSilentAutoLogin = false;
        }
      },
    );

    _activeServerSubscription = ref.listenManual<AsyncValue<ServerConfig?>>(
      activeServerProvider,
      (previous, next) {
        next.when(
          data: (server) {
            if (server != null) {
              _maybeAttemptSilentLogin();
            }
          },
          loading: () {},
          error: (error, stackTrace) {},
        );
      },
    );

    Future.microtask(_maybeAttemptSilentLogin);
  }

  void _initializeAppState() {
    DebugLogger.auth('Initializing unified auth system');

    ref.read(authStateManagerProvider);
    ref.read(authApiIntegrationProvider);
    ref.read(defaultModelAutoSelectionProvider);
    ref.read(shareReceiverInitializerProvider);
  }

  @override
  void dispose() {
    _authNavSubscription?.close();
    _activeServerSubscription?.close();
    super.dispose();
  }

  void _maybeAttemptSilentLogin() {
    if (_attemptedSilentAutoLogin) return;

    final authState = ref.read(authNavigationStateProvider);
    if (authState != AuthNavigationState.needsLogin) {
      return;
    }

    final activeServerAsync = ref.read(activeServerProvider);
    final hasActiveServer = activeServerAsync.maybeWhen(
      data: (server) => server != null,
      orElse: () => false,
    );

    if (!hasActiveServer) {
      return;
    }

    _attemptedSilentAutoLogin = true;

    Future.microtask(() async {
      try {
        final hasCreds = await ref.read(hasSavedCredentialsProvider2.future);
        if (hasCreds) {
          await ref.read(authActionsProvider).silentLogin();
        }
      } catch (_) {
        // Ignore silent login errors; fall back to manual login.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider.select((mode) => mode));
    final router = ref.watch(goRouterProvider);
    ref.watch(appStartupFlowProvider);

    final currentTheme = themeMode == ThemeMode.dark
        ? AppTheme.conduitDarkTheme
        : themeMode == ThemeMode.light
        ? AppTheme.conduitLightTheme
        : MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? AppTheme.conduitDarkTheme
        : AppTheme.conduitLightTheme;

    final locale = ref.watch(localeProvider);

    return AnimatedThemeWrapper(
      theme: currentTheme,
      duration: AnimationDuration.medium,
      child: ErrorBoundary(
        child: MaterialApp.router(
          routerConfig: router,
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          theme: AppTheme.conduitLightTheme,
          darkTheme: AppTheme.conduitDarkTheme,
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeListResolutionCallback: (deviceLocales, supported) {
            if (locale != null) return locale;
            if (deviceLocales == null || deviceLocales.isEmpty) {
              return supported.first;
            }
            for (final device in deviceLocales) {
              for (final loc in supported) {
                if (loc.languageCode == device.languageCode) return loc;
              }
            }
            return supported.first;
          },
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: mediaQuery.textScaler.clamp(
                  minScaleFactor: 0.8,
                  maxScaleFactor: 1.3,
                ),
              ),
              child: OfflineIndicator(child: child ?? const SizedBox.shrink()),
            );
          },
        ),
      ),
    );
  }
}
