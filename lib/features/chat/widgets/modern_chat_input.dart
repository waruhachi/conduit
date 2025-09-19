import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme/theme_extensions.dart';
// app_theme not required here; using theme extension tokens
import '../../../shared/widgets/sheet_handle.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io' show Platform;
import 'dart:async';
import 'dart:ui';
import '../providers/chat_providers.dart';
import '../../tools/providers/tools_providers.dart';
import '../../../core/models/tool.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/settings_service.dart';
import '../../chat/services/voice_input_service.dart';

import '../../../shared/utils/platform_utils.dart';
import 'package:conduit/l10n/app_localizations.dart';

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _InsertNewlineIntent extends Intent {
  const _InsertNewlineIntent();
}

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

class _MicButton extends StatelessWidget {
  final bool isRecording;
  final int intensity; // 0..10
  final VoidCallback? onTap;
  final String tooltip;

  const _MicButton({
    required this.isRecording,
    required this.intensity,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = isRecording
        ? context.conduitTheme.buttonPrimaryText
        : context.conduitTheme.textPrimary.withValues(alpha: Alpha.strong);
    final double normalized = (intensity.clamp(0, 10)) / 10.0;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: SizedBox(
            width: TouchTarget.minimum,
            height: TouchTarget.minimum,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: TouchTarget.minimum * 0.74,
                  height: TouchTarget.minimum * 0.74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRecording
                        ? context.conduitTheme.buttonPrimary.withValues(
                            alpha: 0.12 + (0.14 * normalized),
                          )
                        : Colors.transparent,
                    boxShadow: isRecording
                        ? [
                            BoxShadow(
                              color: context.conduitTheme.buttonPrimary
                                  .withValues(
                                    alpha: 0.22 + (0.18 * normalized),
                                  ),
                              blurRadius: 14 + (8 * normalized),
                              spreadRadius: 2 + (normalized * 2),
                            ),
                          ]
                        : const [],
                  ),
                ),
                AnimatedScale(
                  scale: isRecording ? 1.05 + (normalized * 0.05) : 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Platform.isIOS ? CupertinoIcons.mic_fill : Icons.mic,
                    size: IconSize.medium,
                    color: iconColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernChatInputState extends ConsumerState<ModernChatInput>
    with TickerProviderStateMixin {
  static const double _composerRadius = AppBorderRadius.card;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isRecording = false;
  // final String _voiceInputText = '';
  bool _hasText = false; // track locally without rebuilding on each keystroke
  StreamSubscription<String>? _voiceStreamSubscription;
  late VoiceInputService _voiceService;
  StreamSubscription<int>? _intensitySub;
  StreamSubscription<String>? _textSub;
  int _intensity = 0; // 0..10 from service
  String _baseTextAtStart = '';
  bool _isDeactivated = false;
  int _lastHandledFocusTick = 0;

  @override
  void initState() {
    super.initState();
    _voiceService = ref.read(voiceInputServiceProvider);

    // Apply any prefilled text on first frame (focus handled via inputFocusTrigger)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDeactivated) return;
      final text = ref.read(prefilledInputTextProvider);
      if (text != null && text.isNotEmpty) {
        _controller.text = text;
        _controller.selection = TextSelection.collapsed(offset: text.length);
        // Clear after applying so it doesn't re-apply on rebuilds
        ref.read(prefilledInputTextProvider.notifier).state = null;
      }
    });

    // Removed ref.listen here; it must be used from build in this Riverpod version

    // Listen for text changes and update only when emptiness flips
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isDeactivated) return;
          setState(() => _hasText = has);
        });
      }
    });

    // Publish focus changes to listeners
    _focusNode.addListener(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDeactivated) return;
        final hasFocus = _focusNode.hasFocus;
        // Publish composer focus state
        try {
          ref.read(composerHasFocusProvider.notifier).state = hasFocus;
        } catch (_) {}
      });
    });

    // Do not auto-focus on mount; only focus on explicit user intent
  }

  @override
  void dispose() {
    try {
      ref.read(composerHasFocusProvider.notifier).state = false;
    } catch (_) {}
    _controller.dispose();
    _focusNode.dispose();
    _voiceStreamSubscription?.cancel();
    _intensitySub?.cancel();
    _textSub?.cancel();
    _voiceService.stopListening();
    super.dispose();
  }

  void _ensureFocusedIfEnabled() {
    if (!widget.enabled) return;
    if (!_focusNode.hasFocus) {
      // Use FocusNode directly to avoid depending on Inherited widgets
      _focusNode.requestFocus();
    }
  }

  @override
  void deactivate() {
    _isDeactivated = true;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _isDeactivated = false;
  }

  @override
  void didUpdateWidget(covariant ModernChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Avoid auto-focusing when becoming enabled; wait for user intent
    if (!widget.enabled && oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDeactivated) return;
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
    // Keep focus and keyboard open; do not collapse automatically
  }

  void _insertNewline() {
    final text = _controller.text;
    TextSelection sel = _controller.selection;
    final int start = sel.isValid ? sel.start : text.length;
    final int end = sel.isValid ? sel.end : text.length;
    final String before = text.substring(0, start);
    final String after = text.substring(end);
    final String updated = '$before\n$after';
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: before.length + 1),
      composing: TextRange.empty,
    );
    // Ensure field stays focused
    _ensureFocusedIfEnabled();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(prefilledInputTextProvider, (previous, next) {
      final incoming = next?.trim();
      if (incoming == null || incoming.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDeactivated) return;
        _controller.text = incoming;
        _controller.selection = TextSelection.collapsed(
          offset: incoming.length,
        );
        try {
          ref.read(prefilledInputTextProvider.notifier).state = null;
        } catch (_) {}
      });
    });

    final messages = ref.watch(chatMessagesProvider);
    final isGenerating =
        messages.isNotEmpty &&
        messages.last.role == 'assistant' &&
        messages.last.isStreaming;
    final stopGeneration = ref.read(stopGenerationProvider);

    final webSearchEnabled = ref.watch(webSearchEnabledProvider);
    final imageGenEnabled = ref.watch(imageGenerationEnabledProvider);
    final imageGenAvailable = ref.watch(imageGenerationAvailableProvider);
    final selectedQuickPills = ref.watch(
      appSettingsProvider.select((s) => s.quickPills),
    );
    final sendOnEnter = ref.watch(
      appSettingsProvider.select((s) => s.sendOnEnter),
    );
    final toolsAsync = ref.watch(toolsListProvider);
    final List<Tool> availableTools = toolsAsync.maybeWhen<List<Tool>>(
      data: (t) => t,
      orElse: () => const <Tool>[],
    );
    final bool showWebPill = selectedQuickPills.contains('web');
    final bool showImagePillPref = selectedQuickPills.contains('image');
    final voiceAvailableAsync = ref.watch(voiceInputAvailableProvider);
    final bool voiceAvailable = voiceAvailableAsync.maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );
    final selectedToolIds = ref.watch(selectedToolIdsProvider);

    final focusTick = ref.watch(inputFocusTriggerProvider);
    if (focusTick != _lastHandledFocusTick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDeactivated) return;
        _ensureFocusedIfEnabled();
        _lastHandledFocusTick = focusTick;
      });
    }

    final Brightness brightness = Theme.of(context).brightness;
    final bool isActive = _focusNode.hasFocus || _hasText;
    final Color composerSurface = context.conduitTheme.inputBackground;
    final Color shellBackground = brightness == Brightness.dark
        ? composerSurface.withValues(alpha: 0.78)
        : composerSurface;
    final Color placeholderBase = context.conduitTheme.inputPlaceholder;
    final Color placeholderFocused = context.conduitTheme.inputText.withValues(
      alpha: 0.64,
    );
    final Color outlineColor = Color.lerp(
      context.conduitTheme.inputBorder,
      context.conduitTheme.inputBorderFocused,
      isActive ? 1.0 : 0.0,
    )!.withValues(alpha: brightness == Brightness.dark ? 0.55 : 0.45);
    final Color shellShadowColor = context.conduitTheme.cardShadow.withValues(
      alpha: brightness == Brightness.dark
          ? 0.22 + (isActive ? 0.08 : 0.0)
          : 0.12 + (isActive ? 0.06 : 0.0),
    );

    final List<Widget> quickPills = <Widget>[];

    for (final id in selectedQuickPills) {
      if (id == 'web' && showWebPill) {
        final String label = AppLocalizations.of(context)!.web;
        final IconData icon = Platform.isIOS
            ? CupertinoIcons.search
            : Icons.search;
        void handleTap() {
          final notifier = ref.read(webSearchEnabledProvider.notifier);
          notifier.state = !webSearchEnabled;
        }

        quickPills.add(
          _buildPillButton(
            icon: icon,
            label: label,
            isActive: webSearchEnabled,
            onTap: widget.enabled && !_isRecording ? handleTap : null,
          ),
        );
      } else if (id == 'image' && showImagePillPref && imageGenAvailable) {
        final String label = AppLocalizations.of(context)!.imageGen;
        final IconData icon = Platform.isIOS
            ? CupertinoIcons.photo
            : Icons.image;
        void handleTap() {
          final notifier = ref.read(imageGenerationEnabledProvider.notifier);
          notifier.state = !imageGenEnabled;
        }

        quickPills.add(
          _buildPillButton(
            icon: icon,
            label: label,
            isActive: imageGenEnabled,
            onTap: widget.enabled && !_isRecording ? handleTap : null,
          ),
        );
      } else {
        Tool? tool;
        for (final t in availableTools) {
          if (t.id == id) {
            tool = t;
            break;
          }
        }
        if (tool != null) {
          final bool isSelected = selectedToolIds.contains(id);
          final String label = tool.name;
          final IconData icon = Platform.isIOS
              ? CupertinoIcons.wrench
              : Icons.build;

          void handleTap() {
            final current = List<String>.from(selectedToolIds);
            if (current.contains(id)) {
              current.remove(id);
            } else {
              current.add(id);
            }
            ref.read(selectedToolIdsProvider.notifier).state = current;
          }

          quickPills.add(
            _buildPillButton(
              icon: icon,
              label: label,
              isActive: isSelected,
              onTap: widget.enabled && !_isRecording ? handleTap : null,
            ),
          );
        }
      }
    }

    Widget shell = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: shellBackground,
        borderRadius: BorderRadius.circular(_composerRadius),
        border: Border.all(color: outlineColor, width: BorderWidth.thin),
        boxShadow: [
          BoxShadow(
            color: shellShadowColor,
            blurRadius: 12 + (isActive ? 4 : 0),
            spreadRadius: -2,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewPadding.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: RepaintBoundary(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(Spacing.sm),
                      child: Container(
                        padding: const EdgeInsets.all(Spacing.sm),
                        decoration: BoxDecoration(
                          color: shellBackground,
                          borderRadius: BorderRadius.circular(_composerRadius),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (!widget.enabled) return;
                                  _ensureFocusedIfEnabled();
                                },
                                child: Semantics(
                                  textField: true,
                                  label: AppLocalizations.of(
                                    context,
                                  )!.messageInputLabel,
                                  hint: AppLocalizations.of(
                                    context,
                                  )!.messageInputHint,
                                  child: Shortcuts(
                                    shortcuts: () {
                                      final map = <LogicalKeySet, Intent>{
                                        LogicalKeySet(
                                          LogicalKeyboardKey.meta,
                                          LogicalKeyboardKey.enter,
                                        ): const _SendMessageIntent(),
                                        LogicalKeySet(
                                          LogicalKeyboardKey.control,
                                          LogicalKeyboardKey.enter,
                                        ): const _SendMessageIntent(),
                                      };
                                      if (sendOnEnter) {
                                        map[LogicalKeySet(
                                              LogicalKeyboardKey.enter,
                                            )] =
                                            const _SendMessageIntent();
                                        map[LogicalKeySet(
                                              LogicalKeyboardKey.shift,
                                              LogicalKeyboardKey.enter,
                                            )] =
                                            const _InsertNewlineIntent();
                                      }
                                      return map;
                                    }(),
                                    child: Actions(
                                      actions: <Type, Action<Intent>>{
                                        _SendMessageIntent:
                                            CallbackAction<_SendMessageIntent>(
                                              onInvoke: (intent) {
                                                _sendMessage();
                                                return null;
                                              },
                                            ),
                                        _InsertNewlineIntent:
                                            CallbackAction<
                                              _InsertNewlineIntent
                                            >(
                                              onInvoke: (intent) {
                                                _insertNewline();
                                                return null;
                                              },
                                            ),
                                      },
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0.0,
                                          end: isActive ? 1.0 : 0.0,
                                        ),
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, factor, child) {
                                          final Color animatedPlaceholder =
                                              Color.lerp(
                                                placeholderBase,
                                                placeholderFocused,
                                                factor,
                                              )!;
                                          final Color animatedTextColor =
                                              Color.lerp(
                                                context.conduitTheme.inputText
                                                    .withValues(alpha: 0.88),
                                                context.conduitTheme.inputText,
                                                factor,
                                              )!;

                                          return TextField(
                                            controller: _controller,
                                            focusNode: _focusNode,
                                            enabled: widget.enabled,
                                            autofocus: false,
                                            minLines: 1,
                                            maxLines: null,
                                            keyboardType:
                                                TextInputType.multiline,
                                            textCapitalization:
                                                TextCapitalization.sentences,
                                            textInputAction: sendOnEnter
                                                ? TextInputAction.send
                                                : TextInputAction.newline,
                                            showCursor: true,
                                            scrollPadding:
                                                const EdgeInsets.only(
                                                  bottom: 80,
                                                ),
                                            keyboardAppearance: brightness,
                                            cursorColor: animatedTextColor,
                                            style: AppTypography.bodyLargeStyle
                                                .copyWith(
                                                  color: animatedTextColor,
                                                  fontStyle: _isRecording
                                                      ? FontStyle.italic
                                                      : FontStyle.normal,
                                                  fontWeight: _isRecording
                                                      ? FontWeight.w500
                                                      : FontWeight.w400,
                                                ),
                                            decoration: InputDecoration(
                                              hintText: AppLocalizations.of(
                                                context,
                                              )!.messageHintText,
                                              hintStyle: TextStyle(
                                                color: animatedPlaceholder,
                                                fontSize:
                                                    AppTypography.bodyLarge,
                                                fontWeight: _isRecording
                                                    ? FontWeight.w500
                                                    : FontWeight.w400,
                                                fontStyle: _isRecording
                                                    ? FontStyle.italic
                                                    : FontStyle.normal,
                                              ),
                                              filled: true,
                                              fillColor: shellBackground,
                                              border: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              errorBorder: InputBorder.none,
                                              disabledBorder: InputBorder.none,
                                              contentPadding: EdgeInsets.zero,
                                              isDense: true,
                                              alignLabelWithHint: true,
                                            ),
                                            onSubmitted: (_) {
                                              if (sendOnEnter) {
                                                _sendMessage();
                                              }
                                            },
                                            onTap: () {
                                              if (!widget.enabled) return;
                                              _ensureFocusedIfEnabled();
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.inputPadding,
                        0,
                        Spacing.inputPadding,
                        Spacing.sm,
                      ),
                      child: Row(
                        children: [
                          _buildOverflowButton(
                            tooltip: AppLocalizations.of(context)!.more,
                          ),
                          const SizedBox(width: Spacing.xs),
                          Expanded(
                            child: quickPills.isEmpty
                                ? const SizedBox.shrink()
                                : ClipRect(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _withHorizontalSpacing(
                                          quickPills,
                                          Spacing.xxs,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (voiceAvailable) ...[
                                _buildVoiceButton(voiceAvailable),
                                const SizedBox(width: Spacing.xs),
                              ],
                              _buildPrimaryButton(
                                _hasText,
                                isGenerating,
                                stopGeneration,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (brightness == Brightness.dark) {
      shell = ClipRRect(
        borderRadius: BorderRadius.circular(_composerRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: shell,
        ),
      );
    }

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.only(
        left: 0,
        right: 0,
        top: Spacing.xs,
        bottom: 0,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [shell]),
    );
  }

  Widget _buildVoiceButton(bool voiceAvailable) {
    if (!voiceAvailable) {
      return const SizedBox.shrink();
    }
    return Builder(
      builder: (context) {
        const double buttonSize = TouchTarget.minimum;
        final double t = _isRecording ? (_intensity.clamp(0, 10) / 10.0) : 0.0;
        final double ringMaxExtra = 16.0;
        final double ringSize = buttonSize + (ringMaxExtra * t);
        final double ringOpacity = _isRecording ? 0.15 + (0.35 * t) : 0.0;

        return SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: ringSize,
                height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.conduitTheme.buttonPrimary.withValues(
                    alpha: ringOpacity,
                  ),
                ),
              ),
              Transform.scale(
                scale: _isRecording
                    ? 1.0 + (_intensity.clamp(0, 10) / 200)
                    : 1.0,
                child: _MicButton(
                  isRecording: _isRecording,
                  intensity: _intensity,
                  onTap: (widget.enabled && voiceAvailable)
                      ? _toggleVoice
                      : null,
                  tooltip: AppLocalizations.of(context)!.voiceInput,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _withHorizontalSpacing(List<Widget> children, double gap) {
    if (children.length <= 1) {
      return List<Widget>.from(children);
    }
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i != children.length - 1) {
        result.add(SizedBox(width: gap));
      }
    }
    return result;
  }

  Widget _buildOverflowButton({required String tooltip}) {
    final IconData icon = Platform.isIOS
        ? CupertinoIcons.ellipsis
        : Icons.more_horiz;
    return _buildRoundButton(
      icon: icon,
      onTap: widget.enabled && !_isRecording ? _showOverflowSheet : null,
      tooltip: tooltip,
    );
  }

  Widget _buildPrimaryButton(
    bool hasText,
    bool isGenerating,
    void Function() stopGeneration,
  ) {
    // Compact 44px touch target, circular radius, md icon size
    const double buttonSize = TouchTarget.minimum; // 44.0
    const double radius = AppBorderRadius.round; // big to ensure circle

    final enabled = !isGenerating && hasText && widget.enabled;

    // Generating -> STOP variant
    if (isGenerating) {
      return Tooltip(
        message: AppLocalizations.of(context)!.stopGenerating,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(
              color: context.conduitTheme.error,
              width: BorderWidth.regular,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: () {
              HapticFeedback.lightImpact();
              stopGeneration();
            },
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: context.conduitTheme.error.withValues(
                  alpha: Alpha.buttonPressed,
                ),
                borderRadius: BorderRadius.circular(radius),
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
        ),
      );
    }

    // Default SEND variant
    return Tooltip(
      message: enabled
          ? AppLocalizations.of(context)!.sendMessage
          : AppLocalizations.of(context)!.send,
      child: Opacity(
        opacity: enabled ? Alpha.primary : Alpha.disabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
              side: BorderSide(
                color: enabled
                    ? context.conduitTheme.cardBorder
                    : context.conduitTheme.cardBorder.withValues(
                        alpha: Alpha.medium,
                      ),
                width: BorderWidth.regular,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: enabled
                  ? () {
                      PlatformUtils.lightHaptic();
                      _sendMessage();
                    }
                  : null,
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  color: context.conduitTheme.cardBackground,
                  borderRadius: BorderRadius.circular(radius),
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
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    VoidCallback? onTap,
    String? tooltip,
    bool isActive = false,
  }) {
    const double buttonSize = TouchTarget.minimum;
    final VoidCallback? callback = onTap;
    final bool enabled = callback != null;
    final Color borderColor = isActive
        ? context.conduitTheme.buttonPrimary
        : context.conduitTheme.cardBorder.withValues(
            alpha: enabled ? Alpha.medium : Alpha.disabled,
          );
    final Color fillColor = isActive
        ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.18)
        : context.conduitTheme.cardBackground;
    final Color iconColor = enabled
        ? (isActive
              ? context.conduitTheme.buttonPrimaryText
              : context.conduitTheme.textPrimary.withValues(
                  alpha: Alpha.strong,
                ))
        : context.conduitTheme.textPrimary.withValues(alpha: Alpha.disabled);

    return Tooltip(
      message: tooltip ?? '',
      child: Opacity(
        opacity: enabled ? 1.0 : Alpha.disabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.round),
              side: BorderSide(color: borderColor, width: BorderWidth.thin),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppBorderRadius.round),
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap();
                    },
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: BorderRadius.circular(AppBorderRadius.round),
                  boxShadow: ConduitShadows.button,
                ),
                child: Icon(icon, size: IconSize.medium, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillButton({
    required IconData icon,
    required String label,
    required bool isActive,
    VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;
    final Brightness brightness = Theme.of(context).brightness;
    final Color baseBackground = context.conduitTheme.cardBackground;
    final Color background = isActive
        ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.16)
        : baseBackground.withValues(
            alpha: brightness == Brightness.dark ? 0.18 : 0.12,
          );
    final Color outline = isActive
        ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.8)
        : context.conduitTheme.cardBorder.withValues(alpha: 0.6);
    final Color contentColor = isActive
        ? context.conduitTheme.buttonPrimary
        : context.conduitTheme.textPrimary.withValues(
            alpha: enabled ? Alpha.strong : Alpha.disabled,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.input),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppBorderRadius.input),
            border: Border.all(color: outline, width: BorderWidth.thin),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: IconSize.medium, color: contentColor),
              const SizedBox(width: Spacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelStyle.copyWith(color: contentColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOverflowSheet() {
    HapticFeedback.selectionClick();
    final prevCanRequest = _focusNode.canRequestFocus;
    final wasFocused = _focusNode.hasFocus;
    _focusNode.canRequestFocus = false;
    try {
      FocusScope.of(context).unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => Consumer(
        builder: (innerContext, modalRef, _) {
          final l10n = AppLocalizations.of(innerContext)!;
          final theme = innerContext.conduitTheme;

          final attachments = <Widget>[
            _buildOverflowAction(
              icon: Platform.isIOS ? CupertinoIcons.doc : Icons.attach_file,
              label: l10n.file,
              onTap: widget.onFileAttachment == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      widget.onFileAttachment!.call();
                    },
            ),
            _buildOverflowAction(
              icon: Platform.isIOS ? CupertinoIcons.photo : Icons.image,
              label: l10n.photo,
              onTap: widget.onImageAttachment == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      widget.onImageAttachment!.call();
                    },
            ),
            _buildOverflowAction(
              icon: Platform.isIOS ? CupertinoIcons.camera : Icons.camera_alt,
              label: l10n.camera,
              onTap: widget.onCameraCapture == null
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      widget.onCameraCapture!.call();
                    },
            ),
          ];

          final featureTiles = <Widget>[];
          final webSearchAvailable = modalRef.watch(webSearchAvailableProvider);
          final webSearchEnabled = modalRef.watch(webSearchEnabledProvider);
          if (webSearchAvailable) {
            featureTiles.add(
              _buildFeatureToggleTile(
                icon: Platform.isIOS ? CupertinoIcons.search : Icons.search,
                title: l10n.webSearch,
                subtitle: l10n.webSearchDescription,
                value: webSearchEnabled,
                onChanged: (next) {
                  modalRef.read(webSearchEnabledProvider.notifier).state = next;
                },
              ),
            );
          }

          final imageGenAvailable = modalRef.watch(
            imageGenerationAvailableProvider,
          );
          final imageGenEnabled = modalRef.watch(
            imageGenerationEnabledProvider,
          );
          if (imageGenAvailable) {
            featureTiles.add(
              _buildFeatureToggleTile(
                icon: Platform.isIOS ? CupertinoIcons.photo : Icons.image,
                title: l10n.imageGeneration,
                subtitle: l10n.imageGenerationDescription,
                value: imageGenEnabled,
                onChanged: (next) {
                  modalRef.read(imageGenerationEnabledProvider.notifier).state =
                      next;
                },
              ),
            );
          }

          final selectedToolIds = modalRef.watch(selectedToolIdsProvider);
          final toolsAsync = modalRef.watch(toolsListProvider);
          final Widget toolsSection = toolsAsync.when(
            data: (tools) {
              if (tools.isEmpty) {
                return _buildInfoCard('No tools available');
              }
              final tiles = tools.map((tool) {
                final isSelected = selectedToolIds.contains(tool.id);
                return _buildToolTile(
                  tool: tool,
                  selected: isSelected,
                  onToggle: () {
                    final current = List<String>.from(
                      modalRef.read(selectedToolIdsProvider),
                    );
                    if (isSelected) {
                      current.remove(tool.id);
                    } else {
                      current.add(tool.id);
                    }
                    modalRef.read(selectedToolIdsProvider.notifier).state =
                        current;
                  },
                );
              }).toList();
              return Column(children: _withVerticalSpacing(tiles, Spacing.xxs));
            },
            loading: () => Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: BorderWidth.thin),
              ),
            ),
            error: (error, stack) => _buildInfoCard('Failed to load tools'),
          );

          final bodyChildren = <Widget>[
            const SheetHandle(),
            const SizedBox(height: Spacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < attachments.length; i++) ...[
                      if (i != 0) const SizedBox(width: Spacing.md),
                      Expanded(child: attachments[i]),
                    ],
                  ],
                ),
              ],
            ),
          ];

          if (featureTiles.isNotEmpty) {
            bodyChildren
              ..add(const SizedBox(height: Spacing.md))
              ..addAll(_withVerticalSpacing(featureTiles, Spacing.xs));
          }

          bodyChildren
            ..add(const SizedBox(height: Spacing.md))
            ..add(_buildSectionLabel(l10n.tools))
            ..add(toolsSection);

          return Container(
            decoration: BoxDecoration(
              color: theme.surfaceBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppBorderRadius.bottomSheet),
              ),
              border: Border.all(
                color: theme.dividerColor,
                width: BorderWidth.thin,
              ),
              boxShadow: ConduitShadows.modal,
            ),
            child: SafeArea(
              top: false,
              bottom: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.modalPadding,
                  Spacing.sm,
                  Spacing.modalPadding,
                  Spacing.modalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: bodyChildren,
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) {
        _focusNode.canRequestFocus = prevCanRequest;
        if (wasFocused && widget.enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ensureFocusedIfEnabled();
          });
        }
      }
    });
  }

  List<Widget> _withVerticalSpacing(List<Widget> children, double gap) {
    if (children.length <= 1) {
      return List<Widget>.from(children);
    }
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i != children.length - 1) {
        spaced.add(SizedBox(height: gap));
      }
    }
    return spaced;
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Text(
        text,
        style: AppTypography.labelStyle.copyWith(
          color: context.conduitTheme.textSecondary.withValues(
            alpha: Alpha.strong,
          ),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFeatureToggleTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = context.conduitTheme;
    final brightness = Theme.of(context).brightness;
    final description = subtitle?.trim() ?? '';

    final Color background = value
        ? theme.buttonPrimary.withValues(
            alpha: brightness == Brightness.dark ? 0.28 : 0.16,
          )
        : theme.surfaceContainer.withValues(
            alpha: brightness == Brightness.dark ? 0.32 : 0.12,
          );
    final Color borderColor = value
        ? theme.buttonPrimary.withValues(alpha: 0.7)
        : theme.cardBorder.withValues(alpha: 0.55);

    return Semantics(
      button: true,
      toggled: value,
      label: title,
      hint: description.isEmpty ? null : description,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBorderRadius.input),
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(!value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: Spacing.xxs),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppBorderRadius.input),
              border: Border.all(color: borderColor, width: BorderWidth.thin),
              boxShadow: value ? ConduitShadows.low : const [],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildToolGlyph(icon: icon, selected: value, theme: theme),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: AppTypography.bodyLargeStyle.copyWith(
                                color: theme.textPrimary,
                                fontWeight: value
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: Spacing.xs),
                          _buildTogglePill(isOn: value, theme: theme),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmallStyle.copyWith(
                            color: theme.textSecondary.withValues(
                              alpha: Alpha.strong,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolTile({
    required Tool tool,
    required bool selected,
    required VoidCallback onToggle,
  }) {
    final theme = context.conduitTheme;
    final brightness = Theme.of(context).brightness;
    final description = _toolDescriptionFor(tool);
    final Color background = selected
        ? theme.buttonPrimary.withValues(
            alpha: brightness == Brightness.dark ? 0.28 : 0.16,
          )
        : theme.surfaceContainer.withValues(
            alpha: brightness == Brightness.dark ? 0.32 : 0.12,
          );
    final Color borderColor = selected
        ? theme.buttonPrimary.withValues(alpha: 0.7)
        : theme.cardBorder.withValues(alpha: 0.55);

    return Semantics(
      button: true,
      toggled: selected,
      label: tool.name,
      hint: description.isEmpty ? null : description,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBorderRadius.input),
          onTap: () {
            HapticFeedback.selectionClick();
            onToggle();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: Spacing.xxs),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppBorderRadius.input),
              border: Border.all(color: borderColor, width: BorderWidth.thin),
              boxShadow: selected ? ConduitShadows.low : const [],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildToolGlyph(
                  icon: _toolIconFor(tool),
                  selected: selected,
                  theme: theme,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              tool.name,
                              style: AppTypography.bodyLargeStyle.copyWith(
                                color: theme.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: Spacing.xs),
                          _buildTogglePill(isOn: selected, theme: theme),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xs),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmallStyle.copyWith(
                            color: theme.textSecondary.withValues(
                              alpha: Alpha.strong,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolGlyph({
    required IconData icon,
    required bool selected,
    required ConduitThemeExtension theme,
  }) {
    final Color accentStart = theme.buttonPrimary.withValues(
      alpha: selected ? Alpha.active : Alpha.hover,
    );
    final Color accentEnd = theme.buttonPrimary.withValues(
      alpha: selected ? Alpha.highlight : Alpha.focus,
    );
    final Color iconColor = selected
        ? theme.buttonPrimaryText
        : theme.iconPrimary.withValues(alpha: Alpha.strong);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentStart, accentEnd],
        ),
      ),
      child: Icon(icon, color: iconColor, size: IconSize.modal),
    );
  }

  String _toolDescriptionFor(Tool tool) {
    final metaDescription = _extractMetaDescription(tool.meta);
    if (metaDescription != null && metaDescription.isNotEmpty) {
      return metaDescription;
    }

    final custom = tool.description?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }

    final name = tool.name.toLowerCase();
    if (name.contains('search') || name.contains('browse')) {
      return 'Search the web for fresh context to improve answers.';
    }
    if (name.contains('image') ||
        name.contains('vision') ||
        name.contains('media')) {
      return 'Understand or generate imagery alongside your conversation.';
    }
    if (name.contains('code') ||
        name.contains('python') ||
        name.contains('notebook')) {
      return 'Execute code snippets and return computed results inline.';
    }
    if (name.contains('calc') || name.contains('math')) {
      return 'Perform precise math and calculations on demand.';
    }
    if (name.contains('file') || name.contains('document')) {
      return 'Access and summarize your uploaded files during chat.';
    }
    if (name.contains('api') || name.contains('request')) {
      return 'Trigger API requests and bring external data into the chat.';
    }
    return 'Enhance responses with specialized capabilities from this tool.';
  }

  String? _extractMetaDescription(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return null;
    final value = meta['description'];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  Widget _buildTogglePill({
    required bool isOn,
    required ConduitThemeExtension theme,
  }) {
    final Color trackColor = isOn
        ? theme.buttonPrimary.withValues(alpha: 0.9)
        : theme.cardBorder.withValues(alpha: 0.5);
    final Color thumbColor = isOn
        ? theme.buttonPrimaryText
        : theme.surfaceBackground.withValues(alpha: 0.9);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 42,
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppBorderRadius.round),
        color: trackColor,
      ),
      alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: thumbColor,
          boxShadow: [
            BoxShadow(
              color: theme.buttonPrimary.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  IconData _toolIconFor(Tool tool) {
    final name = tool.name.toLowerCase();
    if (name.contains('image') || name.contains('vision')) {
      return Platform.isIOS ? CupertinoIcons.photo : Icons.image;
    }
    if (name.contains('code') || name.contains('python')) {
      return Platform.isIOS
          ? CupertinoIcons.chevron_left_slash_chevron_right
          : Icons.code;
    }
    if (name.contains('calculator') || name.contains('math')) {
      return Icons.calculate;
    }
    if (name.contains('file') || name.contains('document')) {
      return Platform.isIOS ? CupertinoIcons.doc : Icons.description;
    }
    if (name.contains('api') || name.contains('request')) {
      return Icons.cloud;
    }
    if (name.contains('search')) {
      return Platform.isIOS ? CupertinoIcons.search : Icons.search;
    }
    return Platform.isIOS ? CupertinoIcons.square_grid_2x2 : Icons.extension;
  }

  Widget _buildInfoCard(String message) {
    final theme = context.conduitTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppBorderRadius.input),
        border: Border.all(
          color: theme.cardBorder.withValues(alpha: 0.6),
          width: BorderWidth.thin,
        ),
      ),
      child: Text(
        message,
        style: AppTypography.bodyMediumStyle.copyWith(
          color: theme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildOverflowAction({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final theme = context.conduitTheme;
    final brightness = Theme.of(context).brightness;
    final VoidCallback? callback = onTap;
    final bool enabled = callback != null;
    final Color iconColor = enabled ? theme.buttonPrimary : theme.iconDisabled;
    final Color textColor = enabled
        ? theme.textPrimary
        : theme.textPrimary.withValues(alpha: Alpha.disabled);
    final Color background = theme.surfaceContainer.withValues(
      alpha: brightness == Brightness.dark ? 0.45 : 0.92,
    );
    final Color borderColor = theme.cardBorder.withValues(
      alpha: enabled ? 0.5 : 0.25,
    );
    final Color accent = theme.buttonPrimary.withValues(
      alpha: enabled ? Alpha.selected : Alpha.hover,
    );

    return Opacity(
      opacity: enabled ? 1.0 : Alpha.disabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
          onTap: callback == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  Future.microtask(callback);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppBorderRadius.card),
              border: Border.all(color: borderColor, width: BorderWidth.thin),
              color: background,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent,
                        theme.buttonPrimary.withValues(
                          alpha: enabled ? Alpha.highlight : Alpha.hover,
                        ),
                      ],
                    ),
                  ),
                  child: Icon(icon, color: iconColor, size: IconSize.modal),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmallStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Inline Voice Input ---
  Future<void> _toggleVoice() async {
    if (_isRecording) {
      await _stopVoice();
    } else {
      await _startVoice();
    }
  }

  Future<void> _startVoice() async {
    if (!widget.enabled) return;
    try {
      final ok = await _voiceService.initialize();
      if (!mounted) return;
      if (!ok) {
        _showVoiceUnavailable(
          AppLocalizations.of(context)?.errorMessage ??
              'Voice input unavailable',
        );
        return;
      }
      // Centralized permission + start
      final stream = await _voiceService.beginListening();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _baseTextAtStart = _controller.text;
      });
      _intensitySub?.cancel();
      _intensitySub = _voiceService.intensityStream.listen((value) {
        if (!mounted) return;
        setState(() => _intensity = value);
      });
      _textSub?.cancel();
      _textSub = stream.listen(
        (text) async {
          final updated = _baseTextAtStart.isEmpty
              ? text
              : '${_baseTextAtStart.trimRight()} $text';
          _controller.value = TextEditingValue(
            text: updated,
            selection: TextSelection.collapsed(offset: updated.length),
          );
        },
        onDone: () {
          if (!mounted) return;
          setState(() => _isRecording = false);
          _intensitySub?.cancel();
          _intensitySub = null;
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isRecording = false);
          _intensitySub?.cancel();
          _intensitySub = null;
        },
      );
      _ensureFocusedIfEnabled();
    } catch (_) {
      _showVoiceUnavailable(
        AppLocalizations.of(context)?.errorMessage ??
            'Failed to start voice input',
      );
      if (!mounted) return;
      setState(() => _isRecording = false);
    }
  }

  Future<void> _stopVoice() async {
    _intensitySub?.cancel();
    _intensitySub = null;
    await _voiceService.stopListening();
    if (!mounted) return;
    setState(() => _isRecording = false);
    HapticFeedback.selectionClick();
  }

  // Server transcription removed; only on-device STT updates the input text

  void _showVoiceUnavailable(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
