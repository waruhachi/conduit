import 'package:flutter/material.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../../../core/models/tool.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../chat/providers/chat_providers.dart';
import '../../../core/providers/app_providers.dart';
import '../providers/tools_providers.dart';
import '../../../shared/widgets/sheet_handle.dart';
import '../../chat/views/chat_page_helpers.dart';

class UnifiedToolsModal extends ConsumerStatefulWidget {
  const UnifiedToolsModal({super.key});

  @override
  ConsumerState<UnifiedToolsModal> createState() => _UnifiedToolsModalState();
}

class _UnifiedToolsModalState extends ConsumerState<UnifiedToolsModal> {
  @override
  Widget build(BuildContext context) {
    final webSearchEnabled = ref.watch(webSearchEnabledProvider);
    final imageGenEnabled = ref.watch(imageGenerationEnabledProvider);
    final imageGenAvailable = ref.watch(imageGenerationAvailableProvider);
    final selectedToolIds = ref.watch(selectedToolIdsProvider);
    final toolsAsync = ref.watch(toolsListProvider);

    final theme = context.conduitTheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.bottomSheet),
        ),
        border: Border.all(
          color: theme.dividerColor,
          width: BorderWidth.regular,
        ),
        boxShadow: ConduitShadows.modal,
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: Spacing.md),

                // Full tiles for Web and Image features
                Column(
                  children: [
                    _buildFeatureTile(
                      title: AppLocalizations.of(context)!.webSearch,
                      description: AppLocalizations.of(
                        context,
                      )!.webSearchDescription,
                      icon: Platform.isIOS
                          ? CupertinoIcons.search
                          : Icons.search,
                      isActive: webSearchEnabled,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(webSearchEnabledProvider.notifier).state =
                            !webSearchEnabled;
                      },
                    ),
                    if (imageGenAvailable)
                      _buildFeatureTile(
                        title: AppLocalizations.of(context)!.imageGeneration,
                        description: AppLocalizations.of(
                          context,
                        )!.imageGenerationDescription,
                        icon: Platform.isIOS
                            ? CupertinoIcons.photo
                            : Icons.image,
                        isActive: imageGenEnabled,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ref
                                  .read(imageGenerationEnabledProvider.notifier)
                                  .state =
                              !imageGenEnabled;
                        },
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),

                // All tools as selectable tiles (model selector style)
                toolsAsync.when(
                  data: (tools) {
                    if (tools.isEmpty) {
                      return _buildNeutralCard(
                        child: Text(
                          'No tools available',
                          style: AppTypography.bodySmallStyle.copyWith(
                            color: theme.textSecondary,
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: tools.map((tool) {
                        final isSelected = selectedToolIds.contains(tool.id);
                        return _buildToolTile(
                          tool,
                          isSelected,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            final currentIds = ref.read(
                              selectedToolIdsProvider,
                            );
                            if (isSelected) {
                              ref
                                  .read(selectedToolIdsProvider.notifier)
                                  .state = currentIds
                                  .where((id) => id != tool.id)
                                  .toList();
                            } else {
                              ref.read(selectedToolIdsProvider.notifier).state =
                                  [...currentIds, tool.id];
                            }
                          },
                        );
                      }).toList(),
                    );
                  },
                  loading: () => _buildNeutralCard(
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (error, stack) => _buildNeutralCard(
                    child: Text(
                      'Failed to load tools',
                      style: AppTypography.bodySmallStyle.copyWith(
                        color: theme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNeutralCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: context.conduitTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: context.conduitTheme.cardBorder,
          width: BorderWidth.regular,
        ),
      ),
      child: child,
    );
  }

  // Legacy header removed in simplified design

  // Removed legacy builders (kept earlier for reference)

  IconData _getToolIcon(Tool tool) {
    final toolName = tool.name.toLowerCase();

    if (toolName.contains('image') || toolName.contains('vision')) {
      return Platform.isIOS ? CupertinoIcons.photo : Icons.image;
    } else if (toolName.contains('code') || toolName.contains('python')) {
      return Platform.isIOS
          ? CupertinoIcons.chevron_left_slash_chevron_right
          : Icons.code;
    } else if (toolName.contains('calculator') || toolName.contains('math')) {
      return Icons.calculate;
    } else if (toolName.contains('file') || toolName.contains('document')) {
      return Platform.isIOS ? CupertinoIcons.doc : Icons.description;
    } else if (toolName.contains('api') || toolName.contains('request')) {
      return Platform.isIOS ? CupertinoIcons.link : Icons.api;
    } else if (toolName.contains('chart') || toolName.contains('graph')) {
      return Icons.bar_chart;
    } else if (toolName.contains('data') || toolName.contains('database')) {
      return Icons.storage;
    } else {
      return Icons.build;
    }
  }

  Widget _buildFeatureTile({
    required String title,
    required String description,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.md),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    context.conduitTheme.buttonPrimary.withValues(alpha: 0.2),
                    context.conduitTheme.buttonPrimary.withValues(alpha: 0.1),
                  ],
                )
              : null,
          color: isActive
              ? null
              : context.conduitTheme.surfaceBackground.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: Border.all(
            color: isActive
                ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.5)
                : context.conduitTheme.dividerColor,
            width: BorderWidth.regular,
          ),
          boxShadow: isActive ? ConduitShadows.card : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.conduitTheme.buttonPrimary.withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(AppBorderRadius.md),
                ),
                child: Icon(
                  icon,
                  color: context.conduitTheme.buttonPrimary,
                  size: 16,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.bodyMedium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      description,
                      style: TextStyle(
                        color: context.conduitTheme.textSecondary,
                        fontSize: AppTypography.labelSmall,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              AnimatedOpacity(
                opacity: isActive ? 1 : 0.6,
                duration: AnimationDuration.fast,
                child: Container(
                  padding: const EdgeInsets.all(Spacing.xxs),
                  decoration: BoxDecoration(
                    color: isActive
                        ? context.conduitTheme.buttonPrimary
                        : context.conduitTheme.surfaceBackground,
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    border: Border.all(
                      color: isActive
                          ? context.conduitTheme.buttonPrimary.withValues(
                              alpha: 0.6,
                            )
                          : context.conduitTheme.dividerColor,
                    ),
                  ),
                  child: Icon(
                    isActive
                        ? (Platform.isIOS
                              ? CupertinoIcons.check_mark
                              : Icons.check)
                        : (Platform.isIOS ? CupertinoIcons.add : Icons.add),
                    color: isActive
                        ? context.conduitTheme.textInverse
                        : context.conduitTheme.iconSecondary,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolTile(
    Tool tool,
    bool isSelected, {
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.md),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    context.conduitTheme.buttonPrimary.withValues(alpha: 0.2),
                    context.conduitTheme.buttonPrimary.withValues(alpha: 0.1),
                  ],
                )
              : null,
          color: isSelected
              ? null
              : context.conduitTheme.surfaceBackground.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: Border.all(
            color: isSelected
                ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.5)
                : context.conduitTheme.dividerColor,
            width: BorderWidth.regular,
          ),
          boxShadow: isSelected ? ConduitShadows.card : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.conduitTheme.buttonPrimary.withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(AppBorderRadius.md),
                ),
                child: Icon(
                  _getToolIcon(tool),
                  color: context.conduitTheme.buttonPrimary,
                  size: 16,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.name,
                      style: TextStyle(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.bodyMedium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (tool.meta?['description'] != null &&
                        (tool.meta!['description'] as String).isNotEmpty) ...[
                      const SizedBox(height: Spacing.xs),
                      Text(
                        tool.meta!['description'],
                        style: TextStyle(
                          color: context.conduitTheme.textSecondary,
                          fontSize: AppTypography.labelSmall,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              AnimatedOpacity(
                opacity: isSelected ? 1 : 0.6,
                duration: AnimationDuration.fast,
                child: Container(
                  padding: const EdgeInsets.all(Spacing.xxs),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.conduitTheme.buttonPrimary
                        : context.conduitTheme.surfaceBackground,
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    border: Border.all(
                      color: isSelected
                          ? context.conduitTheme.buttonPrimary.withValues(
                              alpha: 0.6,
                            )
                          : context.conduitTheme.dividerColor,
                    ),
                  ),
                  child: Icon(
                    isSelected
                        ? (Platform.isIOS
                              ? CupertinoIcons.check_mark
                              : Icons.check)
                        : (Platform.isIOS ? CupertinoIcons.add : Icons.add),
                    color: isSelected
                        ? context.conduitTheme.textInverse
                        : context.conduitTheme.iconSecondary,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Removed small pill builder; using full tiles for consistency
}
