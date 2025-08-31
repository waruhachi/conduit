import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import '../models/server_config.dart';

class SocketService {
  final ServerConfig serverConfig;
  final String? authToken;
  IO.Socket? _socket;

  SocketService({required this.serverConfig, required this.authToken});

  String? get sessionId => _socket?.id;
  IO.Socket? get socket => _socket;

  bool get isConnected => _socket?.connected == true;

  Future<void> connect({bool force = false}) async {
    if (_socket != null && _socket!.connected && !force) return;

    try {
      _socket?.dispose();
    } catch (_) {}

    final base = serverConfig.url.replaceFirst(RegExp(r'/+$'), '');
    final path = '/ws/socket.io';

    _socket = IO.io(
      base,
      IO.OptionBuilder()
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

  void offChatEvents() {
    _socket?.off('chat-events');
  }

  void dispose() {
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }
}
