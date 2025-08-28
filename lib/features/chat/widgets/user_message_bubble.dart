import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'enhanced_image_attachment.dart';
import 'enhanced_attachment.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;

class UserMessageBubble extends ConsumerStatefulWidget {
  final dynamic message;
  final bool isUser;
  final bool isStreaming;
  final String? modelName;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;

  const UserMessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    this.isStreaming = false,
    this.modelName,
    this.onCopy,
    this.onEdit,
    this.onRegenerate,
    this.onLike,
    this.onDislike,
  });

  @override
  ConsumerState<UserMessageBubble> createState() => _UserMessageBubbleState();
}

class _UserMessageBubbleState extends ConsumerState<UserMessageBubble>
    with TickerProviderStateMixin {
  bool _showActions = false;
  late AnimationController _fadeController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: AnimationDuration.microInteraction,
      vsync: this,
    );
    _slideController = AnimationController(
      duration: AnimationDuration.messageSlide,
      vsync: this,
    );
  }

  Widget _buildUserAttachmentImages() {
    if (widget.message.attachmentIds == null ||
        widget.message.attachmentIds!.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageCount = widget.message.attachmentIds!.length;

    // iMessage-style image layout with AnimatedSwitcher for smooth transitions
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      child: _buildImageLayout(imageCount),
    );
  }

  Widget _buildUserFileImages() {
    if (widget.message.files == null || widget.message.files!.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageFiles = widget.message.files!
        .where(
          (file) =>
              file is Map && file['type'] == 'image' && file['url'] != null,
        )
        .toList();

    if (imageFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageCount = imageFiles.length;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      child: _buildFileImageLayout(imageFiles, imageCount),
    );
  }

  Widget _buildFileImageLayout(List<dynamic> imageFiles, int imageCount) {
    if (imageCount == 1) {
      final String imageUrl = imageFiles[0]['url'] as String;
      return Row(
        key: ValueKey('user_file_single_$imageUrl'),
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                AppBorderRadius.messageBubble,
              ),
              boxShadow: [
                BoxShadow(
                  color: context.conduitTheme.cardShadow.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                AppBorderRadius.messageBubble,
              ),
              child: EnhancedImageAttachment(
                attachmentId: imageUrl,
                isUserMessage: true,
                isMarkdownFormat: false,
                constraints: const BoxConstraints(
                  maxWidth: 280,
                  maxHeight: 350,
                ),
                disableAnimation: widget.isStreaming,
              ),
            ),
          ),
        ],
      );
    } else if (imageCount == 2) {
      return Row(
        key: ValueKey(
          'user_file_double_${imageFiles.map((e) => e['url']).join('_')}',
        ),
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: imageFiles.asMap().entries.map((entry) {
                final index = entry.key;
                final String imageUrl = entry.value['url'] as String;
                return Padding(
                  padding: EdgeInsets.only(left: index == 0 ? 0 : Spacing.xs),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.messageBubble,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.conduitTheme.cardShadow.withValues(
                            alpha: 0.08,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.messageBubble,
                      ),
                      child: EnhancedImageAttachment(
                        key: ValueKey('user_file_attachment_$imageUrl'),
                        attachmentId: imageUrl,
                        isUserMessage: true,
                        isMarkdownFormat: false,
                        constraints: const BoxConstraints(
                          maxWidth: 135,
                          maxHeight: 180,
                        ),
                        disableAnimation: widget.isStreaming,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    } else {
      return Row(
        key: ValueKey(
          'user_file_grid_${imageFiles.map((e) => e['url']).join('_')}',
        ),
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: imageFiles.map((file) {
                  final String imageUrl = file['url'] as String;
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      boxShadow: [
                        BoxShadow(
                          color: context.conduitTheme.cardShadow.withValues(
                            alpha: 0.06,
                          ),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      child: EnhancedImageAttachment(
                        key: ValueKey('user_file_grid_attachment_$imageUrl'),
                        attachmentId: imageUrl,
                        isUserMessage: true,
                        isMarkdownFormat: false,
                        constraints: BoxConstraints(
                          maxWidth: imageCount == 3 ? 135 : 90,
                          maxHeight: imageCount == 3 ? 135 : 90,
                        ),
                        disableAnimation: widget.isStreaming,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildImageLayout(int imageCount) {
    if (imageCount == 1) {
      // Single image - larger display
      return Row(
        key: ValueKey('user_single_${widget.message.attachmentIds![0]}'),
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                AppBorderRadius.messageBubble,
              ),
              boxShadow: [
                BoxShadow(
                  color: context.conduitTheme.cardShadow.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                AppBorderRadius.messageBubble,
              ),
              child: EnhancedAttachment(
                attachmentId: widget.message.attachmentIds![0],
                isUserMessage: true,
                constraints: const BoxConstraints(
                  maxWidth: 280,
                  maxHeight: 350,
                ),
                disableAnimation: widget.isStreaming,
              ),
            ),
          ),
        ],
      );
    } else if (imageCount == 2) {
      // Two images side by side
      return Row(
        key: ValueKey('user_double_${widget.message.attachmentIds!.join('_')}'),
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.message.attachmentIds!.asMap().entries.map((
                entry,
              ) {
                final index = entry.key;
                final attachmentId = entry.value;
                return Padding(
                  padding: EdgeInsets.only(left: index == 0 ? 0 : Spacing.xs),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.messageBubble,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.conduitTheme.cardShadow.withValues(
                            alpha: 0.08,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.messageBubble,
                      ),
                      child: EnhancedAttachment(
                        key: ValueKey('user_attachment_$attachmentId'),
                        attachmentId: attachmentId,
                        isUserMessage: true,
                        constraints: const BoxConstraints(
                          maxWidth: 135,
                          maxHeight: 180,
                        ),
                        disableAnimation: widget.isStreaming,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    } else {
      // Grid layout for 3+ images
      return Row(
        key: ValueKey('user_grid_${widget.message.attachmentIds!.join('_')}'),
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: widget.message.attachmentIds!.map((attachmentId) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      boxShadow: [
                        BoxShadow(
                          color: context.conduitTheme.cardShadow.withValues(
                            alpha: 0.06,
                          ),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      child: EnhancedAttachment(
                        key: ValueKey('user_grid_attachment_$attachmentId'),
                        attachmentId: attachmentId,
                        isUserMessage: true,
                        constraints: BoxConstraints(
                          maxWidth: imageCount == 3 ? 135 : 90,
                          maxHeight: imageCount == 3 ? 135 : 90,
                        ),
                        disableAnimation: widget.isStreaming,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      );
    }
  }

  // Assistant-only helpers removed; this widget renders only user bubbles.

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _toggleActions() {
    setState(() {
      _showActions = !_showActions;
    });

    if (_showActions) {
      _fadeController.forward();
      _slideController.forward();
    } else {
      _fadeController.reverse();
      _slideController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildUserMessage();
  }

  Widget _buildUserMessage() {
    final hasImages =
        widget.message.attachmentIds != null &&
        widget.message.attachmentIds!.isNotEmpty;
    final hasText = widget.message.content.isNotEmpty;
    final hasGeneratedImages =
        widget.message.files != null &&
        (widget.message.files as List).any(
          (f) => f is Map && f['type'] == 'image' && f['url'] != null,
        );

    return GestureDetector(
          onLongPress: () => _toggleActions(),
          behavior: HitTestBehavior.translucent,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(
              bottom: Spacing.md,
              left: Spacing.xxxl,
              right: Spacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Display images outside and above the text bubble (iMessage style)
                if (hasImages) ...[_buildUserAttachmentImages()],
                if (hasGeneratedImages) ...[_buildUserFileImages()],

                // Display text bubble if there's text content
                if (hasText) const SizedBox(height: Spacing.xs),
                if (hasText)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.82,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.chatBubblePadding,
                              vertical: Spacing.sm,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  context.conduitTheme.chatBubbleUser
                                      .withValues(alpha: 0.95),
                                  context.conduitTheme.chatBubbleUser,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(
                                AppBorderRadius.messageBubble,
                              ),
                              border: Border.all(
                                color:
                                    context.conduitTheme.chatBubbleUserBorder,
                                width: BorderWidth.regular,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              widget.message.content,
                              style: AppTypography.chatMessageStyle.copyWith(
                                color: context.conduitTheme.chatBubbleUserText,
                              ),
                              softWrap: true,
                              textAlign: TextAlign.left,
                              textHeightBehavior: const TextHeightBehavior(
                                applyHeightToFirstAscent: false,
                                applyHeightToLastDescent: false,
                                leadingDistribution:
                                    TextLeadingDistribution.even,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (hasText) const SizedBox(height: Spacing.xs),

                // Action buttons below the message
                if (_showActions) ...[
                  const SizedBox(height: Spacing.sm),
                  _buildUserActionButtons(),
                ],
              ],
            ),
          ),
        )
        .animate()
        .fadeIn(duration: AnimationDuration.messageAppear)
        .slideX(
          begin: AnimationValues.messageSlideDistance,
          end: 0,
          duration: AnimationDuration.messageSlide,
          curve: AnimationCurves.messageSlide,
        );
  }

  // Assistant-only message renderer removed.

  // Markdown rendering and typing indicator helpers removed.

  // Removed unused assistant action buttons builder.

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.actionButtonPadding,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground.withValues(
            alpha: Alpha.buttonHover,
          ),
          borderRadius: BorderRadius.circular(AppBorderRadius.actionButton),
          border: Border.all(
            color: context.conduitTheme.textPrimary.withValues(
              alpha: Alpha.subtle,
            ),
            width: BorderWidth.regular,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: IconSize.small,
              color: context.conduitTheme.iconSecondary,
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              label,
              style: AppTypography.labelStyle.copyWith(
                color: context.conduitTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(
      duration: AnimationDuration.buttonPress,
      curve: AnimationCurves.buttonPress,
    );
  }

  Widget _buildUserActionButtons() {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        _buildActionButton(
          icon: Platform.isIOS ? CupertinoIcons.pencil : Icons.edit_outlined,
          label: 'Edit',
          onTap: widget.onEdit,
        ),
        _buildActionButton(
          icon: Platform.isIOS
              ? CupertinoIcons.doc_on_clipboard
              : Icons.content_copy,
          label: 'Copy',
          onTap: widget.onCopy,
        ),
      ],
    );
  }
}
