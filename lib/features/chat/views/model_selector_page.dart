import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../../../core/models/model.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/theme/app_theme.dart';

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
    final theme = Theme.of(context);
    final modelsAsync = ref.watch(modelsProvider);
    final selectedModel = ref.watch(selectedModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Model'),
        leading: IconButton(
          icon: Icon(Platform.isIOS ? CupertinoIcons.back : Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
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
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          'No models available',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          'Please check your Open-WebUI configuration',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
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
                              : Icons.search_off,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        const SizedBox(height: Spacing.md),
                        Text(
                          'No models found',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          'Try searching with different keywords',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
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
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
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
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Platform.isIOS
                          ? CupertinoIcons.exclamationmark_triangle
                          : Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      'Failed to load models',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      error.toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.lg),
                    ElevatedButton.icon(
                      onPressed: () => ref.refresh(modelsProvider),
                      icon: Icon(
                        Platform.isIOS ? CupertinoIcons.refresh : Icons.refresh,
                      ),
                      label: const Text('Retry'),
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
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: isSelected ? 2 : 0,
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.dividerColor.withValues(alpha: 0.3),
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: isSelected ? FontWeight.w600 : null,
                        color: isSelected ? theme.colorScheme.primary : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Platform.isIOS
                          ? CupertinoIcons.checkmark_circle_fill
                          : Icons.check_circle,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              if (model.description != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  model.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
