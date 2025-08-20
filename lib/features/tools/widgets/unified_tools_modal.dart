import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../../../shared/theme/theme_extensions.dart';
import '../../chat/providers/chat_providers.dart';
import '../providers/tools_providers.dart';

class UnifiedToolsModal extends ConsumerStatefulWidget {
  const UnifiedToolsModal({super.key});

  @override
  ConsumerState<UnifiedToolsModal> createState() => _UnifiedToolsModalState();
}

class _UnifiedToolsModalState extends ConsumerState<UnifiedToolsModal> {
  @override
  Widget build(BuildContext context) {
    final webSearchEnabled = ref.watch(webSearchEnabledProvider);
    final selectedToolIds = ref.watch(selectedToolIdsProvider);
    final toolsAsync = ref.watch(toolsListProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.bottomSheet),
        ),
        boxShadow: ConduitShadows.modal,
      ),
      padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.conduitTheme.textPrimary.withValues(
                alpha: Alpha.medium,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // Title
          Text(
            'Tools & Search',
            style: AppTypography.headlineSmallStyle.copyWith(
              color: context.conduitTheme.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // Web Search Toggle
          _buildWebSearchToggle(webSearchEnabled),
          const SizedBox(height: Spacing.md),

          // Tools Section
          Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Tools',
                  style: AppTypography.labelStyle.copyWith(
                    color: context.conduitTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                toolsAsync.when(
                  data: (tools) {
                    if (tools.isEmpty) {
                      return Text(
                        'No tools available',
                        style: AppTypography.bodySmallStyle.copyWith(
                          color: context.conduitTheme.textSecondary,
                        ),
                      );
                    }

                    return Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: tools.map((tool) {
                        final isSelected = selectedToolIds.contains(tool.id);
                        return FilterChip(
                          label: Text(
                            tool.name,
                            style: TextStyle(
                              color: isSelected
                                  ? context.conduitTheme.buttonPrimaryText
                                  : context.conduitTheme.textPrimary,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            HapticFeedback.lightImpact();
                            final currentIds = ref.read(
                              selectedToolIdsProvider,
                            );
                            if (selected) {
                              ref.read(selectedToolIdsProvider.notifier).state =
                                  [...currentIds, tool.id];
                            } else {
                              ref
                                  .read(selectedToolIdsProvider.notifier)
                                  .state = currentIds
                                  .where((id) => id != tool.id)
                                  .toList();
                            }
                          },
                          avatar: Icon(
                            Icons.build,
                            size: IconSize.small,
                            color: isSelected
                                ? context.conduitTheme.buttonPrimaryText
                                : context.conduitTheme.textSecondary,
                          ),
                          backgroundColor:
                              context.conduitTheme.surfaceBackground,
                          selectedColor: context.conduitTheme.buttonPrimary,
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppBorderRadius.md,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? context.conduitTheme.buttonPrimary
                                  : context.conduitTheme.cardBorder,
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (error, stack) => Text(
                    'Failed to load tools',
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: context.conduitTheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebSearchToggle(bool webSearchEnabled) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ref.read(webSearchEnabledProvider.notifier).state = !webSearchEnabled;
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: webSearchEnabled
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.cardBackground,
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: Border.all(
            color: webSearchEnabled
                ? context.conduitTheme.buttonPrimary
                : context.conduitTheme.cardBorder,
            width: BorderWidth.regular,
          ),
        ),
        child: Row(
          children: [
            Icon(
              webSearchEnabled
                  ? (Platform.isIOS ? CupertinoIcons.globe : Icons.public)
                  : (Platform.isIOS ? CupertinoIcons.search : Icons.search),
              size: IconSize.medium,
              color: webSearchEnabled
                  ? context.conduitTheme.buttonPrimaryText
                  : context.conduitTheme.textPrimary.withValues(
                      alpha: Alpha.strong,
                    ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Web Search',
                    style: AppTypography.labelStyle.copyWith(
                      color: webSearchEnabled
                          ? context.conduitTheme.buttonPrimaryText
                          : context.conduitTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    webSearchEnabled
                        ? 'I can search the internet for information'
                        : 'Enable to search the web for answers',
                    style: AppTypography.captionStyle.copyWith(
                      color: webSearchEnabled
                          ? context.conduitTheme.buttonPrimaryText.withValues(
                              alpha: Alpha.strong,
                            )
                          : context.conduitTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              webSearchEnabled ? Icons.toggle_on : Icons.toggle_off,
              size: IconSize.large,
              color: webSearchEnabled
                  ? context.conduitTheme.buttonPrimaryText
                  : context.conduitTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
