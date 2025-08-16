import 'dart:async';
import 'dart:convert';

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

/// Parser for Server-Sent Events
class SSEParser {
  final _controller = StreamController<SSEEvent>.broadcast();
  
  String _buffer = '';
  String? _currentId;
  String? _currentEvent;
  String _currentData = '';
  int? _currentRetry;
  
  Stream<SSEEvent> get stream => _controller.stream;
  
  /// Feed raw text data to the parser
  void feed(String chunk) {
    _buffer += chunk;
    _processBuffer();
  }
  
  /// Process buffered data and emit events
  void _processBuffer() {
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
  }
  
  /// Process a single line according to SSE spec
  void _processLine(String line) {
    // Empty line signals end of event
    if (line.trim().isEmpty) {
      if (_currentData.isNotEmpty) {
        _emitEvent();
      }
      _resetCurrentEvent();
      return;
    }
    
    // Comment line (starts with :)
    // OpenRouter sends ": OPENROUTER PROCESSING" messages
    if (line.startsWith(':')) {
      // Log but ignore comments
      if (line.contains('OPENROUTER')) {
        // OpenRouter processing indicator - ignore silently
      }
      return; // Ignore comments
    }
    
    // Parse field and value
    final colonIndex = line.indexOf(':');
    String field;
    String value;
    
    if (colonIndex == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colonIndex);
      value = line.substring(colonIndex + 1);
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
    _controller.add(SSEEvent(
      id: _currentId,
      event: _currentEvent,
      data: _currentData,
      retry: _currentRetry,
    ));
  }
  
  /// Reset current event state
  void _resetCurrentEvent() {
    _currentEvent = null;
    _currentData = '';
    // Note: id and retry are not reset per SSE spec
  }
  
  /// Close the parser
  void close() {
    // Emit any remaining data
    if (_currentData.isNotEmpty) {
      _emitEvent();
    }
    _controller.close();
  }
  
  /// Parse SSE events from a stream of bytes
  static Stream<SSEEvent> parseStream(Stream<List<int>> byteStream) {
    final parser = SSEParser();
    
    // Convert bytes to text and feed to parser
    byteStream
        .transform(utf8.decoder)
        .listen(
          (chunk) => parser.feed(chunk),
          onDone: () => parser.close(),
          onError: (error) => parser._controller.addError(error),
        );
    
    return parser.stream;
  }
}

/// Transform a text stream into SSE events
class SSETransformer extends StreamTransformerBase<String, SSEEvent> {
  @override
  Stream<SSEEvent> bind(Stream<String> stream) {
    final parser = SSEParser();
    
    stream.listen(
      (chunk) => parser.feed(chunk),
      onDone: () => parser.close(),
      onError: (error) => parser._controller.addError(error),
    );
    
    return parser.stream;
  }
}