import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../../../core/models/model.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/conduit_components.dart';

class ModelSelectorPage extends ConsumerStatefulWidget {
  const ModelSelectorPage({super.key});

  @override
  ConsumerState<ModelSelectorPage> createState() => _ModelSelectorPageState();
}

class _ModelSelectorPageState extends ConsumerState<ModelSelectorPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  List<Model> _filterModels(List<Model> models) {
    if (_searchQuery.isEmpty) {
      return models;
    }

    final query = _searchQuery.toLowerCase();
    return models.where((model) {
      return model.name.toLowerCase().contains(query) ||
          (model.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(modelsProvider);
    final selectedModel = ref.watch(selectedModelProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.conduitTheme.surfaceBackground,
        elevation: Elevation.none,
        scrolledUnderElevation: Elevation.none,
        leading: ConduitIconButton(
          icon: Platform.isIOS
              ? CupertinoIcons.back
              : Icons.arrow_back_rounded,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Model',
          style: AppTypography.headlineMediumStyle.copyWith(
            color: context.conduitTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: context.conduitTheme.surfaceBackground,
              border: Border(
                bottom: BorderSide(
                  color: context.conduitTheme.dividerColor.withValues(alpha: 0.1),
                  width: BorderWidth.regular,
                ),
              ),
            ),
            child: _buildSearchField(),
          ),
          // Models list
          Expanded(
            child: modelsAsync.when(
              data: (models) {
                final filteredModels = _filterModels(models);

                if (models.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Platform.isIOS
                              ? CupertinoIcons.cube_box
                              : Icons.view_in_ar,
                          size: IconSize.xxl,
                          color: context.conduitTheme.iconSecondary,
                        ),
                        const SizedBox(height: Spacing.lg),
                        Text(
                          'No models available',
                          style: AppTypography.headlineSmallStyle.copyWith(
                            color: context.conduitTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          'Please check your Open-WebUI configuration',
                          style: AppTypography.bodyMediumStyle.copyWith(
                            color: context.conduitTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (filteredModels.isEmpty && _searchQuery.isNotEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Platform.isIOS
                              ? CupertinoIcons.search
                              : Icons.search_rounded,
                          size: IconSize.xxl,
                          color: context.conduitTheme.iconSecondary,
                        ),
                        const SizedBox(height: Spacing.lg),
                        Text(
                          'No models found',
                          style: AppTypography.headlineSmallStyle.copyWith(
                            color: context.conduitTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          'Try searching with different keywords',
                          style: AppTypography.bodyMediumStyle.copyWith(
                            color: context.conduitTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Group models by category if needed
                final groupedModels = _groupModels(filteredModels);

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: groupedModels.length,
                  itemBuilder: (context, index) {
                    final group = groupedModels[index];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (group.title != null) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Spacing.md,
                              Spacing.md,
                              Spacing.md,
                              Spacing.sm,
                            ),
                            child: Text(
                              group.title!,
                              style: AppTypography.labelStyle.copyWith(
                                color: context.conduitTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                        ...group.models.map(
                          (model) => ModelTile(
                            model: model,
                            isSelected: selectedModel?.id == model.id,
                            onTap: () {
                              ref.read(selectedModelProvider.notifier).state =
                                  model;
                              ref.read(isManualModelSelectionProvider.notifier).state = true;
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    context.conduitTheme.buttonPrimary,
                  ),
                ),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Platform.isIOS
                          ? CupertinoIcons.exclamationmark_triangle
                          : Icons.error_rounded,
                      size: IconSize.xxl,
                      color: context.conduitTheme.error,
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(
                      'Failed to load models',
                      style: AppTypography.headlineSmallStyle.copyWith(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Please try again later',
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: context.conduitTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.xl),
                    ElevatedButton(
                      onPressed: () => ref.refresh(modelsProvider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.conduitTheme.buttonPrimary,
                        foregroundColor: context.conduitTheme.buttonPrimaryText,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.buttonPadding,
                          vertical: Spacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppBorderRadius.button),
                        ),
                        elevation: Elevation.none,
                      ),
                      child: Text(
                        'Retry',
                        style: AppTypography.labelStyle.copyWith(
                          color: context.conduitTheme.buttonPrimaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.conduitTheme.inputBackground.withValues(alpha: 0.6),
            context.conduitTheme.inputBackground.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        border: Border.all(
          color: context.conduitTheme.inputBorder.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: TextStyle(
          color: context.conduitTheme.inputText,
          fontSize: AppTypography.bodyMedium,
        ),
        decoration: InputDecoration(
          hintText: 'Search models...',
          hintStyle: TextStyle(
            color: context.conduitTheme.inputPlaceholder.withValues(alpha: 0.8),
            fontSize: AppTypography.bodyMedium,
          ),
          prefixIcon: Icon(
            Platform.isIOS ? CupertinoIcons.search : Icons.search,
            color: context.conduitTheme.iconSecondary,
            size: IconSize.md,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.clear_circled_solid
                        : Icons.clear,
                    color: context.conduitTheme.iconSecondary,
                    size: IconSize.md,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  List<ModelGroup> _groupModels(List<Model> models) {
    // For now, just return all models in one group
    // In the future, we can group by provider, capability, etc.
    return [ModelGroup(title: null, models: models)];
  }
}

class ModelGroup {
  final String? title;
  final List<Model> models;

  ModelGroup({required this.title, required this.models});
}

class ModelTile extends StatelessWidget {
  final Model model;
  final bool isSelected;
  final VoidCallback onTap;

  const ModelTile({
    super.key,
    required this.model,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: isSelected ? 2 : 0,
      color: isSelected
          ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.1)
          : context.conduitTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        side: BorderSide(
          color: isSelected
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.dividerColor.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.name,
                      style: AppTypography.bodyLargeStyle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected 
                            ? context.conduitTheme.buttonPrimary 
                            : context.conduitTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Platform.isIOS
                          ? CupertinoIcons.checkmark_circle_fill
                          : Icons.check_circle,
                      color: context.conduitTheme.buttonPrimary,
                    ),
                ],
              ),
              if (model.description != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  model.description!,
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: context.conduitTheme.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: Spacing.sm),
              Wrap(
                spacing: 8,
                children: [
                  if (model.isMultimodal)
                    _buildCapabilityChip(
                      context,
                      icon: Platform.isIOS ? CupertinoIcons.photo : Icons.image,
                      label: 'Multimodal',
                      color: AppTheme.info,
                    ),
                  if (model.supportsStreaming)
                    _buildCapabilityChip(
                      context,
                      icon: Platform.isIOS
                          ? CupertinoIcons.bolt
                          : Icons.flash_on,
                      label: 'Streaming',
                      color: AppTheme.warning,
                    ),
                  if (model.supportsRAG)
                    _buildCapabilityChip(
                      context,
                      icon: Platform.isIOS
                          ? CupertinoIcons.doc_text
                          : Icons.description,
                      label: 'RAG',
                      color: AppTheme.success,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: Spacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.labelMedium,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
