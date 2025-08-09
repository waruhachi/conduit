import 'package:flutter/material.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../core/services/focus_management_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../shared/widgets/loading_states.dart';
import 'dart:async';
import 'dart:io' show Platform;

import '../../../core/providers/app_providers.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../chat/providers/chat_providers.dart';
import '../../chat/widgets/folder_management_dialog.dart';

/// Optimized conversation list page with Conduit design aesthetics
class ChatsListPage extends ConsumerStatefulWidget {
  final bool isOverlay;

  const ChatsListPage({super.key, this.isOverlay = false});

  @override
  ConsumerState<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends ConsumerState<ChatsListPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  final ScrollController _scrollController = ScrollController();

  // Debounce search to improve performance
  String _searchQuery = '';
  Timer? _debounceTimer;
  bool _isLoadingConversation = false;
  bool _hasAddedFocusListener = false;

  // Provider for archived section visibility
  static final _showArchivedProvider = StateProvider<bool>((ref) => false);

  @override
  bool get wantKeepAlive => true; // Keep state alive for better performance

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusManagementService.registerFocusNode(
      'chats_list_search',
      debugLabel: 'Chats List Search',
    );
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    FocusManagementService.disposeFocusNode('chats_list_search');
    super.dispose();
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();

    // Set new timer for debounced search
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
        ref.read(searchQueryProvider.notifier).state = _searchQuery;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return ErrorBoundary(
      child: Scaffold(
        backgroundColor: context.conduitTheme.surfaceBackground,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _wrapWithRefresh(_buildConversationsList())),
            _buildBottomActions(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _startNewChat,
          backgroundColor: context.conduitTheme.buttonPrimary,
          foregroundColor: context.conduitTheme.buttonPrimaryText,
          elevation: Elevation.medium,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.floatingButton),
          ),
          child: Icon(
            Platform.isIOS ? CupertinoIcons.plus : Icons.add_rounded,
            size: IconSize.large,
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.conduitTheme.surfaceBackground,
      elevation: Elevation.none,
      scrolledUnderElevation: Elevation.none,
      leading: widget.isOverlay
          ? ConduitIconButton(
              icon: Platform.isIOS ? CupertinoIcons.xmark : Icons.close_rounded,
              onPressed: () => Navigator.pop(context),
            )
          : ConduitIconButton(
              icon: Platform.isIOS
                  ? CupertinoIcons.back
                  : Icons.arrow_back_rounded,
              onPressed: () => Navigator.pop(context),
            ),
      title: Text(
        'Chats',
        style: AppTypography.headlineMediumStyle.copyWith(
          color: context.conduitTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        ConduitIconButton(
          icon: Platform.isIOS
              ? CupertinoIcons.ellipsis
              : Icons.more_vert_rounded,
          onPressed: _showOptions,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    // Listen to focus changes and update UI
    final isFocused = _searchFocusNode.hasFocus;

    // Attach listener only once
    if (!_hasAddedFocusListener) {
      _searchFocusNode.addListener(() {
        setState(() {});
      });
      _hasAddedFocusListener = true;
    }

    return GestureDetector(
      onTap: () {
        // Focus the search field when the container is tapped
        _searchFocusNode.requestFocus();
      },
      child: Container(
        margin: const EdgeInsets.all(Spacing.pagePadding),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.inputPadding,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.conduitTheme.inputBackground,
          borderRadius: BorderRadius.circular(AppBorderRadius.input),
          border: Border.all(
            color: isFocused
                ? context.conduitTheme.buttonPrimary
                : context.conduitTheme.inputBorder,
            width: BorderWidth.regular,
          ),
          boxShadow: ConduitShadows.input,
        ),
        child: Row(
          children: [
            Icon(
              Platform.isIOS ? CupertinoIcons.search : Icons.search_rounded,
              size: IconSize.medium,
              color: context.conduitTheme.iconSecondary,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: context.conduitTheme.inputText,
                ),
                decoration: InputDecoration(
                  hintText: 'Search conversations...',
                  hintStyle: AppTypography.bodyMediumStyle.copyWith(
                    color: context.conduitTheme.inputPlaceholder,
                  ),
                  border: InputBorder.none, // Remove default border
                  focusedBorder:
                      InputBorder.none, // Remove default focus border
                  enabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              ConduitIconButton(
                icon: Platform.isIOS
                    ? CupertinoIcons.clear
                    : Icons.clear_rounded,
                onPressed: () {
                  _searchController.clear();
                  _searchQuery = '';
                  ref.read(searchQueryProvider.notifier).state = '';
                },
              ),
          ],
        ),
      ),
    ).animate().fadeIn(
      duration: AnimationDuration.microInteraction,
      curve: AnimationCurves.microInteraction,
    );
  }

  Widget _buildConversationsList() {
    return Consumer(
      builder: (context, ref, child) {
        final conversationsAsync = ref.watch(conversationsProvider);

        return conversationsAsync.when(
          data: (conversations) {
            if (conversations.isEmpty) {
              return _buildEmptyState();
            }

            final filteredConversations = _filterConversations(conversations);

            if (filteredConversations.isEmpty) {
              return _buildNoResultsState();
            }

            // Separate conversations by status
            final pinnedConversations = filteredConversations
                .where((c) => c.pinned == true)
                .toList();
            final regularConversations = filteredConversations
                .where((c) => c.pinned != true && c.archived != true)
                .toList();
            final archivedConversations = filteredConversations
                .where((c) => c.archived == true)
                .toList();

            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.pagePadding,
                vertical: Spacing.sm,
              ),
              children: [
                // Pinned conversations section
                if (pinnedConversations.isNotEmpty) ...[
                  _buildSectionHeader('Pinned', pinnedConversations.length),
                  ...pinnedConversations.asMap().entries.map((entry) {
                    return _buildConversationTile(
                      entry.value,
                      entry.key,
                      isPinned: true,
                    );
                  }),
                  const SizedBox(height: Spacing.lg),
                ],

                // Regular conversations section
                if (regularConversations.isNotEmpty) ...[
                  _buildSectionHeader('Recent', regularConversations.length),
                  ...regularConversations.asMap().entries.map((entry) {
                    return _buildConversationTile(entry.value, entry.key);
                  }),
                ],

                // Archived conversations section (collapsed by default)
                if (archivedConversations.isNotEmpty) ...[
                  const SizedBox(height: Spacing.lg),
                  _buildArchivedSection(archivedConversations),
                ],
              ],
            );
          },
          loading: () => _buildLoadingState(),
          error: (error, stackTrace) => _buildErrorState(error),
        );
      },
    );
  }

  Widget _wrapWithRefresh(Widget child) {
    return ConduitRefreshIndicator(
      onRefresh: () async {
        ref.invalidate(conversationsProvider);
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: child,
    );
  }

  Widget _buildConversationTile(
    dynamic conversation,
    int index, {
    bool isPinned = false,
    bool isArchived = false,
  }) {
    final isSelected =
        ref.watch(activeConversationProvider)?.id == conversation.id;
    // TODO: Use pinned status for future conversation management features
    // final conversationIsPinned = conversation.pinned ?? false;
    final isLoading = _isLoadingConversation && isSelected;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.listGap),
      decoration: BoxDecoration(
        gradient: isSelected
            ? LinearGradient(
                colors: [
                  context.conduitTheme.navigationSelectedBackground.withValues(
                    alpha: 0.15,
                  ),
                  context.conduitTheme.navigationSelectedBackground.withValues(
                    alpha: 0.05,
                  ),
                ],
              )
            : null,
        color: isSelected
            ? null
            : isArchived
            ? context.conduitTheme.surfaceContainer.withValues(alpha: 0.3)
            : context.conduitTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: Border.all(
          color: isSelected
              ? context.conduitTheme.navigationSelected
              : isArchived
              ? context.conduitTheme.dividerColor.withValues(alpha: 0.5)
              : context.conduitTheme.cardBorder,
          width: BorderWidth.regular,
        ),
        boxShadow: isSelected ? ConduitShadows.high : ConduitShadows.low,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : () => _selectConversation(conversation),
          onLongPress: isLoading
              ? null
              : () => _showConversationOptions(conversation),
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.listItemPadding),
            child: Row(
              children: [
                // Conversation icon/avatar
                Container(
                  width: IconSize.avatar,
                  height: IconSize.avatar,
                  decoration: BoxDecoration(
                    color: context.conduitTheme.buttonPrimary,
                    borderRadius: BorderRadius.circular(AppBorderRadius.avatar),
                    boxShadow: ConduitShadows.card,
                  ),
                  child: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.chat_bubble
                        : Icons.chat_rounded,
                    size: IconSize.medium,
                    color: context.conduitTheme.buttonPrimaryText,
                  ),
                ),
                const SizedBox(width: Spacing.md),

                // Conversation details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.title ?? 'New Chat',
                              style: AppTypography.bodyLargeStyle.copyWith(
                                color: isArchived
                                    ? context.conduitTheme.textSecondary
                                    : context.conduitTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPinned)
                            Icon(
                              Platform.isIOS
                                  ? CupertinoIcons.pin_fill
                                  : Icons.push_pin,
                              size: IconSize.small,
                              color: context.conduitTheme.warning,
                            ),
                        ],
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        _getConversationPreview(conversation),
                        style: AppTypography.bodySmallStyle.copyWith(
                          color: isArchived
                              ? context.conduitTheme.textTertiary
                              : context.conduitTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        _formatConversationDate(conversation.updatedAt),
                        style: AppTypography.captionStyle.copyWith(
                          color: isArchived
                              ? context.conduitTheme.textTertiary.withValues(
                                  alpha: 0.5,
                                )
                              : context.conduitTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Action buttons
                Column(
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: IconSize.medium,
                        height: IconSize.medium,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            context.conduitTheme.buttonPrimary,
                          ),
                        ),
                      )
                    else ...[
                      ConduitIconButton(
                        icon: Platform.isIOS
                            ? CupertinoIcons.ellipsis
                            : Icons.more_vert_rounded,
                        onPressed: () => _showConversationOptions(conversation),
                      ),
                      if (conversation.messages.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.xs,
                            vertical: Spacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: context.conduitTheme.buttonPrimary,
                            borderRadius: BorderRadius.circular(
                              AppBorderRadius.badge,
                            ),
                          ),
                          child: Text(
                            conversation.messages.length.toString(),
                            style: AppTypography.captionStyle.copyWith(
                              color: context.conduitTheme.buttonPrimaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(
      duration: AnimationDuration.messageAppear,
      delay: Duration(
        milliseconds: index * AnimationDelay.staggeredDelay.inMilliseconds,
      ),
      curve: AnimationCurves.messageSlide,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Platform.isIOS ? CupertinoIcons.chat_bubble : Icons.chat_rounded,
            size: IconSize.xxl,
            color: context.conduitTheme.iconSecondary,
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'No conversations yet',
            style: AppTypography.headlineSmallStyle.copyWith(
              color: context.conduitTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Start a new chat to begin your conversation',
            style: AppTypography.bodyMediumStyle.copyWith(
              color: context.conduitTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startNewChat,
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
                'Start New Chat',
                style: AppTypography.labelStyle.copyWith(
                  color: context.conduitTheme.buttonPrimaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(
      duration: AnimationDuration.pageTransition,
      curve: AnimationCurves.pageTransition,
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Platform.isIOS ? CupertinoIcons.search : Icons.search_rounded,
            size: IconSize.xxl,
            color: context.conduitTheme.iconSecondary,
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'No conversations found',
            style: AppTypography.headlineSmallStyle.copyWith(
              color: context.conduitTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Try adjusting your search terms',
            style: AppTypography.bodyMediumStyle.copyWith(
              color: context.conduitTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(
      duration: AnimationDuration.pageTransition,
      curve: AnimationCurves.pageTransition,
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.pagePadding),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: Spacing.listGap),
          padding: const EdgeInsets.all(Spacing.listItemPadding),
          decoration: BoxDecoration(
            color: context.conduitTheme.cardBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(
              color: context.conduitTheme.cardBorder,
              width: BorderWidth.regular,
            ),
            boxShadow: ConduitShadows.low,
          ),
          child: Row(
            children: [
              Container(
                width: IconSize.avatar,
                height: IconSize.avatar,
                decoration: BoxDecoration(
                  color: context.conduitTheme.shimmerBase,
                  borderRadius: BorderRadius.circular(AppBorderRadius.avatar),
                ),
              ).animate().shimmer(duration: AnimationDuration.slow),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: AppTypography.bodyLarge,
                      decoration: BoxDecoration(
                        color: context.conduitTheme.shimmerBase,
                        borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                      ),
                    ).animate().shimmer(duration: AnimationDuration.slow),
                    const SizedBox(height: Spacing.xs),
                    Container(
                      height: AppTypography.bodySmall,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: context.conduitTheme.shimmerBase,
                        borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                      ),
                    ).animate().shimmer(duration: AnimationDuration.slow),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
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
            'Failed to load conversations',
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
            onPressed: () => ref.invalidate(conversationsProvider),
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
    );
  }

  Widget _buildBottomActions() {
    return const SizedBox.shrink(); // Remove bottom actions since we'll use FAB
  }

  // Helper methods
  List<dynamic> _filterConversations(List<dynamic> conversations) {
    if (_searchQuery.isEmpty) return conversations;

    return conversations.where((conversation) {
      final title = conversation.title?.toLowerCase() ?? '';
      final content = _getConversationPreview(conversation).toLowerCase();
      final query = _searchQuery.toLowerCase();

      return title.contains(query) || content.contains(query);
    }).toList();
  }

  String _getConversationPreview(dynamic conversation) {
    if (conversation.messages != null && conversation.messages.isNotEmpty) {
      final lastMessage = conversation.messages.last;
      return lastMessage.content ?? 'No content';
    }
    return 'Start a new conversation';
  }

  String _formatConversationDate(DateTime? date) {
    if (date == null) return '';

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // Same day - show time
      final hour = date.hour;
      final minute = date.minute;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // Show day name for this week
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else if (difference.inDays < 365) {
      // Show month and day for this year
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[date.month - 1]} ${date.day}';
    } else {
      // Show full date for older conversations
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  // TODO: Implement search toggle functionality when needed
  // void _toggleSearch() {
  //   // Focus the search field when search is toggled
  //   FocusScope.of(context).requestFocus(FocusNode());
  //   _searchController.clear();
  //   setState(() {
  //     _searchQuery = '';
  //   });
  //   ref.read(searchQueryProvider.notifier).state = '';
  // }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppBorderRadius.bottomSheet),
          ),
          border: Border.all(
            color: context.conduitTheme.dividerColor,
            width: BorderWidth.regular,
          ),
          boxShadow: ConduitShadows.modal,
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Spacing.md),
                  decoration: BoxDecoration(
                    color: context.conduitTheme.dividerColor,
                    borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                  ),
                ),
                // Options
                ListTile(
                  leading: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.folder
                        : Icons.folder_rounded,
                    color: context.conduitTheme.iconPrimary,
                  ),
                  title: Text(
                    'Manage Folders',
                    style: AppTypography.bodyMediumStyle.copyWith(
                      color: context.conduitTheme.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showFolderManagement();
                  },
                ),
                ListTile(
                  leading: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.archivebox
                        : Icons.archive_rounded,
                    color: context.conduitTheme.iconPrimary,
                  ),
                  title: Text(
                    'Archived Chats',
                    style: AppTypography.bodyMediumStyle.copyWith(
                      color: context.conduitTheme.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showArchivedSection();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectConversation(dynamic conversation) async {
    if (_isLoadingConversation) return; // Prevent multiple loads

    setState(() {
      _isLoadingConversation = true;
    });

    try {
      // Mark global conversation loading state to show skeletons in chat
      ref.read(isLoadingConversationProvider.notifier).state = true;
      // Load the full conversation with messages
      final api = ref.read(apiServiceProvider);
      if (api != null) {
        debugPrint('DEBUG: Loading full conversation: ${conversation.id}');
        final fullConversation = await api.getConversation(conversation.id);
        debugPrint(
          'DEBUG: Loaded conversation with ${fullConversation.messages.length} messages',
        );

        // Set the full conversation as active
        ref.read(activeConversationProvider.notifier).state = fullConversation;
        // Clear global loading before navigating so chat doesn't stick on skeletons
        ref.read(isLoadingConversationProvider.notifier).state = false;
      } else {
        // Fallback to the conversation from the list
        ref.read(activeConversationProvider.notifier).state = conversation;
        // Clear global loading before navigating
        ref.read(isLoadingConversationProvider.notifier).state = false;
      }

      // Do not navigate synchronously after async awaits; schedule for next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.isOverlay) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pop();
        }
      });
    } catch (e) {
      debugPrint('DEBUG: Error loading conversation: $e');
      // Fallback to the conversation from the list
      ref.read(activeConversationProvider.notifier).state = conversation;
      // Ensure global loading is cleared even on error
      ref.read(isLoadingConversationProvider.notifier).state = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.isOverlay) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pop();
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingConversation = false;
        });
      }
    }
  }

  void _showConversationOptions(dynamic conversation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppBorderRadius.bottomSheet),
          ),
          border: Border.all(
            color: context.conduitTheme.dividerColor,
            width: BorderWidth.regular,
          ),
          boxShadow: ConduitShadows.modal,
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Spacing.md),
                  decoration: BoxDecoration(
                    color: context.conduitTheme.dividerColor,
                    borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                  ),
                ),
                // Conversation title
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(
                    conversation.title ?? 'New Chat',
                    style: AppTypography.headlineSmallStyle.copyWith(
                      color: context.conduitTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // Options
                ListTile(
                  leading: Icon(
                    Platform.isIOS ? CupertinoIcons.pin : Icons.push_pin,
                    color: conversation.pinned == true
                        ? context.conduitTheme.warning
                        : context.conduitTheme.iconPrimary,
                  ),
                  title: Text(
                    conversation.pinned == true ? 'Unpin Chat' : 'Pin Chat',
                    style: AppTypography.bodyMediumStyle.copyWith(
                      color: context.conduitTheme.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _togglePinConversation(conversation);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.folder
                        : Icons.folder_rounded,
                    color: context.conduitTheme.iconPrimary,
                  ),
                  title: Text(
                    'Move to Folder',
                    style: AppTypography.bodyMediumStyle.copyWith(
                      color: context.conduitTheme.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _moveToFolder(conversation);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.archivebox
                        : Icons.archive_rounded,
                    color: context.conduitTheme.iconPrimary,
                  ),
                  title: Text(
                    'Archive Chat',
                    style: AppTypography.bodyMediumStyle.copyWith(
                      color: context.conduitTheme.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _archiveConversation(conversation);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.delete
                        : Icons.delete_rounded,
                    color: context.conduitTheme.error,
                  ),
                  title: Text(
                    'Delete Chat',
                    style: AppTypography.bodyMediumStyle.copyWith(
                      color: context.conduitTheme.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteConversation(conversation);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startNewChat() {
    startNewChat(ref);
    if (widget.isOverlay) {
      Navigator.of(context).pop(); // Close the overlay
    } else {
      Navigator.of(context).pop(); // Go back to main navigation
    }
  }

  void _showFolderManagement() {
    showDialog(
      context: context,
      builder: (context) => const FolderManagementDialog(),
    );
  }

  void _togglePinConversation(dynamic conversation) async {
    try {
      final api = ref.read(apiServiceProvider);
      if (api != null) {
        final newPinnedState = !(conversation.pinned ?? false);
        await api.pinConversation(conversation.id, newPinnedState);

        // Refresh conversations list
        ref.invalidate(conversationsProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newPinnedState ? 'Chat pinned' : 'Chat unpinned',
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: context.conduitTheme.textInverse,
                ),
              ),
              backgroundColor: context.conduitTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('DEBUG: Error toggling pin: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${conversation.pinned == true ? 'unpin' : 'pin'} chat',
              style: AppTypography.bodyMediumStyle.copyWith(
                color: context.conduitTheme.textInverse,
              ),
            ),
            backgroundColor: context.conduitTheme.error,
          ),
        );
      }
    }
  }

  void _moveToFolder(dynamic conversation) {
    // TODO: Implement folder selection dialog
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Move to folder feature coming soon!',
            style: AppTypography.bodyMediumStyle.copyWith(
              color: context.conduitTheme.textInverse,
            ),
          ),
          backgroundColor: context.conduitTheme.info,
        ),
      );
    }
  }

  void _archiveConversation(dynamic conversation) async {
    try {
      final api = ref.read(apiServiceProvider);
      if (api != null) {
        await api.archiveConversation(conversation.id, true);

        // Refresh conversations list
        ref.invalidate(conversationsProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Chat archived',
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: context.conduitTheme.textInverse,
                ),
              ),
              backgroundColor: context.conduitTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('DEBUG: Error archiving conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to archive chat',
              style: AppTypography.bodyMediumStyle.copyWith(
                color: context.conduitTheme.textInverse,
              ),
            ),
            backgroundColor: context.conduitTheme.error,
          ),
        );
      }
    }
  }

  void _deleteConversation(dynamic conversation) async {
    // Show confirmation dialog
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: 'Delete Chat',
      message:
          'Are you sure you want to delete "${conversation.title ?? 'New Chat'}"? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
      barrierDismissible: true,
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiServiceProvider);
        if (api != null) {
          await api.deleteConversation(conversation.id);

          // Refresh conversations list
          ref.invalidate(conversationsProvider);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Chat deleted',
                  style: AppTypography.bodyMediumStyle.copyWith(
                    color: context.conduitTheme.textInverse,
                  ),
                ),
                backgroundColor: context.conduitTheme.success,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('DEBUG: Error deleting conversation: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to delete chat',
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: context.conduitTheme.textInverse,
                ),
              ),
              backgroundColor: context.conduitTheme.error,
            ),
          );
        }
      }
    }
  }

  void _showArchivedSection() {
    // Set the archived section to be visible
    ref.read(_showArchivedProvider.notifier).state = true;

    // Scroll to the archived section
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.md,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.labelStyle.copyWith(
              color: context.conduitTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.xs,
              vertical: Spacing.xxs,
            ),
            decoration: BoxDecoration(
              color: context.conduitTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppBorderRadius.badge),
            ),
            child: Text(
              count.toString(),
              style: AppTypography.captionStyle.copyWith(
                color: context.conduitTheme.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedSection(List<dynamic> archivedConversations) {
    return Consumer(
      builder: (context, ref, child) {
        final showArchived = ref.watch(_showArchivedProvider);

        return Column(
          children: [
            // Collapsible header
            InkWell(
              onTap: () {
                ref.read(_showArchivedProvider.notifier).state = !showArchived;
              },
              borderRadius: BorderRadius.circular(AppBorderRadius.card),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Row(
                  children: [
                    Icon(
                      Platform.isIOS
                          ? CupertinoIcons.archivebox
                          : Icons.archive_rounded,
                      size: IconSize.small,
                      color: context.conduitTheme.textSecondary,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      'Archived',
                      style: AppTypography.labelStyle.copyWith(
                        color: context.conduitTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.xs,
                        vertical: Spacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: context.conduitTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(
                          AppBorderRadius.badge,
                        ),
                      ),
                      child: Text(
                        archivedConversations.length.toString(),
                        style: AppTypography.captionStyle.copyWith(
                          color: context.conduitTheme.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      showArchived
                          ? (Platform.isIOS
                                ? CupertinoIcons.chevron_up
                                : Icons.keyboard_arrow_up)
                          : (Platform.isIOS
                                ? CupertinoIcons.chevron_down
                                : Icons.keyboard_arrow_down),
                      size: IconSize.small,
                      color: context.conduitTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // Archived conversations (collapsible)
            if (showArchived) ...[
              const SizedBox(height: Spacing.sm),
              ...archivedConversations.asMap().entries.map((entry) {
                return _buildConversationTile(
                  entry.value,
                  entry.key,
                  isArchived: true,
                );
              }),
            ],
          ],
        );
      },
    );
  }
}
