import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../shared/widgets/improved_loading_states.dart';

import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../core/providers/app_providers.dart';
import '../../auth/providers/unified_auth_providers.dart';

/// Profile page (You tab) showing user info and main actions
/// Enhanced with production-grade design tokens for better cohesion
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return ErrorBoundary(
      child: user.when(
        data: (userData) => Scaffold(
          backgroundColor: context.conduitTheme.surfaceBackground,
          appBar: AppBar(
            backgroundColor: context.conduitTheme.surfaceBackground,
            elevation: Elevation.none,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: Icon(
                UiUtils.platformIcon(
                  ios: CupertinoIcons.back,
                  android: Icons.arrow_back,
                ),
                color: context.conduitTheme.textPrimary,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
            ),
            toolbarHeight: kToolbarHeight,
            titleSpacing: 0.0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You',
                  style: context.conduitTheme.headingSmall?.copyWith(
                    color: context.conduitTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Header - Enhanced with better spacing and animations
                _buildProfileHeader(userData)
                    .animate()
                    .fadeIn(duration: AnimationDuration.pageTransition)
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      curve: AnimationCurves.pageTransition,
                    ),
                const SizedBox(height: Spacing.sectionGap),

                // Account Section - Enhanced with improved spacing
                _buildAccountSection(context, ref)
                    .animate()
                    .fadeIn(
                      delay: AnimationDelay.short,
                      duration: AnimationDuration.pageTransition,
                    )
                    .slideY(
                      begin: 0.1,
                      end: 0,
                      curve: AnimationCurves.pageTransition,
                    ),
              ],
            ),
          ),
        ),
        loading: () => Scaffold(
          backgroundColor: context.conduitTheme.surfaceBackground,
          appBar: AppBar(
            backgroundColor: context.conduitTheme.surfaceBackground,
            elevation: Elevation.none,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: Icon(
                UiUtils.platformIcon(
                  ios: CupertinoIcons.back,
                  android: Icons.arrow_back,
                ),
                color: context.conduitTheme.textPrimary,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
            ),
            title: Text(
              'You',
              style: context.conduitTheme.headingSmall?.copyWith(
                color: context.conduitTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
          ),
          body: const Center(
            child: ImprovedLoadingState(message: 'Loading profile...'),
          ),
        ),
        error: (error, stack) => Scaffold(
          backgroundColor: context.conduitTheme.surfaceBackground,
          appBar: AppBar(
            backgroundColor: context.conduitTheme.surfaceBackground,
            elevation: Elevation.none,
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: Icon(
                UiUtils.platformIcon(
                  ios: CupertinoIcons.back,
                  android: Icons.arrow_back,
                ),
                color: context.conduitTheme.textPrimary,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
            ),
            title: Text(
              'You',
              style: context.conduitTheme.headingSmall?.copyWith(
                color: context.conduitTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
          ),
          body: Center(
            child: ImprovedEmptyState(
              title: 'Unable to load profile',
              subtitle: 'Please check your connection and try again',
              icon: UiUtils.platformIcon(
                ios: CupertinoIcons.exclamationmark_triangle,
                android: Icons.error_outline,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(dynamic user) {
    return Builder(
      builder: (context) => ConduitCard(
        padding: const EdgeInsets.all(Spacing.cardPadding),
        child: Row(
          children: [
            // Enhanced avatar with better sizing and shadows
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppBorderRadius.avatar),
                boxShadow: ConduitShadows.card,
              ),
              child: ConduitAvatar(
                size: IconSize.avatar,
                text: user?.name?.substring(0, 1) ?? 'U',
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.name ?? 'User',
                    style: context.conduitTheme.headingMedium?.copyWith(
                      color: context.conduitTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    user?.email ?? 'No email',
                    style: context.conduitTheme.bodyMedium?.copyWith(
                      color: context.conduitTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  // Enhanced status badge with better styling
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: context.conduitTheme.success.withValues(
                        alpha: Alpha.badgeBackground,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.badge,
                      ),
                      border: Border.all(
                        color: context.conduitTheme.success.withValues(
                          alpha: Alpha.avatarBorder,
                        ),
                        width: BorderWidth.thin,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: context.conduitTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Text(
                          'Active',
                          style: context.conduitTheme.label?.copyWith(
                            color: context.conduitTheme.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account',
          style: context.conduitTheme.headingSmall?.copyWith(
            color: context.conduitTheme.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.md),
        ConduitCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _buildThemeToggleTile(context, ref),
              Divider(color: context.conduitTheme.dividerColor, height: 1),
              _buildAboutTile(context),
              Divider(color: context.conduitTheme.dividerColor, height: 1),
              _buildAccountOption(
                icon: UiUtils.platformIcon(
                  ios: CupertinoIcons.square_arrow_left,
                  android: Icons.logout,
                ),
                title: 'Sign Out',
                subtitle: 'End your session',
                onTap: () => _signOut(context, ref),
                isDestructive: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Builder(
      builder: (context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.listItemPadding,
          vertical: Spacing.sm,
        ),
        leading: Container(
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: isDestructive
                ? context.conduitTheme.error.withValues(alpha: Alpha.highlight)
                : context.conduitTheme.buttonPrimary.withValues(
                    alpha: Alpha.highlight,
                  ),
            borderRadius: BorderRadius.circular(AppBorderRadius.small),
          ),
          child: Icon(
            icon,
            color: isDestructive
                ? context.conduitTheme.error
                : context.conduitTheme.buttonPrimary,
            size: IconSize.medium,
          ),
        ),
        title: Text(
          title,
          style: context.conduitTheme.bodyLarge?.copyWith(
            color: isDestructive
                ? context.conduitTheme.error
                : context.conduitTheme.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: context.conduitTheme.bodySmall?.copyWith(
            color: context.conduitTheme.textSecondary,
          ),
        ),
        trailing: Icon(
          UiUtils.platformIcon(
            ios: CupertinoIcons.chevron_right,
            android: Icons.chevron_right,
          ),
          color: context.conduitTheme.iconSecondary,
          size: IconSize.small,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildThemeToggleTile(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final bool isDarkEffective =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.listItemPadding,
        vertical: Spacing.sm,
      ),
      leading: Container(
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: context.conduitTheme.buttonPrimary.withValues(
            alpha: Alpha.highlight,
          ),
          borderRadius: BorderRadius.circular(AppBorderRadius.small),
        ),
        child: Icon(
          UiUtils.platformIcon(
            ios: CupertinoIcons.moon_stars,
            android: Icons.dark_mode,
          ),
          color: context.conduitTheme.buttonPrimary,
          size: IconSize.medium,
        ),
      ),
      title: Text(
        'Dark Mode',
        style: context.conduitTheme.bodyLarge?.copyWith(
          color: context.conduitTheme.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        themeMode == ThemeMode.system
            ? 'Following system: '
                  '${platformBrightness == Brightness.dark ? 'Dark' : 'Light'}'
            : (isDarkEffective
                  ? 'Currently using Dark theme'
                  : 'Currently using Light theme'),
        style: context.conduitTheme.bodySmall?.copyWith(
          color: context.conduitTheme.textSecondary,
        ),
      ),
      trailing: Switch.adaptive(
        value: isDarkEffective,
        onChanged: (value) {
          ref
              .read(themeModeProvider.notifier)
              .setTheme(value ? ThemeMode.dark : ThemeMode.light);
        },
      ),
      onTap: () {
        final newValue = !isDarkEffective;
        ref
            .read(themeModeProvider.notifier)
            .setTheme(newValue ? ThemeMode.dark : ThemeMode.light);
      },
    );
  }

  Widget _buildAboutTile(BuildContext context) {
    return _buildAccountOption(
      icon: UiUtils.platformIcon(
        ios: CupertinoIcons.info,
        android: Icons.info_outline,
      ),
      title: 'About App',
      subtitle: 'Conduit information and links',
      onTap: () => _showAboutDialog(context),
    );
  }

  Future<void> _showAboutDialog(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      // Update dialog with dynamic version each time
      // GitHub repo URL source of truth
      const githubUrl = 'https://github.com/cogwheel0/conduit';

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: ctx.conduitTheme.surfaceBackground,
            title: Text(
              'About Conduit',
              style: ctx.conduitTheme.headingSmall?.copyWith(
                color: ctx.conduitTheme.textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version: ${info.version} (${info.buildNumber})',
                  style: ctx.conduitTheme.bodyMedium?.copyWith(
                    color: ctx.conduitTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.md),
                InkWell(
                  onTap: () => launchUrlString(
                    githubUrl,
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        UiUtils.platformIcon(
                          ios: CupertinoIcons.link,
                          android: Icons.link,
                        ),
                        size: IconSize.small,
                        color: ctx.conduitTheme.buttonPrimary,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Text(
                        'GitHub Repository',
                        style: ctx.conduitTheme.bodyMedium?.copyWith(
                          color: ctx.conduitTheme.buttonPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      UiUtils.showMessage(context, 'Unable to load app info');
    }
  }

  void _signOut(BuildContext context, WidgetRef ref) async {
    final confirm = await UiUtils.showConfirmationDialog(
      context,
      title: 'Sign out?',
      message: 'You\'ll need to sign in again to continue',
      confirmText: 'Sign out',
      isDestructive: true,
    );

    if (confirm) {
      await ref.read(logoutActionProvider);
    }
  }
}
