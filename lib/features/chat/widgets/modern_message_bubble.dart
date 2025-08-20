import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/markdown/streaming_markdown_widget.dart';
import 'enhanced_image_attachment.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;

class ModernMessageBubble extends ConsumerStatefulWidget {
  final dynamic message;
  final bool isUser;
  final bool isStreaming;
  final String? modelName;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;

  const ModernMessageBubble({
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
  ConsumerState<ModernMessageBubble> createState() =>
      _ModernMessageBubbleState();
}

class _ModernMessageBubbleState extends ConsumerState<ModernMessageBubble>
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
    
    // iMessage-style image layout
    if (imageCount == 1) {
      // Single image - larger display
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppBorderRadius.messageBubble),
            child: EnhancedImageAttachment(
              attachmentId: widget.message.attachmentIds![0],
              isUserMessage: true,
              constraints: const BoxConstraints(
                maxWidth: 280,
                maxHeight: 350,
              ),
            ),
          ),
        ],
      );
    } else if (imageCount == 2) {
      // Two images side by side
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.message.attachmentIds!.map((attachmentId) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: attachmentId == widget.message.attachmentIds!.first 
                        ? 0 
                        : Spacing.xs,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppBorderRadius.messageBubble),
                    child: EnhancedImageAttachment(
                      attachmentId: attachmentId,
                      isUserMessage: true,
                      constraints: const BoxConstraints(
                        maxWidth: 135,
                        maxHeight: 180,
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
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    child: EnhancedImageAttachment(
                      attachmentId: attachmentId,
                      isUserMessage: true,
                      constraints: BoxConstraints(
                        maxWidth: imageCount == 3 ? 135 : 90,
                        maxHeight: imageCount == 3 ? 135 : 90,
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

  Widget _buildAssistantAttachmentImages() {
    if (widget.message.attachmentIds == null ||
        widget.message.attachmentIds!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Assistant images - similar style but left-aligned
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: widget.message.attachmentIds!.map<Widget>((attachmentId) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppBorderRadius.messageBubble),
          child: EnhancedImageAttachment(
            attachmentId: attachmentId,
            constraints: const BoxConstraints(
              maxWidth: 300,
              maxHeight: 350,
            ),
          ),
        );
      }).toList(),
    );
  }

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
    if (widget.isUser) {
      return _buildUserMessage();
    } else {
      return _buildAssistantMessage();
    }
  }

  Widget _buildUserMessage() {
    final hasImages = widget.message.attachmentIds != null &&
        widget.message.attachmentIds!.isNotEmpty;
    final hasText = widget.message.content.isNotEmpty;

    return GestureDetector(
      onLongPress: () => _toggleActions(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(
          bottom: Spacing.sm,
          left: Spacing.xxxl,
          right: Spacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Display images outside and above the text bubble (iMessage style)
            if (hasImages) ...[
              _buildUserAttachmentImages(),
              if (hasText) const SizedBox(height: Spacing.xs),
            ],

            // Display text bubble if there's text content
            if (hasText)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.messagePadding,
                          vertical: Spacing.xs,
                        ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            context.conduitTheme.chatBubbleUser.withValues(
                              alpha: 0.95,
                            ),
                            context.conduitTheme.chatBubbleUser,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(
                          AppBorderRadius.messageBubble,
                        ),
                        border: Border.all(
                          color: context.conduitTheme.chatBubbleUserBorder,
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
                      child: _buildCustomText(
                        widget.message.content,
                        context.conduitTheme.chatBubbleUserText,
                      ),
                    ),
                  ),
                ],
              ),
            
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

  Widget _buildAssistantMessage() {
    final hasImages = widget.message.attachmentIds != null &&
        widget.message.attachmentIds!.isNotEmpty;
    final hasContent = widget.message.content.isNotEmpty &&
        widget.message.content != '[TYPING_INDICATOR]';
    final showTyping = (widget.message.content.isEmpty ||
            widget.message.content == '[TYPING_INDICATOR]') &&
        widget.isStreaming;

    return GestureDetector(
      onLongPress: () => _toggleActions(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(
          bottom: Spacing.md,
          left: Spacing.xs,
          right: Spacing.xxxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Simplified AI Name and Avatar
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          context.conduitTheme.buttonPrimary.withValues(
                            alpha: 0.9,
                          ),
                          context.conduitTheme.buttonPrimary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        AppBorderRadius.small,
                      ),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: context.conduitTheme.buttonPrimaryText,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    widget.modelName ?? 'Assistant',
                    style: TextStyle(
                      color: context.conduitTheme.textSecondary,
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),

            // Display images outside the bubble if any
            if (hasImages) ...[
              _buildAssistantAttachmentImages(),
              if (hasContent || showTyping) const SizedBox(height: Spacing.xs),
            ],

            // Message Content Bubble
            if (hasContent || showTyping)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: Spacing.messagePadding,
                  vertical: Spacing.xs,
                ),
                decoration: BoxDecoration(
                  color: context.conduitTheme.chatBubbleAssistant,
                  borderRadius: BorderRadius.circular(
                    AppBorderRadius.messageBubble,
                  ),
                  border: Border.all(
                    color: context.conduitTheme.chatBubbleAssistantBorder,
                    width: BorderWidth.regular,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: showTyping
                    ? _buildTypingIndicator()
                    : _buildCustomText(
                        widget.message.content,
                        context.conduitTheme.chatBubbleAssistantText,
                      ),
              ),

            // Action buttons below the message content
            if (_showActions) ...[
              const SizedBox(height: Spacing.sm),
              _buildActionButtons(),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: AnimationDuration.messageAppear)
        .slideX(
          begin: -AnimationValues.messageSlideDistance,
          end: 0,
          duration: AnimationDuration.messageSlide,
          curve: AnimationCurves.messageSlide,
        );
  }





  Widget _buildCustomText(String text, [Color? textColor]) {
    // Use the new markdown widget for rich text rendering
    return StreamingMarkdownWidget(
      staticContent: text,
      isStreaming: widget.isStreaming,
    );
  }





  Widget _buildTypingIndicator() {
    return Consumer(
      builder: (context, ref, child) {
        // Show only animated dots, no text
        return _buildTypingDots();
      },
    );
  }

  Widget _buildTypingDots() {
    return Row(
      children: List.generate(3, (index) {
        return Container(
              margin: EdgeInsets.only(right: index < 2 ? Spacing.xs : 0),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: context.conduitTheme.loadingIndicator,
                borderRadius: BorderRadius.circular(3),
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .scale(
              duration: AnimationDuration.typingIndicator,
              begin: const Offset(
                AnimationValues.typingIndicatorScale,
                AnimationValues.typingIndicatorScale,
              ),
              end: const Offset(1.0, 1.0),
              curve: AnimationCurves.typingIndicator,
              delay: Duration(
                milliseconds: index * 200,
              ), // Stagger the animation
            );
      }),
    );
  }

  Widget _buildActionButtons() {
    final isErrorMessage = widget.message.content.contains('⚠️') || 
                           widget.message.content.contains('Error') ||
                           widget.message.content.contains('timeout') ||
                           widget.message.content.contains('retry options');
    
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        _buildActionButton(
          icon: Platform.isIOS
              ? CupertinoIcons.doc_on_clipboard
              : Icons.content_copy,
          label: 'Copy',
          onTap: widget.onCopy,
        ),
        if (isErrorMessage) ...[
          _buildActionButton(
            icon: Platform.isIOS ? CupertinoIcons.arrow_clockwise : Icons.refresh,
            label: 'Retry',
            onTap: widget.onRegenerate,
          ),
        ] else ...[
          _buildActionButton(
            icon: Platform.isIOS ? CupertinoIcons.pencil : Icons.edit_outlined,
            label: 'Edit',
            onTap: widget.onEdit,
          ),
          _buildActionButton(
            icon: Platform.isIOS
                ? CupertinoIcons.speaker_1
                : Icons.volume_up_outlined,
            label: 'Read',
            onTap: () => _handleTextToSpeech(context),
          ),
          _buildActionButton(
            icon: Platform.isIOS
                ? CupertinoIcons.hand_thumbsup
                : Icons.thumb_up_outlined,
            label: 'Like',
            onTap: widget.onLike,
          ),
          _buildActionButton(
            icon: Platform.isIOS
                ? CupertinoIcons.hand_thumbsdown
                : Icons.thumb_down_outlined,
            label: 'Dislike',
            onTap: widget.onDislike,
          ),
          _buildActionButton(
            icon: Platform.isIOS ? CupertinoIcons.refresh : Icons.refresh,
            label: 'Regenerate',
            onTap: widget.onRegenerate,
          ),
        ],
      ],
    );
  }

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
        _buildActionButton(
          icon: Platform.isIOS
              ? CupertinoIcons.speaker_1
              : Icons.volume_up_outlined,
          label: 'Read',
          onTap: () => _handleTextToSpeech(context),
        ),
      ],
    );
  }

  void _handleTextToSpeech(BuildContext context) {
    // Implementation for text-to-speech functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Text-to-speech feature coming soon!'),
        backgroundColor: context.conduitTheme.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.snackbar),
        ),
      ),
    );
  }
}
