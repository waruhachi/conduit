import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
// import 'package:http_parser/http_parser.dart';
// Removed legacy websocket/socket.io imports
import 'package:uuid/uuid.dart';
import '../models/server_config.dart';
import '../models/user.dart';
import '../models/model.dart';
import '../models/conversation.dart';
import '../models/chat_message.dart';
import '../auth/api_auth_interceptor.dart';
import '../error/api_error_interceptor.dart';
// Tool-call details are parsed in the UI layer to render collapsible blocks
import 'persistent_streaming_service.dart';
import '../utils/debug_logger.dart';

class ApiService {
  final Dio _dio;
  final ServerConfig serverConfig;
  late final ApiAuthInterceptor _authInterceptor;
  // Removed legacy websocket/socket.io fields

  // Public getter for dio instance
  Dio get dio => _dio;

  // Public getter for base URL
  String get baseUrl => serverConfig.url;

  // Callback to notify when auth token becomes invalid
  void Function()? onAuthTokenInvalid;

  // New callback for the unified auth state manager
  Future<void> Function()? onTokenInvalidated;

  ApiService({required this.serverConfig, String? authToken})
    : _dio = Dio(
        BaseOptions(
          baseUrl: serverConfig.url,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 400,
          // Add custom headers from server config
          headers: serverConfig.customHeaders.isNotEmpty
              ? Map<String, String>.from(serverConfig.customHeaders)
              : null,
        ),
      ) {
    // Use API key from server config if provided and no explicit auth token
    final effectiveAuthToken = authToken ?? serverConfig.apiKey;

    // Initialize the consistent auth interceptor
    _authInterceptor = ApiAuthInterceptor(
      authToken: effectiveAuthToken,
      onAuthTokenInvalid: onAuthTokenInvalid,
      onTokenInvalidated: onTokenInvalidated,
      customHeaders: serverConfig.customHeaders,
    );

    // Add interceptors in order of priority:
    // 1. Auth interceptor (must be first to add auth headers)
    _dio.interceptors.add(_authInterceptor);

    // 2. Validation interceptor removed (no schema loading/logging)

    // 3. Error handling interceptor (transforms errors to standardized format)
    _dio.interceptors.add(
      ApiErrorInterceptor(
        logErrors: kDebugMode,
        throwApiErrors: true, // Transform DioExceptions to include ApiError
      ),
    );

    // 4. Custom debug interceptor to log exactly what we're sending
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.next(options);
          },
        ),
      );

      // LogInterceptor removed - was exposing sensitive data and creating verbose logs
      // We now use custom interceptors with secure logging via DebugLogger
    }

    // Validation interceptor fully removed
  }

  void updateAuthToken(String token) {
    _authInterceptor.updateAuthToken(token);
  }

  String? get authToken => _authInterceptor.authToken;

  /// Ensure interceptor callbacks stay in sync if they are set after construction
  void setAuthCallbacks({
    void Function()? onAuthTokenInvalid,
    Future<void> Function()? onTokenInvalidated,
  }) {
    if (onAuthTokenInvalid != null) {
      this.onAuthTokenInvalid = onAuthTokenInvalid;
      _authInterceptor.onAuthTokenInvalid = onAuthTokenInvalid;
    }
    if (onTokenInvalidated != null) {
      this.onTokenInvalidated = onTokenInvalidated;
      _authInterceptor.onTokenInvalidated = onTokenInvalidated;
    }
  }

  // Health check
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Enhanced health check with model availability
  Future<Map<String, dynamic>> checkServerStatus() async {
    final result = <String, dynamic>{
      'healthy': false,
      'modelsAvailable': false,
      'modelCount': 0,
      'error': null,
    };

    try {
      // Check basic health
      final healthResponse = await _dio.get('/health');
      result['healthy'] = healthResponse.statusCode == 200;

      if (result['healthy']) {
        // Check model availability
        try {
          final modelsResponse = await _dio.get('/api/models');
          final models = modelsResponse.data['data'] as List?;
          result['modelsAvailable'] = models != null && models.isNotEmpty;
          result['modelCount'] = models?.length ?? 0;
        } catch (e) {
          result['modelsAvailable'] = false;
        }
      }
    } catch (e) {
      result['error'] = e.toString();
    }

    return result;
  }

  // Authentication
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _dio.post(
        '/api/v1/auths/signin',
        data: {'email': username, 'password': password},
      );

      return response.data;
    } catch (e) {
      if (e is DioException) {
        // Handle specific redirect cases
        if (e.response?.statusCode == 307 || e.response?.statusCode == 308) {
          final location = e.response?.headers.value('location');
          if (location != null) {
            throw Exception(
              'Server redirect detected. Please check your server URL configuration. Redirect to: $location',
            );
          }
        }
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    await _dio.get('/api/v1/auths/signout');
  }

  // User info
  Future<User> getCurrentUser() async {
    final response = await _dio.get('/api/v1/auths/');
    DebugLogger.log('User info retrieved successfully');
    return User.fromJson(response.data);
  }

  // Models
  Future<List<Model>> getModels() async {
    final response = await _dio.get('/api/models');

    // Handle different response formats
    List<dynamic> models;
    if (response.data is Map && response.data['data'] != null) {
      // Response is wrapped in a 'data' field
      models = response.data['data'] as List;
    } else if (response.data is List) {
      // Response is a direct array
      models = response.data as List;
    } else {
      DebugLogger.error('Unexpected models response format');
      return [];
    }

    DebugLogger.log('Found ${models.length} models');
    return models.map((m) => Model.fromJson(m)).toList();
  }

  // Get default model configuration from OpenWebUI user settings
  Future<String?> getDefaultModel() async {
    try {
      final response = await _dio.get('/api/v1/users/user/settings');

      DebugLogger.log('User settings retrieved successfully');

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        DebugLogger.warning(
          'User settings response is empty or unexpected type: ${data.runtimeType}',
        );
        return null;
      }

      // Extract default model from ui.models array
      final ui = data['ui'];
      if (ui is Map<String, dynamic>) {
        final models = ui['models'];
        if (models is List && models.isNotEmpty) {
          // Return the first model in the user's preferred models list
          final defaultModel = models.first.toString();
          DebugLogger.log(
            'Found default model from user settings: $defaultModel',
          );
          return defaultModel;
        }
      }

      DebugLogger.log('No default model found in user settings');
      return null;
    } catch (e) {
      DebugLogger.error('Error fetching default model from user settings', e);
      // Do not call admin-only configs endpoint here; let the caller
      // handle fallback (e.g., first available model from /api/models).
      return null;
    }
  }

  // Conversations - Updated to use correct OpenWebUI API
  Future<List<Conversation>> getConversations({int? limit, int? skip}) async {
    List<dynamic> allRegularChats = [];

    if (limit == null) {
      // Fetch all conversations using pagination

      // OpenWebUI expects 1-based pagination for the `page` query param.
      // Using 0 triggers server-side offset calculation like `offset = page*limit - limit`,
      // which becomes negative for page=0 and causes a DB error.
      int currentPage = 1;

      while (true) {
        final response = await _dio.get(
          '/api/v1/chats/',
          queryParameters: {'page': currentPage},
        );

        if (response.data is! List) {
          throw Exception(
            'Expected array of chats, got ${response.data.runtimeType}',
          );
        }

        final pageChats = response.data as List;

        if (pageChats.isEmpty) {
          break;
        }

        allRegularChats.addAll(pageChats);
        currentPage++;

        // Safety break to avoid infinite loops (adjust as needed)
        if (currentPage > 100) {
          debugPrint(
            'WARNING: Reached maximum page limit (100), stopping pagination',
          );
          break;
        }
      }

      debugPrint(
        'DEBUG: Fetched total of ${allRegularChats.length} conversations across $currentPage pages',
      );
    } else {
      // Original single page fetch
      final regularResponse = await _dio.get(
        '/api/v1/chats/',
        // Convert skip/limit to 1-based page index expected by OpenWebUI.
        // Example: skip=0 => page=1, skip=limit => page=2, etc.
        queryParameters: {
          if (limit > 0)
            'page': (((skip ?? 0) / limit).floor() + 1).clamp(1, 1 << 30),
        },
      );

      if (regularResponse.data is! List) {
        throw Exception(
          'Expected array of chats, got ${regularResponse.data.runtimeType}',
        );
      }

      allRegularChats = regularResponse.data as List;
    }

    final pinnedResponse = await _dio.get('/api/v1/chats/pinned');
    final archivedResponse = await _dio.get('/api/v1/chats/all/archived');

    debugPrint('DEBUG: Pinned response status: ${pinnedResponse.statusCode}');
    debugPrint(
      'DEBUG: Archived response status: ${archivedResponse.statusCode}',
    );

    if (pinnedResponse.data is! List) {
      throw Exception(
        'Expected array of pinned chats, got ${pinnedResponse.data.runtimeType}',
      );
    }

    if (archivedResponse.data is! List) {
      throw Exception(
        'Expected array of archived chats, got ${archivedResponse.data.runtimeType}',
      );
    }

    final regularChatList = allRegularChats;
    final pinnedChatList = pinnedResponse.data as List;
    final archivedChatList = archivedResponse.data as List;

    debugPrint('DEBUG: Found ${regularChatList.length} regular chats');
    debugPrint('DEBUG: Found ${pinnedChatList.length} pinned chats');
    debugPrint('DEBUG: Found ${archivedChatList.length} archived chats');

    // Convert OpenWebUI chat format to our Conversation format
    final conversations = <Conversation>[];
    final pinnedIds = <String>{};
    final archivedIds = <String>{};

    // Process pinned conversations first
    for (final chatData in pinnedChatList) {
      try {
        final conversation = _parseOpenWebUIChat(chatData);
        // Create a new conversation instance with pinned=true
        final pinnedConversation = conversation.copyWith(pinned: true);
        conversations.add(pinnedConversation);
        pinnedIds.add(conversation.id);
      } catch (e) {
        debugPrint('DEBUG: Error parsing pinned chat ${chatData['id']}: $e');
      }
    }

    // Process archived conversations
    for (final chatData in archivedChatList) {
      try {
        final conversation = _parseOpenWebUIChat(chatData);
        // Create a new conversation instance with archived=true
        final archivedConversation = conversation.copyWith(archived: true);
        conversations.add(archivedConversation);
        archivedIds.add(conversation.id);
      } catch (e) {
        debugPrint('DEBUG: Error parsing archived chat ${chatData['id']}: $e');
      }
    }

    // Process regular conversations (excluding pinned and archived ones)
    for (final chatData in regularChatList) {
      try {
        // Debug: Check if conversation has folder_id in raw data
        if (chatData.containsKey('folder_id') &&
            chatData['folder_id'] != null) {
          debugPrint(
            '🔍 DEBUG: Found conversation with folder_id in raw data: ${chatData['id']} -> ${chatData['folder_id']}',
          );
        }

        // Debug: Check what fields are available in the chat data
        if (regularChatList.indexOf(chatData) == 0) {
          debugPrint(
            '🔍 DEBUG: Sample chat data fields: ${chatData.keys.toList()}',
          );
          final _sampleStr = chatData.toString();
          final _preview = _sampleStr.length > 200
              ? _sampleStr.substring(0, 200)
              : _sampleStr;
          debugPrint('🔍 DEBUG: Sample chat data: $_preview...');
        }

        final conversation = _parseOpenWebUIChat(chatData);
        // Only add if not already added as pinned or archived
        if (!pinnedIds.contains(conversation.id) &&
            !archivedIds.contains(conversation.id)) {
          conversations.add(conversation);
        }
      } catch (e) {
        debugPrint('DEBUG: Error parsing chat ${chatData['id']}: $e');
        // Continue with other chats even if one fails
      }
    }

    debugPrint(
      'DEBUG: Successfully parsed ${conversations.length} conversations (${pinnedIds.length} pinned, ${archivedIds.length} archived)',
    );
    return conversations;
  }

  // Helper method to safely parse timestamps
  DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();

    if (timestamp is int) {
      // OpenWebUI uses Unix timestamps in seconds
      // Check if it's already in milliseconds (13 digits) or seconds (10 digits)
      final timestampMs = timestamp > 1000000000000
          ? timestamp
          : timestamp * 1000;
      return DateTime.fromMillisecondsSinceEpoch(timestampMs);
    }

    if (timestamp is String) {
      final parsed = int.tryParse(timestamp);
      if (parsed != null) {
        final timestampMs = parsed > 1000000000000 ? parsed : parsed * 1000;
        return DateTime.fromMillisecondsSinceEpoch(timestampMs);
      }
    }

    return DateTime.now(); // Fallback to current time
  }

  // Parse OpenWebUI chat format to our Conversation format
  Conversation _parseOpenWebUIChat(Map<String, dynamic> chatData) {
    // OpenWebUI ChatTitleIdResponse format:
    // {
    //   "id": "string",
    //   "title": "string",
    //   "updated_at": integer (timestamp),
    //   "created_at": integer (timestamp),
    //   "pinned": boolean (optional),
    //   "archived": boolean (optional),
    //   "share_id": string (optional),
    //   "folder_id": string (optional)
    // }

    final id = chatData['id'] as String;
    final title = chatData['title'] as String;

    // Safely parse timestamps with validation
    // Try both snake_case and camelCase field names
    final updatedAtRaw = chatData['updated_at'] ?? chatData['updatedAt'];
    final createdAtRaw = chatData['created_at'] ?? chatData['createdAt'];

    final updatedAt = _parseTimestamp(updatedAtRaw);
    final createdAt = _parseTimestamp(createdAtRaw);

    // Parse additional OpenWebUI fields
    // The API response might not include these fields, so we need to handle them safely
    final pinned = chatData['pinned'] as bool? ?? false;
    final archived = chatData['archived'] as bool? ?? false;
    final shareId = chatData['share_id'] as String?;
    final folderId = chatData['folder_id'] as String?;

    // Debug logging for folder assignment
    if (folderId != null) {
      final _idPreview = id.length > 8 ? id.substring(0, 8) : id;
      debugPrint('🔍 DEBUG: Conversation $_idPreview has folderId: $folderId');
    }

    debugPrint(
      'DEBUG: Parsed conversation $id: pinned=$pinned, archived=$archived',
    );

    // For the list endpoint, we don't get the full chat messages
    // We'll need to fetch individual chats later if needed
    return Conversation(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pinned: pinned,
      archived: archived,
      shareId: shareId,
      folderId: folderId,
      messages: [], // Empty for now, will be loaded when chat is opened
    );
  }

  Future<Conversation> getConversation(String id) async {
    DebugLogger.log('Fetching individual chat: $id');
    final response = await _dio.get('/api/v1/chats/$id');

    DebugLogger.log('Chat response received successfully');

    // Parse OpenWebUI ChatResponse format
    final chatData = response.data as Map<String, dynamic>;
    return _parseFullOpenWebUIChat(chatData);
  }

  // Parse full OpenWebUI chat with messages
  Conversation _parseFullOpenWebUIChat(Map<String, dynamic> chatData) {
    debugPrint('DEBUG: Parsing full OpenWebUI chat data');
    debugPrint('DEBUG: Chat data keys: ${chatData.keys.toList()}');

    final id = chatData['id'] as String;
    final title = chatData['title'] as String;

    debugPrint('DEBUG: Parsed chat ID: $id');
    debugPrint('DEBUG: Parsed chat title: $title');

    // Safely parse timestamps with validation
    final updatedAt = _parseTimestamp(chatData['updated_at']);
    final createdAt = _parseTimestamp(chatData['created_at']);

    // Parse additional OpenWebUI fields
    final pinned = chatData['pinned'] as bool? ?? false;
    final archived = chatData['archived'] as bool? ?? false;
    final shareId = chatData['share_id'] as String?;
    final folderId = chatData['folder_id'] as String?;

    // Parse messages from the 'chat' object or top-level messages
    final chatObject = chatData['chat'] as Map<String, dynamic>?;
    final messages = <ChatMessage>[];

    // Extract model from chat.models array
    String? model;
    if (chatObject != null && chatObject['models'] != null) {
      final models = chatObject['models'] as List?;
      if (models != null && models.isNotEmpty) {
        model = models.first as String;
        debugPrint('DEBUG: Extracted model from chat.models: $model');
      }
    }

    // Try multiple locations for messages - prefer history-based ordering like Open‑WebUI
    List? messagesList;
    Map<String, dynamic>? historyMessagesMap;

    if (chatObject != null) {
      // Prefer history.messages with currentId to reconstruct the selected branch
      final history = chatObject['history'] as Map<String, dynamic>?;
      if (history != null && history['messages'] is Map<String, dynamic>) {
        historyMessagesMap = history['messages'] as Map<String, dynamic>;

        // Reconstruct ordered list using parent chain up to currentId
        final currentId = history['currentId']?.toString();
        if (currentId != null && currentId.isNotEmpty) {
          messagesList = _buildMessagesListFromHistory(history);
          debugPrint(
            'DEBUG: Built ${messagesList.length} messages from history chain to currentId=$currentId',
          );
        }
      }

      // Fallback to chat.messages (list format) if history is missing or empty
      if (((messagesList?.isEmpty ?? true)) && chatObject['messages'] != null) {
        messagesList = chatObject['messages'] as List;
        debugPrint(
          'DEBUG: Found ${messagesList.length} messages in chat.messages (fallback)',
        );
      }
    } else if (chatData['messages'] != null) {
      messagesList = chatData['messages'] as List;
      debugPrint(
        'DEBUG: Found ${messagesList.length} messages in top-level messages',
      );
    }

    // Parse messages from list format only (avoiding duplication)
    if (messagesList != null) {
      for (int idx = 0; idx < messagesList.length; idx++) {
        final msgData = messagesList[idx] as Map<String, dynamic>;
        try {
          debugPrint(
            'DEBUG: Parsing message: ${msgData['id']} - role: ${msgData['role']} - content length: ${msgData['content']?.toString().length ?? 0}',
          );

          // If this assistant message includes tool_calls, merge following tool results
          final historyMsg = historyMessagesMap != null
              ? (historyMessagesMap[msgData['id']] as Map<String, dynamic>?)
              : null;

          final toolCalls = (msgData['tool_calls'] is List)
              ? (msgData['tool_calls'] as List)
              : (historyMsg != null && historyMsg['tool_calls'] is List)
              ? (historyMsg['tool_calls'] as List)
              : null;

          if ((msgData['role']?.toString() == 'assistant') &&
              toolCalls is List) {
            // Collect subsequent tool results associated with this assistant turn
            final List<Map<String, dynamic>> results = [];
            int j = idx + 1;
            while (j < messagesList.length) {
              final next = messagesList[j] as Map<String, dynamic>;
              if ((next['role']?.toString() ?? '') != 'tool') break;
              final toolCallId = next['tool_call_id']?.toString();
              final resContent = next['content'];
              final resFiles = next['files'];
              results.add({
                'tool_call_id': toolCallId,
                'content': resContent,
                if (resFiles != null) 'files': resFiles,
              });
              j++;
            }

            // Synthesize content from tool_calls and results
            final synthesized = _synthesizeToolDetailsFromToolCallsWithResults(
              toolCalls,
              results,
            );

            final mergedAssistant = Map<String, dynamic>.from(msgData);
            mergedAssistant['content'] = synthesized;

            final message = _parseOpenWebUIMessage(
              mergedAssistant,
              historyMsg: historyMsg,
            );
            messages.add(message);

            // Skip the tool messages we just merged
            idx = j - 1;
            debugPrint(
              'DEBUG: Successfully parsed tool_call assistant turn: ${message.id}',
            );
            continue;
          }

          // Default path: parse message as-is
          final message = _parseOpenWebUIMessage(
            msgData,
            historyMsg: historyMsg,
          );
          messages.add(message);
          debugPrint(
            'DEBUG: Successfully parsed message: ${message.id} - ${message.role}',
          );
        } catch (e) {
          debugPrint('DEBUG: Error parsing message: $e');
        }
      }
    }

    debugPrint('DEBUG: Total parsed messages: ${messages.length}');

    return Conversation(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      model: model,
      pinned: pinned,
      archived: archived,
      shareId: shareId,
      folderId: folderId,
      messages: messages,
    );
  }

  // Parse OpenWebUI message format to our ChatMessage format
  ChatMessage _parseOpenWebUIMessage(
    Map<String, dynamic> msgData, {
    Map<String, dynamic>? historyMsg,
  }) {
    // OpenWebUI message format may vary, but typically:
    // { "role": "user|assistant", "content": "text", ... }

    // Create a single UUID instance to reuse
    const uuid = Uuid();

    // Prefer richer content from history entry if present
    dynamic content = msgData['content'];
    if ((content == null || (content is String && content.isEmpty)) &&
        historyMsg != null &&
        historyMsg['content'] != null) {
      content = historyMsg['content'];
    }
    String contentString;
    if (content is List) {
      // Concatenate all text fragments in order (Open‑WebUI may split long text)
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map && item['type'] == 'text') {
          final t = item['text']?.toString();
          if (t != null && t.isNotEmpty) buffer.write(t);
        }
      }
      contentString = buffer.toString();
      if (contentString.trim().isEmpty) {
        // Fallback: look for tool-related entries in the array and synthesize details blocks
        final synthesized = _synthesizeToolDetailsFromContentArray(content);
        if (synthesized.isNotEmpty) {
          contentString = synthesized;
        }
      }
    } else {
      contentString = (content as String?) ?? '';
    }

    // Prefer longer content from history if available (guards against truncated previews)
    if (historyMsg != null) {
      final histContent = historyMsg['content'];
      if (histContent is String && histContent.length > contentString.length) {
        contentString = histContent;
      } else if (histContent is List) {
        final buf = StringBuffer();
        for (final item in histContent) {
          if (item is Map && item['type'] == 'text') {
            final t = item['text']?.toString();
            if (t != null && t.isNotEmpty) buf.write(t);
          }
        }
        final combined = buf.toString();
        if (combined.length > contentString.length) {
          contentString = combined;
        }
      }
    }

    // Final fallback: some servers store tool calls under tool_calls instead of content
    final toolCallsList = (msgData['tool_calls'] is List)
        ? (msgData['tool_calls'] as List)
        : (historyMsg != null && historyMsg['tool_calls'] is List)
        ? (historyMsg['tool_calls'] as List)
        : null;
    if (contentString.trim().isEmpty && toolCallsList is List) {
      final synthesized = _synthesizeToolDetailsFromToolCalls(toolCallsList);
      if (synthesized.isNotEmpty) {
        contentString = synthesized;
      }
    }

    // Determine role based on available fields
    String role;
    if (msgData['role'] != null) {
      role = msgData['role'] as String;
    } else if (msgData['model'] != null) {
      // Messages with model field are typically assistant messages
      role = 'assistant';
    } else {
      // Default to user if no role or model
      role = 'user';
    }

    // Parse attachments and generated images from 'files' field
    List<String>? attachmentIds;
    List<Map<String, dynamic>>? files;

    final effectiveFiles = msgData['files'] ?? historyMsg?['files'];
    if (effectiveFiles != null) {
      final filesList = effectiveFiles as List;

      // Separate user uploads (with file_id) from generated images (with type and url)
      final userAttachments = <String>[];
      final generatedFiles = <Map<String, dynamic>>[];

      for (final file in filesList) {
        if (file is Map) {
          if (file['file_id'] != null) {
            // User uploaded file
            userAttachments.add(file['file_id'] as String);
          } else if (file['type'] == 'image' && file['url'] != null) {
            // Generated image
            generatedFiles.add({'type': file['type'], 'url': file['url']});
          }
        }
      }

      attachmentIds = userAttachments.isNotEmpty ? userAttachments : null;
      files = generatedFiles.isNotEmpty ? generatedFiles : null;
    }

    return ChatMessage(
      id: msgData['id']?.toString() ?? uuid.v4(),
      role: role,
      content: contentString,
      timestamp: _parseTimestamp(msgData['timestamp']),
      model: msgData['model'] as String?,
      attachmentIds: attachmentIds,
      files: files,
    );
  }

  // Build ordered messages list from Open‑WebUI history using parent chain to currentId
  List<Map<String, dynamic>> _buildMessagesListFromHistory(
    Map<String, dynamic> history,
  ) {
    final messagesMap = history['messages'] as Map<String, dynamic>?;
    final currentId = history['currentId']?.toString();

    if (messagesMap == null || currentId == null) return [];

    List<Map<String, dynamic>> buildChain(String? id) {
      if (id == null) return [];
      final raw = messagesMap[id];
      if (raw == null) return [];
      final msg = Map<String, dynamic>.from(raw as Map<String, dynamic>);
      msg['id'] = id; // ensure id present
      final parentId = msg['parentId']?.toString();
      if (parentId != null && parentId.isNotEmpty) {
        return [...buildChain(parentId), msg];
      }
      return [msg];
    }

    return buildChain(currentId);
  }

  // ===== Helpers to synthesize tool-call details blocks for UI parsing =====
  String _escapeHtmlAttr(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _jsonStringify(dynamic v) {
    try {
      return jsonEncode(v);
    } catch (_) {
      return v?.toString() ?? '';
    }
  }

  String _synthesizeToolDetailsFromToolCalls(List toolCalls) {
    final buf = StringBuffer();
    for (final c in toolCalls) {
      if (c is! Map) continue;
      final func = c['function'] as Map?;
      final name =
          (func != null ? func['name'] : c['name'])?.toString() ?? 'tool';
      final id =
          (c['id']?.toString() ??
          'call_${DateTime.now().millisecondsSinceEpoch}');
      final done = (c['done']?.toString() ?? 'true');
      final argsRaw = func != null ? func['arguments'] : c['arguments'];
      final resRaw =
          c['result'] ?? c['output'] ?? (func != null ? func['result'] : null);
      final argsStr = _jsonStringify(argsRaw);
      final resStr = resRaw != null ? _jsonStringify(resRaw) : null;
      final attrs = StringBuffer()
        ..write('type="tool_calls"')
        ..write(' done="${_escapeHtmlAttr(done)}"')
        ..write(' id="${_escapeHtmlAttr(id)}"')
        ..write(' name="${_escapeHtmlAttr(name)}"')
        ..write(' arguments="${_escapeHtmlAttr(argsStr)}"');
      if (resStr != null && resStr.isNotEmpty) {
        attrs.write(' result="${_escapeHtmlAttr(resStr)}"');
      }
      buf.writeln(
        '<details ${attrs.toString()}><summary>Tool Executed</summary>',
      );
      buf.writeln('</details>');
    }
    return buf.toString().trim();
  }

  String _synthesizeToolDetailsFromToolCallsWithResults(
    List toolCalls,
    List<Map<String, dynamic>> results,
  ) {
    final buf = StringBuffer();
    Map<String, Map<String, dynamic>> resultsMap = {};
    for (final r in results) {
      final id = r['tool_call_id']?.toString();
      if (id != null) resultsMap[id] = r;
    }

    for (final c in toolCalls) {
      if (c is! Map) continue;
      final func = c['function'] as Map?;
      final name =
          (func != null ? func['name'] : c['name'])?.toString() ?? 'tool';
      final id =
          (c['id']?.toString() ??
          'call_${DateTime.now().millisecondsSinceEpoch}');
      final argsRaw = func != null ? func['arguments'] : c['arguments'];
      final argsStr = _jsonStringify(argsRaw);
      final resultEntry = resultsMap[id];
      final resRaw = resultEntry != null ? resultEntry['content'] : null;
      final filesRaw = resultEntry != null ? resultEntry['files'] : null;
      final resStr = resRaw != null ? _jsonStringify(resRaw) : null;
      final filesStr = filesRaw != null ? _jsonStringify(filesRaw) : null;

      final attrs = StringBuffer()
        ..write('type="tool_calls"')
        ..write(
          ' done="${_escapeHtmlAttr(resultEntry != null ? 'true' : 'false')}"',
        )
        ..write(' id="${_escapeHtmlAttr(id)}"')
        ..write(' name="${_escapeHtmlAttr(name)}"')
        ..write(' arguments="${_escapeHtmlAttr(argsStr)}"');
      if (resStr != null && resStr.isNotEmpty) {
        attrs.write(' result="${_escapeHtmlAttr(resStr)}"');
      }
      if (filesStr != null && filesStr.isNotEmpty) {
        attrs.write(' files="${_escapeHtmlAttr(filesStr)}"');
      }

      buf.writeln(
        '<details ${attrs.toString()}><summary>${resultEntry != null ? 'Tool Executed' : 'Executing...'}</summary>',
      );
      buf.writeln('</details>');
    }
    return buf.toString().trim();
  }

  String _synthesizeToolDetailsFromContentArray(List content) {
    final buf = StringBuffer();
    for (final item in content) {
      if (item is! Map) continue;
      final type = item['type']?.toString();
      if (type == null) continue;
      // OpenWebUI content-blocks shape: { type: 'tool_calls', content: [...], results: [...] }
      if (type == 'tool_calls') {
        final calls = (item['content'] is List)
            ? (item['content'] as List)
            : <dynamic>[];
        final results = <Map<String, dynamic>>[];
        if (item['results'] is List) {
          for (final r in (item['results'] as List)) {
            if (r is Map<String, dynamic>) results.add(r);
          }
        }
        final synthesized = _synthesizeToolDetailsFromToolCallsWithResults(
          calls,
          results,
        );
        if (synthesized.isNotEmpty) buf.writeln(synthesized);
        continue;
      }

      // Heuristics: handle other variants (single tool/function call entries)
      if (type == 'tool_call' || type == 'function_call') {
        final name = (item['name'] ?? item['tool'] ?? 'tool').toString();
        final id =
            (item['id']?.toString() ??
            'call_${DateTime.now().millisecondsSinceEpoch}');
        final argsStr = _jsonStringify(item['arguments'] ?? item['args']);
        final resStr = item['result'] ?? item['output'] ?? item['response'];
        final attrs = StringBuffer()
          ..write('type="tool_calls"')
          ..write(
            ' done="${_escapeHtmlAttr(resStr != null ? 'true' : 'false')}"',
          )
          ..write(' id="${_escapeHtmlAttr(id)}"')
          ..write(' name="${_escapeHtmlAttr(name)}"')
          ..write(' arguments="${_escapeHtmlAttr(argsStr)}"');
        if (resStr != null) {
          final r = _jsonStringify(resStr);
          if (r.isNotEmpty) attrs.write(' result="${_escapeHtmlAttr(r)}"');
        }
        buf.writeln(
          '<details ${attrs.toString()}><summary>${resStr != null ? 'Tool Executed' : 'Executing...'}</summary>',
        );
        buf.writeln('</details>');
      }
    }
    return buf.toString().trim();
  }

  // Create new conversation using OpenWebUI API
  Future<Conversation> createConversation({
    required String title,
    required List<ChatMessage> messages,
    String? model,
    String? systemPrompt,
  }) async {
    debugPrint('DEBUG: Creating new conversation on OpenWebUI server');
    debugPrint('DEBUG: Title: $title, Messages: ${messages.length}');

    // Build messages with parent-child relationships
    final Map<String, dynamic> messagesMap = {};
    final List<Map<String, dynamic>> messagesArray = [];
    String? currentId;
    String? previousId;

    for (final msg in messages) {
      final messageId = msg.id;

      // Build message for history.messages map
      messagesMap[messageId] = {
        'id': messageId,
        'parentId': previousId,
        'childrenIds': [],
        'role': msg.role,
        'content': msg.content,
        'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
        if (msg.role == 'user' && model != null) 'models': [model],
      };

      // Update parent's childrenIds if there's a previous message
      if (previousId != null && messagesMap.containsKey(previousId)) {
        (messagesMap[previousId]['childrenIds'] as List).add(messageId);
      }

      // Build message for messages array
      messagesArray.add({
        'id': messageId,
        'parentId': previousId,
        'childrenIds': [],
        'role': msg.role,
        'content': msg.content,
        'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
        if (msg.role == 'user' && model != null) 'models': [model],
      });

      previousId = messageId;
      currentId = messageId;
    }

    // Create the chat data structure matching OpenWebUI format exactly
    final chatData = {
      'chat': {
        'id': '',
        'title': title,
        'models': model != null ? [model] : [],
        'params': {},
        'history': {
          'messages': messagesMap,
          if (currentId != null) 'currentId': currentId,
        },
        'messages': messagesArray,
        'tags': [],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      'folder_id': null,
    };

    debugPrint('DEBUG: Sending chat data with proper parent-child structure');
    debugPrint('DEBUG: Request data: $chatData');

    final response = await _dio.post('/api/v1/chats/new', data: chatData);

    DebugLogger.log(
      'Create conversation response status: ${response.statusCode}',
    );
    DebugLogger.log('Create conversation response received successfully');

    // Parse the response
    final responseData = response.data as Map<String, dynamic>;
    return _parseFullOpenWebUIChat(responseData);
  }

  // Update conversation with full chat data including all messages
  Future<void> updateConversationWithMessages(
    String conversationId,
    List<ChatMessage> messages, {
    String? title,
    String? model,
    String? systemPrompt,
  }) async {
    debugPrint(
      'DEBUG: Updating conversation $conversationId with ${messages.length} messages',
    );

    // Build messages map and array in OpenWebUI format
    final Map<String, dynamic> messagesMap = {};
    final List<Map<String, dynamic>> messagesArray = [];
    String? currentId;
    String? previousId;

    for (final msg in messages) {
      final messageId = msg.id;

      // Build message for messages map (history.messages)
      final List<Map<String, dynamic>> combinedFilesMap = [];
      if (msg.attachmentIds != null && msg.attachmentIds!.isNotEmpty) {
        for (final id in msg.attachmentIds!) {
          if (id.startsWith('data:') || id.startsWith('http')) {
            combinedFilesMap.add({'type': 'image', 'url': id});
          } else {
            combinedFilesMap.add({'file_id': id});
          }
        }
      }
      if (msg.files != null && msg.files!.isNotEmpty) {
        combinedFilesMap.addAll(msg.files!);
      }

      messagesMap[messageId] = {
        'id': messageId,
        'parentId': previousId,
        'childrenIds': <String>[],
        'role': msg.role,
        'content': msg.content,
        'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
        if (msg.role == 'assistant' && msg.model != null) 'model': msg.model,
        if (msg.role == 'assistant' && msg.model != null)
          'modelName': msg.model,
        if (msg.role == 'assistant') 'modelIdx': 0,
        if (msg.role == 'assistant') 'done': !msg.isStreaming,
        if (msg.role == 'user' && model != null) 'models': [model],
        if (combinedFilesMap.isNotEmpty) 'files': combinedFilesMap,
      };

      // Update parent's childrenIds
      if (previousId != null && messagesMap.containsKey(previousId)) {
        (messagesMap[previousId]['childrenIds'] as List).add(messageId);
      }

      // Build message for messages array
      final List<Map<String, dynamic>> combinedFilesArray = [];
      if (msg.attachmentIds != null && msg.attachmentIds!.isNotEmpty) {
        for (final id in msg.attachmentIds!) {
          if (id.startsWith('data:') || id.startsWith('http')) {
            combinedFilesArray.add({'type': 'image', 'url': id});
          } else {
            combinedFilesArray.add({'file_id': id});
          }
        }
      }
      if (msg.files != null && msg.files!.isNotEmpty) {
        combinedFilesArray.addAll(msg.files!);
      }

      messagesArray.add({
        'id': messageId,
        'parentId': previousId,
        'childrenIds': [],
        'role': msg.role,
        'content': msg.content,
        'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
        if (msg.role == 'assistant' && msg.model != null) 'model': msg.model,
        if (msg.role == 'assistant' && msg.model != null)
          'modelName': msg.model,
        if (msg.role == 'assistant') 'modelIdx': 0,
        if (msg.role == 'assistant') 'done': !msg.isStreaming,
        if (msg.role == 'user' && model != null) 'models': [model],
        if (combinedFilesArray.isNotEmpty) 'files': combinedFilesArray,
      });

      previousId = messageId;
      currentId = messageId;
    }

    // Create the chat data structure matching OpenWebUI format exactly
    final chatData = {
      'chat': {
        if (title != null) 'title': title, // Include the title if provided
        'models': model != null ? [model] : [],
        'messages': messagesArray,
        'history': {
          'messages': messagesMap,
          if (currentId != null) 'currentId': currentId,
        },
        'params': {},
        'files': [],
      },
    };

    debugPrint('DEBUG: Updating chat with OpenWebUI format data using POST');

    // OpenWebUI uses POST not PUT for updating chats
    await _dio.post('/api/v1/chats/$conversationId', data: chatData);

    DebugLogger.log('Update conversation response received successfully');
  }

  Future<void> updateConversation(
    String id, {
    String? title,
    String? systemPrompt,
  }) async {
    // OpenWebUI expects POST to /api/v1/chats/{id} with ChatForm { chat: {...} }
    final chatPayload = <String, dynamic>{
      if (title != null) 'title': title,
      if (systemPrompt != null) 'system': systemPrompt,
    };
    await _dio.post('/api/v1/chats/$id', data: {'chat': chatPayload});
  }

  Future<void> deleteConversation(String id) async {
    await _dio.delete('/api/v1/chats/$id');
  }

  // Pin/Unpin conversation
  Future<void> pinConversation(String id, bool pinned) async {
    debugPrint('DEBUG: ${pinned ? 'Pinning' : 'Unpinning'} conversation: $id');
    await _dio.post('/api/v1/chats/$id/pin', data: {'pinned': pinned});
  }

  // Archive/Unarchive conversation
  Future<void> archiveConversation(String id, bool archived) async {
    debugPrint(
      'DEBUG: ${archived ? 'Archiving' : 'Unarchiving'} conversation: $id',
    );
    await _dio.post('/api/v1/chats/$id/archive', data: {'archived': archived});
  }

  // Share conversation
  Future<String?> shareConversation(String id) async {
    debugPrint('DEBUG: Sharing conversation: $id');
    final response = await _dio.post('/api/v1/chats/$id/share');
    final data = response.data as Map<String, dynamic>;
    return data['share_id'] as String?;
  }

  // Clone conversation
  Future<Conversation> cloneConversation(String id) async {
    debugPrint('DEBUG: Cloning conversation: $id');
    final response = await _dio.post('/api/v1/chats/$id/clone');
    return _parseFullOpenWebUIChat(response.data as Map<String, dynamic>);
  }

  // User Settings
  Future<Map<String, dynamic>> getUserSettings() async {
    debugPrint('DEBUG: Fetching user settings');
    final response = await _dio.get('/api/v1/users/user/settings');
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateUserSettings(Map<String, dynamic> settings) async {
    debugPrint('DEBUG: Updating user settings');
    // Align with web client update route
    await _dio.post('/api/v1/users/user/settings/update', data: settings);
  }

  // Suggestions
  Future<List<String>> getSuggestions() async {
    debugPrint('DEBUG: Fetching conversation suggestions');
    final response = await _dio.get('/api/v1/configs/suggestions');
    final data = response.data;
    if (data is List) {
      return data.cast<String>();
    }
    return [];
  }

  // Tools - Check available tools on server
  Future<List<Map<String, dynamic>>> getAvailableTools() async {
    debugPrint('DEBUG: Fetching available tools');
    try {
      final response = await _dio.get('/api/v1/tools/');
      final data = response.data;
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('DEBUG: Error fetching tools: $e');
    }
    return [];
  }

  // Folders
  Future<List<Map<String, dynamic>>> getFolders() async {
    try {
      debugPrint('DEBUG: Fetching folders from /api/v1/folders/');
      final response = await _dio.get('/api/v1/folders/');
      DebugLogger.log('Folders response status: ${response.statusCode}');
      DebugLogger.log('Folders response received successfully');

      final data = response.data;
      if (data is List) {
        debugPrint('DEBUG: Found ${data.length} folders');
        return data.cast<Map<String, dynamic>>();
      } else {
        DebugLogger.log('Response data is not a list: ${data.runtimeType}');
        return [];
      }
    } catch (e) {
      debugPrint('DEBUG: Error in getFolders: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createFolder({
    required String name,
    String? parentId,
  }) async {
    debugPrint('DEBUG: Creating folder: $name');
    final response = await _dio.post(
      '/api/v1/folders/',
      data: {'name': name, if (parentId != null) 'parent_id': parentId},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateFolder(String id, {String? name, String? parentId}) async {
    debugPrint('DEBUG: Updating folder: $id');
    // OpenWebUI folder update endpoints:
    // - POST /api/v1/folders/{id}/update          -> rename (FolderForm)
    // - POST /api/v1/folders/{id}/update/parent   -> move parent (FolderParentIdForm)
    if (name != null) {
      await _dio.post('/api/v1/folders/$id/update', data: {'name': name});
    }

    if (parentId != null) {
      await _dio.post(
        '/api/v1/folders/$id/update/parent',
        data: {'parent_id': parentId},
      );
    }
  }

  Future<void> deleteFolder(String id) async {
    debugPrint('DEBUG: Deleting folder: $id');
    await _dio.delete('/api/v1/folders/$id');
  }

  Future<void> moveConversationToFolder(
    String conversationId,
    String? folderId,
  ) async {
    debugPrint(
      'DEBUG: Moving conversation $conversationId to folder $folderId',
    );
    await _dio.post(
      '/api/v1/chats/$conversationId/folder',
      data: {'folder_id': folderId},
    );
  }

  Future<List<Conversation>> getConversationsInFolder(String folderId) async {
    debugPrint('DEBUG: Fetching conversations in folder: $folderId');
    final response = await _dio.get('/api/v1/chats/folder/$folderId');
    final data = response.data;
    if (data is List) {
      return data.map((chatData) => _parseOpenWebUIChat(chatData)).toList();
    }
    return [];
  }

  // Tags
  Future<List<String>> getConversationTags(String conversationId) async {
    debugPrint('DEBUG: Fetching tags for conversation: $conversationId');
    final response = await _dio.get('/api/v1/chats/$conversationId/tags');
    final data = response.data;
    if (data is List) {
      return data.cast<String>();
    }
    return [];
  }

  Future<void> addTagToConversation(String conversationId, String tag) async {
    debugPrint('DEBUG: Adding tag "$tag" to conversation: $conversationId');
    await _dio.post('/api/v1/chats/$conversationId/tags', data: {'tag': tag});
  }

  Future<void> removeTagFromConversation(
    String conversationId,
    String tag,
  ) async {
    debugPrint('DEBUG: Removing tag "$tag" from conversation: $conversationId');
    await _dio.delete('/api/v1/chats/$conversationId/tags/$tag');
  }

  Future<List<String>> getAllTags() async {
    debugPrint('DEBUG: Fetching all available tags');
    final response = await _dio.get('/api/v1/chats/tags');
    final data = response.data;
    if (data is List) {
      return data.cast<String>();
    }
    return [];
  }

  Future<List<Conversation>> getConversationsByTag(String tag) async {
    debugPrint('DEBUG: Fetching conversations with tag: $tag');
    final response = await _dio.get('/api/v1/chats/tags/$tag');
    final data = response.data;
    if (data is List) {
      return data.map((chatData) => _parseOpenWebUIChat(chatData)).toList();
    }
    return [];
  }

  // Files
  Future<String> getFileContent(String fileId) async {
    debugPrint('DEBUG: Fetching file content: $fileId');
    // The Open-WebUI endpoint returns the raw file bytes with appropriate
    // Content-Type headers, not JSON. We must read bytes and base64-encode
    // them for consistent handling across platforms/widgets.
    final response = await _dio.get(
      '/api/v1/files/$fileId/content',
      options: Options(responseType: ResponseType.bytes),
    );

    // Try to determine the mime type from response headers; fallback to text/plain
    final contentType =
        response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    String mimeType = 'text/plain';
    if (contentType.isNotEmpty) {
      // Strip charset if present
      mimeType = contentType.split(';').first.trim();
    }

    final bytes = response.data is List<int>
        ? (response.data as List<int>)
        : (response.data as Uint8List).toList();

    final base64Data = base64Encode(bytes);

    // For images, return a data URL so UI can render directly; otherwise return raw base64
    if (mimeType.startsWith('image/')) {
      return 'data:$mimeType;base64,$base64Data';
    }

    return base64Data;
  }

  Future<Map<String, dynamic>> getFileInfo(String fileId) async {
    debugPrint('DEBUG: Fetching file info: $fileId');
    final response = await _dio.get('/api/v1/files/$fileId');
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getUserFiles() async {
    debugPrint('DEBUG: Fetching user files');
    final response = await _dio.get('/api/v1/files/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // Enhanced File Operations
  Future<List<Map<String, dynamic>>> searchFiles({
    String? query,
    String? contentType,
    int? limit,
    int? offset,
  }) async {
    debugPrint('DEBUG: Searching files with query: $query');
    final queryParams = <String, dynamic>{};
    if (query != null) queryParams['q'] = query;
    if (contentType != null) queryParams['content_type'] = contentType;
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;

    final response = await _dio.get(
      '/api/v1/files/search',
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getAllFiles() async {
    debugPrint('DEBUG: Fetching all files (admin)');
    final response = await _dio.get('/api/v1/files/all');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<String> uploadFileWithProgress(
    String filePath,
    String fileName, {
    Function(int sent, int total)? onProgress,
  }) async {
    debugPrint('DEBUG: Uploading file with progress: $fileName');

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final response = await _dio.post(
      '/api/v1/files/',
      data: formData,
      onSendProgress: onProgress,
    );

    return response.data['id'] as String;
  }

  Future<Map<String, dynamic>> updateFileContent(
    String fileId,
    String content,
  ) async {
    debugPrint('DEBUG: Updating file content: $fileId');
    final response = await _dio.post(
      '/api/v1/files/$fileId/data/content/update',
      data: {'content': content},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<String> getFileHtmlContent(String fileId) async {
    debugPrint('DEBUG: Fetching file HTML content: $fileId');
    final response = await _dio.get('/api/v1/files/$fileId/content/html');
    return response.data as String;
  }

  Future<void> deleteFile(String fileId) async {
    debugPrint('DEBUG: Deleting file: $fileId');
    await _dio.delete('/api/v1/files/$fileId');
  }

  Future<Map<String, dynamic>> updateFileMetadata(
    String fileId, {
    String? filename,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('DEBUG: Updating file metadata: $fileId');
    final response = await _dio.put(
      '/api/v1/files/$fileId/metadata',
      data: {
        if (filename != null) 'filename': filename,
        if (metadata != null) 'metadata': metadata,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> processFilesBatch(
    List<String> fileIds, {
    String? operation,
    Map<String, dynamic>? options,
  }) async {
    debugPrint('DEBUG: Processing files batch: ${fileIds.length} files');
    final response = await _dio.post(
      '/api/v1/retrieval/process/files/batch',
      data: {
        'file_ids': fileIds,
        if (operation != null) 'operation': operation,
        if (options != null) 'options': options,
      },
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getFilesByType(String contentType) async {
    debugPrint('DEBUG: Fetching files by type: $contentType');
    final response = await _dio.get(
      '/api/v1/files/',
      queryParameters: {'content_type': contentType},
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> getFileStats() async {
    debugPrint('DEBUG: Fetching file statistics');
    final response = await _dio.get('/api/v1/files/stats');
    return response.data as Map<String, dynamic>;
  }

  // Knowledge Base
  Future<List<Map<String, dynamic>>> getKnowledgeBases() async {
    debugPrint('DEBUG: Fetching knowledge bases');
    final response = await _dio.get('/api/v1/knowledge/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> createKnowledgeBase({
    required String name,
    String? description,
  }) async {
    debugPrint('DEBUG: Creating knowledge base: $name');
    final response = await _dio.post(
      '/api/v1/knowledge/',
      data: {'name': name, if (description != null) 'description': description},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateKnowledgeBase(
    String id, {
    String? name,
    String? description,
  }) async {
    debugPrint('DEBUG: Updating knowledge base: $id');
    await _dio.put(
      '/api/v1/knowledge/$id',
      data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      },
    );
  }

  Future<void> deleteKnowledgeBase(String id) async {
    debugPrint('DEBUG: Deleting knowledge base: $id');
    await _dio.delete('/api/v1/knowledge/$id');
  }

  Future<List<Map<String, dynamic>>> getKnowledgeBaseItems(
    String knowledgeBaseId,
  ) async {
    debugPrint('DEBUG: Fetching knowledge base items: $knowledgeBaseId');
    final response = await _dio.get('/api/v1/knowledge/$knowledgeBaseId/items');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> addKnowledgeBaseItem(
    String knowledgeBaseId, {
    required String content,
    String? title,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('DEBUG: Adding item to knowledge base: $knowledgeBaseId');
    final response = await _dio.post(
      '/api/v1/knowledge/$knowledgeBaseId/items',
      data: {
        'content': content,
        if (title != null) 'title': title,
        if (metadata != null) 'metadata': metadata,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> searchKnowledgeBase(
    String knowledgeBaseId,
    String query,
  ) async {
    debugPrint('DEBUG: Searching knowledge base: $knowledgeBaseId for: $query');
    final response = await _dio.post(
      '/api/v1/knowledge/$knowledgeBaseId/search',
      data: {'query': query},
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // Web Search
  Future<Map<String, dynamic>> performWebSearch(List<String> queries) async {
    debugPrint('DEBUG: Performing web search for queries: $queries');
    try {
      final response = await _dio.post(
        '/api/v1/retrieval/process/web/search',
        data: {'queries': queries},
      );

      DebugLogger.log('Web search response status: ${response.statusCode}');
      DebugLogger.log('Web search response type: ${response.data.runtimeType}');
      DebugLogger.log('Web search response received successfully');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DEBUG: Web search API error: $e');
      if (e is DioException) {
        DebugLogger.error(
          'Web search error response available (truncated for security)',
        );
        debugPrint('DEBUG: Web search error status: ${e.response?.statusCode}');
      }
      rethrow;
    }
  }

  // Get detailed model information
  Future<Map<String, dynamic>?> getModelDetails(String modelId) async {
    try {
      final response = await _dio.get(
        '/api/v1/models/model',
        queryParameters: {'id': modelId},
      );

      if (response.statusCode == 200 && response.data != null) {
        final modelData = response.data as Map<String, dynamic>;
        DebugLogger.log('Model details for $modelId retrieved successfully');
        return modelData;
      }
    } catch (e) {
      debugPrint('DEBUG: Failed to get model details for $modelId: $e');
    }
    return null;
  }

  // Generate title for conversation using dedicated endpoint
  Future<String?> generateTitle({
    required String conversationId,
    required List<Map<String, dynamic>> messages,
    required String model,
  }) async {
    try {
      debugPrint('DEBUG: Generating title for conversation: $conversationId');

      final response = await _dio.post(
        '/api/v1/tasks/title/completions',
        data: {'chat_id': conversationId, 'messages': messages, 'model': model},
      );

      if (response.statusCode == 200 && response.data != null) {
        DebugLogger.log('Raw title response received successfully');

        // Parse the complex response structure
        String? extractedTitle;

        try {
          final responseData = response.data as Map<String, dynamic>;

          // Check if there's a direct title field
          if (responseData.containsKey('title')) {
            extractedTitle = responseData['title']?.toString();
          }
          // Check if it's in choices format (OpenAI-style response)
          else if (responseData.containsKey('choices') &&
              responseData['choices'] is List) {
            final choices = responseData['choices'] as List;
            if (choices.isNotEmpty) {
              final firstChoice = choices[0] as Map<String, dynamic>;
              if (firstChoice.containsKey('message')) {
                final message = firstChoice['message'] as Map<String, dynamic>;
                final content = message['content']?.toString() ?? '';

                // Extract title from JSON-formatted content
                if (content.contains('```json') && content.contains('```')) {
                  // Extract JSON from markdown code block
                  final jsonStart = content.indexOf('```json') + 7;
                  final jsonEnd = content.lastIndexOf('```');
                  if (jsonEnd > jsonStart) {
                    final jsonString = content
                        .substring(jsonStart, jsonEnd)
                        .trim();
                    try {
                      final jsonData =
                          jsonDecode(jsonString) as Map<String, dynamic>;
                      extractedTitle = jsonData['title']?.toString();
                    } catch (e) {
                      debugPrint(
                        'DEBUG: Failed to parse JSON from title response: $e',
                      );
                    }
                  }
                } else {
                  // Try to parse the content directly as JSON
                  try {
                    final jsonData =
                        jsonDecode(content) as Map<String, dynamic>;
                    extractedTitle = jsonData['title']?.toString();
                  } catch (e) {
                    // If not JSON, use content as-is
                    extractedTitle = content;
                  }
                }
              }
            }
          }

          // Clean up the extracted title
          if (extractedTitle != null && extractedTitle.isNotEmpty) {
            // Remove any remaining markdown formatting
            extractedTitle = extractedTitle
                .replaceAll(RegExp(r'```.*?```', dotAll: true), '')
                .trim();
            extractedTitle = extractedTitle
                .replaceAll(RegExp(r'^[{"]|["}]$'), '')
                .trim();

            // Ensure it's not just "New Chat" or empty
            if (extractedTitle.isNotEmpty && extractedTitle != 'New Chat') {
              debugPrint(
                'DEBUG: Successfully extracted title: $extractedTitle',
              );
              return extractedTitle;
            }
          }
        } catch (e) {
          debugPrint('DEBUG: Error parsing title response: $e');
        }

        debugPrint('DEBUG: Could not extract valid title from response');
      }
    } catch (e) {
      debugPrint('DEBUG: Failed to generate title: $e');
    }
    return null;
  }

  // Send chat completed notification
  Future<void> sendChatCompleted({
    required String chatId,
    required String messageId,
    required List<Map<String, dynamic>> messages,
    required String model,
    Map<String, dynamic>? modelItem,
    String? sessionId,
  }) async {
    debugPrint(
      'DEBUG: Sending chat completed notification (optional endpoint)',
    );

    // This endpoint appears to be optional or deprecated in newer OpenWebUI versions
    // The main chat synchronization happens through /api/v1/chats/{id} updates
    // We'll still try to call it but won't fail if it doesn't work

    // Format messages to match OpenWebUI expected structure
    // Note: Removing 'id' field as it causes 400 error
    final formattedMessages = messages.map((msg) {
      final formatted = {
        // Don't include 'id' - it causes 400 error with detail: 'id'
        'role': msg['role'],
        'content': msg['content'],
        'timestamp':
            msg['timestamp'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };

      // Add model info for assistant messages
      if (msg['role'] == 'assistant') {
        formatted['model'] = model;
        if (msg.containsKey('usage')) {
          formatted['usage'] = msg['usage'];
        }
      }

      return formatted;
    }).toList();

    // Include the message ID and session ID at the top level - server expects these
    final requestData = {
      'id': messageId, // The server expects the assistant message ID here
      'chat_id': chatId,
      'model': model,
      'messages': formattedMessages,
      'session_id':
          sessionId ?? const Uuid().v4().substring(0, 20), // Add session_id
      // Don't include model_item as it might not be expected
    };

    try {
      final response = await _dio.post(
        '/api/chat/completed',
        data: requestData,
        options: Options(
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      debugPrint('DEBUG: Chat completed response: ${response.statusCode}');
    } catch (e) {
      // This is a non-critical endpoint - main sync happens via /api/v1/chats/{id}
      debugPrint(
        'DEBUG: Chat completed endpoint not available or failed (non-critical): $e',
      );
    }
  }

  // Query a collection for content
  Future<List<dynamic>> queryCollection(
    String collectionName,
    String query,
  ) async {
    debugPrint(
      'DEBUG: Querying collection: $collectionName with query: $query',
    );
    try {
      final response = await _dio.post(
        '/api/v1/retrieval/query/collection',
        data: {
          'collection_names': [collectionName], // API expects an array
          'query': query,
          'k': 5, // Limit to top 5 results
        },
      );

      debugPrint(
        'DEBUG: Collection query response status: ${response.statusCode}',
      );
      debugPrint(
        'DEBUG: Collection query response type: ${response.data.runtimeType}',
      );
      DebugLogger.log('Collection query response received successfully');

      if (response.data is List) {
        return response.data as List<dynamic>;
      } else if (response.data is Map<String, dynamic>) {
        // If the response is a map, check for common result keys
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('results')) {
          return data['results'] as List<dynamic>? ?? [];
        } else if (data.containsKey('documents')) {
          return data['documents'] as List<dynamic>? ?? [];
        } else if (data.containsKey('data')) {
          return data['data'] as List<dynamic>? ?? [];
        }
      }

      return [];
    } catch (e) {
      debugPrint('DEBUG: Collection query API error: $e');
      if (e is DioException) {
        debugPrint(
          'DEBUG: Collection query error response: ${e.response?.data}',
        );
        debugPrint(
          'DEBUG: Collection query error status: ${e.response?.statusCode}',
        );
      }
      rethrow;
    }
  }

  // Get retrieval configuration to check web search settings
  Future<Map<String, dynamic>> getRetrievalConfig() async {
    debugPrint('DEBUG: Getting retrieval configuration');
    try {
      final response = await _dio.get('/api/v1/retrieval/config');

      debugPrint(
        'DEBUG: Retrieval config response status: ${response.statusCode}',
      );
      DebugLogger.log('Retrieval config response received successfully');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DEBUG: Retrieval config API error: $e');
      if (e is DioException) {
        debugPrint(
          'DEBUG: Retrieval config error response: ${e.response?.data}',
        );
        debugPrint(
          'DEBUG: Retrieval config error status: ${e.response?.statusCode}',
        );
      }
      rethrow;
    }
  }

  // Audio
  Future<List<String>> getAvailableVoices() async {
    debugPrint('DEBUG: Fetching available voices');
    final response = await _dio.get('/api/v1/audio/voices');
    final data = response.data;
    if (data is List) {
      return data.cast<String>();
    }
    return [];
  }

  Future<List<int>> generateSpeech({
    required String text,
    String? voice,
  }) async {
    final textPreview = text.length > 50 ? text.substring(0, 50) : text;
    debugPrint('DEBUG: Generating speech for text: $textPreview...');
    final response = await _dio.post(
      '/api/v1/audio/speech',
      data: {'text': text, if (voice != null) 'voice': voice},
    );

    // Return audio data as bytes
    if (response.data is List) {
      return (response.data as List).cast<int>();
    }
    return [];
  }

  // Server audio transcription removed; rely on on-device STT in UI layer

  // Image Generation
  Future<List<Map<String, dynamic>>> getImageModels() async {
    debugPrint('DEBUG: Fetching image generation models');
    final response = await _dio.get('/api/v1/images/models');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<dynamic> generateImage({
    required String prompt,
    String? model,
    int? width,
    int? height,
    int? steps,
    double? guidance,
  }) async {
    final promptPreview = prompt.length > 50 ? prompt.substring(0, 50) : prompt;
    debugPrint('DEBUG: Generating image with prompt: $promptPreview...');
    try {
      final response = await _dio.post(
        '/api/v1/images/generations',
        data: {
          'prompt': prompt,
          if (model != null) 'model': model,
          if (width != null) 'width': width,
          if (height != null) 'height': height,
          if (steps != null) 'steps': steps,
          if (guidance != null) 'guidance': guidance,
        },
      );
      return response.data;
    } on DioException catch (e) {
      debugPrint('DEBUG: images/generations failed: ${e.response?.statusCode}');
      DebugLogger.error(
        'Image generation request to /api/v1/images/generations failed',
        e,
      );
      // Do not attempt singular fallback here - surface the original error
      rethrow;
    }
  }

  // Prompts
  Future<List<Map<String, dynamic>>> getPrompts() async {
    debugPrint('DEBUG: Fetching prompts');
    final response = await _dio.get('/api/v1/prompts/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // Permissions & Features
  Future<Map<String, dynamic>> getUserPermissions() async {
    debugPrint('DEBUG: Fetching user permissions');
    try {
      final response = await _dio.get('/api/v1/users/permissions');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DEBUG: Error fetching user permissions: $e');
      if (e is DioException) {
        debugPrint('DEBUG: Permissions error response: ${e.response?.data}');
        debugPrint(
          'DEBUG: Permissions error status: ${e.response?.statusCode}',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createPrompt({
    required String title,
    required String content,
    String? description,
    List<String>? tags,
  }) async {
    debugPrint('DEBUG: Creating prompt: $title');
    final response = await _dio.post(
      '/api/v1/prompts/',
      data: {
        'title': title,
        'content': content,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> updatePrompt(
    String id, {
    String? title,
    String? content,
    String? description,
    List<String>? tags,
  }) async {
    debugPrint('DEBUG: Updating prompt: $id');
    await _dio.put(
      '/api/v1/prompts/$id',
      data: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
      },
    );
  }

  Future<void> deletePrompt(String id) async {
    debugPrint('DEBUG: Deleting prompt: $id');
    await _dio.delete('/api/v1/prompts/$id');
  }

  // Tools & Functions
  Future<List<Map<String, dynamic>>> getTools() async {
    debugPrint('DEBUG: Fetching tools');
    final response = await _dio.get('/api/v1/tools/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getFunctions() async {
    debugPrint('DEBUG: Fetching functions');
    final response = await _dio.get('/api/v1/functions/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> createTool({
    required String name,
    required Map<String, dynamic> spec,
  }) async {
    debugPrint('DEBUG: Creating tool: $name');
    final response = await _dio.post(
      '/api/v1/tools/',
      data: {'name': name, 'spec': spec},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createFunction({
    required String name,
    required String code,
    String? description,
  }) async {
    debugPrint('DEBUG: Creating function: $name');
    final response = await _dio.post(
      '/api/v1/functions/',
      data: {
        'name': name,
        'code': code,
        if (description != null) 'description': description,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // Enhanced Tools Management Operations
  Future<Map<String, dynamic>> getTool(String toolId) async {
    debugPrint('DEBUG: Fetching tool details: $toolId');
    final response = await _dio.get('/api/v1/tools/id/$toolId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateTool(
    String toolId, {
    String? name,
    Map<String, dynamic>? spec,
    String? description,
  }) async {
    debugPrint('DEBUG: Updating tool: $toolId');
    final response = await _dio.post(
      '/api/v1/tools/id/$toolId/update',
      data: {
        if (name != null) 'name': name,
        if (spec != null) 'spec': spec,
        if (description != null) 'description': description,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteTool(String toolId) async {
    debugPrint('DEBUG: Deleting tool: $toolId');
    await _dio.delete('/api/v1/tools/id/$toolId/delete');
  }

  Future<Map<String, dynamic>> getToolValves(String toolId) async {
    debugPrint('DEBUG: Fetching tool valves: $toolId');
    final response = await _dio.get('/api/v1/tools/id/$toolId/valves');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateToolValves(
    String toolId,
    Map<String, dynamic> valves,
  ) async {
    debugPrint('DEBUG: Updating tool valves: $toolId');
    final response = await _dio.post(
      '/api/v1/tools/id/$toolId/valves/update',
      data: valves,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getUserToolValves(String toolId) async {
    debugPrint('DEBUG: Fetching user tool valves: $toolId');
    final response = await _dio.get('/api/v1/tools/id/$toolId/valves/user');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUserToolValves(
    String toolId,
    Map<String, dynamic> valves,
  ) async {
    debugPrint('DEBUG: Updating user tool valves: $toolId');
    final response = await _dio.post(
      '/api/v1/tools/id/$toolId/valves/user/update',
      data: valves,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> exportTools() async {
    debugPrint('DEBUG: Exporting tools configuration');
    final response = await _dio.get('/api/v1/tools/export');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> loadToolFromUrl(String url) async {
    debugPrint('DEBUG: Loading tool from URL: $url');
    final response = await _dio.post(
      '/api/v1/tools/load/url',
      data: {'url': url},
    );
    return response.data as Map<String, dynamic>;
  }

  // Enhanced Functions Management Operations
  Future<Map<String, dynamic>> getFunction(String functionId) async {
    debugPrint('DEBUG: Fetching function details: $functionId');
    final response = await _dio.get('/api/v1/functions/id/$functionId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateFunction(
    String functionId, {
    String? name,
    String? code,
    String? description,
  }) async {
    debugPrint('DEBUG: Updating function: $functionId');
    final response = await _dio.post(
      '/api/v1/functions/id/$functionId/update',
      data: {
        if (name != null) 'name': name,
        if (code != null) 'code': code,
        if (description != null) 'description': description,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteFunction(String functionId) async {
    debugPrint('DEBUG: Deleting function: $functionId');
    await _dio.delete('/api/v1/functions/id/$functionId/delete');
  }

  Future<Map<String, dynamic>> toggleFunction(String functionId) async {
    debugPrint('DEBUG: Toggling function: $functionId');
    final response = await _dio.post('/api/v1/functions/id/$functionId/toggle');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> toggleGlobalFunction(String functionId) async {
    debugPrint('DEBUG: Toggling global function: $functionId');
    final response = await _dio.post(
      '/api/v1/functions/id/$functionId/toggle/global',
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getFunctionValves(String functionId) async {
    debugPrint('DEBUG: Fetching function valves: $functionId');
    final response = await _dio.get('/api/v1/functions/id/$functionId/valves');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateFunctionValves(
    String functionId,
    Map<String, dynamic> valves,
  ) async {
    debugPrint('DEBUG: Updating function valves: $functionId');
    final response = await _dio.post(
      '/api/v1/functions/id/$functionId/valves/update',
      data: valves,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getUserFunctionValves(String functionId) async {
    debugPrint('DEBUG: Fetching user function valves: $functionId');
    final response = await _dio.get(
      '/api/v1/functions/id/$functionId/valves/user',
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUserFunctionValves(
    String functionId,
    Map<String, dynamic> valves,
  ) async {
    debugPrint('DEBUG: Updating user function valves: $functionId');
    final response = await _dio.post(
      '/api/v1/functions/id/$functionId/valves/user/update',
      data: valves,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncFunctions() async {
    debugPrint('DEBUG: Syncing functions');
    final response = await _dio.post('/api/v1/functions/sync');
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> exportFunctions() async {
    debugPrint('DEBUG: Exporting functions configuration');
    final response = await _dio.get('/api/v1/functions/export');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // Memory & Notes
  Future<List<Map<String, dynamic>>> getMemories() async {
    debugPrint('DEBUG: Fetching memories');
    final response = await _dio.get('/api/v1/memories/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> createMemory({
    required String content,
    String? title,
  }) async {
    debugPrint('DEBUG: Creating memory');
    final response = await _dio.post(
      '/api/v1/memories/',
      data: {'content': content, if (title != null) 'title': title},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getNotes() async {
    debugPrint('DEBUG: Fetching notes');
    final response = await _dio.get('/api/v1/notes/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> createNote({
    required String title,
    required String content,
    List<String>? tags,
  }) async {
    debugPrint('DEBUG: Creating note: $title');
    final response = await _dio.post(
      '/api/v1/notes/',
      data: {
        'title': title,
        'content': content,
        if (tags != null) 'tags': tags,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateNote(
    String id, {
    String? title,
    String? content,
    List<String>? tags,
  }) async {
    debugPrint('DEBUG: Updating note: $id');
    await _dio.put(
      '/api/v1/notes/$id',
      data: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (tags != null) 'tags': tags,
      },
    );
  }

  Future<void> deleteNote(String id) async {
    debugPrint('DEBUG: Deleting note: $id');
    await _dio.delete('/api/v1/notes/$id');
  }

  // Team Collaboration
  Future<List<Map<String, dynamic>>> getChannels() async {
    debugPrint('DEBUG: Fetching channels');
    final response = await _dio.get('/api/v1/channels/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> createChannel({
    required String name,
    String? description,
    bool isPrivate = false,
  }) async {
    debugPrint('DEBUG: Creating channel: $name');
    final response = await _dio.post(
      '/api/v1/channels/',
      data: {
        'name': name,
        if (description != null) 'description': description,
        'is_private': isPrivate,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> joinChannel(String channelId) async {
    debugPrint('DEBUG: Joining channel: $channelId');
    await _dio.post('/api/v1/channels/$channelId/join');
  }

  Future<void> leaveChannel(String channelId) async {
    debugPrint('DEBUG: Leaving channel: $channelId');
    await _dio.post('/api/v1/channels/$channelId/leave');
  }

  Future<List<Map<String, dynamic>>> getChannelMembers(String channelId) async {
    debugPrint('DEBUG: Fetching channel members: $channelId');
    final response = await _dio.get('/api/v1/channels/$channelId/members');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Conversation>> getChannelConversations(String channelId) async {
    debugPrint('DEBUG: Fetching channel conversations: $channelId');
    final response = await _dio.get('/api/v1/channels/$channelId/chats');
    final data = response.data;
    if (data is List) {
      return data.map((chatData) => _parseOpenWebUIChat(chatData)).toList();
    }
    return [];
  }

  // Enhanced Channel Management Operations
  Future<Map<String, dynamic>> getChannel(String channelId) async {
    debugPrint('DEBUG: Fetching channel details: $channelId');
    final response = await _dio.get('/api/v1/channels/$channelId');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateChannel(
    String channelId, {
    String? name,
    String? description,
    bool? isPrivate,
  }) async {
    debugPrint('DEBUG: Updating channel: $channelId');
    final response = await _dio.post(
      '/api/v1/channels/$channelId/update',
      data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (isPrivate != null) 'is_private': isPrivate,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteChannel(String channelId) async {
    debugPrint('DEBUG: Deleting channel: $channelId');
    await _dio.delete('/api/v1/channels/$channelId/delete');
  }

  Future<List<Map<String, dynamic>>> getChannelMessages(
    String channelId, {
    int? limit,
    int? offset,
    DateTime? before,
    DateTime? after,
  }) async {
    debugPrint('DEBUG: Fetching channel messages: $channelId');
    final queryParams = <String, dynamic>{};
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;
    if (before != null) queryParams['before'] = before.toIso8601String();
    if (after != null) queryParams['after'] = after.toIso8601String();

    final response = await _dio.get(
      '/api/v1/channels/$channelId/messages',
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> postChannelMessage(
    String channelId, {
    required String content,
    String? messageType,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('DEBUG: Posting message to channel: $channelId');
    final response = await _dio.post(
      '/api/v1/channels/$channelId/messages/post',
      data: {
        'content': content,
        if (messageType != null) 'message_type': messageType,
        if (metadata != null) 'metadata': metadata,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateChannelMessage(
    String channelId,
    String messageId, {
    String? content,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('DEBUG: Updating channel message: $channelId/$messageId');
    final response = await _dio.post(
      '/api/v1/channels/$channelId/messages/$messageId/update',
      data: {
        if (content != null) 'content': content,
        if (metadata != null) 'metadata': metadata,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteChannelMessage(String channelId, String messageId) async {
    debugPrint('DEBUG: Deleting channel message: $channelId/$messageId');
    await _dio.delete('/api/v1/channels/$channelId/messages/$messageId');
  }

  Future<Map<String, dynamic>> addMessageReaction(
    String channelId,
    String messageId,
    String emoji,
  ) async {
    debugPrint('DEBUG: Adding reaction to message: $channelId/$messageId');
    final response = await _dio.post(
      '/api/v1/channels/$channelId/messages/$messageId/reactions',
      data: {'emoji': emoji},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> removeMessageReaction(
    String channelId,
    String messageId,
    String emoji,
  ) async {
    debugPrint('DEBUG: Removing reaction from message: $channelId/$messageId');
    await _dio.delete(
      '/api/v1/channels/$channelId/messages/$messageId/reactions/$emoji',
    );
  }

  Future<List<Map<String, dynamic>>> getMessageReactions(
    String channelId,
    String messageId,
  ) async {
    debugPrint('DEBUG: Fetching message reactions: $channelId/$messageId');
    final response = await _dio.get(
      '/api/v1/channels/$channelId/messages/$messageId/reactions',
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getMessageThread(
    String channelId,
    String messageId,
  ) async {
    debugPrint('DEBUG: Fetching message thread: $channelId/$messageId');
    final response = await _dio.get(
      '/api/v1/channels/$channelId/messages/$messageId/thread',
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> replyToMessage(
    String channelId,
    String messageId, {
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    debugPrint('DEBUG: Replying to message: $channelId/$messageId');
    final response = await _dio.post(
      '/api/v1/channels/$channelId/messages/$messageId/reply',
      data: {'content': content, if (metadata != null) 'metadata': metadata},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> markChannelRead(String channelId, {String? messageId}) async {
    debugPrint('DEBUG: Marking channel as read: $channelId');
    await _dio.post(
      '/api/v1/channels/$channelId/read',
      data: {if (messageId != null) 'last_read_message_id': messageId},
    );
  }

  Future<Map<String, dynamic>> getChannelUnreadCount(String channelId) async {
    debugPrint('DEBUG: Fetching unread count for channel: $channelId');
    final response = await _dio.get('/api/v1/channels/$channelId/unread');
    return response.data as Map<String, dynamic>;
  }

  // Chat streaming with conversation context
  // Track cancellable streaming requests by messageId for stop parity
  final Map<String, CancelToken> _streamCancelTokens = {};
  final Map<String, String> _messagePersistentStreamIds = {};

  // Send message with SSE streaming
  // Returns a record with (stream, messageId, sessionId)
  ({Stream<String> stream, String messageId, String sessionId}) sendMessage({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? conversationId,
    List<String>? toolIds,
    bool enableWebSearch = false,
    bool enableImageGeneration = false,
    Map<String, dynamic>? modelItem,
    String? sessionIdOverride,
    List<Map<String, dynamic>>? toolServers,
    Map<String, dynamic>? backgroundTasks,
    String? responseMessageId,
  }) {
    final streamController = StreamController<String>();

    // Generate unique IDs
    final messageId =
        (responseMessageId != null && responseMessageId.isNotEmpty)
        ? responseMessageId
        : const Uuid().v4();
    final sessionId =
        (sessionIdOverride != null && sessionIdOverride.isNotEmpty)
        ? sessionIdOverride
        : const Uuid().v4().substring(0, 20);

    // NOTE: Previously used to branch for Gemini-specific handling; not needed now.

    // Process messages to match OpenWebUI format
    final processedMessages = messages.map((message) {
      final role = message['role'] as String;
      final content = message['content'];
      final files = message['files'] as List<Map<String, dynamic>>?;

      final isContentArray = content is List;
      final hasImages = files?.any((file) => file['type'] == 'image') ?? false;

      if (isContentArray) {
        return {'role': role, 'content': content};
      } else if (hasImages && role == 'user') {
        final imageFiles = files!
            .where((file) => file['type'] == 'image')
            .toList();
        final contentText = content is String ? content : '';
        final contentArray = <Map<String, dynamic>>[
          {'type': 'text', 'text': contentText},
        ];

        for (final file in imageFiles) {
          contentArray.add({
            'type': 'image_url',
            'image_url': {'url': file['url']},
          });
        }
        return {'role': role, 'content': contentArray};
      } else {
        final contentText = content is String ? content : '';
        return {'role': role, 'content': contentText};
      }
    }).toList();

    // Separate files from messages
    final allFiles = <Map<String, dynamic>>[];
    for (final message in messages) {
      final files = message['files'] as List<Map<String, dynamic>>?;
      if (files != null) {
        final nonImageFiles = files
            .where((file) => file['type'] != 'image')
            .toList();
        allFiles.addAll(nonImageFiles);
      }
    }

    // Build request data - minimal params for SSE to work
    // OpenWebUI server doesn't support SSE with session_id/id parameters
    final data = {
      'stream': true,
      'model': model,
      'messages': processedMessages,
    };

    // Add only essential parameters
    if (conversationId != null) {
      data['chat_id'] = conversationId;
    }

    // Add feature flags if enabled
    if (enableWebSearch) {
      data['web_search'] = true;
      debugPrint('DEBUG: Web search enabled in SSE request');
    }
    if (enableImageGeneration) {
      // Mirror web_search behavior for image generation
      data['image_generation'] = true;
      debugPrint('DEBUG: Image generation enabled in SSE request');
    }

    if (enableWebSearch || enableImageGeneration) {
      // Include features map for compatibility
      data['features'] = {
        'web_search': enableWebSearch,
        'image_generation': enableImageGeneration,
        'code_interpreter': false,
        'memory': false,
      };
    }

    // No default reasoning parameters included; providers handle thinking UIs natively.

    // Add tool_ids if provided (Open-WebUI expects tool_ids as array of strings)
    if (toolIds != null && toolIds.isNotEmpty) {
      data['tool_ids'] = toolIds;
      debugPrint('DEBUG: Including tool_ids in SSE request: $toolIds');

      // Hint server to use native function calling when tools are selected
      // This enables provider-native tool execution paths and consistent UI events
      try {
        final params =
            (data['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        params['function_calling'] = 'native';
        data['params'] = params;
        debugPrint('DEBUG: Set params.function_calling = native');
      } catch (_) {
        // Non-fatal; continue without forcing native mode
      }
    }

    // Include tool_servers if provided (for native function calling with OpenAPI servers)
    if (toolServers != null && toolServers.isNotEmpty) {
      data['tool_servers'] = toolServers;
      debugPrint(
        'DEBUG: Including tool_servers in request (${toolServers.length})',
      );
    }

    // Include non-image files at the top level as expected by Open WebUI
    if (allFiles.isNotEmpty) {
      data['files'] = allFiles;
      debugPrint(
        'DEBUG: Including non-image files in request: ${allFiles.length}',
      );
    }

    // Don't add session_id or id - they break SSE streaming!
    // The server falls back to task-based async when these are present

    debugPrint('DEBUG: Starting SSE streaming request');
    debugPrint('DEBUG: Model: $model');
    debugPrint('DEBUG: Message count: ${processedMessages.length}');

    // Debug the data being sent
    debugPrint('DEBUG: SSE request data keys (pre-bg): ${data.keys.toList()}');
    debugPrint(
      'DEBUG: Has background_tasks (pre-bg): ${data.containsKey('background_tasks')}',
    );
    debugPrint(
      'DEBUG: Has session_id (pre-bg): ${data.containsKey('session_id')}',
    );
    debugPrint(
      'DEBUG: background_tasks value (pre-bg): ${data['background_tasks']}',
    );
    debugPrint('DEBUG: session_id value (pre-bg): ${data['session_id']}');
    debugPrint('DEBUG: id value (pre-bg): ${data['id']}');

    // Decide whether to use background task flow.
    // Use background task mode when tools, web_search, image_generation are enabled,
    // or when an explicit dynamic socket session binding is requested.
    final bool useBackgroundTasks =
        (toolIds != null && toolIds.isNotEmpty) ||
        enableWebSearch ||
        enableImageGeneration ||
        (sessionIdOverride != null && sessionIdOverride.isNotEmpty);

    // Use background flow only when required; otherwise prefer SSE even with chat_id.
    // SSE must not include session_id/id to avoid server falling back to task mode.
    if (useBackgroundTasks) {
      // Attach identifiers to trigger background task processing on the server
      data['session_id'] = sessionId;
      data['id'] = messageId;
      if (conversationId != null) {
        data['chat_id'] = conversationId;
      }

      // Attach background_tasks if provided
      if (backgroundTasks != null && backgroundTasks.isNotEmpty) {
        data['background_tasks'] = backgroundTasks;
      }

      // Extra diagnostics to confirm dynamic-channel payload
      debugPrint('DEBUG: Background flow payload keys: ${data.keys.toList()}');
      debugPrint('DEBUG: Using session_id: $sessionId');
      debugPrint('DEBUG: Using message id: $messageId');
      debugPrint(
        'DEBUG: Has tool_ids: ${data.containsKey('tool_ids')} -> ${data['tool_ids']}',
      );
      debugPrint(
        'DEBUG: Has background_tasks: ${data.containsKey('background_tasks')}',
      );

      debugPrint('DEBUG: Initiating background tools flow (task-based)');
      debugPrint('DEBUG: Posting to /api/chat/completions (no SSE)');

      // Fire in background; poll chat for updates and stream deltas to UI
      () async {
        try {
          final resp = await _dio.post('/api/chat/completions', data: data);
          final respData = resp.data;
          final taskId = (respData is Map)
              ? (respData['task_id']?.toString())
              : null;
          debugPrint('DEBUG: Background task created: $taskId');

          // If no session/socket provided, fall back to polling for updates.
          if (sessionIdOverride == null || sessionIdOverride.isEmpty) {
            await _pollChatForMessageUpdates(
              chatId: conversationId!,
              messageId: messageId,
              streamController: streamController,
            );
          } else {
            // Close the controller so listeners don't hang waiting for chunks
            if (!streamController.isClosed) {
              streamController.close();
            }
          }
        } catch (e) {
          debugPrint('DEBUG: Background tools flow failed: $e');
          if (!streamController.isClosed) streamController.close();
        }
      }();
    } else {
      // SSE streaming path for low-latency pure completions (no background tasks)
      () async {
        try {
          // Request SSE stream; avoid session_id/id which break streaming
          final resp = await _dio.post(
            '/api/chat/completions',
            data: data,
            options: Options(
              responseType: ResponseType.stream,
              headers: {'Accept': 'text/event-stream'},
            ),
          );

          // Parse SSE lines and forward deltas to the controller
          final body = resp.data;
          // Dio returns ResponseBody for stream responseType
          final stream = (body is ResponseBody) ? body.stream : null;
          if (stream == null) {
            // Fallback: if server responded JSON, emit once
            try {
              final dataStr = resp.data?.toString() ?? '';
              if (dataStr.isNotEmpty && !streamController.isClosed) {
                streamController.add(dataStr);
              }
            } catch (_) {}
            if (!streamController.isClosed) streamController.close();
            return;
          }

          String buffer = '';
          late final StreamSubscription<List<int>> sub;
          sub = stream.listen(
            (chunk) {
              try {
                buffer += utf8.decode(chunk, allowMalformed: true);
                // Process complete lines; keep remainder in buffer
                final parts = buffer.split('\n');
                buffer = parts.isNotEmpty ? parts.removeLast() : '';
                for (final raw in parts) {
                  final line = raw.trim();
                  if (line.isEmpty) continue;
                  if (line == 'data: [DONE]') {
                    try {
                      if (!streamController.isClosed) streamController.close();
                    } catch (_) {}
                    sub.cancel();
                    return;
                  }
                  if (line.startsWith('data:')) {
                    final payloadStr = line.substring(5).trim();
                    if (payloadStr.isEmpty) continue;
                    try {
                      final Map<String, dynamic> j = jsonDecode(payloadStr);
                      final choices = j['choices'];
                      if (choices is List && choices.isNotEmpty) {
                        final choice = choices.first;
                        final delta = choice is Map ? choice['delta'] : null;
                        if (delta is Map) {
                          final content = delta['content']?.toString() ?? '';
                          if (content.isNotEmpty &&
                              !streamController.isClosed) {
                            streamController.add(content);
                          }
                        } else {
                          final message = (choice is Map)
                              ? (choice['message']?['content']?.toString() ??
                                    '')
                              : '';
                          if (message.isNotEmpty &&
                              !streamController.isClosed) {
                            streamController.add(message);
                          }
                        }
                      } else if (j['content'] is String) {
                        final content = j['content'] as String;
                        if (content.isNotEmpty && !streamController.isClosed) {
                          streamController.add(content);
                        }
                      }
                    } catch (_) {
                      // Non-JSON payload; forward as-is
                      if (!streamController.isClosed) {
                        streamController.add(payloadStr);
                      }
                    }
                  }
                }
              } catch (_) {}
            },
            onDone: () {
              try {
                if (!streamController.isClosed) streamController.close();
              } catch (_) {}
            },
            onError: (_) {
              try {
                if (!streamController.isClosed) streamController.close();
              } catch (_) {}
            },
            cancelOnError: true,
          );
        } catch (e) {
          debugPrint('DEBUG: SSE streaming failed: $e');
          if (!streamController.isClosed) streamController.close();
        }
      }();
    }

    return (
      stream: streamController.stream,
      messageId: messageId,
      sessionId: sessionId,
    );
  }

  // === Tasks control (parity with Web client) ===
  Future<void> stopTask(String taskId) async {
    try {
      await _dio.post('/api/tasks/stop/$taskId');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<String>> getTaskIdsByChat(String chatId) async {
    try {
      final resp = await _dio.get('/api/tasks/chat/$chatId');
      final data = resp.data;
      if (data is Map && data['task_ids'] is List) {
        return (data['task_ids'] as List).map((e) => e.toString()).toList();
      }
      return const [];
    } catch (e) {
      rethrow;
    }
  }

  // Poll the server chat until the assistant message is populated with tool results,
  // then stream deltas to the UI and close.
  Future<void> _pollChatForMessageUpdates({
    required String chatId,
    required String messageId,
    required StreamController<String> streamController,
  }) async {
    String last = '';
    int stableCount = 0;
    final started = DateTime.now();

    bool containsDone(String s) =>
        s.contains('<details type="tool_calls"') && s.contains('done="true"');

    // Allow longer time for large completions (e.g., long stories)
    while (DateTime.now().difference(started).inSeconds < 180) {
      try {
        // Small delay between polls
        await Future.delayed(const Duration(milliseconds: 900));

        final resp = await _dio.get('/api/v1/chats/$chatId');
        final data = resp.data as Map<String, dynamic>;

        // Locate assistant content from multiple shapes
        String content = '';

        Map<String, dynamic>? chatObj = (data['chat'] is Map<String, dynamic>)
            ? data['chat'] as Map<String, dynamic>
            : null;

        // 1) Preferred: chat.messages (list) – try exact id first
        if (chatObj != null && chatObj['messages'] is List) {
          final List messagesList = chatObj['messages'] as List;
          final target = messagesList.firstWhere(
            (m) => (m is Map && (m['id']?.toString() == messageId)),
            orElse: () => null,
          );
          if (target != null) {
            final rawContent = (target as Map)['content'];
            if (rawContent is List) {
              final textItem = rawContent.firstWhere(
                (i) => i is Map && i['type'] == 'text',
                orElse: () => null,
              );
              if (textItem != null) {
                content = textItem['text']?.toString() ?? '';
              }
            } else if (rawContent is String) {
              content = rawContent;
            }
          }
        }

        // 2) Fallback: chat.history.messages (map) – try exact id
        if (content.isEmpty && chatObj != null) {
          final history = chatObj['history'];
          if (history is Map && history['messages'] is Map) {
            final Map<String, dynamic> messagesMap =
                (history['messages'] as Map).cast<String, dynamic>();
            final msg = messagesMap[messageId];
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

        // 3) Last resort: top-level messages (list) – try exact id
        if (content.isEmpty && data['messages'] is List) {
          final List topMessages = data['messages'] as List;
          final target = topMessages.firstWhere(
            (m) => (m is Map && (m['id']?.toString() == messageId)),
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

        // 4) If nothing found by id, fall back to the latest assistant message
        if (content.isEmpty) {
          // Prefer chat.messages list
          if (chatObj != null && chatObj['messages'] is List) {
            final List messagesList = chatObj['messages'] as List;
            // Find last assistant
            for (int i = messagesList.length - 1; i >= 0; i--) {
              final m = messagesList[i];
              if (m is Map && (m['role']?.toString() == 'assistant')) {
                final rawContent = m['content'];
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
                if (content.isNotEmpty) break;
              }
            }
          }

          // Try history map if still empty
          if (content.isEmpty && chatObj != null) {
            final history = chatObj['history'];
            if (history is Map && history['messages'] is Map) {
              final Map<dynamic, dynamic> msgMapDyn =
                  history['messages'] as Map;
              // Iterate by values; no guaranteed ordering, but often sufficient
              for (final entry in msgMapDyn.values) {
                if (entry is Map &&
                    (entry['role']?.toString() == 'assistant')) {
                  final rawContent = entry['content'];
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
                  if (content.isNotEmpty) break;
                }
              }
            }
          }
        }

        if (content.isEmpty) {
          continue;
        }

        // Stream only the delta when content grows monotonically
        if (content.startsWith(last)) {
          final delta = content.substring(last.length);
          if (delta.isNotEmpty && !streamController.isClosed) {
            streamController.add(delta);
          }
        } else {
          // Fallback: replace entire content by emitting a separator + full content
          if (!streamController.isClosed) {
            streamController.add('\n');
            streamController.add(content);
          }
        }
        // Stop when we detect done=true on tool_calls or when content stabilizes
        if (containsDone(content)) {
          break;
        }

        // If content hasn't changed for a few polls, assume completion,
        // but do not early-exit while content is still empty.
        final prev = last;
        if (content == prev && content.isNotEmpty) {
          stableCount++;
        } else if (content != prev) {
          stableCount = 0;
        }
        if (content.isNotEmpty && stableCount >= 3) {
          break;
        }

        last = content;
      } catch (e) {
        // Ignore transient errors and continue polling
      }
    }

    // Final backfill: one last attempt to fetch the latest content
    // in case the server wrote the final message after our last poll.
    try {
      if (!streamController.isClosed) {
        final resp = await _dio.get('/api/v1/chats/$chatId');
        final data = resp.data as Map<String, dynamic>;
        String content = '';
        Map<String, dynamic>? chatObj = (data['chat'] is Map<String, dynamic>)
            ? data['chat'] as Map<String, dynamic>
            : null;
        if (chatObj != null && chatObj['messages'] is List) {
          final List messagesList = chatObj['messages'] as List;
          final target = messagesList.firstWhere(
            (m) => (m is Map && (m['id']?.toString() == messageId)),
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
                content = (textItem as Map)['text']?.toString() ?? '';
              }
            }
          }
        }
        if (content.isEmpty && chatObj != null) {
          final history = chatObj['history'];
          if (history is Map && history['messages'] is Map) {
            final Map<String, dynamic> messagesMap =
                (history['messages'] as Map).cast<String, dynamic>();
            final msg = messagesMap[messageId];
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
                  content = (textItem as Map)['text']?.toString() ?? '';
                }
              }
            }
          }
        }
        if (content.isNotEmpty && content != last) {
          streamController.add('\n');
          streamController.add(content);
        }
      }
    } catch (_) {}

    if (!streamController.isClosed) {
      streamController.close();
    }
  }

  // Cancel an active streaming message by its messageId (client-side abort)
  void cancelStreamingMessage(String messageId) {
    try {
      final token = _streamCancelTokens.remove(messageId);
      if (token != null && !token.isCancelled) {
        token.cancel('User cancelled');
      }
    } catch (_) {}

    try {
      final pid = _messagePersistentStreamIds.remove(messageId);
      if (pid != null) {
        PersistentStreamingService().unregisterStream(pid);
      }
    } catch (_) {}
  }

  // File upload for RAG
  Future<String> uploadFile(String filePath, String fileName) async {
    debugPrint('DEBUG: Starting file upload: $fileName from $filePath');

    try {
      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist: $filePath');
      }

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      debugPrint('DEBUG: Uploading to /api/v1/files/');
      final response = await _dio.post('/api/v1/files/', data: formData);

      DebugLogger.log('Upload response status: ${response.statusCode}');
      DebugLogger.log('Upload response received successfully');

      if (response.data is Map && response.data['id'] != null) {
        final fileId = response.data['id'] as String;
        debugPrint('DEBUG: File uploaded successfully with ID: $fileId');
        return fileId;
      } else {
        throw Exception('Invalid response format: missing file ID');
      }
    } catch (e) {
      debugPrint('ERROR: File upload failed: $e');
      rethrow;
    }
  }

  // Search conversations
  Future<List<Conversation>> searchConversations(String query) async {
    final response = await _dio.get(
      '/api/v1/chats/search',
      queryParameters: {'q': query},
    );
    final results = response.data as List;
    return results.map((c) => Conversation.fromJson(c)).toList();
  }

  // Debug method to test API endpoints
  Future<void> debugApiEndpoints() async {
    debugPrint('=== DEBUG API ENDPOINTS ===');
    debugPrint('Server URL: ${serverConfig.url}');
    debugPrint('Auth token present: ${authToken != null}');

    // Test different possible endpoints
    final endpoints = [
      '/api/v1/chats',
      '/api/chats',
      '/api/v1/conversations',
      '/api/conversations',
    ];

    for (final endpoint in endpoints) {
      try {
        debugPrint('Testing endpoint: $endpoint');
        final response = await _dio.get(endpoint);
        debugPrint('✅ $endpoint - Status: ${response.statusCode}');
        DebugLogger.log('   Response type: ${response.data.runtimeType}');
        if (response.data is List) {
          DebugLogger.log('   Array length: ${(response.data as List).length}');
        } else if (response.data is Map) {
          DebugLogger.log('   Object keys: ${(response.data as Map).keys}');
        }
        final _dataStr = response.data.toString();
        final _dataPreview = _dataStr.length > 200
            ? _dataStr.substring(0, 200)
            : _dataStr;
        DebugLogger.log('   Sample data: $_dataPreview...');
      } catch (e) {
        debugPrint('❌ $endpoint - Error: $e');
      }
      debugPrint('---');
    }
    debugPrint('=== END DEBUG ===');
  }

  // Check if server has API documentation
  Future<void> checkApiDocumentation() async {
    debugPrint('=== CHECKING API DOCUMENTATION ===');
    final docEndpoints = ['/docs', '/api/docs', '/swagger', '/api/swagger'];

    for (final endpoint in docEndpoints) {
      try {
        final response = await _dio.get(endpoint);
        if (response.statusCode == 200) {
          debugPrint('✅ API docs available at: ${serverConfig.url}$endpoint');
          if (response.data is String &&
              response.data.toString().contains('swagger')) {
            debugPrint('   This appears to be Swagger documentation');
          }
        }
      } catch (e) {
        debugPrint('❌ No docs at $endpoint');
      }
    }
    debugPrint('=== END API DOCS CHECK ===');
  }

  // dispose() removed – no legacy websocket resources to clean up

  // Helper method to get current weekday name
  // ==================== ADVANCED CHAT FEATURES ====================
  // Chat import/export, bulk operations, and advanced search

  /// Import chat data from external sources
  Future<List<Map<String, dynamic>>> importChats({
    required List<Map<String, dynamic>> chatsData,
    String? folderId,
    bool overwriteExisting = false,
  }) async {
    debugPrint('DEBUG: Importing ${chatsData.length} chats');
    final response = await _dio.post(
      '/api/v1/chats/import',
      data: {
        'chats': chatsData,
        if (folderId != null) 'folder_id': folderId,
        'overwrite_existing': overwriteExisting,
      },
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Export chat data for backup or migration
  Future<List<Map<String, dynamic>>> exportChats({
    List<String>? chatIds,
    String? folderId,
    bool includeMessages = true,
    String? format,
  }) async {
    debugPrint(
      'DEBUG: Exporting chats${chatIds != null ? ' (${chatIds.length} chats)' : ''}',
    );
    final queryParams = <String, dynamic>{};
    if (chatIds != null) queryParams['chat_ids'] = chatIds.join(',');
    if (folderId != null) queryParams['folder_id'] = folderId;
    if (!includeMessages) queryParams['include_messages'] = false;
    if (format != null) queryParams['format'] = format;

    final response = await _dio.get(
      '/api/v1/chats/export',
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Archive all chats in bulk
  Future<Map<String, dynamic>> archiveAllChats({
    List<String>? excludeIds,
    String? beforeDate,
  }) async {
    debugPrint('DEBUG: Archiving all chats in bulk');
    final response = await _dio.post(
      '/api/v1/chats/archive/all',
      data: {
        if (excludeIds != null) 'exclude_ids': excludeIds,
        if (beforeDate != null) 'before_date': beforeDate,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Delete all chats in bulk
  Future<Map<String, dynamic>> deleteAllChats({
    List<String>? excludeIds,
    String? beforeDate,
    bool archived = false,
  }) async {
    debugPrint('DEBUG: Deleting all chats in bulk (archived: $archived)');
    final response = await _dio.post(
      '/api/v1/chats/delete/all',
      data: {
        if (excludeIds != null) 'exclude_ids': excludeIds,
        if (beforeDate != null) 'before_date': beforeDate,
        'archived_only': archived,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Get pinned chats
  Future<List<Conversation>> getPinnedChats() async {
    debugPrint('DEBUG: Fetching pinned chats');
    final response = await _dio.get('/api/v1/chats/pinned');
    final data = response.data;
    if (data is List) {
      return data.map((chatData) => _parseOpenWebUIChat(chatData)).toList();
    }
    return [];
  }

  /// Get archived chats
  Future<List<Conversation>> getArchivedChats({int? limit, int? offset}) async {
    debugPrint('DEBUG: Fetching archived chats');
    final queryParams = <String, dynamic>{};
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;

    final response = await _dio.get(
      '/api/v1/chats/archived',
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.map((chatData) => _parseOpenWebUIChat(chatData)).toList();
    }
    return [];
  }

  /// Advanced search for chats and messages
  Future<List<Conversation>> searchChats({
    String? query,
    String? userId,
    String? model,
    String? tag,
    String? folderId,
    DateTime? fromDate,
    DateTime? toDate,
    bool? pinned,
    bool? archived,
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    debugPrint('DEBUG: Searching chats with query: $query');
    final queryParams = <String, dynamic>{};
    // OpenAPI expects 'text' for this endpoint; keep extras if server tolerates them
    if (query != null) queryParams['text'] = query;
    if (userId != null) queryParams['user_id'] = userId;
    if (model != null) queryParams['model'] = model;
    if (tag != null) queryParams['tag'] = tag;
    if (folderId != null) queryParams['folder_id'] = folderId;
    if (fromDate != null) queryParams['from_date'] = fromDate.toIso8601String();
    if (toDate != null) queryParams['to_date'] = toDate.toIso8601String();
    if (pinned != null) queryParams['pinned'] = pinned;
    if (archived != null) queryParams['archived'] = archived;
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;
    if (sortBy != null) queryParams['sort_by'] = sortBy;
    if (sortOrder != null) queryParams['sort_order'] = sortOrder;

    final response = await _dio.get(
      '/api/v1/chats/search',
      queryParameters: queryParams,
    );
    final data = response.data;
    // The endpoint can return a List[ChatTitleIdResponse] or a map.
    // Normalize to a List<Conversation> using our safe parser.
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map((e) => _parseOpenWebUIChat(e))
          .toList();
    }
    if (data is Map<String, dynamic>) {
      final list = (data['conversations'] ?? data['items'] ?? data['results']);
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => _parseOpenWebUIChat(e))
            .toList();
      }
    }
    return <Conversation>[];
  }

  /// Search within messages content (capability-safe)
  ///
  /// Many OpenWebUI versions do not expose a dedicated messages search endpoint.
  /// We attempt a GET to `/api/v1/chats/messages/search` and gracefully return
  /// an empty list when the endpoint is missing or method is not allowed
  /// (404/405), avoiding noisy errors.
  Future<List<Map<String, dynamic>>> searchMessages({
    required String query,
    String? chatId,
    String? userId,
    String? role, // 'user' or 'assistant'
    DateTime? fromDate,
    DateTime? toDate,
    int? limit,
    int? offset,
  }) async {
    debugPrint('DEBUG: Searching messages with query: $query');

    // Build query parameters; include both 'text' and 'query' for compatibility
    final qp = <String, dynamic>{
      'text': query,
      'query': query,
      if (chatId != null) 'chat_id': chatId,
      if (userId != null) 'user_id': userId,
      if (role != null) 'role': role,
      if (fromDate != null) 'from_date': fromDate.toIso8601String(),
      if (toDate != null) 'to_date': toDate.toIso8601String(),
      if (limit != null) 'limit': limit,
      if (offset != null) 'offset': offset,
    };

    try {
      final response = await _dio.get(
        '/api/v1/chats/messages/search',
        queryParameters: qp,
        // Accept 404/405 to avoid throwing when endpoint is unsupported
        options: Options(
          validateStatus: (code) =>
              code != null && (code < 400 || code == 404 || code == 405),
        ),
      );

      // If not supported, quietly return empty results
      if (response.statusCode == 404 || response.statusCode == 405) {
        debugPrint(
          'DEBUG: messages search endpoint not supported (status: ${response.statusCode})',
        );
        return [];
      }

      final data = response.data;
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      }
      if (data is Map<String, dynamic>) {
        final list = (data['items'] ?? data['results'] ?? data['messages']);
        if (list is List) {
          return list.whereType<Map<String, dynamic>>().toList();
        }
      }
      return [];
    } on DioException catch (e) {
      // On any transport or other error, degrade gracefully without surfacing
      debugPrint('DEBUG: messages search request failed gracefully: ${e.type}');
      return [];
    }
  }

  /// Get chat statistics and analytics
  Future<Map<String, dynamic>> getChatStats({
    String? userId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    debugPrint('DEBUG: Fetching chat statistics');
    final queryParams = <String, dynamic>{};
    if (userId != null) queryParams['user_id'] = userId;
    if (fromDate != null) queryParams['from_date'] = fromDate.toIso8601String();
    if (toDate != null) queryParams['to_date'] = toDate.toIso8601String();

    final response = await _dio.get(
      '/api/v1/chats/stats',
      queryParameters: queryParams,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Duplicate/copy a chat
  Future<Conversation> duplicateChat(String chatId, {String? title}) async {
    debugPrint('DEBUG: Duplicating chat: $chatId');
    final response = await _dio.post(
      '/api/v1/chats/$chatId/duplicate',
      data: {if (title != null) 'title': title},
    );
    return _parseFullOpenWebUIChat(response.data as Map<String, dynamic>);
  }

  /// Get recent chats with activity
  Future<List<Conversation>> getRecentChats({int limit = 10, int? days}) async {
    debugPrint('DEBUG: Fetching recent chats (limit: $limit)');
    final queryParams = <String, dynamic>{'limit': limit};
    if (days != null) queryParams['days'] = days;

    final response = await _dio.get(
      '/api/v1/chats/recent',
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.map((chatData) => _parseOpenWebUIChat(chatData)).toList();
    }
    return [];
  }

  /// Get chat history with pagination and filters
  Future<Map<String, dynamic>> getChatHistory({
    int? limit,
    int? offset,
    String? cursor,
    String? model,
    String? tag,
    bool? pinned,
    bool? archived,
    String? sortBy,
    String? sortOrder,
  }) async {
    debugPrint('DEBUG: Fetching chat history with filters');
    final queryParams = <String, dynamic>{};
    if (limit != null) queryParams['limit'] = limit;
    if (offset != null) queryParams['offset'] = offset;
    if (cursor != null) queryParams['cursor'] = cursor;
    if (model != null) queryParams['model'] = model;
    if (tag != null) queryParams['tag'] = tag;
    if (pinned != null) queryParams['pinned'] = pinned;
    if (archived != null) queryParams['archived'] = archived;
    if (sortBy != null) queryParams['sort_by'] = sortBy;
    if (sortOrder != null) queryParams['sort_order'] = sortOrder;

    final response = await _dio.get(
      '/api/v1/chats/history',
      queryParameters: queryParams,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Batch operations on multiple chats
  Future<Map<String, dynamic>> batchChatOperation({
    required List<String> chatIds,
    required String
    operation, // 'archive', 'delete', 'pin', 'unpin', 'move_to_folder'
    Map<String, dynamic>? params,
  }) async {
    debugPrint(
      'DEBUG: Performing batch operation "$operation" on ${chatIds.length} chats',
    );
    final response = await _dio.post(
      '/api/v1/chats/batch',
      data: {
        'chat_ids': chatIds,
        'operation': operation,
        if (params != null) 'params': params,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Get suggested prompts based on chat history
  Future<List<String>> getChatSuggestions({
    String? context,
    int limit = 5,
  }) async {
    debugPrint('DEBUG: Fetching chat suggestions');
    final queryParams = <String, dynamic>{'limit': limit};
    if (context != null) queryParams['context'] = context;

    final response = await _dio.get(
      '/api/v1/chats/suggestions',
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.cast<String>();
    }
    return [];
  }

  /// Get chat templates for quick starts
  Future<List<Map<String, dynamic>>> getChatTemplates({
    String? category,
    String? tag,
  }) async {
    debugPrint('DEBUG: Fetching chat templates');
    final queryParams = <String, dynamic>{};
    if (category != null) queryParams['category'] = category;
    if (tag != null) queryParams['tag'] = tag;

    final response = await _dio.get(
      '/api/v1/chats/templates',
      queryParameters: queryParams,
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Create a chat from template
  Future<Conversation> createChatFromTemplate(
    String templateId, {
    Map<String, dynamic>? variables,
    String? title,
  }) async {
    debugPrint('DEBUG: Creating chat from template: $templateId');
    final response = await _dio.post(
      '/api/v1/chats/templates/$templateId/create',
      data: {
        if (variables != null) 'variables': variables,
        if (title != null) 'title': title,
      },
    );
    return _parseFullOpenWebUIChat(response.data as Map<String, dynamic>);
  }

  // ==================== END ADVANCED CHAT FEATURES ====================

  // Legacy streaming wrapper methods removed
}
