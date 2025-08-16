import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class StreamRecoveryService {
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  
  // Recovery state for each stream
  final Map<String, StreamRecoveryState> _recoveryStates = {};
  
  // Register a stream for recovery
  void registerStream(String streamId, StreamRecoveryState state) {
    _recoveryStates[streamId] = state;
    debugPrint('StreamRecoveryService: Registered stream $streamId for recovery');
  }
  
  // Unregister a stream
  void unregisterStream(String streamId) {
    _recoveryStates.remove(streamId);
    debugPrint('StreamRecoveryService: Unregistered stream $streamId');
  }
  
  // Attempt to recover a stream
  Future<Stream<String>?> recoverStream(String streamId) async {
    final state = _recoveryStates[streamId];
    if (state == null) {
      debugPrint('StreamRecoveryService: No recovery state for stream $streamId');
      return null;
    }
    
    debugPrint('StreamRecoveryService: Attempting to recover stream $streamId');
    debugPrint('StreamRecoveryService: Last received index: ${state.lastReceivedIndex}');
    
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        // Create recovery request with continuation token
        final recoveryData = {
          ...state.originalRequest,
          'continue_from_index': state.lastReceivedIndex,
          'recovery_mode': true,
          'stream_id': streamId,
        };
        
        // Add any accumulated content to avoid duplication
        if (state.accumulatedContent.isNotEmpty) {
          recoveryData['accumulated_content'] = state.accumulatedContent;
        }
        
        debugPrint('StreamRecoveryService: Recovery attempt ${retryCount + 1}/$maxRetries');
        
        // Make recovery request
        final dio = Dio(BaseOptions(
          baseUrl: state.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: null, // No timeout for streaming
          headers: state.headers,
        ));
        
        final response = await dio.post(
          state.endpoint,
          data: recoveryData,
          options: Options(
            headers: {
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
            },
            responseType: ResponseType.stream,
          ),
        );
        
        if (response.statusCode == 200) {
          debugPrint('StreamRecoveryService: Successfully recovered stream $streamId');
          
          // Create new stream from recovered response
          final stream = _processRecoveredStream(
            response.data.stream,
            state,
            streamId,
          );
          
          return stream;
        }
      } catch (e) {
        debugPrint('StreamRecoveryService: Recovery attempt failed: $e');
        retryCount++;
        
        if (retryCount < maxRetries) {
          await Future.delayed(retryDelay * retryCount);
        }
      }
    }
    
    debugPrint('StreamRecoveryService: Failed to recover stream $streamId after $maxRetries attempts');
    return null;
  }
  
  // Process recovered stream and filter out duplicates
  Stream<String> _processRecoveredStream(
    Stream<List<int>> rawStream,
    StreamRecoveryState state,
    String streamId,
  ) {
    final controller = StreamController<String>();
    
    String buffer = '';
    bool skipUntilNewContent = state.lastReceivedIndex > 0;
    int currentIndex = 0;
    
    rawStream.listen(
      (chunk) {
        final text = utf8.decode(chunk, allowMalformed: true);
        buffer += text;
        
        // Process complete SSE events
        while (buffer.contains('\n')) {
          final lineEnd = buffer.indexOf('\n');
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);
          
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            
            if (data == '[DONE]') {
              controller.close();
              return;
            }
            
            // Parse JSON data
            try {
              final json = jsonDecode(data);
              
              // Check if we should skip this content (already received)
              if (skipUntilNewContent) {
                currentIndex++;
                if (currentIndex <= state.lastReceivedIndex) {
                  debugPrint('StreamRecoveryService: Skipping duplicate content at index $currentIndex');
                  continue;
                }
                skipUntilNewContent = false;
              }
              
              // Extract content from JSON
              if (json['choices'] != null && json['choices'].isNotEmpty) {
                final delta = json['choices'][0]['delta'];
                if (delta != null && delta['content'] != null) {
                  final content = delta['content'] as String;
                  
                  // Update recovery state
                  state.lastReceivedIndex = currentIndex;
                  state.accumulatedContent += content;
                  
                  // Emit recovered content
                  controller.add(content);
                  currentIndex++;
                }
              }
            } catch (e) {
              debugPrint('StreamRecoveryService: Error parsing recovered data: $e');
            }
          }
        }
      },
      onDone: () {
        debugPrint('StreamRecoveryService: Recovered stream completed');
        controller.close();
        unregisterStream(streamId);
      },
      onError: (error) {
        debugPrint('StreamRecoveryService: Recovered stream error: $error');
        controller.addError(error);
        
        // Attempt another recovery
        Future.delayed(retryDelay, () async {
          final recoveredStream = await recoverStream(streamId);
          if (recoveredStream != null) {
            recoveredStream.listen(
              (data) => controller.add(data),
              onDone: () => controller.close(),
              onError: (e) => controller.addError(e),
            );
          } else {
            controller.close();
          }
        });
      },
    );
    
    return controller.stream;
  }
  
  // Update recovery state with new content
  void updateStreamProgress(String streamId, String content, int index) {
    final state = _recoveryStates[streamId];
    if (state != null) {
      state.lastReceivedIndex = index;
      state.accumulatedContent += content;
    }
  }
  
  // Clear recovery state for a stream
  void clearStreamState(String streamId) {
    _recoveryStates.remove(streamId);
  }
}

// Recovery state for a stream
class StreamRecoveryState {
  final String baseUrl;
  final String endpoint;
  final Map<String, dynamic> originalRequest;
  final Map<String, String> headers;
  int lastReceivedIndex;
  String accumulatedContent;
  DateTime lastActivity;
  
  StreamRecoveryState({
    required this.baseUrl,
    required this.endpoint,
    required this.originalRequest,
    required this.headers,
    this.lastReceivedIndex = 0,
    this.accumulatedContent = '',
  }) : lastActivity = DateTime.now();
  
  // Check if stream is stale (no activity for too long)
  bool get isStale {
    return DateTime.now().difference(lastActivity).inMinutes > 5;
  }
  
  // Update activity timestamp
  void updateActivity() {
    lastActivity = DateTime.now();
  }
}