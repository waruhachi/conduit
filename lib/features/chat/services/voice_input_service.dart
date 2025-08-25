import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:stts/stts.dart';

// Lightweight replacement for previous stt.LocaleName used across the UI
class LocaleName {
  final String localeId;
  final String name;
  const LocaleName(this.localeId, this.name);
}

class VoiceInputService {
  final AudioRecorder _recorder = AudioRecorder();
  final Stt _speech = Stt();
  bool _isInitialized = false;
  bool _isListening = false;
  bool _localSttAvailable = false;
  String? _selectedLocaleId;
  List<LocaleName> _locales = const [];
  StreamController<String>? _textStreamController;
  String _currentText = '';
  // Public stream for UI waveform visualization (emits partial text length as proxy)
  StreamController<int>? _intensityController;
  Stream<int> get intensityStream =>
      _intensityController?.stream ?? const Stream<int>.empty();

  /// Public stream of partial/final transcript strings and special audio tokens.
  Stream<String> get textStream =>
      _textStreamController?.stream ?? const Stream<String>.empty();
  Timer? _autoStopTimer;
  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<SttRecognition>? _sttResultSub;
  StreamSubscription<SttState>? _sttStateSub;

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    if (!isSupportedPlatform) return false;
    // Prepare local speech recognizer
    try {
      // Check permission and supported status
      _localSttAvailable = await _speech.isSupported();
      if (_localSttAvailable) {
        try {
          final langs = await _speech.getLanguages();
          _locales = langs.map((l) => LocaleName(l, l)).toList();
          final deviceTag = WidgetsBinding.instance.platformDispatcher.locale
              .toLanguageTag();
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
                    : LocaleName('en_US', 'en_US'),
              );
            },
          );
          _selectedLocaleId = match.localeId;
        } catch (e) {
          // ignore locale load errors
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
      // Prefer stts permission check which will request microphone permission
      final mic = await _speech.hasPermission();
      if (mic) return true;
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
    try {
      final supported = await _speech.isSupported();
      return supported;
    } catch (e) {
      // ignore errors checking on-device support
      return false;
    }
  }

  // Test method to verify on-device STT functionality
  Future<String> testOnDeviceStt() async {
    try {
      // starting on-device STT test

      // First ensure we're initialized
      await initialize();

      if (!_localSttAvailable) {
        return 'Local STT not available. Available: $_localSttAvailable';
      }

      // Check microphone permission
      final hasMic = await checkPermissions();
      if (!hasMic) {
        return 'Microphone permission not granted';
      }

      // Test if speech recognition is available
      final supported = await _speech.isSupported();
      if (!supported)
        return 'Speech recognition service is not available on this device';

      // Set language if available, then start and stop quickly
      if (_selectedLocaleId != null) {
        try {
          await _speech.setLanguage(_selectedLocaleId!);
        } catch (_) {}
      }
      await _speech.start(SttRecognitionOptions(punctuation: true));
      await Future.delayed(const Duration(milliseconds: 100));
      await _speech.stop();

      return 'On-device STT test completed successfully. Local STT available: $_localSttAvailable, Selected locale: $_selectedLocaleId';
    } catch (e) {
      // on-device STT test failed
      return 'On-device STT test failed: $e';
    }
  }

  String? get selectedLocaleId => _selectedLocaleId;
  List<LocaleName> get locales => _locales;

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
    if (_localSttAvailable) {
      // Schedule a check for speech recognition availability
      Future.microtask(() async {
        try {
          final isStillAvailable = await _speech.isSupported();
          if (!isStillAvailable && _isListening) {
            // speech recognition no longer available, fallback to recording
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
          // ignore availability check errors
        }
      });

      // Local on-device STT path
      _autoStopTimer?.cancel();
      _autoStopTimer = Timer(const Duration(seconds: 60), () {
        if (_isListening) {
          _stopListening();
        }
      });

      // Listen for results and state changes; keep subscriptions so we can cancel later
      _sttResultSub = _speech.onResultChanged.listen((SttRecognition result) {
        if (!_isListening) return;
        _currentText = result.text;
        _textStreamController?.add(_currentText);
        if (result.isFinal) {
          _stopListening();
        }
      }, onError: (_) {});

      _sttStateSub = _speech.onStateChanged.listen((_) {}, onError: (_) {});

      try {
        if (_selectedLocaleId != null) {
          _speech.setLanguage(_selectedLocaleId!).catchError((_) {});
        }
        // Start recognition (no await blocking the sync flow)
        _speech.start(SttRecognitionOptions(punctuation: true)).catchError((_) {
          // fallback to recording
          _localSttAvailable = false;
          _startRecordingProxyIntensity();
        });
      } catch (e) {
        _localSttAvailable = false;
        _startRecordingProxyIntensity();
      }
    } else {
      // Fallback: record audio and signal file path for server transcription
      // Local STT not available, falling back to recording
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
    if (_localSttAvailable) {
      try {
        await _speech.stop();
      } catch (_) {}
      // Cancel STT subscriptions
      try {
        _sttResultSub?.cancel();
      } catch (_) {}
      _sttResultSub = null;
      try {
        _sttStateSub?.cancel();
      } catch (_) {}
      _sttStateSub = null;
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
      _speech.dispose().catchError((_) {});
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
  final service = ref.watch(voiceInputServiceProvider);
  return service.textStream;
});

/// Stream of crude voice intensity for waveform visuals
final voiceIntensityStreamProvider = StreamProvider<int>((ref) {
  final service = ref.watch(voiceInputServiceProvider);
  return service.intensityStream;
});
