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
import '../providers/text_to_speech_provider.dart';
import 'enhanced_image_attachment.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'enhanced_attachment.dart';
import 'package:conduit/shared/widgets/chat_action_button.dart';
import '../../../shared/widgets/model_avatar.dart';

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
                  ],
                ),
              ),

              // Action buttons below the message content (only after streaming completes)
              if (!widget.isStreaming) ...[
                const SizedBox(height: Spacing.sm),
                _buildActionButtons(),
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
