import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme/theme_extensions.dart';
// app_theme not required here; using theme extension tokens
import '../../../shared/widgets/sheet_handle.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io' show Platform;
import 'dart:async';
import 'dart:math' as math;
import '../providers/chat_providers.dart';
import '../../tools/widgets/unified_tools_modal.dart';
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
            child: Center(
              child: isRecording
                  ? _WaveformBars(intensity: intensity, color: iconColor)
                  : Icon(
                      Platform.isIOS ? CupertinoIcons.mic_fill : Icons.mic,
                      size: IconSize.medium,
                      color: iconColor,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final int intensity; // 0..10
  final Color color;

  const _WaveformBars({required this.intensity, required this.color});

  @override
  Widget build(BuildContext context) {
    // 5 bars with varying base heights; scale with intensity
    final double unit = (intensity.clamp(0, 10)) / 10.0; // 0..1
    final List<double> factors = [0.4, 0.7, 1.0, 0.7, 0.4];
    final double maxHeight = IconSize.medium; // ~24px
    // Keep bars within the available width to avoid RenderFlex overflow
    final double width = 14.0; // tighter than 16 to accommodate padding
    final double barWidth = 2.0;
    final double gap = 1.0;
    return SizedBox(
      width: width,
      height: maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (i) {
          final double h = (maxHeight * (factors[i] * (0.3 + 0.7 * unit)))
              .clamp(4.0, maxHeight);
          return Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0.0 : gap),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: barWidth,
              height: h,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2.0),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ModernChatInputState extends ConsumerState<ModernChatInput>
    with TickerProviderStateMixin {
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
    // Listen for prefilled text changes safely from build
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

    // Check if assistant is currently generating by checking last assistant message streaming
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

    // React to external focus requests (e.g., from share prefill or startup)
    final focusTick = ref.watch(inputFocusTriggerProvider);
    if (focusTick != _lastHandledFocusTick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isDeactivated) return;
        // Explicit request: always try to focus and show the keyboard
        _ensureFocusedIfEnabled();
        _lastHandledFocusTick = focusTick;
      });
    }

    final Brightness brightness = Theme.of(context).brightness;
    final Color outlineColor = (_focusNode.hasFocus || _hasText)
        ? context.conduitTheme.inputBorderFocused.withValues(alpha: 0.6)
        : context.conduitTheme.inputBorder.withValues(alpha: 0.7);
    final Color glowColor = context.conduitTheme.inputBackground.withValues(
      alpha: brightness == Brightness.dark ? 0.2 : 0.12,
    );
    final Color composerSurface = context.conduitTheme.inputBackground;
    final Color placeholderColor = context.conduitTheme.inputPlaceholder;
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
          // Main input area with unified 2-row design
          Container(
            decoration: BoxDecoration(
              color: context.conduitTheme.inputBackground,
              borderRadius: BorderRadius.circular(AppBorderRadius.bottomSheet),
              border: Border(
                top: BorderSide(
                  color: outlineColor.withValues(alpha: 0.5),
                  width: BorderWidth.regular,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor,
                  blurRadius: 24,
                  spreadRadius: -16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            width: double.infinity,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // cap the input area to 40% of screen height to avoid bottom overflow
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: AnimatedSize(
                  duration: AnimationDuration
                      .fast, // Faster for better responsiveness
                  curve: Curves.fastOutSlowIn, // More efficient curve
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: RepaintBoundary(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Modern header row inspired by the Gemini surface
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Spacing.sm,
                              Spacing.sm,
                              Spacing.xs,
                              Spacing.sm,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: composerSurface,
                                borderRadius: BorderRadius.circular(
                                  AppBorderRadius.large,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.md,
                                vertical: Spacing.xs,
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
                                                  CallbackAction<
                                                    _SendMessageIntent
                                                  >(
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
                                            child: TextField(
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
                                              keyboardAppearance: Theme.of(
                                                context,
                                              ).brightness,
                                              cursorColor: context
                                                  .conduitTheme
                                                  .inputText,
                                              style: AppTypography
                                                  .chatMessageStyle
                                                  .copyWith(
                                                    color: _isRecording
                                                        ? context
                                                              .conduitTheme
                                                              .inputPlaceholder
                                                        : context
                                                              .conduitTheme
                                                              .inputText,
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
                                                  color: placeholderColor,
                                                  fontSize:
                                                      AppTypography.bodyLarge,
                                                  fontWeight: _isRecording
                                                      ? FontWeight.w500
                                                      : FontWeight.w400,
                                                  fontStyle: _isRecording
                                                      ? FontStyle.italic
                                                      : FontStyle.normal,
                                                ),
                                                filled: false,
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                errorBorder: InputBorder.none,
                                                disabledBorder:
                                                    InputBorder.none,
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
                          Container(
                            padding: const EdgeInsets.only(
                              left: Spacing.inputPadding,
                              right: Spacing.inputPadding,
                              top: Spacing.xs,
                              bottom: Spacing.sm,
                            ),
                            child: Row(
                              children: [
                                _buildRoundButton(
                                  icon: Icons.add,
                                  onTap: widget.enabled && !_isRecording
                                      ? _showAttachmentOptions
                                      : null,
                                  tooltip: AppLocalizations.of(
                                    context,
                                  )!.addAttachment,
                                  showBackground: false,
                                  iconSize: IconSize.large + 2.0,
                                ),
                                const SizedBox(width: Spacing.xs),
                                // Quick pills: expand to full text when space allows
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final double total = constraints.maxWidth;
                                      final bool showImage =
                                          imageGenAvailable &&
                                          showImagePillPref;
                                      final bool showWeb = showWebPill;
                                      // Tools button is always shown
                                      final double toolsWidth =
                                          TouchTarget.minimum;
                                      final double gapBeforeTools = Spacing.xs;

                                      final double availableForPills = math.max(
                                        0.0,
                                        total - toolsWidth - gapBeforeTools,
                                      );

                                      // Compose selected pill entries in order
                                      final List<Map<String, dynamic>> entries =
                                          [];
                                      final textStyle =
                                          AppTypography.labelStyle;
                                      const double horizontalPadding =
                                          Spacing.md * 2;

                                      for (final id in selectedQuickPills) {
                                        if (id == 'web' && showWeb) {
                                          final lbl = AppLocalizations.of(
                                            context,
                                          )!.web;
                                          final tp = TextPainter(
                                            text: TextSpan(
                                              text: lbl,
                                              style: textStyle,
                                            ),
                                            maxLines: 1,
                                            textDirection: Directionality.of(
                                              context,
                                            ),
                                          )..layout();
                                          entries.add({
                                            'id': id,
                                            'label': lbl,
                                            'width':
                                                tp.width + horizontalPadding,
                                            'widgetBuilder': () => _buildPillButton(
                                              icon: Platform.isIOS
                                                  ? CupertinoIcons.search
                                                  : Icons.search,
                                              label: lbl,
                                              isActive: webSearchEnabled,
                                              onTap:
                                                  widget.enabled &&
                                                      !_isRecording
                                                  ? () {
                                                      ref
                                                              .read(
                                                                webSearchEnabledProvider
                                                                    .notifier,
                                                              )
                                                              .state =
                                                          !webSearchEnabled;
                                                    }
                                                  : null,
                                            ),
                                          });
                                        } else if (id == 'image' && showImage) {
                                          final lbl = AppLocalizations.of(
                                            context,
                                          )!.imageGen;
                                          final tp = TextPainter(
                                            text: TextSpan(
                                              text: lbl,
                                              style: textStyle,
                                            ),
                                            maxLines: 1,
                                            textDirection: Directionality.of(
                                              context,
                                            ),
                                          )..layout();
                                          entries.add({
                                            'id': id,
                                            'label': lbl,
                                            'width':
                                                tp.width + horizontalPadding,
                                            'widgetBuilder': () => _buildPillButton(
                                              icon: Platform.isIOS
                                                  ? CupertinoIcons.photo
                                                  : Icons.image,
                                              label: lbl,
                                              isActive: imageGenEnabled,
                                              onTap:
                                                  widget.enabled &&
                                                      !_isRecording
                                                  ? () {
                                                      ref
                                                              .read(
                                                                imageGenerationEnabledProvider
                                                                    .notifier,
                                                              )
                                                              .state =
                                                          !imageGenEnabled;
                                                    }
                                                  : null,
                                            ),
                                          });
                                        } else {
                                          // Tool ID from server
                                          Tool? tool;
                                          for (final t in availableTools) {
                                            if (t.id == id) {
                                              tool = t;
                                              break;
                                            }
                                          }
                                          if (tool != null) {
                                            final lbl = tool.name;
                                            final tp = TextPainter(
                                              text: TextSpan(
                                                text: lbl,
                                                style: textStyle,
                                              ),
                                              maxLines: 1,
                                              textDirection: Directionality.of(
                                                context,
                                              ),
                                            )..layout();
                                            final selectedIds = ref.watch(
                                              selectedToolIdsProvider,
                                            );
                                            final isActive = selectedIds
                                                .contains(id);
                                            entries.add({
                                              'id': id,
                                              'label': lbl,
                                              'width':
                                                  tp.width + horizontalPadding,
                                              'widgetBuilder': () => _buildPillButton(
                                                icon: Platform.isIOS
                                                    ? CupertinoIcons.wrench
                                                    : Icons.build,
                                                label: lbl,
                                                isActive: isActive,
                                                onTap:
                                                    widget.enabled &&
                                                        !_isRecording
                                                    ? () {
                                                        final current =
                                                            List<String>.from(
                                                              ref.read(
                                                                selectedToolIdsProvider,
                                                              ),
                                                            );
                                                        if (current.contains(
                                                          id,
                                                        )) {
                                                          current.remove(id);
                                                        } else {
                                                          current.add(id);
                                                        }
                                                        ref
                                                                .read(
                                                                  selectedToolIdsProvider
                                                                      .notifier,
                                                                )
                                                                .state =
                                                            current;
                                                      }
                                                    : null,
                                              ),
                                            });
                                          }
                                        }
                                      }

                                      // Build rowChildren according to measured widths and available space
                                      final List<Widget> rowChildren = [];
                                      if (entries.isEmpty) {
                                        // no quick pills, will just show tools later
                                      } else if (entries.length == 1) {
                                        final e = entries.first;
                                        final pill =
                                            e['widgetBuilder']() as Widget;
                                        final w = (e['width'] as double);
                                        if (w <= availableForPills) {
                                          rowChildren.add(pill);
                                        } else {
                                          rowChildren.add(
                                            Flexible(
                                              fit: FlexFit.loose,
                                              child: pill,
                                            ),
                                          );
                                        }
                                      } else {
                                        // up to 2 based on settings enforcement; if more, take first 2
                                        final e1 = entries[0];
                                        final e2 = entries[1];
                                        final w1 = (e1['width'] as double);
                                        final w2 = (e2['width'] as double);
                                        const double gapBetweenPills =
                                            Spacing.xs;
                                        final combined =
                                            w1 + gapBetweenPills + w2;
                                        final pill1 =
                                            e1['widgetBuilder']() as Widget;
                                        final pill2 =
                                            e2['widgetBuilder']() as Widget;

                                        if (combined <= availableForPills) {
                                          rowChildren
                                            ..add(pill1)
                                            ..add(
                                              const SizedBox(width: Spacing.xs),
                                            )
                                            ..add(pill2);
                                        } else if (w1 < availableForPills) {
                                          rowChildren
                                            ..add(pill1)
                                            ..add(
                                              const SizedBox(width: Spacing.xs),
                                            )
                                            ..add(
                                              Flexible(
                                                fit: FlexFit.loose,
                                                child: pill2,
                                              ),
                                            );
                                        } else if (w2 < availableForPills) {
                                          rowChildren
                                            ..add(
                                              Flexible(
                                                fit: FlexFit.loose,
                                                child: pill1,
                                              ),
                                            )
                                            ..add(
                                              const SizedBox(width: Spacing.xs),
                                            )
                                            ..add(pill2);
                                        } else {
                                          final int f1 = math.max(
                                            1,
                                            w1.round(),
                                          );
                                          final int f2 = math.max(
                                            1,
                                            w2.round(),
                                          );
                                          rowChildren
                                            ..add(
                                              Flexible(
                                                fit: FlexFit.loose,
                                                flex: f1,
                                                child: pill1,
                                              ),
                                            )
                                            ..add(
                                              const SizedBox(width: Spacing.xs),
                                            )
                                            ..add(
                                              Flexible(
                                                fit: FlexFit.loose,
                                                flex: f2,
                                                child: pill2,
                                              ),
                                            );
                                        }
                                      }

                                      // Append tools button at the end (always visible)
                                      rowChildren.add(
                                        _buildIconButton(
                                          icon: Platform.isIOS
                                              ? CupertinoIcons.wrench
                                              : Icons.build,
                                          onTap: widget.enabled && !_isRecording
                                              ? _showUnifiedToolsModal
                                              : null,
                                          tooltip: AppLocalizations.of(
                                            context,
                                          )!.tools,
                                          isActive:
                                              ref
                                                  .watch(
                                                    selectedToolIdsProvider,
                                                  )
                                                  .isNotEmpty ||
                                              webSearchEnabled ||
                                              imageGenEnabled,
                                        ),
                                      );

                                      return Row(children: rowChildren);
                                    },
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
                                // Debug button for testing on-device STT (enable by changing false to true)
                                // ignore: dead_code
                                if (false) ...[
                                  const SizedBox(width: Spacing.sm),
                                  _buildRoundButton(
                                    icon: Icons.bug_report,
                                    onTap: widget.enabled
                                        ? () async {
                                            final result = await _voiceService
                                                .testOnDeviceStt();
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'STT Test: $result',
                                                  ),
                                                  duration: const Duration(
                                                    seconds: 5,
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        : null,
                                    tooltip: 'Test On-Device STT',
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
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
    bool isActive = false,
  }) {
    final Color iconColor = widget.enabled
        ? (isActive
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.textPrimary.withValues(
                  alpha: Alpha.strong,
                ))
        : context.conduitTheme.textPrimary.withValues(alpha: Alpha.disabled);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        padding: const EdgeInsets.all(Spacing.xs),
        constraints: const BoxConstraints(
          minWidth: TouchTarget.minimum,
          minHeight: TouchTarget.minimum,
        ),
        splashRadius: TouchTarget.minimum / 2,
        icon: Icon(icon, color: iconColor, size: IconSize.medium),
      ),
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
    bool showBackground = true,
    double? iconSize,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          side: BorderSide(
            color: isActive
                ? context.conduitTheme.buttonPrimary
                : showBackground
                ? context.conduitTheme.cardBorder
                : Colors.transparent,
            width: BorderWidth.regular,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBorderRadius.xl),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Container(
            width: TouchTarget.minimum,
            height: TouchTarget.minimum,
            decoration: BoxDecoration(
              color: isActive
                  ? context.conduitTheme.buttonPrimary
                  : showBackground
                  ? context.conduitTheme.cardBackground
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppBorderRadius.xl),
              boxShadow: (isActive || showBackground)
                  ? ConduitShadows.button
                  : null,
            ),
            child: Icon(
              icon,
              size: iconSize ?? IconSize.medium,
              color: widget.enabled
                  ? (isActive
                        ? context.conduitTheme.buttonPrimaryText
                        : context.conduitTheme.textPrimary.withValues(
                            alpha: Alpha.strong,
                          ))
                  : context.conduitTheme.textPrimary.withValues(
                      alpha: Alpha.disabled,
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
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        side: BorderSide(
          color: isActive
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.cardBorder,
          width: BorderWidth.regular,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.xl),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textStyle = AppTypography.labelStyle.copyWith(
              color: isActive
                  ? context.conduitTheme.buttonPrimary
                  : context.conduitTheme.textPrimary,
            );

            // Measure natural single-line text width
            final textPainter = TextPainter(
              text: TextSpan(text: label, style: textStyle),
              maxLines: 1,
              textDirection: Directionality.of(context),
            )..layout();

            const double horizontalPadding = Spacing.md * 2;
            final double naturalWidth = textPainter.width + horizontalPadding;
            final double maxAllowed = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : naturalWidth;
            final double finalWidth = math.min(naturalWidth, maxAllowed);
            final bool needsClamp = naturalWidth > maxAllowed;

            final double innerTextWidth = math.max(
              0.0,
              finalWidth - horizontalPadding,
            );

            return Container(
              width: finalWidth,
              height: TouchTarget.comfortable, // exact height match
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              decoration: BoxDecoration(
                // Subtle primary tint when active for clearer affordance
                color: isActive
                    ? context.conduitTheme.buttonPrimary.withValues(
                        alpha: Alpha.buttonHover + 0.04,
                      )
                    : context.conduitTheme.cardBackground,
                borderRadius: BorderRadius.circular(AppBorderRadius.xl),
                // No elevation to match modal chips
                boxShadow: ConduitShadows.button,
              ),
              child: Center(
                child: needsClamp
                    ? SizedBox(
                        width: innerTextWidth,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: textStyle,
                        ),
                      )
                    : Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        textAlign: TextAlign.center,
                        style: textStyle,
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
    HapticFeedback.selectionClick();
    final prevCanRequest = _focusNode.canRequestFocus;
    final wasFocused = _focusNode.hasFocus;
    _focusNode.canRequestFocus = false;
    // Ensure keyboard is closed before presenting modal
    try {
      FocusScope.of(context).unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppBorderRadius.bottomSheet),
          ),
          border: Border.all(
            color: context.conduitTheme.dividerColor,
            width: BorderWidth.regular,
          ),
          boxShadow: ConduitShadows.modal,
        ),
        padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar (standardized)
            const SheetHandle(),
            const SizedBox(height: Spacing.lg),

            // Options grid
            Row(
              children: [
                Expanded(
                  child: _buildAttachmentOption(
                    icon: Platform.isIOS
                        ? CupertinoIcons.doc
                        : Icons.attach_file,
                    label: AppLocalizations.of(context)!.file,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context); // Close modal
                      widget.onFileAttachment?.call();
                    },
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _buildAttachmentOption(
                    icon: Platform.isIOS ? CupertinoIcons.photo : Icons.image,
                    label: AppLocalizations.of(context)!.photo,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context); // Close modal
                      widget.onImageAttachment?.call();
                    },
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _buildAttachmentOption(
                    icon: Platform.isIOS
                        ? CupertinoIcons.camera
                        : Icons.camera_alt,
                    label: AppLocalizations.of(context)!.camera,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context); // Close modal
                      widget.onCameraCapture?.call();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) {
        _focusNode.canRequestFocus = prevCanRequest;
        if (wasFocused && widget.enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ensureFocusedIfEnabled();
            // Let focus naturally reopen the IME.
          });
        }
      }
    });
  }

  void _showUnifiedToolsModal() {
    HapticFeedback.selectionClick();
    final prevCanRequest = _focusNode.canRequestFocus;
    final wasFocused = _focusNode.hasFocus;
    _focusNode.canRequestFocus = false;
    // Ensure keyboard is closed before presenting modal
    try {
      FocusScope.of(context).unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } catch (_) {}
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const UnifiedToolsModal(),
    ).whenComplete(() {
      if (mounted) {
        _focusNode.canRequestFocus = prevCanRequest;
        if (wasFocused && widget.enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _ensureFocusedIfEnabled();
            // Let focus naturally reopen the IME.
          });
        }
      }
    });
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

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.conduitTheme.cardBackground,
                borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                border: Border.all(
                  color: context.conduitTheme.cardBorder,
                  width: BorderWidth.regular,
                ),
              ),
              child: Icon(
                icon,
                color: context.conduitTheme.iconPrimary,
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
      ),
    );
  }
}
