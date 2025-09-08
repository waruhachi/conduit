import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';
import '../models/server_config.dart';

class SocketService {
  final ServerConfig serverConfig;
  final String? authToken;
  final bool websocketOnly;
  io.Socket? _socket;

  SocketService({
    required this.serverConfig,
    required this.authToken,
    this.websocketOnly = false,
  });

  String? get sessionId => _socket?.id;
  io.Socket? get socket => _socket;

  bool get isConnected => _socket?.connected == true;

  Future<void> connect({bool force = false}) async {
    if (_socket != null && _socket!.connected && !force) return;

    try {
      _socket?.dispose();
    } catch (_) {}

    String base = serverConfig.url.replaceFirst(RegExp(r'/+$'), '');
    // Normalize accidental ":0" ports or invalid port values in stored URL
    try {
      final u = Uri.parse(base);
      if (u.hasPort && u.port == 0) {
        // Drop the explicit :0 to fall back to scheme default (80/443)
        base = '${u.scheme}://${u.host}${u.path.isEmpty ? '' : u.path}';
      }
    } catch (_) {}
    final path = '/ws/socket.io';

    final builder = io.OptionBuilder()
        // Transport selection
        .setTransports(
          websocketOnly ? ['websocket'] : ['polling', 'websocket'],
        )
        .setRememberUpgrade(!websocketOnly)
        .setUpgrade(!websocketOnly)
        // Tune reconnect/backoff and timeouts
        .setReconnectionAttempts(0) // 0/Infinity semantics: unlimited attempts
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setRandomizationFactor(0.5)
        .setTimeout(20000)
        .setPath(path);

    // Merge Authorization (if any) with user-defined custom headers for the
    // Socket.IO handshake. Avoid overriding reserved headers.
    final Map<String, String> extraHeaders = {};
    if (authToken != null && authToken!.isNotEmpty) {
      extraHeaders['Authorization'] = 'Bearer $authToken';
      builder.setAuth({'token': authToken});
    }
    if (serverConfig.customHeaders.isNotEmpty) {
      final reserved = {
        'authorization',
        'content-type',
        'accept',
        // Socket/WebSocket reserved or managed by client/runtime
        'host',
        'origin',
        'connection',
        'upgrade',
        'sec-websocket-key',
        'sec-websocket-version',
        'sec-websocket-extensions',
        'sec-websocket-protocol',
      };
      serverConfig.customHeaders.forEach((key, value) {
        final lower = key.toLowerCase();
        if (!reserved.contains(lower) && value.isNotEmpty) {
          // Do not overwrite Authorization we already set from authToken
          if (lower == 'authorization' && extraHeaders.containsKey('Authorization')) {
            return;
          }
          extraHeaders[key] = value;
        }
      });
    }
    if (extraHeaders.isNotEmpty) {
      builder.setExtraHeaders(extraHeaders);
    }

    _socket = io.io(base, builder.build());

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

    _socket!.on('reconnect_attempt', (attempt) {
      debugPrint('Socket reconnect_attempt: $attempt');
    });

    _socket!.on('reconnect', (attempt) {
      debugPrint('Socket reconnected after $attempt attempts');
      if (authToken != null && authToken!.isNotEmpty) {
        // Best-effort rejoin
        _socket!.emit('user-join', {
          'auth': {'token': authToken}
        });
      }
    });

    _socket!.on('reconnect_failed', (_) {
      debugPrint('Socket reconnect_failed');
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

  // Best-effort: ensure there is an active connection and wait briefly.
  // Returns true if connected by the end of the timeout.
  Future<bool> ensureConnected({Duration timeout = const Duration(seconds: 2)}) async {
    if (isConnected) return true;
    try {
      await connect();
    } catch (_) {}
    final start = DateTime.now();
    while (!isConnected && DateTime.now().difference(start) < timeout) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return isConnected;
  }
}
