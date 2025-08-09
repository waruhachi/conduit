import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/utils/ui_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/folder.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/app_providers.dart';

class FolderManagementDialog extends ConsumerStatefulWidget {
  final Conversation? conversation;

  const FolderManagementDialog({super.key, this.conversation});

  @override
  ConsumerState<FolderManagementDialog> createState() =>
      _FolderManagementDialogState();
}

class _FolderManagementDialogState
    extends ConsumerState<FolderManagementDialog> {
  final _nameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(foldersProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: context.conduitTheme.cardBackground,
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          border: Border.all(
            color: context.conduitTheme.cardBorder.withValues(alpha: 0.3),
            width: BorderWidth.thin,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.conduitTheme.buttonPrimary,
                    context.conduitTheme.buttonPrimary.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppBorderRadius.xl),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.conduitTheme.textInverse.withValues(
                        alpha: 0.2,
                      ),
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                    ),
                    child: Icon(
                      Platform.isIOS
                          ? CupertinoIcons.folder
                          : Icons.folder_rounded,
                      color: context.conduitTheme.textInverse,
                      size: IconSize.md,
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      widget.conversation != null
                          ? 'Move to Folder'
                          : 'Manage Folders',
                      style: TextStyle(
                        color: context.conduitTheme.textInverse,
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ConduitIconButton(
                    icon: Platform.isIOS
                        ? CupertinoIcons.xmark
                        : Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Create new folder section
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.conduitTheme.inputBackground,
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                        border: Border.all(
                          color: context.conduitTheme.inputBorder,
                          width: BorderWidth.thin,
                        ),
                      ),
                      child: TextField(
                        controller: _nameController,
                        style: TextStyle(
                          color: context.conduitTheme.inputText,
                          fontSize: AppTypography.bodyLarge,
                        ),
                        decoration: InputDecoration(
                          hintText: 'New folder name',
                          hintStyle: TextStyle(
                            color: context.conduitTheme.inputPlaceholder
                                .withValues(alpha: 0.5),
                            fontSize: AppTypography.bodyLarge,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md,
                            vertical: Spacing.sm,
                          ),
                          prefixIcon: Icon(
                            Platform.isIOS
                                ? CupertinoIcons.folder_badge_plus
                                : Icons.create_new_folder_rounded,
                            color: context.conduitTheme.iconSecondary,
                            size: IconSize.md,
                          ),
                        ),
                        onSubmitted: (_) => _createFolder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  ConduitButton(
                    text: 'Create',
                    onPressed: _isCreating ? null : _createFolder,
                    isLoading: _isCreating,
                    width: 80,
                  ),
                ],
              ),
            ),

            // Divider
            Container(
              height: 0.5,
              margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              color: context.conduitTheme.dividerColor.withValues(alpha: 0.3),
            ),

            // Folders list
            Expanded(
              child: folders.when(
                data: (folderList) => folderList.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.sm,
                        ),
                        itemCount: folderList.length,
                        itemBuilder: (context, index) {
                          final folder = folderList[index];
                          return _buildFolderTile(folder);
                        },
                      ),
                loading: () => _buildLoadingState(),
                error: (error, _) => _buildErrorState(error),
              ),
            ),

            // Bottom actions
            if (widget.conversation != null) ...[
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                color: context.conduitTheme.dividerColor.withValues(alpha: 0.3),
              ),
              Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: ConduitButton(
                        text: 'Remove from Folder',
                        onPressed: () => _moveToFolder(null),
                        isSecondary: true,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: ConduitButton(
                        text: 'Cancel',
                        onPressed: () => Navigator.pop(context),
                        isSecondary: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.conduitTheme.cardBackground.withValues(
                  alpha: 0.6,
                ),
                borderRadius: BorderRadius.circular(AppBorderRadius.round),
              ),
              child: Icon(
                Platform.isIOS ? CupertinoIcons.folder : Icons.folder_outlined,
                size: 40,
                color: context.conduitTheme.iconSecondary,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'No folders yet',
              style: TextStyle(
                color: context.conduitTheme.textPrimary,
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Create a folder to organize\nyour conversations',
              style: TextStyle(
                color: context.conduitTheme.textSecondary,
                fontSize: AppTypography.labelLarge,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator.adaptive(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              context.conduitTheme.buttonPrimary,
            ),
          ),
          SizedBox(height: Spacing.lg),
          Text(
            'Loading folders...',
            style: TextStyle(
              color: context.conduitTheme.textSecondary,
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.conduitTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppBorderRadius.round),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: context.conduitTheme.error,
              ),
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Failed to load folders',
              style: TextStyle(
                color: context.conduitTheme.textPrimary,
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              error.toString(),
              style: TextStyle(
                color: context.conduitTheme.textSecondary,
                fontSize: AppTypography.labelLarge,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderTile(Folder folder) {
    final isSelected = widget.conversation?.folderId == folder.id;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.xs,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.conversation != null
              ? () => _moveToFolder(folder.id)
              : null,
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          child: Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isSelected
                  ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.1)
                  : context.conduitTheme.cardBackground.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppBorderRadius.md),
              border: Border.all(
                color: isSelected
                    ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.3)
                    : context.conduitTheme.cardBorder.withValues(alpha: 0.2),
                width: BorderWidth.thin,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.conduitTheme.buttonPrimary.withValues(
                            alpha: 0.2,
                          )
                        : context.conduitTheme.cardBorder.withValues(
                            alpha: 0.6,
                          ),
                    borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                  ),
                  child: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.folder_fill
                        : Icons.folder_rounded,
                    color: isSelected
                        ? context.conduitTheme.buttonPrimary
                        : context.conduitTheme.iconSecondary,
                    size: IconSize.md,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: TextStyle(
                          color: isSelected
                              ? context.conduitTheme.buttonPrimary
                              : context.conduitTheme.textPrimary,
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        '${folder.conversationIds.length} conversations',
                        style: TextStyle(
                          color: context.conduitTheme.textSecondary,
                          fontSize: AppTypography.labelMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.conversation != null && isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: context.conduitTheme.buttonPrimary,
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.round,
                      ),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: context.conduitTheme.textInverse,
                      size: 16,
                    ),
                  )
                else if (widget.conversation == null)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: context.conduitTheme.iconSecondary,
                      size: IconSize.md,
                    ),
                    color: context.conduitTheme.cardBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      side: BorderSide(
                        color: context.conduitTheme.cardBorder.withValues(
                          alpha: 0.3,
                        ),
                        width: BorderWidth.thin,
                      ),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _renameFolder(folder);
                          break;
                        case 'delete':
                          _deleteFolder(folder);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: context.conduitTheme.iconSecondary,
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              'Rename',
                              style: TextStyle(
                                color: context.conduitTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_rounded,
                              size: 18,
                              color: context.conduitTheme.error,
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              'Delete',
                              style: TextStyle(
                                color: context.conduitTheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service available');

      await api.createFolder(name: name);
      ref.invalidate(foldersProvider);
      _nameController.clear();

      if (mounted) {
        UiUtils.showMessage(context, 'Folder "$name" created');
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(context, 'Error creating folder: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _moveToFolder(String? folderId) async {
    if (widget.conversation == null) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service available');

      await api.moveConversationToFolder(widget.conversation!.id, folderId);
      ref.invalidate(conversationsProvider);
      ref.invalidate(foldersProvider);

      if (mounted) {
        Navigator.pop(context);
        UiUtils.showMessage(
          context,
          folderId != null
              ? 'Conversation moved to folder'
              : 'Conversation removed from folder',
        );
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(context, 'Error moving conversation: $e');
      }
    }
  }

  void _renameFolder(Folder folder) async {
    final controller = TextEditingController(text: folder.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.neutral700,
        title: Text(
          'Rename Folder',
          style: TextStyle(color: context.conduitTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: context.conduitTheme.inputText),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(
              color: context.conduitTheme.inputPlaceholder.withValues(
                alpha: 0.5,
              ),
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: context.conduitTheme.inputBorder.withValues(alpha: 0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: context.conduitTheme.inputBorder.withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: context.conduitTheme.buttonPrimary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: context.conduitTheme.textPrimary.withValues(alpha: 0.7),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: context.conduitTheme.buttonPrimary,
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != folder.name) {
      try {
        final api = ref.read(apiServiceProvider);
        if (api != null) {
          await api.updateFolder(folder.id, name: result);
          ref.invalidate(foldersProvider);

          if (mounted) {
            UiUtils.showMessage(context, 'Folder renamed to "$result"');
          }
        }
      } catch (e) {
        if (mounted) {
          UiUtils.showMessage(context, 'Failed to rename folder: $e');
        }
      }
    }

    controller.dispose();
  }

  void _deleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.conduitTheme.cardBackground,
        title: Text(
          'Delete Folder',
          style: TextStyle(color: context.conduitTheme.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${folder.name}"?\n\nThis action cannot be undone. Conversations in this folder will be moved to the main folder.',
          style: TextStyle(color: context.conduitTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: context.conduitTheme.textPrimary.withValues(alpha: 0.7),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.conduitTheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiServiceProvider);
        if (api != null) {
          await api.deleteFolder(folder.id);
          ref.invalidate(foldersProvider);
          ref.invalidate(conversationsProvider);

          if (mounted) {
            UiUtils.showMessage(context, 'Folder "${folder.name}" deleted');
          }
        }
      } catch (e) {
        if (mounted) {
          UiUtils.showMessage(context, 'Failed to delete folder: $e');
        }
      }
    }
  }
}
