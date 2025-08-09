import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;
import '../../core/services/connectivity_service.dart';
import '../theme/theme_extensions.dart';

class OfflineIndicator extends ConsumerWidget {
  final Widget child;
  final bool showBanner;

  const OfflineIndicator({
    super.key,
    required this.child,
    this.showBanner = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityStatus = ref.watch(connectivityStatusProvider);

    return Stack(
      children: [
        child,
        if (showBanner)
          connectivityStatus.when(
            data: (status) {
              if (status == ConnectivityStatus.offline) {
                return _OfflineBanner();
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => _OfflineBanner(),
          ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child:
            Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: context.conduitTheme.warning,
                    boxShadow: ConduitShadows.low,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Platform.isIOS
                            ? CupertinoIcons.wifi_slash
                            : Icons.wifi_off,
                        color: context.conduitTheme.textInverse,
                        size: AppTypography.headlineMedium,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          'You\'re offline. Some features may be limited.',
                          style: TextStyle(
                            color: context.conduitTheme.textInverse,
                            fontSize: AppTypography.labelLarge,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .animate(onPlay: (controller) => controller.forward())
                .slideY(
                  begin: -1,
                  end: 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                ),
      ),
    );
  }
}

// Inline offline indicator for specific features
class InlineOfflineIndicator extends ConsumerWidget {
  final String message;
  final IconData? icon;
  final Color? backgroundColor;

  const InlineOfflineIndicator({
    super.key,
    this.message = 'This feature requires an internet connection',
    this.icon,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    if (isOnline) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            context.conduitTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: context.conduitTheme.warning.withValues(alpha: 0.3),
          width: BorderWidth.regular,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon ??
                (Platform.isIOS ? CupertinoIcons.wifi_slash : Icons.wifi_off),
            color: context.conduitTheme.warning,
            size: Spacing.lg,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: context.conduitTheme.warning,
                fontSize: AppTypography.labelLarge,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 300));
  }
}

// Offline-aware button that disables when offline
class OfflineAwareButton extends ConsumerWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool requiresConnection;
  final String? offlineTooltip;

  const OfflineAwareButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.requiresConnection = true,
    this.offlineTooltip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final enabled = !requiresConnection || isOnline;

    return Tooltip(
      message: !enabled
          ? (offlineTooltip ?? 'This action requires an internet connection')
          : '',
      child: FilledButton(onPressed: enabled ? onPressed : null, child: child),
    );
  }
}

// Chat-specific offline indicator
class ChatOfflineOverlay extends ConsumerWidget {
  const ChatOfflineOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    if (isOnline) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.conduitTheme.warning.withValues(alpha: 0.2),
        border: Border(
          top: BorderSide(
            color: context.conduitTheme.warning.withValues(alpha: 0.5),
            width: BorderWidth.regular,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Platform.isIOS ? CupertinoIcons.wifi_slash : Icons.wifi_off,
            color: context.conduitTheme.warning,
            size: Spacing.md,
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            'Messages will be sent when you\'re back online',
            style: TextStyle(
              color: context.conduitTheme.warning,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 300));
  }
}
