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
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../core/auth/auth_state_manager.dart';
import 'package:conduit/l10n/app_localizations.dart';
import '../../../core/models/user.dart' as models;

class ChatsDrawer extends ConsumerStatefulWidget {
  const ChatsDrawer({super.key});

  @override
  ConsumerState<ChatsDrawer> createState() => _ChatsDrawerState();
}

class _ChatsDrawerState extends ConsumerState<ChatsDrawer> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'drawer_search');
  final ScrollController _listController = ScrollController();
  Timer? _debounce;
  String _query = '';
  bool _isLoadingConversation = false;
  String? _pendingConversationId;
  String? _dragHoverFolderId;
  bool _isDragging = false;
  bool _draggingHasFolder = false;

  // UI state providers for sections
  static final _showArchivedProvider = StateProvider<bool>((ref) => false);
  static final _expandedFoldersProvider = StateProvider<Map<String, bool>>(
    (ref) => {},
  );

  Future<void> _refreshChats() async {
    try {
      // Always refresh folders
      ref.invalidate(foldersProvider);

      if (_query.trim().isEmpty) {
        // Refresh main conversations list
        ref.invalidate(conversationsProvider);
        try {
          await ref.read(conversationsProvider.future);
        } catch (_) {}
      } else {
        // Refresh server-side search results
        ref.invalidate(serverSearchProvider(_query));
        try {
          await ref.read(serverSearchProvider(_query).future);
        } catch (_) {}
      }

      // Await folders as well so the list stabilizes
      try {
        await ref.read(foldersProvider.future);
      } catch (_) {}
    } catch (_) {}
  }

  Widget _buildRefreshableScrollable({required List<Widget> children}) {
    // Common padding used in both scrollable variants
    const padding = EdgeInsets.fromLTRB(
      Spacing.md,
      Spacing.sm,
      Spacing.md,
      Spacing.md,
    );

    if (Platform.isIOS) {
      // Use Cupertino-style pull-to-refresh on iOS
      final scroll = CustomScrollView(
        key: const PageStorageKey<String>('chats_drawer_scroll'),
        controller: _listController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: _refreshChats),
          SliverPadding(
            padding: padding,
            sliver: SliverList(
              delegate: SliverChildListDelegate(children),
            ),
          ),
        ],
      );
      return CupertinoScrollbar(controller: _listController, child: scroll);
    }

    // Material pull-to-refresh elsewhere
    return RefreshIndicator(
      onRefresh: _refreshChats,
      child: Scrollbar(
        controller: _listController,
        child: ListView(
          key: const PageStorageKey<String>('chats_drawer_scroll'),
          controller: _listController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: children,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listController.dispose();
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

    return Container(
      color: theme.surfaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.sm,
            ),
            child: Row(
              children: [
                Expanded(child: _buildSearchField(context)),
                const SizedBox(width: Spacing.sm),
                IconButton(
                  icon: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.bubble_left
                        : Icons.add_comment,
                    color: theme.iconPrimary,
                    size: IconSize.lg,
                  ),
                  onPressed: () {
                    chat.startNewChat(ref);
                    if (mounted) Navigator.of(context).maybePop();
                  },
                  tooltip: AppLocalizations.of(context)!.newChat,
                  constraints: const BoxConstraints(
                    minWidth: TouchTarget.comfortable,
                    minHeight: TouchTarget.comfortable,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildConversationList(context)),
          Divider(height: 1, color: theme.dividerColor),
          _buildBottomSection(context),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = context.conduitTheme;
    return TextField(
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
          color: theme.inputPlaceholder,
          fontSize: AppTypography.bodyMedium,
        ),
        prefixIcon: Icon(
          Platform.isIOS ? CupertinoIcons.search : Icons.search,
          color: theme.iconSecondary,
          size: IconSize.input,
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
                  size: IconSize.input,
                ),
              )
            : null,
        filled: true,
        fillColor: theme.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide(color: theme.inputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          borderSide: BorderSide(color: theme.buttonPrimary, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
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
                  AppLocalizations.of(context)!.noConversationsYet,
                  style: AppTypography.bodyMediumStyle.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ),
            );
          }

          // Build sections
          final pinned = list.where((c) => c.pinned == true).toList();

          // Determine which folder IDs actually exist from the API
          final foldersState = ref.watch(foldersProvider);
          final availableFolderIds = foldersState.maybeWhen(
            data: (folders) => folders.map((f) => f.id).toSet(),
            orElse: () => <String>{},
          );

          // Conversations that reference a non-existent/unknown folder should not disappear.
          // Treat those as regular until the folders list is available and contains the ID.
          final regular = list.where((c) {
            final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
            final folderKnown = hasFolder && availableFolderIds.contains(c.folderId);
            return c.pinned != true &&
                c.archived != true &&
                (!hasFolder || !folderKnown);
          }).toList();

          final foldered = list.where((c) {
            final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
            return c.pinned != true &&
                c.archived != true &&
                hasFolder &&
                availableFolderIds.contains(c.folderId);
          }).toList();

          final archived = list.where((c) => c.archived == true).toList();

          final children = <Widget>[
            if (pinned.isNotEmpty) ...[
              _buildSectionHeader(
                AppLocalizations.of(context)!.pinned,
                pinned.length,
              ),
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
            ...ref
                .watch(foldersProvider)
                .when(
                  data: (folders) {
                    final grouped = <String, List<dynamic>>{};
                    for (final c in foldered) {
                      final id = c.folderId!;
                      grouped.putIfAbsent(id, () => []).add(c);
                    }

                    // Show all folders (including empty)
                    final sections = folders.map((folder) {
                      final expandedMap = ref.watch(
                        _expandedFoldersProvider,
                      );
                      final isExpanded = expandedMap[folder.id] ?? false;
                      final convs = grouped[folder.id] ?? const <dynamic>[];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildFolderHeader(
                            folder.id,
                            folder.name,
                            convs.length,
                          ),
                          if (isExpanded && convs.isNotEmpty) ...[
                            const SizedBox(height: Spacing.xs),
                            ...convs.map(
                              (c) => _buildTileFor(c, inFolder: true),
                            ),
                            const SizedBox(height: Spacing.xs),
                          ],
                          const SizedBox(height: Spacing.xs),
                        ],
                      );
                    }).toList();
                    return sections.isEmpty
                        ? [const SizedBox.shrink()]
                        : sections;
                  },
                  loading: () => [const SizedBox.shrink()],
                  error: (e, st) => [const SizedBox.shrink()],
                ),
            const SizedBox(height: Spacing.md),

            if (regular.isNotEmpty) ...[
              _buildSectionHeader(
                AppLocalizations.of(context)!.recent,
                regular.length,
              ),
              const SizedBox(height: Spacing.xs),
              ...regular.map(_buildTileFor),
            ],

            if (archived.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              _buildArchivedSection(archived),
            ],
          ];
          return _buildRefreshableScrollable(children: children);
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
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

        // For search results, apply the same folder safety logic
        final foldersState = ref.watch(foldersProvider);
        final availableFolderIds = foldersState.maybeWhen(
          data: (folders) => folders.map((f) => f.id).toSet(),
          orElse: () => <String>{},
        );

        final regular = list.where((c) {
          final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
          final folderKnown = hasFolder && availableFolderIds.contains(c.folderId);
          return c.pinned != true &&
              c.archived != true &&
              (!hasFolder || !folderKnown);
        }).toList();

        final foldered = list.where((c) {
          final hasFolder = (c.folderId != null && c.folderId!.isNotEmpty);
          return c.pinned != true &&
              c.archived != true &&
              hasFolder &&
              availableFolderIds.contains(c.folderId);
        }).toList();

        final archived = list.where((c) => c.archived == true).toList();

        final children = <Widget>[
          _buildSectionHeader('Results', list.length),
          const SizedBox(height: Spacing.xs),
          if (pinned.isNotEmpty) ...[
            _buildSectionHeader(
              AppLocalizations.of(context)!.pinned,
              pinned.length,
            ),
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
          ...ref
              .watch(foldersProvider)
              .when(
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
                        _buildFolderHeader(
                          folder.id,
                          folder.name,
                          convs.length,
                        ),
                        if (isExpanded && convs.isNotEmpty) ...[
                          const SizedBox(height: Spacing.xs),
                          ...convs.map(
                            (c) => _buildTileFor(c, inFolder: true),
                          ),
                          const SizedBox(height: Spacing.sm),
                        ],
                      ],
                    );
                  }).toList();
                  return sections.isEmpty
                      ? [const SizedBox.shrink()]
                      : sections;
                },
                loading: () => [const SizedBox.shrink()],
                error: (e, st) => [const SizedBox.shrink()],
              ),
          const SizedBox(height: Spacing.md),
          if (regular.isNotEmpty) ...[
            _buildSectionHeader(
              AppLocalizations.of(context)!.recent,
              regular.length,
            ),
            const SizedBox(height: Spacing.xs),
            ...regular.map(_buildTileFor),
          ],
          if (archived.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            _buildArchivedSection(archived),
          ],
        ];
        return _buildRefreshableScrollable(children: children);
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
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
          style: AppTypography.labelStyle.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(width: Spacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.surfaceContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppBorderRadius.xs),
            border: Border.all(
              color: theme.dividerColor,
              width: BorderWidth.thin,
            ),
          ),
          child: Text(
            '$count',
            style: AppTypography.tiny.copyWith(color: theme.textSecondary),
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
          AppLocalizations.of(context)!.folders,
          style: AppTypography.labelStyle.copyWith(color: theme.textSecondary),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: AppLocalizations.of(context)!.newFolder,
          icon: Icon(
            Platform.isIOS
                ? CupertinoIcons.folder_badge_plus
                : Icons.create_new_folder_outlined,
            color: theme.iconPrimary,
          ),
          onPressed: _promptCreateFolder,
        ),
      ],
    );
  }

  Future<void> _promptCreateFolder() async {
    final name = await ThemedDialogs.promptTextInput(
      context,
      title: AppLocalizations.of(context)!.newFolder,
      hintText: AppLocalizations.of(context)!.folderName,
      confirmText: AppLocalizations.of(context)!.create,
      cancelText: AppLocalizations.of(context)!.cancel,
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
      UiUtils.showMessage(
        context,
        AppLocalizations.of(context)!.failedToCreateFolder,
        isError: true,
      );
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
              AppLocalizations.of(
                context,
              )!.movedChatToFolder(details.data.title, name),
            );
          }
        } catch (_) {
          if (mounted) {
            UiUtils.showMessage(
              context,
              AppLocalizations.of(context)!.failedToMoveChat,
              isError: true,
            );
          }
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Material(
          color: isHover
              ? theme.buttonPrimary.withValues(alpha: 0.08)
              : theme.surfaceContainer.withValues(alpha: 0.05),
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
            onLongPress: () {
              HapticFeedback.selectionClick();
              _showFolderContextMenu(context, folderId, name);
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
                        ? (Platform.isIOS
                              ? CupertinoIcons.folder_open
                              : Icons.folder_open)
                        : (Platform.isIOS
                              ? CupertinoIcons.folder
                              : Icons.folder),
                    color: theme.iconPrimary,
                    size: IconSize.listItem,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      name,
                      style: AppTypography.standard.copyWith(
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
                        ? (Platform.isIOS
                              ? CupertinoIcons.chevron_up
                              : Icons.expand_less)
                        : (Platform.isIOS
                              ? CupertinoIcons.chevron_down
                              : Icons.expand_more),
                    color: theme.iconSecondary,
                    size: IconSize.listItem,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFolderContextMenu(
    BuildContext context,
    String folderId,
    String folderName,
  ) {
    final theme = context.conduitTheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surfaceBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.lg),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Platform.isIOS ? CupertinoIcons.pencil : Icons.edit_rounded,
                  color: theme.iconPrimary,
                ),
                title: Text(
                  AppLocalizations.of(context)!.rename,
                  style: TextStyle(color: theme.textPrimary),
                ),
                onTap: () async {
                  HapticFeedback.selectionClick();
                  Navigator.pop(sheetContext);
                  await _renameFolder(context, folderId, folderName);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Platform.isIOS ? CupertinoIcons.delete : Icons.delete_rounded,
                  color: theme.error,
                ),
                title: Text(
                  AppLocalizations.of(context)!.delete,
                  style: TextStyle(color: theme.error),
                ),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(sheetContext);
                  await _confirmAndDeleteFolder(context, folderId, folderName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameFolder(
    BuildContext context,
    String folderId,
    String currentName,
  ) async {
    final newName = await ThemedDialogs.promptTextInput(
      context,
      title: AppLocalizations.of(context)!.rename,
      hintText: AppLocalizations.of(context)!.folderName,
      initialValue: currentName,
      confirmText: AppLocalizations.of(context)!.save,
      cancelText: AppLocalizations.of(context)!.cancel,
    );

    if (newName == null) return;
    if (newName.isEmpty || newName == currentName) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.updateFolder(folderId, name: newName);
      HapticFeedback.selectionClick();
      ref.invalidate(foldersProvider);
    } catch (_) {
      if (!mounted) return;
      UiUtils.showMessage(
        this.context,
        'Failed to rename folder',
        isError: true,
      );
    }
  }

  Future<void> _confirmAndDeleteFolder(
    BuildContext context,
    String folderId,
    String folderName,
  ) async {
    final confirmed = await ThemedDialogs.confirm(
      context,
      title: AppLocalizations.of(context)!.deleteFolderTitle,
      message: AppLocalizations.of(context)!.deleteFolderMessage,
      confirmText: AppLocalizations.of(context)!.delete,
      isDestructive: true,
    );
    if (!confirmed) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service');
      await api.deleteFolder(folderId);
      HapticFeedback.mediumImpact();
      ref.invalidate(foldersProvider);
      ref.invalidate(conversationsProvider);
    } catch (_) {
      if (!mounted) return;
      UiUtils.showMessage(
        this.context,
        AppLocalizations.of(context)!.failedToDeleteFolder,
        isError: true,
      );
    }
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
            UiUtils.showMessage(
              context,
              'Removed "${details.data.title}" from folder',
            );
          }
        } catch (_) {
          if (mounted) {
            UiUtils.showMessage(
              context,
              AppLocalizations.of(context)!.failedToMoveChat,
              isError: true,
            );
          }
        }
      },
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: isHover
                ? theme.buttonPrimary.withValues(alpha: 0.08)
                : theme.surfaceContainer.withValues(alpha: 0.03),
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
    final theme = context.conduitTheme;
    final bool isLoadingSelected =
        (_pendingConversationId == conv.id) &&
        (ref.watch(chat.isLoadingConversationProvider) == true);
    final tile = _ConversationTile(
      title: title,
      pinned: conv.pinned == true,
      selected: isActive,
      isLoading: isLoadingSelected,
      onTap: _isLoadingConversation
          ? null
          : () => _selectConversation(context, conv.id),
      onLongPress: null,
      onMorePressed: () {
        HapticFeedback.selectionClick();
        _showConversationContextMenu(context, conv);
      },
    );
    return Padding(
      padding: EdgeInsets.only(
        bottom: Spacing.xs,
        left: inFolder ? Spacing.md : 0,
      ),
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
                color: theme.cardBackground,
                borderRadius: BorderRadius.circular(AppBorderRadius.md),
                border: Border.all(
                  color: theme.dividerColor,
                  width: BorderWidth.regular,
                ),
                boxShadow: ConduitShadows.card,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Platform.isIOS
                        ? CupertinoIcons.chat_bubble_2
                        : Icons.chat_bubble_outline,
                    size: IconSize.listItem,
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
          final hasFolder =
              (conv.folderId != null && (conv.folderId as String).isNotEmpty);
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
          color: theme.surfaceContainer.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            side: BorderSide(
              color: theme.dividerColor,
              width: BorderWidth.regular,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            onTap: () => ref.read(_showArchivedProvider.notifier).state = !show,
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
                    size: IconSize.listItem,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.archived,
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
                    size: IconSize.listItem,
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
    // Capture a provider container detached from this widget's lifecycle so
    // we can continue to read/write providers after the drawer is closed.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      // Mark global loading to show skeletons in chat
      container.read(chat.isLoadingConversationProvider.notifier).state = true;
      _pendingConversationId = id;

      // Immediately clear current chat to show loading skeleton in the chat view
      container.read(activeConversationProvider.notifier).state = null;
      container.read(chat.chatMessagesProvider.notifier).clearMessages();

      // Close the drawer immediately for faster perceived performance
      if (mounted) {
        // Prefer closing the Scaffold's drawer to avoid popping other routes
        final scaffold = Scaffold.maybeOf(context);
        if (scaffold?.isDrawerOpen == true) {
          scaffold!.closeDrawer();
        } else {
          navigator.maybePop();
        }
      }

      // Load the full conversation details in the background
      final api = container.read(apiServiceProvider);
      if (api != null) {
        final full = await api.getConversation(id);
        container.read(activeConversationProvider.notifier).state = full;
      } else {
        // Fallback: use the lightweight item to update the active conversation
        container
            .read(activeConversationProvider.notifier)
            .state = (await container.read(
          conversationsProvider.future,
        )).firstWhere((c) => c.id == id);
      }

      // Clear loading after data is ready
      container.read(chat.isLoadingConversationProvider.notifier).state = false;
      _pendingConversationId = null;
    } catch (_) {
      container.read(chat.isLoadingConversationProvider.notifier).state = false;
      _pendingConversationId = null;
    } finally {
      if (mounted) setState(() => _isLoadingConversation = false);
    }
  }

  Widget _buildBottomSection(BuildContext context) {
    final theme = context.conduitTheme;
    final currentUserAsync = ref.watch(currentUserProvider);
    final userFromProfile = currentUserAsync.maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    final dynamic authUser = ref.watch(authUserProvider);
    final user = userFromProfile ?? authUser;
    String _displayName(dynamic u) {
      if (u == null) return 'User';
      if (u is models.User) {
        return (u.name?.isNotEmpty == true ? u.name : u.username) ?? 'User';
      }
      if (u is Map) {
        final Map m = u;
        String? _asString(dynamic v) =>
            v is String && v.trim().isNotEmpty ? v.trim() : null;
        String? _pick(Map source) {
          return _asString(source['name']) ??
              _asString(source['display_name']) ??
              _asString(source['preferred_username']) ??
              _asString(source['username']);
        }

        final top = _pick(m);
        if (top != null) return top;
        final nestedUser = m['user'];
        if (nestedUser is Map) {
          final nested = _pick(nestedUser);
          if (nested != null) return nested;
          final nestedEmail = _asString(nestedUser['email']);
          if (nestedEmail != null && nestedEmail.contains('@')) {
            return nestedEmail.split('@').first;
          }
        }
        final email = _asString(m['email']);
        if (email != null && email.contains('@')) {
          return email.split('@').first;
        }
        return 'User';
      }
      // Fallback to string representation if some other type
      final s = u.toString();
      return s.isNotEmpty ? s : 'User';
    }

    String _initial(String name) {
      if (name.isEmpty) return 'U';
      final ch = name.characters.first;
      return ch.toUpperCase();
    }

    final displayName = _displayName(user);
    final initial = _initial(displayName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (user != null) ...[
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: theme.surfaceContainer.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppBorderRadius.md),
                border: Border.all(
                  color: theme.dividerColor,
                  width: BorderWidth.regular,
                ),
                boxShadow: ConduitShadows.card,
              ),
              child: Row(
                children: [
                  Container(
                    width: IconSize.avatar,
                    height: IconSize.avatar,
                    decoration: BoxDecoration(
                      color: theme.buttonPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.avatar,
                      ),
                      border: Border.all(
                        color: theme.buttonPrimary.withValues(alpha: 0.35),
                        width: BorderWidth.thin,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
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
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.standard.copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w600,
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
                  ),
                ],
              ),
            ),
          ],
        ],
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.lg),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  isPinned
                      ? (Platform.isIOS
                            ? CupertinoIcons.pin_slash
                            : Icons.push_pin_outlined)
                      : (Platform.isIOS
                            ? CupertinoIcons.pin_fill
                            : Icons.push_pin_rounded),
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
                    UiUtils.showMessage(
                      this.context,
                      AppLocalizations.of(context)!.failedToUpdatePin,
                      isError: true,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  isArchived
                      ? (Platform.isIOS
                            ? CupertinoIcons.archivebox_fill
                            : Icons.unarchive_rounded)
                      : (Platform.isIOS
                            ? CupertinoIcons.archivebox
                            : Icons.archive_rounded),
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
                    UiUtils.showMessage(
                      this.context,
                      AppLocalizations.of(context)!.failedToUpdateArchive,
                      isError: true,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Platform.isIOS ? CupertinoIcons.pencil : Icons.edit_rounded,
                  color: theme.iconPrimary,
                ),
                title: Text(
                  AppLocalizations.of(context)!.rename,
                  style: TextStyle(color: theme.textPrimary),
                ),
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
                title: Text(
                  AppLocalizations.of(context)!.delete,
                  style: TextStyle(color: theme.error),
                ),
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
    final newName = await ThemedDialogs.promptTextInput(
      context,
      title: AppLocalizations.of(context)!.renameChat,
      hintText: AppLocalizations.of(context)!.enterChatName,
      initialValue: currentTitle,
      confirmText: AppLocalizations.of(context)!.save,
      cancelText: AppLocalizations.of(context)!.cancel,
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
        ref.read(activeConversationProvider.notifier).state = active!.copyWith(
          title: newName,
        );
      }
    } catch (_) {
      if (!mounted) return;
      UiUtils.showMessage(
        this.context,
        AppLocalizations.of(context)!.failedToRenameChat,
        isError: true,
      );
    }
  }

  Future<void> _confirmAndDeleteConversation(
    BuildContext context,
    String conversationId,
  ) async {
    final confirmed = await ThemedDialogs.confirm(
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
      UiUtils.showMessage(
        this.context,
        AppLocalizations.of(context)!.failedToDeleteChat,
        isError: true,
      );
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
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMorePressed;

  const _ConversationTile({
    required this.title,
    required this.pinned,
    required this.selected,
    required this.isLoading,
    required this.onTap,
    this.onLongPress,
    this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final Color selectedBackground =
        theme.buttonPrimary.withValues(alpha: 0.10); // subtle highlight
    final Color selectedBorder = theme.buttonPrimary.withValues(alpha: 0.60);

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? selectedBackground : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          side: BorderSide(
            color: selected ? selectedBorder : theme.dividerColor,
            width: BorderWidth.regular,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          onTap: isLoading ? null : onTap,
          onLongPress: onLongPress,
          child: Stack(
            children: [
              // Left accent bar for active conversation
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                left: 0,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: selected ? 3.0 : 0.0,
                  decoration: BoxDecoration(
                    color: theme.buttonPrimary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppBorderRadius.md),
                      bottomLeft: Radius.circular(AppBorderRadius.md),
                    ),
                  ),
                ),
              ),
              Padding(
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
                        style: AppTypography.standard.copyWith(
                          color: theme.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    if (isLoading)
                      SizedBox(
                        width: IconSize.sm,
                        height: IconSize.sm,
                        child: CircularProgressIndicator(
                          strokeWidth: BorderWidth.medium,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.loadingIndicator,
                          ),
                        ),
                      )
                    else if (onMorePressed != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: TouchTarget.listItem,
                          minHeight: TouchTarget.listItem,
                        ),
                        icon: Icon(
                          Platform.isIOS
                              ? CupertinoIcons.ellipsis
                              : Icons.more_vert_rounded,
                          color: theme.iconSecondary,
                          size: IconSize.listItem,
                        ),
                        onPressed: onMorePressed,
                        tooltip: AppLocalizations.of(context)!.more,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Bottom quick actions widget removed as design now shows only profile card
