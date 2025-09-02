import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../../features/auth/providers/unified_auth_providers.dart';
import '../services/navigation_service.dart';
import '../../features/onboarding/views/onboarding_sheet.dart';
import '../../shared/theme/theme_extensions.dart';
import '../utils/debug_logger.dart';

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

  // When auth state becomes authenticated, run additional background work
  ref.listen<AuthNavigationState>(authNavigationStateProvider,
      (prev, next) {
    if (next == AuthNavigationState.authenticated) {
      // Schedule microtask so we don't perform side-effects inside build
      Future.microtask(() async {
        try {
          final api = ref.read(apiServiceProvider);
          if (api == null) {
            DebugLogger.warning(
              'API service not available for startup flow',
            );
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
            DebugLogger.warning('StartupFlow: default model preload failed: $e');
          }

          // Show onboarding once when user reaches chat and hasn't seen it yet
          await _maybeShowOnboarding(ref);
        } catch (e) {
          DebugLogger.error('StartupFlow error', e);
        }
      });
    }
  });
});

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
