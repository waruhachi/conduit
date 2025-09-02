import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/utils/ui_utils.dart';

class AppCustomizationPage extends ConsumerWidget {
  const AppCustomizationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      backgroundColor: context.conduitTheme.surfaceBackground,
      appBar: AppBar(
        backgroundColor: context.conduitTheme.surfaceBackground,
        elevation: Elevation.none,
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
          'App Customization',
          style: AppTypography.headlineSmallStyle.copyWith(
            color: context.conduitTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Display',
              style: context.conduitTheme.headingSmall?.copyWith(
                color: context.conduitTheme.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            ConduitCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.listItemPadding,
                      vertical: Spacing.sm,
                    ),
                    // Use platform defaults for switch colors to match theme
                    value: settings.omitProviderInModelName,
                    title: Text(
                      'Hide provider in model names',
                      style: context.conduitTheme.bodyLarge?.copyWith(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Show names like "gpt-4o" instead of "openai/gpt-4o".',
                      style: context.conduitTheme.bodySmall?.copyWith(
                        color: context.conduitTheme.textSecondary,
                      ),
                    ),
                    onChanged: (v) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setOmitProviderInModelName(v);
                    },
                    secondary: Container(
                      padding: const EdgeInsets.all(Spacing.sm),
                      decoration: BoxDecoration(
                        color: context.conduitTheme.buttonPrimary
                            .withValues(alpha: Alpha.highlight),
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.small),
                      ),
                      child: Icon(
                        Platform.isIOS
                            ? CupertinoIcons.textformat
                            : Icons.text_fields,
                        color: context.conduitTheme.buttonPrimary,
                        size: IconSize.medium,
                      ),
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
}
