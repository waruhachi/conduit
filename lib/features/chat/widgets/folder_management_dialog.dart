import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  final BuildContext? parentContext;

  const FolderManagementDialog({super.key, this.conversation, this.parentContext});

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
    final isMovingConversation = widget.conversation != null;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 680),
          decoration: BoxDecoration(
            color: context.conduitTheme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.modal),
            border: Border.all(
              color: context.conduitTheme.cardBorder.withValues(alpha: 0.2),
              width: BorderWidth.regular,
            ),
            boxShadow: ConduitShadows.modal,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modern Header
              _buildModernHeader(context, isMovingConversation),

              // Content Section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Create folder section (only if managing folders)
                    if (!isMovingConversation) ...[
                      _buildCreateFolderSection(context),
                      ConduitDivider(color: context.conduitTheme.dividerColor.withValues(alpha: 0.2)),
                    ],

                    // Folders list
                    Expanded(
                      child: folders.when(
                        data: (folderList) => _buildFoldersList(context, folderList, isMovingConversation),
                        loading: () => _buildLoadingState(context),
                        error: (error, _) => _buildErrorState(context, error),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom actions (only for conversation moving)
              if (isMovingConversation) _buildBottomActions(context),
            ],
          ),
        ).animate().slideY(
          begin: 0.1,
          duration: AnimationDuration.modalPresentation,
          curve: AnimationCurves.modalPresentation,
        ).fadeIn(
          duration: AnimationDuration.modalPresentation,
          curve: AnimationCurves.easeOut,
        ),
      ),
    );
  }

  // Modern header with clean design
  Widget _buildModernHeader(BuildContext context, bool isMovingConversation) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: context.conduitTheme.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.modal),
        ),
        border: Border(
          bottom: BorderSide(
            color: context.conduitTheme.dividerColor.withValues(alpha: 0.1),
            width: BorderWidth.regular,
          ),
        ),
      ),
      child: Row(
        children: [
          // Modern icon container
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.conduitTheme.buttonPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppBorderRadius.lg),
            ),
            child: Icon(
              Platform.isIOS ? CupertinoIcons.folder_fill : Icons.folder_rounded,
              color: context.conduitTheme.buttonPrimary,
              size: IconSize.medium,
            ),
          ),
          const SizedBox(width: Spacing.md),
          
          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMovingConversation ? 'Move to Folder' : 'Manage Folders',
                  style: AppTypography.headlineMediumStyle.copyWith(
                    color: context.conduitTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  isMovingConversation 
                      ? 'Select a folder for "${widget.conversation?.title ?? 'this conversation'}"'
                      : 'Create and organize your conversation folders',
                  style: AppTypography.bodyMediumStyle.copyWith(
                    color: context.conduitTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          
          // Close button
          ConduitIconButton(
            icon: Platform.isIOS ? CupertinoIcons.xmark : Icons.close_rounded,
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  // Create folder section with improved UX
  Widget _buildCreateFolderSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl, vertical: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create New Folder',
            style: AppTypography.bodyMediumStyle.copyWith(
              color: context.conduitTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: AccessibleFormField(
                  controller: _nameController,
                  hint: 'Enter folder name',
                  prefixIcon: Icon(
                    Platform.isIOS 
                        ? CupertinoIcons.folder_badge_plus 
                        : Icons.create_new_folder_rounded,
                    color: context.conduitTheme.iconSecondary,
                    size: IconSize.medium,
                  ),
                  onSubmitted: (_) => _createFolder(),
                  isCompact: true,
                ),
              ),
              const SizedBox(width: Spacing.md),
              ConduitButton(
                text: 'Create',
                onPressed: _isCreating ? null : _createFolder,
                isLoading: _isCreating,
                icon: Platform.isIOS ? CupertinoIcons.add : Icons.add_rounded,
                isCompact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Enhanced folders list
  Widget _buildFoldersList(BuildContext context, List<Folder> folderList, bool isMovingConversation) {
    if (folderList.isEmpty) {
      return _buildEmptyState(context, isMovingConversation);
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.xl,
        vertical: Spacing.md,
      ),
      itemCount: folderList.length,
      separatorBuilder: (context, index) => const SizedBox(height: Spacing.xs),
      itemBuilder: (context, index) {
        final folder = folderList[index];
        return _buildFolderTile(folder, index).animate(delay: Duration(milliseconds: index * 50))
            .slideX(begin: 0.2, duration: AnimationDuration.fast)
            .fadeIn(duration: AnimationDuration.fast);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isMovingConversation) {
    return ConduitEmptyState(
      icon: Platform.isIOS ? CupertinoIcons.folder : Icons.folder_outlined,
      title: 'No folders yet',
      message: isMovingConversation 
          ? 'Create a folder first'
          : 'Use the form above to create your first folder',
      isCompact: true,
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: ConduitLoadingIndicator(
          message: 'Loading folders...',
          size: IconSize.xl,
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return ConduitEmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Failed to load folders',
      message: 'Please check your connection and try again',
      isCompact: true,
      action: ConduitButton(
        text: 'Retry',
        onPressed: () => ref.invalidate(foldersProvider),
        icon: Icons.refresh_rounded,
        isCompact: true,
      ),
    );
  }

  // Bottom actions for conversation moving
  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: context.conduitTheme.cardBackground,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppBorderRadius.modal),
        ),
        border: Border(
          top: BorderSide(
            color: context.conduitTheme.dividerColor.withValues(alpha: 0.1),
            width: BorderWidth.regular,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ConduitButton(
              text: 'Remove from Folder',
              onPressed: () => _moveToFolder(null),
              isSecondary: true,
              icon: Platform.isIOS ? CupertinoIcons.folder_badge_minus : Icons.folder_off_rounded,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: ConduitButton(
              text: 'Cancel',
              onPressed: () => Navigator.pop(context),
              isSecondary: true,
              icon: Platform.isIOS ? CupertinoIcons.xmark : Icons.close_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(Folder folder, int index) {
    final isSelected = widget.conversation?.folderId == folder.id;
    final isMovingConversation = widget.conversation != null;

    return ConduitCard(
      onTap: isMovingConversation ? () => _moveToFolder(folder.id) : null,
      isSelected: isSelected,
      child: ConduitListItem(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected
                ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.15)
                : context.conduitTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
            border: isSelected ? Border.all(
              color: context.conduitTheme.buttonPrimary.withValues(alpha: 0.3),
              width: BorderWidth.regular,
            ) : null,
          ),
          child: Icon(
            Platform.isIOS ? CupertinoIcons.folder_fill : Icons.folder_rounded,
            color: isSelected
                ? context.conduitTheme.buttonPrimary
                : context.conduitTheme.iconSecondary,
            size: IconSize.lg,
          ),
        ),
        title: Text(
          folder.name,
          style: AppTypography.bodyLargeStyle.copyWith(
            color: isSelected
                ? context.conduitTheme.buttonPrimary
                : context.conduitTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(
              Platform.isIOS ? CupertinoIcons.chat_bubble_2 : Icons.chat_bubble_outline_rounded,
              size: IconSize.xs,
              color: context.conduitTheme.textTertiary,
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              '${folder.conversationIds.length} conversation${folder.conversationIds.length != 1 ? 's' : ''}',
              style: AppTypography.bodySmallStyle.copyWith(
                color: context.conduitTheme.textSecondary,
              ),
            ),
            if (folder.conversationIds.isNotEmpty) ...[
              const SizedBox(width: Spacing.sm),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: context.conduitTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                'Active',
                style: AppTypography.captionStyle.copyWith(
                  color: context.conduitTheme.success,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        trailing: _buildFolderActions(folder, isSelected, isMovingConversation),
        isSelected: isSelected,
      ),
    );
  }

  Widget _buildFolderActions(Folder folder, bool isSelected, bool isMovingConversation) {
    if (isMovingConversation) {
      return isSelected
          ? Container(
              padding: const EdgeInsets.all(Spacing.xs),
              decoration: BoxDecoration(
                color: context.conduitTheme.buttonPrimary,
                borderRadius: BorderRadius.circular(AppBorderRadius.round),
              ),
              child: Icon(
                Platform.isIOS ? CupertinoIcons.checkmark : Icons.check_rounded,
                color: context.conduitTheme.buttonPrimaryText,
                size: IconSize.small,
              ),
            )
          : Icon(
              Platform.isIOS ? CupertinoIcons.chevron_right : Icons.arrow_forward_ios_rounded,
              color: context.conduitTheme.iconSecondary.withValues(alpha: 0.6),
              size: IconSize.small,
            );
    }

    // Management mode - show actions menu
    return PopupMenuButton<String>(
      icon: Icon(
        Platform.isIOS ? CupertinoIcons.ellipsis : Icons.more_vert_rounded,
        color: context.conduitTheme.iconSecondary,
        size: IconSize.medium,
      ),
      color: context.conduitTheme.surfaceBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        side: BorderSide(
          color: context.conduitTheme.cardBorder.withValues(alpha: 0.2),
          width: BorderWidth.regular,
        ),
      ),
      elevation: Elevation.medium,
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
                Platform.isIOS ? CupertinoIcons.pencil : Icons.edit_rounded,
                size: IconSize.small,
                color: context.conduitTheme.iconSecondary,
              ),
              const SizedBox(width: Spacing.md),
              Text(
                'Rename',
                style: AppTypography.bodyMediumStyle.copyWith(
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
                Platform.isIOS ? CupertinoIcons.delete : Icons.delete_outline_rounded,
                size: IconSize.small,
                color: context.conduitTheme.error,
              ),
              const SizedBox(width: Spacing.md),
              Text(
                'Delete',
                style: AppTypography.bodyMediumStyle.copyWith(
                  color: context.conduitTheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
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
        UiUtils.showMessage(widget.parentContext ?? context, 'Folder "$name" created');
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(widget.parentContext ?? context, 'Error creating folder: $e');
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
          widget.parentContext ?? context,
          folderId != null
              ? 'Conversation moved to folder'
              : 'Conversation removed from folder',
        );
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(widget.parentContext ?? context, 'Error moving conversation: $e');
      }
    }
  }

  void _renameFolder(Folder folder) async {
    final controller = TextEditingController(text: folder.name);
    
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.ltr,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
          width: 400,
          decoration: BoxDecoration(
            color: dialogContext.conduitTheme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.modal),
            border: Border.all(
              color: dialogContext.conduitTheme.cardBorder.withValues(alpha: 0.2),
              width: BorderWidth.regular,
            ),
            boxShadow: ConduitShadows.modal,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(Spacing.xl),
                decoration: BoxDecoration(
                  color: dialogContext.conduitTheme.cardBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppBorderRadius.modal),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: dialogContext.conduitTheme.dividerColor.withValues(alpha: 0.1),
                      width: BorderWidth.regular,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: dialogContext.conduitTheme.buttonPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                      ),
                      child: Icon(
                        Platform.isIOS ? CupertinoIcons.pencil : Icons.edit_rounded,
                        color: dialogContext.conduitTheme.buttonPrimary,
                        size: IconSize.medium,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rename Folder',
                            style: AppTypography.headlineSmallStyle.copyWith(
                              color: dialogContext.conduitTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            'Enter a new name for your folder',
                            style: AppTypography.bodyMediumStyle.copyWith(
                              color: dialogContext.conduitTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: AccessibleFormField(
                  controller: controller,
                  label: 'Folder Name',
                  hint: 'Enter folder name',
                  autofocus: true,
                  isRequired: true,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.pop(dialogContext, value.trim());
                    }
                  },
                ),
              ),
              
              // Actions
              Container(
                padding: const EdgeInsets.all(Spacing.xl),
                decoration: BoxDecoration(
                  color: dialogContext.conduitTheme.cardBackground,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppBorderRadius.modal),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: dialogContext.conduitTheme.dividerColor.withValues(alpha: 0.1),
                      width: BorderWidth.regular,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ConduitButton(
                        text: 'Cancel',
                        onPressed: () => Navigator.pop(dialogContext),
                        isSecondary: true,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: ConduitButton(
                        text: 'Rename',
                        onPressed: () {
                          final newName = controller.text.trim();
                          if (newName.isNotEmpty) {
                            Navigator.pop(dialogContext, newName);
                          }
                        },
                        icon: Platform.isIOS ? CupertinoIcons.checkmark : Icons.check_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate().slideY(
        begin: 0.1,
        duration: AnimationDuration.modalPresentation,
        curve: AnimationCurves.modalPresentation,
      ).fadeIn(
        duration: AnimationDuration.modalPresentation,
        curve: AnimationCurves.easeOut,
      ),
    ),
  );

    if (result != null && result.isNotEmpty && result != folder.name) {
      try {
        final api = ref.read(apiServiceProvider);
        if (api != null) {
          await api.updateFolder(folder.id, name: result);
          ref.invalidate(foldersProvider);

          if (mounted) {
            UiUtils.showMessage(widget.parentContext ?? context, 'Folder renamed to "$result"');
          }
        }
      } catch (e) {
        if (mounted) {
          UiUtils.showMessage(widget.parentContext ?? context, 'Failed to rename folder: $e');
        }
      }
    }

    controller.dispose();
  }

  void _deleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.ltr,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
          width: 400,
          decoration: BoxDecoration(
            color: dialogContext.conduitTheme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.modal),
            border: Border.all(
              color: dialogContext.conduitTheme.cardBorder.withValues(alpha: 0.2),
              width: BorderWidth.regular,
            ),
            boxShadow: ConduitShadows.modal,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(Spacing.xl),
                decoration: BoxDecoration(
                  color: dialogContext.conduitTheme.cardBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppBorderRadius.modal),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: dialogContext.conduitTheme.dividerColor.withValues(alpha: 0.1),
                      width: BorderWidth.regular,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: dialogContext.conduitTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                      ),
                      child: Icon(
                        Platform.isIOS ? CupertinoIcons.delete : Icons.delete_outline_rounded,
                        color: dialogContext.conduitTheme.error,
                        size: IconSize.medium,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delete Folder',
                            style: AppTypography.headlineSmallStyle.copyWith(
                              color: dialogContext.conduitTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            'This action cannot be undone',
                            style: AppTypography.bodyMediumStyle.copyWith(
                              color: dialogContext.conduitTheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Spacing.md),
                      decoration: BoxDecoration(
                        color: dialogContext.conduitTheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                        border: Border.all(
                          color: dialogContext.conduitTheme.dividerColor.withValues(alpha: 0.2),
                          width: BorderWidth.regular,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Platform.isIOS ? CupertinoIcons.folder_fill : Icons.folder_rounded,
                            color: dialogContext.conduitTheme.iconSecondary,
                            size: IconSize.medium,
                          ),
                          const SizedBox(width: Spacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  folder.name,
                                  style: AppTypography.bodyLargeStyle.copyWith(
                                    color: dialogContext.conduitTheme.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: Spacing.xs),
                                Text(
                                  '${folder.conversationIds.length} conversation${folder.conversationIds.length != 1 ? 's' : ''}',
                                  style: AppTypography.bodySmallStyle.copyWith(
                                    color: dialogContext.conduitTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text(
                      'Are you sure you want to delete this folder?',
                      style: AppTypography.bodyLargeStyle.copyWith(
                        color: dialogContext.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      folder.conversationIds.isNotEmpty 
                          ? 'All conversations in this folder will be moved to the main chat list.'
                          : 'This folder is empty and will be permanently deleted.',
                      style: AppTypography.bodyMediumStyle.copyWith(
                        color: dialogContext.conduitTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Actions
              Container(
                padding: const EdgeInsets.all(Spacing.xl),
                decoration: BoxDecoration(
                  color: dialogContext.conduitTheme.cardBackground,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppBorderRadius.modal),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: dialogContext.conduitTheme.dividerColor.withValues(alpha: 0.1),
                      width: BorderWidth.regular,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ConduitButton(
                        text: 'Cancel',
                        onPressed: () => Navigator.pop(dialogContext, false),
                        isSecondary: true,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: ConduitButton(
                        text: 'Delete Folder',
                        onPressed: () => Navigator.pop(dialogContext, true),
                        isDestructive: true,
                        icon: Platform.isIOS ? CupertinoIcons.delete : Icons.delete_outline_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate().slideY(
        begin: 0.1,
        duration: AnimationDuration.modalPresentation,
        curve: AnimationCurves.modalPresentation,
      ).fadeIn(
        duration: AnimationDuration.modalPresentation,
        curve: AnimationCurves.easeOut,
      ),
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
            UiUtils.showMessage(widget.parentContext ?? context, 'Folder "${folder.name}" deleted');
          }
        }
      } catch (e) {
        if (mounted) {
          UiUtils.showMessage(widget.parentContext ?? context, 'Failed to delete folder: $e');
        }
      }
    }
  }
}
