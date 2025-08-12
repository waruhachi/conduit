import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';
import '../models/server_config.dart';
import '../models/user.dart';
import '../models/model.dart';
import '../models/conversation.dart';
import '../models/chat_message.dart';
import '../auth/api_auth_interceptor.dart';
import '../validation/validation_interceptor.dart';
import '../error/api_error_interceptor.dart';

class ApiService {
  final Dio _dio;
  final ServerConfig serverConfig;
  late final ApiAuthInterceptor _authInterceptor;
  WebSocketChannel? _wsChannel;
  io.Socket? _socket;

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
        ),
      ) {
    // Initialize the consistent auth interceptor
    _authInterceptor = ApiAuthInterceptor(
      authToken: authToken,
      onAuthTokenInvalid: onAuthTokenInvalid,
      onTokenInvalidated: onTokenInvalidated,
    );

    // Add interceptors in order of priority:
    // 1. Auth interceptor (must be first to add auth headers)
    _dio.interceptors.add(_authInterceptor);

    // 2. Validation interceptor (validates requests/responses against OpenAPI schema)
    final validationInterceptor = ValidationInterceptor(
      enableRequestValidation: true,
      enableResponseValidation: true,
      throwOnValidationError: false, // Don't throw, just log validation issues
      logValidationResults: kDebugMode,
    );
    _dio.interceptors.add(validationInterceptor);

    // 3. Error handling interceptor (transforms errors to standardized format)
    _dio.interceptors.add(
      ApiErrorInterceptor(
        logErrors: kDebugMode,
        throwApiErrors: true, // Transform DioExceptions to include ApiError
      ),
    );

    // 4. Logging interceptor for debugging (should be last to see final requests/responses)
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: false, // Don't log response bodies to reduce noise
          requestHeader: true,
          responseHeader: false,
          error: true,
          logPrint: (obj) => debugPrint('API: $obj'),
        ),
      );
    }

    // Initialize validation interceptor asynchronously
    validationInterceptor.initialize().catchError((error) {
      debugPrint(
        'ApiService: Failed to initialize validation interceptor: $error',
      );
    });
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
          debugPrint('DEBUG: Error checking models: $e');
          result['modelsAvailable'] = false;
        }
      }
    } catch (e) {
      result['error'] = e.toString();
      debugPrint('DEBUG: Server status check failed: $e');
    }

    return result;
  }

  // Authentication
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      debugPrint(
        'DEBUG: Attempting login to ${serverConfig.url}/api/v1/auths/signin',
      );
      final response = await _dio.post(
        '/api/v1/auths/signin',
        data: {'email': username, 'password': password},
      );
      debugPrint('DEBUG: Login successful, status: ${response.statusCode}');
      return response.data;
    } catch (e) {
      if (e is DioException) {
        debugPrint('DEBUG: Login DioException: ${e.type}');
        debugPrint('DEBUG: Response status: ${e.response?.statusCode}');
        debugPrint('DEBUG: Response headers: ${e.response?.headers}');
        debugPrint('DEBUG: Request URL: ${e.requestOptions.uri}');

        // Handle specific redirect cases
        if (e.response?.statusCode == 307 || e.response?.statusCode == 308) {
          final location = e.response?.headers.value('location');
          if (location != null) {
            debugPrint('DEBUG: Server redirecting to: $location');
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
    debugPrint('DEBUG: /api/v1/auths/ response: ${jsonEncode(response.data)}');
    return User.fromJson(response.data);
  }

  // Models
  Future<List<Model>> getModels() async {
    final response = await _dio.get('/api/models');
    debugPrint('DEBUG: /api/models raw response: ${jsonEncode(response.data)}');

    // Handle different response formats
    List<dynamic> models;
    if (response.data is Map && response.data['data'] != null) {
      // Response is wrapped in a 'data' field
      models = response.data['data'] as List;
    } else if (response.data is List) {
      // Response is a direct array
      models = response.data as List;
    } else {
      debugPrint('ERROR: Unexpected models response format');
      return [];
    }

    debugPrint('DEBUG: Found ${models.length} models');
    return models.map((m) => Model.fromJson(m)).toList();
  }

  // Get default model configuration from OpenWebUI user settings
  Future<String?> getDefaultModel() async {
    try {
      debugPrint('DEBUG: Fetching default model from user settings');
      final response = await _dio.get('/api/v1/users/user/settings');

      debugPrint('DEBUG: User settings response: ${jsonEncode(response.data)}');

      final settings = response.data as Map<String, dynamic>;

      // Extract default model from ui.models array
      final ui = settings['ui'] as Map<String, dynamic>?;
      if (ui != null) {
        final models = ui['models'] as List?;
        if (models != null && models.isNotEmpty) {
          // Return the first model in the user's preferred models list
          final defaultModel = models.first.toString();
          debugPrint(
            'DEBUG: Found default model from user settings: $defaultModel',
          );
          return defaultModel;
        }
      }

      debugPrint('DEBUG: No default model found in user settings');
      return null;
    } catch (e) {
      debugPrint('DEBUG: Error fetching default model from user settings: $e');
      // Fall back to trying the old endpoint
      try {
        debugPrint('DEBUG: Falling back to configs/models endpoint');
        final response = await _dio.get('/api/v1/configs/models');
        final config = response.data as Map<String, dynamic>;

        final defaultModel =
            config['DEFAULT_MODELS'] as String? ??
            config['default_models'] as String? ??
            config['default_model'] as String?;

        if (defaultModel != null && defaultModel.isNotEmpty) {
          debugPrint('DEBUG: Found default model from fallback: $defaultModel');
          return defaultModel;
        }
      } catch (fallbackError) {
        debugPrint('DEBUG: Fallback also failed: $fallbackError');
      }

      return null;
    }
  }

  // Conversations - Updated to use correct OpenWebUI API
  Future<List<Conversation>> getConversations({int? limit, int? skip}) async {
    debugPrint('DEBUG: Fetching conversations from OpenWebUI API');
    debugPrint('DEBUG: Making request to ${serverConfig.url}/api/v1/chats/');
    debugPrint('DEBUG: Auth token present: ${authToken != null}');

    // Fetch regular, pinned, and archived conversations
    final regularResponse = await _dio.get(
      '/api/v1/chats/',
      queryParameters: {
        if (limit != null && limit > 0)
          'page': ((skip ?? 0) / limit)
              .floor(), // OpenWebUI uses page-based pagination with proper bounds checking
      },
    );

    final pinnedResponse = await _dio.get('/api/v1/chats/pinned');
    final archivedResponse = await _dio.get('/api/v1/chats/all/archived');

    debugPrint('DEBUG: Regular response status: ${regularResponse.statusCode}');
    debugPrint('DEBUG: Pinned response status: ${pinnedResponse.statusCode}');
    debugPrint(
      'DEBUG: Archived response status: ${archivedResponse.statusCode}',
    );

    if (regularResponse.data is! List) {
      throw Exception(
        'Expected array of chats, got ${regularResponse.data.runtimeType}',
      );
    }

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

    final regularChatList = regularResponse.data as List;
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
    debugPrint('DEBUG: Fetching individual chat: $id');
    final response = await _dio.get('/api/v1/chats/$id');

    debugPrint('DEBUG: Chat response: ${response.data}');

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

    // Try multiple locations for messages - prefer list format to avoid duplication
    List? messagesList;

    if (chatObject != null) {
      // Check for messages in chat.messages (list format) - PREFERRED
      if (chatObject['messages'] != null) {
        messagesList = chatObject['messages'] as List;
        debugPrint(
          'DEBUG: Found ${messagesList.length} messages in chat.messages',
        );
      } else {
        // Fallback: Check for messages in chat.history.messages (map format)
        final history = chatObject['history'] as Map<String, dynamic>?;
        if (history != null && history['messages'] != null) {
          final messagesMap = history['messages'] as Map<String, dynamic>;
          debugPrint(
            'DEBUG: Found ${messagesMap.length} messages in chat.history.messages (converting to list)',
          );
          
          // Convert map to list format to use common parsing logic
          messagesList = [];
          for (final entry in messagesMap.entries) {
            final msgData = Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
            msgData['id'] = entry.key; // Use the key as the message ID
            messagesList.add(msgData);
          }
        }
      }
    } else if (chatData['messages'] != null) {
      messagesList = chatData['messages'] as List;
      debugPrint(
        'DEBUG: Found ${messagesList.length} messages in top-level messages',
      );
    }

    // Parse messages from list format only (avoiding duplication)
    if (messagesList != null) {
      for (final msgData in messagesList) {
        try {
          debugPrint(
            'DEBUG: Parsing message: ${msgData['id']} - role: ${msgData['role']} - content length: ${msgData['content']?.toString().length ?? 0}',
          );
          // Convert OpenWebUI message format to our ChatMessage format
          final message = _parseOpenWebUIMessage(msgData);
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
      pinned: pinned,
      archived: archived,
      shareId: shareId,
      folderId: folderId,
      messages: messages,
    );
  }

  // Parse OpenWebUI message format to our ChatMessage format
  ChatMessage _parseOpenWebUIMessage(Map<String, dynamic> msgData) {
    // OpenWebUI message format may vary, but typically:
    // { "role": "user|assistant", "content": "text", ... }

    // Create a single UUID instance to reuse
    const uuid = Uuid();

    // Handle content that could be either String or List (for content arrays)
    final content = msgData['content'];
    String contentString;
    if (content is List) {
      // For content arrays, extract the text content
      final textContent = content.firstWhere(
        (item) => item is Map && item['type'] == 'text',
        orElse: () => {'text': ''},
      );
      contentString = textContent['text'] as String? ?? '';
    } else {
      contentString = content as String? ?? '';
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

    return ChatMessage(
      id: msgData['id']?.toString() ?? uuid.v4(),
      role: role,
      content: contentString,
      timestamp: _parseTimestamp(msgData['timestamp']),
      model: msgData['model'] as String?,
    );
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
    debugPrint('DEBUG: Request data: ${chatData}');

    final response = await _dio.post('/api/v1/chats/new', data: chatData);

    debugPrint('DEBUG: Create conversation response status: ${response.statusCode}');
    debugPrint('DEBUG: Create conversation response data: ${response.data}');

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
      messagesMap[messageId] = {
        'id': messageId,
        'parentId': previousId,
        'childrenIds': <String>[],
        'role': msg.role,
        'content': msg.content,
        'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
        if (msg.role == 'assistant' && msg.model != null) 'model': msg.model,
        if (msg.role == 'assistant' && msg.model != null) 'modelName': msg.model,
        if (msg.role == 'assistant') 'modelIdx': 0,
        if (msg.role == 'assistant') 'done': true,
        if (msg.role == 'user' && model != null) 'models': [model],
      };
      
      // Update parent's childrenIds
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
        if (msg.role == 'assistant' && msg.model != null) 'model': msg.model,
        if (msg.role == 'assistant' && msg.model != null) 'modelName': msg.model,
        if (msg.role == 'assistant') 'modelIdx': 0,
        if (msg.role == 'assistant') 'done': true,
        if (msg.role == 'user' && model != null) 'models': [model],
      });
      
      previousId = messageId;
      currentId = messageId;
    }

    // Create the chat data structure matching OpenWebUI format exactly
    final chatData = {
      'chat': {
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
    final response = await _dio.post(
      '/api/v1/chats/$conversationId',
      data: chatData,
    );

    debugPrint('DEBUG: Update conversation response: ${response.data}');
  }

  Future<void> updateConversation(
    String id, {
    String? title,
    String? systemPrompt,
  }) async {
    await _dio.put(
      '/api/v1/chats/$id',
      data: {
        if (title != null) 'title': title,
        if (systemPrompt != null) 'system': systemPrompt,
      },
    );
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
    await _dio.post('/api/v1/users/user/settings', data: settings);
  }

  // Server Banners
  Future<List<Map<String, dynamic>>> getBanners() async {
    debugPrint('DEBUG: Fetching server banners');
    final response = await _dio.get('/api/v1/configs/banners');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
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
    debugPrint('DEBUG: Fetching folders');
    final response = await _dio.get('/api/v1/folders/');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
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
    await _dio.put(
      '/api/v1/folders/$id',
      data: {
        if (name != null) 'name': name,
        if (parentId != null) 'parent_id': parentId,
      },
    );
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
    final response = await _dio.get('/api/v1/files/$fileId/content');
    return response.data as String;
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

      debugPrint('DEBUG: Web search response status: ${response.statusCode}');
      debugPrint(
        'DEBUG: Web search response type: ${response.data.runtimeType}',
      );
      debugPrint('DEBUG: Web search response data: ${response.data}');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DEBUG: Web search API error: $e');
      if (e is DioException) {
        debugPrint('DEBUG: Web search error response: ${e.response?.data}');
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
        debugPrint('DEBUG: Model details for $modelId: $modelData');
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
        debugPrint('DEBUG: Raw title response: ${response.data}');

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
    debugPrint('DEBUG: Sending chat completed notification (optional endpoint)');
    
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
        'timestamp': msg['timestamp'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
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

    // Include the message ID at the top level - server expects this
    final requestData = {
      'id': messageId,  // The server expects the assistant message ID here
      'chat_id': chatId,
      'model': model,
      'messages': formattedMessages,
      // Don't include model_item as it might not be expected
    };

    try {
      final response = await _dio.post(
        '/api/chat/completed',
        data: requestData,
      );
      debugPrint('DEBUG: Chat completed response: ${response.statusCode}');
    } catch (e) {
      // This is a non-critical endpoint - main sync happens via /api/v1/chats/{id}
      debugPrint('DEBUG: Chat completed endpoint not available or failed (non-critical): $e');
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
      debugPrint('DEBUG: Collection query response data: ${response.data}');

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
      debugPrint('DEBUG: Retrieval config response data: ${response.data}');

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
    debugPrint(
      'DEBUG: Generating speech for text: ${text.substring(0, 50)}...',
    );
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

  Future<String> transcribeAudio(
    List<int> audioData, {
    String? language,
  }) async {
    // Normalize language to primary ISO 639-1 (e.g., en-US -> en) per server accepted list
    String? normalizedLang;
    if (language != null && language.isNotEmpty) {
      normalizedLang = language.split(RegExp('[-_]')).first.toLowerCase();
    }

    debugPrint(
      'DEBUG: Transcribing audio data: bytes=${audioData.length}, language=${normalizedLang ?? 'null'}',
    );

    FormData buildForm(String? lang) {
      final Map<String, dynamic> formMap = {
        'file': MultipartFile.fromBytes(
          audioData,
          filename: 'audio.wav',
          contentType: MediaType.parse('audio/wav'),
        ),
      };
      if (lang != null && lang.isNotEmpty) {
        formMap['language'] = lang;
      }
      return FormData.fromMap(formMap);
    }

    var formData = buildForm(normalizedLang);
    try {
      final response = await _dio.post(
        '/api/v1/audio/transcriptions',
        data: formData,
        options: Options(headers: {'Accept': 'application/json'}),
      );
      final data = response.data;
      debugPrint(
        'DEBUG: Transcription response status: ${response.statusCode}',
      );
      debugPrint('DEBUG: Transcription response data: $data');
      if (data is String) return data;
      if (data is Map<String, dynamic>) {
        final text = data['text'] ?? data['transcription'] ?? data['result'];
        if (text is String) return text;
        if (data['data'] is Map && (data['data']['text'] is String)) {
          return data['data']['text'] as String;
        }
      }
      return '';
    } catch (e) {
      debugPrint('DEBUG: Transcription API error: $e');
      // If server complains about invalid language code, retry without language
      try {
        if (e is DioException) {
          final data = e.response?.data;
          final msg = data is Map<String, dynamic>
              ? data.toString()
              : data?.toString() ?? '';
          if (msg.contains("not a valid language code")) {
            debugPrint('DEBUG: Retrying transcription without language');
            final retryResponse = await _dio.post(
              '/api/v1/audio/transcriptions',
              data: buildForm(null),
              options: Options(headers: {'Accept': 'application/json'}),
            );
            final rdata = retryResponse.data;
            debugPrint(
              'DEBUG: Transcription retry status: ${retryResponse.statusCode}',
            );
            debugPrint('DEBUG: Transcription retry data: $rdata');
            if (rdata is String) return rdata;
            if (rdata is Map<String, dynamic>) {
              final text =
                  rdata['text'] ?? rdata['transcription'] ?? rdata['result'];
              if (text is String) return text;
              if (rdata['data'] is Map && (rdata['data']['text'] is String)) {
                return rdata['data']['text'] as String;
              }
            }
            return '';
          }
        }
      } catch (e2) {
        debugPrint('DEBUG: Transcription retry error: $e2');
      }
      rethrow;
    }
  }

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

  Future<Map<String, dynamic>> generateImage({
    required String prompt,
    String? model,
    int? width,
    int? height,
    int? steps,
    double? guidance,
  }) async {
    debugPrint(
      'DEBUG: Generating image with prompt: ${prompt.substring(0, 50)}...',
    );
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
    return response.data as Map<String, dynamic>;
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
  String _getCurrentWeekday() {
    final weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[DateTime.now().weekday - 1];
  }

  // Returns a record with (stream, messageId, sessionId)
  ({Stream<String> stream, String messageId, String sessionId})
  sendMessageDirect({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? conversationId,
    List<Map<String, dynamic>>? tools,
    bool enableWebSearch = false,
    Map<String, dynamic>? modelItem,
  }) {
    final streamController = StreamController<String>();

    // Generate unique IDs
    final messageId = const Uuid().v4();
    final sessionId = const Uuid().v4().substring(0, 20);

    // Check if this is a Gemini model that requires special handling
    final isGeminiModel = model.toLowerCase().contains('gemini');
    debugPrint('DEBUG: Is Gemini model: $isGeminiModel');

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

    // Build request data (exactly like OpenWebUI)
    final data = {
      'stream': true,
      'model': model,
      'messages': processedMessages,
      'params': {},
      'tool_servers': [],
      'features': {
        'image_generation': false,
        'code_interpreter': false,
        'web_search': enableWebSearch,
        'memory': false,
      },
      'variables': {
        '{{USER_NAME}}': 'User',
        '{{USER_LOCATION}}': 'Unknown',
        '{{CURRENT_DATETIME}}': DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' '),
        '{{CURRENT_DATE}}': DateTime.now().toIso8601String().substring(0, 10),
        '{{CURRENT_TIME}}': DateTime.now().toIso8601String().substring(11, 19),
        '{{CURRENT_WEEKDAY}}': _getCurrentWeekday(),
        '{{CURRENT_TIMEZONE}}': DateTime.now().timeZoneName,
        '{{USER_LANGUAGE}}': 'en-US',
      },
      if (modelItem != null) 'model_item': modelItem,
      if (conversationId != null) 'chat_id': conversationId,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      if (allFiles.isNotEmpty) 'files': allFiles,
    };

    debugPrint('DEBUG: Starting SSE streaming request');
    debugPrint('DEBUG: Model: $model');
    debugPrint('DEBUG: Message count: ${processedMessages.length}');

    // Use SSE streaming exactly like OpenWebUI frontend
    _streamChatCompletion(data, streamController, messageId);

    return (
      stream: streamController.stream,
      messageId: messageId,
      sessionId: sessionId,
    );
  }

  // SSE streaming implementation that matches OpenWebUI exactly
  void _streamChatCompletion(
    Map<String, dynamic> data,
    StreamController<String> streamController,
    String messageId,
  ) async {
    try {
      debugPrint('DEBUG: Making SSE request to /api/chat/completions');

      // Make the request with proper SSE headers (exactly like OpenWebUI)
      final response = await _dio.post(
        '/api/chat/completions',
        data: data,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
          },
          // Disable response timeout to allow streaming
          receiveTimeout: null,
        ),
      );

      debugPrint(
        'DEBUG: SSE response received, status: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'HTTP ${response.statusCode}: Failed to start streaming',
        );
      }

      // Process the SSE stream exactly like OpenWebUI frontend
      final stream = response.data.stream as Stream<List<int>>;
      String buffer = '';

      await for (final chunk in stream) {
        try {
          // Decode chunk to string
          final chunkStr = utf8.decode(chunk);
          buffer += chunkStr;

          // Process complete lines (SSE format)
          final lines = buffer.split('\n');
          buffer = lines.removeLast(); // Keep incomplete line in buffer

          for (final line in lines) {
            final trimmedLine = line.trim();
            if (trimmedLine.isEmpty) continue;

            debugPrint('DEBUG: SSE line: $trimmedLine');

            if (trimmedLine.startsWith('data: ')) {
              final jsonStr = trimmedLine.substring(6); // Remove "data: "

              if (jsonStr == '[DONE]') {
                debugPrint('DEBUG: SSE stream finished with [DONE]');
                streamController.close();
                return;
              }

              try {
                final json = jsonDecode(jsonStr) as Map<String, dynamic>;
                debugPrint('DEBUG: SSE JSON: $json');

                // Process exactly like OpenWebUI
                if (json.containsKey('choices')) {
                  final choices = json['choices'] as List?;
                  if (choices != null && choices.isNotEmpty) {
                    final choice = choices[0] as Map<String, dynamic>;

                    if (choice.containsKey('delta')) {
                      final delta = choice['delta'] as Map<String, dynamic>;

                      // Handle content streaming (word by word)
                      if (delta.containsKey('content')) {
                        final content = delta['content'] as String?;
                        if (content != null && content.isNotEmpty) {
                          debugPrint('DEBUG: Adding content chunk: "$content"');
                          streamController.add(content);
                        }
                      }

                      // Handle function calls
                      if (delta.containsKey('tool_calls')) {
                        final toolCalls = delta['tool_calls'] as List?;
                        if (toolCalls != null && toolCalls.isNotEmpty) {
                          debugPrint('DEBUG: Tool calls received: $toolCalls');
                          // Handle tool calls if needed
                        }
                      }
                    }

                    // Handle finish reason
                    if (choice.containsKey('finish_reason')) {
                      final finishReason = choice['finish_reason'];
                      if (finishReason != null) {
                        debugPrint(
                          'DEBUG: Stream finished with reason: $finishReason',
                        );
                        streamController.close();
                        return;
                      }
                    }
                  }
                } else if (json.containsKey('error')) {
                  // Handle server errors
                  final error = json['error'];
                  debugPrint('DEBUG: SSE error: $error');
                  streamController.addError('Server error: $error');
                  return;
                } else {
                  debugPrint('DEBUG: Unknown SSE JSON format: $json');
                }
              } catch (e) {
                debugPrint('DEBUG: Error parsing SSE JSON "$jsonStr": $e');
                // Continue processing other lines
              }
            } else if (trimmedLine.startsWith('event: ') ||
                trimmedLine.startsWith('id: ') ||
                trimmedLine.startsWith('retry: ')) {
              // Handle other SSE fields (ignore for now)
              debugPrint('DEBUG: SSE metadata: $trimmedLine');
            } else {
              debugPrint('DEBUG: Unknown SSE line format: $trimmedLine');
            }
          }
        } catch (e) {
          debugPrint('DEBUG: Error processing SSE chunk: $e');
          // Continue processing
        }
      }

      // Stream ended without [DONE] marker
      debugPrint('DEBUG: SSE stream ended unexpectedly');
      streamController.close();
    } catch (e) {
      debugPrint('DEBUG: SSE streaming error: $e');
      streamController.addError(e);
    }
  }

  // Initialize Socket.IO connection
  Future<void> _initializeSocket() async {
    if (_socket != null && _socket!.connected) {
      return; // Already connected
    }

    try {
      debugPrint(
        'DEBUG: Initializing Socket.IO connection to ${serverConfig.url}',
      );

      _socket = io.io(
        serverConfig.url,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setPath('/ws/socket.io')
            .setAuth({'token': _authInterceptor.authToken})
            .build(),
      );

      _socket!.onConnect((_) {
        debugPrint('DEBUG: Socket.IO connected with ID: ${_socket!.id}');

        // Emit user-join event with auth token
        _socket!.emit('user-join', {
          'auth': {'token': _authInterceptor.authToken},
        });
      });

      _socket!.onDisconnect((_) {
        debugPrint('DEBUG: Socket.IO disconnected');
      });

      _socket!.onError((error) {
        debugPrint('DEBUG: Socket.IO error: $error');
      });

      _socket!.onReconnect((_) {
        debugPrint('DEBUG: Socket.IO reconnected');
      });
    } catch (e) {
      debugPrint('DEBUG: Failed to initialize Socket.IO: $e');
    }
  }

  // Socket.IO streaming method that listens to real-time events
  ({Stream<String> stream, String messageId, String sessionId})
  sendMessageWithSocketIO({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? conversationId,
    List<Map<String, dynamic>>? tools,
    bool enableWebSearch = false,
    Map<String, dynamic>? modelItem,
  }) {
    final streamController = StreamController<String>();

    // Generate unique IDs
    final messageId = const Uuid().v4();
    final sessionId = const Uuid().v4().substring(0, 20);

    debugPrint('DEBUG: Starting Socket.IO streaming for message: $messageId');

    // Initialize socket connection
    _initializeSocket()
        .then((_) {
          _handleSocketIOStreamingResponse(messageId, streamController);

          // Send the chat completion request via API
          // This will trigger the server to emit Socket.IO events
          _sendChatCompletionForSocketIO(
            messages: messages,
            model: model,
            conversationId: conversationId,
            messageId: messageId,
            tools: tools,
            enableWebSearch: enableWebSearch,
            modelItem: modelItem,
          );
        })
        .catchError((error) {
          debugPrint('DEBUG: Socket.IO initialization failed: $error');
          streamController.addError('Failed to initialize Socket.IO: $error');
        });

    return (
      stream: streamController.stream,
      messageId: messageId,
      sessionId: sessionId,
    );
  }

  // Handle Socket.IO real-time streaming events
  void _handleSocketIOStreamingResponse(
    String messageId,
    StreamController<String> streamController,
  ) async {
    // Check if socket is available
    if (_socket == null || !_socket!.connected) {
      debugPrint(
        'DEBUG: Socket not available for real-time streaming, falling back to polling',
      );
      streamController.addError('Socket.IO not connected');
      streamController.close();
      return;
    }

    debugPrint(
      'DEBUG: Setting up Socket.IO real-time streaming for message: $messageId',
    );
    bool streamCompleted = false;
    Timer? timeoutTimer;

    // Set up timeout to prevent hanging
    timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (!streamCompleted) {
        debugPrint(
          'DEBUG: Socket.IO streaming timeout for message: $messageId',
        );
        streamCompleted = true;
        streamController.addError('Streaming timeout');
        streamController.close();
      }
    });

    // Set up listener for chat-events from the server (OpenWebUI pattern)
    void handleChatEvent(dynamic data) {
      try {
        if (streamCompleted) return;

        debugPrint('DEBUG: Received Socket.IO chat event: $data');

        final Map<String, dynamic> eventData = data is Map<String, dynamic>
            ? data
            : (data as Map).cast<String, dynamic>();

        final chatId = eventData['chat_id']?.toString();
        final eventMessageId = eventData['message_id']?.toString();
        final eventDetails = eventData['data'] as Map<String, dynamic>? ?? {};

        final eventType = eventDetails['type']?.toString();
        final eventDataContent =
            eventDetails['data'] as Map<String, dynamic>? ?? {};

        debugPrint(
          'DEBUG: Event type: $eventType, chat_id: $chatId, message_id: $eventMessageId',
        );

        // Only process events for our message
        if (eventMessageId != messageId && eventMessageId != null) {
          return;
        }

        switch (eventType) {
          case 'message':
            // Incremental content streaming - add the new chunk
            final content = eventDataContent['content']?.toString() ?? '';
            if (content.isNotEmpty) {
              debugPrint('DEBUG: Adding Socket.IO content chunk: "$content"');
              streamController.add(content);
            }
            break;

          case 'replace':
            // Full content replacement - replace entire content
            final content = eventDataContent['content']?.toString() ?? '';
            debugPrint('DEBUG: Replacing Socket.IO content: "$content"');
            streamController.add('__REPLACE_CONTENT__$content');
            break;

          case 'status':
            // Status update (like "generating", "thinking", etc.)
            final status = eventDataContent['status']?.toString() ?? '';
            if (status.isNotEmpty) {
              debugPrint('DEBUG: Socket.IO Status update: $status');
              // Optionally emit status as a special event
              streamController.add('__STATUS__$status');
            }
            break;

          case 'error':
            // Error occurred during generation
            final error =
                eventDataContent['error']?.toString() ?? 'Unknown error';
            debugPrint('DEBUG: Socket.IO streaming error: $error');
            streamCompleted = true;
            timeoutTimer?.cancel();
            _socket?.off('chat-events', handleChatEvent);
            streamController.addError(error);
            streamController.close();
            break;

          case 'done':
            // Streaming completed successfully
            debugPrint(
              'DEBUG: Socket.IO streaming completed for message: $messageId',
            );
            streamCompleted = true;
            timeoutTimer?.cancel();
            _socket?.off('chat-events', handleChatEvent);
            streamController.close();
            break;

          default:
            debugPrint('DEBUG: Unknown Socket.IO event type: $eventType');
            break;
        }
      } catch (e, stackTrace) {
        debugPrint('DEBUG: Error handling Socket.IO event: $e');
        debugPrint('DEBUG: Stack trace: $stackTrace');
        if (!streamCompleted) {
          streamCompleted = true;
          timeoutTimer?.cancel();
          _socket?.off('chat-events', handleChatEvent);
          streamController.addError('Error processing streaming event: $e');
          streamController.close();
        }
      }
    }

    // Listen for chat-events
    _socket!.on('chat-events', handleChatEvent);

    // Clean up when stream is closed
    streamController.onCancel = () {
      debugPrint(
        'DEBUG: Cleaning up Socket.IO listeners for message: $messageId',
      );
      streamCompleted = true;
      timeoutTimer?.cancel();
      _socket?.off('chat-events', handleChatEvent);
    };
  }

  // Send chat completion request that will trigger Socket.IO events
  Future<void> _sendChatCompletionForSocketIO({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? conversationId,
    required String messageId,
    List<Map<String, dynamic>>? tools,
    bool enableWebSearch = false,
    Map<String, dynamic>? modelItem,
  }) async {
    try {
      // Process messages same as SSE version
      final processedMessages = messages.map((message) {
        final role = message['role'] as String;
        final content = message['content'];
        final files = message['files'] as List<Map<String, dynamic>>?;

        final isContentArray = content is List;
        final hasImages =
            files?.any((file) => file['type'] == 'image') ?? false;

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

      // Create request data
      final data = {
        'model': model,
        'messages': processedMessages,
        'stream': true, // Enable streaming
        'message_id': messageId, // Include message ID for Socket.IO events
        if (conversationId != null) 'chat_id': conversationId,
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        if (allFiles.isNotEmpty) 'files': allFiles,
        if (enableWebSearch) 'web_search': enableWebSearch,
        'session_id': _socket?.id, // Include Socket.IO session ID
      };

      debugPrint('DEBUG: Sending Socket.IO-enabled chat completion request');
      debugPrint('DEBUG: Message ID: $messageId');
      debugPrint('DEBUG: Socket ID: ${_socket?.id}');

      // Send the request - server should emit Socket.IO events in response
      await _dio.post('/api/chat/completions', data: data);
    } catch (e) {
      debugPrint('DEBUG: Error sending Socket.IO chat completion request: $e');
      rethrow;
    }
  }

  // Enhanced SSE streaming method that matches OpenWebUI implementation
  ({Stream<String> stream, String messageId, String sessionId})
  sendMessageWithImprovedSSE({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? conversationId,
    List<Map<String, dynamic>>? tools,
    bool enableWebSearch = false,
    Map<String, dynamic>? modelItem,
  }) {
    final streamController = StreamController<String>();

    // Generate a unique message ID and session ID for the request
    final messageId = const Uuid().v4();
    final sessionId = const Uuid().v4().substring(0, 20); // Match WebUI format

    // Check if this is a Gemini model that requires special handling
    final isGeminiModel = model.toLowerCase().contains('gemini');
    debugPrint('DEBUG: Is Gemini model in API: $isGeminiModel');
    debugPrint('DEBUG: Model ID in API: $model');

    // Process messages to match OpenWebUI format
    final processedMessages = messages.map((message) {
      final role = message['role'] as String;
      final content = message['content'];
      final files = message['files'] as List<Map<String, dynamic>>?;

      // Check if content is already a List (content array format)
      final isContentArray = content is List;

      // Check if this message has image files
      final hasImages = files?.any((file) => file['type'] == 'image') ?? false;

      if (isContentArray) {
        // Content is already in the correct array format
        return {'role': role, 'content': content};
      } else if (hasImages && role == 'user') {
        // For user messages with images, use OpenWebUI's content array format
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
        // For messages without images or non-user messages, use regular format
        final contentText = content is String ? content : '';
        return {'role': role, 'content': contentText};
      }
    }).toList();

    // Separate files from messages (OpenWebUI format)
    final allFiles = <Map<String, dynamic>>[];
    for (final message in messages) {
      final files = message['files'] as List<Map<String, dynamic>>?;
      if (files != null) {
        // Only include non-image files in the files array
        final nonImageFiles = files
            .where((file) => file['type'] != 'image')
            .toList();
        allFiles.addAll(nonImageFiles);
      }
    }

    // Prepare the request in OpenWebUI format
    final data = {
      'stream': true,
      'model': model,
      'messages': processedMessages,
      'params': {
        'temperature': 0.7,
        'top_p': 1.0,
        'max_tokens': 4096,
        'stream_response': true,
      },
      'files': allFiles.isNotEmpty ? allFiles : null,
      'tool_servers': [],
      'features': {
        'image_generation': false,
        'code_interpreter': false,
        'web_search': enableWebSearch,
        'memory': false,
      },
      'variables': {
        '{{USER_NAME}}': 'User',
        '{{USER_LOCATION}}': 'Unknown',
        '{{CURRENT_DATETIME}}': DateTime.now().toString().substring(0, 19),
        '{{CURRENT_DATE}}': DateTime.now().toString().substring(0, 10),
        '{{CURRENT_TIME}}': DateTime.now().toString().substring(11, 19),
        '{{CURRENT_WEEKDAY}}': _getCurrentWeekday(),
        '{{CURRENT_TIMEZONE}}': DateTime.now().timeZoneName,
        '{{USER_LANGUAGE}}': 'en-US',
      },
      if (conversationId != null) 'chat_id': conversationId,
      if (modelItem != null) 'model_item': modelItem,
      'background_tasks': {
        'title_generation': true,
        'tags_generation': true,
        'follow_up_generation': true,
      },
      'session_id': sessionId,
      'id': messageId,
    };

    debugPrint('DEBUG: Sending chat completion request:');
    debugPrint('DEBUG: Model: $model');
    debugPrint('DEBUG: Messages count: ${processedMessages.length}');
    debugPrint('DEBUG: Files count: ${allFiles.length}');
    debugPrint('DEBUG: Web search enabled: $enableWebSearch');

    // Use Server-Sent Events for streaming
    const url = '/api/chat/completions';

    _dio
        .post(
          url,
          data: data,
          options: Options(
            responseType: ResponseType.stream,
            headers: {'Accept': 'text/event-stream'},
            // Increase timeout for streaming responses
            receiveTimeout: const Duration(minutes: 5),
          ),
        )
        .then((response) {
          final stream = response.data.stream;

          stream.listen(
            (data) {
              final decodedData = utf8.decode(data);
              debugPrint('DEBUG: SSE Raw data: $decodedData');
              final lines = decodedData.split('\n');
              for (final line in lines) {
                if (line.startsWith('data: ')) {
                  final jsonStr = line.substring(6);
                  debugPrint('DEBUG: SSE JSON: $jsonStr');
                  if (jsonStr == '[DONE]') {
                    debugPrint('DEBUG: Stream finished with [DONE]');
                    streamController.close();
                    return;
                  }
                  try {
                    final json = jsonDecode(jsonStr);
                    if (json is Map<String, dynamic>) {
                      final choices = json['choices'];
                      if (choices is List && choices.isNotEmpty) {
                        final delta = choices[0]['delta'];
                        if (delta is Map<String, dynamic>) {
                          // Handle regular content
                          final content = delta['content'];
                          if (content is String && content.isNotEmpty) {
                            debugPrint(
                              'DEBUG: Adding content chunk: "$content"',
                            );
                            streamController.add(content);
                          }

                          // Handle function calls
                          final toolCalls = delta['tool_calls'];
                          if (toolCalls is List && toolCalls.isNotEmpty) {
                            for (final toolCall in toolCalls) {
                              if (toolCall is Map<String, dynamic>) {
                                final function = toolCall['function'];
                                if (function is Map<String, dynamic>) {
                                  final name = function['name'];
                                  final arguments = function['arguments'];
                                  debugPrint(
                                    'DEBUG: Function call - Name: $name, Arguments: $arguments',
                                  );
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('DEBUG: Error parsing SSE data: $e');
                  }
                }
              }
            },
            onError: (error) {
              debugPrint('DEBUG: Stream error: $error');
              debugPrint('DEBUG: Stream error type: ${error.runtimeType}');
              streamController.addError(error);
            },
            onDone: () {
              debugPrint('DEBUG: Stream completed');
              streamController.close();
            },
          );
        })
        .catchError((error) {
          debugPrint('DEBUG: Request error: $error');
          streamController.addError(error);
        });

    return (
      stream: streamController.stream,
      messageId: messageId,
      sessionId: sessionId,
    );
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

      debugPrint('DEBUG: Upload response status: ${response.statusCode}');
      debugPrint('DEBUG: Upload response data: ${response.data}');

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
        debugPrint('   Response type: ${response.data.runtimeType}');
        if (response.data is List) {
          debugPrint('   Array length: ${(response.data as List).length}');
        } else if (response.data is Map) {
          debugPrint('   Object keys: ${(response.data as Map).keys}');
        }
        debugPrint(
          '   Sample data: ${response.data.toString().substring(0, 200)}...',
        );
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

  void dispose() {
    _wsChannel?.sink.close();
    _wsChannel = null;
  }

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
  Future<Map<String, dynamic>> searchChats({
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
    if (query != null) queryParams['q'] = query;
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
    return response.data as Map<String, dynamic>;
  }

  /// Search within messages content
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
    final response = await _dio.post(
      '/api/v1/chats/messages/search',
      data: {
        'query': query,
        if (chatId != null) 'chat_id': chatId,
        if (userId != null) 'user_id': userId,
        if (role != null) 'role': role,
        if (fromDate != null) 'from_date': fromDate.toIso8601String(),
        if (toDate != null) 'to_date': toDate.toIso8601String(),
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
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

  // Enhanced streaming method that uses improved SSE (like OpenWebUI) and Socket.IO fallback
  ({Stream<String> stream, String messageId, String sessionId})
  sendMessageWithStreaming({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? conversationId,
    List<Map<String, dynamic>>? tools,
    bool enableWebSearch = false,
    Map<String, dynamic>? modelItem,
    bool preferSocketIO = false, // Changed default to false - SSE is primary
  }) {
    debugPrint('DEBUG: Starting streaming with SSE as primary method');

    // Use improved SSE streaming as primary method (matches OpenWebUI exactly)
    return sendMessageDirect(
      messages: messages,
      model: model,
      conversationId: conversationId,
      tools: tools,
      enableWebSearch: enableWebSearch,
      modelItem: modelItem,
    );
  }

  // Enhanced streaming method with Socket.IO preference
  ({Stream<String> stream, String messageId, String sessionId})
  sendMessageWithEnhancedStreaming({
    required List<Map<String, dynamic>> messages,
    required String model,
    String? conversationId,
    List<Map<String, dynamic>>? tools,
    bool enableWebSearch = false,
    Map<String, dynamic>? modelItem,
    bool preferSocketIO = true,
  }) {
    debugPrint(
      'DEBUG: Starting enhanced streaming with preferSocketIO: $preferSocketIO',
    );

    // Try Socket.IO first if preferred and available
    if (preferSocketIO) {
      try {
        debugPrint('DEBUG: Attempting Socket.IO streaming...');
        return sendMessageWithSocketIO(
          messages: messages,
          model: model,
          conversationId: conversationId,
          tools: tools,
          enableWebSearch: enableWebSearch,
          modelItem: modelItem,
        );
      } catch (e) {
        debugPrint(
          'DEBUG: Socket.IO streaming failed, falling back to SSE: $e',
        );
        // Fall through to SSE
      }
    }

    // Use SSE streaming as fallback
    debugPrint('DEBUG: Using SSE streaming as fallback');
    return sendMessageDirect(
      messages: messages,
      model: model,
      conversationId: conversationId,
      tools: tools,
      enableWebSearch: enableWebSearch,
      modelItem: modelItem,
    );
  }
}
