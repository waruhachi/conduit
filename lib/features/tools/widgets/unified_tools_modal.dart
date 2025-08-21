import 'package:flutter/material.dart';
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
        border: Border.all(color: theme.dividerColor, width: BorderWidth.regular),
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
                // Handle bar (standardized)
                const SheetHandle(),
                const SizedBox(height: Spacing.md),

                // Removed header for minimal, focused layout

                // Web Search Toggle
                _buildWebSearchToggle(webSearchEnabled),
                const SizedBox(height: Spacing.md),

                // Image Generation Toggle (conditionally shown)
                if (imageGenAvailable) ...[
                  _buildImageGenerationToggle(imageGenEnabled),
                  const SizedBox(height: Spacing.md),
                ],

                // Tools Section
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('Available Tools', tools.length),
                        const SizedBox(height: Spacing.sm),
                        ...tools.map(
                          (tool) => Padding(
                            padding: const EdgeInsets.only(bottom: Spacing.sm),
                            child: _buildToolCard(
                              tool,
                              selectedToolIds.contains(tool.id),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildSectionHeader(String title, int count) {
    final theme = context.conduitTheme;
    return Row(
      children: [
        Text(
          title,
          style: AppTypography.bodySmallStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.surfaceBackground.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppBorderRadius.xs),
            border: Border.all(color: theme.dividerColor, width: BorderWidth.thin),
          ),
          child: Text(
            '$count',
            style: AppTypography.bodySmallStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebSearchToggle(bool webSearchEnabled) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        side: BorderSide(
          color: webSearchEnabled
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.cardBorder,
          width: BorderWidth.regular,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
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
      ),
    );
  }

  Widget _buildImageGenerationToggle(bool imageGenEnabled) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        side: BorderSide(
          color: imageGenEnabled
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.cardBorder,
          width: BorderWidth.regular,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        onTap: () {
          HapticFeedback.lightImpact();
          ref.read(imageGenerationEnabledProvider.notifier).state =
              !imageGenEnabled;
        },
        child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: imageGenEnabled
                ? context.conduitTheme.buttonPrimary
                : context.conduitTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
        child: Row(
          children: [
            Icon(
              Platform.isIOS ? CupertinoIcons.photo : Icons.image,
              size: IconSize.medium,
              color: imageGenEnabled
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
                    'Image Generation',
                    style: AppTypography.labelStyle.copyWith(
                      color: imageGenEnabled
                          ? context.conduitTheme.buttonPrimaryText
                          : context.conduitTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    imageGenEnabled
                        ? 'I can generate images from your prompt'
                        : 'Enable to generate images with your request',
                    style: AppTypography.captionStyle.copyWith(
                      color: imageGenEnabled
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
              imageGenEnabled ? Icons.toggle_on : Icons.toggle_off,
              size: IconSize.large,
              color: imageGenEnabled
                  ? context.conduitTheme.buttonPrimaryText
                  : context.conduitTheme.textSecondary,
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildToolCard(Tool tool, bool isSelected) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        side: BorderSide(
          color: isSelected
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.cardBorder,
          width: BorderWidth.regular,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        onTap: () {
          HapticFeedback.lightImpact();
          final currentIds = ref.read(selectedToolIdsProvider);
          if (isSelected) {
            ref.read(selectedToolIdsProvider.notifier).state = currentIds
                .where((id) => id != tool.id)
                .toList();
          } else {
            ref.read(selectedToolIdsProvider.notifier).state = [
              ...currentIds,
              tool.id,
            ];
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: isSelected
                ? context.conduitTheme.buttonPrimary
                : context.conduitTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
          child: Row(
          children: [
            Icon(
              _getToolIcon(tool),
              size: IconSize.medium,
              color: isSelected
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
                    tool.name,
                    style: AppTypography.labelStyle.copyWith(
                      color: isSelected
                          ? context.conduitTheme.buttonPrimaryText
                          : context.conduitTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (tool.meta?['description'] != null &&
                      tool.meta!['description'].toString().isNotEmpty)
                    Text(
                      tool.meta!['description'].toString(),
                      style: AppTypography.captionStyle.copyWith(
                        color: isSelected
                            ? context.conduitTheme.buttonPrimaryText.withValues(
                                alpha: Alpha.strong,
                              )
                            : context.conduitTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.toggle_on : Icons.toggle_off,
              size: IconSize.large,
              color: isSelected
                  ? context.conduitTheme.buttonPrimaryText
                  : context.conduitTheme.textSecondary,
            ),
          ],
          ),
        ),
      ),
    );
  }

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
}
