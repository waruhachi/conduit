import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'dart:io' show Platform;
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/markdown/streaming_markdown_widget.dart';
import '../../../core/utils/reasoning_parser.dart';
import 'enhanced_image_attachment.dart';

class DocumentationMessageWidget extends ConsumerStatefulWidget {
  final dynamic message;
  final bool isUser;
  final bool isStreaming;
  final String? modelName;
  final VoidCallback? onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;

  const DocumentationMessageWidget({
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
  ConsumerState<DocumentationMessageWidget> createState() =>
      _DocumentationMessageWidgetState();
}

class _DocumentationMessageWidgetState
    extends ConsumerState<DocumentationMessageWidget>
    with TickerProviderStateMixin {
  bool _showActions = false;
  bool _showReasoning = false;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  ReasoningContent? _reasoningContent;
  String _renderedContent = '';
  Timer? _throttleTimer;
  String? _pendingContent;
  Widget? _cachedAvatar;

  @override
  void initState() {
    super.initState();
    _renderedContent = widget.message.content ?? '';
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Parse reasoning content if present
    _updateReasoningContent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Build cached avatar when theme context is available
    _buildCachedAvatar();
  }

  @override
  void didUpdateWidget(DocumentationMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Re-parse reasoning content when message content changes
    if (oldWidget.message.content != widget.message.content) {
      // Throttle markdown re-rendering for smoother streaming
      _scheduleRenderUpdate(widget.message.content ?? '');
      _updateReasoningContent();
    }
    
    // Rebuild cached avatar if model name changes
    if (oldWidget.modelName != widget.modelName) {
      _buildCachedAvatar();
    }
  }

  void _updateReasoningContent() {
    if (!widget.isUser && widget.message.content != null) {
      final newReasoningContent = ReasoningParser.parseReasoningContent(
        widget.message.content!,
      );
      if (newReasoningContent != _reasoningContent) {
        setState(() {
          _reasoningContent = newReasoningContent;
        });
      }
    }
  }

  void _scheduleRenderUpdate(String rawContent) {
    final safe = _safeForStreaming(rawContent);
    if (_throttleTimer != null && _throttleTimer!.isActive) {
      _pendingContent = safe;
      return;
    }
    if (mounted) {
      setState(() => _renderedContent = safe);
    } else {
      _renderedContent = safe;
    }
    _throttleTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      if (_pendingContent != null) {
        setState(() {
          _renderedContent = _pendingContent!;
          _pendingContent = null;
        });
      }
    });
  }

  String _safeForStreaming(String content) {
    if (content.isEmpty) return content;
    // Auto-close an unbalanced triple backtick fence during streaming so markdown stays valid
    final fenceCount = '```'.allMatches(content).length;
    if (fenceCount.isOdd) {
      return '$content\n```';
    }
    return content;
  }

  void _buildCachedAvatar() {
    _cachedAvatar = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: context.conduitTheme.buttonPrimary,
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
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _throttleTimer?.cancel();
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
      return _buildDocumentationMessage();
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
        margin: const EdgeInsets.only(bottom: 12, left: 50, right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Display images outside and above the text bubble
            if (hasImages) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: _buildUserAttachmentImages(),
                  ),
                ],
              ),
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
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: context.conduitTheme.chatBubbleUser,
                        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                        border: Border.all(
                          color: context.conduitTheme.chatBubbleUserBorder,
                          width: BorderWidth.regular,
                        ),
                      ),
                      child: Text(
                        widget.message.content,
                        style: TextStyle(
                          color: context.conduitTheme.chatBubbleUserText,
                          fontSize: AppTypography.bodyMedium,
                          height: 1.3,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            
            // Action buttons below the message bubble
            if (_showActions) ...[
              const SizedBox(height: Spacing.sm),
              _buildUserActionButtons(),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: const Duration(milliseconds: 400))
        .slideX(
          begin: 0.2,
          end: 0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
  }

  Widget _buildDocumentationMessage() {
    return GestureDetector(
      onLongPress: () => _toggleActions(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16, left: 12, right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cached AI Name and Avatar to prevent flashing
            _cachedAvatar ?? const SizedBox.shrink(),

            // Reasoning Section (if present)
            if (_reasoningContent != null) ...[
              InkWell(
                onTap: () => setState(() => _showReasoning = !_showReasoning),
                borderRadius: BorderRadius.circular(AppBorderRadius.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: context.conduitTheme.surfaceContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    border: Border.all(
                      color: context.conduitTheme.dividerColor,
                      width: BorderWidth.thin,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showReasoning
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                        color: context.conduitTheme.textSecondary,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Icon(
                        Icons.psychology_outlined,
                        size: 14,
                        color: context.conduitTheme.buttonPrimary,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Text(
                        _reasoningContent!.summary.isNotEmpty
                            ? _reasoningContent!.summary
                            : 'Thought for ${_reasoningContent!.formattedDuration}',
                        style: TextStyle(
                          fontSize: AppTypography.bodySmall,
                          color: context.conduitTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Expandable reasoning content
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  margin: const EdgeInsets.only(top: Spacing.sm),
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: context.conduitTheme.surfaceContainer.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    border: Border.all(
                      color: context.conduitTheme.dividerColor,
                      width: BorderWidth.thin,
                    ),
                  ),
                  child: SelectableText(
                    _reasoningContent!.cleanedReasoning,
                    style: TextStyle(
                      fontSize: AppTypography.bodySmall,
                      color: context.conduitTheme.textSecondary,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
                crossFadeState: _showReasoning
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),

              const SizedBox(height: Spacing.md),
            ],

            // Documentation-style content without heavy bubble; premium markdown
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display attachment images if any (for user uploaded images)
                  if (widget.message.attachmentIds != null &&
                      widget.message.attachmentIds!.isNotEmpty) ...[
                    _buildAttachmentImages(),
                    const SizedBox(height: Spacing.md),
                  ],
                  
                  if (widget.isStreaming &&
                      (widget.message.content.trim().isEmpty ||
                          widget.message.content == '[TYPING_INDICATOR]'))
                    _buildTypingIndicator()
                  else if (widget.isStreaming &&
                      widget.message.content.isNotEmpty &&
                      widget.message.content != '[TYPING_INDICATOR]')
                    // While streaming, render markdown with throttling and safety fixes
                    _buildEnhancedMarkdownContent(_renderedContent)
                  else
                    // After streaming finishes (or static content), render full markdown
                    _buildEnhancedMarkdownContent(
                      _reasoningContent?.mainContent ??
                          widget.message.content,
                    ),
                ],
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
        .fadeIn(duration: const Duration(milliseconds: 300))
        .slideY(
          begin: 0.1,
          end: 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
  }

  Widget _buildEnhancedMarkdownContent(String content) {
    if (content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    // Process content to ensure proper image rendering
    final processedContent = _processContentForImages(content);

    return StreamingMarkdownWidget(
      staticContent: processedContent,
      isStreaming: widget.isStreaming,
    );
  }

  String _processContentForImages(String content) {
    // Check if content contains image markdown or base64 data URLs
    // This ensures images generated by AI are properly formatted
    
    // Pattern to detect base64 images that might not be in markdown format
    final base64Pattern = RegExp(r'data:image/[^;]+;base64,[A-Za-z0-9+/]+=*');
    
    // If we find base64 images not wrapped in markdown, wrap them
    if (base64Pattern.hasMatch(content) && !content.contains('![')) {
      content = content.replaceAllMapped(base64Pattern, (match) {
        final imageData = match.group(0)!;
        // Check if this image is already in markdown format
        final markdownCheck = RegExp(r'!\[.*?\]\(' + RegExp.escape(imageData) + r'\)');
        if (!markdownCheck.hasMatch(content)) {
          return '\n![Generated Image]($imageData)\n';
        }
        return imageData;
      });
    }
    
    return content;
  }

  Widget _buildUserAttachmentImages() {
    if (widget.message.attachmentIds == null ||
        widget.message.attachmentIds!.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageCount = widget.message.attachmentIds!.length;
    
    // Similar to iMessage style but adapted for documentation widget
    if (imageCount == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        child: EnhancedImageAttachment(
          attachmentId: widget.message.attachmentIds![0],
          isUserMessage: true,
          constraints: const BoxConstraints(
            maxWidth: 280,
            maxHeight: 350,
          ),
        ),
      );
    } else if (imageCount == 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: widget.message.attachmentIds!.map((attachmentId) {
          return Padding(
            padding: EdgeInsets.only(
              left: attachmentId == widget.message.attachmentIds!.first 
                  ? 0 
                  : Spacing.xs,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppBorderRadius.lg),
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
      );
    } else {
      return Container(
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
      );
    }
  }

  Widget _buildAttachmentImages() {
    if (widget.message.attachmentIds == null ||
        widget.message.attachmentIds!.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageCount = widget.message.attachmentIds!.length;

    // Display images in a clean, modern layout for assistant messages
    if (imageCount == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        child: EnhancedImageAttachment(
          attachmentId: widget.message.attachmentIds![0],
          isMarkdownFormat: true,
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 400,
          ),
        ),
      );
    } else {
      return Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: widget.message.attachmentIds!.map<Widget>((attachmentId) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            child: EnhancedImageAttachment(
              attachmentId: attachmentId,
              isMarkdownFormat: true,
              constraints: BoxConstraints(
                maxWidth: imageCount == 2 ? 245 : 160,
                maxHeight: imageCount == 2 ? 245 : 160,
              ),
            ),
          );
        }).toList(),
      );
    }
  }

  Widget _buildTypingIndicator() {
    return Consumer(
      builder: (context, ref, child) {
        const statusText = 'Thinking about your question...';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              statusText,
              style: TextStyle(
                color: context.conduitTheme.textSecondary.withValues(
                  alpha: 0.7,
                ),
                fontSize: AppTypography.bodyMedium,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                _buildTypingDot(0),
                const SizedBox(width: Spacing.xs),
                _buildTypingDot(200),
                const SizedBox(width: Spacing.xs),
                _buildTypingDot(400),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTypingDot(int delay) {
    return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: context.conduitTheme.textSecondary.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppBorderRadius.xs),
          ),
        )
        .animate(onPlay: (controller) => controller.repeat())
        .scale(
          duration: const Duration(milliseconds: 1000),
          begin: const Offset(1, 1),
          end: const Offset(1.3, 1.3),
        )
        .then(delay: Duration(milliseconds: delay))
        .scale(
          duration: const Duration(milliseconds: 1000),
          begin: const Offset(1.3, 1.3),
          end: const Offset(1, 1),
        );
  }

  Widget _buildActionButtons() {
    final isErrorMessage = widget.message.content.contains('⚠️') || 
                           widget.message.content.contains('Error') ||
                           widget.message.content.contains('timeout') ||
                           widget.message.content.contains('retry options');
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: context.conduitTheme.textPrimary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppBorderRadius.lg),
          border: Border.all(
            color: context.conduitTheme.textPrimary.withValues(alpha: 0.08),
            width: BorderWidth.regular,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: IconSize.sm,
              color: context.conduitTheme.textPrimary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.labelMedium,
                color: context.conduitTheme.textPrimary.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserActionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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