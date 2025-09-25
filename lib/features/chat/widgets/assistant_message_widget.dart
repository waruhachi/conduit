import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/markdown/streaming_markdown_widget.dart';
import '../../../core/utils/reasoning_parser.dart';
import '../../../core/utils/message_segments.dart';
import '../../../core/utils/tool_calls_parser.dart';
import '../../../core/models/chat_message.dart';
import '../providers/text_to_speech_provider.dart';
import 'enhanced_image_attachment.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'enhanced_attachment.dart';
import 'package:conduit/shared/widgets/chat_action_button.dart';
import '../../../shared/widgets/model_avatar.dart';
import 'package:url_launcher/url_launcher_string.dart';
import '../providers/chat_providers.dart' show sendMessage;
import '../../../core/utils/debug_logger.dart';

class AssistantMessageWidget extends ConsumerStatefulWidget {
  final dynamic message;
  final bool isStreaming;
  final String? modelName;
  final String? modelIconUrl;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;

  const AssistantMessageWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.modelName,
    this.modelIconUrl,
    this.onCopy,
    this.onRegenerate,
    this.onLike,
    this.onDislike,
  });

  @override
  ConsumerState<AssistantMessageWidget> createState() =>
      _AssistantMessageWidgetState();
}

class _AssistantMessageWidgetState extends ConsumerState<AssistantMessageWidget>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  // Unified content segments (text, tool-calls, reasoning)
  List<MessageSegment> _segments = const [];
  final Set<String> _expandedToolIds = {};
  final Set<int> _expandedReasoning = {};
  Widget? _cachedAvatar;
  bool _allowTypingIndicator = false;
  Timer? _typingGateTimer;
  String _ttsPlainText = '';
  // press state handled by shared ChatActionButton

  Future<void> _handleFollowUpTap(String suggestion) async {
    final trimmed = suggestion.trim();
    if (trimmed.isEmpty || widget.isStreaming) {
      return;
    }
    try {
      await sendMessage(ref, trimmed, null);
    } catch (err, stack) {
      DebugLogger.log(
        'Failed to send follow-up: $err',
        scope: 'chat/assistant',
      );
      debugPrintStack(stackTrace: stack);
    }
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Parse reasoning and tool-calls sections
    _reparseSections();
    _updateTypingIndicatorGate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Build cached avatar when theme context is available
    _buildCachedAvatar();
  }

  @override
  void didUpdateWidget(AssistantMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Re-parse sections when message content changes
    if (oldWidget.message.content != widget.message.content) {
      _reparseSections();
      _updateTypingIndicatorGate();
    }

    // Rebuild cached avatar if model name or icon changes
    if (oldWidget.modelName != widget.modelName ||
        oldWidget.modelIconUrl != widget.modelIconUrl) {
      _buildCachedAvatar();
    }
  }

  void _reparseSections() {
    final raw0 = widget.message.content ?? '';
    // Strip any leftover placeholders from content before parsing
    const ti = '[TYPING_INDICATOR]';
    const searchBanner = '🔍 Searching the web...';
    String raw = raw0;
    if (raw.startsWith(ti)) {
      raw = raw.substring(ti.length);
    }
    if (raw.startsWith(searchBanner)) {
      raw = raw.substring(searchBanner.length);
    }
    // Do not truncate content during streaming; segmented parser skips
    // incomplete details blocks and tiles will render once complete.
    final rSegs = ReasoningParser.segments(raw);

    final out = <MessageSegment>[];
    final textBuf = StringBuffer();
    if (rSegs == null || rSegs.isEmpty) {
      final tSegs = ToolCallsParser.segments(raw);
      if (tSegs == null || tSegs.isEmpty) {
        out.add(MessageSegment.text(raw));
        textBuf.write(raw);
      } else {
        for (final s in tSegs) {
          if (s.isToolCall && s.entry != null) {
            out.add(MessageSegment.tool(s.entry!));
          } else if ((s.text ?? '').isNotEmpty) {
            out.add(MessageSegment.text(s.text!));
            textBuf.write(s.text);
          }
        }
      }
    } else {
      for (final rs in rSegs) {
        if (rs.isReasoning && rs.entry != null) {
          out.add(MessageSegment.reason(rs.entry!));
        } else if ((rs.text ?? '').isNotEmpty) {
          final t = rs.text!;
          final tSegs = ToolCallsParser.segments(t);
          if (tSegs == null || tSegs.isEmpty) {
            out.add(MessageSegment.text(t));
            textBuf.write(t);
          } else {
            for (final s in tSegs) {
              if (s.isToolCall && s.entry != null) {
                out.add(MessageSegment.tool(s.entry!));
              } else if ((s.text ?? '').isNotEmpty) {
                out.add(MessageSegment.text(s.text!));
                textBuf.write(s.text);
              }
            }
          }
        }
      }
    }

    final segments = out.isEmpty ? [MessageSegment.text(raw)] : out;
    final speechText = _buildTtsPlainText(segments, raw);

    setState(() {
      _segments = segments;
      _ttsPlainText = speechText;
    });
    _updateTypingIndicatorGate();
  }

  void _updateTypingIndicatorGate() {
    // Show typing indicator while streaming until we have any renderable segments
    // (tool tiles or actual text). Use a short delay to avoid flicker.
    _typingGateTimer?.cancel();
    final hasRenderable = _hasRenderableSegments;
    if (widget.isStreaming && !hasRenderable) {
      _allowTypingIndicator = false;
      _typingGateTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() {
            _allowTypingIndicator = true;
          });
        }
      });
    } else {
      _allowTypingIndicator = false;
    }
  }

  String get _messageId {
    try {
      final dynamic idValue = widget.message.id;
      if (idValue == null) {
        return '';
      }
      return idValue.toString();
    } catch (_) {
      return '';
    }
  }

  String _buildTtsPlainText(List<MessageSegment> segments, String fallback) {
    if (segments.isEmpty) {
      return _sanitizeForSpeech(fallback);
    }

    final buffer = StringBuffer();
    for (final segment in segments) {
      if (!segment.isText) {
        continue;
      }
      final text = segment.text ?? '';
      final sanitized = _sanitizeForSpeech(text);
      if (sanitized.isEmpty) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer.write(sanitized);
    }

    final result = buffer.toString().trim();
    if (result.isEmpty) {
      return _sanitizeForSpeech(fallback);
    }
    return result;
  }

  String _sanitizeForSpeech(String input) {
    if (input.isEmpty) {
      return '';
    }

    var text = input;
    text = text.replaceAll(RegExp(r'```'), ' ');
    text = text.replaceAll(RegExp(r'`'), '');
    text = text.replaceAll(RegExp(r'!\[(.*?)\]\((.*?)\)'), r'$1');
    text = text.replaceAll(RegExp(r'\[(.*?)\]\((.*?)\)'), r'$1');
    text = text.replaceAll(RegExp(r'\*\*'), '');
    text = text.replaceAll(RegExp(r'__'), '');
    text = text.replaceAll(RegExp(r'\*'), '');
    text = text.replaceAll(RegExp(r'_'), '');
    text = text.replaceAll(RegExp(r'~'), '');
    text = text.replaceAll(RegExp(r'^[-*+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^>\s?', multiLine: true), '');
    text = text.replaceAll('&nbsp;', ' ');
    text = text.replaceAll('&amp;', '&');
    text = text.replaceAll('&lt;', '<');
    text = text.replaceAll('&gt;', '>');
    text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  // No streaming-specific markdown fixes needed here; handled by Markdown widget

  Widget _buildToolCallTile(ToolCallEntry tc) {
    final isExpanded = _expandedToolIds.contains(tc.id);
    final theme = context.conduitTheme;

    String pretty(dynamic v, {int max = 1200}) {
      try {
        final formatted = const JsonEncoder.withIndent('  ').convert(v);
        return formatted.length > max
            ? '${formatted.substring(0, max)}\n…'
            : formatted;
      } catch (_) {
        final s = v?.toString() ?? '';
        return s.length > max ? '${s.substring(0, max)}…' : s;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedToolIds.remove(tc.id);
            } else {
              _expandedToolIds.add(tc.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            border: Border.all(
              color: theme.dividerColor,
              width: BorderWidth.thin,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: theme.textSecondary,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Icon(
                    tc.done
                        ? Icons.build_circle_outlined
                        : Icons.play_circle_outline,
                    size: 14,
                    color: theme.buttonPrimary,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Flexible(
                    child: Text(
                      tc.done
                          ? 'Tool Executed: ${tc.name}'
                          : 'Running tool: ${tc.name}…',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        color: theme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  margin: const EdgeInsets.only(top: Spacing.sm),
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: theme.surfaceContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    border: Border.all(
                      color: theme.dividerColor,
                      width: BorderWidth.thin,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tc.arguments != null) ...[
                        Text(
                          'Arguments',
                          style: TextStyle(
                            fontSize: AppTypography.bodySmall,
                            color: theme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.xxs),
                        SelectableText(
                          pretty(tc.arguments),
                          style: TextStyle(
                            fontSize: AppTypography.bodySmall,
                            color: theme.textSecondary,
                            fontFamily: 'monospace',
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: Spacing.sm),
                      ],

                      if (tc.result != null) ...[
                        Text(
                          'Result',
                          style: TextStyle(
                            fontSize: AppTypography.bodySmall,
                            color: theme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: Spacing.xxs),
                        SelectableText(
                          pretty(tc.result),
                          style: TextStyle(
                            fontSize: AppTypography.bodySmall,
                            color: theme.textSecondary,
                            fontFamily: 'monospace',
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedContent() {
    final children = <Widget>[];
    // Determine if media (attachments or generated images) is rendered above.
    final hasMediaAbove =
        (widget.message.attachmentIds?.isNotEmpty ?? false) ||
        (widget.message.files?.isNotEmpty ?? false);
    bool firstToolSpacerAdded = false;
    int idx = 0;
    for (final seg in _segments) {
      if (seg.isTool && seg.toolCall != null) {
        // Add top spacing before the first tool block for clarity
        if (!firstToolSpacerAdded) {
          children.add(const SizedBox(height: Spacing.sm));
          firstToolSpacerAdded = true;
        }
        children.add(_buildToolCallTile(seg.toolCall!));
      } else if (seg.isReasoning && seg.reasoning != null) {
        // If a reasoning tile is the very first content and sits at the top,
        // add a small spacer above it for breathing room.
        if (children.isEmpty && !hasMediaAbove) {
          children.add(const SizedBox(height: Spacing.sm));
        }
        children.add(_buildReasoningTile(seg.reasoning!, idx));
      } else if ((seg.text ?? '').trim().isNotEmpty) {
        children.add(_buildEnhancedMarkdownContent(seg.text!));
      }
      idx++;
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  bool get _hasRenderableSegments {
    bool textRenderable(String t) {
      String cleaned = t;
      // Hide tool_calls blocks entirely
      cleaned = cleaned.replaceAll(
        RegExp(
          r'<details\s+type="tool_calls"[^>]*>[\s\S]*?<\/details>',
          multiLine: true,
          dotAll: true,
        ),
        '',
      );
      // Hide reasoning blocks as well in text check
      cleaned = cleaned.replaceAll(
        RegExp(
          r'<details\s+type="reasoning"[^>]*>[\s\S]*?<\/details>',
          multiLine: true,
          dotAll: true,
        ),
        '',
      );
      // If last <details> is unclosed, drop tail to avoid rendering raw tag
      final lastOpen = cleaned.lastIndexOf('<details');
      if (lastOpen >= 0) {
        final tail = cleaned.substring(lastOpen);
        if (!tail.contains('</details>')) {
          cleaned = cleaned.substring(0, lastOpen);
        }
      }
      return cleaned.trim().isNotEmpty;
    }

    for (final seg in _segments) {
      if (seg.isTool && seg.toolCall != null) return true;
      if (seg.isReasoning && seg.reasoning != null) return true;
      final text = seg.text ?? '';
      if (textRenderable(text)) return true;
    }
    return false;
  }

  void _buildCachedAvatar() {
    final theme = context.conduitTheme;
    final iconUrl = widget.modelIconUrl?.trim();
    final hasIcon = iconUrl != null && iconUrl.isNotEmpty;

    final Widget leading = hasIcon
        ? ModelAvatar(size: 20, imageUrl: iconUrl, label: widget.modelName)
        : Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: theme.buttonPrimary,
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: theme.buttonPrimaryText,
              size: 12,
            ),
          );

    _cachedAvatar = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          leading,
          const SizedBox(width: Spacing.xs),
          Text(
            widget.modelName ?? 'Assistant',
            style: TextStyle(
              color: theme.textSecondary,
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
    _typingGateTimer?.cancel();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildDocumentationMessage();
  }

  Widget _buildDocumentationMessage() {
    final visibleStatusHistory = widget.message.statusHistory
        .where((status) => status.hidden != true)
        .toList(growable: false);
    final hasStatusTimeline = visibleStatusHistory.isNotEmpty;
    final hasCodeExecutions = widget.message.codeExecutions.isNotEmpty;
    final hasFollowUps =
        widget.message.followUps.isNotEmpty && !widget.isStreaming;
    final hasSources = widget.message.sources.isNotEmpty;

    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(
            bottom: 16,
            left: Spacing.xs,
            right: Spacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cached AI Name and Avatar to prevent flashing
              _cachedAvatar ?? const SizedBox.shrink(),

              // Reasoning blocks are now rendered inline where they appear

              // Documentation-style content without heavy bubble; premium markdown
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Display attachments - prioritize files array over attachmentIds to avoid duplication
                    if (widget.message.files != null &&
                        widget.message.files!.isNotEmpty) ...[
                      _buildFilesFromArray(),
                      const SizedBox(height: Spacing.md),
                    ] else if (widget.message.attachmentIds != null &&
                        widget.message.attachmentIds!.isNotEmpty) ...[
                      _buildAttachmentItems(),
                      const SizedBox(height: Spacing.md),
                    ],

                    if (hasStatusTimeline) ...[
                      StatusHistoryTimeline(updates: visibleStatusHistory),
                      const SizedBox(height: Spacing.md),
                    ],

                    // Tool calls are rendered inline via segmented content
                    // Smoothly crossfade between typing indicator and content
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) {
                        final fade = CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        );
                        final size = CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        );
                        return FadeTransition(
                          opacity: fade,
                          child: SizeTransition(
                            sizeFactor: size,
                            axisAlignment: -1.0, // collapse/expand from top
                            child: child,
                          ),
                        );
                      },
                      child:
                          (widget.isStreaming &&
                              !_hasRenderableSegments &&
                              _allowTypingIndicator)
                          ? KeyedSubtree(
                              key: const ValueKey('typing'),
                              child: _buildTypingIndicator(),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('content'),
                              child: _buildSegmentedContent(),
                            ),
                    ),

                    if (hasCodeExecutions) ...[
                      const SizedBox(height: Spacing.md),
                      CodeExecutionListView(
                        executions: widget.message.codeExecutions,
                      ),
                    ],

                    if (hasSources) ...[
                      const SizedBox(height: Spacing.md),
                      CitationListView(sources: widget.message.sources),
                    ],
                  ],
                ),
              ),

              // Action buttons below the message content (only after streaming completes)
              if (!widget.isStreaming) ...[
                const SizedBox(height: Spacing.sm),
                _buildActionButtons(),
                if (hasFollowUps) ...[
                  const SizedBox(height: Spacing.md),
                  FollowUpSuggestionBar(
                    suggestions: widget.message.followUps,
                    onSelected: _handleFollowUpTap,
                    isBusy: widget.isStreaming,
                  ),
                ],
              ],
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

    // Always hide tool_calls blocks; tiles render them separately.
    String cleaned = content.replaceAll(
      RegExp(
        r'<details\s+type="tool_calls"[^>]*>[\s\S]*?<\/details>',
        multiLine: true,
        dotAll: true,
      ),
      '',
    );
    // Also hide reasoning details blocks if any slipped into text
    cleaned = cleaned.replaceAll(
      RegExp(
        r'<details\s+type="reasoning"[^>]*>[\s\S]*?<\/details>',
        multiLine: true,
        dotAll: true,
      ),
      '',
    );
    // Remove raw <think>...</think> or <reasoning>...</reasoning> tags in text
    cleaned = cleaned
        .replaceAll(
          RegExp(r'<think>[\s\S]*?<\/think>', multiLine: true, dotAll: true),
          '',
        )
        .replaceAll(
          RegExp(
            r'<reasoning>[\s\S]*?<\/reasoning>',
            multiLine: true,
            dotAll: true,
          ),
          '',
        );

    // If there's an unclosed <details>, drop the tail to avoid raw tags.
    final lastOpen = cleaned.lastIndexOf('<details');
    if (lastOpen >= 0) {
      final tail = cleaned.substring(lastOpen);
      if (!tail.contains('</details>')) {
        cleaned = cleaned.substring(0, lastOpen);
      }
    }

    // Process images in the remaining text
    final processedContent = _processContentForImages(cleaned);

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
        final markdownCheck = RegExp(
          r'!\[.*?\]\(' + RegExp.escape(imageData) + r'\)',
        );
        if (!markdownCheck.hasMatch(content)) {
          return '\n![Generated Image]($imageData)\n';
        }
        return imageData;
      });
    }

    return content;
  }

  Widget _buildAttachmentItems() {
    if (widget.message.attachmentIds == null ||
        widget.message.attachmentIds!.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageCount = widget.message.attachmentIds!.length;

    // Display images in a clean, modern layout for assistant messages
    // Use AnimatedSwitcher for smooth transitions when loading
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      child: imageCount == 1
          ? Container(
              key: ValueKey('single_item_${widget.message.attachmentIds![0]}'),
              child: EnhancedAttachment(
                attachmentId: widget.message.attachmentIds![0],
                isMarkdownFormat: true,
                constraints: const BoxConstraints(
                  maxWidth: 500,
                  maxHeight: 400,
                ),
                disableAnimation: widget.isStreaming,
              ),
            )
          : Wrap(
              key: ValueKey(
                'multi_items_${widget.message.attachmentIds!.join('_')}',
              ),
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: widget.message.attachmentIds!.map<Widget>((
                attachmentId,
              ) {
                return EnhancedAttachment(
                  key: ValueKey('attachment_$attachmentId'),
                  attachmentId: attachmentId,
                  isMarkdownFormat: true,
                  constraints: BoxConstraints(
                    maxWidth: imageCount == 2 ? 245 : 160,
                    maxHeight: imageCount == 2 ? 245 : 160,
                  ),
                  disableAnimation: widget.isStreaming,
                );
              }).toList(),
            ),
    );
  }

  Widget _buildFilesFromArray() {
    if (widget.message.files == null || widget.message.files!.isEmpty) {
      return const SizedBox.shrink();
    }

    final allFiles = widget.message.files!;

    // Separate images and non-image files
    final imageFiles = allFiles
        .where((file) => file['type'] == 'image')
        .toList();
    final nonImageFiles = allFiles
        .where((file) => file['type'] != 'image')
        .toList();

    final widgets = <Widget>[];

    // Add images first
    if (imageFiles.isNotEmpty) {
      widgets.add(_buildImagesFromFiles(imageFiles));
    }

    // Add non-image files
    if (nonImageFiles.isNotEmpty) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: Spacing.sm));
      }
      widgets.add(_buildNonImageFiles(nonImageFiles));
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildImagesFromFiles(List<dynamic> imageFiles) {
    final imageCount = imageFiles.length;

    // Display images using EnhancedImageAttachment for consistency
    // Use AnimatedSwitcher for smooth transitions
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      child: imageCount == 1
          ? Container(
              key: ValueKey('file_single_${imageFiles[0]['url']}'),
              child: Builder(
                builder: (context) {
                  final imageUrl = imageFiles[0]['url'] as String?;
                  if (imageUrl == null) return const SizedBox.shrink();

                  return EnhancedImageAttachment(
                    attachmentId:
                        imageUrl, // Pass URL directly as it handles URLs
                    isMarkdownFormat: true,
                    constraints: const BoxConstraints(
                      maxWidth: 500,
                      maxHeight: 400,
                    ),
                    disableAnimation:
                        false, // Keep animations enabled to prevent black display
                  );
                },
              ),
            )
          : Wrap(
              key: ValueKey(
                'file_multi_${imageFiles.map((f) => f['url']).join('_')}',
              ),
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: imageFiles.map<Widget>((file) {
                final imageUrl = file['url'] as String?;
                if (imageUrl == null) return const SizedBox.shrink();

                return EnhancedImageAttachment(
                  key: ValueKey('gen_attachment_$imageUrl'),
                  attachmentId: imageUrl, // Pass URL directly
                  isMarkdownFormat: true,
                  constraints: BoxConstraints(
                    maxWidth: imageCount == 2 ? 245 : 160,
                    maxHeight: imageCount == 2 ? 245 : 160,
                  ),
                  disableAnimation:
                      false, // Keep animations enabled to prevent black display
                );
              }).toList(),
            ),
    );
  }

  Widget _buildNonImageFiles(List<dynamic> nonImageFiles) {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: nonImageFiles.map<Widget>((file) {
        final fileUrl = file['url'] as String?;

        if (fileUrl == null) return const SizedBox.shrink();

        // Extract file ID from URL if it's in the format /api/v1/files/{id}/content
        String attachmentId = fileUrl;
        if (fileUrl.contains('/api/v1/files/') &&
            fileUrl.contains('/content')) {
          final fileIdMatch = RegExp(
            r'/api/v1/files/([^/]+)/content',
          ).firstMatch(fileUrl);
          if (fileIdMatch != null) {
            attachmentId = fileIdMatch.group(1)!;
          }
        }

        return EnhancedAttachment(
          key: ValueKey('file_attachment_$attachmentId'),
          attachmentId: attachmentId,
          isMarkdownFormat: true,
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 100),
          disableAnimation: widget.isStreaming,
        );
      }).toList(),
    );
  }

  Widget _buildTypingIndicator() {
    return Consumer(
      builder: (context, ref, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Increase spacing between assistant name and typing indicator
            const SizedBox(height: Spacing.md),
            // Give the indicator breathing room to avoid any clip from transitions
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: SizedBox(
                height: 22,
                child: Platform.isIOS
                    ? _buildTypingPillBubble()
                    : _buildTypingEllipsis(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTypingEllipsis() {
    final min = AnimationValues.typingIndicatorScale;
    final dotColor = context.conduitTheme.textSecondary.withValues(alpha: 0.75);

    const double dotSize = 6.0;
    const double gap = Spacing.xs; // 4.0
    final d = AnimationDelay.typingDelay;
    final d2 = Duration(milliseconds: d.inMilliseconds * 2);

    Widget dot(Duration delay) {
      return Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          )
          .animate(onPlay: (controller) => controller.repeat())
          .then(delay: delay)
          .scale(
            duration: AnimationDuration.typingIndicator,
            curve: AnimationCurves.typingIndicator,
            begin: Offset(min, min),
            end: const Offset(1, 1),
          )
          .then(delay: AnimationDelay.typingDelay)
          .scale(
            duration: AnimationDuration.typingIndicator,
            curve: AnimationCurves.typingIndicator,
            begin: const Offset(1, 1),
            end: Offset(min, min),
          );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(Duration.zero),
        const SizedBox(width: gap),
        dot(d),
        const SizedBox(width: gap),
        dot(d2),
      ],
    );
  }

  Widget _buildTypingPillBubble() {
    final min = AnimationValues.typingIndicatorScale;

    final bubbleColor = context.conduitTheme.surfaceContainerHighest;
    final dotColor = context.conduitTheme.textSecondary.withValues(alpha: 0.75);

    const double dotSize = 6.0;
    const double gap = Spacing.xs; // 4.0
    const double padV = 6.0;
    const double padH = 10.0;

    final d = AnimationDelay.typingDelay;
    final d2 = Duration(milliseconds: d.inMilliseconds * 2);

    Widget dot(Duration delay) {
      return Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          )
          .animate(onPlay: (controller) => controller.repeat())
          .then(delay: delay)
          .scale(
            duration: AnimationDuration.typingIndicator,
            curve: AnimationCurves.typingIndicator,
            begin: Offset(min, min),
            end: const Offset(1, 1),
          )
          .then(delay: AnimationDelay.typingDelay)
          .scale(
            duration: AnimationDuration.typingIndicator,
            curve: AnimationCurves.typingIndicator,
            begin: const Offset(1, 1),
            end: Offset(min, min),
          );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(Duration.zero),
          const SizedBox(width: gap),
          dot(d),
          const SizedBox(width: gap),
          dot(d2),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final l10n = AppLocalizations.of(context)!;
    final ttsState = ref.watch(textToSpeechControllerProvider);
    final messageId = _messageId;
    final hasSpeechText = _ttsPlainText.trim().isNotEmpty;
    final isErrorMessage =
        widget.message.content.contains('⚠️') ||
        widget.message.content.contains('Error') ||
        widget.message.content.contains('timeout') ||
        widget.message.content.contains('retry options');

    final isActiveMessage = ttsState.activeMessageId == messageId;
    final isSpeaking =
        isActiveMessage && ttsState.status == TtsPlaybackStatus.speaking;
    final isPaused =
        isActiveMessage && ttsState.status == TtsPlaybackStatus.paused;
    final isBusy =
        isActiveMessage &&
        (ttsState.status == TtsPlaybackStatus.loading ||
            ttsState.status == TtsPlaybackStatus.initializing);
    final bool disableDueToStreaming = widget.isStreaming && !isActiveMessage;
    final bool ttsAvailable = !ttsState.initialized || ttsState.available;
    final bool showStopState =
        isActiveMessage && (isSpeaking || isPaused || isBusy);
    final bool shouldShowTtsButton = hasSpeechText && messageId.isNotEmpty;
    final bool canStartTts =
        shouldShowTtsButton && !disableDueToStreaming && ttsAvailable;

    VoidCallback? ttsOnTap;
    if (showStopState || canStartTts) {
      ttsOnTap = () {
        if (messageId.isEmpty) {
          return;
        }
        ref
            .read(textToSpeechControllerProvider.notifier)
            .toggleForMessage(messageId: messageId, text: _ttsPlainText);
      };
    }

    final IconData listenIcon = Platform.isIOS
        ? CupertinoIcons.speaker_2_fill
        : Icons.volume_up;
    final IconData stopIcon = Platform.isIOS
        ? CupertinoIcons.stop_fill
        : Icons.stop;
    final IconData ttsIcon = showStopState ? stopIcon : listenIcon;
    final String ttsLabel = showStopState ? l10n.ttsStop : l10n.ttsListen;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (shouldShowTtsButton)
          _buildActionButton(icon: ttsIcon, label: ttsLabel, onTap: ttsOnTap),
        _buildActionButton(
          icon: Platform.isIOS
              ? CupertinoIcons.doc_on_clipboard
              : Icons.content_copy,
          label: l10n.copy,
          onTap: widget.onCopy,
        ),
        if (isErrorMessage) ...[
          _buildActionButton(
            icon: Platform.isIOS
                ? CupertinoIcons.arrow_clockwise
                : Icons.refresh,
            label: l10n.retry,
            onTap: widget.onRegenerate,
          ),
        ] else ...[
          _buildActionButton(
            icon: Platform.isIOS ? CupertinoIcons.refresh : Icons.refresh,
            label: l10n.regenerate,
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
    return ChatActionButton(icon: icon, label: label, onTap: onTap);
  }

  // Reasoning tile rendered inline at the position it appears
  Widget _buildReasoningTile(ReasoningEntry rc, int index) {
    final isExpanded = _expandedReasoning.contains(index);
    final theme = context.conduitTheme;

    String headerText() {
      final l10n = AppLocalizations.of(context)!;
      final hasSummary = rc.summary.isNotEmpty;
      final isThinkingSummary =
          rc.summary.trim().toLowerCase() == 'thinking…' ||
          rc.summary.trim().toLowerCase() == 'thinking...';
      if (widget.isStreaming) {
        return hasSummary ? rc.summary : l10n.thinking;
      }
      if (rc.duration > 0) {
        return l10n.thoughtForDuration(rc.formattedDuration);
      }
      if (!hasSummary || isThinkingSummary) {
        return l10n.thoughts;
      }
      return rc.summary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedReasoning.remove(index);
            } else {
              _expandedReasoning.add(index);
            }
          });
        },
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: theme.surfaceContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            border: Border.all(
              color: theme.dividerColor,
              width: BorderWidth.thin,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: theme.textSecondary,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Icon(
                    Icons.psychology_outlined,
                    size: 14,
                    color: theme.buttonPrimary,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Flexible(
                    child: Text(
                      headerText(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        color: theme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  margin: const EdgeInsets.only(top: Spacing.sm),
                  padding: const EdgeInsets.all(Spacing.sm),
                  decoration: BoxDecoration(
                    color: theme.surfaceContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    border: Border.all(
                      color: theme.dividerColor,
                      width: BorderWidth.thin,
                    ),
                  ),
                  child: SelectableText(
                    rc.cleanedReasoning,
                    style: TextStyle(
                      fontSize: AppTypography.bodySmall,
                      color: theme.textSecondary,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantResponseSection extends StatelessWidget {
  const _AssistantResponseSection({
    required this.title,
    required this.child,
    this.icon,
  });

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: theme.buttonPrimary),
              const SizedBox(width: Spacing.xs),
            ],
            Text(
              title,
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.card),
            border: Border.all(
              color: theme.cardBorder.withValues(alpha: 0.6),
              width: BorderWidth.thin,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ],
    );
  }
}

class _AssistantSuggestionChip extends StatelessWidget {
  const _AssistantSuggestionChip({
    required this.label,
    this.icon,
    this.onPressed,
    this.enabled = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final effectiveOnPressed = enabled ? onPressed : null;
    final iconColor = enabled
        ? theme.textSecondary
        : theme.textSecondary.withValues(alpha: 0.5);

    final background = theme.cardBackground.withValues(
      alpha: enabled ? 0.95 : 0.85,
    );
    final borderColor = theme.cardBorder.withValues(
      alpha: enabled ? 0.6 : 0.35,
    );

    return RawChip(
      avatar: icon != null ? Icon(icon, size: 16, color: iconColor) : null,
      label: Text(
        label,
        style: TextStyle(
          color: enabled ? theme.textPrimary : theme.textSecondary,
          fontSize: AppTypography.labelMedium,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
      onPressed: effectiveOnPressed,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xxs,
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: background,
      disabledColor: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.pill),
        side: BorderSide(color: borderColor, width: BorderWidth.thin),
      ),
    );
  }
}

class StatusHistoryTimeline extends StatelessWidget {
  const StatusHistoryTimeline({super.key, required this.updates});

  final List<ChatStatusUpdate> updates;

  @override
  Widget build(BuildContext context) {
    if (updates.isEmpty) {
      return const SizedBox.shrink();
    }

    return _AssistantResponseSection(
      title: 'Status updates',
      icon: Icons.sync_alt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Spacing.xs),
          for (var index = 0; index < updates.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == updates.length - 1 ? 0 : Spacing.xs,
              ),
              child: _StatusHistoryEntry(update: updates[index]),
            ),
        ],
      ),
    );
  }
}

class _StatusHistoryEntry extends StatelessWidget {
  const _StatusHistoryEntry({required this.update});

  final ChatStatusUpdate update;

  Color _indicatorColor(ConduitThemeExtension theme) {
    if (update.done == false) {
      return theme.buttonPrimary;
    }
    if (update.done == true) {
      return theme.success;
    }
    return theme.textSecondary;
  }

  IconData _indicatorIcon() {
    if (update.done == false) {
      return Icons.timelapse;
    }
    if (update.done == true) {
      return Icons.check_circle;
    }
    return Icons.radio_button_unchecked;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    final indicatorColor = _indicatorColor(theme);
    final description = update.description?.trim().isNotEmpty == true
        ? update.description!.trim()
        : (update.action?.isNotEmpty == true
              ? update.action!.replaceAll('_', ' ')
              : 'Processing');
    final timestamp = update.occurredAt;
    final queries = [...update.queries];
    if (update.query != null && update.query!.trim().isNotEmpty) {
      if (!queries.contains(update.query)) {
        queries.add(update.query!.trim());
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: theme.cardBorder.withValues(alpha: 0.5),
          width: BorderWidth.thin,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_indicatorIcon(), size: 16, color: indicatorColor),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        color: theme.textSecondary,
                        fontWeight: update.done == true
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (update.count != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xxs),
                        child: Text(
                          update.count == 1
                              ? 'Retrieved 1 source'
                              : 'Retrieved ${update.count} sources',
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: AppTypography.labelSmall,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (timestamp != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xxs),
                        child: Text(
                          _formatTimestamp(timestamp),
                          style: TextStyle(
                            color: theme.textSecondary.withValues(alpha: 0.8),
                            fontSize: AppTypography.labelSmall,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (queries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: queries.map((query) {
                  return _AssistantSuggestionChip(
                    label: query,
                    icon: Icons.search,
                    onPressed: () {
                      _launchUri(
                        'https://www.google.com/search?q=${Uri.encodeComponent(query)}',
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          if (update.urls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Wrap(
                spacing: Spacing.xs,
                runSpacing: Spacing.xs,
                children: update.urls.map((url) {
                  final host = Uri.tryParse(url)?.host ?? 'Link';
                  return _AssistantSuggestionChip(
                    label: host,
                    icon: Icons.open_in_new,
                    onPressed: () => _launchUri(url),
                  );
                }).toList(),
              ),
            ),
          if (update.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: update.items.map((item) {
                  final title = item.title?.isNotEmpty == true
                      ? item.title!
                      : item.link ?? 'Result';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.xs),
                    child: InkWell(
                      onTap: item.link != null
                          ? () => _launchUri(item.link!)
                          : null,
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.xxs,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.link,
                              size: 16,
                              color: theme.textSecondary,
                            ),
                            const SizedBox(width: Spacing.xs),
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: item.link != null
                                      ? theme.buttonPrimary
                                      : theme.textSecondary,
                                  decoration: item.link != null
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                  fontSize: AppTypography.bodySmall,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);
    if (difference.inMinutes < 1) {
      return 'Just now';
    }
    if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
    }
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class CodeExecutionListView extends StatelessWidget {
  const CodeExecutionListView({super.key, required this.executions});

  final List<ChatCodeExecution> executions;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    if (executions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Code executions',
          style: TextStyle(
            color: theme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.bodyLarge,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          children: executions.map((execution) {
            final hasError = execution.result?.error != null;
            final hasOutput = execution.result?.output != null;
            IconData icon;
            Color iconColor;
            if (hasError) {
              icon = Icons.error_outline;
              iconColor = theme.error;
            } else if (hasOutput) {
              icon = Icons.check_circle_outline;
              iconColor = theme.success;
            } else {
              icon = Icons.sync;
              iconColor = theme.textSecondary;
            }
            final label = execution.name?.isNotEmpty == true
                ? execution.name!
                : 'Execution';
            return ActionChip(
              avatar: Icon(icon, size: 16, color: iconColor),
              label: Text(label),
              onPressed: () => _showCodeExecutionDetails(context, execution),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _showCodeExecutionDetails(
    BuildContext context,
    ChatCodeExecution execution,
  ) async {
    final theme = context.conduitTheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.surfaceBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.dialog),
        ),
      ),
      builder: (ctx) {
        final result = execution.result;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          execution.name ?? 'Code execution',
                          style: TextStyle(
                            fontSize: AppTypography.bodyLarge,
                            fontWeight: FontWeight.w600,
                            color: theme.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.sm),
                  if (execution.language != null)
                    Text(
                      'Language: ${execution.language}',
                      style: TextStyle(color: theme.textSecondary),
                    ),
                  const SizedBox(height: Spacing.sm),
                  if (execution.code != null && execution.code!.isNotEmpty) ...[
                    Text(
                      'Code',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Container(
                      padding: const EdgeInsets.all(Spacing.sm),
                      decoration: BoxDecoration(
                        color: theme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      ),
                      child: SelectableText(
                        execution.code!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                  ],
                  if (result?.error != null) ...[
                    Text(
                      'Error',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.error,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    SelectableText(result!.error!),
                    const SizedBox(height: Spacing.md),
                  ],
                  if (result?.output != null) ...[
                    Text(
                      'Output',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    SelectableText(result!.output!),
                    const SizedBox(height: Spacing.md),
                  ],
                  if (result?.files.isNotEmpty == true) ...[
                    Text(
                      'Files',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    ...result!.files.map((file) {
                      final name = file.name ?? file.url ?? 'Download';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(name),
                        onTap: file.url != null
                            ? () => _launchUri(file.url!)
                            : null,
                        trailing: file.url != null
                            ? const Icon(Icons.open_in_new)
                            : null,
                      );
                    }),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class CitationListView extends StatelessWidget {
  const CitationListView({super.key, required this.sources});

  final List<ChatSourceReference> sources;

  @override
  Widget build(BuildContext context) {
    final theme = context.conduitTheme;
    if (sources.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sources.length == 1 ? 'Source' : 'Sources',
          style: TextStyle(
            color: theme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: AppTypography.bodyLarge,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        ...sources.map((source) {
          final title = source.title?.isNotEmpty == true
              ? source.title!
              : source.url ?? 'Citation';
          final subtitle = source.snippet?.isNotEmpty == true
              ? source.snippet!
              : source.url;

          return Card(
            margin: const EdgeInsets.only(bottom: Spacing.xs),
            color: theme.surfaceContainer,
            child: ListTile(
              onTap: source.url != null ? () => _launchUri(source.url!) : null,
              title: Text(title, style: TextStyle(color: theme.textPrimary)),
              subtitle: subtitle != null
                  ? Text(subtitle, style: TextStyle(color: theme.textSecondary))
                  : null,
              trailing: source.url != null
                  ? const Icon(Icons.open_in_new, size: 18)
                  : null,
            ),
          );
        }),
      ],
    );
  }
}

class FollowUpSuggestionBar extends StatelessWidget {
  const FollowUpSuggestionBar({
    super.key,
    required this.suggestions,
    required this.onSelected,
    required this.isBusy,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final trimmedSuggestions = suggestions
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    if (trimmedSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return _AssistantResponseSection(
      title: 'Suggested next steps',
      icon: Icons.auto_awesome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Spacing.xs),
          Wrap(
            spacing: Spacing.xs,
            runSpacing: Spacing.xs,
            children: [
              for (final suggestion in trimmedSuggestions)
                _AssistantSuggestionChip(
                  label: suggestion,
                  onPressed: isBusy ? null : () => onSelected(suggestion),
                  enabled: !isBusy,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _launchUri(String url) async {
  if (url.isEmpty) return;
  try {
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  } catch (err) {
    DebugLogger.log('Unable to open url $url: $err', scope: 'chat/assistant');
  }
}
