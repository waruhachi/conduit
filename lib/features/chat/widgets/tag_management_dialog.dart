import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/conversation.dart';
import '../../../core/providers/app_providers.dart';

class TagManagementDialog extends ConsumerStatefulWidget {
  final Conversation conversation;

  const TagManagementDialog({super.key, required this.conversation});

  @override
  ConsumerState<TagManagementDialog> createState() =>
      _TagManagementDialogState();
}

class _TagManagementDialogState extends ConsumerState<TagManagementDialog> {
  final _tagController = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversationTags = widget.conversation.tags;

    return Dialog(
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppBorderRadius.lg),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Platform.isIOS ? CupertinoIcons.tag : Icons.label,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'Manage Tags',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Platform.isIOS ? CupertinoIcons.xmark : Icons.close,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Add new tag section
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      decoration: InputDecoration(
                        hintText: 'Add new tag',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(
                          Platform.isIOS
                              ? CupertinoIcons.tag_fill
                              : Icons.label,
                        ),
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  ElevatedButton(
                    onPressed: _isAdding ? null : _addTag,
                    child: _isAdding
                        ? const SizedBox(
                            width: Spacing.md,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add'),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Current tags
            Expanded(
              child: conversationTags.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Platform.isIOS
                                ? CupertinoIcons.tag
                                : Icons.label_outline,
                            size: 48,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          const SizedBox(height: Spacing.md),
                          Text(
                            'No tags yet',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          Text(
                            'Add tags to organize and find conversations easily',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(Spacing.md),
                      itemCount: conversationTags.length,
                      itemBuilder: (context, index) {
                        final tag = conversationTags[index];
                        return _buildTagChip(context, tag);
                      },
                    ),
            ),

            // Bottom actions
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagChip(BuildContext context, String tag) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Chip(
        avatar: Icon(
          Platform.isIOS ? CupertinoIcons.tag_fill : Icons.label,
          size: 16,
          color: theme.colorScheme.onPrimaryContainer,
        ),
        label: Text(tag),
        backgroundColor: theme.colorScheme.primaryContainer,
        deleteIcon: Icon(
          Platform.isIOS ? CupertinoIcons.xmark_circle_fill : Icons.cancel,
          size: 18,
        ),
        onDeleted: () => _removeTag(tag),
      ),
    );
  }

  Future<void> _addTag() async {
    final tag = _tagController.text.trim();
    if (tag.isEmpty || widget.conversation.tags.contains(tag)) return;

    setState(() => _isAdding = true);

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service available');

      await api.addTagToConversation(widget.conversation.id, tag);
      ref.invalidate(conversationsProvider);
      _tagController.clear();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tag "$tag" added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding tag: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      setState(() => _isAdding = false);
    }
  }

  Future<void> _removeTag(String tag) async {
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No API service available');

      await api.removeTagFromConversation(widget.conversation.id, tag);
      ref.invalidate(conversationsProvider);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tag "$tag" removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing tag: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
