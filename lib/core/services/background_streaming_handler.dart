import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Handles background streaming continuation for iOS and Android
/// 
/// On iOS: Uses background tasks to keep streams alive for ~30 seconds
/// On Android: Uses foreground service notifications
class BackgroundStreamingHandler {
  static const MethodChannel _channel = MethodChannel('conduit/background_streaming');
  
  static BackgroundStreamingHandler? _instance;
  static BackgroundStreamingHandler get instance => _instance ??= BackgroundStreamingHandler._();
  
  BackgroundStreamingHandler._() {
    _setupMethodCallHandler();
  }
  
  final Set<String> _activeStreamIds = <String>{};
  final Map<String, StreamState> _streamStates = <String, StreamState>{};
  
  // Callbacks for platform-specific events
  void Function(List<String> streamIds)? onStreamsSuspending;
  void Function()? onBackgroundTaskExpiring;
  bool Function()? shouldContinueInBackground;
  
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'checkStreams':
          return _activeStreamIds.length;
          
        case 'streamsSuspending':
          final Map<String, dynamic> args = call.arguments as Map<String, dynamic>;
          final List<String> streamIds = (args['streamIds'] as List).cast<String>();
          final String reason = args['reason'] as String;
          
          debugPrint('Background: Streams suspending - $streamIds (reason: $reason)');
          onStreamsSuspending?.call(streamIds);
          
          // Save stream states for recovery
          await _saveStreamStatesForRecovery(streamIds, reason);
          break;
          
        case 'backgroundTaskExpiring':
          debugPrint('Background: Background task expiring');
          onBackgroundTaskExpiring?.call();
          break;
      }
    });
  }
  
  /// Start background execution for given stream IDs
  Future<void> startBackgroundExecution(List<String> streamIds) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    
    _activeStreamIds.addAll(streamIds);
    
    try {
      await _channel.invokeMethod('startBackgroundExecution', {
        'streamIds': streamIds,
      });
      
      debugPrint('Background: Started background execution for ${streamIds.length} streams');
    } catch (e) {
      debugPrint('Background: Failed to start background execution: $e');
    }
  }
  
  /// Stop background execution for given stream IDs
  Future<void> stopBackgroundExecution(List<String> streamIds) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    
    _activeStreamIds.removeAll(streamIds);
    streamIds.forEach(_streamStates.remove);
    
    try {
      await _channel.invokeMethod('stopBackgroundExecution', {
        'streamIds': streamIds,
      });
      
      debugPrint('Background: Stopped background execution for ${streamIds.length} streams');
    } catch (e) {
      debugPrint('Background: Failed to stop background execution: $e');
    }
  }
  
  /// Register a stream with its current state
  void registerStream(String streamId, {
    required String conversationId,
    required String messageId,
    String? sessionId,
    int? lastChunkSequence,
    String? lastContent,
  }) {
    _streamStates[streamId] = StreamState(
      streamId: streamId,
      conversationId: conversationId,
      messageId: messageId,
      sessionId: sessionId,
      lastChunkSequence: lastChunkSequence ?? 0,
      lastContent: lastContent ?? '',
      timestamp: DateTime.now(),
    );
    
    _activeStreamIds.add(streamId);
  }
  
  /// Update stream state with new chunk
  void updateStreamState(String streamId, {
    int? chunkSequence,
    String? content,
    String? appendedContent,
  }) {
    final state = _streamStates[streamId];
    if (state == null) return;
    
    _streamStates[streamId] = state.copyWith(
      lastChunkSequence: chunkSequence ?? state.lastChunkSequence,
      lastContent: appendedContent != null 
          ? (state.lastContent + appendedContent)
          : (content ?? state.lastContent),
      timestamp: DateTime.now(),
    );
  }
  
  /// Unregister a stream when it completes
  void unregisterStream(String streamId) {
    _activeStreamIds.remove(streamId);
    _streamStates.remove(streamId);
  }
  
  /// Get current stream state for recovery
  StreamState? getStreamState(String streamId) {
    return _streamStates[streamId];
  }
  
  /// Keep alive the background task (iOS only)
  Future<void> keepAlive() async {
    if (!Platform.isIOS) return;
    
    try {
      await _channel.invokeMethod('keepAlive');
    } catch (e) {
      debugPrint('Background: Failed to keep alive: $e');
    }
  }
  
  /// Recover stream states from previous app session
  Future<List<StreamState>> recoverStreamStates() async {
    if (!Platform.isIOS && !Platform.isAndroid) return [];
    
    try {
      final List<dynamic>? states = await _channel.invokeMethod('recoverStreamStates');
      if (states == null) return [];
      
      final recovered = <StreamState>[];
      for (final stateData in states) {
        final map = stateData as Map<String, dynamic>;
        final state = StreamState.fromMap(map);
        if (state != null) {
          recovered.add(state);
          _streamStates[state.streamId] = state;
        }
      }
      
      debugPrint('Background: Recovered ${recovered.length} stream states');
      return recovered;
    } catch (e) {
      debugPrint('Background: Failed to recover stream states: $e');
      return [];
    }
  }
  
  /// Save stream states for recovery after app restart
  Future<void> _saveStreamStatesForRecovery(List<String> streamIds, String reason) async {
    final statesToSave = streamIds
        .map((id) => _streamStates[id])
        .where((state) => state != null)
        .map((state) => state!.toMap())
        .toList();
    
    try {
      await _channel.invokeMethod('saveStreamStates', {
        'states': statesToSave,
        'reason': reason,
      });
    } catch (e) {
      debugPrint('Background: Failed to save stream states: $e');
    }
  }
  
  /// Check if any streams are currently active
  bool get hasActiveStreams => _activeStreamIds.isNotEmpty;
  
  /// Get list of active stream IDs
  List<String> get activeStreamIds => _activeStreamIds.toList();
  
  /// Clear all stream data (usually on app termination)
  void clearAll() {
    _activeStreamIds.clear();
    _streamStates.clear();
  }
}

/// Represents the state of a streaming request
class StreamState {
  final String streamId;
  final String conversationId;
  final String messageId;
  final String? sessionId;
  final int lastChunkSequence;
  final String lastContent;
  final DateTime timestamp;
  
  const StreamState({
    required this.streamId,
    required this.conversationId,
    required this.messageId,
    this.sessionId,
    required this.lastChunkSequence,
    required this.lastContent,
    required this.timestamp,
  });
  
  StreamState copyWith({
    String? streamId,
    String? conversationId,
    String? messageId,
    String? sessionId,
    int? lastChunkSequence,
    String? lastContent,
    DateTime? timestamp,
  }) {
    return StreamState(
      streamId: streamId ?? this.streamId,
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      sessionId: sessionId ?? this.sessionId,
      lastChunkSequence: lastChunkSequence ?? this.lastChunkSequence,
      lastContent: lastContent ?? this.lastContent,
      timestamp: timestamp ?? this.timestamp,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'streamId': streamId,
      'conversationId': conversationId,
      'messageId': messageId,
      'sessionId': sessionId,
      'lastChunkSequence': lastChunkSequence,
      'lastContent': lastContent,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
  
  static StreamState? fromMap(Map<String, dynamic> map) {
    try {
      return StreamState(
        streamId: map['streamId'] as String,
        conversationId: map['conversationId'] as String,
        messageId: map['messageId'] as String,
        sessionId: map['sessionId'] as String?,
        lastChunkSequence: map['lastChunkSequence'] as int? ?? 0,
        lastContent: map['lastContent'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      debugPrint('Failed to parse StreamState from map: $e');
      return null;
    }
  }
  
  /// Check if this state is stale (older than threshold)
  bool isStale({Duration threshold = const Duration(minutes: 5)}) {
    return DateTime.now().difference(timestamp) > threshold;
  }
  
  @override
  String toString() {
    return 'StreamState(streamId: $streamId, conversationId: $conversationId, '
           'messageId: $messageId, sequence: $lastChunkSequence, '
           'contentLength: ${lastContent.length}, timestamp: $timestamp)';
  }
}