import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/utils/platform_utils.dart';

import '../services/message_batch_service.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers/app_providers.dart';
import '../providers/chat_providers.dart';
import '../../../shared/widgets/themed_dialogs.dart';

/// Batch operations toolbar that appears when messages are selected
class MessageBatchToolbar extends ConsumerWidget {
  final List<ChatMessage> selectedMessages;
  final VoidCallback? onCancel;

  const MessageBatchToolbar({
    super.key,
    required this.selectedMessages,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conduitTheme = context.conduitTheme;
    final selectedCount = selectedMessages.length;

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: conduitTheme.cardBackground,
        border: Border(
          top: BorderSide(color: conduitTheme.cardBorder, width: 1),
        ),
        boxShadow: ConduitShadows.medium,
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Selected count
            Expanded(
              child: Text(
                '$selectedCount message${selectedCount == 1 ? '' : 's'} selected',
                style: conduitTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Action buttons
            _buildActionButton(
              icon: Platform.isIOS
                  ? CupertinoIcons.doc_on_clipboard
                  : Icons.copy,
              label: 'Copy',
              onPressed: () => _showCopyOptions(context, ref),
            ),

            const SizedBox(width: Spacing.sm),

            _buildActionButton(
              icon: Platform.isIOS ? CupertinoIcons.share : Icons.share,
              label: 'Export',
              onPressed: () => _showExportOptions(context, ref),
            ),

            const SizedBox(width: Spacing.sm),

            _buildActionButton(
              icon: Platform.isIOS
                  ? CupertinoIcons.ellipsis_circle
                  : Icons.more_vert,
              label: 'More',
              onPressed: () => _showMoreOptions(context, ref),
            ),

            const SizedBox(width: Spacing.sm),

            // Cancel button
            GestureDetector(
              onTap: () {
                PlatformUtils.lightHaptic();
                onCancel?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.neutral50.withValues(alpha: Alpha.subtle),
                  borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppTheme.neutral50.withValues(alpha: 0.8),
                    fontSize: AppTypography.labelLarge,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(
      begin: 1,
      end: 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: () {
        PlatformUtils.lightHaptic();
        onPressed();
      },
      child: Container(
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: AppTheme.neutral50.withValues(alpha: Alpha.subtle),
          borderRadius: BorderRadius.circular(AppBorderRadius.sm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: AppTheme.neutral50.withValues(alpha: 0.8),
              size: IconSize.md,
            ),
            const SizedBox(height: Spacing.xxs),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.neutral50.withValues(alpha: 0.8),
                fontSize: AppTypography.labelSmall,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCopyOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => CopyOptionsSheet(messages: selectedMessages),
    );
  }

  void _showExportOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ExportOptionsSheet(messages: selectedMessages),
    );
  }

  void _showMoreOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => MoreOptionsSheet(messages: selectedMessages),
    );
  }
}

/// Copy options bottom sheet
class CopyOptionsSheet extends ConsumerWidget {
  final List<ChatMessage> messages;

  const CopyOptionsSheet({super.key, required this.messages});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conduitTheme = context.conduitTheme;

    return Container(
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.lg),
        ),
        boxShadow: ConduitShadows.modal,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: Spacing.sm),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.conduitTheme.dividerColor,
                borderRadius: BorderRadius.circular(AppBorderRadius.xs),
              ),
            ),

            const SizedBox(height: Spacing.lg - Spacing.xs),

            // Title
            Text('Copy Messages', style: conduitTheme.headingMedium),

            const SizedBox(height: Spacing.lg - Spacing.xs),

            // Copy options
            _buildCopyOption(
              context,
              ref,
              icon: Icons.text_fields,
              title: 'Plain Text',
              subtitle: 'Copy as plain text',
              format: CopyFormat.plain,
            ),

            _buildCopyOption(
              context,
              ref,
              icon: Icons.code,
              title: 'Markdown',
              subtitle: 'Copy with formatting',
              format: CopyFormat.markdown,
            ),

            _buildCopyOption(
              context,
              ref,
              icon: Icons.data_object,
              title: 'JSON',
              subtitle: 'Copy as structured data',
              format: CopyFormat.json,
            ),

            const SizedBox(height: Spacing.lg - Spacing.xs),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyOption(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String subtitle,
    required CopyFormat format,
  }) {
    return ListTile(
      leading: Icon(icon, color: context.conduitTheme.iconSecondary),
      title: Text(
        title,
        style: context.conduitTheme.bodyLarge?.copyWith(
          color: context.conduitTheme.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: context.conduitTheme.bodySmall?.copyWith(
          color: context.conduitTheme.textSecondary,
        ),
      ),
      onTap: () async {
        Navigator.pop(context);
        await _copyMessages(context, ref, format);
      },
    );
  }

  Future<void> _copyMessages(
    BuildContext context,
    WidgetRef ref,
    CopyFormat format,
  ) async {
    try {
      final batchService = ref.read(messageBatchServiceProvider);
      final result = await batchService.copyMessages(
        messages: messages,
        format: format,
      );

      if (result.success) {
        final content = result.data?['content'] as String?;
        if (content != null) {
          await Clipboard.setData(ClipboardData(text: content));

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${messages.length} messages copied to clipboard',
                ),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to copy messages: ${result.error}'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error copying messages: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}

/// Export options bottom sheet
class ExportOptionsSheet extends ConsumerWidget {
  final List<ChatMessage> messages;

  const ExportOptionsSheet({super.key, required this.messages});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conduitTheme = context.conduitTheme;

    return Container(
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.lg),
        ),
        boxShadow: ConduitShadows.modal,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: Spacing.sm),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.conduitTheme.dividerColor,
                borderRadius: BorderRadius.circular(AppBorderRadius.xs),
              ),
            ),

            const SizedBox(height: Spacing.lg - Spacing.xs),

            // Title
            Text('Export Messages', style: conduitTheme.headingMedium),

            const SizedBox(height: Spacing.lg - Spacing.xs),

            // Export options
            _buildExportOption(
              context,
              ref,
              icon: Icons.text_fields,
              title: 'Text File',
              subtitle: 'Export as plain text (.txt)',
              format: ExportFormat.text,
            ),

            _buildExportOption(
              context,
              ref,
              icon: Icons.code,
              title: 'Markdown',
              subtitle: 'Export with formatting (.md)',
              format: ExportFormat.markdown,
            ),

            _buildExportOption(
              context,
              ref,
              icon: Icons.data_object,
              title: 'JSON',
              subtitle: 'Export as structured data (.json)',
              format: ExportFormat.json,
            ),

            _buildExportOption(
              context,
              ref,
              icon: Icons.table_chart,
              title: 'CSV',
              subtitle: 'Export as spreadsheet (.csv)',
              format: ExportFormat.csv,
            ),

            const SizedBox(height: Spacing.lg - Spacing.xs),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String subtitle,
    required ExportFormat format,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.neutral50.withValues(alpha: 0.8)),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.neutral50,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppTheme.neutral50.withValues(alpha: Alpha.strong),
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        _showExportDialog(context, ref, format);
      },
    );
  }

  void _showExportDialog(
    BuildContext context,
    WidgetRef ref,
    ExportFormat format,
  ) {
    showDialog(
      context: context,
      builder: (context) => ExportDialog(messages: messages, format: format),
    );
  }
}

/// More options bottom sheet for additional batch operations
class MoreOptionsSheet extends ConsumerWidget {
  final List<ChatMessage> messages;

  const MoreOptionsSheet({super.key, required this.messages});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conduitTheme = context.conduitTheme;

    return Container(
      decoration: BoxDecoration(
        color: conduitTheme.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.lg),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: Spacing.sm),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.neutral50.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppBorderRadius.xs),
              ),
            ),

            const SizedBox(height: Spacing.lg - Spacing.xs),

            // Title
            Text('More Actions', style: conduitTheme.headingMedium),

            const SizedBox(height: Spacing.lg - Spacing.xs),

            // More options
            ListTile(
              leading: Icon(
                Icons.label_outline,
                color: context.conduitTheme.iconSecondary,
              ),
              title: Text(
                'Add Tags',
                style: context.conduitTheme.bodyLarge?.copyWith(
                  color: context.conduitTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Tag selected messages',
                style: context.conduitTheme.bodySmall?.copyWith(
                  color: context.conduitTheme.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showTagDialog(context, ref);
              },
            ),

            ListTile(
              leading: Icon(
                Icons.archive_outlined,
                color: context.conduitTheme.iconSecondary,
              ),
              title: Text(
                'Archive',
                style: context.conduitTheme.bodyLarge?.copyWith(
                  color: context.conduitTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Archive selected messages',
                style: context.conduitTheme.bodySmall?.copyWith(
                  color: context.conduitTheme.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _archiveMessages(context, ref);
              },
            ),

            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: context.conduitTheme.error,
              ),
              title: Text(
                'Delete',
                style: context.conduitTheme.bodyLarge?.copyWith(
                  color: context.conduitTheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Delete selected messages',
                style: context.conduitTheme.bodySmall?.copyWith(
                  color: context.conduitTheme.textSecondary,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(context, ref);
              },
            ),

            const SizedBox(height: Spacing.lg - Spacing.xs),
          ],
        ),
      ),
    );
  }

  void _showTagDialog(BuildContext context, WidgetRef ref) async {
    final activeConversation = ref.read(activeConversationProvider);
    if (activeConversation == null) return;

    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.conduitTheme.surfaceBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.dialog),
          ),
          title: Text(
            'Manage Tags',
            style: TextStyle(color: context.conduitTheme.textPrimary),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Add new tag input
                TextField(
                  controller: controller,
                  style: TextStyle(color: context.conduitTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Add a tag',
                    hintStyle: TextStyle(
                      color: context.conduitTheme.inputPlaceholder,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: context.conduitTheme.inputBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: context.conduitTheme.inputBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: context.conduitTheme.buttonPrimary,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.add,
                        color: context.conduitTheme.buttonPrimary,
                      ),
                      onPressed: () async {
                        final tag = controller.text.trim();
                        if (tag.isNotEmpty) {
                          try {
                            final api = ref.read(apiServiceProvider);
                            if (api != null) {
                              await api.addTagToConversation(
                                activeConversation.id,
                                tag,
                              );
                              controller.clear();
                              setState(() {}); // Refresh the dialog

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Tag "$tag" added')),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to add tag: $e'),
                                  backgroundColor: AppTheme.error,
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.md),

                // Current tags
                FutureBuilder<List<String>>(
                  future: _loadConversationTags(ref, activeConversation.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: context.conduitTheme.buttonPrimary,
                        ),
                      );
                    }

                    final tags = snapshot.data ?? [];

                    if (tags.isEmpty) {
                      return Text(
                        'No tags yet',
                        style: TextStyle(
                          color: context.conduitTheme.textSecondary,
                        ),
                      );
                    }

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags
                          .map(
                            (tag) => Chip(
                              label: Text(
                                tag,
                                style: TextStyle(
                                  color: context.conduitTheme.textPrimary,
                                ),
                              ),
                              backgroundColor: context
                                  .conduitTheme
                                  .buttonPrimary
                                  .withValues(alpha: 0.2),
                              deleteIcon: Icon(
                                Icons.close,
                                color: context.conduitTheme.iconSecondary,
                                size: IconSize.sm,
                              ),
                              onDeleted: () async {
                                try {
                                  final api = ref.read(apiServiceProvider);
                                  if (api != null) {
                                    await api.removeTagFromConversation(
                                      activeConversation.id,
                                      tag,
                                    );
                                    setState(() {}); // Refresh the dialog

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Tag "$tag" removed'),
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Failed to remove tag: $e',
                                        ),
                                        backgroundColor:
                                            context.conduitTheme.error,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                controller.dispose();
                Navigator.pop(context);
              },
              child: Text(
                'Done',
                style: TextStyle(
                  color: AppTheme.neutral50.withValues(alpha: Alpha.strong),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<String>> _loadConversationTags(
    WidgetRef ref,
    String conversationId,
  ) async {
    try {
      final api = ref.read(apiServiceProvider);
      if (api != null) {
        return await api.getConversationTags(conversationId);
      }
    } catch (e) {
      // Return empty list on error
    }
    return [];
  }

  void _archiveMessages(BuildContext context, WidgetRef ref) async {
    final activeConversation = ref.read(activeConversationProvider);
    if (activeConversation == null) return;

    final confirmed = await ThemedDialogs.confirm(
      context,
      title: 'Archive Conversation',
      message:
          'Archive this conversation? You can find it in the archived conversations section.',
      confirmText: 'Archive',
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiServiceProvider);
        if (api != null) {
          await api.archiveConversation(activeConversation.id, true);
          ref.invalidate(conversationsProvider);
          ref.invalidate(archivedConversationsProvider);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Conversation archived')),
            );

            // Navigate back or clear current conversation
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to archive conversation: $e'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    ThemedDialogs.confirm(
      context,
      title: 'Delete Messages',
      message:
          'Are you sure you want to delete ${messages.length} message${messages.length == 1 ? '' : 's'}? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    ).then((confirmed) {
      if (confirmed == true) {
        _deleteMessages(context, ref);
      }
    });
  }

  void _deleteMessages(BuildContext context, WidgetRef ref) async {
    final activeConversation = ref.read(activeConversationProvider);
    if (activeConversation == null) return;

    final confirmed = await ThemedDialogs.confirm(
      context,
      title: 'Delete Conversation',
      message:
          'Are you sure you want to delete this conversation?\n\nThis action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiServiceProvider);
        if (api != null) {
          await api.deleteConversation(activeConversation.id);
          ref.invalidate(conversationsProvider);
          ref.invalidate(archivedConversationsProvider);

          // Clear the current conversation
          ref.read(activeConversationProvider.notifier).state = null;
          ref.read(chatMessagesProvider.notifier).clearMessages();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Conversation deleted')),
            );

            // Navigate back to conversation list
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete conversation: $e'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }
}

/// Export dialog with options
class ExportDialog extends ConsumerStatefulWidget {
  final List<ChatMessage> messages;
  final ExportFormat format;

  const ExportDialog({super.key, required this.messages, required this.format});

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  bool _includeTimestamps = true;
  bool _includeMetadata = false;
  bool _includeAttachments = true;
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final conduitTheme = context.conduitTheme;

    return AlertDialog(
      backgroundColor: AppTheme.neutral700,
      title: Text('Export Options', style: conduitTheme.headingMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export ${widget.messages.length} messages as ${widget.format.name.toUpperCase()}',
            style: conduitTheme.bodyMedium?.copyWith(
              color: AppTheme.neutral50.withValues(alpha: 0.8),
            ),
          ),

          const SizedBox(height: Spacing.lg - Spacing.xs),

          // Export options
          CheckboxListTile(
            title: const Text(
              'Include timestamps',
              style: TextStyle(color: AppTheme.neutral50),
            ),
            value: _includeTimestamps,
            onChanged: (value) =>
                setState(() => _includeTimestamps = value ?? true),
            activeColor: AppTheme.brandPrimary,
          ),

          CheckboxListTile(
            title: const Text(
              'Include metadata',
              style: TextStyle(color: AppTheme.neutral50),
            ),
            value: _includeMetadata,
            onChanged: (value) =>
                setState(() => _includeMetadata = value ?? false),
            activeColor: AppTheme.brandPrimary,
          ),

          CheckboxListTile(
            title: const Text(
              'Include attachments',
              style: TextStyle(color: AppTheme.neutral50),
            ),
            value: _includeAttachments,
            onChanged: (value) =>
                setState(() => _includeAttachments = value ?? true),
            activeColor: AppTheme.brandPrimary,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isExporting ? null : _performExport,
          child: _isExporting
              ? const SizedBox(
                  width: Spacing.md,
                  height: Spacing.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Export'),
        ),
      ],
    );
  }

  Future<void> _performExport() async {
    setState(() => _isExporting = true);

    try {
      final batchService = ref.read(messageBatchServiceProvider);
      final options = ExportOptions(
        includeTimestamps: _includeTimestamps,
        includeMetadata: _includeMetadata,
        includeAttachments: _includeAttachments,
      );

      final result = await batchService.exportMessages(
        messages: widget.messages,
        format: widget.format,
        options: options,
      );

      if (result.success && mounted) {
        Navigator.pop(context);

        // In a real app, you would save the file or share it
        // For now, we'll copy to clipboard
        final content = result.data?['content'] as String?;
        if (content != null) {
          await Clipboard.setData(ClipboardData(text: content));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Export copied to clipboard (${widget.format.name.toUpperCase()})',
                ),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${result.error}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }
}
