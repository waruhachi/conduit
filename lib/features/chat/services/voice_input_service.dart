import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class VoiceInputService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isInitialized = false;
  bool _isListening = false;
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
    // Log platform for diagnostics
    // ignore: avoid_print
    print(
      'DEBUG: VoiceInputService initialize on platform: '
      '${Platform.isAndroid
          ? 'Android'
          : Platform.isIOS
          ? 'iOS'
          : 'Other'}',
    );
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
  bool get isAvailable => _isInitialized;

  Stream<String> startListening() {
    // Ensure initialized; we allow initialize to pass even if native STT unavailable
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

    // Start recording raw audio; UI or auto-timer will stop and trigger transcription via API
    // ignore: avoid_print
    print('DEBUG: VoiceInputService startListening');
    _startRecordingProxyIntensity();

    // Auto-stop after 30 seconds similar to native STT behavior
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(seconds: 30), () {
      if (_isListening) {
        _stopListening();
      }
    });

    return _textStreamController!.stream;
  }

  Future<void> stopListening() async {
    await _stopListening();
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    // Also stop recorder if active
    await _stopRecording();
    // ignore: avoid_print
    print('DEBUG: VoiceInputService stopped listening');

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
      // ignore: avoid_print
      print('DEBUG: VoiceInputService recording started at: ' + filePath);

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
      // ignore: avoid_print
      print('DEBUG: VoiceInputService recording failed: $e');
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
      // ignore: avoid_print
      print('DEBUG: VoiceInputService recording saved: ' + path);
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
