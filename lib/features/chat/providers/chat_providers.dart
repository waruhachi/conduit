import 'dart:async';
import 'dart:convert';
import 'package:yaml/yaml.dart' as yaml;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/auth/auth_state_manager.dart';
import '../../../core/utils/stream_chunker.dart';
import '../../../core/services/persistent_streaming_service.dart';
import '../../../core/utils/debug_logger.dart';
import '../services/reviewer_mode_service.dart';

const bool kSocketVerboseLogging = false;

// Chat messages for current conversation
final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, List<ChatMessage>>((ref) {
      return ChatMessagesNotifier(ref);
    });

// Loading state for conversation (used to show chat skeletons during fetch)
final isLoadingConversationProvider = StateProvider<bool>((ref) => false);

// Prefilled input text (e.g., when sharing text from other apps)
final prefilledInputTextProvider = StateProvider<String?>((ref) => null);

// Trigger to request focus on the chat input (increment to signal)
final inputFocusTriggerProvider = StateProvider<int>((ref) => 0);

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
      debugPrint('Conversation changed: ${previous?.id} -> ${next?.id}');

      // Only react when the conversation actually changes
      if (previous?.id == next?.id) {
        // If same conversation but server updated it (e.g., title/content), avoid overwriting
        // locally streamed assistant content with an outdated server copy.
        if (previous?.updatedAt != next?.updatedAt) {
          final serverMessages = next?.messages ?? const [];
          // Only replace local messages if the server has strictly more messages
          // (i.e., includes new content we don't have yet).
          if (serverMessages.length > state.length) {
            state = serverMessages;
          }
        }
        return;
      }

      // Cancel any existing message stream when switching conversations
      _cancelMessageStream();

      if (next != null) {
        state = next.messages;

        // Update selected model if conversation has a different model
        _updateModelForConversation(next);
      } else {
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

  Future<void> _updateModelForConversation(Conversation conversation) async {
    // Check if conversation has a model specified
    if (conversation.model == null || conversation.model!.isEmpty) {
      return;
    }

    final currentSelectedModel = _ref.read(selectedModelProvider);

    // If the conversation's model is different from the currently selected one
    if (currentSelectedModel?.id != conversation.model) {
      // Get available models to find the matching one
      try {
        final models = await _ref.read(modelsProvider.future);

        if (models.isEmpty) {
          return;
        }

        // Look for exact match first
        final conversationModel = models
            .where((model) => model.id == conversation.model)
            .firstOrNull;

        if (conversationModel != null) {
          // Update the selected model
          _ref.read(selectedModelProvider.notifier).state = conversationModel;
        } else {
          // Model not found in available models - silently continue
        }
      } catch (e) {
        // Model update failed - silently continue
      }
    }
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

    // Ensure we never keep the typing placeholder in persisted content
    String sanitized(String s) {
      const ti = '[TYPING_INDICATOR]';
      const searchBanner = '🔍 Searching the web...';
      if (s.startsWith(ti)) {
        s = s.substring(ti.length);
      }
      if (s.startsWith(searchBanner)) {
        s = s.substring(searchBanner.length);
      }
      return s;
    }

    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(content: sanitized(content)),
    ];
  }

  void updateLastMessageWithFunction(
    ChatMessage Function(ChatMessage) updater,
  ) {
    if (state.isEmpty) return;

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant') return;

    state = [...state.sublist(0, state.length - 1), updater(lastMessage)];
  }

  void appendToLastMessage(String content) {
    if (state.isEmpty) {
      return;
    }

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant') {
      return;
    }
    if (!lastMessage.isStreaming) {
      // Ignore late chunks when streaming already finished
      return;
    }

    // Strip a leading typing indicator if present, then append delta
    const ti = '[TYPING_INDICATOR]';
    const searchBanner = '🔍 Searching the web...';
    String current = lastMessage.content;
    if (current.startsWith(ti)) {
      current = current.substring(ti.length);
    }
    if (current.startsWith(searchBanner)) {
      current = current.substring(searchBanner.length);
    }
    final newContent = current.isEmpty ? content : current + content;

    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(content: newContent),
    ];
  }

  void replaceLastMessageContent(String content) {
    if (state.isEmpty) {
      return;
    }

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant') {
      return;
    }

    // Remove typing indicator if present in the replacement
    String sanitized = content;
    const ti = '[TYPING_INDICATOR]';
    const searchBanner = '🔍 Searching the web...';
    if (sanitized.startsWith(ti)) {
      sanitized = sanitized.substring(ti.length);
    }
    if (sanitized.startsWith(searchBanner)) {
      sanitized = sanitized.substring(searchBanner.length);
    }
    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(content: sanitized),
    ];
  }

  void finishStreaming() {
    if (state.isEmpty) return;

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant' || !lastMessage.isStreaming) return;

    // Also strip any leftover typing indicator before finalizing
    const ti = '[TYPING_INDICATOR]';
    const searchBanner = '🔍 Searching the web...';
    String cleaned = lastMessage.content;
    if (cleaned.startsWith(ti)) {
      cleaned = cleaned.substring(ti.length);
    }
    if (cleaned.startsWith(searchBanner)) {
      cleaned = cleaned.substring(searchBanner.length);
    }

    state = [
      ...state.sublist(0, state.length - 1),
      lastMessage.copyWith(isStreaming: false, content: cleaned),
    ];
  }

  @override
  void dispose() {
    debugPrint(
      'ChatMessagesNotifier disposing - ${_subscriptions.length} subscriptions',
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

    super.dispose();
  }
}

// Start a new chat (unified function for both "New Chat" button and home screen)
void startNewChat(dynamic ref) {
  // Clear active conversation
  ref.read(activeConversationProvider.notifier).state = null;

  // Clear messages
  ref.read(chatMessagesProvider.notifier).clearMessages();
}

// Available tools provider
final availableToolsProvider = StateProvider<List<String>>((ref) => []);

// Web search enabled state for API-based web search
final webSearchEnabledProvider = StateProvider<bool>((ref) => false);

// Image generation enabled state - behaves like web search
final imageGenerationEnabledProvider = StateProvider<bool>((ref) => false);

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
  // Check if this is already a data URL (for images)
  if (fileId.startsWith('data:')) {
    return fileId;
  }

  try {
    // First, get file info to determine if it's an image
    final fileInfo = await api.getFileInfo(fileId);

    // Try different fields for filename - check all possible field names
    final fileName =
        fileInfo['filename'] ??
        fileInfo['meta']?['name'] ??
        fileInfo['name'] ??
        fileInfo['file_name'] ??
        fileInfo['original_name'] ??
        fileInfo['original_filename'] ??
        '';

    final ext = fileName.toLowerCase().split('.').last;

    // Only process image files
    if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return null;
    }

    // Get file content as base64 string
    final fileContent = await api.getFileContent(fileId);

    // The API service returns base64 string directly
    return fileContent;
  } catch (e) {
    return null;
  }
}

// Regenerate message function that doesn't duplicate user message
Future<void> regenerateMessage(
  WidgetRef ref,
  String userMessageContent,
  List<String>? attachments,
) async {
  final reviewerMode = ref.read(reviewerModeProvider);
  final api = ref.read(apiServiceProvider);
  final selectedModel = ref.read(selectedModelProvider);

  if ((!reviewerMode && api == null) || selectedModel == null) {
    throw Exception('No API service or model selected');
  }

  final activeConversation = ref.read(activeConversationProvider);
  if (activeConversation == null) {
    throw Exception('No active conversation');
  }

  // In reviewer mode, simulate response
  if (reviewerMode) {
    final assistantMessage = ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      model: selectedModel.id,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

    // Reviewer mode: no immediate tool preview (no tool context)

    // Reviewer mode: no immediate tool preview (no tool context)

    // Use canned response for regeneration
    final responseText = ReviewerModeService.generateResponse(
      userMessage: userMessageContent,
    );

    // Simulate streaming response
    final words = responseText.split(' ');
    for (final word in words) {
      await Future.delayed(const Duration(milliseconds: 40));
      ref.read(chatMessagesProvider.notifier).appendToLastMessage('$word ');
    }

    ref.read(chatMessagesProvider.notifier).finishStreaming();
    await _saveConversationLocally(ref);
    return;
  }

  // For real API, proceed with regeneration using existing conversation messages
  try {
    // Get conversation history for context (excluding the removed assistant message)
    final List<ChatMessage> messages = ref.read(chatMessagesProvider);
    final List<Map<String, dynamic>> conversationMessages =
        <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (msg.role.isNotEmpty && msg.content.isNotEmpty && !msg.isStreaming) {
        // Handle messages with attachments
        if (msg.attachmentIds != null && msg.attachmentIds!.isNotEmpty) {
          final List<Map<String, dynamic>> contentArray = [];

          // Add text content first
          if (msg.content.isNotEmpty) {
            contentArray.add({'type': 'text', 'text': msg.content});
          }

          conversationMessages.add({
            'role': msg.role,
            'content': contentArray.isNotEmpty ? contentArray : msg.content,
          });
        } else {
          // Regular text message
          conversationMessages.add({'role': msg.role, 'content': msg.content});
        }
      }
    }

    // Stream response using SSE
    final response = api!.sendMessage(
      messages: conversationMessages,
      model: selectedModel.id,
      conversationId: activeConversation.id,
    );

    final stream = response.stream;
    final assistantMessageId = response.messageId;

    // Add assistant message placeholder
    final assistantMessage = ChatMessage(
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      model: selectedModel.id,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

    // Handle streaming response (basic chunking for this path)
    final chunkedStream = StreamChunker.chunkStream(
      stream,
      enableChunking: true,
      minChunkSize: 5,
      maxChunkLength: 3,
      delayBetweenChunks: const Duration(milliseconds: 15),
    );

    await for (final chunk in chunkedStream) {
      ref.read(chatMessagesProvider.notifier).appendToLastMessage(chunk);
    }

    ref.read(chatMessagesProvider.notifier).finishStreaming();
    await _saveConversationLocally(ref);
  } catch (e) {
    rethrow;
  }
}

// Send message function for widgets
Future<void> sendMessage(
  WidgetRef ref,
  String message,
  List<String>? attachments, [
  List<String>? toolIds,
]) async {
  await _sendMessageInternal(ref, message, attachments, toolIds);
}

// Service-friendly wrapper (accepts generic Ref)
Future<void> sendMessageFromService(
  Ref ref,
  String message,
  List<String>? attachments, [
  List<String>? toolIds,
]) async {
  await _sendMessageInternal(ref, message, attachments, toolIds);
}

// Internal send message implementation
Future<void> _sendMessageInternal(
  dynamic ref,
  String message,
  List<String>? attachments, [
  List<String>? toolIds,
]) async {
  final reviewerMode = ref.read(reviewerModeProvider);
  final api = ref.read(apiServiceProvider);
  final selectedModel = ref.read(selectedModelProvider);

  if ((!reviewerMode && api == null) || selectedModel == null) {
    throw Exception('No API service or model selected');
  }

  // Check if we need to create a new conversation first
  var activeConversation = ref.read(activeConversationProvider);

  // Create user message first

  final userMessage = ChatMessage(
    id: const Uuid().v4(),
    role: 'user',
    content: message,
    timestamp: DateTime.now(),
    model: selectedModel.id,
    attachmentIds: attachments,
  );

  if (activeConversation == null) {
    // Create new conversation with the first message included
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

        // Invalidate conversations provider to refresh the list
        // Adding a small delay to prevent rapid invalidations that could cause duplicates
        Future.delayed(const Duration(milliseconds: 100), () {
          try {
            // Guard against using ref after widget disposal
            if (ref.mounted == true) {
              ref.invalidate(conversationsProvider);
            }
          } catch (_) {
            // If ref doesn't support mounted or is disposed, skip
          }
        });
      } catch (e) {
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
  }

  // We'll add the assistant message placeholder after we get the message ID from the API (or immediately in reviewer mode)

  // Immediately trigger title generation after user message is sent (first turn only)
  try {
    final currentConversation = ref.read(activeConversationProvider);
    if (currentConversation != null &&
        currentConversation.title == 'New Chat') {
      final currentMessages = ref.read(chatMessagesProvider);
      if (currentMessages.length == 1 && currentMessages.first.role == 'user') {
        final List<Map<String, dynamic>> formatted = [
          {
            'id': currentMessages.first.id,
            'role': currentMessages.first.role,
            'content': currentMessages.first.content,
            'timestamp':
                currentMessages.first.timestamp.millisecondsSinceEpoch ~/ 1000,
          },
        ];
        _triggerTitleGeneration(
          ref,
          currentConversation.id,
          formatted,
          selectedModel.id,
        );
      }
    }
  } catch (e) {
    // Silent fail for early title generation
  }

  // Reviewer mode: simulate a response locally and return
  if (reviewerMode) {
    // Add assistant message placeholder
    final assistantMessage = ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      model: selectedModel.id,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

    // Check if there are attachments
    String? filename;
    if (attachments != null && attachments.isNotEmpty) {
      // Get the first attachment filename for the response
      // In reviewer mode, we just simulate having a file
      filename = "demo_file.txt";
    }

    // Check if this is voice input
    // In reviewer mode, we don't have actual voice input state
    final isVoiceInput = false;

    // Generate appropriate canned response
    final responseText = ReviewerModeService.generateResponse(
      userMessage: message,
      filename: filename,
      isVoiceInput: isVoiceInput,
    );

    // Simulate token-by-token streaming
    final words = responseText.split(' ');
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
      // Check if message has attachments (images and non-images)
      if (msg.attachmentIds != null && msg.attachmentIds!.isNotEmpty) {
        // All models use the same content array format (OpenWebUI standard)

        // Use the same content array format for all models (OpenWebUI standard)
        final List<Map<String, dynamic>> contentArray = [];
        // Collect non-image files to include in the message map so API can forward top-level 'files'
        final List<Map<String, dynamic>> nonImageFiles = [];

        // Add text content first
        if (msg.content.isNotEmpty) {
          contentArray.add({'type': 'text', 'text': msg.content});
        }

        // Add image attachments with proper MIME type handling; collect non-image attachments
        for (final attachmentId in msg.attachmentIds!) {
          try {
            final base64Data = await _getFileAsBase64(api, attachmentId);
            if (base64Data != null) {
              // Check if this is already a data URL
              if (base64Data.startsWith('data:')) {
                contentArray.add({
                  'type': 'image_url',
                  'image_url': {'url': base64Data},
                });
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

                  contentArray.add({
                    'type': 'image_url',
                    'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
                  });
                }
              }
            } else {
              // Treat as non-image file; include minimal descriptor so server can resolve by id
              nonImageFiles.add({'id': attachmentId, 'type': 'file'});
            }
          } catch (e) {
            // Handle attachment processing errors silently
          }
        }

        final messageMap = <String, dynamic>{
          'role': msg.role,
          'content': contentArray,
        };
        if (nonImageFiles.isNotEmpty) {
          messageMap['files'] = nonImageFiles;
        }
        conversationMessages.add(messageMap);
      } else {
        // Regular text-only message
        conversationMessages.add({'role': msg.role, 'content': msg.content});
      }
    }
  }

  // Check feature toggles for API (gated by server availability)
  final webSearchEnabled =
      ref.read(webSearchEnabledProvider) &&
      ref.read(webSearchAvailableProvider);
  final imageGenerationEnabled = ref.read(imageGenerationEnabledProvider);

  // Prepare tools list - pass tool IDs directly
  final List<String>? toolIdsForApi = (toolIds != null && toolIds.isNotEmpty)
      ? toolIds
      : null;

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

    // If image generation is enabled and we want image-only, skip assistant SSE
    if (imageGenerationEnabled) {
      // Create assistant placeholder
      final imageOnlyAssistantId = const Uuid().v4();
      final imageOnlyAssistant = ChatMessage(
        id: imageOnlyAssistantId,
        role: 'assistant',
        content: '',
        timestamp: DateTime.now(),
        model: selectedModel.id,
        isStreaming: true,
      );
      ref.read(chatMessagesProvider.notifier).addMessage(imageOnlyAssistant);

      try {
        final imageResponse = await api.generateImage(prompt: message);

        // Extract image URLs or base64 data URIs from response
        List<Map<String, dynamic>> extractGeneratedFiles(dynamic resp) {
          final results = <Map<String, dynamic>>[];

          if (resp is List) {
            for (final item in resp) {
              if (item is String && item.isNotEmpty) {
                results.add({'type': 'image', 'url': item});
              } else if (item is Map) {
                final url = item['url'];
                final b64 = item['b64_json'] ?? item['b64'];
                if (url is String && url.isNotEmpty) {
                  results.add({'type': 'image', 'url': url});
                } else if (b64 is String && b64.isNotEmpty) {
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              }
            }
            return results;
          }

          if (resp is! Map) return results;

          final data = resp['data'];
          if (data is List) {
            for (final item in data) {
              if (item is Map) {
                final url = item['url'];
                final b64 = item['b64_json'] ?? item['b64'];
                if (url is String && url.isNotEmpty) {
                  results.add({'type': 'image', 'url': url});
                } else if (b64 is String && b64.isNotEmpty) {
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              } else if (item is String && item.isNotEmpty) {
                results.add({'type': 'image', 'url': item});
              }
            }
          }

          final images = resp['images'];
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
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              }
            }
          }

          final singleUrl = resp['url'];
          if (singleUrl is String && singleUrl.isNotEmpty) {
            results.add({'type': 'image', 'url': singleUrl});
          }
          final singleB64 = resp['b64_json'] ?? resp['b64'];
          if (singleB64 is String && singleB64.isNotEmpty) {
            results.add({
              'type': 'image',
              'url': 'data:image/png;base64,$singleB64',
            });
          }

          return results;
        }

        final generatedFiles = extractGeneratedFiles(imageResponse);
        if (generatedFiles.isNotEmpty) {
          ref
              .read(chatMessagesProvider.notifier)
              .updateLastMessageWithFunction(
                (ChatMessage m) =>
                    m.copyWith(files: generatedFiles, isStreaming: false),
              );
          await _saveConversationToServer(ref);

          // Trigger title generation for image-only flow
          final activeConv = ref.read(activeConversationProvider);
          if (activeConv != null) {
            // Build minimal formatted messages
            final currentMessages = ref.read(chatMessagesProvider);
            final List<Map<String, dynamic>> formattedMessages = [];
            for (final msg in currentMessages) {
              formattedMessages.add({
                'id': msg.id,
                'role': msg.role,
                'content': msg.content,
                'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
              });
            }
            _triggerTitleGeneration(
              ref,
              activeConv.id,
              formattedMessages,
              selectedModel.id,
            );
          }
        } else {
          // No images; mark done
          ref.read(chatMessagesProvider.notifier).finishStreaming();
        }
      } catch (e) {
        ref.read(chatMessagesProvider.notifier).finishStreaming();
      }

      // Image-only done; do not start SSE
      return;
    }

    // Stream response using SSE
    // Resolve Socket session for background tasks parity
    final socketService = ref.read(socketServiceProvider);
    final socketSessionId = socketService?.sessionId;

    // Resolve tool servers from user settings (if any)
    List<Map<String, dynamic>>? toolServers;
    try {
      final userSettings = await api.getUserSettings();
      final ui = userSettings['ui'] as Map<String, dynamic>?;
      final rawServers = ui != null ? (ui['toolServers'] as List?) : null;
      if (rawServers != null && rawServers.isNotEmpty) {
        toolServers = await _resolveToolServers(rawServers, api);
      }
    } catch (_) {}

    // Background tasks parity with Web client (safe defaults)
    final bgTasks = <String, dynamic>{
      'title_generation': true,
      'tags_generation': true,
      'follow_up_generation': true,
    };

    final response = await api.sendMessage(
      messages: conversationMessages,
      model: selectedModel.id,
      conversationId: activeConversation?.id,
      toolIds: toolIdsForApi,
      enableWebSearch: webSearchEnabled,
      // Disable server-side image generation to avoid duplicate images;
      // handled via pre-stream client-side request above
      enableImageGeneration: false,
      modelItem: modelItem,
      sessionIdOverride: socketSessionId,
      toolServers: toolServers,
      backgroundTasks: bgTasks,
    );

    final stream = response.stream;
    final assistantMessageId = response.messageId;
    final sessionId = response.sessionId;

    // Add assistant message placeholder with the generated ID and immediate typing indicator
    final assistantMessage = ChatMessage(
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      model: selectedModel.id,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantMessage);

    // If socket is available, start listening for chat-events immediately
    // Background-tools flow (tools/tool servers) relies on socket/dynamic channel for
    // streaming content. Allow socket TEXT in that mode. For pure SSE flows, suppress
    // socket TEXT to avoid duplicates (still surface tool_call status).
    final bool isBackgroundToolsFlow =
        (toolIdsForApi != null && toolIdsForApi.isNotEmpty) ||
        (toolServers != null && toolServers.isNotEmpty);
    bool suppressSocketContent = !isBackgroundToolsFlow; // allow socket text for tools
    bool usingDynamicChannel = false; // set true when server provides a channel
    if (socketService != null) {
      void chatHandler(Map<String, dynamic> ev) {
        try {
          final data = ev['data'];
          if (data == null) return;
          final type = data['type'];
          final payload = data['data'];
          DebugLogger.stream('Socket chat-events: type=$type');
          if (type == 'chat:completion' && payload != null) {
            if (payload is Map<String, dynamic>) {
              // Provider may emit tool_calls at the top level
              // Always surface tool_calls status from socket for instant tiles
              if (payload.containsKey('tool_calls')) {
                final tc = payload['tool_calls'];
                if (tc is List) {
                  for (final call in tc) {
                    if (call is Map<String, dynamic>) {
                      final fn = call['function'];
                      final name = (fn is Map && fn['name'] is String) ? fn['name'] as String : null;
                      if (name is String && name.isNotEmpty) {
                        final msgs = ref.read(chatMessagesProvider);
                        final exists = (msgs.isNotEmpty) && RegExp(
                              r'<details\s+type=\"tool_calls\"[^>]*\bname=\"' + RegExp.escape(name) + r'\"',
                              multiLine: true,
                            ).hasMatch(msgs.last.content);
                        if (!exists) {
                          final status = '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                          ref.read(chatMessagesProvider.notifier).appendToLastMessage(status);
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
                    // Surface tool_calls status like SSE path
                    if (delta.containsKey('tool_calls')) {
                      final tc = delta['tool_calls'];
                      if (tc is List) {
                        for (final call in tc) {
                          if (call is Map<String, dynamic>) {
                            final fn = call['function'];
                            final name = (fn is Map && fn['name'] is String) ? fn['name'] as String : null;
                            if (name is String && name.isNotEmpty) {
                              final msgs = ref.read(chatMessagesProvider);
                              final exists = (msgs.isNotEmpty) && RegExp(
                                    r'<details\s+type=\"tool_calls\"[^>]*\bname=\"' + RegExp.escape(name) + r'\"',
                                    multiLine: true,
                                  ).hasMatch(msgs.last.content);
                              if (!exists) {
                                final status = '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                                ref.read(chatMessagesProvider.notifier).appendToLastMessage(status);
                              }
                            }
                          }
                        }
                      }
                    }
                    final content = delta['content']?.toString() ?? '';
                    if (content.isNotEmpty) {
                      ref.read(chatMessagesProvider.notifier).appendToLastMessage(content);
                    }
                  }
                }
              }
              if (!suppressSocketContent && payload.containsKey('content')) {
                final content = payload['content']?.toString() ?? '';
                if (content.isNotEmpty) {
                  final msgs = ref.read(chatMessagesProvider);
                  if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
                    final prev = msgs.last.content;
                    if (prev.isEmpty || prev == '[TYPING_INDICATOR]') {
                      ref
                          .read(chatMessagesProvider.notifier)
                          .replaceLastMessageContent(content);
                    } else if (content.startsWith(prev)) {
                      ref
                          .read(chatMessagesProvider.notifier)
                          .appendToLastMessage(content.substring(prev.length));
                    } else {
                      ref
                          .read(chatMessagesProvider.notifier)
                          .replaceLastMessageContent(content);
                    }
                  } else {
                    ref
                        .read(chatMessagesProvider.notifier)
                        .appendToLastMessage(content);
                  }
                }
              }
              if (payload['done'] == true) {
                // Stop listening to further socket events for this session.
                try { socketService.offChatEvents(); } catch (_) {}

                // Notify server that chat is completed (mirrors web client)
                try {
                  final apiSvc = ref.read(apiServiceProvider);
                  final chatId = activeConversation?.id ?? '';
                  if (apiSvc != null && chatId.isNotEmpty) {
                    unawaited(apiSvc
                        .sendChatCompleted(
                          chatId: chatId,
                          messageId: assistantMessageId,
                          messages: const [],
                          model: selectedModel.id,
                          modelItem: modelItem,
                          sessionId: sessionId,
                        )
                        .timeout(const Duration(seconds: 3))
                        .catchError((_) {}));
                  }
                } catch (_) {}

                // If no content was rendered yet, fetch final assistant message from server
                final msgs = ref.read(chatMessagesProvider);
                if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
                  final lastContent = msgs.last.content.trim();
                  if (lastContent.isEmpty) {
                    final apiSvc = ref.read(apiServiceProvider);
                    final chatId = activeConversation?.id;
                    final msgId = assistantMessageId;
                    if (apiSvc != null && chatId != null && chatId.isNotEmpty) {
                      Future.microtask(() async {
                        try {
                          final resp = await apiSvc.dio.get('/api/v1/chats/' + chatId);
                          final data = resp.data as Map<String, dynamic>;
                          String content = '';
                          final chatObj = data['chat'] as Map<String, dynamic>?;
                          if (chatObj != null) {
                            // Prefer chat.messages list
                            final list = chatObj['messages'];
                            if (list is List) {
                              final target = list.firstWhere(
                                (m) => (m is Map && (m['id']?.toString() == msgId)),
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
                            // Fallback to history map
                            if (content.isEmpty) {
                              final history = chatObj['history'];
                              if (history is Map && history['messages'] is Map) {
                                final Map<String, dynamic> messagesMap =
                                    (history['messages'] as Map).cast<String, dynamic>();
                                final msg = messagesMap[msgId];
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
                            ref
                                .read(chatMessagesProvider.notifier)
                                .replaceLastMessageContent(content);
                          }
                        } catch (_) {
                          // Swallow; we'll still finish streaming
                        } finally {
                          ref.read(chatMessagesProvider.notifier).finishStreaming();
                        }
                      });
                      return; // Defer finish to microtask
                    }
                  }
                }
                // Normal path: finish now
                ref.read(chatMessagesProvider.notifier).finishStreaming();
              }
            }
          } else if (type == 'request:chat:completion' && payload != null) {
            // Mirror web client's execute path: listen on provided dynamic channel
            final channel = payload['channel'];
            if (channel is String && channel.isNotEmpty) {
              // Prefer dynamic channel for streaming content; suppress chat-events text to avoid duplicates
              suppressSocketContent = true;
              usingDynamicChannel = true;
              usingDynamicChannel = true;
              if (kSocketVerboseLogging) {
                DebugLogger.stream('Socket request:chat:completion channel=$channel');
              }
              void channelLineHandler(dynamic line) {
                try {
                  if (line is String) {
                    final s = line.trim();
                    DebugLogger.stream('Socket [' + channel + '] line=' + (s.length > 160 ? s.substring(0, 160) + '…' : s));
                    if (s == '[DONE]' || s == 'DONE') {
                      socketService.offEvent(channel);
                      // Channel completed
                      try {
                        unawaited(api.sendChatCompleted(
                          chatId: activeConversation?.id ?? '',
                          messageId: assistantMessageId,
                          messages: const [],
                          model: selectedModel.id,
                          modelItem: modelItem,
                          sessionId: sessionId,
                        ));
                      } catch (_) {}
                      ref.read(chatMessagesProvider.notifier).finishStreaming();
                      return;
                    }
                    if (s.startsWith('data:')) {
                      final dataStr = s.substring(5).trim();
                      if (dataStr == '[DONE]') {
                        socketService.offEvent(channel);
                        try {
                          unawaited(api.sendChatCompleted(
                            chatId: activeConversation?.id ?? '',
                            messageId: assistantMessageId,
                            messages: const [],
                            model: selectedModel.id,
                            modelItem: modelItem,
                            sessionId: sessionId,
                          ));
                        } catch (_) {}
                        ref.read(chatMessagesProvider.notifier).finishStreaming();
                        return;
                      }
                      // Try to parse OpenAI-style delta JSON
                      try {
                        final Map<String, dynamic> j = jsonDecode(dataStr);
                        final choices = j['choices'];
                        if (choices is List && choices.isNotEmpty) {
                          final choice = choices.first;
                          final delta = choice is Map ? choice['delta'] : null;
                          if (delta is Map) {
                            if (delta.containsKey('content')) {
                              final c = delta['content']?.toString() ?? '';
                              if (c.isNotEmpty) {
                                DebugLogger.stream('Socket [' + channel + '] delta.content len=' + c.length.toString());
                              }
                            }
                            // Surface tool_calls status
                            if (delta.containsKey('tool_calls')) {
                              if (kSocketVerboseLogging) {
                                DebugLogger.stream('Socket [' + channel + '] delta.tool_calls detected');
                              }
                              final tc = delta['tool_calls'];
                              if (tc is List) {
                                for (final call in tc) {
                                  if (call is Map<String, dynamic>) {
                                    final fn = call['function'];
                                    final name = (fn is Map && fn['name'] is String)
                                        ? fn['name'] as String
                                        : null;
                                    if (name is String && name.isNotEmpty) {
                                      final msgs = ref.read(chatMessagesProvider);
                                      final exists = (msgs.isNotEmpty) && RegExp(
                                            r'<details\\s+type=\"tool_calls\"[^>]*\\bname=\"' + RegExp.escape(name) + r'\"',
                                            multiLine: true,
                                          ).hasMatch(msgs.last.content);
                                      if (!exists) {
                                        final status = '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                                        ref.read(chatMessagesProvider.notifier).appendToLastMessage(status);
                                      }
                                    }
                                  }
                                }
                              }
                            }
                            // Append streamed content
                            final content = delta['content']?.toString() ?? '';
                            if (content.isNotEmpty) {
                              ref.read(chatMessagesProvider.notifier).appendToLastMessage(content);
                            }
                          }
                        }
                      } catch (_) {
                        // Non-JSON line: append as-is
                        if (s.isNotEmpty) {
                          ref.read(chatMessagesProvider.notifier).appendToLastMessage(s);
                        }
                      }
                    } else {
                      // Plain text line
                      if (s.isNotEmpty) {
                        ref.read(chatMessagesProvider.notifier).appendToLastMessage(s);
                      }
                    }
                  } else if (line is Map) {
                    // If server sends { done: true } via channel
                    final done = line['done'] == true;
                    if (done) {
                      socketService.offEvent(channel);
                      try {
                        unawaited(api.sendChatCompleted(
                          chatId: activeConversation?.id ?? '',
                          messageId: assistantMessageId,
                          messages: const [],
                          model: selectedModel.id,
                          modelItem: modelItem,
                          sessionId: sessionId,
                        ));
                      } catch (_) {}
                      ref.read(chatMessagesProvider.notifier).finishStreaming();
                      return;
                    }
                  }
                } catch (_) {}
              }

              // Register dynamic channel listener
              try {
                socketService.onEvent(channel, channelLineHandler);
              } catch (_) {}
            }
          } else if (type == 'execute:tool' && payload != null) {
            // Show an executing tile immediately using provided tool info
            try {
              final name = payload['name']?.toString() ?? 'tool';
              DebugLogger.stream('Socket execute:tool name=' + name);
              final status = '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
              ref.read(chatMessagesProvider.notifier).appendToLastMessage(status);
            } catch (_) {}
          }
        } catch (_) {}
      }

      socketService.onChatEvents(chatHandler);
      // Also mirror channel-events like the web client
      void channelEventsHandler(Map<String, dynamic> ev) {
        try {
          final data = ev['data'];
          if (data == null) return;
          final type = data['type'];
          final payload = data['data'];
          DebugLogger.stream('Socket channel-events: type=' + type.toString());
          // Handle generic channel progress messages if needed
          if (type == 'message' && payload is Map) {
            final content = payload['content']?.toString() ?? '';
            if (content.isNotEmpty) {
              ref.read(chatMessagesProvider.notifier).appendToLastMessage(content);
            }
          }
        } catch (_) {}
      }
      socketService.onChannelEvents(channelEventsHandler);
      Future.delayed(const Duration(seconds: 90), () {
        try {
          socketService.offChatEvents();
          socketService.offChannelEvents();
        } catch (_) {}
      });
    }

    // Prepare streaming and background handling BEFORE image generation
    final chunkedStream = StreamChunker.chunkStream(
      stream,
      enableChunking: true,
      minChunkSize: 5,
      maxChunkLength: 3,
      delayBetweenChunks: const Duration(milliseconds: 15),
    );

    // Create a stream controller for persistent handling
    final persistentController = StreamController<String>.broadcast();

    // Register stream with persistent service for app lifecycle handling
    final persistentService = PersistentStreamingService();

    // Defer UI updates until images attach if image generation is enabled
    bool deferUntilImagesAttached = imageGenerationEnabled;
    bool imagesAttached = !imageGenerationEnabled;
    final StringBuffer prebuffer = StringBuffer();

    final streamId = persistentService.registerStream(
      subscription: chunkedStream.listen(
        (chunk) {
          // Buffer chunks until images are attached
          if (deferUntilImagesAttached && !imagesAttached) {
            prebuffer.write(chunk);
            return;
          }
          persistentController.add(chunk);
        },
        onDone: () {
          persistentController.close();
        },
        onError: (error) {
          persistentController.addError(error);
        },
      ),
      controller: persistentController,
      recoveryCallback: () async {
        // Recovery callback to restart streaming if interrupted
        debugPrint('DEBUG: Attempting to recover interrupted stream');
        // TODO: Implement stream recovery logic
      },
      metadata: {
        'conversationId': activeConversation?.id,
        'messageId': assistantMessageId,
        'modelId': selectedModel.id,
      },
    );

    // If image generation is enabled, trigger it BEFORE starting the SSE stream
    if (imageGenerationEnabled) {
      try {
        debugPrint(
          'DEBUG: Image generation enabled - triggering request (pre-stream)',
        );
        final imageResponse = await api.generateImage(prompt: message);

        // Extract image URLs or base64 data URIs from response
        List<Map<String, dynamic>> extractGeneratedFiles(dynamic resp) {
          final results = <Map<String, dynamic>>[];

          // If it's already a list (e.g., list of URLs or file maps)
          if (resp is List) {
            for (final item in resp) {
              if (item is String && item.isNotEmpty) {
                results.add({'type': 'image', 'url': item});
              } else if (item is Map) {
                final url = item['url'];
                final b64 = item['b64_json'] ?? item['b64'];
                if (url is String && url.isNotEmpty) {
                  results.add({'type': 'image', 'url': url});
                } else if (b64 is String && b64.isNotEmpty) {
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              }
            }
            return results;
          }

          if (resp is! Map) return results;

          // Common patterns: { data: [ { url }, { b64_json } ] }
          final data = resp['data'];
          if (data is List) {
            for (final item in data) {
              if (item is Map) {
                final url = item['url'];
                final b64 = item['b64_json'] ?? item['b64'];
                if (url is String && url.isNotEmpty) {
                  results.add({'type': 'image', 'url': url});
                } else if (b64 is String && b64.isNotEmpty) {
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              } else if (item is String && item.isNotEmpty) {
                // Some servers may return a list of URLs
                results.add({'type': 'image', 'url': item});
              }
            }
          }

          // Alternative patterns
          final images = resp['images'];
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
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              }
            }
          }

          // Single fields
          final singleUrl = resp['url'];
          if (singleUrl is String && singleUrl.isNotEmpty) {
            results.add({'type': 'image', 'url': singleUrl});
          }
          final singleB64 = resp['b64_json'] ?? resp['b64'];
          if (singleB64 is String && singleB64.isNotEmpty) {
            results.add({
              'type': 'image',
              'url': 'data:image/png;base64,$singleB64',
            });
          }

          return results;
        }

        final generatedFiles = extractGeneratedFiles(imageResponse);
        if (generatedFiles.isNotEmpty) {
          debugPrint(
            'DEBUG: Image generation returned ${generatedFiles.length} file(s) (pre-stream)',
          );

          // Attach images to the last assistant message (placeholder)
          ref.read(chatMessagesProvider.notifier).updateLastMessageWithFunction(
            (ChatMessage m) {
              final currentFiles = m.files ?? <Map<String, dynamic>>[];
              return m.copyWith(files: [...currentFiles, ...generatedFiles]);
            },
          );

          // Save updated conversation with images before streaming content
          await _saveConversationToServer(ref);

          // Now that images are attached and persisted, allow streaming to flow
          imagesAttached = true;
          if (deferUntilImagesAttached && prebuffer.isNotEmpty) {
            // Flush buffered chunks
            ref
                .read(chatMessagesProvider.notifier)
                .appendToLastMessage(prebuffer.toString());
            prebuffer.clear();
          }
        } else {
          debugPrint(
            'DEBUG: No images found in generation response (pre-stream)',
          );
          // Do not block streaming if no images are produced
          imagesAttached = true;
          if (deferUntilImagesAttached && prebuffer.isNotEmpty) {
            ref
                .read(chatMessagesProvider.notifier)
                .appendToLastMessage(prebuffer.toString());
            prebuffer.clear();
          }
        }
      } catch (e) {
        debugPrint('DEBUG: Image generation failed (pre-stream): $e');
        // Fail open: allow text streaming to continue
        imagesAttached = true;
        if (deferUntilImagesAttached && prebuffer.isNotEmpty) {
          ref
              .read(chatMessagesProvider.notifier)
              .appendToLastMessage(prebuffer.toString());
          prebuffer.clear();
        }
      }
    }

    // For built-in web search, the status will be updated when function calls are detected
    // in the streaming response. Manual status update is not needed here.

    // (moved above) streaming registration is already set up

    // Track web search status
    bool isSearching = false;

    final streamSubscription = persistentController.stream.listen(
      (chunk) {
        var effectiveChunk = chunk;
        // Check for web search indicators in the stream
        if (webSearchEnabled && !isSearching) {
          // Check if this is the start of web search
          if (chunk.contains('[SEARCHING]') ||
              chunk.contains('Searching the web') ||
              chunk.contains('web search')) {
            isSearching = true;
            // Update the message to show search status
            ref
                .read(chatMessagesProvider.notifier)
                .updateLastMessageWithFunction(
                  (message) => message.copyWith(
                    content: '🔍 Searching the web...',
                    metadata: {'webSearchActive': true},
                  ),
                );
            return; // Don't append this chunk
          }
        }

        // Check if web search is complete
        if (isSearching &&
            (chunk.contains('[/SEARCHING]') ||
                chunk.contains('Search complete'))) {
          isSearching = false;
          // Only update metadata; keep content to avoid flicker/indicator reappearing
          ref
              .read(chatMessagesProvider.notifier)
              .updateLastMessageWithFunction(
                (message) => message.copyWith(
                  metadata: {'webSearchActive': false},
                ),
              );
          // Strip markers from this chunk and continue processing
          effectiveChunk = effectiveChunk
              .replaceAll('[SEARCHING]', '')
              .replaceAll('[/SEARCHING]', '');
        }

        // If we buffered chunks before images attached, flush once
        if (deferUntilImagesAttached && !imagesAttached) {
          // do nothing; still waiting
          return;
        }

        // Regular content - append to message (markers removed above)
        if (effectiveChunk.trim().isNotEmpty) {
          ref
              .read(chatMessagesProvider.notifier)
              .appendToLastMessage(effectiveChunk);
        }
      },

      onDone: () async {
        // Unregister from persistent service
        persistentService.unregisterStream(streamId);
        // Stop socket events now that streaming finished only for SSE-driven streams
        if (socketService != null && suppressSocketContent == true) {
          try { socketService.offChatEvents(); } catch (_) {}
        }
        // Allow socket content again for future sessions (harmless if already false)
        suppressSocketContent = false;
        // If this path was SSE-driven (no background tools/dynamic channel), finish now.
        // Otherwise keep streaming state until socket/dynamic channel signals done.
        if (!usingDynamicChannel && !isBackgroundToolsFlow) {
          ref.read(chatMessagesProvider.notifier).finishStreaming();
        }

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

              // Only notify completion immediately for non-background SSE flows.
              // For background tools/dynamic-channel flows, defer completion
              // until the socket/dynamic channel signals done.
              if (!isBackgroundToolsFlow && !usingDynamicChannel) {
                try {
                  unawaited(
                    api
                        .sendChatCompleted(
                          chatId: activeConversation.id,
                          messageId:
                              assistantMessageId, // Use message ID from response
                          messages: formattedMessages,
                          model: selectedModel.id,
                          modelItem: modelItem, // Include model metadata
                          sessionId: sessionId, // Include session ID
                        )
                        .timeout(const Duration(seconds: 3))
                        .catchError((_) {}),
                  );
                } catch (_) {
                  // Ignore
                }
              }

              // Fetch the latest conversation state
              try {
                // Quick fetch to get the current state - no waiting for title generation
                final updatedConv = await api.getConversation(
                  activeConversation.id,
                );

                // Check if we should update the title (only on first response and if server has one)
                final shouldUpdateTitle =
                    messages.length <= 2 &&
                    updatedConv.title != 'New Chat' &&
                    updatedConv.title.isNotEmpty;

                if (shouldUpdateTitle) {
                  // Ensure the title is reasonable (not too long)
                  final cleanTitle = updatedConv.title.length > 100
                      ? '${updatedConv.title.substring(0, 100)}...'
                      : updatedConv.title;

                  // Update the conversation with title and combined messages
                  final updatedConversation = activeConversation.copyWith(
                    title: cleanTitle,
                    updatedAt: DateTime.now(),
                  );

                  ref.read(activeConversationProvider.notifier).state =
                      updatedConversation;
                } else {
                  // Keep local messages and only refresh conversations list
                  ref.invalidate(conversationsProvider);
                }

                // Streaming already marked as complete when stream ended
                // Removed post-assistant title trigger/background check; handled right after user message
              } catch (e) {
                // Streaming already marked as complete when stream ended
              }
            } catch (e) {
              // Continue without failing the entire process
              // Note: Conversation still syncs via _saveConversationToServer
              // Streaming already marked as complete when stream ended
            }
          }
        }

        // Save conversation to OpenWebUI server only after streaming is complete
        // Add a small delay to ensure the last message content is fully updated
        await Future.delayed(const Duration(milliseconds: 100));
        await _saveConversationToServer(ref);

        // Removed post-assistant image generation; images are handled immediately after user message
      },
      onError: (error) {
        // Mark streaming as complete on error
        ref.read(chatMessagesProvider.notifier).finishStreaming();
        // Stop socket events to avoid duplicates after error (only for SSE-driven)
        if (socketService != null && suppressSocketContent == true) {
          try { socketService.offChatEvents(); } catch (_) {}
        }

        // Special handling for Socket.IO streaming failures
        // These indicate the server generated a response but we couldn't stream it
        if (error.toString().contains(
          'Socket.IO streaming not fully implemented',
        )) {
          // Don't remove the message - let the server content replacement handle it
          // The onDone callback will fetch the actual response from the server
          return; // Exit early to avoid removing the message
        }

        // Handle streaming error - remove the assistant message placeholder for other errors
        ref.read(chatMessagesProvider.notifier).removeLastMessage();

        // Handle different types of errors
        if (error.toString().contains('400')) {
          // Bad request errors - likely malformed request format
          final errorMessage = ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '''⚠️ **Message Format Error**

This might be because:
• Image attachment couldn't be processed
• Request format incompatible with selected model  
• Message contains unsupported content

**💡 Solutions:**
• Long press this message and select "Retry"
• Try removing attachments and resending
• Switch to a different model and retry

*Long press this message to access retry options.*''',
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
          final errorMessage = ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '''⚠️ **Server Error**

This usually means:
• OpenWebUI server is experiencing issues
• Selected model might be unavailable  
• Temporary connection problem

**💡 Solutions:**
• Long press this message and select "Retry"
• Wait a moment and try again
• Switch to a different model
• Check with your server administrator

*Long press this message to access retry options.*''',
            timestamp: DateTime.now(),
            isStreaming: false,
          );
          ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
        } else if (error.toString().contains('timeout')) {
          // Timeout errors
          final errorMessage = ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '''⏱️ **Request Timeout**

This might be because:
• Server taking too long to respond
• Internet connection is slow
• Model processing a complex request

**💡 Solutions:**
• Long press this message and select "Retry"
• Try a shorter message
• Check your internet connection
• Switch to a faster model

*Long press this message to access retry options.*''',
            timestamp: DateTime.now(),
            isStreaming: false,
          );
          ref.read(chatMessagesProvider.notifier).addMessage(errorMessage);
        }

        // Don't throw the error to prevent unhandled exceptions
        // The error message has been added to the chat
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

// Trigger title generation using the dedicated endpoint
Future<void> _triggerTitleGeneration(
  dynamic ref,
  String conversationId,
  List<Map<String, dynamic>> messages,
  String model,
) async {
  try {
    final api = ref.read(apiServiceProvider);
    if (api == null) return;

    // Call the title generation endpoint
    final generatedTitle = await api.generateTitle(
      conversationId: conversationId,
      messages: messages,
      model: model,
    );

    if (generatedTitle != null &&
        generatedTitle.isNotEmpty &&
        generatedTitle != 'New Chat') {
      // Update the active conversation with the new title
      final activeConversation = ref.read(activeConversationProvider);
      if (activeConversation?.id == conversationId) {
        final updated = activeConversation!.copyWith(
          title: generatedTitle,
          updatedAt: DateTime.now(),
        );
        ref.read(activeConversationProvider.notifier).state = updated;

        // Save the updated title to the server
        try {
          final currentMessages = ref.read(chatMessagesProvider);
          await api.updateConversationWithMessages(
            conversationId,
            currentMessages,
            title: generatedTitle,
            model: model,
          );
        } catch (e) {
          // Handle title save errors silently
        }

        // Refresh the conversations list
        ref.invalidate(conversationsProvider);
      }
    } else {
      // Fall back to background checking
      _checkForTitleInBackground(ref, conversationId);
    }
  } catch (e) {
    // Fall back to background checking
    _checkForTitleInBackground(ref, conversationId);
  }
}

// Background function to check for title updates without blocking UI
Future<void> _checkForTitleInBackground(
  dynamic ref,
  String conversationId,
) async {
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
        break; // Stop on error
      }
    }
  } catch (e) {
    // Handle background title check errors silently
  }
}

// Save current conversation to OpenWebUI server
Future<void> _saveConversationToServer(dynamic ref) async {
  try {
    final api = ref.read(apiServiceProvider);
    final messages = ref.read(chatMessagesProvider);
    final activeConversation = ref.read(activeConversationProvider);
    final selectedModel = ref.read(selectedModelProvider);

    if (api == null || messages.isEmpty || activeConversation == null) {
      return;
    }

    // Check if the last assistant message is truly empty (no text and no files)
    final lastMessage = messages.last;
    if (lastMessage.role == 'assistant' &&
        lastMessage.content.trim().isEmpty &&
        (lastMessage.files == null || lastMessage.files!.isEmpty) &&
        (lastMessage.attachmentIds == null ||
            lastMessage.attachmentIds!.isEmpty)) {
      return;
    }

    // Update the existing conversation with all messages (including assistant response)

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
    } catch (e) {
      // Fallback to local storage if server update fails
      await _saveConversationLocally(ref);
      return;
    }

    // Refresh conversations list to show the updated conversation
    // Adding a small delay to prevent rapid invalidations that could cause duplicates
    Future.delayed(const Duration(milliseconds: 100), () {
      try {
        if (ref.mounted == true) {
          ref.invalidate(conversationsProvider);
        }
      } catch (_) {}
    });
  } catch (e) {
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
    final existingIndex = conversations.indexWhere(
      (c) => c['id'] == updatedConversation.id,
    );
    if (existingIndex >= 0) {
      conversations[existingIndex] = updatedConversation.toJson();
    } else {
      conversations.add(updatedConversation.toJson());
    }

    await storage.setString('conversations', jsonEncode(conversations));
    ref.read(activeConversationProvider.notifier).state = updatedConversation;
    ref.invalidate(conversationsProvider);
  } catch (e) {
    // Handle local storage errors silently
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
final regenerateLastMessageProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final messages = ref.read(chatMessagesProvider);
    if (messages.length < 2) return;

    // Find last user message with proper bounds checking
    ChatMessage? lastUserMessage;
    // Detect if last assistant message had generated images
    final ChatMessage? lastAssistantMessage = messages.isNotEmpty
        ? messages.last
        : null;
    final bool lastAssistantHadImages =
        lastAssistantMessage != null &&
        lastAssistantMessage.role == 'assistant' &&
        (lastAssistantMessage.files?.any((f) => f['type'] == 'image') == true);
    for (int i = messages.length - 2; i >= 0 && i < messages.length; i--) {
      if (i >= 0 && messages[i].role == 'user') {
        lastUserMessage = messages[i];
        break;
      }
    }

    if (lastUserMessage == null) return;

    // Remove last assistant message
    ref.read(chatMessagesProvider.notifier).removeLastMessage();

    // If previous assistant was image-only or had images, regenerate images instead of text
    if (lastAssistantHadImages) {
      final api = ref.read(apiServiceProvider);
      final selectedModel = ref.read(selectedModelProvider);
      if (api == null || selectedModel == null) return;

      // Add assistant placeholder
      final placeholder = ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content: '',
        timestamp: DateTime.now(),
        model: selectedModel.id,
        isStreaming: true,
      );
      ref.read(chatMessagesProvider.notifier).addMessage(placeholder);

      try {
        final imageResponse = await api.generateImage(
          prompt: lastUserMessage.content,
        );

        List<Map<String, dynamic>> extractGeneratedFiles(dynamic resp) {
          final results = <Map<String, dynamic>>[];
          if (resp is List) {
            for (final item in resp) {
              if (item is String && item.isNotEmpty) {
                results.add({'type': 'image', 'url': item});
              } else if (item is Map) {
                final url = item['url'];
                final b64 = item['b64_json'] ?? item['b64'];
                if (url is String && url.isNotEmpty) {
                  results.add({'type': 'image', 'url': url});
                } else if (b64 is String && b64.isNotEmpty) {
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              }
            }
            return results;
          }
          if (resp is! Map) return results;
          final data = resp['data'];
          if (data is List) {
            for (final item in data) {
              if (item is Map) {
                final url = item['url'];
                final b64 = item['b64_json'] ?? item['b64'];
                if (url is String && url.isNotEmpty) {
                  results.add({'type': 'image', 'url': url});
                } else if (b64 is String && b64.isNotEmpty) {
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              } else if (item is String && item.isNotEmpty) {
                results.add({'type': 'image', 'url': item});
              }
            }
          }
          final images = resp['images'];
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
                  results.add({
                    'type': 'image',
                    'url': 'data:image/png;base64,$b64',
                  });
                }
              }
            }
          }
          final singleUrl = resp['url'];
          if (singleUrl is String && singleUrl.isNotEmpty) {
            results.add({'type': 'image', 'url': singleUrl});
          }
          final singleB64 = resp['b64_json'] ?? resp['b64'];
          if (singleB64 is String && singleB64.isNotEmpty) {
            results.add({
              'type': 'image',
              'url': 'data:image/png;base64,$singleB64',
            });
          }
          return results;
        }

        final generatedFiles = extractGeneratedFiles(imageResponse);
        if (generatedFiles.isNotEmpty) {
          ref
              .read(chatMessagesProvider.notifier)
              .updateLastMessageWithFunction(
                (ChatMessage m) =>
                    m.copyWith(files: generatedFiles, isStreaming: false),
              );
          await _saveConversationToServer(ref);

          // Trigger title generation after image-only regenerate
          final activeConv = ref.read(activeConversationProvider);
          if (activeConv != null) {
            final currentMsgs = ref.read(chatMessagesProvider);
            final List<Map<String, dynamic>> formatted = [];
            for (final msg in currentMsgs) {
              formatted.add({
                'id': msg.id,
                'role': msg.role,
                'content': msg.content,
                'timestamp': msg.timestamp.millisecondsSinceEpoch ~/ 1000,
              });
            }
            _triggerTitleGeneration(
              ref,
              activeConv.id,
              formatted,
              selectedModel.id,
            );
          }
        } else {
          ref.read(chatMessagesProvider.notifier).finishStreaming();
        }
      } catch (e) {
        ref.read(chatMessagesProvider.notifier).finishStreaming();
      }
      return;
    }

    // Resend the message via normal flow
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

// ========== Tool Servers (OpenAPI) Helpers ==========

Future<List<Map<String, dynamic>>> _resolveToolServers(
  List rawServers,
  dynamic api,
) async {
  final List<Map<String, dynamic>> resolved = [];
  for (final s in rawServers) {
    try {
      if (s is! Map) continue;
      final cfg = s['config'];
      if (cfg is Map && cfg['enable'] != true) continue;

      final url = (s['url'] ?? '').toString();
      final path = (s['path'] ?? '').toString();
      if (url.isEmpty || path.isEmpty) continue;
      final fullUrl = path.contains('://')
          ? path
          : '$url${path.startsWith('/') ? '' : '/'}$path';

      // Fetch OpenAPI spec (supports YAML/JSON)
      Map<String, dynamic>? openapi;
      try {
        final resp = await api.dio.get(fullUrl);
        final ct = resp.headers.map['content-type']?.join(',') ?? '';
        if (fullUrl.toLowerCase().endsWith('.yaml') ||
            fullUrl.toLowerCase().endsWith('.yml') ||
            ct.contains('yaml')) {
          final doc = yaml.loadYaml(resp.data);
          openapi = json.decode(json.encode(doc)) as Map<String, dynamic>;
        } else {
          final data = resp.data;
          if (data is Map<String, dynamic>) {
            openapi = data;
          } else if (data is String) {
            openapi = json.decode(data) as Map<String, dynamic>;
          }
        }
      } catch (_) {
        continue;
      }
      if (openapi == null) continue;

      // Convert OpenAPI to tool specs
      final specs = _convertOpenApiToToolPayload(openapi);
      resolved.add({
        'url': url,
        'openapi': openapi,
        'info': openapi['info'],
        'specs': specs,
      });
    } catch (_) {
      continue;
    }
  }
  return resolved;
}

Map<String, dynamic>? _resolveRef(String ref, Map<String, dynamic>? components) {
  // e.g., #/components/schemas/MySchema
  if (!ref.startsWith('#/')) return null;
  final parts = ref.split('/');
  if (parts.length < 4) return null;
  final type = parts[2]; // schemas
  final name = parts[3];
  final section = components?[type];
  if (section is Map<String, dynamic>) {
    final schema = section[name];
    if (schema is Map<String, dynamic>) return Map<String, dynamic>.from(schema);
  }
  return null;
}

Map<String, dynamic> _resolveSchemaSimple(
  dynamic schema,
  Map<String, dynamic>? components,
) {
  if (schema is Map<String, dynamic>) {
    if (schema.containsKey(r'$ref')) {
      final ref = schema[r'$ref'] as String;
      final resolved = _resolveRef(ref, components);
      if (resolved != null) return _resolveSchemaSimple(resolved, components);
    }
    final type = schema['type'];
    final out = <String, dynamic>{};
    if (type is String) {
      out['type'] = type;
      if (schema['description'] != null) out['description'] = schema['description'];
      if (type == 'object') {
        out['properties'] = <String, dynamic>{};
        if (schema['required'] is List) out['required'] = List.from(schema['required']);
        final props = schema['properties'];
        if (props is Map<String, dynamic>) {
          props.forEach((k, v) {
            out['properties'][k] = _resolveSchemaSimple(v, components);
          });
        }
      } else if (type == 'array') {
        out['items'] = _resolveSchemaSimple(schema['items'], components);
      }
    }
    return out;
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _convertOpenApiToToolPayload(Map<String, dynamic> openApi) {
  final tools = <Map<String, dynamic>>[];
  final paths = openApi['paths'];
  if (paths is! Map) return tools;
  paths.forEach((path, methods) {
    if (methods is! Map) return;
    methods.forEach((method, operation) {
      if (operation is Map && operation['operationId'] != null) {
        final tool = <String, dynamic>{
          'name': operation['operationId'],
          'description': operation['description'] ?? operation['summary'] ?? 'No description available.',
          'parameters': {
            'type': 'object',
            'properties': <String, dynamic>{},
            'required': <dynamic>[],
          },
        };
        // Parameters
        final params = operation['parameters'];
        if (params is List) {
          for (final p in params) {
            if (p is Map) {
              final name = p['name'];
              final schema = p['schema'] as Map?;
              if (name != null && schema != null) {
                String desc = (schema['description'] ?? p['description'] ?? '').toString();
                if (schema['enum'] is List) {
                  desc = '$desc. Possible values: ${(schema['enum'] as List).join(', ')}';
                }
                tool['parameters']['properties'][name] = {
                  'type': schema['type'],
                  'description': desc,
                };
                if (p['required'] == true) {
                  (tool['parameters']['required'] as List).add(name);
                }
              }
            }
          }
        }
        // requestBody
        final reqBody = operation['requestBody'];
        if (reqBody is Map) {
          final content = reqBody['content'];
          if (content is Map && content['application/json'] is Map) {
            final schema = content['application/json']['schema'];
            final resolved = _resolveSchemaSimple(schema, openApi['components'] as Map<String, dynamic>?);
            if (resolved['properties'] is Map) {
              tool['parameters']['properties'] = {
                ...tool['parameters']['properties'],
                ...resolved['properties'] as Map<String, dynamic>,
              };
              if (resolved['required'] is List) {
                final req = Set.from(tool['parameters']['required'] as List)
                  ..addAll(resolved['required'] as List);
                tool['parameters']['required'] = req.toList();
              }
            } else if (resolved['type'] == 'array') {
              tool['parameters'] = resolved;
            }
          }
        }
        tools.add(tool);
      }
    });
  });
  return tools;
}
