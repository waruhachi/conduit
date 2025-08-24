import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/platform_service.dart' as ps;
import '../../../core/services/settings_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/sheet_handle.dart';
import '../services/voice_input_service.dart';

class VoiceInputSheet extends ConsumerStatefulWidget {
  final void Function(String text) onTextReceived;

  const VoiceInputSheet({super.key, required this.onTextReceived});

  @override
  ConsumerState<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends ConsumerState<VoiceInputSheet> {
  late final VoiceInputService _voiceService;
  StreamSubscription<int>? _intensitySub;
  StreamSubscription<String>? _textSub;

  bool _isListening = false;
  bool _isTranscribing = false;
  int _intensity = 0; // 0..10
  String _recognizedText = '';
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;

  bool _holdToTalk = false;
  bool _autoSendFinal = false;
  String _languageTag = 'en';

  // Simplified: remove explicit mode selector and rely on a single toggle
  // Hold-to-talk: true → push-to-talk; false → continuous

  @override
  void initState() {
    super.initState();
    _voiceService = ref.read(voiceInputServiceProvider);

    // Initialize language
    try {
      final preset = _voiceService.selectedLocaleId;
      _languageTag =
          (preset ??
                  WidgetsBinding.instance.platformDispatcher.locale
                      .toLanguageTag())
              .split(RegExp('[-_]'))
              .first
              .toLowerCase();
    } catch (_) {
      _languageTag = 'en';
    }

    // Load persisted voice settings
    final settings = ref.read(appSettingsProvider);
    _holdToTalk = settings.voiceHoldToTalk;
    _autoSendFinal = settings.voiceAutoSendFinal;
    if (settings.voiceLocaleId != null && settings.voiceLocaleId!.isNotEmpty) {
      _voiceService.setLocale(settings.voiceLocaleId);
      _languageTag = settings.voiceLocaleId!
          .split(RegExp('[-_]'))
          .first
          .toLowerCase();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_holdToTalk && !_isListening) {
        _startListening();
      }
    });
  }

  @override
  void dispose() {
    _intensitySub?.cancel();
    _textSub?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _recognizedText = '';
      _elapsedSeconds = 0;
    });

    final hapticEnabled = ref.read(hapticEnabledProvider);
    ps.PlatformService.hapticFeedbackWithSettings(
      type: ps.HapticType.medium,
      hapticEnabled: hapticEnabled,
    );

    try {
      final ok = await _voiceService.initialize();
      if (!ok) throw Exception('Voice service unavailable');
      if (!_voiceService.hasLocalStt) {
        final mic = await _voiceService.checkPermissions();
        if (!mic) throw Exception('Microphone permission not granted');
      }

      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_isListening) {
          t.cancel();
          return;
        }
        setState(() => _elapsedSeconds += 1);
      });

      final stream = _voiceService.startListening();
      _intensitySub = _voiceService.intensityStream.listen((value) {
        if (!mounted) return;
        setState(() => _intensity = value);
      });
      _textSub = stream.listen(
        (text) {
          if (text.startsWith('[[AUDIO_FILE_PATH]]:')) {
            final path = text.split(':').skip(1).join(':');
            _transcribeRecordedFile(path);
          } else {
            setState(() => _recognizedText = text);
          }
        },
        onDone: () {
          setState(() => _isListening = false);
          _elapsedTimer?.cancel();
          if (_autoSendFinal && _recognizedText.trim().isNotEmpty) {
            _sendText();
          }
        },
        onError: (_) {
          setState(() => _isListening = false);
          _elapsedTimer?.cancel();
          final h = ref.read(hapticEnabledProvider);
          ps.PlatformService.hapticFeedbackWithSettings(
            type: ps.HapticType.warning,
            hapticEnabled: h,
          );
        },
      );
    } catch (_) {
      setState(() => _isListening = false);
    }
  }

  Future<void> _stopListening() async {
    _intensitySub?.cancel();
    _intensitySub = null;
    await _voiceService.stopListening();
    _elapsedTimer?.cancel();
    if (mounted) setState(() => _isListening = false);
    final hapticEnabled = ref.read(hapticEnabledProvider);
    ps.PlatformService.hapticFeedbackWithSettings(
      type: ps.HapticType.selection,
      hapticEnabled: hapticEnabled,
    );
  }

  Future<void> _transcribeRecordedFile(String filePath) async {
    try {
      setState(() => _isTranscribing = true);
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('API service unavailable');
      final bytes = await File(filePath).readAsBytes();
      String? language;
      try {
        language = WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag();
      } catch (_) {
        language = 'en-US';
      }
      final text = await api.transcribeAudio(
        bytes.toList(),
        language: language,
      );
      if (!mounted) return;
      setState(() {
        _recognizedText = text;
        _isListening = false;
      });
      if (_autoSendFinal && _recognizedText.trim().isNotEmpty) {
        _sendText();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  void _sendText() {
    if (_recognizedText.trim().isEmpty) return;
    final hapticEnabled = ref.read(hapticEnabledProvider);
    ps.PlatformService.hapticFeedbackWithSettings(
      type: ps.HapticType.success,
      hapticEnabled: hapticEnabled,
    );
    widget.onTextReceived(_recognizedText.trim());
    Navigator.of(context).pop();
  }

  String _formatSeconds(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _pickLanguage() async {
    if (!_voiceService.hasLocalStt) return;
    final locales = _voiceService.locales;
    if (locales.isEmpty || !mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
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
          child: SafeArea(
            top: false,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: locales.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: context.conduitTheme.dividerColor),
              itemBuilder: (ctx, i) {
                final l = locales[i];
                final isSelected = l.localeId == _voiceService.selectedLocaleId;
                return ListTile(
                  title: Text(
                    l.name,
                    style: TextStyle(color: context.conduitTheme.textPrimary),
                  ),
                  subtitle: Text(
                    l.localeId,
                    style: TextStyle(color: context.conduitTheme.textSecondary),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check,
                          color: context.conduitTheme.buttonPrimary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, l.localeId),
                );
              },
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _voiceService.setLocale(selected);
        _languageTag = selected.split(RegExp('[-_]')).first.toLowerCase();
      });
      await ref.read(appSettingsProvider.notifier).setVoiceLocaleId(selected);
      if (_isListening) {
        await _voiceService.stopListening();
        _startListening();
      }
    }
  }

  Widget _buildWaveform({required bool isCompact, required bool isUltra}) {
    final barCount = isUltra ? 10 : 12;
    final base = isUltra ? 4 : (isCompact ? 6 : 8);
    final range = isUltra ? 14 : (isCompact ? 18 : 24);
    return SizedBox(
      height: isUltra ? 18 : (isCompact ? 24 : 32),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: Row(
          key: ValueKey<int>(_intensity),
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final normalized = ((_intensity + i) % 10) / 10.0;
            final barHeight = base + (normalized * range);
            return Container(
              width: isUltra ? 2.5 : (isCompact ? 3 : 4),
              height: barHeight,
              margin: EdgeInsets.symmetric(
                horizontal: isUltra ? 1 : (isCompact ? 1.5 : 2),
              ),
              decoration: BoxDecoration(
                color: context.conduitTheme.buttonPrimary.withValues(
                  alpha: 0.7,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ),
    );
  }

  // Mode selector removed for simplicity

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isCompact = media.size.height < 680;

    return Container(
      height: media.size.height * (isCompact ? 0.45 : 0.6),
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.bottomSheet),
        ),
        border: Border.all(color: context.conduitTheme.dividerColor, width: 1),
        boxShadow: ConduitShadows.modal,
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
          child: Column(
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.only(
                  top: Spacing.md,
                  bottom: Spacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isTranscribing
                          ? AppLocalizations.of(context)!.transcribing
                          : _isListening
                          ? (_voiceService.hasLocalStt
                                ? AppLocalizations.of(context)!.listening
                                : AppLocalizations.of(context)!.recording)
                          : AppLocalizations.of(context)!.voiceInput,
                      style: TextStyle(
                        fontSize: AppTypography.headlineMedium,
                        fontWeight: FontWeight.w600,
                        color: context.conduitTheme.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _voiceService.hasLocalStt
                              ? _pickLanguage
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.xs,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: context.conduitTheme.surfaceBackground
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(
                                AppBorderRadius.badge,
                              ),
                              border: Border.all(
                                color: context.conduitTheme.dividerColor,
                                width: BorderWidth.thin,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _languageTag.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: AppTypography.labelSmall,
                                    color: context.conduitTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_voiceService.hasLocalStt) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 16,
                                    color: context.conduitTheme.iconSecondary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        AnimatedOpacity(
                          opacity: _isListening ? 1 : 0.6,
                          duration: AnimationDuration.fast,
                          child: Text(
                            _formatSeconds(_elapsedSeconds),
                            style: TextStyle(
                              color: context.conduitTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        ConduitIconButton(
                          icon: Platform.isIOS
                              ? CupertinoIcons.xmark
                              : Icons.close,
                          tooltip: AppLocalizations.of(
                            context,
                          )!.closeButtonSemantic,
                          isCompact: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Single-line controls
              Row(
                children: [
                  ps.PlatformService.getPlatformSwitch(
                    value: _holdToTalk,
                    onChanged: (v) async {
                      setState(() => _holdToTalk = v);
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setVoiceHoldToTalk(v);
                      if (!_holdToTalk && !_isListening) {
                        _startListening();
                      }
                      if (_holdToTalk && _isListening) {
                        _stopListening();
                      }
                    },
                    activeColor: context.conduitTheme.buttonPrimary,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Flexible(
                    child: Text(
                      AppLocalizations.of(context)!.holdToTalk,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.conduitTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  ps.PlatformService.getPlatformSwitch(
                    value: _autoSendFinal,
                    onChanged: (v) async {
                      setState(() => _autoSendFinal = v);
                      await ref
                          .read(appSettingsProvider.notifier)
                          .setVoiceAutoSendFinal(v);
                    },
                    activeColor: context.conduitTheme.buttonPrimary,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Flexible(
                    child: Text(
                      AppLocalizations.of(context)!.autoSend,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.conduitTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),

              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) {
                    final isUltra = media.size.height < 560;
                    final double micSize = isUltra
                        ? 72
                        : (isCompact ? 88 : 104);
                    final double micIconSize = isUltra
                        ? 28
                        : (isCompact ? 34 : 40);
                    final double topPaddingForScale =
                        ((micSize * 1.2) - micSize) / 2 + 8;

                    final content = Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: isUltra ? Spacing.sm : Spacing.md),
                          GestureDetector(
                            onTapDown: _holdToTalk
                                ? (_) {
                                    if (!_isListening) _startListening();
                                  }
                                : null,
                            onTapUp: _holdToTalk
                                ? (_) {
                                    if (_isListening) _stopListening();
                                  }
                                : null,
                            onTapCancel: _holdToTalk
                                ? () {
                                    if (_isListening) _stopListening();
                                  }
                                : null,
                            onTap: () => _holdToTalk
                                ? null
                                : (_isListening
                                      ? _stopListening()
                                      : _startListening()),
                            child: Semantics(
                              button: true,
                              label: _isListening
                                  ? AppLocalizations.of(context)!.stopListening
                                  : AppLocalizations.of(
                                      context,
                                    )!.startListening,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    width:
                                        micSize + (_intensity * 2).toDouble(),
                                    height:
                                        micSize + (_intensity * 2).toDouble(),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: _isListening
                                          ? [
                                              BoxShadow(
                                                color: context
                                                    .conduitTheme
                                                    .buttonPrimary
                                                    .withValues(alpha: 0.25),
                                                blurRadius:
                                                    24 + _intensity.toDouble(),
                                                spreadRadius: 2,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                  // Middle ring removed for simpler look
                                  Container(
                                    width: micSize,
                                    height: micSize,
                                    decoration: BoxDecoration(
                                      color: _isListening
                                          ? context.conduitTheme.buttonPrimary
                                                .withValues(alpha: 0.15)
                                          : context
                                                .conduitTheme
                                                .surfaceBackground
                                                .withValues(
                                                  alpha: Alpha.subtle,
                                                ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _isListening
                                            ? context.conduitTheme.buttonPrimary
                                            : context.conduitTheme.dividerColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(
                                      _isListening
                                          ? (Platform.isIOS
                                                ? CupertinoIcons.mic_fill
                                                : Icons.mic)
                                          : (Platform.isIOS
                                                ? CupertinoIcons.mic_off
                                                : Icons.mic_off),
                                      size: micIconSize,
                                      color: _isListening
                                          ? context.conduitTheme.buttonPrimary
                                          : context.conduitTheme.iconSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          _buildWaveform(
                            isCompact: isCompact,
                            isUltra: isUltra,
                          ),
                          SizedBox(
                            height: isUltra
                                ? Spacing.sm
                                : (isCompact ? Spacing.md : Spacing.xl),
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  media.size.height *
                                  (isUltra ? 0.13 : (isCompact ? 0.16 : 0.2)),
                              minHeight: isUltra ? 56 : (isCompact ? 64 : 80),
                            ),
                            child: ConduitCard(
                              isCompact: isCompact,
                              padding: EdgeInsets.all(
                                isCompact ? Spacing.md : Spacing.md,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.transcript,
                                        style: TextStyle(
                                          fontSize: AppTypography.labelSmall,
                                          fontWeight: FontWeight.w600,
                                          color: context
                                              .conduitTheme
                                              .textSecondary,
                                        ),
                                      ),
                                      const Spacer(),
                                      ConduitIconButton(
                                        icon: Icons.close,
                                        isCompact: true,
                                        tooltip: AppLocalizations.of(
                                          context,
                                        )!.clear,
                                        onPressed:
                                            _recognizedText.isNotEmpty &&
                                                !_isTranscribing
                                            ? () => setState(
                                                () => _recognizedText = '',
                                              )
                                            : null,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: Spacing.xs),
                                  if (_isTranscribing)
                                    Center(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          ConduitLoadingIndicator(
                                            size: isUltra
                                                ? 14
                                                : (isCompact ? 16 : 18),
                                            isCompact: true,
                                          ),
                                          const SizedBox(width: Spacing.xs),
                                          Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.transcribing,
                                            style: TextStyle(
                                              fontSize: isUltra
                                                  ? 12
                                                  : (isCompact ? 12 : 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Flexible(
                                      child: SingleChildScrollView(
                                        child: Text(
                                          _recognizedText.isEmpty
                                              ? (_isListening
                                                    ? (_voiceService.hasLocalStt
                                                          ? AppLocalizations.of(
                                                              context,
                                                            )!.speakNow
                                                          : AppLocalizations.of(
                                                              context,
                                                            )!.recording)
                                                    : AppLocalizations.of(
                                                        context,
                                                      )!.typeBelowToBegin)
                                              : _recognizedText,
                                          style: TextStyle(
                                            fontSize: isUltra
                                                ? AppTypography.bodySmall
                                                : (isCompact
                                                      ? AppTypography.bodyMedium
                                                      : AppTypography
                                                            .bodyLarge),
                                            color: _recognizedText.isEmpty
                                                ? context
                                                      .conduitTheme
                                                      .inputPlaceholder
                                                : context
                                                      .conduitTheme
                                                      .textPrimary,
                                            height: 1.4,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.only(top: topPaddingForScale),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: viewport.maxHeight,
                        ),
                        child: content,
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: ConduitButton(
                      text: _isListening
                          ? AppLocalizations.of(context)!.stop
                          : AppLocalizations.of(context)!.start,
                      isSecondary: true,
                      isCompact: isCompact,
                      onPressed: _isListening
                          ? _stopListening
                          : _startListening,
                    ),
                  ),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: ConduitButton(
                      text: AppLocalizations.of(context)!.send,
                      isCompact: isCompact,
                      onPressed: _recognizedText.isNotEmpty ? _sendText : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
