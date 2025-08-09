import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/loading_states.dart';
import '../../../shared/widgets/empty_states.dart';

import '../../../shared/utils/platform_utils.dart';
import '../services/conversation_search_service.dart';
import '../../../core/providers/app_providers.dart';

/// Advanced conversation search widget with filters and results
class ConversationSearchWidget extends ConsumerStatefulWidget {
  final Function(String conversationId, String? messageId)? onResultTap;
  final bool showFilters;

  const ConversationSearchWidget({
    super.key,
    this.onResultTap,
    this.showFilters = true,
  });

  @override
  ConsumerState<ConversationSearchWidget> createState() =>
      _ConversationSearchWidgetState();
}

class _ConversationSearchWidgetState
    extends ConsumerState<ConversationSearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _isSearching = false;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    ref.read(searchQueryProvider.notifier).state = query;

    if (query.isNotEmpty) {
      _performSearch(query);
    } else {
      ref.read(conversationSearchResultsProvider.notifier).state = null;
    }
  }

  Future<void> _performSearch(String query) async {
    if (_isSearching) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final searchService = ref.read(conversationSearchServiceProvider);
      final conversations = ref
          .read(conversationsProvider)
          .when(
            data: (data) => data,
            loading: () => <dynamic>[],
            error: (_, _) => <dynamic>[],
          );

      final options = ref.read(searchOptionsProvider);

      final results = await searchService.searchConversations(
        conversations: conversations.cast(),
        query: query,
        options: options,
      );

      ref.read(conversationSearchResultsProvider.notifier).state = results;
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conduitTheme = context.conduitTheme;
    final searchResults = ref.watch(conversationSearchResultsProvider);

    return Column(
      children: [
        // Search header
        Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: conduitTheme.cardBackground,
            border: Border(
              bottom: BorderSide(
                color: conduitTheme.cardBorder,
                width: BorderWidth.regular,
              ),
            ),
          ),
          child: Column(
            children: [
              // Search input
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: conduitTheme.inputBackground,
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                        border: Border.all(
                          color: _searchFocus.hasFocus
                              ? conduitTheme.inputBorderFocused
                              : conduitTheme.inputBorder,
                          width: BorderWidth.regular,
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        decoration: InputDecoration(
                          hintText: 'Search conversations...',
                          hintStyle: TextStyle(
                            color: context.conduitTheme.inputPlaceholder,
                            fontSize: AppTypography.bodyLarge,
                          ),
                          prefixIcon: Icon(
                            Platform.isIOS
                                ? CupertinoIcons.search
                                : Icons.search,
                            color: context.conduitTheme.iconSecondary,
                            size: AppTypography.headlineMedium,
                          ),
                          suffixIcon: _isSearching
                              ? Padding(
                                  padding: const EdgeInsets.all(Spacing.md),
                                  child: ConduitLoading.inline(
                                    size: Spacing.md,
                                  ),
                                )
                              : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Platform.isIOS
                                        ? CupertinoIcons.clear
                                        : Icons.clear,
                                    color: context.conduitTheme.iconSecondary,
                                    size: AppTypography.headlineMedium,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchFocus.unfocus();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md,
                            vertical: Spacing.xs,
                          ),
                        ),
                        style: TextStyle(
                          color: context.conduitTheme.inputText,
                          fontSize: AppTypography.bodyLarge,
                        ),
                        onSubmitted: (_) => _searchFocus.unfocus(),
                      ),
                    ),
                  ),

                  // Filter toggle
                  if (widget.showFilters) ...[
                    const SizedBox(width: Spacing.xs),
                    GestureDetector(
                      onTap: () {
                        PlatformUtils.lightHaptic();
                        setState(() {
                          _showFilters = !_showFilters;
                        });
                      },
                      child: Container(
                        width: Spacing.xxl + Spacing.xs,
                        height: Spacing.xxl + Spacing.xs,
                        decoration: BoxDecoration(
                          color: _showFilters
                              ? AppTheme.neutral50.withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            AppBorderRadius.md,
                          ),
                          border: Border.all(
                            color: _showFilters
                                ? AppTheme.neutral50.withValues(alpha: 0.3)
                                : conduitTheme.inputBorder,
                            width: BorderWidth.regular,
                          ),
                        ),
                        child: Icon(
                          Platform.isIOS
                              ? CupertinoIcons.slider_horizontal_3
                              : Icons.tune,
                          color: AppTheme.neutral50.withValues(alpha: 0.8),
                          size: AppTypography.headlineMedium,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Search filters
              if (_showFilters && widget.showFilters)
                _buildSearchFilters(conduitTheme),
            ],
          ),
        ),

        // Search results
        Expanded(child: _buildSearchResults(conduitTheme, searchResults)),
      ],
    );
  }

  Widget _buildSearchFilters(ConduitThemeExtension theme) {
    final options = ref.watch(searchOptionsProvider);

    return Container(
      margin: const EdgeInsets.only(top: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppTheme.neutral50.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(color: theme.cardBorder, width: BorderWidth.regular),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search in:',
            style: theme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.neutral50.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: Spacing.xs),

          // Search scope toggles
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.sm,
            children: [
              _buildFilterToggle(
                'Titles',
                options.searchTitles,
                (value) =>
                    _updateSearchOptions(options.copyWith(searchTitles: value)),
              ),
              _buildFilterToggle(
                'Messages',
                options.searchMessages,
                (value) => _updateSearchOptions(
                  options.copyWith(searchMessages: value),
                ),
              ),
              _buildFilterToggle(
                'Tags',
                options.searchTags,
                (value) =>
                    _updateSearchOptions(options.copyWith(searchTags: value)),
              ),
            ],
          ),

          const SizedBox(height: Spacing.md),

          Text(
            'Message type:',
            style: theme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.neutral50.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: Spacing.xs),

          // Role filter
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.sm,
            children: [
              _buildFilterChip(
                'All',
                options.roleFilter == null,
                () => _updateSearchOptions(options.copyWith(roleFilter: null)),
              ),
              _buildFilterChip(
                'My messages',
                options.roleFilter == 'user',
                () =>
                    _updateSearchOptions(options.copyWith(roleFilter: 'user')),
              ),
              _buildFilterChip(
                'AI messages',
                options.roleFilter == 'assistant',
                () => _updateSearchOptions(
                  options.copyWith(roleFilter: 'assistant'),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().slideY(
      begin: -0.5,
      end: 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Widget _buildFilterToggle(
    String label,
    bool value,
    Function(bool) onChanged,
  ) {
    return GestureDetector(
      onTap: () {
        PlatformUtils.selectionHaptic();
        onChanged(!value);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppTypography.headlineMedium,
            height: AppTypography.headlineMedium,
            decoration: BoxDecoration(
              color: value ? AppTheme.brandPrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(AppBorderRadius.xs),
              border: Border.all(
                color: value
                    ? AppTheme.brandPrimary
                    : AppTheme.neutral50.withValues(alpha: 0.3),
                width: BorderWidth.regular,
              ),
            ),
            child: value
                ? const Icon(
                    Icons.check,
                    color: AppTheme.neutral50,
                    size: AppTypography.labelLarge,
                  )
                : null,
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.neutral50.withValues(alpha: 0.8),
              fontSize: AppTypography.labelLarge,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        PlatformUtils.selectionHaptic();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xs,
          vertical: Spacing.xs + Spacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.brandPrimary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          border: Border.all(
            color: isActive
                ? AppTheme.brandPrimary
                : AppTheme.neutral50.withValues(alpha: 0.3),
            width: BorderWidth.regular,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? AppTheme.brandPrimary
                : AppTheme.neutral50.withValues(alpha: 0.8),
            fontSize: AppTypography.labelMedium,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _updateSearchOptions(ConversationSearchOptions newOptions) {
    ref.read(searchOptionsProvider.notifier).state = newOptions;

    // Re-search with new options if we have a query
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _performSearch(query);
    }
  }

  Widget _buildSearchResults(
    ConduitThemeExtension theme,
    ConversationSearchResults? results,
  ) {
    if (_searchController.text.trim().isEmpty) {
      return _buildSearchPrompt(theme);
    }

    if (results == null) {
      return Center(child: ConduitLoading.primary());
    }

    if (results.isEmpty) {
      return SearchEmptyState(
        query: results.query,
        onClearSearch: () {
          _searchController.clear();
          _searchFocus.unfocus();
        },
      );
    }

    return Column(
      children: [
        // Results header
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppTheme.neutral50.withValues(alpha: 0.05),
            border: Border(
              bottom: BorderSide(
                color: theme.cardBorder,
                width: BorderWidth.regular,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                '${results.length} of ${results.totalMatches} results',
                style: theme.bodySmall?.copyWith(
                  color: AppTheme.neutral50.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                '${results.searchDuration.inMilliseconds}ms',
                style: theme.bodySmall?.copyWith(
                  color: AppTheme.neutral50.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),

        // Results list
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final match = results.results[index];
              return _buildSearchResultItem(theme, match, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchPrompt(ConduitThemeExtension theme) {
    return ConduitEmptyState(
      title: 'Search your conversations',
      subtitle: 'Find messages, titles, and tags across all your conversations',
      icon: Platform.isIOS ? CupertinoIcons.search : Icons.search,
    );
  }

  Widget _buildSearchResultItem(
    ConduitThemeExtension theme,
    ConversationSearchMatch match,
    int index,
  ) {
    return GestureDetector(
          onTap: () {
            PlatformUtils.lightHaptic();
            widget.onResultTap?.call(match.conversationId, match.messageId);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.xs,
            ),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: theme.cardBackground,
              borderRadius: BorderRadius.circular(AppBorderRadius.md),
              border: Border.all(
                color: theme.cardBorder,
                width: BorderWidth.regular,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with conversation title and match type
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        match.conversationTitle,
                        style: theme.headingSmall?.copyWith(
                          fontSize: AppTypography.bodyLarge,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    _buildMatchTypeBadge(match.matchType),
                  ],
                ),

                const SizedBox(height: Spacing.sm),

                // Snippet with highlighted text
                _buildHighlightedSnippet(theme, match.highlightedSnippet),

                const SizedBox(height: Spacing.sm),

                // Footer with metadata
                Row(
                  children: [
                    if (match.messageRole != null) ...[
                      _buildRoleBadge(match.messageRole!),
                      const SizedBox(width: Spacing.sm),
                    ],
                    Text(
                      _formatTimestamp(match.timestamp),
                      style: theme.caption,
                    ),
                    const Spacer(),
                    Text(
                      '${match.relevanceScore.round()}% match',
                      style: theme.caption?.copyWith(
                        color: AppTheme.brandPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        .animate(delay: Duration(milliseconds: index * 50))
        .fadeIn(duration: const Duration(milliseconds: 200))
        .slideX(begin: 0.3, end: 0);
  }

  Widget _buildMatchTypeBadge(SearchMatchType type) {
    Color color;
    String label;

    switch (type) {
      case SearchMatchType.title:
        color = AppTheme.info;
        label = 'Title';
        break;
      case SearchMatchType.message:
        color = AppTheme.success;
        label = 'Message';
        break;
      case SearchMatchType.tag:
        color = AppTheme.warning;
        label = 'Tag';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    Color color;
    String label;

    switch (role) {
      case 'user':
        color = AppTheme.brandPrimary;
        label = 'You';
        break;
      case 'assistant':
        color = AppTheme.success;
        label = 'AI';
        break;
      case 'system':
        color = AppTheme.warning;
        label = 'System';
        break;
      default:
        color = AppTheme.neutral400;
        label = role;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.xs + Spacing.xxs,
        vertical: Spacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppBorderRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildHighlightedSnippet(
    ConduitThemeExtension theme,
    String highlightedText,
  ) {
    // Simple implementation - in a real app you'd want proper HTML parsing
    final parts = highlightedText.split('<mark>');
    final spans = <InlineSpan>[];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i == 0) {
        spans.add(TextSpan(text: part));
      } else {
        final markParts = part.split('</mark>');
        if (markParts.length >= 2) {
          // Highlighted part
          spans.add(
            TextSpan(
              text: markParts[0],
              style: TextStyle(
                backgroundColor: AppTheme.brandPrimary.withValues(alpha: 0.3),
                color: AppTheme.neutral50,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          // Rest of the text
          spans.add(TextSpan(text: markParts.sublist(1).join('</mark>')));
        } else {
          spans.add(TextSpan(text: part));
        }
      }
    }

    return RichText(
      text: TextSpan(
        style: theme.bodyMedium?.copyWith(
          color: AppTheme.neutral50.withValues(alpha: 0.8),
          height: 1.4,
        ),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inDays > 7) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
