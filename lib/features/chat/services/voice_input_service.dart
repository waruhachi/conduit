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
      debugPrint('DEBUG: Initializing speech_to_text...');
      _localSttAvailable = await _speech!.initialize(
        onStatus: (status) {
          debugPrint('DEBUG: SpeechToText status: $status');
          // When platform end-of-speech triggers, ensure we stop timer/streams
          if (status.toLowerCase().contains('notListening') ||
              status.toLowerCase().contains('done')) {
            // No-op: UI manages stopping; SpeechToText emits final result
          }
        },
        onError: (SpeechRecognitionError error) {
          debugPrint('DEBUG: SpeechToText error: ${error.errorMsg}');
          debugPrint('DEBUG: SpeechToText error permanent: ${error.permanent}');
          // If error is permanent, mark local STT as unavailable
          if (error.permanent) {
            debugPrint('DEBUG: Permanent error detected, disabling local STT');
            _localSttAvailable = false;
          }
          // If any error, we keep fallback available; no throws here.
        },
      );
      debugPrint(
        'DEBUG: SpeechToText initialization result: $_localSttAvailable',
      );
      if (_localSttAvailable) {
        try {
          _locales = await _speech!.locales();
          debugPrint(
            'DEBUG: Available locales: ${_locales.map((l) => l.localeId).join(', ')}',
          );
          final deviceTag = WidgetsBinding.instance.platformDispatcher.locale
              .toLanguageTag();
          debugPrint('DEBUG: Device locale: $deviceTag');
          final match = _locales.firstWhere(
            (l) => l.localeId.toLowerCase() == deviceTag.toLowerCase(),
            orElse: () {
              final primary = deviceTag
                  .split(RegExp('[-_]'))
                  .first
                  .toLowerCase();
              return _locales.firstWhere(
                (l) => l.localeId.toLowerCase().startsWith('$primary-'),
                orElse: () => _locales.isNotEmpty
                    ? _locales.first
                    : stt.LocaleName('en_US', 'English (US)'),
              );
            },
          );
          _selectedLocaleId = match.localeId;
          debugPrint('DEBUG: Selected locale: $_selectedLocaleId');
        } catch (e) {
          debugPrint('DEBUG: Error loading locales: $e');
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

  // Add a method to check if on-device STT is properly supported
  Future<bool> checkOnDeviceSupport() async {
    if (!isSupportedPlatform || !_isInitialized) return false;
    if (_speech == null) return false;

    try {
      // Check if the speech engine supports on-device recognition
      final result = await _speech!.initialize();
      debugPrint('DEBUG: On-device support check - initialize result: $result');

      if (result) {
        // Note: getEngines() method is not available in speech_to_text 7.3.0
        // The package handles engine selection internally
        debugPrint(
          'DEBUG: SpeechToText initialized successfully - engine selection handled internally',
        );
      }

      return result;
    } catch (e) {
      debugPrint('DEBUG: Error checking on-device support: $e');
      return false;
    }
  }

  // Test method to verify on-device STT functionality
  Future<String> testOnDeviceStt() async {
    try {
      debugPrint('DEBUG: Starting on-device STT test');

      // First ensure we're initialized
      await initialize();

      if (!_localSttAvailable || _speech == null) {
        return 'Local STT not available. Available: $_localSttAvailable, Speech: ${_speech != null}';
      }

      // Check microphone permission
      final hasMic = await checkPermissions();
      if (!hasMic) {
        return 'Microphone permission not granted';
      }

      // Test if speech recognition is available
      final isAvailable = await _speech!.isAvailable;
      debugPrint('DEBUG: Speech recognition isAvailable: $isAvailable');

      if (!isAvailable) {
        return 'Speech recognition service is not available on this device';
      }

      // Check if listening is already active
      final isListening = await _speech!.isListening;
      debugPrint('DEBUG: Speech recognition isListening: $isListening');

      if (isListening) {
        await _speech!.stop();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Check if we can start listening
      startListening();

      // Wait a bit for initialization
      await Future.delayed(const Duration(milliseconds: 100));

      // Stop immediately after starting
      await stopListening();

      return 'On-device STT test completed successfully. Local STT available: $_localSttAvailable, Selected locale: $_selectedLocaleId';
    } catch (e) {
      debugPrint('DEBUG: On-device STT test failed: $e');
      return 'On-device STT test failed: $e';
    }
  }

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

    // Check if speech recognition is available before trying to use it
    if (_localSttAvailable && _speech != null) {
      // Schedule a check for speech recognition availability
      Future.microtask(() async {
        try {
          final isStillAvailable = await _speech!.isAvailable;
          if (!isStillAvailable && _isListening) {
            debugPrint(
              'DEBUG: Speech recognition no longer available, falling back to recording',
            );
            _localSttAvailable = false;
            // Restart with fallback method
            _startRecordingProxyIntensity();
            _autoStopTimer?.cancel();
            _autoStopTimer = Timer(const Duration(seconds: 30), () {
              if (_isListening) {
                _stopListening();
              }
            });
            return;
          }
        } catch (e) {
          debugPrint('DEBUG: Error checking speech availability: $e');
        }
      });

      // Local on-device STT path
      debugPrint(
        'DEBUG: Starting on-device STT with locale: $_selectedLocaleId',
      );
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
        pauseFor: const Duration(seconds: 3),
        onResult: (SpeechRecognitionResult result) {
          if (!_isListening) return;
          debugPrint(
            'DEBUG: Speech result: "${result.recognizedWords}" (final: ${result.finalResult})',
          );
          _currentText = result.recognizedWords;
          _textStreamController?.add(_currentText);
          if (result.finalResult) {
            // Will be followed by notListening status; we proactively close
            _stopListening();
          }
        },
        onSoundLevelChange: (level) {
          debugPrint('DEBUG: Sound level: $level');
          // level is roughly 0..1+; map to 0..10
          final scaled = (level * 10).clamp(0, 10).round();
          _intensityController?.add(scaled);
        },
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
        onDevice: true,
      );
      debugPrint('DEBUG: SpeechToText.listen() called with onDevice: true');
    } else {
      // Fallback: record audio and signal file path for server transcription
      debugPrint('DEBUG: Local STT not available, falling back to recording');
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
