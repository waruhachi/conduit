import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../chat/providers/chat_providers.dart' as chat;
// import '../../files/views/files_page.dart';
import '../../profile/views/profile_page.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../core/auth/auth_state_manager.dart';
import 'package:conduit/l10n/app_localizations.dart';

class ChatsDrawer extends ConsumerStatefulWidget {
  const ChatsDrawer({super.key});

  @override
  ConsumerState<ChatsDrawer> createState() => _ChatsDrawerState();
}

class _ChatsDrawerState extends ConsumerState<ChatsDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'drawer_search');
  Timer? _debounce;
  String _query = '';
  bool _isLoadingConversation = false;
  String? _dragHoverFolderId;
  bool _isDragging = false;
  bool _draggingHasFolder = false;

  // UI state providers for sections
  static final _showArchivedProvider = StateProvider<bool>((ref) => false);
  static final _expandedFoldersProvider =
      StateProvider<Map<String, bool>>((ref) => {});

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = _searchController.text.trim());
    });
  }

  // Payload for drag-and-drop of conversations
  // Kept local to this widget
  // ignore: unused_element
  static _DragConversationData _dragData(String id, String title) =>
      _DragConversationData(id: id, title: title);

  @override
  Widget build(BuildContext context) {
    // Bottom section now only shows navigation actions
    final theme = context.conduitTheme;

    return SafeArea(
      child: Container(
        color: theme.surfaceBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: _buildSearchField(context),
            ),
            Expanded(child: _buildConversationList(context)),
            const Divider(height: 1),
            _buildBottomSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = context.conduitTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Centered title (no leading icon)
          Text(
            'Chats',
            style: AppTypography.headlineSmallStyle.copyWith(
              color: theme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          // Right-aligned new chat action
          Positioned(
            right: 0,
            child: IconButton(
              icon: Icon(
                Platform.isIOS ? CupertinoIcons.plus : Icons.add_rounded,
                color: theme.iconPrimary,
              ),
              onPressed: () {
                chat.startNewChat(ref);
                if (mounted) Navigator.of(context).maybePop();
              },
              tooltip: AppLocalizations.of(context)!.newChat,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = context.conduitTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.inputBackground.withValues(alpha: 0.6),
            theme.inputBackground.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        border: Border.all(
          color: _searchFocusNode.hasFocus
              ? theme.buttonPrimary.withValues(alpha: 0.8)
              : theme.inputBorder.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (_) => _onSearchChanged(),
        style: TextStyle(
          color: theme.inputText,
          fontSize: AppTypography.bodyMedium,
        ),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.searchConversations,
          hintStyle: TextStyle(
            color: theme.inputPlaceholder.withValues(alpha: 0.8),
            fontSize: AppTypography.bodyMedium,
          ),
          prefixIcon: Icon(
            Platform.isIOS ? CupertinoIcons.search : Icons.search,
            color: theme.iconSecondary,
            size: IconSize.md,
          ),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                    _searchFocusNode.unfocus();
                  },
                  icon: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.clear_circled_solid
                        : Icons.clear,
                    color: theme.iconSecondary,
                    size: IconSize.md,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(BuildContext context) {
    final theme = context.conduitTheme;

    if (_query.isEmpty) {
      final conversationsAsync = ref.watch(conversationsProvider);
      return conversationsAsync.when(
        data: (items) {
          final list = items;

          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Text(
                  'No conversations yet',
                  style: AppTypography.bodyMediumStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ),
            );
          }

          // Build sections
          final pinned = list.where((c) => c.pinned == true).toList();
          final regular = list
              .where((c) =>
                  c.pinned != true &&
                  c.archived != true &&
                  (c.folderId == null || c.folderId!.isEmpty))
              .toList();
          final foldered = list
              .where((c) =>
                  c.pinned != true &&
                  c.archived != true &&
                  c.folderId != null &&
                  c.folderId!.isNotEmpty)
              .toList();
          final archived = list.where((c) => c.archived == true).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              Spacing.md,
            ),
            children: [
              if (pinned.isNotEmpty) ...[
                _buildSectionHeader('Pinned', pinned.length),
                const SizedBox(height: Spacing.xs),
                ...pinned.map((conv) => _buildTileFor(conv)),
                const SizedBox(height: Spacing.md),
              ],

              // Folders section (shown even if empty)
              _buildFoldersSectionHeader(),
              const SizedBox(height: Spacing.xs),
              if (_isDragging && _draggingHasFolder) ...[
                _buildUnfileDropTarget(),
                const SizedBox(height: Spacing.sm),
              ],
              ...ref.watch(foldersProvider).when(
                      data: (folders) {
                        final grouped = <String, List<dynamic>>{};
                        for (final c in foldered) {
                          final id = c.folderId!;
                          grouped.putIfAbsent(id, () => []).add(c);
                        }

                        // Show all folders (including empty)
                        final sections = folders.map((folder) {
                          final expandedMap = ref.watch(_expandedFoldersProvider);
                          final isExpanded = expandedMap[folder.id] ?? false;
                          final convs = grouped[folder.id] ?? const <dynamic>[];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildFolderHeader(folder.id, folder.name, convs.length),
                              if (isExpanded && convs.isNotEmpty) ...[
                                const SizedBox(height: Spacing.xs),
                                ...convs.map((c) => _buildTileFor(c, inFolder: true)),
                                const SizedBox(height: Spacing.sm),
                              ],
                            ],
                          );
                        }).toList();
                        return sections.isEmpty ? [const SizedBox.shrink()] : sections;
                      },
                      loading: () => [const SizedBox.shrink()],
                      error: (e, st) => [const SizedBox.shrink()],
                    ),
              const SizedBox(height: Spacing.md),

              if (regular.isNotEmpty) ...[
                _buildSectionHeader(AppLocalizations.of(context)!.recent, regular.length),
                const SizedBox(height: Spacing.xs),
                ...regular.map(_buildTileFor),
              ],

              if (archived.isNotEmpty) ...[
                const SizedBox(height: Spacing.md),
                _buildArchivedSection(archived),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text(
              AppLocalizations.of(context)!.failedToLoadChats,
              style: AppTypography.bodyMediumStyle.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    // Server-backed search
    final searchAsync = ref.watch(serverSearchProvider(_query));
    return searchAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                'No results for "$_query"',
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
          );
        }

        final pinned = list.where((c) => c.pinned == true).toList();
        final regular = list
            .where((c) =>
                c.pinned != true &&
                c.archived != true &&
                (c.folderId == null || c.folderId!.isEmpty))
            .toList();
        final foldered = list
            .where((c) =>
                c.pinned != true &&
                c.archived != true &&
                c.folderId != null &&
                c.folderId!.isNotEmpty)
            .toList();
        final archived = list.where((c) => c.archived == true).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.md,
          ),
          children: [
            _buildSectionHeader('Results', list.length),
            const SizedBox(height: Spacing.xs),
            if (pinned.isNotEmpty) ...[
              _buildSectionHeader('Pinned', pinned.length),
              const SizedBox(height: Spacing.xs),
              ...pinned.map((conv) => _buildTileFor(conv)),
              const SizedBox(height: Spacing.md),
            ],
            // Folders section (shown even if empty)
            _buildFoldersSectionHeader(),
            const SizedBox(height: Spacing.xs),
            if (_isDragging && _draggingHasFolder) ...[
              _buildUnfileDropTarget(),
              const SizedBox(height: Spacing.sm),
            ],
            ...ref.watch(foldersProvider).when(
                  data: (folders) {
                    final grouped = <String, List<dynamic>>{};
                    for (final c in foldered) {
                      final id = c.folderId!;
                      grouped.putIfAbsent(id, () => []).add(c);
                    }

                      final sections = folders.map((folder) {
                        final expandedMap = ref.watch(_expandedFoldersProvider);
                        final isExpanded = expandedMap[folder.id] ?? false;
                        final convs = grouped[folder.id] ?? const <dynamic>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildFolderHeader(folder.id, folder.name, convs.length),
                            if (isExpanded && convs.isNotEmpty) ...[
                              const SizedBox(height: Spacing.xs),
                              ...convs.map((c) => _buildTileFor(c, inFolder: true)),
                              const SizedBox(height: Spacing.sm),
                            ],
                          ],
                        );
                      }).toList();
                      return sections.isEmpty ? [const SizedBox.shrink()] : sections;
                    },
                    loading: () => [const SizedBox.shrink()],
                    error: (e, st) => [const SizedBox.shrink()],
                  ),
            const SizedBox(height: Spacing.md),
            if (regular.isNotEmpty) ...[
              _buildSectionHeader(AppLocalizations.of(context)!.recent, regular.length),
              const SizedBox(height: Spacing.xs),
              ...regular.map(_buildTileFor),
            ],
            if (archived.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              _buildArchivedSection(archived),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Text(
            'Search failed',
            style: AppTypography.bodyMediumStyle.copyWith(
              color: theme.textSecondary,
            ),
          ),
        ),
      ),
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

  /// Header for the Folders section with a create button on the right
  Widget _buildFoldersSectionHeader() {
    final theme = context.conduitTheme;
    return Row(
      children: [
        Text(
          'Folders',
          style: AppTypography.bodySmallStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: AppLocalizations.of(context)!.newFolder,
          icon: Icon(
            Platform.isIOS ? CupertinoIcons.folder_badge_plus : Icons.create_new_folder_outlined,
            color: theme.iconPrimary,
          ),
          onPressed: _promptCreateFolder,
        ),
      ],
    );
  }

  Future<void> _promptCreateFolder() async {
    final theme = context.conduitTheme;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.surfaceBackground,
        title: Text(AppLocalizations.of(context)!.newFolder, style: TextStyle(color: theme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.inputText),
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.folderName,
            hintStyle: TextStyle(color: theme.inputPlaceholder),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.inputBorder)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.buttonPrimary)),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );

    if (name == null) return;
    if (name.isEmpty) return;
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.createFolder(name: name);
      HapticFeedback.lightImpact();
      ref.invalidate(foldersProvider);
      if (!mounted) return;
      UiUtils.showMessage(context, AppLocalizations.of(context)!.folderCreated);
    } catch (e) {
      if (!mounted) return;
      UiUtils.showMessage(context, AppLocalizations.of(context)!.failedToCreateFolder, isError: true);
    }
  }

  Widget _buildFolderHeader(String folderId, String name, int count) {
    final theme = context.conduitTheme;
    final expandedMap = ref.watch(_expandedFoldersProvider);
    final isExpanded = expandedMap[folderId] ?? false;
    final isHover = _dragHoverFolderId == folderId;
    return DragTarget<_DragConversationData>(
      onWillAcceptWithDetails: (details) {
        setState(() => _dragHoverFolderId = folderId);
        return true;
      },
      onLeave: (_) => setState(() => _dragHoverFolderId = null),
      onAcceptWithDetails: (details) async {
        setState(() {
          _dragHoverFolderId = null;
          _isDragging = false;
        });
        try {
          final api = ref.read(apiServiceProvider);
          if (api == null) throw Exception('No API service');
          await api.moveConversationToFolder(details.data.id, folderId);
          HapticFeedback.selectionClick();
          ref.invalidate(conversationsProvider);
          ref.invalidate(foldersProvider);
          if (mounted) {
            UiUtils.showMessage(
              context,
              AppLocalizations.of(context)!.movedChatToFolder(details.data.title, name),
            );
          }
        } catch (_) {
          if (mounted) {
            UiUtils.showMessage(context, AppLocalizations.of(context)!.failedToMoveChat, isError: true);
          }
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Material(
          color: isHover
              ? theme.buttonPrimary.withValues(alpha: 0.08)
              : theme.surfaceBackground.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            side: BorderSide(
              color: isHover
                  ? theme.buttonPrimary.withValues(alpha: 0.6)
                  : theme.dividerColor,
              width: BorderWidth.regular,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            onTap: () {
              final current = {...ref.read(_expandedFoldersProvider)};
              current[folderId] = !isExpanded;
              ref.read(_expandedFoldersProvider.notifier).state = current;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    isExpanded
                        ? (Platform.isIOS ? CupertinoIcons.folder_open : Icons.folder_open)
                        : (Platform.isIOS ? CupertinoIcons.folder : Icons.folder),
                    color: theme.iconPrimary,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      name,
                      style: AppTypography.bodyLargeStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Icon(
                    isExpanded
                        ? (Platform.isIOS ? CupertinoIcons.chevron_up : Icons.expand_less)
                        : (Platform.isIOS ? CupertinoIcons.chevron_down : Icons.expand_more),
                    color: theme.iconSecondary,
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnfileDropTarget() {
    final theme = context.conduitTheme;
    final isHover = _dragHoverFolderId == '__UNFILE__';
    return DragTarget<_DragConversationData>(
      onWillAcceptWithDetails: (details) {
        setState(() => _dragHoverFolderId = '__UNFILE__');
        return true;
      },
      onLeave: (_) => setState(() => _dragHoverFolderId = null),
      onAcceptWithDetails: (details) async {
        setState(() {
          _dragHoverFolderId = null;
          _isDragging = false;
        });
        try {
          final api = ref.read(apiServiceProvider);
          if (api == null) throw Exception('No API service');
          await api.moveConversationToFolder(details.data.id, null);
          HapticFeedback.selectionClick();
          ref.invalidate(conversationsProvider);
          ref.invalidate(foldersProvider);
          if (mounted) {
            UiUtils.showMessage(context, 'Removed "${details.data.title}" from folder');
          }
        } catch (_) {
          if (mounted) {
            UiUtils.showMessage(context, AppLocalizations.of(context)!.failedToMoveChat, isError: true);
          }
        }
      },
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: isHover
                ? theme.buttonPrimary.withValues(alpha: 0.08)
                : theme.surfaceBackground.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            border: Border.all(
              color: isHover
                  ? theme.buttonPrimary.withValues(alpha: 0.6)
                  : theme.dividerColor,
              width: BorderWidth.regular,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Platform.isIOS
                    ? CupertinoIcons.folder_badge_minus
                    : Icons.folder_off_outlined,
                color: theme.iconPrimary,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Drop here to remove from folder',
                  style: AppTypography.bodyMediumStyle.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTileFor(dynamic conv, {bool inFolder = false}) {
    final isActive = ref.watch(activeConversationProvider)?.id == conv.id;
    final title = conv.title?.isEmpty == true ? 'Chat' : (conv.title ?? 'Chat');
    final tile = _ConversationTile(
      title: title,
      pinned: conv.pinned == true,
      selected: isActive,
      onTap: _isLoadingConversation ? null : () => _selectConversation(context, conv.id),
      // Remove long-press context menu to avoid conflict with drag gesture
      onLongPress: null,
      onMorePressed: () {
        HapticFeedback.selectionClick();
        _showConversationContextMenu(context, conv);
      },
    );

    return Padding(
      padding: EdgeInsets.only(bottom: Spacing.xs, left: inFolder ? Spacing.md : 0),
      child: LongPressDraggable<_DragConversationData>(
        data: _DragConversationData(id: conv.id, title: title),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          elevation: 6,
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          child: Opacity(
            opacity: 0.9,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(AppBorderRadius.md),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: BorderWidth.regular,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Platform.isIOS
                        ? CupertinoIcons.chat_bubble_2
                        : Icons.chat_bubble_outline,
                    size: IconSize.md,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.5,
          child: IgnorePointer(child: tile),
        ),
        onDragStarted: () {
          HapticFeedback.lightImpact();
          final hasFolder = (conv.folderId != null && (conv.folderId as String).isNotEmpty);
          setState(() {
            _isDragging = true;
            _draggingHasFolder = hasFolder;
          });
        },
        onDragEnd: (_) => setState(() {
          _dragHoverFolderId = null;
          _isDragging = false;
          _draggingHasFolder = false;
        }),
        child: tile,
      ),
    );
  }

  Widget _buildArchivedSection(List<dynamic> archived) {
    final theme = context.conduitTheme;
    final show = ref.watch(_showArchivedProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.surfaceBackground.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            side: BorderSide(color: theme.dividerColor, width: BorderWidth.regular),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            onTap: () =>
                ref.read(_showArchivedProvider.notifier).state = !show,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Platform.isIOS
                        ? CupertinoIcons.archivebox
                        : Icons.archive_rounded,
                    color: theme.iconPrimary,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Archived',
                      style: AppTypography.bodyLargeStyle.copyWith(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${archived.length}',
                    style: AppTypography.bodySmallStyle.copyWith(
                      color: theme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Icon(
                    show
                        ? (Platform.isIOS
                            ? CupertinoIcons.chevron_up
                            : Icons.expand_less)
                        : (Platform.isIOS
                            ? CupertinoIcons.chevron_down
                            : Icons.expand_more),
                    color: theme.iconSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (show) ...[
          const SizedBox(height: Spacing.xs),
          ...archived.map((c) => _buildTileFor(c)),
        ],
      ],
    );
  }

  Future<void> _selectConversation(BuildContext context, String id) async {
    if (_isLoadingConversation) return;
    setState(() => _isLoadingConversation = true);
    final navigator = Navigator.of(context);
    try {
      // Mark global loading to show skeletons in chat
      ref.read(chat.isLoadingConversationProvider.notifier).state = true;

      final api = ref.read(apiServiceProvider);
      if (api != null) {
        final full = await api.getConversation(id);
        ref.read(activeConversationProvider.notifier).state = full;
      } else {
        // Fallback: let ChatPage handle if API missing
        ref.read(activeConversationProvider.notifier).state =
            (await ref.read(conversationsProvider.future))
                .firstWhere((c) => c.id == id);
      }

      // Clear global loading before closing drawer
      ref.read(chat.isLoadingConversationProvider.notifier).state = false;

      if (mounted) navigator.maybePop();
    } catch (_) {
      ref.read(chat.isLoadingConversationProvider.notifier).state = false;
      if (mounted) navigator.maybePop();
    } finally {
      if (mounted) setState(() => _isLoadingConversation = false);
    }
  }

  Widget _buildBottomSection(BuildContext context) {
    final theme = context.conduitTheme;
    final user = ref.watch(authUserProvider);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user != null) ...[
              const SizedBox(height: Spacing.sm),
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: theme.surfaceBackground.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(AppBorderRadius.md),
                  border: Border.all(color: theme.dividerColor, width: BorderWidth.regular),
                ),
                child: Row(
                  children: [
                    Container(
                      width: IconSize.avatar,
                      height: IconSize.avatar,
                      decoration: BoxDecoration(
                        color: theme.buttonPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppBorderRadius.avatar),
                        border: Border.all(color: theme.buttonPrimary.withValues(alpha: 0.35), width: BorderWidth.thin),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (user.name ?? user.username ?? 'U').toString().substring(0, 1).toUpperCase(),
                        style: AppTypography.bodyLargeStyle.copyWith(
                          color: theme.buttonPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (user.name ?? user.username ?? 'User').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyLargeStyle.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'You',
                            style: AppTypography.bodySmallStyle.copyWith(
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).maybePop();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ProfilePage()),
                        );
                      },
                      child: Text(AppLocalizations.of(context)!.manage),
                    )
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showConversationContextMenu(BuildContext context, dynamic conv) {
    final theme = context.conduitTheme;
    final bool isPinned = conv.pinned == true;
    final bool isArchived = conv.archived == true;

    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppBorderRadius.lg)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isPinned
                      ? (Platform.isIOS ? CupertinoIcons.pin_slash : Icons.push_pin_outlined)
                      : (Platform.isIOS ? CupertinoIcons.pin_fill : Icons.push_pin_rounded),
                  color: theme.iconPrimary,
                ),
                title: Text(
                  isPinned
                      ? AppLocalizations.of(context)!.unpin
                      : AppLocalizations.of(context)!.pin,
                  style: TextStyle(color: theme.textPrimary),
                ),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  Navigator.pop(sheetContext);
                  try {
                    await chat.pinConversation(ref, conv.id, !isPinned);
                  } catch (_) {
                    if (!mounted) return;
                    UiUtils.showMessage(this.context, AppLocalizations.of(context)!.failedToUpdatePin, isError: true);
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  isArchived
                      ? (Platform.isIOS ? CupertinoIcons.archivebox_fill : Icons.unarchive_rounded)
                      : (Platform.isIOS ? CupertinoIcons.archivebox : Icons.archive_rounded),
                  color: theme.iconPrimary,
                ),
                title: Text(
                  isArchived
                      ? AppLocalizations.of(context)!.unarchive
                      : AppLocalizations.of(context)!.archive,
                  style: TextStyle(color: theme.textPrimary),
                ),
                onTap: () async {
                  HapticFeedback.lightImpact();
                  Navigator.pop(sheetContext);
                  try {
                    await chat.archiveConversation(ref, conv.id, !isArchived);
                  } catch (_) {
                    if (!mounted) return;
                    UiUtils.showMessage(this.context, AppLocalizations.of(context)!.failedToUpdateArchive, isError: true);
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Platform.isIOS ? CupertinoIcons.pencil : Icons.edit_rounded,
                  color: theme.iconPrimary,
                ),
                title: Text(AppLocalizations.of(context)!.rename, style: TextStyle(color: theme.textPrimary)),
                onTap: () async {
                  HapticFeedback.selectionClick();
                  Navigator.pop(sheetContext);
                  await _renameConversation(context, conv.id, conv.title ?? '');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Platform.isIOS ? CupertinoIcons.delete : Icons.delete_rounded,
                  color: theme.error,
                ),
                title: Text(AppLocalizations.of(context)!.delete, style: TextStyle(color: theme.error)),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(sheetContext);
                  await _confirmAndDeleteConversation(context, conv.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameConversation(
    BuildContext context,
    String conversationId,
    String currentTitle,
  ) async {
    final theme = context.conduitTheme;
    final controller = TextEditingController(text: currentTitle);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: theme.surfaceBackground,
          title: Text(AppLocalizations.of(context)!.renameChat, style: TextStyle(color: theme.textPrimary)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: theme.inputText),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.enterChatName,
              hintStyle: TextStyle(color: theme.inputPlaceholder),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.inputBorder),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: theme.buttonPrimary),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: Text(AppLocalizations.of(context)!.save),
            ),
          ],
        );
      },
    );

    if (newName == null) return;
    if (newName.isEmpty || newName == currentTitle) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.updateConversation(conversationId, title: newName);
      HapticFeedback.selectionClick();
      // Reflect changes
      ref.invalidate(conversationsProvider);
      final active = ref.read(activeConversationProvider);
      if (active?.id == conversationId) {
        ref.read(activeConversationProvider.notifier).state =
            active!.copyWith(title: newName);
      }
    } catch (_) {
      if (!mounted) return;
      UiUtils.showMessage(this.context, AppLocalizations.of(context)!.failedToRenameChat, isError: true);
    }
  }

  Future<void> _confirmAndDeleteConversation(
    BuildContext context,
    String conversationId,
  ) async {
    final confirmed = await UiUtils.showConfirmationDialog(
      context,
      title: AppLocalizations.of(context)!.deleteChatTitle,
      message: AppLocalizations.of(context)!.deleteChatMessage,
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
    );
    if (!confirmed) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.deleteConversation(conversationId);
      HapticFeedback.mediumImpact();
      // Clear if deleting active
      final active = ref.read(activeConversationProvider);
      if (active?.id == conversationId) {
        ref.read(activeConversationProvider.notifier).state = null;
        ref.read(chat.chatMessagesProvider.notifier).clearMessages();
      }
      ref.invalidate(conversationsProvider);
    } catch (_) {
      if (!mounted) return;
      UiUtils.showMessage(this.context, AppLocalizations.of(context)!.failedToDeleteChat, isError: true);
    }
  }
}

class _DragConversationData {
  final String id;
  final String title;
  const _DragConversationData({required this.id, required this.title});
}

class _ConversationTile extends StatelessWidget {
  final String title;
  final bool pinned;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMorePressed;

  const _ConversationTile({
    required this.title,
    required this.pinned,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    return Material(
      color: selected
          ? theme.buttonPrimary.withValues(alpha: 0.08)
          : theme.surfaceBackground.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        side: BorderSide(
          color: selected ? theme.buttonPrimary.withValues(alpha: 0.5) : theme.dividerColor,
          width: BorderWidth.regular,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLargeStyle.copyWith(
                    color: theme.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.xs),
              if (onMorePressed != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    Platform.isIOS ? CupertinoIcons.ellipsis : Icons.more_vert_rounded,
                    color: theme.iconSecondary,
                    size: IconSize.md,
                  ),
                  onPressed: onMorePressed,
                  tooltip: AppLocalizations.of(context)!.more,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bottom quick actions widget removed as design now shows only profile card
