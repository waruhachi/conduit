import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/settings_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../tools/providers/tools_providers.dart';
import '../../../core/models/tool.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../core/providers/app_providers.dart';
import '../../../l10n/app_localizations.dart';

class AppCustomizationPage extends ConsumerWidget {
  const AppCustomizationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final bool isDarkEffective =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            platformBrightness == Brightness.dark);
    final locale = ref.watch(localeProvider);

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
          tooltip: AppLocalizations.of(context)!.back,
        ),
        title: Text(
          AppLocalizations.of(context)!.appCustomization,
          style: AppTypography.headlineSmallStyle.copyWith(
            color: context.conduitTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.display,
              style: context.conduitTheme.headingSmall?.copyWith(
                color: context.conduitTheme.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            ConduitCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Dark mode toggle
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.listItemPadding,
                      vertical: Spacing.sm,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(Spacing.sm),
                      decoration: BoxDecoration(
                        color: context.conduitTheme.buttonPrimary
                            .withValues(alpha: Alpha.highlight),
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.small),
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
                      AppLocalizations.of(context)!.darkMode,
                      style: context.conduitTheme.bodyLarge?.copyWith(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      themeMode == ThemeMode.system
                          ? AppLocalizations.of(context)!.followingSystem(
                              platformBrightness == Brightness.dark
                                  ? AppLocalizations.of(context)!.themeDark
                                  : AppLocalizations.of(context)!.themeLight,
                            )
                          : (isDarkEffective
                                ? AppLocalizations.of(context)!
                                    .currentlyUsingDarkTheme
                                : AppLocalizations.of(context)!
                                    .currentlyUsingLightTheme),
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
                          .setTheme(
                              newValue ? ThemeMode.dark : ThemeMode.light);
                    },
                  ),
                  Divider(color: context.conduitTheme.dividerColor, height: 1),

                  // App language selector
                  Builder(builder: (context) {
                    final currentCode = locale?.languageCode ?? 'system';
                    final label = () {
                      switch (currentCode) {
                        case 'en':
                          return 'English';
                        case 'de':
                          return 'Deutsch';
                        case 'fr':
                          return 'Français';
                        case 'it':
                          return 'Italiano';
                        default:
                          return 'System';
                      }
                    }();

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Spacing.listItemPadding,
                        vertical: Spacing.sm,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(Spacing.sm),
                        decoration: BoxDecoration(
                          color: context.conduitTheme.buttonPrimary
                              .withValues(alpha: Alpha.highlight),
                          borderRadius:
                              BorderRadius.circular(AppBorderRadius.small),
                        ),
                        child: Icon(
                          UiUtils.platformIcon(
                            ios: CupertinoIcons.globe,
                            android: Icons.language,
                          ),
                          color: context.conduitTheme.buttonPrimary,
                          size: IconSize.medium,
                        ),
                      ),
                      title: Text(
                        AppLocalizations.of(context)!.appLanguage,
                        style: context.conduitTheme.bodyLarge?.copyWith(
                          color: context.conduitTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        label,
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
                      onTap: () async {
                        final selected = await _showLanguageSelector(
                            context, currentCode);
                        if (selected != null) {
                          if (selected == 'system') {
                            await ref
                                .read(localeProvider.notifier)
                                .setLocale(null);
                          } else {
                            await ref
                                .read(localeProvider.notifier)
                                .setLocale(Locale(selected));
                          }
                        }
                      },
                    );
                  }),
                  Divider(color: context.conduitTheme.dividerColor, height: 1),

                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.listItemPadding,
                      vertical: Spacing.sm,
                    ),
                    // Use platform defaults for switch colors to match theme
                    value: settings.omitProviderInModelName,
                    title: Text(
                      AppLocalizations.of(context)!.hideProviderInModelNames,
                      style: context.conduitTheme.bodyLarge?.copyWith(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context)!
                          .hideProviderInModelNamesDescription,
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

            const SizedBox(height: Spacing.lg),
            // Quick pills (Web / Image Gen)
            Text(
              AppLocalizations.of(context)!.onboardQuickTitle,
              style: context.conduitTheme.headingSmall?.copyWith(
                color: context.conduitTheme.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Consumer(
              builder: (context, ref, _) {
                final selectedRaw = ref.watch(
                  appSettingsProvider.select((s) => s.quickPills),
                );
                final toolsAsync = ref.watch(toolsListProvider);
                final tools = toolsAsync.maybeWhen(
                  data: (t) => t,
                  orElse: () => const <Tool>[],
                );
                final allowed = <String>{
                  'web',
                  'image',
                  ...tools.map((t) => t.id),
                };
                // Sanitize persisted selection
                final selected =
                    selectedRaw.where((id) => allowed.contains(id)).take(2).toList();
                if (selected.length != selectedRaw.length) {
                  // Persist sanitized list asynchronously
                  Future.microtask(() => ref
                      .read(appSettingsProvider.notifier)
                      .setQuickPills(selected));
                }
                final int selectedCount = selected.length;

                void toggle(String id) async {
                  final current = List<String>.from(selected);
                  if (current.contains(id)) {
                    current.remove(id);
                  } else {
                    if (current.length >= 2) return; // enforce max 2
                    current.add(id);
                  }
                  await ref.read(appSettingsProvider.notifier).setQuickPills(current);
                }

                // Build dynamic tool chips list once
                final List<Widget> dynamicToolChips = ref
                    .watch(toolsListProvider)
                    .maybeWhen<List<Widget>>(
                      data: (tools) => tools.map((Tool t) {
                        final isSel = selected.contains(t.id);
                        final canSelect = selectedCount < 2 || isSel;
                        return ConduitChip(
                          label: t.name,
                          icon: Icons.extension,
                          isSelected: isSel,
                          onTap: canSelect ? () => toggle(t.id) : null,
                        );
                      }).toList(),
                      orElse: () => const <Widget>[],
                    );

                return ConduitCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.listItemPadding,
                    vertical: Spacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.appCustomizationSubtitle,
                              style: context.conduitTheme.bodySmall?.copyWith(
                                color: context.conduitTheme.textSecondary,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () async {
                                    await ref
                                        .read(appSettingsProvider.notifier)
                                        .setQuickPills(const []);
                                  },
                            child: Text(AppLocalizations.of(context)!.clear),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.sm),
                      Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.sm,
                        children: [
                          ConduitChip(
                            label: AppLocalizations.of(context)!.web,
                            icon: Platform.isIOS
                                ? CupertinoIcons.search
                                : Icons.search,
                            isSelected: selected.contains('web'),
                            onTap: (selectedCount < 2 || selected.contains('web'))
                                ? () => toggle('web')
                                : null,
                          ),
                          ConduitChip(
                            label: AppLocalizations.of(context)!.imageGen,
                            icon: Platform.isIOS
                                ? CupertinoIcons.photo
                                : Icons.image,
                            isSelected: selected.contains('image'),
                            onTap: (selectedCount < 2 || selected.contains('image'))
                                ? () => toggle('image')
                                : null,
                          ),
                          // Dynamic tools from server
                          ...dynamicToolChips,
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: Spacing.lg),
            // Chat input behavior
            Text(
              'Chat',
              style: context.conduitTheme.headingSmall?.copyWith(
                color: context.conduitTheme.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            ConduitCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.listItemPadding,
                      vertical: Spacing.sm,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(Spacing.sm),
                      decoration: BoxDecoration(
                        color: context.conduitTheme.buttonPrimary
                            .withValues(alpha: Alpha.highlight),
                        borderRadius: BorderRadius.circular(AppBorderRadius.small),
                      ),
                      child: Icon(
                        Platform.isIOS
                            ? CupertinoIcons.paperplane
                            : Icons.keyboard_return,
                        color: context.conduitTheme.buttonPrimary,
                        size: IconSize.medium,
                      ),
                    ),
                    title: Text(
                      'Send on Enter',
                      style: context.conduitTheme.bodyLarge?.copyWith(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Enter sends (soft keyboard). Cmd/Ctrl+Enter also available',
                      style: context.conduitTheme.bodySmall?.copyWith(
                        color: context.conduitTheme.textSecondary,
                      ),
                    ),
                    trailing: Switch.adaptive(
                      value: settings.sendOnEnter,
                      onChanged: (v) =>
                          ref.read(appSettingsProvider.notifier).setSendOnEnter(v),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Spacing.lg),
            Text(
              AppLocalizations.of(context)!.realtime,
              style: context.conduitTheme.headingSmall?.copyWith(
                color: context.conduitTheme.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            ConduitCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: Spacing.listItemPadding,
                      vertical: Spacing.sm,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(Spacing.sm),
                      decoration: BoxDecoration(
                        color: context.conduitTheme.buttonPrimary
                            .withValues(alpha: Alpha.highlight),
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.small),
                      ),
                      child: Icon(
                        Platform.isIOS
                            ? CupertinoIcons.waveform
                            : Icons.sync_alt,
                        color: context.conduitTheme.buttonPrimary,
                        size: IconSize.medium,
                      ),
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.transportMode,
                      style: context.conduitTheme.bodyLarge?.copyWith(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context)!.transportModeDescription,
                      style: context.conduitTheme.bodySmall?.copyWith(
                        color: context.conduitTheme.textSecondary,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.listItemPadding,
                      0,
                      Spacing.listItemPadding,
                      Spacing.md,
                    ),
                    child: DropdownButtonFormField<String>(
                      initialValue: settings.socketTransportMode,
                      onChanged: (v) async {
                        if (v == null) return;
                        await ref
                            .read(appSettingsProvider.notifier)
                            .setSocketTransportMode(v);
                      },
                      items: [
                        DropdownMenuItem(
                          value: 'auto',
                          child: Text(AppLocalizations.of(context)!
                              .transportModeAuto),
                        ),
                        DropdownMenuItem(
                          value: 'ws',
                          child: Text(AppLocalizations.of(context)!
                              .transportModeWs),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context)!.mode,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.listItemPadding,
                      0,
                      Spacing.listItemPadding,
                      Spacing.md,
                    ),
                    child: Text(
                      settings.socketTransportMode == 'auto'
                          ? AppLocalizations.of(context)!
                              .transportModeAutoInfo
                          : AppLocalizations.of(context)!
                              .transportModeWsInfo,
                      style: context.conduitTheme.caption?.copyWith(
                        color: context.conduitTheme.textSecondary,
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

  Future<String?> _showLanguageSelector(BuildContext context, String current) {
    return showModalBottomSheet<String>(
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
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: Spacing.sm),
              ListTile(
                title: Text(AppLocalizations.of(context)!.system),
                trailing: current == 'system' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, 'system'),
              ),
              ListTile(
                title: Text(AppLocalizations.of(context)!.english),
                trailing: current == 'en' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, 'en'),
              ),
              ListTile(
                title: Text(AppLocalizations.of(context)!.deutsch),
                trailing: current == 'de' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, 'de'),
              ),
              ListTile(
                title: Text(AppLocalizations.of(context)!.francais),
                trailing: current == 'fr' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, 'fr'),
              ),
              ListTile(
                title: Text(AppLocalizations.of(context)!.italiano),
                trailing: current == 'it' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, 'it'),
              ),
              const SizedBox(height: Spacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
