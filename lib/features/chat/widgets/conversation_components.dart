import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import '../../../core/models/conversation.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../providers/chat_providers.dart';

// Optimized delete conversation provider with error handling
final deleteConversationProvider = FutureProvider.family<void, String>((
  ref,
  conversationId,
) async {
  final api = ref.read(apiServiceProvider);
  if (api == null) throw Exception('No API service available');

  await api.deleteConversation(conversationId);
  ref.invalidate(conversationsProvider);
});

/// Optimized conversation tile with Conduit design aesthetics
class ModernConversationTile extends ConsumerStatefulWidget {
  final Conversation conversation;
  final bool isActive;
  final Future<void> Function() onTap;
  final VoidCallback onDelete;

  const ModernConversationTile({
    super.key,
    required this.conversation,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  ConsumerState<ModernConversationTile> createState() =>
      _ModernConversationTileState();
}

class _ModernConversationTileState extends ConsumerState<ModernConversationTile>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.xs,
            ),
            child: Dismissible(
              key: Key(widget.conversation.id),
              direction: DismissDirection.horizontal,
              background: _buildSwipeBackground(DismissDirection.startToEnd),
              secondaryBackground: _buildSwipeBackground(
                DismissDirection.endToStart,
              ),
              confirmDismiss: _handleDismiss,
              child: _buildTileContent(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSwipeBackground(DismissDirection direction) {
    final isArchive = direction == DismissDirection.startToEnd;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isArchive
              ? [
                  AppTheme.brandPrimary.withValues(alpha: 0.1),
                  AppTheme.brandPrimary.withValues(alpha: 0.2),
                ]
              : [
                  AppTheme.error.withValues(alpha: 0.1),
                  AppTheme.error.withValues(alpha: 0.2),
                ],
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
      ),
      alignment: isArchive ? Alignment.centerLeft : Alignment.centerRight,
      padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Container(
        width: Spacing.xxl,
        height: Spacing.xxl,
        decoration: BoxDecoration(
          color: isArchive ? AppTheme.brandPrimary : AppTheme.error,
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          boxShadow: ConduitShadows.low,
        ),
        child: Icon(
          isArchive
              ? (Platform.isIOS ? CupertinoIcons.archivebox : Icons.archive)
              : (Platform.isIOS ? CupertinoIcons.delete : Icons.delete),
          color: AppTheme.neutral50,
          size: AppTypography.headlineMedium,
        ),
      ),
    );
  }

  Future<bool?> _handleDismiss(DismissDirection direction) async {
    if (direction == DismissDirection.startToEnd) {
      await _handleArchive();
    } else {
      widget.onDelete();
    }
    return false;
  }

  Widget _buildTileContent() {
    return GestureDetector(
      onTapDown: (_) => _animationController.forward(),
      onTapUp: (_) => _animationController.reverse(),
      onTapCancel: () => _animationController.reverse(),
      onTap: _isLoading ? null : _handleTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          gradient: widget.isActive
              ? LinearGradient(
                  colors: [
                    AppTheme.brandPrimary.withValues(alpha: 0.15),
                    AppTheme.brandPrimary.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    AppTheme.neutral700.withValues(alpha: 0.6),
                    AppTheme.neutral700.withValues(alpha: 0.3),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          border: Border.all(
            color: widget.isActive
                ? AppTheme.brandPrimary.withValues(alpha: 0.3)
                : AppTheme.neutral600.withValues(alpha: 0.2),
            width: widget.isActive ? BorderWidth.medium : BorderWidth.thin,
          ),
          boxShadow: widget.isActive ? ConduitShadows.low : null,
        ),
        child: Row(
          children: [
            _buildLeadingIcon(),
            const SizedBox(width: Spacing.md),
            Expanded(child: _buildContent()),
            _buildTrailingActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingIcon() {
    if (_isLoading) {
      return SizedBox(
        width: Spacing.xl,
        height: Spacing.xl,
        child: CircularProgressIndicator.adaptive(
          strokeWidth: BorderWidth.thick,
          valueColor: AlwaysStoppedAnimation<Color>(
            widget.isActive ? AppTheme.brandPrimary : AppTheme.neutral300,
          ),
        ),
      );
    }

    return Container(
      width: Spacing.xl,
      height: Spacing.xl,
      decoration: BoxDecoration(
        gradient: widget.isActive
            ? LinearGradient(
                colors: [AppTheme.brandPrimary, AppTheme.brandPrimaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  AppTheme.neutral600.withValues(alpha: 0.8),
                  AppTheme.neutral500.withValues(alpha: 0.6),
                ],
              ),
        borderRadius: BorderRadius.circular(AppBorderRadius.sm),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Platform.isIOS
                ? CupertinoIcons.chat_bubble_2_fill
                : Icons.chat_rounded,
            color: AppTheme.neutral50,
            size: Spacing.md,
          ),
          if (widget.conversation.pinned)
            Positioned(
              top: Spacing.xxs,
              right: Spacing.xxs,
              child: Container(
                width: Spacing.sm,
                height: Spacing.sm,
                decoration: const BoxDecoration(
                  color: AppTheme.warning,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: widget.isActive ? AppTheme.neutral50 : AppTheme.neutral100,
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.bodyLarge,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Row(
          children: [
            Icon(
              Platform.isIOS ? CupertinoIcons.time : Icons.access_time_rounded,
              size: AppTypography.labelMedium,
              color: AppTheme.neutral400,
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              _formatDate(widget.conversation.updatedAt),
              style: const TextStyle(
                color: AppTheme.neutral400,
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.conversation.messages.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                width: Spacing.xxs,
                height: Spacing.xxs,
                decoration: const BoxDecoration(
                  color: AppTheme.neutral400,
                  shape: BoxShape.circle,
                ),
              ),
              Text(
                '${widget.conversation.messages.length} messages',
                style: const TextStyle(
                  color: AppTheme.neutral400,
                  fontSize: AppTypography.labelMedium,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        if (widget.conversation.tags.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          _buildTags(),
        ],
      ],
    );
  }

  Widget _buildTags() {
    return Wrap(
      spacing: Spacing.xs,
      runSpacing: Spacing.xs,
      children: widget.conversation.tags.take(3).map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xs + Spacing.xxs,
            vertical: Spacing.xxs,
          ),
          decoration: BoxDecoration(
            color: AppTheme.brandPrimary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppBorderRadius.xs),
            border: Border.all(
              color: AppTheme.brandPrimary.withValues(alpha: 0.2),
              width: BorderWidth.thin,
            ),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              color: AppTheme.brandPrimary,
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTrailingActions() {
    return PopupMenuButton<String>(
      icon: Container(
        width: Spacing.xl,
        height: Spacing.xl,
        decoration: BoxDecoration(
          color: AppTheme.neutral700.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppBorderRadius.sm),
        ),
        child: Icon(
          Platform.isIOS ? CupertinoIcons.ellipsis : Icons.more_vert_rounded,
          color: AppTheme.neutral300,
          size: Spacing.md,
        ),
      ),
      color: AppTheme.neutral800,
      elevation: Elevation.high + Spacing.xs,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        side: BorderSide(
          color: AppTheme.neutral600.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      onSelected: _handleMenuAction,
      itemBuilder: (context) => _buildMenuItems(),
    );
  }

  List<PopupMenuItem<String>> _buildMenuItems() {
    return [
      _buildMenuItem(
        'pin',
        widget.conversation.pinned
            ? (Platform.isIOS
                  ? CupertinoIcons.pin_slash
                  : Icons.push_pin_outlined)
            : (Platform.isIOS
                  ? CupertinoIcons.pin_fill
                  : Icons.push_pin_rounded),
        widget.conversation.pinned ? 'Unpin' : 'Pin',
      ),
      _buildMenuItem(
        'archive',
        Platform.isIOS ? CupertinoIcons.archivebox : Icons.archive_rounded,
        'Archive',
      ),
      _buildMenuItem(
        'share',
        Platform.isIOS ? CupertinoIcons.share : Icons.share_rounded,
        'Share',
      ),
      _buildMenuItem(
        'clone',
        Platform.isIOS ? CupertinoIcons.doc_on_doc : Icons.content_copy_rounded,
        'Clone',
      ),
      PopupMenuItem<String>(
        enabled: false,
        child: Divider(color: AppTheme.neutral600, height: BorderWidth.regular),
      ),
      _buildMenuItem(
        'delete',
        Platform.isIOS ? CupertinoIcons.delete : Icons.delete_rounded,
        'Delete',
        isDestructive: true,
      ),
    ];
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String label, {
    bool isDestructive = false,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Container(
            width: Spacing.lg + Spacing.xs,
            height: Spacing.lg + Spacing.xs,
            decoration: BoxDecoration(
              color: isDestructive
                  ? AppTheme.error.withValues(alpha: 0.1)
                  : AppTheme.neutral700.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppBorderRadius.xs),
            ),
            child: Icon(
              icon,
              size: Spacing.md,
              color: isDestructive ? AppTheme.error : AppTheme.neutral200,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            label,
            style: TextStyle(
              color: isDestructive ? AppTheme.error : AppTheme.neutral50,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTap() async {
    setState(() => _isLoading = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case 'pin':
        await _handlePin();
        break;
      case 'archive':
        await _handleArchive();
        break;
      case 'share':
        await _handleShare();
        break;
      case 'clone':
        await _handleClone();
        break;
      case 'delete':
        widget.onDelete();
        break;
    }
  }

  Future<void> _handlePin() async {
    try {
      await pinConversation(
        ref,
        widget.conversation.id,
        !widget.conversation.pinned,
      );
      if (mounted) {
        UiUtils.showMessage(
          context,
          widget.conversation.pinned
              ? 'Conversation unpinned'
              : 'Conversation pinned',
        );
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(
          context,
          'Failed to ${widget.conversation.pinned ? 'unpin' : 'pin'} conversation',
        );
      }
    }
  }

  Future<void> _handleArchive() async {
    try {
      await archiveConversation(ref, widget.conversation.id, true);
      if (mounted) {
        UiUtils.showMessage(context, 'Conversation archived');
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(context, 'Failed to archive conversation');
      }
    }
  }

  Future<void> _handleShare() async {
    try {
      final shareId = await shareConversation(ref, widget.conversation.id);
      if (mounted && shareId != null) {
        _showShareDialog(shareId);
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(context, 'Failed to share conversation');
      }
    }
  }

  Future<void> _handleClone() async {
    try {
      await cloneConversation(ref, widget.conversation.id);
      if (mounted) {
        Navigator.pop(context);
        UiUtils.showMessage(context, 'Conversation cloned');
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showMessage(context, 'Failed to clone conversation');
      }
    }
  }

  void _showShareDialog(String shareId) {
    final shareUrl =
        '${ref.read(apiServiceProvider)?.serverConfig.url}/s/$shareId';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.neutral800,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          side: BorderSide(
            color: AppTheme.neutral600.withValues(alpha: 0.3),
            width: BorderWidth.thin,
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.brandPrimary, AppTheme.brandPrimaryLight],
                ),
                borderRadius: BorderRadius.circular(AppBorderRadius.sm),
              ),
              child: const Icon(
                Icons.share_rounded,
                color: AppTheme.neutral50,
                size: Spacing.md,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            const Text(
              'Share Conversation',
              style: TextStyle(
                color: AppTheme.neutral50,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anyone with this link can view the conversation:',
              style: TextStyle(color: AppTheme.neutral300),
            ),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: AppTheme.neutral700.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppBorderRadius.md),
                border: Border.all(
                  color: AppTheme.neutral600.withValues(alpha: 0.3),
                  width: BorderWidth.thin,
                ),
              ),
              child: SelectableText(
                shareUrl,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: AppTheme.neutral50,
                  fontSize: AppTypography.labelMedium,
                ),
              ),
            ),
          ],
        ),
        actions: [
          ConduitButton(
            text: 'Close',
            isSecondary: true,
            onPressed: () => Navigator.pop(context),
          ),
          ConduitButton(
            text: 'Copy Link',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: shareUrl));
              if (context.mounted) {
                UiUtils.showMessage(context, 'Link copied to clipboard');
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();

    // Convert to local timezone if needed
    final localDate = date.toLocal();
    final localNow = now.toLocal();
    final difference = localNow.difference(localDate);

    // Handle negative differences (future dates)
    if (difference.isNegative) {
      return 'Just now';
    }

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes <= 1) {
          return 'Just now';
        }
        return '${difference.inMinutes}m';
      }
      return '${difference.inHours}h';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else if (difference.inDays < 365) {
      return '${localDate.month}/${localDate.day}';
    } else {
      return '${localDate.month}/${localDate.day}/${localDate.year}';
    }
  }
}

/// Optimized archived chats view with improved performance
class ModernArchivedChatsView extends ConsumerWidget {
  final ScrollController scrollController;

  const ModernArchivedChatsView({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedConversations = ref.watch(archivedConversationsProvider);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.neutral800, AppTheme.neutral900],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          topLeft: ui.Radius.circular(AppBorderRadius.lg),
          topRight: ui.Radius.circular(AppBorderRadius.lg),
        ),
        border: Border.all(
          color: AppTheme.neutral600.withValues(alpha: 0.2),
          width: BorderWidth.thin,
        ),
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(context),
          const Divider(color: AppTheme.neutral600, height: 1, thickness: 0.5),
          Expanded(child: _buildContent(context, archivedConversations, ref)),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
      width: Spacing.xxl,
      height: Spacing.xs,
      decoration: BoxDecoration(
        color: AppTheme.neutral500,
        borderRadius: BorderRadius.circular(AppBorderRadius.xs),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        children: [
          Container(
            width: Spacing.xxl,
            height: Spacing.xxl,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.brandPrimary, AppTheme.brandPrimaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppBorderRadius.md),
            ),
            child: const Icon(
              Icons.archive_rounded,
              color: AppTheme.neutral50,
              size: AppTypography.headlineMedium,
            ),
          ),
          const SizedBox(width: Spacing.md),
          const Expanded(
            child: Text(
              'Archived Conversations',
              style: TextStyle(
                color: AppTheme.neutral50,
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
          ),
          ConduitIconButton(
            icon: Platform.isIOS ? CupertinoIcons.xmark : Icons.close_rounded,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Conversation> conversations,
    WidgetRef ref,
  ) {
    if (conversations.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        return ModernArchivedConversationTile(
          conversation: conversation,
          onUnarchive: () => _handleUnarchive(ref, context, conversation.id),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: Spacing.xxl + Spacing.xl,
            height: Spacing.xxl + Spacing.xl,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.neutral600.withValues(alpha: 0.3),
                  AppTheme.neutral700.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(AppBorderRadius.round),
            ),
            child: const Icon(
              Icons.archive_rounded,
              size: Spacing.xxl,
              color: AppTheme.neutral400,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          const Text(
            'Nothing archived yet',
            style: TextStyle(
              color: AppTheme.neutral50,
              fontSize: AppTypography.headlineSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          const Text(
            'Conversations you archive will appear here',
            style: TextStyle(
              color: AppTheme.neutral400,
              fontSize: AppTypography.labelLarge,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _handleUnarchive(
    WidgetRef ref,
    BuildContext context,
    String conversationId,
  ) async {
    try {
      await archiveConversation(ref, conversationId, false);
      if (context.mounted) {
        UiUtils.showMessage(context, 'Conversation unarchived');
      }
    } catch (e) {
      if (context.mounted) {
        UiUtils.showMessage(context, 'Failed to unarchive conversation');
      }
    }
  }
}

/// Optimized archived conversation tile
class ModernArchivedConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onUnarchive;

  const ModernArchivedConversationTile({
    super.key,
    required this.conversation,
    required this.onUnarchive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.neutral700.withValues(alpha: 0.4),
              AppTheme.neutral700.withValues(alpha: 0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          border: Border.all(
            color: AppTheme.neutral600.withValues(alpha: 0.2),
            width: BorderWidth.thin,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.neutral600.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppBorderRadius.sm),
              ),
              child: const Icon(
                Icons.archive_rounded,
                color: AppTheme.neutral300,
                size: 16,
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.neutral50,
                      fontWeight: FontWeight.w600,
                      fontSize: AppTypography.bodyLarge,
                    ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    _formatArchivedDate(conversation.updatedAt),
                    style: const TextStyle(
                      color: AppTheme.neutral400,
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            ConduitIconButton(
              icon: Platform.isIOS
                  ? CupertinoIcons.arrow_up_bin
                  : Icons.unarchive_rounded,
              onPressed: onUnarchive,
              tooltip: 'Unarchive',
            ),
          ],
        ),
      ),
    );
  }

  String _formatArchivedDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
