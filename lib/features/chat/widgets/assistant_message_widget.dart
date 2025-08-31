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
import '../../../core/utils/tool_calls_parser.dart';
import 'enhanced_image_attachment.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'enhanced_attachment.dart';

class AssistantMessageWidget extends ConsumerStatefulWidget {
  final dynamic message;
  final bool isStreaming;
  final String? modelName;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;

  const AssistantMessageWidget({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.modelName,
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
  bool _showReasoning = false;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  ReasoningContent? _reasoningContent;
  List<ToolCallsSegment> _toolSegments = const [];
  final Set<String> _expandedToolIds = {};
  Widget? _cachedAvatar;
  String _contentSansDetails = '';
  bool _allowTypingIndicator = false;
  Timer? _typingGateTimer;

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

    // Rebuild cached avatar if model name changes
    if (oldWidget.modelName != widget.modelName) {
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
    // Do not truncate content during streaming; segmented parser will skip
    // incomplete details blocks and tiles will render once complete.
    final rc = ReasoningParser.parseReasoningContent(raw);
    String base = rc?.mainContent ?? raw;

    final tools = ToolCallsParser.parse(base);
    List<ToolCallsSegment>? segments = ToolCallsParser.segments(base);

    // Fallback: if parser failed but content has tool_calls details, synthesize segments
    if ((segments == null || segments.isEmpty) && base.contains('<details') && base.contains('type="tool_calls"')) {
      final fallbackSegs = <ToolCallsSegment>[];
      final detailsRegex = RegExp(r'<details[^>]*>([\s\S]*?)<\/details>', multiLine: true, dotAll: true);
      final attrRegex = RegExp(r'(\w+)="([^"]*)"');
      final matches = detailsRegex.allMatches(base).toList();
      String textRemainder = base;
      for (final m in matches) {
        final full = m.group(0) ?? '';
        final openTag = RegExp(r'<details[^>]*>').firstMatch(full)?.group(0) ?? '';
        if (!openTag.contains('type="tool_calls"')) continue;
        final attrs = <String, String>{};
        for (final am in attrRegex.allMatches(openTag)) {
          attrs[am.group(1)!] = am.group(2) ?? '';
        }
        final id = attrs['id'] ?? '';
        final name = attrs['name'] ?? 'tool';
        final done = (attrs['done'] == 'true');
        final args = attrs['arguments'];
        final result = attrs['result'];
        final files = attrs['files'];

        dynamic decodeMaybe(String? s) {
          if (s == null || s.isEmpty) return null;
          try {
            return json.decode(s);
          } catch (_) {
            return s;
          }
        }

        final entry = ToolCallEntry(
          id: id.isNotEmpty ? id : '${name}_${m.start}',
          name: name,
          done: done,
          arguments: decodeMaybe(args),
          result: decodeMaybe(result),
          files: (decodeMaybe(files) is List) ? decodeMaybe(files) as List : null,
        );
        fallbackSegs.add(ToolCallsSegment.entry(entry));
        textRemainder = textRemainder.replaceFirst(full, '');
      }
      if (fallbackSegs.isNotEmpty) {
        final remainder = textRemainder.trim();
        if (remainder.isNotEmpty) {
          fallbackSegs.add(ToolCallsSegment.text(remainder));
        }
        segments = fallbackSegs;
      }
    }

    setState(() {
      _reasoningContent = rc;
      _contentSansDetails = tools?.mainContent ?? base;
      _toolSegments = segments ?? [ToolCallsSegment.text(_contentSansDetails)];
    });
    _updateTypingIndicatorGate();
  }

  void _updateTypingIndicatorGate() {
    // Only show typing indicator if streaming and nothing renderable yet,
    // and only after a short delay to avoid flicker when content arrives quickly.
    _typingGateTimer?.cancel();
    final hasRenderable = _hasRenderableSegments;
    final contentEmpty = (widget.message.content ?? '').trim().isEmpty;
    if (widget.isStreaming && !hasRenderable && contentEmpty) {
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

  // No streaming-specific markdown fixes needed here; handled by Markdown widget

  Widget _buildToolCallTile(ToolCallEntry tc) {
    final isExpanded = _expandedToolIds.contains(tc.id);
    final theme = context.conduitTheme;

    String _pretty(dynamic v, {int max = 1200}) {
      try {
        final pretty = const JsonEncoder.withIndent('  ').convert(v);
        return pretty.length > max ? pretty.substring(0, max) + '\n…' : pretty;
      } catch (_) {
        final s = v?.toString() ?? '';
        return s.length > max ? s.substring(0, max) + '…' : s;
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
                    tc.done ? Icons.build_circle_outlined : Icons.play_circle_outline,
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
                          _pretty(tc.arguments),
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
                          _pretty(tc.result),
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
                crossFadeState:
                    isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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
    bool firstToolSpacerAdded = false;
    for (final seg in _toolSegments) {
      if (seg.isToolCall && seg.entry != null) {
        // Add top spacing before the first tool block for clarity
        if (!firstToolSpacerAdded) {
          children.add(const SizedBox(height: Spacing.sm));
          firstToolSpacerAdded = true;
        }
        children.add(_buildToolCallTile(seg.entry!));
      } else if ((seg.text ?? '').trim().isNotEmpty) {
        children.add(
          _buildEnhancedMarkdownContent(seg.text!),
        );
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  bool get _hasRenderableSegments {
    for (final seg in _toolSegments) {
      if ((seg.isToolCall && seg.entry != null) ||
          ((seg.text ?? '').trim().isNotEmpty)) {
        return true;
      }
    }
    return false;
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
              borderRadius: BorderRadius.circular(AppBorderRadius.small),
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
                          () {
                            final l10n = AppLocalizations.of(context)!;
                            final rc = _reasoningContent!;
                            final hasSummary = rc.summary.isNotEmpty;
                            final isThinkingSummary = rc.summary.trim().toLowerCase() == 'thinking…' || rc.summary.trim().toLowerCase() == 'thinking...';
                            if (widget.isStreaming) {
                              // During streaming, prefer showing Thinking…
                              return hasSummary ? rc.summary : l10n.thinking;
                            }
                            // After streaming ends:
                            if (rc.duration > 0) {
                              return l10n.thoughtForDuration(rc.formattedDuration);
                            }
                            // If summary was just the placeholder 'Thinking…', replace with a neutral title
                            if (!hasSummary || isThinkingSummary) {
                              return l10n.thoughts;
                            }
                            return rc.summary;
                          }(),
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

                const SizedBox(height: 0),
              ],

              // Documentation-style content without heavy bubble; premium markdown
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Display attachments (images use EnhancedImageAttachment; non-images use card)
                    if (widget.message.attachmentIds != null &&
                        widget.message.attachmentIds!.isNotEmpty) ...[
                      _buildAttachmentItems(),
                      const SizedBox(height: Spacing.md),
                    ],

                    // Display generated images from files property
                    if (widget.message.files != null &&
                        widget.message.files!.isNotEmpty) ...[
                      _buildGeneratedImages(),
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
                      child: (!_hasRenderableSegments &&
                              _allowTypingIndicator &&
                              widget.isStreaming &&
                              (widget.message.content.trim().isEmpty ||
                                  widget.message.content ==
                                      '[TYPING_INDICATOR]'))
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

    // For streaming, hide any tool_calls <details> blocks that may be incomplete
    // to avoid showing raw tag text; tiles will render once blocks complete.
    String cleaned = content;
    if (widget.isStreaming) {
      cleaned = cleaned.replaceAll(
        RegExp(
          r'<details\s+type="tool_calls"[^>]*>[\s\S]*?<\/details>',
          multiLine: true,
          dotAll: true,
        ),
        '',
      );
      final lastOpen = cleaned.lastIndexOf('<details');
      if (lastOpen >= 0) {
        final tail = cleaned.substring(lastOpen);
        if (!tail.contains('</details>')) {
          cleaned = cleaned.substring(0, lastOpen);
        }
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

  Widget _buildGeneratedImages() {
    if (widget.message.files == null || widget.message.files!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Filter for image files
    final imageFiles = widget.message.files!
        .where((file) => file['type'] == 'image')
        .toList();

    if (imageFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    final imageCount = imageFiles.length;

    // Display generated images using EnhancedImageAttachment for consistency
    // Use AnimatedSwitcher for smooth transitions
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      child: imageCount == 1
          ? Container(
              key: ValueKey('gen_single_${imageFiles[0]['url']}'),
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
                    disableAnimation: widget
                        .isStreaming, // Disable animation during streaming
                  );
                },
              ),
            )
          : Wrap(
              key: ValueKey(
                'gen_multi_${imageFiles.map((f) => f['url']).join('_')}',
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
                      widget.isStreaming, // Disable animation during streaming
                );
              }).toList(),
            ),
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
    final isErrorMessage =
        widget.message.content.contains('⚠️') ||
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
          label: AppLocalizations.of(context)!.copy,
          onTap: widget.onCopy,
        ),
        if (isErrorMessage) ...[
          _buildActionButton(
            icon: Platform.isIOS
                ? CupertinoIcons.arrow_clockwise
                : Icons.refresh,
            label: AppLocalizations.of(context)!.retry,
            onTap: widget.onRegenerate,
          ),
        ] else ...[
          _buildActionButton(
            icon: Platform.isIOS ? CupertinoIcons.refresh : Icons.refresh,
            label: AppLocalizations.of(context)!.regenerate,
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
}
