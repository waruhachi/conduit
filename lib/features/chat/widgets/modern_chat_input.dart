import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'dart:io' show Platform;
import 'dart:async';
import '../providers/chat_providers.dart';

import '../../../shared/utils/platform_utils.dart';

class ModernChatInput extends ConsumerStatefulWidget {
  final Function(String) onSendMessage;
  final bool enabled;
  final Function()? onVoiceInput;
  final Function()? onFileAttachment;
  final Function()? onImageAttachment;
  final Function()? onCameraCapture;

  const ModernChatInput({
    super.key,
    required this.onSendMessage,
    this.enabled = true,
    this.onVoiceInput,
    this.onFileAttachment,
    this.onImageAttachment,
    this.onCameraCapture,
  });

  @override
  ConsumerState<ModernChatInput> createState() => _ModernChatInputState();
}

class _ModernChatInputState extends ConsumerState<ModernChatInput>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final bool _isRecording = false;
  bool _isExpanded = true; // Start expanded for better UX
  // TODO: Implement voice input functionality
  // final String _voiceInputText = '';
  bool _hasText = false; // track locally without rebuilding on each keystroke
  StreamSubscription<String>? _voiceStreamSubscription;
  late AnimationController _expandController;
  late AnimationController _pulseController;
  Timer? _blurCollapseTimer;
  bool _hasAutoFocusedOnce = false;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration:
          AnimationDuration.fast, // Faster animation for better responsiveness
      vsync: this,
      value: 1.0, // Start expanded
    );
    _pulseController = AnimationController(
      duration: AnimationDuration.slow,
      vsync: this,
    );

    // Listen for text changes and update only when emptiness flips
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _hasText = has);
          // Intelligent expansion: expand when user starts typing
          if (has && !_isExpanded) {
            _setExpanded(true);
          }
        });
      }
    });

    // Intelligent expand/collapse around focus changes
    _focusNode.addListener(() {
      // Cancel any pending blur-driven collapse
      _blurCollapseTimer?.cancel();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final hasFocus = _focusNode.hasFocus;
        if (hasFocus) {
          if (!_isExpanded) _setExpanded(true);
        } else {
          // Defer collapse slightly to avoid IME show/hide race conditions
          _blurCollapseTimer = Timer(const Duration(milliseconds: 160), () {
            if (!mounted) return;
            if (_focusNode.hasFocus) return; // focus came back
            // Collapse only when keyboard is fully hidden to avoid flicker
            final keyboardVisible =
                MediaQuery.of(context).viewInsets.bottom > 0;
            if (keyboardVisible) return;
            final has = _controller.text.trim().isNotEmpty;
            if (!has && _isExpanded) {
              _setExpanded(false);
            }
          });
        }
      });
    });

    // Let autofocus handle the focus - no manual intervention
    // The TextField's autofocus: true should handle focus and keyboard automatically
    // Additionally, request focus after first frame to ensure reliability across platforms
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_hasAutoFocusedOnce && widget.enabled) {
        _ensureFocusedIfEnabled();
        _hasAutoFocusedOnce = true;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _expandController.dispose();
    _pulseController.dispose();
    _blurCollapseTimer?.cancel();
    _voiceStreamSubscription?.cancel();
    super.dispose();
  }

  void _ensureFocusedIfEnabled() {
    if (!widget.enabled) return;
    if (!_focusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  @override
  void didUpdateWidget(covariant ModernChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled && !_hasAutoFocusedOnce) {
      // Became enabled (e.g., after selecting a model) → focus the input
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureFocusedIfEnabled();
        _hasAutoFocusedOnce = true;
      });
    }
    if (!widget.enabled && oldWidget.enabled) {
      // Became disabled → collapse and hide keyboard
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isExpanded) _setExpanded(false);
        if (_focusNode.hasFocus) {
          _focusNode.unfocus();
        }
      });
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;

    PlatformUtils.lightHaptic();
    widget.onSendMessage(text);
    _controller.clear();
    // Keep input expanded and focused for better UX - don't dismiss keyboard
    // KeyboardUtils.dismissKeyboard(context);
    // _setExpanded(false);
  }

  void _setExpanded(bool expanded) {
    if (_isExpanded == expanded) return;
    setState(() {
      _isExpanded = expanded;
    });
    if (expanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if assistant is currently generating by checking last assistant message streaming
    final messages = ref.watch(chatMessagesProvider);
    final isGenerating =
        messages.isNotEmpty &&
        messages.last.role == 'assistant' &&
        messages.last.isStreaming;
    final stopGeneration = ref.read(stopGenerationProvider);

    return Container(
      // Transparent wrapper so rounded corners are visible against page background
      color: Colors.transparent,
      padding: EdgeInsets.only(
        left: 0,
        right: 0,
        top: Spacing.xs.toDouble(),
        bottom: 0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Web search status indicator
          _buildWebSearchStatusIndicator(),

          // Main input area with unified 2-row design
          Container(
            clipBehavior: Clip.antiAlias,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: context.conduitTheme.inputBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppBorderRadius.xl),
                bottom: Radius.circular(0),
              ),
              border: Border(
                top: BorderSide(
                  color: context.conduitTheme.inputBorder,
                  width: BorderWidth.regular,
                ),
                left: BorderSide(
                  color: context.conduitTheme.inputBorder,
                  width: BorderWidth.regular,
                ),
                right: BorderSide(
                  color: context.conduitTheme.inputBorder,
                  width: BorderWidth.regular,
                ),
                // Removed bottom border to eliminate divider
              ),
              boxShadow: ConduitShadows.input,
            ),
            width: double.infinity,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // cap the input area to 40% of screen height to avoid bottom overflow
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: AnimatedSize(
                duration:
                    AnimationDuration.fast, // Faster for better responsiveness
                curve: Curves.fastOutSlowIn, // More efficient curve
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Collapsed/Expanded top row: text input with left/right buttons in collapsed
                      Padding(
                        padding: const EdgeInsets.all(Spacing.inputPadding),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (!_isExpanded) ...[
                              _buildRoundButton(
                                icon: Icons.add,
                                onTap: widget.enabled
                                    ? _showAttachmentOptions
                                    : null,
                                tooltip: 'Add attachment',
                              ),
                              const SizedBox(width: Spacing.sm),
                            ],
                            // Text input expands to fill
                            Expanded(
                              child: Semantics(
                                textField: true,
                                label: 'Message input',
                                hint: 'Type your message',
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _focusNode,
                                  enabled: widget.enabled,
                                  autofocus: false,
                                  maxLines: _isExpanded ? null : 1,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  showCursor: true,
                                  cursorColor: context.conduitTheme.inputText,
                                  style: AppTypography.chatMessageStyle
                                      .copyWith(
                                        color: context.conduitTheme.inputText,
                                      ),
                                  decoration: InputDecoration(
                                    hintText: 'Message...',
                                    hintStyle: TextStyle(
                                      color:
                                          context.conduitTheme.inputPlaceholder,
                                      fontSize: AppTypography.bodyLarge,
                                      fontWeight: _isRecording
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                      fontStyle: _isRecording
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                    // Ensure the text field background matches its parent container
                                    // and does not use the global InputDecorationTheme fill
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    isDense: true,
                                    alignLabelWithHint: true,
                                  ),
                                  // Removed onChanged setState to reduce rebuilds
                                  onSubmitted: (_) => _sendMessage(),
                                  onTap: () {
                                    if (!widget.enabled) return;
                                    if (!_isExpanded) {
                                      _setExpanded(true);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (!mounted) return;
                                            _ensureFocusedIfEnabled();
                                          });
                                    } else {
                                      _ensureFocusedIfEnabled();
                                    }
                                  },
                                ),
                              ),
                            ),
                            if (!_isExpanded) ...[
                              const SizedBox(width: Spacing.sm),
                              // Primary action button (Send/Stop) when collapsed
                              _buildPrimaryButton(
                                _hasText,
                                isGenerating,
                                stopGeneration,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Expanded bottom row with additional options
                      if (_isExpanded) ...[
                        Container(
                          padding: const EdgeInsets.only(
                            left: Spacing.inputPadding,
                            right: Spacing.inputPadding,
                            bottom: Spacing.inputPadding,
                          ),
                          child: FadeTransition(
                            opacity: _expandController,
                            child: Row(
                              children: [
                                _buildRoundButton(
                                  icon: Icons.add,
                                  onTap: widget.enabled
                                      ? _showAttachmentOptions
                                      : null,
                                  tooltip: 'Add attachment',
                                ),
                                const SizedBox(width: Spacing.sm),
                                Flexible(
                                  child: Center(child: _buildResearchToggle()),
                                ),
                                const SizedBox(width: Spacing.md),
                                // Microphone button: call provided callback for premium voice UI
                                _buildRoundButton(
                                  icon: Platform.isIOS
                                      ? CupertinoIcons.mic_fill
                                      : Icons.mic,
                                  onTap: widget.enabled
                                      ? widget.onVoiceInput
                                      : null,
                                  tooltip: 'Voice input',
                                  isActive: _isRecording,
                                ),
                                const SizedBox(width: Spacing.sm),
                                // Primary action button (Send/Stop) when expanded
                                _buildPrimaryButton(
                                  _hasText,
                                  isGenerating,
                                  stopGeneration,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton(
    bool hasText,
    bool isGenerating,
    void Function() stopGeneration,
  ) {
    // Spec: 48px touch target, circular radius, md icon size
    const double buttonSize = TouchTarget.comfortable; // 48.0
    const double radius = AppBorderRadius.round; // big to ensure circle

    final enabled = !isGenerating && hasText && widget.enabled;

    // Generating -> STOP variant
    if (isGenerating) {
      return Tooltip(
        message: 'Stop generating',
        child: GestureDetector(
          onTap: stopGeneration,
          child: Container(
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              color: context.conduitTheme.error.withValues(
                alpha: Alpha.buttonPressed,
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: context.conduitTheme.error,
                width: BorderWidth.regular,
              ),
              boxShadow: ConduitShadows.button,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: buttonSize - 18,
                  height: buttonSize - 18,
                  child: CircularProgressIndicator(
                    strokeWidth: BorderWidth.medium,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      context.conduitTheme.error,
                    ),
                  ),
                ),
                Icon(
                  Platform.isIOS ? CupertinoIcons.stop_fill : Icons.stop,
                  size: IconSize.medium,
                  color: context.conduitTheme.error,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Default SEND variant
    return Tooltip(
      message: enabled ? 'Send message' : 'Send',
      child: GestureDetector(
        onTap: enabled ? _sendMessage : null,
        child: Opacity(
          opacity: enabled ? Alpha.primary : Alpha.disabled,
          child: IgnorePointer(
            ignoring: !enabled,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: context.conduitTheme.cardBackground,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: enabled
                      ? context.conduitTheme.cardBorder
                      : context.conduitTheme.cardBorder.withValues(
                          alpha: Alpha.medium,
                        ),
                  width: BorderWidth.regular,
                ),
                boxShadow: ConduitShadows.button,
              ),
              child: Icon(
                Platform.isIOS ? CupertinoIcons.arrow_up : Icons.arrow_upward,
                size: IconSize.medium,
                color: enabled
                    ? context.conduitTheme.textPrimary
                    : context.conduitTheme.textPrimary.withValues(
                        alpha: Alpha.disabled,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    VoidCallback? onTap,
    String? tooltip,
    bool isActive = false,
    bool showBackground = true,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: TouchTarget.comfortable,
          height: TouchTarget.comfortable,
          decoration: BoxDecoration(
            color: isActive
                ? context.conduitTheme.textPrimary.withValues(
                    alpha: Alpha.buttonHover,
                  )
                : showBackground
                ? context.conduitTheme.cardBackground
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppBorderRadius.xl),
            border: Border.all(
              color: isActive
                  ? context.conduitTheme.textPrimary.withValues(
                      alpha: Alpha.buttonHover + Alpha.subtle,
                    )
                  : showBackground
                  ? context.conduitTheme.cardBorder
                  : Colors.transparent,
              width: BorderWidth.regular,
            ),
            boxShadow: (isActive || showBackground)
                ? ConduitShadows.button
                : null,
          ),
          child: Icon(
            icon,
            size: IconSize.medium,
            color: widget.enabled
                ? (isActive
                      ? context.conduitTheme.textPrimary
                      : context.conduitTheme.textPrimary.withValues(
                          alpha: Alpha.strong,
                        ))
                : context.conduitTheme.textPrimary.withValues(
                    alpha: Alpha.disabled,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildResearchToggle() {
    final webSearchEnabled = ref.watch(
      webSearchEnabledProvider.select((enabled) => enabled),
    );

    return GestureDetector(
      onTap: widget.enabled
          ? () {
              ref.read(webSearchEnabledProvider.notifier).state =
                  !webSearchEnabled;
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: webSearchEnabled
              ? context.conduitTheme.textPrimary.withValues(
                  alpha: Alpha.buttonHover,
                )
              : context.conduitTheme.surfaceBackground.withValues(
                  alpha: Alpha.subtle,
                ),
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          border: Border.all(
            color: webSearchEnabled
                ? context.conduitTheme.textPrimary.withValues(
                    alpha: Alpha.buttonHover + Alpha.subtle,
                  )
                : context.conduitTheme.textPrimary.withValues(
                    alpha: Alpha.subtle,
                  ),
            width: BorderWidth.regular,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Platform.isIOS ? CupertinoIcons.search : Icons.travel_explore,
              size: IconSize.small,
              color: widget.enabled
                  ? (webSearchEnabled
                        ? context.conduitTheme.textPrimary
                        : context.conduitTheme.textPrimary.withValues(
                            alpha: Alpha.strong,
                          ))
                  : context.conduitTheme.textPrimary.withValues(
                      alpha: Alpha.disabled,
                    ),
            ),
            const SizedBox(width: Spacing.sm),
            Flexible(
              child: Text(
                'Search',
                style: TextStyle(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w500,
                  color: widget.enabled
                      ? (webSearchEnabled
                            ? context.conduitTheme.textPrimary
                            : context.conduitTheme.textPrimary.withValues(
                                alpha: Alpha.strong,
                              ))
                      : context.conduitTheme.textPrimary.withValues(
                          alpha: Alpha.disabled,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebSearchStatusIndicator() {
    final webSearchEnabled = ref.watch(
      webSearchEnabledProvider.select((enabled) => enabled),
    );

    if (!webSearchEnabled) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      margin: const EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        bottom: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.conduitTheme.info.withValues(
          alpha: Alpha.badgeBackground,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.badge),
        border: Border.all(
          color: context.conduitTheme.info.withValues(alpha: Alpha.subtle),
          width: BorderWidth.regular,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Platform.isIOS ? CupertinoIcons.search : Icons.travel_explore,
            size: IconSize.small,
            color: context.conduitTheme.info,
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            'Web search on',
            style: AppTypography.captionStyle.copyWith(
              color: context.conduitTheme.info,
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppBorderRadius.bottomSheet),
          ),
          boxShadow: ConduitShadows.modal,
        ),
        padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.conduitTheme.textPrimary.withValues(
                  alpha: Alpha.medium,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: Spacing.lg),

            // Options grid
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Platform.isIOS ? CupertinoIcons.doc : Icons.attach_file,
                  label: 'File',
                  onTap: () {
                    Navigator.pop(context); // Close modal
                    widget.onFileAttachment?.call();
                  },
                ),
                _buildAttachmentOption(
                  icon: Platform.isIOS ? CupertinoIcons.photo : Icons.image,
                  label: 'Photo',
                  onTap: () {
                    Navigator.pop(context); // Close modal
                    widget.onImageAttachment?.call();
                  },
                ),
                _buildAttachmentOption(
                  icon: Platform.isIOS
                      ? CupertinoIcons.camera
                      : Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context); // Close modal
                    widget.onCameraCapture?.call();
                  },
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: context.conduitTheme.textPrimary.withValues(
                alpha: Alpha.subtle,
              ),
              borderRadius: BorderRadius.circular(AppBorderRadius.lg),
              border: Border.all(
                color: context.conduitTheme.textPrimary.withValues(
                  alpha: Alpha.subtle,
                ),
                width: BorderWidth.regular,
              ),
            ),
            child: Icon(
              icon,
              color: context.conduitTheme.textPrimary,
              size: IconSize.xl,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            label,
            style: AppTypography.labelStyle.copyWith(
              color: context.conduitTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
