import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceInputService {
  final AudioRecorder _recorder = AudioRecorder();
  stt.SpeechToText? _speech;
  bool _isInitialized = false;
  bool _isListening = false;
  bool _localSttAvailable = false;
  String? _selectedLocaleId;
  List<stt.LocaleName> _locales = const [];
  StreamController<String>? _textStreamController;
  String _currentText = '';
  // Public stream for UI waveform visualization (emits partial text length as proxy)
  StreamController<int>? _intensityController;
  Stream<int> get intensityStream =>
      _intensityController?.stream ?? const Stream<int>.empty();
  Timer? _autoStopTimer;
  StreamSubscription<Amplitude>? _ampSub;

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    if (!isSupportedPlatform) return false;
    // Prepare local speech recognizer
    try {
      _speech = stt.SpeechToText();
      _localSttAvailable = await _speech!.initialize(
        onStatus: (status) {
          // When platform end-of-speech triggers, ensure we stop timer/streams
          if (status.toLowerCase().contains('notListening') ||
              status.toLowerCase().contains('done')) {
            // No-op: UI manages stopping; SpeechToText emits final result
          }
        },
        onError: (SpeechRecognitionError error) {
          // If any error, we keep fallback available; no throws here.
        },
      );
      if (_localSttAvailable) {
        try {
          _locales = await _speech!.locales();
          final deviceTag = WidgetsBinding.instance.platformDispatcher.locale
              .toLanguageTag();
          final match = _locales.firstWhere(
            (l) => l.localeId.toLowerCase() == deviceTag.toLowerCase(),
            orElse: () {
              final primary = deviceTag.split(RegExp('[-_]')).first.toLowerCase();
              return _locales.firstWhere(
                (l) => l.localeId.toLowerCase().startsWith('$primary-'),
                orElse: () => _locales.isNotEmpty
                    ? _locales.first
                    : stt.LocaleName('en_US', 'English (US)'),
              );
            },
          );
          _selectedLocaleId = match.localeId;
        } catch (_) {
          _selectedLocaleId = null;
        }
      }
    } catch (_) {
      _localSttAvailable = false;
    }
    _isInitialized = true;
    return true;
  }

  Future<bool> checkPermissions() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  bool get isListening => _isListening;
  bool get isAvailable => _isInitialized; // service usable (local or fallback)
  bool get hasLocalStt => _localSttAvailable;
  String? get selectedLocaleId => _selectedLocaleId;
  List<stt.LocaleName> get locales => _locales;

  void setLocale(String? localeId) {
    _selectedLocaleId = localeId;
  }

  Stream<String> startListening() {
    if (!_isInitialized) {
      throw Exception('Voice input not initialized');
    }

    if (_isListening) {
      stopListening();
    }

    _textStreamController = StreamController<String>.broadcast();
    _currentText = '';
    _isListening = true;
    _intensityController = StreamController<int>.broadcast();

    if (_localSttAvailable && _speech != null) {
      // Local on-device STT path
      _autoStopTimer?.cancel();
      // SpeechToText has its own end-of-speech handling; we still cap at 60s
      _autoStopTimer = Timer(const Duration(seconds: 60), () {
        if (_isListening) {
          _stopListening();
        }
      });

      _speech!.listen(
        localeId: _selectedLocaleId,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
        onResult: (SpeechRecognitionResult result) {
          if (!_isListening) return;
          _currentText = result.recognizedWords;
          _textStreamController?.add(_currentText);
          if (result.finalResult) {
            // Will be followed by notListening status; we proactively close
            _stopListening();
          }
        },
        onSoundLevelChange: (level) {
          // level is roughly 0..1+; map to 0..10
          final scaled = (level * 10).clamp(0, 10).round();
          _intensityController?.add(scaled);
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );
    } else {
      // Fallback: record audio and signal file path for server transcription
      _startRecordingProxyIntensity();
      _autoStopTimer?.cancel();
      _autoStopTimer = Timer(const Duration(seconds: 30), () {
        if (_isListening) {
          _stopListening();
        }
      });
    }

    return _textStreamController!.stream;
  }

  Future<void> stopListening() async {
    await _stopListening();
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    if (_localSttAvailable && _speech != null) {
      try {
        await _speech!.stop();
      } catch (_) {}
    } else {
      // Also stop recorder if active
      await _stopRecording();
    }

    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _ampSub?.cancel();
    _ampSub = null;

    if (_currentText.isNotEmpty) {
      _textStreamController?.add(_currentText);
    }

    _textStreamController?.close();
    _textStreamController = null;
    _intensityController?.close();
    _intensityController = null;
  }

  void dispose() {
    stopListening();
    _stopRecording(force: true);
    try {
      _speech?.cancel();
    } catch (_) {}
  }

  // --- Recording and intensity proxy for server transcription path ---
  Future<void> _startRecordingProxyIntensity() async {
    try {
      final hasMic = await _recorder.hasPermission();
      if (!hasMic) {
        _textStreamController?.addError('Microphone permission not granted');
        _stopListening();
        return;
      }

      // Start recording in a portable format (WAV/PCM) for best compatibility with server
      final tmpDir = await getTemporaryDirectory();
      final filePath = p.join(
        tmpDir.path,
        'conduit_voice_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 16000,
          bitRate: 128000,
        ),
        path: filePath,
      );
      // recording started at filePath

      // Drive intensity from amplitude stream and detect silence
      // Consider amplitude less than threshold as silence; stop after ~3s of continuous silence
      const silenceThresholdDb = -45.0; // dBFS threshold
      const silenceWindow = Duration(seconds: 3);
      DateTime lastNonSilent = DateTime.now();

      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 125))
          .listen((amp) {
            if (!_isListening) return;
            // Normalize peak power (dBFS) into 0-10 bar scale
            final db = amp.current;
            // Map dB [-60..0] -> [0..10]
            final clamped = db.clamp(-60.0, 0.0);
            final norm = ((clamped + 60.0) / 60.0) * 10.0;
            _intensityController?.add(norm.round().clamp(0, 10));

            if (db > silenceThresholdDb) {
              lastNonSilent = DateTime.now();
            } else {
              if (DateTime.now().difference(lastNonSilent) >= silenceWindow) {
                _stopListening();
              }
            }
          });
    } catch (e) {
      _textStreamController?.addError('Audio recording failed: $e');
      _stopListening();
    }
  }

  Future<void> _stopRecording({bool force = false}) async {
    try {
      if (!await _recorder.isRecording() && !force) return;
      final path = await _recorder.stop();
      if (path == null) {
        _textStreamController?.addError('Recording failed: no file path');
        return;
      }
      // Hand off recorded file path to listeners as a special token; UI layer will upload for transcription
      _textStreamController?.add('[[AUDIO_FILE_PATH]]:$path');
    } catch (e) {
      _textStreamController?.addError('Stop recording error: $e');
    }
  }

  // Native locales not used in server transcription mode
}

final voiceInputServiceProvider = Provider<VoiceInputService>((ref) {
  return VoiceInputService();
});

final voiceInputAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(voiceInputServiceProvider);
  if (!service.isSupportedPlatform) return false;
  final initialized = await service.initialize();
  if (!initialized) return false;
  // If local STT exists, we consider it available; otherwise ensure mic permission for fallback
  if (service.hasLocalStt) return true;
  final hasPermission = await service.checkPermissions();
  if (!hasPermission) return false;
  return service.isAvailable;
});

final voiceInputStreamProvider = StreamProvider<String>((ref) {
  // Voice input stream would be initialized when needed
  return const Stream.empty();
});

/// Stream of crude voice intensity for waveform visuals
final voiceIntensityStreamProvider = StreamProvider<int>((ref) {
  // Connected at runtime by the UI after calling startListening
  return const Stream.empty();
});
