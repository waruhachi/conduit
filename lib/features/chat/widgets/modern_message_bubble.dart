import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;
import '../../../core/providers/app_providers.dart';

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
  static const int _maxCachedImages = 24;

  // Cache for image base64 data to prevent repeated API calls
  final Map<String, String?> _imageCache = {};

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
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(
            bottom: Spacing.messagePadding,
            left: Spacing.xxxl,
            right: Spacing.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _toggleActions(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.messagePadding,
                      vertical: Spacing.sm,
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
                      boxShadow: ConduitShadows.high,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display images if any
                        if (widget.message.attachmentIds != null &&
                            widget.message.attachmentIds!.isNotEmpty)
                          _buildAttachmentImages(),

                        // Display text content if any
                        if (widget.message.content.isNotEmpty) ...[
                          if (widget.message.attachmentIds != null &&
                              widget.message.attachmentIds!.isNotEmpty)
                            const SizedBox(height: Spacing.sm),
                          _buildCustomText(
                            widget.message.content,
                            context.conduitTheme.chatBubbleUserText,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
    return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(
            bottom: Spacing.lg,
            left: Spacing.xs,
            right: Spacing.xxxl,
          ),
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

              // Message Content
              GestureDetector(
                onLongPress: () => _toggleActions(),
                child: Container(
                  padding: const EdgeInsets.all(Spacing.messagePadding),
                  decoration: BoxDecoration(
                    color: context.conduitTheme.chatBubbleAssistant,
                    borderRadius: BorderRadius.circular(
                      AppBorderRadius.messageBubble,
                    ),
                    border: Border.all(
                      color: context.conduitTheme.chatBubbleAssistantBorder,
                      width: BorderWidth.regular,
                    ),
                    boxShadow: ConduitShadows.low,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Check for typing indicator - show for empty content OR explicit typing indicator during streaming
                      if ((widget.message.content.isEmpty ||
                              widget.message.content == '[TYPING_INDICATOR]') &&
                          widget.isStreaming) ...[
                        _buildTypingIndicator(),
                      ] else if (widget.message.content.isNotEmpty &&
                          widget.message.content != '[TYPING_INDICATOR]') ...[
                        _buildCustomText(
                          widget.message.content,
                          context.conduitTheme.chatBubbleAssistantText,
                        ),
                      ] else
                        // Fallback: show empty state for non-streaming empty messages
                        const SizedBox.shrink(),

                      // Action buttons
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
        .fadeIn(duration: AnimationDuration.messageAppear)
        .slideX(
          begin: -AnimationValues.messageSlideDistance,
          end: 0,
          duration: AnimationDuration.messageSlide,
          curve: AnimationCurves.messageSlide,
        );
  }

  Widget _buildAttachmentImages() {
    if (widget.message.attachmentIds == null ||
        widget.message.attachmentIds!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.message.attachmentIds!.map<Widget>((attachmentId) {
        return Consumer(
          builder: (context, ref, child) {
            final api = ref.watch(apiServiceProvider);
            if (api == null) return const SizedBox.shrink();

            return FutureBuilder<String?>(
              future: _getCachedImageBase64(api, attachmentId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    height: 150,
                    width: 200,
                    margin: const EdgeInsets.only(bottom: Spacing.xs),
                    decoration: BoxDecoration(
                      color: context.conduitTheme.surfaceBackground.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: context.conduitTheme.buttonPrimary,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }

                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data == null) {
                  return Container(
                    height: 100,
                    width: 150,
                    margin: const EdgeInsets.only(bottom: Spacing.xs),
                    decoration: BoxDecoration(
                      color: context.conduitTheme.surfaceBackground.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                      border: Border.all(
                        color: context.conduitTheme.textSecondary.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          color: context.conduitTheme.textSecondary,
                          size: 32,
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Image unavailable',
                          style: TextStyle(
                            color: context.conduitTheme.textSecondary,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final base64Data = snapshot.data!;
                try {
                  // Handle data URLs (data:image/...;base64,...)
                  String actualBase64;
                  if (base64Data.startsWith('data:')) {
                    // Extract base64 part from data URL
                    final commaIndex = base64Data.indexOf(',');
                    if (commaIndex != -1) {
                      actualBase64 = base64Data.substring(commaIndex + 1);
                    } else {
                      throw Exception('Invalid data URL format');
                    }
                  } else {
                    // Direct base64 string
                    actualBase64 = base64Data;
                  }

                  final imageBytes = base64.decode(actualBase64);
                  return Container(
                    margin: const EdgeInsets.only(bottom: Spacing.xs),
                    constraints: const BoxConstraints(
                      maxWidth: 300,
                      maxHeight: 300,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 100,
                            width: 150,
                            decoration: BoxDecoration(
                              color: context.conduitTheme.surfaceBackground
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(
                                AppBorderRadius.sm,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: context.conduitTheme.error,
                                  size: 32,
                                ),
                                const SizedBox(height: Spacing.xs),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(
                                    color: context.conduitTheme.error,
                                    fontSize: AppTypography.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                } catch (e) {
                  return Container(
                    height: 100,
                    width: 150,
                    margin: const EdgeInsets.only(bottom: Spacing.xs),
                    decoration: BoxDecoration(
                      color: context.conduitTheme.surfaceBackground.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: context.conduitTheme.error,
                          size: 32,
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Invalid image format',
                          style: TextStyle(
                            color: context.conduitTheme.error,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            );
          },
        );
      }).toList(),
    );
  }

  Future<String?> _getCachedImageBase64(dynamic api, String fileId) async {
    // Check cache first to prevent repeated API calls
    if (_imageCache.containsKey(fileId)) {
      return _imageCache[fileId];
    }

    // If not in cache, get the image and cache it
    final result = await _getImageBase64(api, fileId);
    // Simple LRU-like eviction to bound memory
    if (_imageCache.length >= _maxCachedImages) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[fileId] = result;
    return result;
  }

  Future<String?> _getImageBase64(dynamic api, String fileId) async {
    try {
      // Check if this is already a data URL (for images)
      if (fileId.startsWith('data:')) {
        return fileId;
      }

      // First, get file info to determine if it's an image
      final fileInfo = await api.getFileInfo(fileId);
      final fileName =
          fileInfo['filename'] ??
          fileInfo['meta']?['name'] ??
          fileInfo['name'] ??
          fileInfo['file_name'] ??
          fileInfo['original_name'] ??
          fileInfo['original_filename'] ??
          '';
      final ext = fileName.toLowerCase().split('.').last;

      // Only process image files
      if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        debugPrint('DEBUG: Skipping non-image file: $fileName');
        return null;
      }

      // Get file content as base64 string
      final fileContent = await api.getFileContent(fileId);
      return fileContent;
    } catch (e) {
      debugPrint('DEBUG: Error getting image content for $fileId: $e');
      return null;
    }
  }

  Widget _buildCustomText(String text, [Color? textColor]) {
    // Simple markdown-like parsing for efficiency
    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        if (i < lines.length - 1) {
          widgets.add(const SizedBox(height: Spacing.sm));
        }
        continue;
      }

      // Parse basic markdown
      Widget textWidget = _parseMarkdownLine(line, textColor);

      if (i < lines.length - 1) {
        widgets.add(textWidget);
        widgets.add(const SizedBox(height: Spacing.xs));
      } else {
        widgets.add(textWidget);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _parseMarkdownLine(String line, [Color? textColor]) {
    // Handle code blocks
    if (line.startsWith('```')) {
      return Container(
            margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: context.conduitTheme.surfaceBackground.withValues(
                alpha: Alpha.badgeBackground,
              ),
              borderRadius: BorderRadius.circular(AppBorderRadius.sm),
              border: Border.all(
                color: context.conduitTheme.textPrimary.withValues(
                  alpha: Alpha.subtle,
                ),
                width: BorderWidth.regular,
              ),
            ),
            child: Text(
              line.substring(3),
              style: AppTypography.chatCodeStyle.copyWith(
                color: textColor ?? context.conduitTheme.textSecondary,
              ),
            ),
          )
          .animate()
          .fadeIn(duration: AnimationDuration.microInteraction)
          .slideX(
            begin: 0.1,
            end: 0,
            duration: AnimationDuration.microInteraction,
          );
    }

    // Handle headers
    if (line.startsWith('#')) {
      int level = 0;
      while (level < line.length && line[level] == '#') {
        level++;
      }
      final fontSize = AppTypography.headlineMedium - (level * 2);
      return Text(
            line.substring(level).trim(),
            style: AppTypography.headlineMediumStyle.copyWith(
              color: textColor ?? context.conduitTheme.textPrimary,
              fontSize: fontSize.toDouble(),
            ),
          )
          .animate()
          .fadeIn(duration: AnimationDuration.microInteraction)
          .slideX(
            begin: 0.1,
            end: 0,
            duration: AnimationDuration.microInteraction,
          );
    }

    // Handle inline code
    if (line.contains('`')) {
      final parts = line.split('`');
      final widgets = <Widget>[];

      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          if (i % 2 == 1) {
            // Inline code
            widgets.add(
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xs + Spacing.xxs,
                  vertical: Spacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: context.conduitTheme.textPrimary.withValues(
                    alpha: Alpha.badgeBackground,
                  ),
                  borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                ),
                child: Text(
                  parts[i],
                  style: AppTypography.chatCodeStyle.copyWith(
                    color: textColor ?? context.conduitTheme.textSecondary,
                  ),
                ),
              ),
            );
          } else {
            // Regular text
            widgets.add(
              Text(
                parts[i],
                style: AppTypography.chatMessageStyle.copyWith(
                  color: textColor ?? context.conduitTheme.textPrimary,
                ),
              ),
            );
          }
        }
      }

      return Wrap(
            crossAxisAlignment: WrapCrossAlignment.start,
            children: widgets,
          )
          .animate()
          .fadeIn(duration: AnimationDuration.microInteraction)
          .slideX(
            begin: 0.1,
            end: 0,
            duration: AnimationDuration.microInteraction,
          );
    }

    // Regular text
    return Text(
          line,
          style: AppTypography.chatMessageStyle.copyWith(
            color: textColor ?? context.conduitTheme.textPrimary,
            letterSpacing: 0.1,
          ),
        )
        .animate()
        .fadeIn(duration: AnimationDuration.microInteraction)
        .slideX(
          begin: 0.1,
          end: 0,
          duration: AnimationDuration.microInteraction,
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
