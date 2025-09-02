import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import '../models/server_config.dart';

class SocketService {
  final ServerConfig serverConfig;
  final String? authToken;
  io.Socket? _socket;

  SocketService({required this.serverConfig, required this.authToken});

  String? get sessionId => _socket?.id;
  io.Socket? get socket => _socket;

  bool get isConnected => _socket?.connected == true;

  Future<void> connect({bool force = false}) async {
    if (_socket != null && _socket!.connected && !force) return;

    try {
      _socket?.dispose();
    } catch (_) {}

    final base = serverConfig.url.replaceFirst(RegExp(r'/+$'), '');
    final path = '/ws/socket.io';

    _socket = io.io(
      base,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath(path)
          .setExtraHeaders(
            authToken != null && authToken!.isNotEmpty
                ? {
                    'Authorization': 'Bearer $authToken',
                  }
                : {},
          )
          .build(),
    );

    _socket!.on('connect', (_) {
      debugPrint('Socket connected: ${_socket!.id}');
      if (authToken != null && authToken!.isNotEmpty) {
        _socket!.emit('user-join', {
          'auth': {'token': authToken}
        });
      }
    });

    _socket!.on('connect_error', (err) {
      debugPrint('Socket connect_error: $err');
    });

    _socket!.on('disconnect', (reason) {
      debugPrint('Socket disconnected: $reason');
    });
  }

  void onChatEvents(void Function(Map<String, dynamic> event) handler) {
    _socket?.on('chat-events', (data) {
      try {
        if (data is Map<String, dynamic>) {
          handler(data);
        } else if (data is Map) {
          handler(Map<String, dynamic>.from(data));
        }
      } catch (_) {}
    });
  }

  // Subscribe to general channel events (server-broadcasted channel updates)
  void onChannelEvents(void Function(Map<String, dynamic> event) handler) {
    _socket?.on('channel-events', (data) {
      try {
        if (data is Map<String, dynamic>) {
          handler(data);
        } else if (data is Map) {
          handler(Map<String, dynamic>.from(data));
        }
      } catch (_) {}
    });
  }

  void offChatEvents() {
    _socket?.off('chat-events');
  }

  void offChannelEvents() {
    _socket?.off('channel-events');
  }

  // Subscribe to an arbitrary socket.io event (used for dynamic tool channels)
  void onEvent(String eventName, void Function(dynamic data) handler) {
    _socket?.on(eventName, handler);
  }

  void offEvent(String eventName) {
    _socket?.off(eventName);
  }
  void dispose() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }
}
