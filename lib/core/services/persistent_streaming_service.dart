import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'background_streaming_handler.dart';
import 'connectivity_service.dart';
import '../utils/debug_logger.dart';

class PersistentStreamingService with WidgetsBindingObserver {
  static final PersistentStreamingService _instance =
      PersistentStreamingService._internal();
  factory PersistentStreamingService() => _instance;
  PersistentStreamingService._internal() {
    _initialize();
  }

  // Active streams registry
  final Map<String, StreamSubscription> _activeStreams = {};
  final Map<String, StreamController> _streamControllers = {};
  final Map<String, Function> _streamRecoveryCallbacks = {};
  final Map<String, Map<String, dynamic>> _streamMetadata = {};

  // App lifecycle state
  // AppLifecycleState? _lastLifecycleState; // Removed as it's unused
  bool _isInBackground = false;
  Timer? _backgroundTimer;
  Timer? _heartbeatTimer;

  // Background streaming handler
  late final BackgroundStreamingHandler _backgroundHandler;

  // Connectivity monitoring
  StreamSubscription<bool>? _connectivitySubscription;
  ConnectivityService? _connectivityService;
  bool _hasConnectivity = true;

  // Recovery state
  final Map<String, int> _retryAttempts = {};
  static const int _maxRetryAttempts = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  void _initialize() {
    WidgetsBinding.instance.addObserver(this);
    _backgroundHandler = BackgroundStreamingHandler.instance;
    _setupBackgroundHandlerCallbacks();
    _startHeartbeat();
  }

  void _setupBackgroundHandlerCallbacks() {
    _backgroundHandler.onStreamsSuspending = (streamIds) {
      DebugLogger.stream(
        'PersistentStreaming: Streams suspending - $streamIds',
      );
      // Mark streams as suspended but don't close them yet
      for (final streamId in streamIds) {
        _markStreamAsSuspended(streamId);
      }
    };

    _backgroundHandler.onBackgroundTaskExpiring = () {
      DebugLogger.stream('PersistentStreaming: Background task expiring');
      // Save states and prepare for recovery
      _saveStreamStatesForRecovery();
    };

    _backgroundHandler.shouldContinueInBackground = () {
      return _activeStreams.isNotEmpty;
    };
  }

  void attachConnectivityService(ConnectivityService service) {
    if (identical(_connectivityService, service)) {
      return;
    }

    _connectivitySubscription?.cancel();
    _connectivityService = service;
    _connectivitySubscription = service.isConnected.listen(_handleConnectivityChange);
  }

  void _handleConnectivityChange(bool connected) {
    final wasConnected = _hasConnectivity;
    _hasConnectivity = connected;

    if (!wasConnected && connected) {
      DebugLogger.stream(
        'PersistentStreaming: Connectivity restored, recovering streams',
      );
      _recoverActiveStreams();
    } else if (wasConnected && !connected) {
      DebugLogger.stream(
        'PersistentStreaming: Connectivity lost, suspending streams',
      );
      _suspendAllStreams();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_activeStreams.isNotEmpty && _isInBackground) {
        _backgroundHandler.keepAlive();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // _lastLifecycleState = state; // Removed as it's unused

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _onAppBackground();
        break;
      case AppLifecycleState.resumed:
        _onAppForeground();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Handle app termination
        _onAppDetached();
        break;
    }
  }

  void _onAppBackground() {
    DebugLogger.stream('PersistentStreamingService: App went to background');
    _isInBackground = true;

    // Enable wake lock to prevent device sleep during streaming
    if (_activeStreams.isNotEmpty) {
      _enableWakeLock();
      _startBackgroundExecution();
    }
  }

  void _onAppForeground() {
    DebugLogger.stream(
      'PersistentStreamingService: App returned to foreground',
    );
    _isInBackground = false;

    // Cancel background timer
    _backgroundTimer?.cancel();
    _backgroundTimer = null;

    // Disable wake lock if no active streams
    if (_activeStreams.isEmpty) {
      _disableWakeLock();
    }

    // Check and recover any interrupted streams
    _recoverActiveStreams();
  }

  void _onAppDetached() {
    DebugLogger.stream('PersistentStreamingService: App detached');

    // Save stream states for recovery
    _saveStreamStatesForRecovery();

    // Clean up
    _backgroundTimer?.cancel();
    _heartbeatTimer?.cancel();
    _disableWakeLock();
  }

  // Register a stream for persistent handling
  String registerStream({
    required StreamSubscription subscription,
    required StreamController controller,
    Function? recoveryCallback,
    Map<String, dynamic>? metadata,
  }) {
    final streamId = DateTime.now().millisecondsSinceEpoch.toString();

    _activeStreams[streamId] = subscription;
    _streamControllers[streamId] = controller;
    if (recoveryCallback != null) {
      _streamRecoveryCallbacks[streamId] = recoveryCallback;
    }

    // Store metadata for recovery
    if (metadata != null) {
      _streamMetadata[streamId] = metadata;

      // Register with background handler
      _backgroundHandler.registerStream(
        streamId,
        conversationId: metadata['conversationId'] ?? '',
        messageId: metadata['messageId'] ?? '',
        sessionId: metadata['sessionId'],
        lastChunkSequence: metadata['lastChunkSequence'],
        lastContent: metadata['lastContent'],
      );
    }

    // Enable wake lock when streaming starts
    if (_activeStreams.length == 1) {
      _enableWakeLock();
    }

    // Start background execution if app is backgrounded
    if (_isInBackground) {
      _startBackgroundExecution();
    }

    DebugLogger.stream(
      'PersistentStreamingService: Registered stream $streamId',
    );

    return streamId;
  }

  // Unregister a stream
  void unregisterStream(String streamId) {
    _activeStreams.remove(streamId);
    _streamControllers.remove(streamId);
    _streamRecoveryCallbacks.remove(streamId);
    _streamMetadata.remove(streamId);
    _retryAttempts.remove(streamId);

    // Unregister from background handler
    _backgroundHandler.unregisterStream(streamId);

    // Stop background execution if no more streams
    if (_activeStreams.isEmpty) {
      _backgroundHandler.stopBackgroundExecution([streamId]);
      _disableWakeLock();
    }

    DebugLogger.stream(
      'PersistentStreamingService: Unregistered stream $streamId',
    );
  }

  // Check if a stream is still active
  bool isStreamActive(String streamId) {
    return _activeStreams.containsKey(streamId);
  }

  // Recover interrupted streams
  Future<void> _recoverActiveStreams() async {
    if (!_hasConnectivity) {
      DebugLogger.stream(
        'PersistentStreaming: No connectivity, skipping recovery',
      );
      return;
    }

    // First, try to recover from background handler saved states
    final savedStates = await _backgroundHandler.recoverStreamStates();
    for (final state in savedStates) {
      if (!state.isStale()) {
        await _recoverStreamFromState(state);
      }
    }

    // Then check active streams for recovery
    for (final entry in _streamRecoveryCallbacks.entries) {
      final streamId = entry.key;
      final recoveryCallback = entry.value;

      // Check if stream was interrupted or needs recovery
      final subscription = _activeStreams[streamId];
      if (subscription == null || _needsRecovery(streamId)) {
        await _attemptStreamRecovery(streamId, recoveryCallback);
      }
    }
  }

  Future<void> _recoverStreamFromState(StreamState state) async {
    final recoveryCallback = _streamRecoveryCallbacks[state.streamId];
    if (recoveryCallback != null) {
      DebugLogger.stream(
        'PersistentStreaming: Recovering stream from saved state: ${state.streamId}',
      );
      await _attemptStreamRecovery(state.streamId, recoveryCallback);
    }
  }

  Future<void> _attemptStreamRecovery(
    String streamId,
    Function recoveryCallback,
  ) async {
    final attempts = _retryAttempts[streamId] ?? 0;
    if (attempts >= _maxRetryAttempts) {
      DebugLogger.warning(
        'PersistentStreaming: Max retry attempts reached for stream $streamId',
      );
      return;
    }

    DebugLogger.stream(
      'PersistentStreaming: Recovering stream $streamId (attempt ${attempts + 1})',
    );

    try {
      _retryAttempts[streamId] = attempts + 1;

      // Add exponential backoff delay
      if (attempts > 0) {
        final delay = _retryDelay * (1 << (attempts - 1)); // 2s, 4s, 8s...
        await Future.delayed(delay);
      }

      // Call recovery callback to restart the stream
      await recoveryCallback();

      // Reset retry count on success
      _retryAttempts.remove(streamId);
    } catch (e) {
      DebugLogger.error(
        'PersistentStreaming: Failed to recover stream $streamId',
        e,
      );

      // Schedule next retry if under limit
      if (_retryAttempts[streamId]! < _maxRetryAttempts) {
        Timer(
          _retryDelay,
          () => _attemptStreamRecovery(streamId, recoveryCallback),
        );
      }
    }
  }

  bool _needsRecovery(String streamId) {
    final metadata = _streamMetadata[streamId];
    if (metadata == null) return false;

    // Check if stream has been inactive for too long
    final lastUpdate = metadata['lastUpdate'] as DateTime?;
    if (lastUpdate != null) {
      final timeSinceUpdate = DateTime.now().difference(lastUpdate);
      // Align with app-side watchdogs: be less aggressive than UI guard
      // but still attempt recovery before server timeouts become likely.
      return timeSinceUpdate > const Duration(minutes: 2);
    }

    return false;
  }

  // Platform-specific background execution
  void _startBackgroundExecution() {
    if (_activeStreams.isNotEmpty) {
      _backgroundHandler.startBackgroundExecution(_activeStreams.keys.toList());
    }
  }

  void _markStreamAsSuspended(String streamId) {
    final metadata = _streamMetadata[streamId];
    if (metadata != null) {
      metadata['suspended'] = true;
      metadata['suspendedAt'] = DateTime.now();
    }
  }

  void _suspendAllStreams() {
    for (final streamId in _activeStreams.keys) {
      _markStreamAsSuspended(streamId);
    }
  }

  void _saveStreamStatesForRecovery() {
    // The background handler will handle the actual saving
    DebugLogger.stream(
      'PersistentStreaming: Saving ${_activeStreams.length} stream states for recovery',
    );
  }

  // Update stream metadata when chunks are received
  void updateStreamProgress(
    String streamId, {
    int? chunkSequence,
    String? content,
    String? appendedContent,
  }) {
    // Update background handler state
    _backgroundHandler.updateStreamState(
      streamId,
      chunkSequence: chunkSequence,
      content: content,
      appendedContent: appendedContent,
    );

    // Update local metadata
    final metadata = _streamMetadata[streamId];
    if (metadata != null) {
      metadata['lastUpdate'] = DateTime.now();
      metadata['lastChunkSequence'] =
          chunkSequence ?? metadata['lastChunkSequence'];
      if (appendedContent != null) {
        metadata['lastContent'] =
            (metadata['lastContent'] ?? '') + appendedContent;
      } else if (content != null) {
        metadata['lastContent'] = content;
      }
      metadata['suspended'] = false; // Mark as active
    }
  }

  // Wake lock management
  void _enableWakeLock() async {
    try {
      await WakelockPlus.enable();
      DebugLogger.stream('PersistentStreamingService: Wake lock enabled');
    } catch (e) {
      DebugLogger.error(
        'PersistentStreamingService: Failed to enable wake lock',
        e,
      );
    }
  }

  void _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
      DebugLogger.stream('PersistentStreamingService: Wake lock disabled');
    } catch (e) {
      DebugLogger.error(
        'PersistentStreamingService: Failed to disable wake lock',
        e,
      );
    }
  }

  // Get active stream count
  int get activeStreamCount => _activeStreams.length;

  // Get stream metadata
  Map<String, dynamic>? getStreamMetadata(String streamId) {
    return _streamMetadata[streamId];
  }

  // Check if stream is suspended
  bool isStreamSuspended(String streamId) {
    final metadata = _streamMetadata[streamId];
    return metadata?['suspended'] == true;
  }

  // Force recovery of a specific stream
  Future<void> forceRecoverStream(String streamId) async {
    final recoveryCallback = _streamRecoveryCallbacks[streamId];
    if (recoveryCallback != null) {
      _retryAttempts.remove(streamId); // Reset retry count
      await _attemptStreamRecovery(streamId, recoveryCallback);
    }
  }

  // Cleanup
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundTimer?.cancel();
    _heartbeatTimer?.cancel();
    _connectivitySubscription?.cancel();
    _disableWakeLock();

    // Stop all background execution
    if (_activeStreams.isNotEmpty) {
      _backgroundHandler.stopBackgroundExecution(_activeStreams.keys.toList());
    }

    // Cancel all active streams
    for (final subscription in _activeStreams.values) {
      subscription.cancel();
    }
    _activeStreams.clear();

    // Close all controllers
    for (final controller in _streamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _streamControllers.clear();

    // Clear all metadata
    _streamMetadata.clear();
    _streamRecoveryCallbacks.clear();
    _retryAttempts.clear();

    // Clear background handler
    _backgroundHandler.clearAll();
  }
}
