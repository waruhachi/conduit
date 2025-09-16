import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../features/auth/providers/unified_auth_providers.dart';
import '../services/navigation_service.dart';
import '../models/conversation.dart';
import '../services/background_streaming_handler.dart';
import '../../features/onboarding/views/onboarding_sheet.dart';
import '../../shared/theme/theme_extensions.dart';
import '../services/connectivity_service.dart';
import '../utils/debug_logger.dart';

enum _ConversationWarmupStatus { idle, warming, complete }

final _conversationWarmupStatusProvider =
    StateProvider<_ConversationWarmupStatus>(
      (ref) => _ConversationWarmupStatus.idle,
    );

final _conversationWarmupLastAttemptProvider = StateProvider<DateTime?>(
  (ref) => null,
);

void _scheduleConversationWarmup(Ref ref, {bool force = false}) {
  final navState = ref.read(authNavigationStateProvider);
  if (navState != AuthNavigationState.authenticated) {
    ref.read(_conversationWarmupStatusProvider.notifier).state =
        _ConversationWarmupStatus.idle;
    return;
  }

  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) {
    return;
  }

  final statusController = ref.read(_conversationWarmupStatusProvider.notifier);
  final status = statusController.state;

  if (!force) {
    if (status == _ConversationWarmupStatus.warming ||
        status == _ConversationWarmupStatus.complete) {
      return;
    }
  } else if (status == _ConversationWarmupStatus.warming) {
    return;
  }

  final now = DateTime.now();
  final lastAttempt = ref.read(_conversationWarmupLastAttemptProvider);
  if (!force &&
      lastAttempt != null &&
      now.difference(lastAttempt) < const Duration(seconds: 30)) {
    return;
  }
  ref.read(_conversationWarmupLastAttemptProvider.notifier).state = now;

  statusController.state = _ConversationWarmupStatus.warming;

  Future.microtask(() async {
    try {
      final existing = ref.read(conversationsProvider);
      if (existing.hasValue) {
        statusController.state = _ConversationWarmupStatus.complete;
        return;
      }
      if (existing.hasError) {
        ref.invalidate(conversationsProvider);
      }
      final conversations = await ref.read(conversationsProvider.future);
      statusController.state = _ConversationWarmupStatus.complete;
      DebugLogger.info(
        'Background chats warmup fetched ${conversations.length} conversations',
      );
    } catch (error) {
      DebugLogger.warning('Background chats warmup failed: $error');
      statusController.state = _ConversationWarmupStatus.idle;
    }
  });
}

/// App-level startup/background task flow orchestrator.
///
/// Moves background initialization out of widgets and into a Riverpod provider,
/// keeping UI lean and business logic centralized.
final appStartupFlowProvider = Provider<void>((ref) {
  // Ensure token integration listeners are active
  ref.watch(authApiIntegrationProvider);
  ref.watch(apiTokenUpdaterProvider);

  // Kick background model loading flow (non-blocking)
  ref.watch(backgroundModelLoadProvider);

  // If authenticated, keep socket service alive and connected
  final navState = ref.watch(authNavigationStateProvider);
  if (navState == AuthNavigationState.authenticated) {
    ref.watch(socketServiceProvider);
  }

  // Ensure resume-triggered foreground refresh is active
  ref.watch(foregroundRefreshProvider);

  // Keep Socket.IO connection alive in background within platform limits
  ref.watch(socketPersistenceProvider);

  // Warm the conversations list in the background as soon as possible
  Future.microtask(() => _scheduleConversationWarmup(ref));

  // Watch for auth transitions to trigger warmup and other background work
  ref.listen<AuthNavigationState>(authNavigationStateProvider, (prev, next) {
    if (next == AuthNavigationState.authenticated) {
      // Schedule microtask so we don't perform side-effects inside build
      Future.microtask(() async {
        try {
          final api = ref.read(apiServiceProvider);
          if (api == null) {
            DebugLogger.warning('API service not available for startup flow');
            return;
          }

          // Ensure API has the latest token immediately
          final authToken = ref.read(authTokenProvider3);
          if (authToken != null && authToken.isNotEmpty) {
            api.updateAuthToken(authToken);
            DebugLogger.auth('StartupFlow: Applied auth token to API');
          }

          // Preload default model in background (best-effort)
          try {
            await ref.read(defaultModelProvider.future);
          } catch (e) {
            DebugLogger.warning(
              'StartupFlow: default model preload failed: $e',
            );
          }

          // Kick background chat warmup now that we're authenticated
          _scheduleConversationWarmup(ref, force: true);

          // Show onboarding once when user reaches chat and hasn't seen it yet
          await _maybeShowOnboarding(ref);
        } catch (e) {
          DebugLogger.error('StartupFlow error', e);
        }
      });
    } else {
      // Reset warmup state when leaving authenticated flow
      ref.read(_conversationWarmupStatusProvider.notifier).state =
          _ConversationWarmupStatus.idle;
    }
  });

  // Retry warmup when connectivity is restored
  ref.listen<bool>(isOnlineProvider, (prev, next) {
    if (next == true) {
      _scheduleConversationWarmup(ref);
    }
  });

  // When conversations reload (e.g., manual refresh), ensure warmup runs again
  ref.listen<AsyncValue<List<Conversation>>>(conversationsProvider, (
    previous,
    next,
  ) {
    final wasReady = previous?.hasValue == true || previous?.hasError == true;
    if (wasReady && next.isLoading) {
      ref.read(_conversationWarmupStatusProvider.notifier).state =
          _ConversationWarmupStatus.idle;
      Future.microtask(() => _scheduleConversationWarmup(ref, force: true));
    }
  });
});

/// Listens to app lifecycle and refreshes server state when app returns to foreground.
///
/// Rationale: Socket.IO does not replay historical events. If the app was suspended,
/// we may miss updates. On resume, invalidate conversations to reconcile state.
final foregroundRefreshProvider = Provider<void>((ref) {
  final observer = _ForegroundRefreshObserver(ref);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
});

class _ForegroundRefreshObserver extends WidgetsBindingObserver {
  final Ref _ref;
  _ForegroundRefreshObserver(this._ref);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Schedule to avoid side-effects during build frames
      Future.microtask(() {
        try {
          _ref.invalidate(conversationsProvider);
          _ref.read(_conversationWarmupStatusProvider.notifier).state =
              _ConversationWarmupStatus.idle;
        } catch (_) {}
        _scheduleConversationWarmup(_ref, force: true);
      });
    }
  }
}

/// Attempts to keep the realtime socket connection alive while the app is
/// backgrounded, similar to how PersistentStreamingService works for streams.
///
/// Notes:
/// - iOS: limited to short background task windows; we send periodic keepAlive.
/// - Android: uses existing foreground service notification.
final socketPersistenceProvider = Provider<void>((ref) {
  final observer = _SocketPersistenceObserver(ref);
  WidgetsBinding.instance.addObserver(observer);
  // React to active conversation changes while backgrounded
  final sub = ref.listen<Conversation?>(
    activeConversationProvider,
    (prev, next) => observer.onActiveConversationChanged(),
  );
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  ref.onDispose(sub.close);
});

class _SocketPersistenceObserver extends WidgetsBindingObserver {
  final Ref _ref;
  _SocketPersistenceObserver(this._ref);

  static const String _socketId = 'socket-keepalive';
  Timer? _heartbeat;
  bool _bgActive = false;
  bool _isBackgrounded = false;

  bool _shouldKeepAlive() {
    final authed =
        _ref.read(authNavigationStateProvider) ==
        AuthNavigationState.authenticated;
    final hasConversation = _ref.read(activeConversationProvider) != null;
    return authed && hasConversation;
  }

  void _startBackground() {
    if (_bgActive) return;
    if (!_shouldKeepAlive()) return;
    try {
      BackgroundStreamingHandler.instance.startBackgroundExecution([_socketId]);
      // Periodic keep-alive (primarily useful on iOS)
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
        try {
          await BackgroundStreamingHandler.instance.keepAlive();
        } catch (_) {}
      });
      _bgActive = true;
    } catch (_) {}
  }

  void _stopBackground() {
    if (!_bgActive) return;
    try {
      BackgroundStreamingHandler.instance.stopBackgroundExecution([_socketId]);
    } catch (_) {}
    _heartbeat?.cancel();
    _heartbeat = null;
    _bgActive = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _isBackgrounded = true;
        _startBackground();
        break;
      case AppLifecycleState.resumed:
        _isBackgrounded = false;
        _stopBackground();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _isBackgrounded = false;
        _stopBackground();
        break;
    }
  }

  // Called when active conversation changes; only acts during background
  void onActiveConversationChanged() {
    if (!_isBackgrounded) return;
    if (_shouldKeepAlive()) {
      _startBackground();
    } else {
      _stopBackground();
    }
  }
}

Future<void> _maybeShowOnboarding(Ref ref) async {
  try {
    final storage = ref.read(optimizedStorageServiceProvider);
    final seen = await storage.getOnboardingSeen();
    if (seen) return;

    // Small delay to allow initial navigation/frame to settle
    await Future.delayed(const Duration(milliseconds: 300));

    // Only surface onboarding on the chat route to avoid interrupting flows
    if (NavigationService.currentRoute != Routes.chat) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navContext = NavigationService.navigatorKey.currentContext;
      if (navContext == null) return;

      // Show onboarding sheet
      showModalBottomSheet(
        context: navContext,
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

      await storage.setOnboardingSeen(true);
    });
  } catch (e) {
    // Best-effort only; never fail app startup due to onboarding
    DebugLogger.warning('StartupFlow: onboarding display failed: $e');
  }
}
