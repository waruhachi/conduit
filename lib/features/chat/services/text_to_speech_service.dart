import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lightweight wrapper around FlutterTts to centralize configuration
class TextToSpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _available = false;

  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  VoidCallback? _onCancel;
  VoidCallback? _onPause;
  VoidCallback? _onContinue;
  void Function(String message)? _onError;

  bool get isInitialized => _initialized;
  bool get isAvailable => _available;

  /// Register callbacks for TTS lifecycle events
  void bindHandlers({
    VoidCallback? onStart,
    VoidCallback? onComplete,
    VoidCallback? onCancel,
    VoidCallback? onPause,
    VoidCallback? onContinue,
    void Function(String message)? onError,
  }) {
    _onStart = onStart;
    _onComplete = onComplete;
    _onCancel = onCancel;
    _onPause = onPause;
    _onContinue = onContinue;
    _onError = onError;

    _tts.setStartHandler(_handleStart);
    _tts.setCompletionHandler(_handleComplete);
    _tts.setCancelHandler(_handleCancel);
    _tts.setPauseHandler(_handlePause);
    _tts.setContinueHandler(_handleContinue);
    _tts.setErrorHandler(_handleError);
  }

  /// Initialize the native TTS engine lazily
  Future<bool> initialize() async {
    if (_initialized) {
      return _available;
    }

    try {
      await _tts.awaitSpeakCompletion(false);
      if (!kIsWeb && Platform.isIOS) {
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ]);
      }
      _available = true;
    } catch (e) {
      _available = false;
      _onError?.call(e.toString());
    }

    _initialized = true;
    return _available;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Cannot speak empty text');
    }

    if (!_initialized) {
      await initialize();
    }

    if (!_available) {
      throw StateError('Text-to-speech is unavailable on this device');
    }

    await _tts.stop();
    final result = await _tts.speak(text);
    if (result == null) {
      return;
    }

    if (result is int && result != 1) {
      _onError?.call('Text-to-speech engine returned code $result');
    }
  }

  Future<void> pause() async {
    if (!_initialized || !_available) {
      return;
    }

    try {
      await _tts.pause();
    } catch (e) {
      _onError?.call(e.toString());
    }
  }

  Future<void> stop() async {
    if (!_initialized) {
      return;
    }

    try {
      await _tts.stop();
    } catch (e) {
      _onError?.call(e.toString());
    }
  }

  Future<void> dispose() async {
    await stop();
  }

  void _handleStart() {
    _onStart?.call();
  }

  void _handleComplete() {
    _onComplete?.call();
  }

  void _handleCancel() {
    _onCancel?.call();
  }

  void _handlePause() {
    _onPause?.call();
  }

  void _handleContinue() {
    _onContinue?.call();
  }

  void _handleError(dynamic message) {
    final safeMessage = message == null
        ? 'Unknown TTS error'
        : message.toString();
    _onError?.call(safeMessage);
  }
}
