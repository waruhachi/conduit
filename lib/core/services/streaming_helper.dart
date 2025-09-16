import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/models/chat_message.dart';
import '../../core/services/persistent_streaming_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/utils/stream_chunker.dart';
import '../../core/utils/tool_calls_parser.dart';

// Keep local verbosity toggle for socket logs
const bool kSocketVerboseLogging = false;

/// Unified streaming helper for chat send/regenerate flows.
///
/// This attaches chunked SSE streaming handlers, optional WebSocket event handlers,
/// and manages background search/image-gen UI updates. It operates via callbacks to
/// avoid tight coupling with provider files for easier reuse and testing.
StreamSubscription<String> attachUnifiedChunkedStreaming({
  required Stream<String> stream,
  required bool webSearchEnabled,
  required bool isBackgroundFlow,
  required bool suppressSocketContentInitially,
  required bool usingDynamicChannelInitially,
  required String assistantMessageId,
  required String modelId,
  required Map<String, dynamic> modelItem,
  required String sessionId,
  required String? activeConversationId,
  required dynamic api,
  required SocketService? socketService,
  // Message update callbacks
  required void Function(String) appendToLastMessage,
  required void Function(String) replaceLastMessageContent,
  required void Function(ChatMessage Function(ChatMessage))
  updateLastMessageWith,
  required void Function() finishStreaming,
  required List<ChatMessage> Function() getMessages,
}) {
  // Chunk the incoming stream for smoother UI updates
  final chunkedStream = StreamChunker.chunkStream(
    stream,
    enableChunking: true,
    minChunkSize: 5,
    maxChunkLength: 3,
    delayBetweenChunks: const Duration(milliseconds: 15),
  );

  // Persistable controller to survive brief app suspensions
  final persistentController = StreamController<String>.broadcast();
  final persistentService = PersistentStreamingService();

  final streamId = persistentService.registerStream(
    subscription: chunkedStream.listen(
      persistentController.add,
      onDone: persistentController.close,
      onError: persistentController.addError,
    ),
    controller: persistentController,
    recoveryCallback: () async {
      debugPrint('DEBUG: Attempting to recover interrupted stream');
    },
    metadata: {
      'conversationId': activeConversationId,
      'messageId': assistantMessageId,
      'modelId': modelId,
    },
  );

  bool isSearching = false;
  bool suppressSocketContent = suppressSocketContentInitially;
  bool usingDynamicChannel = usingDynamicChannelInitially;

  void updateImagesFromCurrentContent() {
    try {
      final msgs = getMessages();
      if (msgs.isEmpty || msgs.last.role != 'assistant') return;
      final content = msgs.last.content;
      if (content.isEmpty) return;

      final collected = <Map<String, dynamic>>[];

      if (content.contains('<details')) {
        final parsed = ToolCallsParser.parse(content);
        if (parsed != null) {
          for (final entry in parsed.toolCalls) {
            if (entry.files != null && entry.files!.isNotEmpty) {
              collected.addAll(_extractFilesFromResult(entry.files));
            }
            if (entry.result != null) {
              collected.addAll(_extractFilesFromResult(entry.result));
            }
          }
        }
      }

      if (collected.isEmpty) {
        final base64Pattern = RegExp(
          r'data:image/[^;\s]+;base64,[A-Za-z0-9+/]+=*',
        );
        final base64Matches = base64Pattern.allMatches(content);
        for (final match in base64Matches) {
          final url = match.group(0);
          if (url != null && url.isNotEmpty) {
            collected.add({'type': 'image', 'url': url});
          }
        }

        final urlPattern = RegExp(
          r'https?://[^\s<>\"]+\.(jpg|jpeg|png|gif|webp)',
          caseSensitive: false,
        );
        final urlMatches = urlPattern.allMatches(content);
        for (final match in urlMatches) {
          final url = match.group(0);
          if (url != null && url.isNotEmpty) {
            collected.add({'type': 'image', 'url': url});
          }
        }

        final jsonPattern = RegExp(
          r'\{[^}]*"url"[^}]*:[^}]*"(data:image/[^"]+|https?://[^"]+\.(jpg|jpeg|png|gif|webp))"[^}]*\}',
          caseSensitive: false,
        );
        final jsonMatches = jsonPattern.allMatches(content);
        for (final match in jsonMatches) {
          final url = RegExp(
            r'"url"[^:]*:[^"]*"([^"]+)"',
          ).firstMatch(match.group(0) ?? '')?.group(1);
          if (url != null && url.isNotEmpty) {
            collected.add({'type': 'image', 'url': url});
          }
        }

        final partialResultsPattern = RegExp(
          r'(result|files)="([^"]*(?:data:image/[^"]*|https?://[^"]*\.(jpg|jpeg|png|gif|webp))[^"]*)"',
          caseSensitive: false,
        );
        final partialMatches = partialResultsPattern.allMatches(content);
        for (final match in partialMatches) {
          final attrValue = match.group(2);
          if (attrValue != null) {
            try {
              final decoded = json.decode(attrValue);
              collected.addAll(_extractFilesFromResult(decoded));
            } catch (_) {
              if (attrValue.startsWith('data:image/') ||
                  RegExp(
                    r'https?://[^\s]+\.(jpg|jpeg|png|gif|webp)$',
                    caseSensitive: false,
                  ).hasMatch(attrValue)) {
                collected.add({'type': 'image', 'url': attrValue});
              }
            }
          }
        }
      }

      if (collected.isEmpty) return;

      final existing = msgs.last.files ?? <Map<String, dynamic>>[];
      final seen = <String>{
        for (final f in existing)
          if (f['url'] is String) (f['url'] as String) else '',
      }..removeWhere((e) => e.isEmpty);

      final merged = <Map<String, dynamic>>[...existing];
      for (final f in collected) {
        final url = f['url'] as String?;
        if (url != null && url.isNotEmpty && !seen.contains(url)) {
          merged.add({'type': 'image', 'url': url});
          seen.add(url);
        }
      }

      if (merged.length != existing.length) {
        updateLastMessageWith((m) => m.copyWith(files: merged));
      }
    } catch (_) {}
  }

  void channelLineHandlerFactory(String channel) {
    void handler(dynamic line) {
      try {
        if (line is String) {
          final s = line.trim();
          if (s == '[DONE]' || s == 'DONE') {
            try {
              socketService?.offEvent(channel);
            } catch (_) {}
            try {
              // Fire and forget
              // ignore: unawaited_futures
              api?.sendChatCompleted(
                chatId: activeConversationId ?? '',
                messageId: assistantMessageId,
                messages: const [],
                model: modelId,
                modelItem: modelItem,
                sessionId: sessionId,
              );
            } catch (_) {}
            finishStreaming();
            return;
          }
          if (s.startsWith('data:')) {
            final dataStr = s.substring(5).trim();
            if (dataStr == '[DONE]') {
              try {
                socketService?.offEvent(channel);
              } catch (_) {}
              try {
                // ignore: unawaited_futures
                api?.sendChatCompleted(
                  chatId: activeConversationId ?? '',
                  messageId: assistantMessageId,
                  messages: const [],
                  model: modelId,
                  modelItem: modelItem,
                  sessionId: sessionId,
                );
              } catch (_) {}
              finishStreaming();
              return;
            }
            try {
              final Map<String, dynamic> j = jsonDecode(dataStr);
              final choices = j['choices'];
              if (choices is List && choices.isNotEmpty) {
                final choice = choices.first;
                final delta = choice is Map ? choice['delta'] : null;
                if (delta is Map) {
                  if (delta.containsKey('tool_calls')) {
                    final tc = delta['tool_calls'];
                    if (tc is List) {
                      for (final call in tc) {
                        if (call is Map<String, dynamic>) {
                          final fn = call['function'];
                          final name = (fn is Map && fn['name'] is String)
                              ? fn['name'] as String
                              : null;
                          if (name is String && name.isNotEmpty) {
                            final msgs = getMessages();
                            final exists =
                                (msgs.isNotEmpty) &&
                                RegExp(
                                  r'<details\s+type=\"tool_calls\"[^>]*\bname=\"' +
                                      RegExp.escape(name) +
                                      r'\"',
                                  multiLine: true,
                                ).hasMatch(msgs.last.content);
                            if (!exists) {
                              final status =
                                  '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                              appendToLastMessage(status);
                            }
                          }
                        }
                      }
                    }
                  }
                  final content = delta['content']?.toString() ?? '';
                  if (content.isNotEmpty) {
                    appendToLastMessage(content);
                    updateImagesFromCurrentContent();
                  }
                }
              }
            } catch (_) {
              if (s.isNotEmpty) {
                appendToLastMessage(s);
                updateImagesFromCurrentContent();
              }
            }
          } else {
            if (s.isNotEmpty) {
              appendToLastMessage(s);
              updateImagesFromCurrentContent();
            }
          }
        } else if (line is Map) {
          if (line['done'] == true) {
            try {
              socketService?.offEvent(channel);
            } catch (_) {}
            finishStreaming();
            return;
          }
        }
      } catch (_) {}
    }

    try {
      socketService?.onEvent(channel, handler);
    } catch (_) {}
    Future.delayed(const Duration(minutes: 3), () {
      try {
        socketService?.offEvent(channel);
      } catch (_) {}
    });
  }

  void chatHandler(Map<String, dynamic> ev) {
    try {
      final data = ev['data'];
      if (data == null) return;
      final type = data['type'];
      final payload = data['data'];

      if (type == 'chat:completion' && payload != null) {
        if (payload is Map<String, dynamic>) {
          if (payload.containsKey('tool_calls')) {
            final tc = payload['tool_calls'];
            if (tc is List) {
              for (final call in tc) {
                if (call is Map<String, dynamic>) {
                  final fn = call['function'];
                  final name = (fn is Map && fn['name'] is String)
                      ? fn['name'] as String
                      : null;
                  if (name is String && name.isNotEmpty) {
                    final msgs = getMessages();
                    final exists =
                        (msgs.isNotEmpty) &&
                        RegExp(
                          r'<details\s+type=\"tool_calls\"[^>]*\bname=\"' +
                              RegExp.escape(name) +
                              r'\"',
                          multiLine: true,
                        ).hasMatch(msgs.last.content);
                    if (!exists) {
                      final status =
                          '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                      appendToLastMessage(status);
                    }
                  }
                }
              }
            }
          }
          if (!suppressSocketContent && payload.containsKey('choices')) {
            final choices = payload['choices'];
            if (choices is List && choices.isNotEmpty) {
              final choice = choices.first;
              final delta = choice is Map ? choice['delta'] : null;
              if (delta is Map) {
                if (delta.containsKey('tool_calls')) {
                  final tc = delta['tool_calls'];
                  if (tc is List) {
                    for (final call in tc) {
                      if (call is Map<String, dynamic>) {
                        final fn = call['function'];
                        final name = (fn is Map && fn['name'] is String)
                            ? fn['name'] as String
                            : null;
                        if (name is String && name.isNotEmpty) {
                          final msgs = getMessages();
                          final exists =
                              (msgs.isNotEmpty) &&
                              RegExp(
                                r'<details\s+type=\"tool_calls\"[^>]*\bname=\"' +
                                    RegExp.escape(name) +
                                    r'\"',
                                multiLine: true,
                              ).hasMatch(msgs.last.content);
                          if (!exists) {
                            final status =
                                '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                            appendToLastMessage(status);
                          }
                        }
                      }
                    }
                  }
                }
                final content = delta['content']?.toString() ?? '';
                if (content.isNotEmpty) {
                  appendToLastMessage(content);
                  updateImagesFromCurrentContent();
                }
              }
            }
          }
          if (payload['done'] == true) {
            try {
              socketService?.offChatEvents();
            } catch (_) {}
            try {
              // ignore: unawaited_futures
              api?.sendChatCompleted(
                chatId: activeConversationId ?? '',
                messageId: assistantMessageId,
                messages: const [],
                model: modelId,
                modelItem: modelItem,
                sessionId: sessionId,
              );
            } catch (_) {}

            final msgs = getMessages();
            if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
              final lastContent = msgs.last.content.trim();
              if (lastContent.isEmpty) {
                Future.microtask(() async {
                  try {
                    final chatId = activeConversationId;
                    if (chatId != null && chatId.isNotEmpty) {
                      final resp = await api?.dio.get('/api/v1/chats/$chatId');
                      final data = resp?.data as Map<String, dynamic>?;
                      String content = '';
                      final chatObj = data?['chat'] as Map<String, dynamic>?;
                      if (chatObj != null) {
                        final list = chatObj['messages'];
                        if (list is List) {
                          final target = list.firstWhere(
                            (m) =>
                                (m is Map &&
                                (m['id']?.toString() == assistantMessageId)),
                            orElse: () => null,
                          );
                          if (target != null) {
                            final rawContent = (target as Map)['content'];
                            if (rawContent is String) {
                              content = rawContent;
                            } else if (rawContent is List) {
                              final textItem = rawContent.firstWhere(
                                (i) => i is Map && i['type'] == 'text',
                                orElse: () => null,
                              );
                              if (textItem != null) {
                                content = textItem['text']?.toString() ?? '';
                              }
                            }
                          }
                        }
                        if (content.isEmpty) {
                          final history = chatObj['history'];
                          if (history is Map && history['messages'] is Map) {
                            final Map<String, dynamic> messagesMap =
                                (history['messages'] as Map)
                                    .cast<String, dynamic>();
                            final msg = messagesMap[assistantMessageId];
                            if (msg is Map) {
                              final rawContent = msg['content'];
                              if (rawContent is String) {
                                content = rawContent;
                              } else if (rawContent is List) {
                                final textItem = rawContent.firstWhere(
                                  (i) => i is Map && i['type'] == 'text',
                                  orElse: () => null,
                                );
                                if (textItem != null) {
                                  content = textItem['text']?.toString() ?? '';
                                }
                              }
                            }
                          }
                        }
                      }
                      if (content.isNotEmpty) {
                        replaceLastMessageContent(content);
                      }
                    }
                  } catch (_) {
                  } finally {
                    finishStreaming();
                  }
                });
                return;
              }
            }
            finishStreaming();
          }
        }
      } else if (type == 'chat:message:error' && payload != null) {
        // Server reports an error for the current assistant message
        try {
          dynamic err = payload is Map ? payload['error'] : null;
          String content = '';
          if (err is Map) {
            final c = err['content'];
            if (c is String) {
              content = c;
            } else if (c != null) {
              content = c.toString();
            }
          } else if (err is String) {
            content = err;
          } else if (payload is Map && payload['message'] is String) {
            content = payload['message'];
          }
          if (content.isNotEmpty) {
            // Replace current assistant message with a readable error
            replaceLastMessageContent('⚠️ $content');
          }
        } catch (_) {}
        // Ensure UI exits streaming state
        finishStreaming();
      } else if ((type == 'chat:message:delta' || type == 'message') &&
          payload != null) {
        // Incremental message content over socket; respect suppression on SSE-driven flows
        if (!suppressSocketContent) {
          final content = payload['content']?.toString() ?? '';
          if (content.isNotEmpty) {
            appendToLastMessage(content);
            updateImagesFromCurrentContent();
          }
        }
      } else if ((type == 'chat:message' || type == 'replace') &&
          payload != null) {
        // Full message replacement over socket; respect suppression on SSE-driven flows
        if (!suppressSocketContent) {
          final content = payload['content']?.toString() ?? '';
          if (content.isNotEmpty) {
            replaceLastMessageContent(content);
          }
        }
      } else if ((type == 'chat:message:files') && payload != null) {
        // Alias for files event used by web client
        try {
          final files = _extractFilesFromResult(payload['files'] ?? payload);
          if (files.isNotEmpty) {
            final msgs = getMessages();
            if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
              final existing = msgs.last.files ?? <Map<String, dynamic>>[];
              final seen = <String>{
                for (final f in existing)
                  if (f['url'] is String) (f['url'] as String) else '',
              }..removeWhere((e) => e.isEmpty);
              final merged = <Map<String, dynamic>>[...existing];
              for (final f in files) {
                final url = f['url'] as String?;
                if (url != null && url.isNotEmpty && !seen.contains(url)) {
                  merged.add({'type': 'image', 'url': url});
                  seen.add(url);
                }
              }
              if (merged.length != existing.length) {
                updateLastMessageWith((m) => m.copyWith(files: merged));
              }
            }
          }
        } catch (_) {}
      } else if (type == 'request:chat:completion' && payload != null) {
        final channel = payload['channel'];
        if (channel is String && channel.isNotEmpty) {
          suppressSocketContent = true;
          channelLineHandlerFactory(channel);
        }
      } else if (type == 'execute:tool' && payload != null) {
        // Show an executing tile immediately; also surface any inline files/result
        try {
          final name = payload['name']?.toString() ?? 'tool';
          final status =
              '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
          appendToLastMessage(status);
          try {
            final filesA = _extractFilesFromResult(payload['files']);
            final filesB = _extractFilesFromResult(payload['result']);
            final all = [...filesA, ...filesB];
            if (all.isNotEmpty) {
              final msgs = getMessages();
              if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
                final existing = msgs.last.files ?? <Map<String, dynamic>>[];
                final seen = <String>{
                  for (final f in existing)
                    if (f['url'] is String) (f['url'] as String) else '',
                }..removeWhere((e) => e.isEmpty);
                final merged = <Map<String, dynamic>>[...existing];
                for (final f in all) {
                  final url = f['url'] as String?;
                  if (url != null && url.isNotEmpty && !seen.contains(url)) {
                    merged.add({'type': 'image', 'url': url});
                    seen.add(url);
                  }
                }
                if (merged.length != existing.length) {
                  updateLastMessageWith((m) => m.copyWith(files: merged));
                }
              }
            }
          } catch (_) {}
        } catch (_) {}
      } else if (type == 'files' && payload != null) {
        // Handle raw files event (image generation results)
        try {
          final files = _extractFilesFromResult(payload);
          if (files.isNotEmpty) {
            final msgs = getMessages();
            if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
              final existing = msgs.last.files ?? <Map<String, dynamic>>[];
              final seen = <String>{
                for (final f in existing)
                  if (f['url'] is String) (f['url'] as String) else '',
              }..removeWhere((e) => e.isEmpty);
              final merged = <Map<String, dynamic>>[...existing];
              for (final f in files) {
                final url = f['url'] as String?;
                if (url != null && url.isNotEmpty && !seen.contains(url)) {
                  merged.add({'type': 'image', 'url': url});
                  seen.add(url);
                }
              }
              if (merged.length != existing.length) {
                updateLastMessageWith((m) => m.copyWith(files: merged));
              }
            }
          }
        } catch (_) {}
      } else if (type == 'event:status' && payload != null) {
        final status = payload['status']?.toString() ?? '';
        if (status.isNotEmpty) {
          updateLastMessageWith(
            (m) => m.copyWith(metadata: {...?m.metadata, 'status': status}),
          );
        }
      } else if (type == 'event:tool' && payload != null) {
        // Accept files from both 'result' and 'files'
        final files = [
          ..._extractFilesFromResult(payload['files']),
          ..._extractFilesFromResult(payload['result']),
        ];
        if (files.isNotEmpty) {
          final msgs = getMessages();
          if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
            final existing = msgs.last.files ?? <Map<String, dynamic>>[];
            final merged = [...existing, ...files];
            updateLastMessageWith((m) => m.copyWith(files: merged));
          }
        }
      } else if (type == 'event:message:delta' && payload != null) {
        if (suppressSocketContent) return;
        final content = payload['content']?.toString() ?? '';
        if (content.isNotEmpty) {
          appendToLastMessage(content);
          updateImagesFromCurrentContent();
        }
      }
    } catch (_) {}
  }

  void channelEventsHandler(Map<String, dynamic> ev) {
    try {
      final data = ev['data'];
      if (data == null) return;
      final type = data['type'];
      final payload = data['data'];
      if (type == 'message' && payload is Map) {
        final content = payload['content']?.toString() ?? '';
        if (content.isNotEmpty) {
          appendToLastMessage(content);
          updateImagesFromCurrentContent();
        }
      }
    } catch (_) {}
  }

  if (socketService != null) {
    socketService.onChatEvents(chatHandler);
    socketService.onChannelEvents(channelEventsHandler);
    Future.delayed(const Duration(seconds: 90), () {
      try {
        socketService.offChatEvents();
        socketService.offChannelEvents();
      } catch (_) {}
      try {
        final msgs = getMessages();
        if (msgs.isNotEmpty &&
            msgs.last.role == 'assistant' &&
            msgs.last.isStreaming) {
          finishStreaming();
        }
      } catch (_) {}
    });
  }

  final subscription = persistentController.stream.listen(
    (chunk) {
      var effectiveChunk = chunk;
      if (webSearchEnabled && !isSearching) {
        if (chunk.contains('[SEARCHING]') ||
            chunk.contains('Searching the web') ||
            chunk.contains('web search')) {
          isSearching = true;
          updateLastMessageWith(
            (message) => message.copyWith(
              content: '🔍 Searching the web...',
              metadata: {'webSearchActive': true},
            ),
          );
          return; // Don't append this chunk
        }
      }

      if (isSearching &&
          (chunk.contains('[/SEARCHING]') ||
              chunk.contains('Search complete'))) {
        isSearching = false;
        updateLastMessageWith(
          (message) => message.copyWith(metadata: {'webSearchActive': false}),
        );
        effectiveChunk = effectiveChunk
            .replaceAll('[SEARCHING]', '')
            .replaceAll('[/SEARCHING]', '');
      }

      if (effectiveChunk.trim().isNotEmpty) {
        appendToLastMessage(effectiveChunk);
        updateImagesFromCurrentContent();
      }
    },
    onDone: () async {
      // Unregister from persistent service
      persistentService.unregisterStream(streamId);

      // Stop socket events now that streaming finished only for SSE-driven streams
      if (socketService != null && suppressSocketContent == true) {
        try {
          socketService.offChatEvents();
        } catch (_) {}
      }
      // Allow socket content again for future sessions
      suppressSocketContent = false;

      // If SSE-driven (no dynamic channel/background flow), finish now
      if (!usingDynamicChannel && !isBackgroundFlow) {
        finishStreaming();
      }
    },
    onError: (error) async {
      try {
        persistentService.unregisterStream(streamId);
      } catch (_) {}
      finishStreaming();
      if (socketService != null && suppressSocketContent == true) {
        try {
          socketService.offChatEvents();
        } catch (_) {}
      }
    },
  );

  return subscription;
}

List<Map<String, dynamic>> _extractFilesFromResult(dynamic resp) {
  final results = <Map<String, dynamic>>[];
  if (resp == null) return results;
  dynamic r = resp;
  if (r is String) {
    try {
      r = jsonDecode(r);
    } catch (_) {}
  }
  if (r is List) {
    for (final item in r) {
      if (item is String && item.isNotEmpty) {
        results.add({'type': 'image', 'url': item});
      } else if (item is Map) {
        final url = item['url'];
        final b64 = item['b64_json'] ?? item['b64'];
        if (url is String && url.isNotEmpty) {
          results.add({'type': 'image', 'url': url});
        } else if (b64 is String && b64.isNotEmpty) {
          results.add({'type': 'image', 'url': 'data:image/png;base64,$b64'});
        }
      }
    }
    return results;
  }
  if (r is! Map) return results;
  final data = r['data'];
  if (data is List) {
    for (final item in data) {
      if (item is Map) {
        final url = item['url'];
        final b64 = item['b64_json'] ?? item['b64'];
        if (url is String && url.isNotEmpty) {
          results.add({'type': 'image', 'url': url});
        } else if (b64 is String && b64.isNotEmpty) {
          results.add({'type': 'image', 'url': 'data:image/png;base64,$b64'});
        }
      } else if (item is String && item.isNotEmpty) {
        results.add({'type': 'image', 'url': item});
      }
    }
  }
  final images = r['images'];
  if (images is List) {
    for (final item in images) {
      if (item is String && item.isNotEmpty) {
        results.add({'type': 'image', 'url': item});
      } else if (item is Map) {
        final url = item['url'];
        final b64 = item['b64_json'] ?? item['b64'];
        if (url is String && url.isNotEmpty) {
          results.add({'type': 'image', 'url': url});
        } else if (b64 is String && b64.isNotEmpty) {
          results.add({'type': 'image', 'url': 'data:image/png;base64,$b64'});
        }
      }
    }
  }
  final files = r['files'];
  if (files is List) {
    results.addAll(_extractFilesFromResult(files));
  }
  final singleUrl = r['url'];
  if (singleUrl is String && singleUrl.isNotEmpty) {
    results.add({'type': 'image', 'url': singleUrl});
  }
  final singleB64 = r['b64_json'] ?? r['b64'];
  if (singleB64 is String && singleB64.isNotEmpty) {
    results.add({'type': 'image', 'url': 'data:image/png;base64,$singleB64'});
  }
  return results;
}
