import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Event data from Server-Sent Events stream
class SSEEvent {
  final String? id;
  final String? event;
  final String data;
  final int? retry;

  SSEEvent({
    this.id,
    this.event,
    required this.data,
    this.retry,
  });
}

/// Parser for Server-Sent Events with robust error handling and heartbeat support
class SSEParser {
  final _controller = StreamController<SSEEvent>.broadcast();
  
  String _buffer = '';
  String? _currentId;
  String? _currentEvent;
  String _currentData = '';
  int? _currentRetry;
  
  // Heartbeat and health monitoring
  Timer? _heartbeatTimer;
  DateTime _lastDataReceived = DateTime.now();
  Duration _heartbeatTimeout = const Duration(seconds: 30);
  bool _isClosed = false;
  
  // Recovery state
  String? _lastEventId;
  bool _reconnectRequested = false;
  
  Stream<SSEEvent> get stream => _controller.stream;
  
  // Events for monitoring connection health
  final _heartbeatController = StreamController<void>.broadcast();
  final _reconnectController = StreamController<String?>.broadcast();
  
  Stream<void> get heartbeat => _heartbeatController.stream;
  Stream<String?> get reconnectRequests => _reconnectController.stream;
  
  SSEParser({Duration? heartbeatTimeout}) {
    if (heartbeatTimeout != null) {
      _heartbeatTimeout = heartbeatTimeout;
    }
    _startHeartbeatTimer();
  }
  
  /// Feed raw text data to the parser
  void feed(String chunk) {
    if (_isClosed) return;
    
    _lastDataReceived = DateTime.now();
    _buffer += chunk;
    _processBuffer();
    
    // Reset heartbeat timer since we received data
    _resetHeartbeatTimer();
  }
  
  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(_heartbeatTimeout, _onHeartbeatTimeout);
  }
  
  void _resetHeartbeatTimer() {
    if (!_isClosed) {
      _startHeartbeatTimer();
    }
  }
  
  void _onHeartbeatTimeout() {
    debugPrint('SSEParser: Heartbeat timeout - no data received in ${_heartbeatTimeout.inSeconds}s');
    
    if (!_isClosed) {
      // Emit heartbeat timeout event
      _heartbeatController.add(null);
      
      // Request reconnection with last event ID for recovery
      _reconnectRequested = true;
      _reconnectController.add(_lastEventId);
    }
  }
  
  /// Process buffered data and emit events
  void _processBuffer() {
    try {
      // Handle potential Unicode boundary issues by checking for incomplete characters
      if (_buffer.isNotEmpty && _hasIncompleteUnicode(_buffer)) {
        // Keep buffer intact if it might contain incomplete Unicode
        return;
      }
      
      // Split by newlines but keep the last incomplete line
      final lines = _buffer.split('\n');
      
      // Keep the last line in buffer if it doesn't end with newline
      if (!_buffer.endsWith('\n')) {
        _buffer = lines.removeLast();
      } else {
        _buffer = '';
      }
      
      for (final line in lines) {
        _processLine(line);
      }
    } catch (e) {
      debugPrint('SSEParser: Error processing buffer: $e');
      // Reset buffer on parsing error to prevent cascading failures
      _buffer = '';
    }
  }
  
  bool _hasIncompleteUnicode(String text) {
    if (text.isEmpty) return false;
    
    // Check if the last few characters might be incomplete Unicode
    // This is a simple heuristic - in practice, Dart's UTF-8 decoder handles this
    final lastChar = text.codeUnitAt(text.length - 1);
    
    // If it's a high surrogate, we might be missing the low surrogate
    return lastChar >= 0xD800 && lastChar <= 0xDBFF;
  }
  
  /// Process a single line according to SSE spec
  void _processLine(String line) {
    // Handle carriage return if present (some servers use \r\n)
    final cleanLine = line.replaceAll('\r', '');
    
    // Empty line signals end of event
    if (cleanLine.trim().isEmpty) {
      if (_currentData.isNotEmpty) {
        _emitEvent();
      }
      _resetCurrentEvent();
      return;
    }
    
    // Comment line (starts with :) - these serve as keep-alives
    if (cleanLine.startsWith(':')) {
      // Treat comments as heartbeat signals
      _lastDataReceived = DateTime.now();
      _resetHeartbeatTimer();
      
      // Log processing indicators but don't spam debug output
      if (cleanLine.contains('OPENROUTER') && kDebugMode) {
        debugPrint('SSEParser: OpenRouter processing...');
      } else if (cleanLine.contains('PROCESSING') && kDebugMode) {
        debugPrint('SSEParser: Server processing...');
      }
      return;
    }
    
    // Parse field and value
    final colonIndex = cleanLine.indexOf(':');
    String field;
    String value;
    
    if (colonIndex == -1) {
      field = cleanLine;
      value = '';
    } else {
      field = cleanLine.substring(0, colonIndex);
      value = cleanLine.substring(colonIndex + 1);
      // Remove leading space from value if present
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
    }
    
    // Process field according to SSE spec
    switch (field) {
      case 'data':
        if (_currentData.isNotEmpty) {
          _currentData += '\n';
        }
        _currentData += value;
        break;
      
      case 'event':
        _currentEvent = value;
        break;
      
      case 'id':
        _currentId = value;
        _lastEventId = value; // Track for reconnection
        break;
      
      case 'retry':
        final retryValue = int.tryParse(value);
        if (retryValue != null) {
          _currentRetry = retryValue;
        }
        break;
      
      default:
        // Ignore unknown fields
        break;
    }
  }
  
  /// Emit the current event
  void _emitEvent() {
    if (_isClosed) return;
    
    try {
      final event = SSEEvent(
        id: _currentId,
        event: _currentEvent,
        data: _currentData,
        retry: _currentRetry,
      );
      
      _controller.add(event);
      
      // Track last event ID for potential reconnection
      if (_currentId != null) {
        _lastEventId = _currentId;
      }
      
    } catch (e) {
      debugPrint('SSEParser: Error emitting event: $e');
      _controller.addError(e);
    }
  }
  
  /// Reset current event state
  void _resetCurrentEvent() {
    _currentEvent = null;
    _currentData = '';
    // Note: id and retry are not reset per SSE spec
  }
  
  /// Close the parser
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    
    // Cancel heartbeat timer
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    
    // Emit any remaining data
    if (_currentData.isNotEmpty) {
      _emitEvent();
    }
    
    // Close controllers
    _controller.close();
    _heartbeatController.close();
    _reconnectController.close();
  }
  
  /// Get the last event ID for reconnection
  String? get lastEventId => _lastEventId;
  
  /// Check if parser is closed
  bool get isClosed => _isClosed;
  
  /// Check if reconnection was requested due to timeout
  bool get reconnectRequested => _reconnectRequested;
  
  /// Reset reconnect flag (call when reconnection is handled)
  void resetReconnectFlag() {
    _reconnectRequested = false;
  }
  
  /// Get time since last data was received
  Duration get timeSinceLastData => DateTime.now().difference(_lastDataReceived);
  
  /// Parse SSE events from a stream of bytes with robust error handling
  static Stream<SSEEvent> parseStream(
    Stream<List<int>> byteStream, {
    Duration? heartbeatTimeout,
  }) {
    final parser = SSEParser(heartbeatTimeout: heartbeatTimeout);
    
    // Convert bytes to text and feed to parser with error recovery
    StreamSubscription? subscription;
    
    subscription = byteStream
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            try {
              parser.feed(chunk);
            } catch (e) {
              debugPrint('SSEParser: Error feeding chunk: $e');
              // Don't propagate feed errors - just skip the problematic chunk
            }
          },
          onDone: () => parser.close(),
          onError: (error) {
            debugPrint('SSEParser: Stream error: $error');
            parser._controller.addError(error);
          },
          cancelOnError: false, // Continue processing despite errors
        );
    
    // Clean up subscription when parser is closed
    parser._controller.onCancel = () {
      subscription?.cancel();
    };
    
    return parser.stream;
  }
}

/// Transform a text stream into SSE events with heartbeat monitoring
class SSETransformer extends StreamTransformerBase<String, SSEEvent> {
  final Duration? heartbeatTimeout;
  
  const SSETransformer({this.heartbeatTimeout});
  
  @override
  Stream<SSEEvent> bind(Stream<String> stream) {
    final parser = SSEParser(heartbeatTimeout: heartbeatTimeout);
    
    StreamSubscription? subscription;
    
    subscription = stream.listen(
      (chunk) {
        try {
          parser.feed(chunk);
        } catch (e) {
          debugPrint('SSETransformer: Error feeding chunk: $e');
          // Continue processing despite errors
        }
      },
      onDone: () => parser.close(),
      onError: (error) {
        debugPrint('SSETransformer: Stream error: $error');
        parser._controller.addError(error);
      },
      cancelOnError: false,
    );
    
    // Clean up subscription when parser is closed
    parser._controller.onCancel = () {
      subscription?.cancel();
    };
    
    return parser.stream;
  }
}

/// Enhanced SSE event with additional metadata for resilient streaming
class EnhancedSSEEvent extends SSEEvent {
  final DateTime timestamp;
  final int sequenceNumber;
  final String? sessionId;
  
  EnhancedSSEEvent({
    required super.data,
    super.id,
    super.event,
    super.retry,
    required this.timestamp,
    required this.sequenceNumber,
    this.sessionId,
  });
  
  factory EnhancedSSEEvent.fromSSEEvent(
    SSEEvent event, {
    required int sequenceNumber,
    String? sessionId,
  }) {
    return EnhancedSSEEvent(
      data: event.data,
      id: event.id,
      event: event.event,
      retry: event.retry,
      timestamp: DateTime.now(),
      sequenceNumber: sequenceNumber,
      sessionId: sessionId,
    );
  }
}