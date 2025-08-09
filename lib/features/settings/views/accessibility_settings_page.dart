import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/conduit_components.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/services/enhanced_accessibility_service.dart';
import '../../../core/services/platform_service.dart';

/// Accessibility settings page with WCAG 2.2 AA compliance controls
class AccessibilitySettingsPage extends ConsumerWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      backgroundColor: context.conduitTheme.surfaceBackground,
      appBar: PlatformService.createPlatformAppBar(
        title: 'Accessibility',
        backgroundColor: context.conduitTheme.surfaceBackground,
        foregroundColor: context.conduitTheme.textPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Motion & Animation'),
            const SizedBox(height: Spacing.sm),

            // Reduce Motion Toggle
            ConduitCard(
              child: EnhancedAccessibilityService.createAccessibleSwitch(
                value: settings.reduceMotion,
                onChanged: (value) {
                  ref.read(appSettingsProvider.notifier).setReduceMotion(value);
                  EnhancedAccessibilityService.announceSuccess(
                    value
                        ? 'Reduced motion enabled'
                        : 'Reduced motion disabled',
                  );
                },
                label: 'Reduce Motion',
                description:
                    'Minimize animations and transitions for better focus and reduced vestibular disturbance',
              ),
            ),

            const SizedBox(height: Spacing.sm),

            // Animation Speed Slider
            if (!settings.reduceMotion) ...[
              ConduitCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Animation Speed',
                      style: TextStyle(
                        color: context.conduitTheme.textPrimary,
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Adjust the speed of animations and transitions',
                      style: TextStyle(
                        color: context.conduitTheme.textSecondary,
                        fontSize: AppTypography.labelLarge,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    EnhancedAccessibilityService.createAccessibleSlider(
                      value: settings.animationSpeed,
                      onChanged: (value) {
                        ref
                            .read(appSettingsProvider.notifier)
                            .setAnimationSpeed(value);
                      },
                      label: 'Animation speed',
                      min: 0.5,
                      max: 2.0,
                      divisions: 6,
                      valueFormatter: (value) {
                        if (value < 0.75) return 'Slow';
                        if (value < 1.25) return 'Normal';
                        return 'Fast';
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
            ],

            const SizedBox(height: Spacing.lg),
            _buildSectionHeader(context, 'Visual & Text'),
            const SizedBox(height: Spacing.sm),

            // Large Text Toggle
            ConduitCard(
              child: EnhancedAccessibilityService.createAccessibleSwitch(
                value: settings.largeText,
                onChanged: (value) {
                  ref.read(appSettingsProvider.notifier).setLargeText(value);
                  EnhancedAccessibilityService.announceSuccess(
                    value ? 'Large text enabled' : 'Large text disabled',
                  );
                },
                label: 'Large Text',
                description:
                    'Increase text size throughout the app for better readability',
              ),
            ),

            const SizedBox(height: Spacing.sm),

            // High Contrast Toggle
            ConduitCard(
              child: EnhancedAccessibilityService.createAccessibleSwitch(
                value: settings.highContrast,
                onChanged: (value) {
                  ref.read(appSettingsProvider.notifier).setHighContrast(value);
                  EnhancedAccessibilityService.announceSuccess(
                    value ? 'High contrast enabled' : 'High contrast disabled',
                  );
                },
                label: 'High Contrast',
                description:
                    'Increase contrast between text and background colors',
              ),
            ),

            const SizedBox(height: Spacing.lg),
            _buildSectionHeader(context, 'Interaction'),
            const SizedBox(height: Spacing.sm),

            // Haptic Feedback Toggle
            ConduitCard(
              child: EnhancedAccessibilityService.createAccessibleSwitch(
                value: settings.hapticFeedback,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setHapticFeedback(value);
                  if (value) {
                    PlatformService.hapticFeedback(type: HapticType.success);
                  }
                  EnhancedAccessibilityService.announceSuccess(
                    value
                        ? 'Haptic feedback enabled'
                        : 'Haptic feedback disabled',
                  );
                },
                label: 'Haptic Feedback',
                description:
                    'Feel vibrations when interacting with buttons and controls',
              ),
            ),

            const SizedBox(height: Spacing.lg),
            _buildSectionHeader(context, 'System Integration'),
            const SizedBox(height: Spacing.sm),

            // System Settings Info Card
            ConduitCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: context.conduitTheme.buttonPrimary,
                        size: IconSize.md,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Text(
                        'System Settings',
                        style: TextStyle(
                          color: context.conduitTheme.textPrimary,
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Conduit automatically respects your device\'s accessibility settings, including:',
                    style: TextStyle(
                      color: context.conduitTheme.textSecondary,
                      fontSize: AppTypography.labelLarge,
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  ...[
                    '• Reduce Motion (iOS/Android)',
                    '• VoiceOver/TalkBack screen readers',
                    '• Dynamic Type/Font scale',
                    '• Color inversion and filters',
                  ].map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        item,
                        style: TextStyle(
                          color: context.conduitTheme.textSecondary,
                          fontSize: AppTypography.labelLarge,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Spacing.lg),

            // Reset to Defaults Button
            ConduitButton(
              text: 'Reset to Defaults',
              onPressed: () => _showResetDialog(context, ref),
              isSecondary: true,
              width: double.infinity,
            ),

            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return EnhancedAccessibilityService.createAccessibleText(
      title,
      style: TextStyle(
        color: context.conduitTheme.buttonPrimary,
        fontSize: AppTypography.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      isHeader: true,
    );
  }

  Future<void> _showResetDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await PlatformService.showPlatformAlert(
      context: context,
      title: 'Reset Accessibility Settings',
      content:
          'This will reset all accessibility preferences to their default values. Are you sure?',
      confirmText: 'Reset',
      cancelText: 'Cancel',
      isDestructive: true,
    );

    if (confirmed == true) {
      await ref.read(appSettingsProvider.notifier).resetToDefaults();
      EnhancedAccessibilityService.announceSuccess(
        'Accessibility settings reset to defaults',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Accessibility settings reset to defaults'),
            backgroundColor: context.conduitTheme.buttonPrimary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
