import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/widgets/error_boundary.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/app_providers.dart';
import 'core/router/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/offline_indicator.dart';
import 'features/auth/providers/unified_auth_providers.dart';
import 'core/auth/auth_state_manager.dart';
import 'core/utils/debug_logger.dart';
import 'core/utils/system_ui_style.dart';

import 'package:conduit/l10n/app_localizations.dart';
import 'core/services/share_receiver_service.dart';
import 'core/providers/app_startup_providers.dart';

developer.TimelineTask? _startupTimeline;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Global error handlers
      FlutterError.onError = (FlutterErrorDetails details) {
        DebugLogger.error(
          'flutter-error',
          scope: 'app/framework',
          error: details.exception,
        );
        final stack = details.stack;
        if (stack != null) {
          debugPrintStack(stackTrace: stack);
        }
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        DebugLogger.error(
          'platform-error',
          scope: 'app/platform',
          error: error,
          stackTrace: stack,
        );
        debugPrintStack(stackTrace: stack);
        return true;
      };

      // Start startup timeline instrumentation
      _startupTimeline = developer.TimelineTask();
      _startupTimeline!.start('app_startup');
      _startupTimeline!.instant('bindings_initialized');

      // Defer edge-to-edge mode to post-frame to avoid impacting first paint
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ignore: discarded_futures
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _startupTimeline?.instant('edge_to_edge_enabled');
      });

      final sharedPrefs = await SharedPreferences.getInstance();
      _startupTimeline!.instant('shared_prefs_ready');
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
      _startupTimeline!.instant('secure_storage_ready');

      // Finish timeline after first frame paints
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startupTimeline?.instant('first_frame_rendered');
        _startupTimeline?.finish();
        _startupTimeline = null;
      });

      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPrefs),
            secureStorageProvider.overrideWithValue(secureStorage),
          ],
          child: const ConduitApp(),
        ),
      );
      developer.Timeline.instantSync('runApp_called');
    },
    (error, stack) {
      DebugLogger.error(
        'zone-error',
        scope: 'app',
        error: error,
        stackTrace: stack,
      );
      debugPrintStack(stackTrace: stack);
    },
  );
}

class ConduitApp extends ConsumerStatefulWidget {
  const ConduitApp({super.key});

  @override
  ConsumerState<ConduitApp> createState() => _ConduitAppState();
}

class _ConduitAppState extends ConsumerState<ConduitApp> {
  ProviderSubscription<void>? _startupFlowSubscription;
  Brightness? _lastAppliedOverlayBrightness;
  @override
  void initState() {
    super.initState();
    // Defer heavy provider initialization to after first frame to render UI sooner
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeAppState());

    // Activate app startup flow without tying it to root widget rebuilds
    _startupFlowSubscription = ref.listenManual<void>(
      appStartupFlowProvider,
      (previous, next) {},
    );
  }

  void _initializeAppState() {
    DebugLogger.auth('init', scope: 'app');

    ref.read(authStateManagerProvider);
    ref.read(authApiIntegrationProvider);
    ref.read(defaultModelAutoSelectionProvider);
    ref.read(shareReceiverInitializerProvider);
  }

  @override
  void dispose() {
    _startupFlowSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider.select((mode) => mode));
    final router = ref.watch(goRouterProvider);
    final locale = ref.watch(localeProvider);

    return ErrorBoundary(
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
          final brightness = Theme.of(context).brightness;
          if (_lastAppliedOverlayBrightness != brightness) {
            _lastAppliedOverlayBrightness = brightness;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              applySystemUiOverlayStyleOnce(brightness: brightness);
            });
          }
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: mediaQuery.textScaler.clamp(
                minScaleFactor: 1.0,
                maxScaleFactor: 3.0,
              ),
            ),
            child: OfflineIndicator(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }
}
