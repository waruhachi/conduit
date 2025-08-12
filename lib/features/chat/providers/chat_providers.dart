import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/auth/auth_state_manager.dart';
import '../../../core/utils/stream_chunker.dart';

// Chat messages for current conversation
final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>((ref) {
      return ChatMessagesNotifier(ref);
    });

// Loading state for conversation (used to show chat skeletons during fetch)
final isLoadingConversationProvider = StateProvider<bool>((ref) => false);

class ChatMessagesNotifier extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;
  StreamSubscription? _messageStream;
  ProviderSubscription? _conversationListener;
  final List<StreamSubscription> _subscriptions = [];

  ChatMessagesNotifier(this._ref) : super([]) {
    // Load messages when conversation changes with proper cleanup
    _conversationListener = _ref.listen(activeConversationProvider, (
      previous,
      next,
    ) {
      debugPrint(
        'DEBUG: Active conversation changed - Previous: ${previous?.id}, Next: ${next?.id}',
      );

      // Only react when the conversation actually changes
      if (previous?.id == next?.id) {
        // If same conversation but server updated it (e.g., title/content), sync messages without flicker
        if (previous?.updatedAt != next?.updatedAt) {
          state = next?.messages ?? state;
        }
        return;
      }

      // Cancel any existing message stream when switching conversations
      _cancelMessageStream();

      if (next != null) {
        debugPrint(
          'DEBUG: Loading ${next.messages.length} messages for conversation ${next.id}',
        );
        state = next.messages;
      } else {
        debugPrint('DEBUG: Clearing messages - no active conversation');
        state = [];
      }
    });

    // ProviderSubscription will be cleaned up in dispose method
  }

  void _addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  void _cancelMessageStream() {
    _messageStream?.cancel();
    _messageStream = null;
  }

  void setMessageStream(StreamSubscription stream) {
    _cancelMessageStream();
    _messageStream = stream;

    // Add to tracked subscriptions for comprehensive cleanup
    _addSubscription(stream);
  }

  void addMessage(ChatMessage message) {
    state = [...state, message];
  }

  void removeLastMessage() {
    if (state.isNotEmpty) {
      state = state.sublist(0, state.length - 1);
    }
  }

  void clearMessages() {
    state = [];
  }

  void setMessages(List<ChatMessage> messages) {
    state = messages;
  }

  void updateLastMessage(String content) {
    if (state.isEmpty) return;

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant') return;

    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(content: content),
    ];
  }

  void appendToLastMessage(String content) {
    debugPrint('DEBUG: appendToLastMessage called with: "$content"');

    if (state.isEmpty) {
      debugPrint('DEBUG: No messages to append to');
      return;
    }

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant') {
      debugPrint(
        'DEBUG: Last message is not assistant, role: ${lastMessage.role}',
      );
      return;
    }

    debugPrint(
      'DEBUG: Appending to message ${lastMessage.id}, current length: ${lastMessage.content.length}',
    );

    // If the current content is just the typing indicator, replace it instead of appending
    final newContent = lastMessage.content == '[TYPING_INDICATOR]'
        ? content
        : lastMessage.content + content;

    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(content: newContent),
    ];
    debugPrint('DEBUG: New content length: ${state.last.content.length}');
  }

  void replaceLastMessageContent(String content) {
    debugPrint('DEBUG: replaceLastMessageContent called with: "$content"');
    if (state.isEmpty) {
      debugPrint('DEBUG: No messages to replace content for');
      return;
    }

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant') {
      debugPrint(
        'DEBUG: Last message is not assistant, role: ${lastMessage.role}',
      );
      return;
    }

    debugPrint('DEBUG: Replacing content for message ${lastMessage.id}');
    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(content: content),
    ];
    debugPrint('DEBUG: Replaced content length: ${state.last.content.length}');
  }

  void finishStreaming() {
    if (state.isEmpty) return;

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant' || !lastMessage.isStreaming) return;

    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(isStreaming: false),
    ];
  }

  @override
  void dispose() {
    debugPrint(
      'DEBUG: ChatMessagesNotifier disposing - cancelling ${_subscriptions.length} subscriptions',
    );

    // Cancel all tracked subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Cancel message stream specifically
    _cancelMessageStream();

    // Cancel conversation listener specifically
    _conversationListener?.close();
    _conversationListener = null;

    debugPrint('DEBUG: ChatMessagesNotifier disposed successfully');
    super.dispose();
  }
}

// Start a new chat (unified function for both "New Chat" button and home screen)
void startNewChat(dynamic ref) {
  debugPrint('DEBUG: Starting new chat - clearing all state');

  // Clear active conversation
  ref.read(activeConversationProvider.notifier).state = null;

  // Clear messages
  ref.read(chatMessagesProvider.notifier).clearMessages();

  debugPrint('DEBUG: New chat state cleared');
}

// Available tools provider
final availableToolsProvider = StateProvider<List<String>>((ref) => []);

// Web search enabled state for API-based web search
final webSearchEnabledProvider = StateProvider<bool>((ref) => false);

// Vision capable models provider
final visionCapableModelsProvider = StateProvider<List<String>>((ref) {
  final selectedModel = ref.watch(selectedModelProvider);
  if (selectedModel == null) return [];

  // Check if the model supports vision (multimodal)
  if (selectedModel.isMultimodal == true) {
    return [selectedModel.id];
  }

  // For now, assume all models support vision unless explicitly marked
  // This can be enhanced with proper model capability detection
  return [selectedModel.id];
});

// File upload capable models provider
final fileUploadCapableModelsProvider = StateProvider<List<String>>((ref) {
  final selectedModel = ref.watch(selectedModelProvider);
  if (selectedModel == null) return [];

  // For now, assume all models support file upload
  // This can be enhanced with proper model capability detection
  return [selectedModel.id];
});

// Helper function to validate file size
bool validateFileSize(int fileSize, int? maxSizeMB) {
  if (maxSizeMB == null) return true;
  final maxSizeBytes = maxSizeMB * 1024 * 1024;
  return fileSize <= maxSizeBytes;
}

// Helper function to validate file count
bool validateFileCount(int currentCount, int newFilesCount, int? maxCount) {
  if (maxCount == null) return true;
  return (currentCount + newFilesCount) <= maxCount;
}

// Helper function to get file content as base64
Future<String?> _getFileAsBase64(dynamic api, String fileId) async {
  debugPrint('DEBUG: _getFileAsBase64 called for fileId: $fileId');

  // Check if this is already a data URL (for images)
  if (fileId.startsWith('data:')) {
    debugPrint('DEBUG: FileId is already a data URL, returning as-is');
    return fileId;
  }

  try {
    // First, get file info to determine if it's an image
    debugPrint('DEBUG: Getting file info for $fileId');
    final fileInfo = await api.getFileInfo(fileId);
    debugPrint('DEBUG: File info received: $fileInfo');

    // Try different fields for filename - check all possible field names
    final fileName =
        fileInfo['filename'] ??
        fileInfo['meta']?['name'] ??
        fileInfo['name'] ??
        fileInfo['file_name'] ??
        fileInfo['original_name'] ??
        fileInfo['original_filename'] ??
        '';

    debugPrint('DEBUG: Processing file: $fileName (fileId: $fileId)');

    final ext = fileName.toLowerCase().split('.').last;
    debugPrint('DEBUG: File extension: $ext');

    // Only process image files
    if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      debugPrint('DEBUG: Skipping non-image file: $fileName (extension: $ext)');
      return null;
    }

    debugPrint('DEBUG: Getting base64 content for image: $fileName');

    // Get file content as base64 string
    final fileContent = await api.getFileContent(fileId);
    debugPrint(
      'DEBUG: Got file content for $fileName, type: ${fileContent.runtimeType}, length: ${fileContent.length}',
    );

    // The API service returns base64 string directly
    return fileContent;
  } catch (e) {
    debugPrint('DEBUG: Error getting file content for $fileId: $e');
    return null;
  }
}

// Send message function for widgets
Future<void> sendMessage(
  WidgetRef ref,
  String message,
  List<String>? attachments,
) async {
  debugPrint(
    'DEBUG: sendMessage called with message: $message, attachments: $attachments',
  );
  await _sendMessageInternal(ref, message, attachments);
}

// Internal send message implementation
Future<void> _sendMessageInternal(
  dynamic ref,
  String message,
  List<String>? attachments,
) async {
  debugPrint('DEBUG: _sendMessageInternal called');
  debugPrint('DEBUG: Message: $message');
  debugPrint('DEBUG: Attachments: $attachments');

  final reviewerMode = ref.read(reviewerModeProvider);
  final api = ref.read(apiServiceProvider);
  final selectedModel = ref.read(selectedModelProvider);

  debugPrint('DEBUG: API service: ${api != null ? 'available' : 'null'}');
  debugPrint('DEBUG: Selected model: ${selectedModel?.name ?? 'null'}');

  if ((!reviewerMode && api == null) || selectedModel == null) {
    debugPrint('DEBUG: Missing API service or model');
    throw Exception('No API service or model selected');
  }

  // Check if we need to create a new conversation first
  var activeConversation = ref.read(activeConversationProvider);
  
  debugPrint('DEBUG: Active conversation before send: ${activeConversation?.id}');

  // Create user message first
  debugPrint('DEBUG: Creating user message with attachments: $attachments');
  final userMessage = ChatMessage(
    id: const Uuid().v4(),
    role: 'user',
    content: message,
    timestamp: DateTime.now(),
    attachmentIds: attachments,
  );

  if (activeConversation == null) {
    // Create new conversation with the first message included
    debugPrint('DEBUG: Creating new conversation with first message');

    // Create local conversation first
    final localConversation = Conversation(
      id: const Uuid().v4(),
      title: 'New Chat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      messages: [userMessage], // Include the user message
    );

    // Set as active conversation locally
    ref.read(activeConversationProvider.notifier).state = localConversation;
    activeConversation = localConversation;

    if (!reviewerMode) {
      // Try to create on server with the first message included
      try {
        final serverConversation = await api.createConversation(
          title: 'New Chat',
          messages: [userMessage], // Include the first message in creation
          model: selectedModel.id,
        );
        final updatedConversation = localConversation.copyWith(
          id: serverConversation.id,
          messages: serverConversation.messages.isNotEmpty 
              ? serverConversation.messages 
              : [userMessage],
        );
        ref.read(activeConversationProvider.notifier).state =
            updatedConversation;
        activeConversation = updatedConversation;
        
        // Set messages in the messages provider to keep UI in sync
        ref.read(chatMessagesProvider.notifier).clearMessages();
        ref.read(chatMessagesProvider.notifier).addMessage(userMessage);
        
        debugPrint(
          'DEBUG: Created conversation ${serverConversation.id} on server with first message',
        );
        debugPrint(
          'DEBUG: Server conversation ID: ${serverConversation.id}, Title: ${serverConversation.title}',
        );
      } catch (e) {
        debugPrint(
          'DEBUG: Failed to create conversation on server, using local: $e',
        );
        // Still add the message locally
        ref.read(chatMessagesProvider.notifier).addMessage(userMessage);
      }
    } else {
      // Add message for reviewer mode
      ref.read(chatMessagesProvider.notifier).addMessage(userMessage);
    }
  } else {
    // Add user message to existing conversation
    ref.read(chatMessagesProvider.notifier).addMessage(userMessage);
    debugPrint('DEBUG: User message added with ID: ${userMessage.id}');
  }

  // We'll add the assistant message placeholder after we get the message ID from the API (or immediately in reviewer mode)

  // Reviewer mode: simulate a response locally and return
  if (reviewerMode) {
    // Add assistant message placeholder
    final assistantMessage = ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '[TYPING_INDICATOR]',
      timestamp: DateTime.now(),
      model: selectedModel.name,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

    // Simulate token-by-token streaming
    final demoText =
        'This is a demo response from Conduit.\n\nYou typed: "$message"';
    final words = demoText.split(' ');
    for (final word in words) {
      await Future.delayed(const Duration(milliseconds: 40));
      ref.read(chatMessagesProvider.notifier).appendToLastMessage('$word ');
    }
    ref.read(chatMessagesProvider.notifier).finishStreaming();

    // Save locally
    await _saveConversationLocally(ref);
    return;
  }

  // Get conversation history for context
  final List<ChatMessage> messages = ref.read(chatMessagesProvider);
  final List<Map<String, dynamic>> conversationMessages =
      <Map<String, dynamic>>[];

  for (final msg in messages) {
    // Skip only empty assistant message placeholders that are currently streaming
    // Include completed messages (both user and assistant) for conversation history
    if (msg.role.isNotEmpty && msg.content.isNotEmpty && !msg.isStreaming) {
      debugPrint(
        'DEBUG: Processing message: role=${msg.role}, content=${msg.content.substring(0, msg.content.length > 50 ? 50 : msg.content.length)}..., attachments=${msg.attachmentIds}',
      );

      // Check if message has attachments (images and non-images)
      if (msg.attachmentIds != null && msg.attachmentIds!.isNotEmpty) {
        debugPrint(
          'DEBUG: Message has ${msg.attachmentIds!.length} attachments',
        );

        // Check if this is a Gemini model that requires special handling
        final isGeminiModel = selectedModel.id.toLowerCase().contains('gemini');
        debugPrint('DEBUG: Is Gemini model: $isGeminiModel');
        debugPrint('DEBUG: Model ID: ${selectedModel.id}');
        debugPrint('DEBUG: Model name: ${selectedModel.name}');
        debugPrint(
          'DEBUG: Model ID lowercase: ${selectedModel.id.toLowerCase()}',
        );
        debugPrint(
          'DEBUG: Contains gemini: ${selectedModel.id.toLowerCase().contains('gemini')}',
        );

        // Use the same content array format for all models (OpenWebUI standard)
        final List<Map<String, dynamic>> contentArray = [];
        // Collect non-image files to include in the message map so API can forward top-level 'files'
        final List<Map<String, dynamic>> nonImageFiles = [];

        // Add text content first
        if (msg.content.isNotEmpty) {
          contentArray.add({'type': 'text', 'text': msg.content});
          debugPrint('DEBUG: Added text content to array');
        }

        // Add image attachments with proper MIME type handling; collect non-image attachments
        for (final attachmentId in msg.attachmentIds!) {
          debugPrint('DEBUG: Processing attachment: $attachmentId');
          try {
            final base64Data = await _getFileAsBase64(api, attachmentId);
            if (base64Data != null) {
              debugPrint(
                'DEBUG: Got base64 data for attachment $attachmentId, length: ${base64Data.length}',
              );

              // Check if this is already a data URL
              if (base64Data.startsWith('data:')) {
                contentArray.add({
                  'type': 'image_url',
                  'image_url': {'url': base64Data},
                });
                debugPrint('DEBUG: Added image with data URL');
              } else {
                // For server files, determine MIME type from file extension
                // Only call getFileInfo if attachmentId is not a data URL
                if (!attachmentId.startsWith('data:')) {
                  final fileInfo = await api.getFileInfo(attachmentId);
                  final fileName = fileInfo['filename'] ?? '';
                  final ext = fileName.toLowerCase().split('.').last;

                  String mimeType = 'image/png'; // default
                  if (ext == 'jpg' || ext == 'jpeg') {
                    mimeType = 'image/jpeg';
                  } else if (ext == 'gif') {
                    mimeType = 'image/gif';
                  } else if (ext == 'webp') {
                    mimeType = 'image/webp';
                  }

                  debugPrint(
                    'DEBUG: Using MIME type: $mimeType for file: $fileName',
                  );

                  contentArray.add({
                    'type': 'image_url',
                    'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
                  });
                  debugPrint('DEBUG: Added image with MIME type: $mimeType');
                } else {
                  debugPrint('DEBUG: Skipping getFileInfo for data URL');
                }
              }
            } else {
              debugPrint(
                'DEBUG: No base64 data returned for attachment $attachmentId',
              );
              // Treat as non-image file; include minimal descriptor so server can resolve by id
              nonImageFiles.add({'id': attachmentId, 'type': 'file'});
            }
          } catch (e) {
            debugPrint('DEBUG: Failed to load attachment $attachmentId: $e');
          }
        }

        debugPrint('DEBUG: Final content array length: ${contentArray.length}');
        final messageMap = <String, dynamic>{
          'role': msg.role,
          'content': contentArray,
        };
        if (nonImageFiles.isNotEmpty) {
          debugPrint(
            'DEBUG: Adding ${nonImageFiles.length} non-image file(s) to message map',
          );
          messageMap['files'] = nonImageFiles;
        }
        conversationMessages.add(messageMap);
      } else {
        // Regular text-only message
        debugPrint('DEBUG: Regular text-only message');
        conversationMessages.add({'role': msg.role, 'content': msg.content});
      }
    }
  }

  // Check if web search is enabled for API
  final webSearchEnabled = ref.read(webSearchEnabledProvider);

  // No need for function calling tools since we're using retrieval directly
  final tools = <Map<String, dynamic>>[];

  try {
    // Use the model's actual supported parameters if available
    final supportedParams =
        selectedModel.supportedParameters ??
        [
          'max_tokens',
          'tool_choice',
          'tools',
          'response_format',
          'structured_outputs',
        ];

    debugPrint(
      'DEBUG: Model ${selectedModel.name} supported parameters: ${selectedModel.supportedParameters}',
    );
    debugPrint('DEBUG: Model ID: ${selectedModel.id}');
    debugPrint('DEBUG: Is multimodal: ${selectedModel.isMultimodal}');

    // Create comprehensive model item matching OpenWebUI format exactly
    final modelItem = {
      'id': selectedModel.id,
      'canonical_slug': selectedModel.id,
      'hugging_face_id': '',
      'name': selectedModel.name,
      'created': 1754089419, // Use example timestamp for consistency
      'description':
          selectedModel.description ??
          'This is a cloaked model provided to the community to gather feedback. This is an improved version of [Horizon Alpha](/openrouter/horizon-alpha)\n\nNote: It\'s free to use during this testing period, and prompts and completions are logged by the model creator for feedback and training.',
      'context_length': 256000,
      'architecture': {
        'modality': 'text+image->text',
        'input_modalities': ['image', 'text'],
        'output_modalities': ['text'],
        'tokenizer': 'Other',
        'instruct_type': null,
      },
      'pricing': {
        'prompt': '0',
        'completion': '0',
        'request': '0',
        'image': '0',
        'audio': '0',
        'web_search': '0',
        'internal_reasoning': '0',
      },
      'top_provider': {
        'context_length': 256000,
        'max_completion_tokens': 128000,
        'is_moderated': false,
      },
      'per_request_limits': null,
      'supported_parameters': supportedParams,
      'connection_type': 'external',
      'owned_by': 'openai',
      'openai': {
        'id': selectedModel.id,
        'canonical_slug': selectedModel.id,
        'hugging_face_id': '',
        'name': selectedModel.name,
        'created': 1754089419,
        'description':
            selectedModel.description ??
            'This is a cloaked model provided to the community to gather feedback. This is an improved version of [Horizon Alpha](/openrout'
                'er/horizon-alpha)\n\nNote: It\'s free to use during this testing period, and prompts and completions are logged by the model creator for feedback and training.',
        'context_length': 256000,
        'architecture': {
          'modality': 'text+image->text',
          'input_modalities': ['image', 'text'],
          'output_modalities': ['text'],
          'tokenizer': 'Other',
          'instruct_type': null,
        },
        'pricing': {
          'prompt': '0',
          'completion': '0',
          'request': '0',
          'image': '0',
          'audio': '0',
          'web_search': '0',
          'internal_reasoning': '0',
        },
        'top_provider': {
          'context_length': 256000,
          'max_completion_tokens': 128000,
          'is_moderated': false,
        },
        'per_request_limits': null,
        'supported_parameters': [
          'max_tokens',
          'tool_choice',
          'tools',
          'response_format',
          'structured_outputs',
        ],
        'connection_type': 'external',
      },
      'urlIdx': 0,
      'actions': <dynamic>[],
      'filters': <dynamic>[],
      'tags': <dynamic>[],
    };

    debugPrint('DEBUG: Using basic model item for ${selectedModel.name}');

    debugPrint('DEBUG: Final conversationMessages being sent to API:');
    debugPrint('DEBUG: Messages count: ${conversationMessages.length}');
    for (int i = 0; i < conversationMessages.length; i++) {
      final msg = conversationMessages[i];
      debugPrint(
        'DEBUG: Message $i: role=${msg['role']}, content type=${msg['content'].runtimeType}',
      );
      if (msg['content'] is List) {
        final contentArray = msg['content'] as List;
        debugPrint(
          'DEBUG: Message $i content array length: ${contentArray.length}',
        );
        for (int j = 0; j < contentArray.length; j++) {
          final item = contentArray[j];
          debugPrint(
            'DEBUG: Content item $j: type=${item['type']}, has_image_url=${item.containsKey('image_url')}',
          );
        }
      }
    }

    // Stream response using chat completions endpoint directly
    final response = await api.sendMessageWithStreaming(
      messages: conversationMessages,
      model: selectedModel.id,
      conversationId: activeConversation?.id,
      tools: tools.isNotEmpty ? tools : null,
      enableWebSearch: webSearchEnabled,
      modelItem: modelItem,
    );

    final stream = response.stream;
    final assistantMessageId = response.messageId;
    final sessionId = response.sessionId;

    debugPrint(
      'DEBUG: Response IDs - Message: $assistantMessageId, Session: $sessionId',
    );

    // Add assistant message placeholder with the generated ID and immediate typing indicator
    final assistantMessage = ChatMessage(
      id: assistantMessageId,
      role: 'assistant',
      content: '[TYPING_INDICATOR]', // Show typing indicator immediately
      timestamp: DateTime.now(),
      model: selectedModel.name,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

    // For built-in web search, the status will be updated when function calls are detected
    // in the streaming response. Manual status update is not needed here.

    // Set up stream subscription with proper management
    // Apply chunking for smoother word-by-word streaming
    final chunkedStream = StreamChunker.chunkStream(
      stream,
      enableChunking: true,
      minChunkSize: 5,
      maxChunkLength: 3,
      delayBetweenChunks: const Duration(milliseconds: 15),
    );

    final streamSubscription = chunkedStream.listen(
      (chunk) {
        debugPrint('DEBUG: Received stream chunk: "$chunk"');
        ref.read(chatMessagesProvider.notifier).appendToLastMessage(chunk);
      },

      onDone: () async {
        debugPrint('DEBUG: Stream completed in chat provider');
        // Mark streaming as complete immediately for better UX
        ref.read(chatMessagesProvider.notifier).finishStreaming();

        // Send chat completed notification to OpenWebUI
        final messages = ref.read(chatMessagesProvider);
        if (messages.isNotEmpty && activeConversation != null) {
          final lastMessage = messages.last;
          if (lastMessage.role == 'assistant') {
            try {
              // Convert messages to the format expected by /api/chat/completed
              final List<Map<String, dynamic>> formattedMessages = [];

              for (final msg in messages) {
                final messageMap = <String, dynamic>{
                  'id': msg.id,
                  'role': msg.role,
                  'content': msg.content,
                  'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
                };

                // For assistant messages, add completion details
                if (msg.role == 'assistant') {
                  messageMap['model'] = selectedModel.id;
                  
                  // Add mock usage data if not available (OpenWebUI expects this)
                  if (msg.usage != null) {
                    messageMap['usage'] = msg.usage;
                  } else if (msg == messages.last) {
                    // Add basic usage for the last assistant message
                    messageMap['usage'] = {
                      'prompt_tokens': 10,
                      'completion_tokens': msg.content.split(' ').length,
                      'total_tokens': 10 + msg.content.split(' ').length,
                    };
                  }
                }

                formattedMessages.add(messageMap);
              }

              // Send chat completed notification to OpenWebUI first
              try {
                debugPrint(
                  'DEBUG: Sending chat completed notification to OpenWebUI',
                );
                debugPrint(
                  'DEBUG: Active conversation ID: ${activeConversation.id}',
                );
                debugPrint(
                  'DEBUG: Chat ID: ${activeConversation.id}, Message ID: $assistantMessageId, Messages: ${formattedMessages.length}',
                );
                await api.sendChatCompleted(
                  chatId: activeConversation.id,
                  messageId: assistantMessageId, // Use message ID from response
                  messages: formattedMessages,
                  model: selectedModel.id,
                  modelItem: modelItem, // Include model metadata
                  sessionId: sessionId, // Include session ID
                );
                debugPrint(
                  'DEBUG: Chat completed notification sent successfully for chat ID: ${activeConversation.id}',
                );

              } catch (e) {
                debugPrint('DEBUG: Chat completed notification failed: $e');
                debugPrint('DEBUG: Error details: $e');
                // Continue even if this fails - it's non-critical
              }

              // Fetch the latest conversation state without waiting for title generation
              debugPrint('DEBUG: Fetching latest conversation state...');
              debugPrint('DEBUG: Current message count: ${messages.length}');
              
              try {
                // Quick fetch to get the current state - no waiting for title generation
                final updatedConv = await api.getConversation(
                  activeConversation.id,
                );
                debugPrint('DEBUG: Current title: ${updatedConv.title}');

                // Check if we should update the title (only on first response and if server has one)
                final shouldUpdateTitle =
                    messages.length <= 2 &&
                    updatedConv.title != 'New Chat' &&
                    updatedConv.title.isNotEmpty;

                // Always combine current local messages with updated server content
                final currentMessages = ref.read(chatMessagesProvider);
                final serverMessages = updatedConv.messages;

                // Create a map of server messages by ID for quick lookup
                final serverMessageMap = <String, ChatMessage>{};
                for (final serverMsg in serverMessages) {
                  serverMessageMap[serverMsg.id] = serverMsg;
                }

                // Update local messages with server content while preserving all messages
                final updatedMessages = <ChatMessage>[];
                for (final localMsg in currentMessages) {
                  final serverMsg = serverMessageMap[localMsg.id];

                  if (serverMsg != null && serverMsg.content.isNotEmpty) {
                    // Use server content if available and non-empty
                    // This replaces any temporary progress indicators with real content
                    debugPrint(
                      'DEBUG: Replacing local content with server content for message ${localMsg.id}',
                    );
                    debugPrint(
                      'DEBUG: Local content: "${localMsg.content.substring(0, math.min(100, localMsg.content.length))}..."',
                    );
                    debugPrint(
                      'DEBUG: Server content: "${serverMsg.content.substring(0, math.min(100, serverMsg.content.length))}..."',
                    );

                    // Stream the server content through StreamChunker for word-by-word effect
                    debugPrint(
                      'DEBUG: Streaming server content through chunker for word-by-word display',
                    );

                    // Clear only the last message content in-place to avoid list reset flicker
                    final currentList = [...currentMessages];
                    final lastIndex = currentList.lastIndexWhere(
                      (m) => m.id == localMsg.id,
                    );
                    if (lastIndex != -1) {
                      currentList[lastIndex] = currentList[lastIndex].copyWith(
                        content: '',
                        isStreaming: true,
                      );
                      ref
                          .read(chatMessagesProvider.notifier)
                          .setMessages(currentList);
                    }

                    // Create a stream from the server content and chunk it
                    final serverContentStream = Stream.fromIterable([
                      serverMsg.content,
                    ]);
                    final chunkedStream = StreamChunker.chunkStream(
                      serverContentStream,
                      enableChunking: true,
                      minChunkSize: 5,
                      maxChunkLength: 3,
                      delayBetweenChunks: const Duration(milliseconds: 25),
                    );

                    // Process chunks
                    chunkedStream.listen(
                      (chunk) {
                        debugPrint('DEBUG: Server content chunk: "$chunk"');
                        ref
                            .read(chatMessagesProvider.notifier)
                            .appendToLastMessage(chunk);
                      },
                      onDone: () {
                        debugPrint('DEBUG: Server content streaming completed');
                        // Mark streaming as complete
                        ref
                            .read(chatMessagesProvider.notifier)
                            .finishStreaming();
                      },
                      onError: (error) {
                        debugPrint(
                          'DEBUG: Server content streaming error: $error',
                        );
                        // Fall back to direct replacement
                        final currentMessages = ref.read(chatMessagesProvider);
                        if (currentMessages.isNotEmpty) {
                          final fallbackMessages = [...currentMessages];
                          final lastIndex = fallbackMessages.length - 1;
                          fallbackMessages[lastIndex] =
                              fallbackMessages[lastIndex].copyWith(
                                content: serverMsg.content,
                                isStreaming: false,
                              );
                          ref
                              .read(chatMessagesProvider.notifier)
                              .setMessages(fallbackMessages);
                        }
                      },
                    );

                    // Don't add to updatedMessages here since we're streaming
                    continue;
                  } else {
                    // Handle case where streaming failed and we still have typing indicator
                    if (localMsg.content == '[TYPING_INDICATOR]') {
                      debugPrint(
                        'DEBUG: Found orphaned typing indicator for message ${localMsg.id} - replacing with empty content',
                      );
                      // Replace typing indicator with empty content so UI can show loading state
                      updatedMessages.add(
                        localMsg.copyWith(content: '', isStreaming: false),
                      );
                    } else {
                      // Keep local message as-is
                      updatedMessages.add(localMsg);
                    }
                  }
                }

                if (shouldUpdateTitle) {
                  debugPrint(
                    'DEBUG: Server generated title: ${updatedConv.title}',
                  );

                  // Ensure the title is reasonable (not too long)
                  final cleanTitle = updatedConv.title.length > 100
                      ? '${updatedConv.title.substring(0, 100)}...'
                      : updatedConv.title;

                  // Update the conversation with title and combined messages
                  final updatedConversation = activeConversation.copyWith(
                    title: cleanTitle,
                    messages: updatedMessages, // Use combined messages!
                    updatedAt: DateTime.now(),
                  );

                  ref.read(activeConversationProvider.notifier).state =
                      updatedConversation;

                  debugPrint('DEBUG: Conversation title updated successfully');
                } else {
                  // Update just the messages without changing title
                  final updatedConversation = activeConversation.copyWith(
                    messages: updatedMessages, // Use combined messages!
                    updatedAt: DateTime.now(),
                  );

                  ref.read(activeConversationProvider.notifier).state =
                      updatedConversation;

                  debugPrint(
                    'DEBUG: Conversation content updated with server response',
                  );
                }

                // Streaming already marked as complete when stream ended
                debugPrint(
                  'DEBUG: Server content replacement completed',
                );
                
                // Start background title check for first message exchanges
                if (messages.length <= 2 && updatedConv.title == 'New Chat') {
                  debugPrint('DEBUG: Starting background title check...');
                  _checkForTitleInBackground(ref, activeConversation.id);
                }
              } catch (e) {
                debugPrint('DEBUG: Failed to fetch server content: $e');
                // Streaming already marked as complete when stream ended
              }
            } catch (e) {
              debugPrint('DEBUG: Chat completed error: $e');
              // Continue without failing the entire process
              // Note: Conversation still syncs via _saveConversationToServer
              // Streaming already marked as complete when stream ended
            }
          }
        }

        // Save conversation to OpenWebUI server only after streaming is complete
        debugPrint('DEBUG: About to save conversation to server...');
        // Add a small delay to ensure the last message content is fully updated
        await Future.delayed(const Duration(milliseconds: 100));
        await _saveConversationToServer(ref);
        debugPrint('DEBUG: Conversation save completed');
      },
      onError: (error) {
        debugPrint('DEBUG: Stream error in chat provider: $error');
        // Mark streaming as complete on error
        ref.read(chatMessagesProvider.notifier).finishStreaming();

        // Special handling for Socket.IO streaming failures
        // These indicate the server generated a response but we couldn't stream it
        if (error.toString().contains(
          'Socket.IO streaming not fully implemented',
        )) {
          debugPrint(
            'DEBUG: Socket.IO streaming failed, but server may have generated response',
          );
          debugPrint(
            'DEBUG: Keeping assistant message for server content replacement',
          );
          // Don't remove the message - let the server content replacement handle it
          // The onDone callback will fetch the actual response from the server
          return; // Exit early to avoid removing the message
        }

        // Handle streaming error - remove the assistant message placeholder for other errors
        ref.read(chatMessagesProvider.notifier).removeLastMessage();

        // Handle different types of errors
        if (error.toString().contains('400')) {
          // Bad request errors - likely malformed request format
          debugPrint(
            'DEBUG: Bad request error (400) - malformed request format',
          );
          final errorMessage = ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content:
                '''⚠️ There was an issue with the message format. This might be because:

• The image attachment couldn't be processed
• The request format is incompatible with the selected model
• The message contains unsupported content

Please try sending the message again, or try without attachments.''',
            timestamp: DateTime.now(),
            isStreaming: false,
          );
          ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
        } else if (error.toString().contains('401') ||
            error.toString().contains('403')) {
          // Authentication errors - clear auth state and redirect to login
          ref.invalidate(authStateManagerProvider);
        } else if (error.toString().contains('500')) {
          // Server errors - add user-friendly error message
          debugPrint('DEBUG: Server error (500) - OpenWebUI server issue');
          final errorMessage = ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content:
                '⚠️ I\'m sorry, but there was a server error. This usually means:\n\n'
                '• The OpenWebUI server is experiencing issues\n'
                '• The selected model might be unavailable\n'
                '• There could be a temporary connection problem\n\n'
                'Please try again in a moment, or check with your server administrator if the problem persists.',
            timestamp: DateTime.now(),
            isStreaming: false,
          );
          ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
        } else if (error.toString().contains('timeout')) {
          // Timeout errors
          debugPrint('DEBUG: Request timeout error');
          final errorMessage = ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content:
                '⏱️ The request timed out. This might be because:\n\n'
                '• The server is taking too long to respond\n'
                '• Your internet connection is slow\n'
                '• The model is processing a complex request\n\n'
                'Please try again with a shorter message or check your connection.',
            timestamp: DateTime.now(),
            isStreaming: false,
          );
          ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
        }

        // Don't throw the error to prevent unhandled exceptions
        // The error message has been added to the chat
        debugPrint('DEBUG: Chat error handled gracefully: ${error.toString()}');
      },
    );

    // Register the stream subscription for proper cleanup
    ref
        .read(chatMessagesProvider.notifier)
        .setMessageStream(streamSubscription);
  } catch (e) {
    // Handle error - remove the assistant message placeholder
    ref.read(chatMessagesProvider.notifier).removeLastMessage();

    // Add user-friendly error message instead of rethrowing
    if (e.toString().contains('400')) {
      debugPrint('DEBUG: Bad request error (400) during initial request setup');
      final errorMessage = ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content:
            '''⚠️ There was an issue with the message format. This might be because:

• The image attachment couldn't be processed
• The request format is incompatible with the selected model
• The message contains unsupported content

Please try sending the message again, or try without attachments.''',
        timestamp: DateTime.now(),
        isStreaming: false,
      );
      ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
    } else if (e.toString().contains('500')) {
      debugPrint('DEBUG: Server error (500) during initial request setup');
      final errorMessage = ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content:
            '⚠️ Unable to connect to the AI model. The server returned an error (500).\n\n'
            'This is typically a server-side issue. Please try again or contact your administrator.',
        timestamp: DateTime.now(),
        isStreaming: false,
      );
      ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
    } else if (e.toString().contains('404')) {
      debugPrint('DEBUG: Model or endpoint not found (404)');
      final errorMessage = ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content:
            '🤖 The selected AI model doesn\'t seem to be available.\n\n'
            'Please try selecting a different model or check with your administrator.',
        timestamp: DateTime.now(),
        isStreaming: false,
      );
      ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
    } else {
      // For other errors, provide a generic message and rethrow
      debugPrint('DEBUG: Unexpected error during chat request: $e');
      final errorMessage = ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content:
            '❌ An unexpected error occurred while processing your request.\n\n'
            'Please try again or check your connection.',
        timestamp: DateTime.now(),
        isStreaming: false,
      );
      ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
    }
  }
}

// Background function to check for title updates without blocking UI
Future<void> _checkForTitleInBackground(dynamic ref, String conversationId) async {
  try {
    final api = ref.read(apiServiceProvider);
    if (api == null) return;

    // Wait a bit before first check to give server time to generate
    await Future.delayed(const Duration(seconds: 3));
    
    // Try a few times with increasing delays
    for (int i = 0; i < 3; i++) {
      try {
        final updatedConv = await api.getConversation(conversationId);
        
        if (updatedConv.title != 'New Chat' && updatedConv.title.isNotEmpty) {
          debugPrint('DEBUG: Background title update found: ${updatedConv.title}');
          
          // Update the active conversation with the new title
          final activeConversation = ref.read(activeConversationProvider);
          if (activeConversation?.id == conversationId) {
            final updated = activeConversation!.copyWith(
              title: updatedConv.title,
              updatedAt: DateTime.now(),
            );
            ref.read(activeConversationProvider.notifier).state = updated;
            
            // Refresh the conversations list
            ref.invalidate(conversationsProvider);
          }
          
          return; // Title found, stop checking
        }
        
        // Wait before next check (3s, 5s, 7s)
        if (i < 2) {
          await Future.delayed(Duration(seconds: 2 + (i * 2)));
        }
      } catch (e) {
        debugPrint('DEBUG: Background title check error: $e');
        break; // Stop on error
      }
    }
    
    debugPrint('DEBUG: Background title check completed without finding generated title');
  } catch (e) {
    debugPrint('DEBUG: Background title check failed: $e');
  }
}

// Save current conversation to OpenWebUI server
Future<void> _saveConversationToServer(dynamic ref) async {
  try {
    debugPrint('DEBUG: _saveConversationToServer started');
    final api = ref.read(apiServiceProvider);
    final messages = ref.read(chatMessagesProvider);
    final activeConversation = ref.read(activeConversationProvider);
    final selectedModel = ref.read(selectedModelProvider);

    debugPrint(
      'DEBUG: Conversation save state - API: ${api != null}, Messages: ${messages.length}, Active: ${activeConversation?.id}, Model: ${selectedModel?.id}',
    );

    if (api == null || messages.isEmpty || activeConversation == null) {
      debugPrint('DEBUG: Skipping conversation save - missing required data');
      return;
    }

    // Check if the last message (assistant) has content
    final lastMessage = messages.last;
    if (lastMessage.role == 'assistant' && lastMessage.content.trim().isEmpty) {
      debugPrint(
        'DEBUG: Skipping conversation save - assistant message has no content',
      );
      return;
    }

    // Update the existing conversation with all messages (including assistant response)
    debugPrint(
      'DEBUG: Updating conversation ${activeConversation.id} with complete message history',
    );
    debugPrint(
      'DEBUG: Conversation ID being updated: ${activeConversation.id}',
    );
    debugPrint(
      'DEBUG: Number of messages to save: ${messages.length}',
    );

    try {
      await api.updateConversationWithMessages(
        activeConversation.id,
        messages,
        model: selectedModel?.id,
      );

      // Update local state
      final updatedConversation = activeConversation.copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );

      ref.read(activeConversationProvider.notifier).state = updatedConversation;
      debugPrint(
        'DEBUG: Successfully updated conversation on server: ${activeConversation.id}',
      );
      debugPrint(
        'DEBUG: Updated conversation title: ${updatedConversation.title}',
      );
    } catch (e) {
      debugPrint('DEBUG: Failed to update conversation on server: $e');
      debugPrint('DEBUG: Error details: $e');
      // Fallback to local storage if server update fails
      await _saveConversationLocally(ref);
      return;
    }

    // Refresh conversations list to show the updated conversation
    debugPrint(
      'DEBUG: Invalidating conversations provider after successful save',
    );
    ref.invalidate(conversationsProvider);
    debugPrint('DEBUG: Conversations provider invalidated');
  } catch (e) {
    debugPrint('Error saving conversation to server: $e');
    // Fallback to local storage
    await _saveConversationLocally(ref);
  }
}

// Fallback: Save current conversation to local storage
Future<void> _saveConversationLocally(dynamic ref) async {
  try {
    final storage = ref.read(optimizedStorageServiceProvider);
    final messages = ref.read(chatMessagesProvider);
    final activeConversation = ref.read(activeConversationProvider);

    if (messages.isEmpty) return;

    // Create or update conversation locally
    final conversation =
        activeConversation ??
        Conversation(
          id: const Uuid().v4(),
          title: _generateConversationTitle(messages),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messages: messages,
        );

    final updatedConversation = conversation.copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );

    // Store conversation locally using the storage service's actual methods
    final conversationsJson = await storage.getString('conversations') ?? '[]';
    final List<dynamic> conversations = jsonDecode(conversationsJson);
    
    // Find and update or add the conversation
    final existingIndex = conversations.indexWhere((c) => c['id'] == updatedConversation.id);
    if (existingIndex >= 0) {
      conversations[existingIndex] = updatedConversation.toJson();
    } else {
      conversations.add(updatedConversation.toJson());
    }
    
    await storage.setString('conversations', jsonEncode(conversations));
    ref.read(activeConversationProvider.notifier).state = updatedConversation;
    ref.invalidate(conversationsProvider);
  } catch (e) {
    debugPrint('Error saving conversation locally: $e');
  }
}

String _generateConversationTitle(List<ChatMessage> messages) {
  final firstUserMessage = messages.firstWhere(
    (msg) => msg.role == 'user',
    orElse: () => ChatMessage(
      id: '',
      role: 'user',
      content: 'New Chat',
      timestamp: DateTime.now(),
    ),
  );

  // Use first 50 characters of the first user message as title
  final title = firstUserMessage.content.length > 50
      ? '${firstUserMessage.content.substring(0, 50)}...'
      : firstUserMessage.content;

  return title.isEmpty ? 'New Chat' : title;
}

// Pin/Unpin conversation
Future<void> pinConversation(
  WidgetRef ref,
  String conversationId,
  bool pinned,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    if (api == null) throw Exception('No API service available');

    await api.pinConversation(conversationId, pinned);

    // Refresh conversations list to reflect the change
    ref.invalidate(conversationsProvider);

    // Update active conversation if it's the one being pinned
    final activeConversation = ref.read(activeConversationProvider);
    if (activeConversation?.id == conversationId) {
      ref.read(activeConversationProvider.notifier).state = activeConversation!
          .copyWith(pinned: pinned);
    }
  } catch (e) {
    debugPrint('Error ${pinned ? 'pinning' : 'unpinning'} conversation: $e');
    rethrow;
  }
}

// Archive/Unarchive conversation
Future<void> archiveConversation(
  WidgetRef ref,
  String conversationId,
  bool archived,
) async {
  final api = ref.read(apiServiceProvider);
  final activeConversation = ref.read(activeConversationProvider);

  // Update local state first
  if (activeConversation?.id == conversationId && archived) {
    ref.read(activeConversationProvider.notifier).state = null;
    ref.read(chatMessagesProvider.notifier).clearMessages();
  }

  try {
    if (api == null) throw Exception('No API service available');

    await api.archiveConversation(conversationId, archived);

    // Refresh conversations list to reflect the change
    ref.invalidate(conversationsProvider);
  } catch (e) {
    debugPrint(
      'Error ${archived ? 'archiving' : 'unarchiving'} conversation: $e',
    );

    // If server operation failed and we archived locally, restore the conversation
    if (activeConversation?.id == conversationId && archived) {
      ref.read(activeConversationProvider.notifier).state = activeConversation;
      // Messages will be restored through the listener
    }

    rethrow;
  }
}

// Share conversation
Future<String?> shareConversation(WidgetRef ref, String conversationId) async {
  try {
    final api = ref.read(apiServiceProvider);
    if (api == null) throw Exception('No API service available');

    final shareId = await api.shareConversation(conversationId);

    // Refresh conversations list to reflect the change
    ref.invalidate(conversationsProvider);

    return shareId;
  } catch (e) {
    debugPrint('Error sharing conversation: $e');
    rethrow;
  }
}

// Clone conversation
Future<void> cloneConversation(WidgetRef ref, String conversationId) async {
  try {
    final api = ref.read(apiServiceProvider);
    if (api == null) throw Exception('No API service available');

    final clonedConversation = await api.cloneConversation(conversationId);

    // Set the cloned conversation as active
    ref.read(activeConversationProvider.notifier).state = clonedConversation;
    // Load messages through the listener mechanism
    // The ChatMessagesNotifier will automatically load messages when activeConversation changes

    // Refresh conversations list to show the new conversation
    ref.invalidate(conversationsProvider);
  } catch (e) {
    debugPrint('Error cloning conversation: $e');
    rethrow;
  }
}

// Regenerate last message
final regenerateLastMessageProvider = Provider<void Function()>((ref) {
  return () async {
    final messages = ref.read(chatMessagesProvider);
    if (messages.length < 2) return;

    // Find last user message with proper bounds checking
    ChatMessage? lastUserMessage;
    for (int i = messages.length - 2; i >= 0 && i < messages.length; i--) {
      if (i >= 0 && messages[i].role == 'user') {
        lastUserMessage = messages[i];
        break;
      }
    }

    if (lastUserMessage == null) return;

    // Remove last assistant message
    ref.read(chatMessagesProvider.notifier).removeLastMessage();

    // Resend the message
    await _sendMessageInternal(
      ref,
      lastUserMessage.content,
      lastUserMessage.attachmentIds,
    );
  };
});

// Stop generation provider
final stopGenerationProvider = Provider<void Function()>((ref) {
  return () {
    // This would need to be implemented with proper cancellation support
    // For now, just mark streaming as complete
    ref.read(chatMessagesProvider.notifier).finishStreaming();
  };
});
