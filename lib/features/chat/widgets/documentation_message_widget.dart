import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:async';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'dart:io' show Platform;
import '../../../shared/theme/theme_extensions.dart';
import '../../../core/utils/reasoning_parser.dart';

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
  void didUpdateWidget(DocumentationMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Re-parse reasoning content when message content changes
    if (oldWidget.message.content != widget.message.content) {
      // Throttle markdown re-rendering for smoother streaming
      _scheduleRenderUpdate(widget.message.content ?? '');
      _updateReasoningContent();
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
      return _buildDocumentationMessage();
    }
  }

  Widget _buildUserMessage() {
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16, left: 50, right: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _toggleActions(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
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
                        fontSize: AppTypography.bodyLarge,
                        height: 1.5,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 24, left: 12, right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Simplified AI Name and Avatar
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
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
              ),

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
              GestureDetector(
                onLongPress: () => _toggleActions(),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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

                      // Action buttons - inline and minimal
                      if (_showActions) ...[
                        const SizedBox(height: Spacing.md),
                        _buildActionButtons(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
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

    final codeFence = RegExp(
      r"```([\w\-\+\.#]*)\n([\s\S]*?)```",
      multiLine: true,
    );
    final widgets = <Widget>[];
    int lastIndex = 0;
    for (final match in codeFence.allMatches(content)) {
      if (match.start > lastIndex) {
        final textSegment = content.substring(lastIndex, match.start);
        widgets.add(
          GptMarkdown(
            textSegment,
            style: TextStyle(
              color: context.conduitTheme.textPrimary,
              fontSize: AppTypography.bodyLarge,
              height: 1.6,
              letterSpacing: 0.1,
            ),
          ),
        );
      }

      final language = match.group(1)?.trim().isEmpty == true
          ? null
          : match.group(1)!.trim();
      final code = match.group(2) ?? '';
      widgets.add(_buildCodeBlock(code, language));
      lastIndex = match.end;
    }

    if (lastIndex < content.length) {
      final tail = content.substring(lastIndex);
      widgets.add(
        GptMarkdown(
          tail,
          style: TextStyle(
            color: context.conduitTheme.textPrimary,
            fontSize: AppTypography.bodyLarge,
            height: 1.6,
            letterSpacing: 0.1,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets
          .map(
            (w) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: w,
            ),
          )
          .toList(),
    );
  }

  Widget _buildCodeBlock(String code, String? language) {
    return Container(
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: context.conduitTheme.dividerColor.withValues(alpha: 0.7),
          width: BorderWidth.thin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            child: Row(
              children: [
                Icon(
                  Platform.isIOS
                      ? CupertinoIcons.chevron_left_slash_chevron_right
                      : Icons.code,
                  size: 14,
                  color: context.conduitTheme.iconSecondary,
                ),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: Text(
                    language?.toUpperCase() ?? 'CODE',
                    style: TextStyle(
                      fontSize: AppTypography.labelSmall,
                      color: context.conduitTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _copyToClipboard(code),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.xs,
                      vertical: Spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: context.conduitTheme.surfaceBackground.withValues(
                        alpha: 0.2,
                      ),
                      borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Platform.isIOS
                              ? CupertinoIcons.doc_on_clipboard
                              : Icons.copy,
                          size: 14,
                          color: context.conduitTheme.iconSecondary,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Text(
                          'Copy',
                          style: TextStyle(
                            fontSize: AppTypography.labelSmall,
                            color: context.conduitTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppBorderRadius.md),
              ),
            ),
            child: SelectableText(
              code.trimRight(),
              style: TextStyle(
                color: context.conduitTheme.textSecondary,
                fontFamily: AppTypography.monospaceFontFamily,
                fontSize: AppTypography.bodySmall,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Code copied'),
          backgroundColor: context.conduitTheme.buttonPrimary,
        ),
      );
    }
  }

  // Removed lightweight streaming text; we now stream markdown with throttling

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
}
