import 'dart:convert';
import 'package:yaml/yaml.dart' as yaml;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/tool_calls_parser.dart';
import '../../../core/services/streaming_helper.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/auth/auth_state_manager.dart';
import '../../../core/utils/stream_chunker.dart';
import '../../../core/services/persistent_streaming_service.dart';
import '../../../core/utils/debug_logger.dart';
import '../../../core/utils/inactivity_watchdog.dart';
import '../services/reviewer_mode_service.dart';
import '../../../shared/services/tasks/task_queue.dart';
import '../../tools/providers/tools_providers.dart';
import 'dart:async';

const bool kSocketVerboseLogging = false;

// Chat messages for current conversation
final chatMessagesProvider =
    NotifierProvider<ChatMessagesNotifier, List<ChatMessage>>(
      ChatMessagesNotifier.new,
    );

// Loading state for conversation (used to show chat skeletons during fetch)
final isLoadingConversationProvider =
    NotifierProvider<IsLoadingConversationNotifier, bool>(
      IsLoadingConversationNotifier.new,
    );

// Prefilled input text (e.g., when sharing text from other apps)
final prefilledInputTextProvider =
    NotifierProvider<PrefilledInputTextNotifier, String?>(
      PrefilledInputTextNotifier.new,
    );

// Trigger to request focus on the chat input (increment to signal)
final inputFocusTriggerProvider =
    NotifierProvider<InputFocusTriggerNotifier, int>(
      InputFocusTriggerNotifier.new,
    );

// Whether the chat composer currently has focus
final composerHasFocusProvider = NotifierProvider<ComposerFocusNotifier, bool>(
  ComposerFocusNotifier.new,
);

class IsLoadingConversationNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class PrefilledInputTextNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;

  void clear() => state = null;
}

class InputFocusTriggerNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;

  int increment() {
    final next = state + 1;
    state = next;
    return next;
  }
}

class ComposerFocusNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class ChatMessagesNotifier extends Notifier<List<ChatMessage>> {
  StreamSubscription? _messageStream;
  ProviderSubscription? _conversationListener;
  final List<StreamSubscription> _subscriptions = [];
  // Activity-based watchdog to prevent stuck typing indicator
  InactivityWatchdog? _typingWatchdog;

  bool _initialized = false;

  @override
  List<ChatMessage> build() {
    if (!_initialized) {
      _initialized = true;
      _conversationListener = ref.listen(activeConversationProvider, (
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
            // Primary rule: adopt server messages when there are strictly more of them.
            if (serverMessages.length > state.length) {
              state = serverMessages;
              return;
            }

            // Secondary rule: if counts are equal but the last assistant message grew,
            // adopt the server copy to recover from missed socket events.
            if (serverMessages.isNotEmpty && state.isNotEmpty) {
              final serverLast = serverMessages.last;
              final localLast = state.last;
              final serverText = serverLast.content.trim();
              final localText = localLast.content.trim();
              final sameLastId = serverLast.id == localLast.id;
              final isAssistant = serverLast.role == 'assistant';
              final serverHasMore =
                  serverText.isNotEmpty && serverText.length > localText.length;
              final localEmptyButServerHas =
                  localText.isEmpty && serverText.isNotEmpty;
              if (sameLastId &&
                  isAssistant &&
                  (serverHasMore || localEmptyButServerHas)) {
                state = serverMessages;
                return;
              }
            }
          }
          return;
        }

        // Cancel any existing message stream when switching conversations
        _cancelMessageStream();
        // Also cancel typing guard on conversation switch
        _cancelTypingGuard();

        if (next != null) {
          state = next.messages;

          // Update selected model if conversation has a different model
          _updateModelForConversation(next);
        } else {
          state = [];
        }
      });

      ref.onDispose(() {
        for (final subscription in _subscriptions) {
          subscription.cancel();
        }
        _subscriptions.clear();

        _cancelMessageStream();
        _cancelTypingGuard();

        _conversationListener?.close();
        _conversationListener = null;
      });
    }

    final activeConversation = ref.read(activeConversationProvider);
    return activeConversation?.messages ?? const [];
  }

  void _addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  void _cancelMessageStream() {
    _messageStream?.cancel();
    _messageStream = null;
  }

  void _cancelTypingGuard() {
    _typingWatchdog?.stop();
    _typingWatchdog = null;
  }

  void _scheduleTypingGuard({Duration? timeout}) {
    // Default timeout tuned to balance long tool gaps and UX
    final effectiveTimeout = timeout ?? const Duration(seconds: 25);
    _typingWatchdog ??= InactivityWatchdog(
      window: effectiveTimeout,
      onTimeout: () async {
        try {
          if (state.isEmpty) return;
          final last = state.last;
          // Still the same streaming message and no finish signal
          if (last.role == 'assistant' && last.isStreaming) {
            // Attempt a soft recovery: if content is still empty, try fetching final content from server
            if ((last.content).trim().isEmpty) {
              try {
                final apiSvc = ref.read(apiServiceProvider);
                final activeConv = ref.read(activeConversationProvider);
                final msgId = last.id;
                final chatId = activeConv?.id;
                if (apiSvc != null && chatId != null && chatId.isNotEmpty) {
                  final resp = await apiSvc.dio.get('/api/v1/chats/$chatId');
                  final data = resp.data as Map<String, dynamic>;
                  String content = '';
                  final chatObj = data['chat'] as Map<String, dynamic>?;
                  if (chatObj != null) {
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
                            content =
                                (textItem as Map)['text']?.toString() ?? '';
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
                              content =
                                  (textItem as Map)['text']?.toString() ?? '';
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
              } catch (_) {}
            }
            // Regardless of fetch result, ensure UI is not stuck
            finishStreaming();
          }
        } finally {
          _cancelTypingGuard();
        }
      },
    );
    _typingWatchdog!.setWindow(effectiveTimeout);
    _typingWatchdog!.ping();
  }

  void _touchStreamingActivity() {
    // Keep guard alive while streaming
    if (state.isNotEmpty) {
      final last = state.last;
      if (last.role == 'assistant' && last.isStreaming) {
        // Compute a dynamic timeout based on flow type
        Duration timeout = const Duration(seconds: 25);
        try {
          final meta = last.metadata ?? const <String, dynamic>{};
          final isBgFlow = (meta['backgroundFlow'] == true);
          final isWebSearchFlow =
              (meta['webSearchFlow'] == true) ||
              (meta['webSearchActive'] == true);
          final isImageGenFlow = (meta['imageGenerationFlow'] == true);

          // Also consult global toggles if metadata not present
          final globalWebSearch = ref.read(webSearchEnabledProvider);
          final webSearchAvailable = ref.read(webSearchAvailableProvider);
          final globalImageGen = ref.read(imageGenerationEnabledProvider);

          // Extend guard windows to tolerate long reasoning/tools (> 1 min)
          if (isWebSearchFlow || (globalWebSearch && webSearchAvailable)) {
            if (timeout.inSeconds < 60) timeout = const Duration(seconds: 60);
          }
          if (isBgFlow) {
            // Background tools/dynamic channel can be much longer
            if (timeout.inSeconds < 120) timeout = const Duration(seconds: 120);
          }
          if (isImageGenFlow || globalImageGen) {
            // Image generation tends to be the longest
            if (timeout.inSeconds < 180) timeout = const Duration(seconds: 180);
          }
        } catch (_) {}

        _scheduleTypingGuard(timeout: timeout);
      }
    }
  }

  // Public wrapper to cancel the currently active stream (used by Stop)
  void cancelActiveMessageStream() {
    _cancelMessageStream();
  }

  Future<void> _updateModelForConversation(Conversation conversation) async {
    // Check if conversation has a model specified
    if (conversation.model == null || conversation.model!.isEmpty) {
      return;
    }

    final currentSelectedModel = ref.read(selectedModelProvider);

    // If the conversation's model is different from the currently selected one
    if (currentSelectedModel?.id != conversation.model) {
      // Get available models to find the matching one
      try {
        final models = await ref.read(modelsProvider.future);

        if (models.isEmpty) {
          return;
        }

        // Look for exact match first
        final conversationModel = models
            .where((model) => model.id == conversation.model)
            .firstOrNull;

        if (conversationModel != null) {
          // Update the selected model
          ref.read(selectedModelProvider.notifier).set(conversationModel);
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
    if (message.role == 'assistant' && message.isStreaming) {
      _touchStreamingActivity();
    }
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
    _touchStreamingActivity();
  }

  void updateLastMessageWithFunction(
    ChatMessage Function(ChatMessage) updater,
  ) {
    if (state.isEmpty) return;

    final lastMessage = state.last;
    if (lastMessage.role != 'assistant') return;
    final updated = updater(lastMessage);
    state = [...state.sublist(0, state.length - 1), updated];
    if (updated.isStreaming) {
      _touchStreamingActivity();
    }
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
    _touchStreamingActivity();
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
    _touchStreamingActivity();
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
    _cancelTypingGuard();

    // Trigger a refresh of the conversations list so UI like the Chats Drawer
    // can pick up updated titles and ordering once streaming completes.
    // Best-effort: ignore if ref lifecycle/context prevents invalidation.
    try {
      ref.invalidate(conversationsProvider);
    } catch (_) {}
  }
}

// Pre-seed an assistant skeleton message (with a given id or a new one),
// persist it to the server to keep the chain correct, and return the id.
Future<String> _preseedAssistantAndPersist(
  dynamic ref, {
  String? existingAssistantId,
  required String modelId,
  String? systemPrompt,
}) async {
  final api = ref.read(apiServiceProvider);
  final activeConv = ref.read(activeConversationProvider);

  // Choose id: reuse existing if provided, else create new
  final String assistantMessageId =
      (existingAssistantId != null && existingAssistantId.isNotEmpty)
      ? existingAssistantId
      : const Uuid().v4();

  // If the message with this id doesn't exist locally, add a placeholder
  final msgs = ref.read(chatMessagesProvider);
  final exists = msgs.any((m) => m.id == assistantMessageId);
  if (!exists) {
    final placeholder = ChatMessage(
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      model: modelId,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(placeholder);
  } else {
    // If it exists and is the last assistant, ensure we mark it streaming
    try {
      final last = msgs.isNotEmpty ? msgs.last : null;
      if (last != null &&
          last.id == assistantMessageId &&
          last.role == 'assistant' &&
          !last.isStreaming) {
        ref
            .read(chatMessagesProvider.notifier)
            .updateLastMessageWithFunction(
              (m) => m.copyWith(isStreaming: true),
            );
      }
    } catch (_) {}
  }

  // Persist the skeleton to the server so the web client sees a correct chain
  try {
    if (api != null && activeConv != null) {
      final resolvedSystemPrompt =
          (systemPrompt != null && systemPrompt.trim().isNotEmpty)
          ? systemPrompt.trim()
          : activeConv.systemPrompt;
      final current = ref.read(chatMessagesProvider);
      await api.updateConversationWithMessages(
        activeConv.id,
        current,
        model: modelId,
        systemPrompt: resolvedSystemPrompt,
      );
    }
  } catch (_) {}

  return assistantMessageId;
}

String? _extractSystemPromptFromSettings(Map<String, dynamic>? settings) {
  if (settings == null) return null;

  final rootValue = settings['system'];
  if (rootValue is String) {
    final trimmed = rootValue.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }

  final ui = settings['ui'];
  if (ui is Map<String, dynamic>) {
    final uiValue = ui['system'];
    if (uiValue is String) {
      final trimmed = uiValue.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  }

  return null;
}

// Start a new chat (unified function for both "New Chat" button and home screen)
void startNewChat(dynamic ref) {
  // Clear active conversation
  ref.read(activeConversationProvider.notifier).clear();

  // Clear messages
  ref.read(chatMessagesProvider.notifier).clearMessages();
}

// Available tools provider
final availableToolsProvider =
    NotifierProvider<AvailableToolsNotifier, List<String>>(
      AvailableToolsNotifier.new,
    );

// Web search enabled state for API-based web search
final webSearchEnabledProvider =
    NotifierProvider<WebSearchEnabledNotifier, bool>(
      WebSearchEnabledNotifier.new,
    );

// Image generation enabled state - behaves like web search
final imageGenerationEnabledProvider =
    NotifierProvider<ImageGenerationEnabledNotifier, bool>(
      ImageGenerationEnabledNotifier.new,
    );

// Vision capable models provider
final visionCapableModelsProvider =
    NotifierProvider<VisionCapableModelsNotifier, List<String>>(
      VisionCapableModelsNotifier.new,
    );

// File upload capable models provider
final fileUploadCapableModelsProvider =
    NotifierProvider<FileUploadCapableModelsNotifier, List<String>>(
      FileUploadCapableModelsNotifier.new,
    );

class AvailableToolsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void set(List<String> tools) => state = List<String>.from(tools);
}

class WebSearchEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class ImageGenerationEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class VisionCapableModelsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final selectedModel = ref.watch(selectedModelProvider);
    if (selectedModel == null) {
      return [];
    }

    if (selectedModel.isMultimodal == true) {
      return [selectedModel.id];
    }

    // For now, assume all models support vision unless explicitly marked
    return [selectedModel.id];
  }
}

class FileUploadCapableModelsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final selectedModel = ref.watch(selectedModelProvider);
    if (selectedModel == null) {
      return [];
    }

    // For now, assume all models support file upload
    return [selectedModel.id];
  }
}

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

// Small internal helper to convert a message with attachments into the
// OpenWebUI content payload format (text + image_url + files).
// - Adds text first (if non-empty)
// - Converts image attachments to image_url with data URLs (resolving MIME type when needed)
// - Includes non-image attachments in a 'files' array for server-side resolution
Future<Map<String, dynamic>> _buildMessagePayloadWithAttachments({
  required dynamic api,
  required String role,
  required String cleanedText,
  required List<String> attachmentIds,
}) async {
  final List<Map<String, dynamic>> contentArray = [];
  final List<Map<String, dynamic>> nonImageFiles = [];

  if (cleanedText.isNotEmpty) {
    contentArray.add({'type': 'text', 'text': cleanedText});
  }

  for (final attachmentId in attachmentIds) {
    try {
      final base64Data = await _getFileAsBase64(api, attachmentId);
      if (base64Data != null) {
        if (base64Data.startsWith('data:')) {
          contentArray.add({
            'type': 'image_url',
            'image_url': {'url': base64Data},
          });
        } else {
          if (!attachmentId.startsWith('data:')) {
            final fileInfo = await api.getFileInfo(attachmentId);
            final fileName = fileInfo['filename'] ?? '';
            final ext = fileName.toLowerCase().split('.').last;

            String mimeType = 'image/png';
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
        nonImageFiles.add({'id': attachmentId, 'type': 'file'});
      }
    } catch (_) {
      // Swallow and continue to keep regeneration robust
    }
  }

  final messageMap = <String, dynamic>{
    'role': role,
    'content': contentArray.isNotEmpty ? contentArray : cleanedText,
  };
  if (nonImageFiles.isNotEmpty) {
    messageMap['files'] = nonImageFiles;
  }
  return messageMap;
}

// Regenerate message function that doesn't duplicate user message
Future<void> regenerateMessage(
  dynamic ref,
  String userMessageContent,
  List<String>? attachments,
) async {
  final reviewerMode = ref.read(reviewerModeProvider);
  final api = ref.read(apiServiceProvider);
  final selectedModel = ref.read(selectedModelProvider);

  if ((!reviewerMode && api == null) || selectedModel == null) {
    throw Exception('No API service or model selected');
  }

  var activeConversation = ref.read(activeConversationProvider);
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

    // Helpers defined above

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
    Map<String, dynamic>? userSettingsData;
    String? userSystemPrompt;
    try {
      userSettingsData = await api!.getUserSettings();
      userSystemPrompt = _extractSystemPromptFromSettings(userSettingsData);
    } catch (_) {}

    if ((activeConversation.systemPrompt == null ||
            activeConversation.systemPrompt!.trim().isEmpty) &&
        (userSystemPrompt?.isNotEmpty ?? false)) {
      final updated = activeConversation.copyWith(
        systemPrompt: userSystemPrompt,
      );
      ref.read(activeConversationProvider.notifier).set(updated);
      activeConversation = updated;
    }

    // Include selected tool ids so provider-native tool calling is triggered
    final selectedToolIds = ref.read(selectedToolIdsProvider);
    // Get conversation history for context (excluding the removed assistant message)
    final List<ChatMessage> messages = ref.read(chatMessagesProvider);
    final List<Map<String, dynamic>> conversationMessages =
        <Map<String, dynamic>>[];

    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (msg.role.isNotEmpty && msg.content.isNotEmpty && !msg.isStreaming) {
        final cleaned = ToolCallsParser.sanitizeForApi(msg.content);

        // Prefer provided attachments for the last user message; otherwise use message attachments
        final bool isLastUser =
            (i == messages.length - 1) && msg.role == 'user';
        final List<String> messageAttachments =
            (isLastUser && (attachments != null && attachments.isNotEmpty))
            ? List<String>.from(attachments)
            : (msg.attachmentIds ?? const <String>[]);

        if (messageAttachments.isNotEmpty) {
          final messageMap = await _buildMessagePayloadWithAttachments(
            api: api,
            role: msg.role,
            cleanedText: cleaned,
            attachmentIds: messageAttachments,
          );
          conversationMessages.add(messageMap);
        } else {
          conversationMessages.add({'role': msg.role, 'content': cleaned});
        }
      }
    }

    final conversationSystemPrompt = activeConversation.systemPrompt?.trim();
    final effectiveSystemPrompt =
        (conversationSystemPrompt != null &&
            conversationSystemPrompt.isNotEmpty)
        ? conversationSystemPrompt
        : userSystemPrompt;
    if (effectiveSystemPrompt != null && effectiveSystemPrompt.isNotEmpty) {
      final hasSystemMessage = conversationMessages.any(
        (m) => (m['role']?.toString().toLowerCase() ?? '') == 'system',
      );
      if (!hasSystemMessage) {
        conversationMessages.insert(0, {
          'role': 'system',
          'content': effectiveSystemPrompt,
        });
      }
    }

    // Pre-seed assistant skeleton and persist chain
    final String assistantMessageId = await _preseedAssistantAndPersist(
      ref,
      modelId: selectedModel.id,
      systemPrompt: effectiveSystemPrompt,
    );

    // Feature toggles
    final webSearchEnabled =
        ref.read(webSearchEnabledProvider) &&
        ref.read(webSearchAvailableProvider);
    final imageGenerationEnabled = ref.read(imageGenerationEnabledProvider);

    // Model metadata for completion notifications
    final supportedParams =
        selectedModel.supportedParameters ??
        [
          'max_tokens',
          'tool_choice',
          'tools',
          'response_format',
          'structured_outputs',
        ];
    final modelItem = {
      'id': selectedModel.id,
      'canonical_slug': selectedModel.id,
      'hugging_face_id': '',
      'name': selectedModel.name,
      'created': 1754089419,
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

    // Socket binding for background flows
    final socketService = ref.read(socketServiceProvider);
    String? socketSessionId = socketService?.sessionId;
    bool wantSessionBinding =
        (socketService?.isConnected == true) &&
        (socketSessionId != null && socketSessionId.isNotEmpty);
    // When regenerating with tools, make a best-effort to ensure a live socket.
    if (!wantSessionBinding && socketService != null) {
      try {
        final ok = await socketService.ensureConnected();
        if (ok) {
          socketSessionId = socketService.sessionId;
          wantSessionBinding =
              socketSessionId != null && socketSessionId.isNotEmpty;
        }
      } catch (_) {}
    }

    // Resolve tool servers from user settings (if any)
    List<Map<String, dynamic>>? toolServers;
    final uiSettings = userSettingsData?['ui'] as Map<String, dynamic>?;
    final rawServers = uiSettings != null
        ? (uiSettings['toolServers'] as List?)
        : null;
    if (rawServers != null && rawServers.isNotEmpty) {
      try {
        toolServers = await _resolveToolServers(rawServers, api);
      } catch (_) {}
    }

    // Background tasks parity with Web client (safe defaults)
    bool shouldGenerateTitle = false;
    try {
      final conv = ref.read(activeConversationProvider);
      final nonSystemCount = conversationMessages
          .where((m) => (m['role']?.toString() ?? '') != 'system')
          .length;
      shouldGenerateTitle =
          (conv == null) ||
          ((conv.title == 'New Chat' || (conv.title.isEmpty)) &&
              nonSystemCount == 1);
    } catch (_) {}

    final bgTasks = <String, dynamic>{
      if (shouldGenerateTitle) 'title_generation': true,
      if (shouldGenerateTitle) 'tags_generation': true,
      'follow_up_generation': true,
      if (webSearchEnabled) 'web_search': true,
      if (imageGenerationEnabled) 'image_generation': true,
    };

    final bool isBackgroundToolsFlowPre =
        (selectedToolIds.isNotEmpty) ||
        (toolServers != null && toolServers.isNotEmpty);
    final bool isBackgroundWebSearchPre = webSearchEnabled;

    // Dispatch using unified send pipeline (background tools flow)
    final bool isBackgroundFlowPre =
        isBackgroundToolsFlowPre ||
        isBackgroundWebSearchPre ||
        imageGenerationEnabled;
    final bool passSocketSession = wantSessionBinding && isBackgroundFlowPre;
    final response = api!.sendMessage(
      messages: conversationMessages,
      model: selectedModel.id,
      conversationId: activeConversation.id,
      toolIds: selectedToolIds.isNotEmpty ? selectedToolIds : null,
      enableWebSearch: webSearchEnabled,
      enableImageGeneration: imageGenerationEnabled,
      modelItem: modelItem,
      sessionIdOverride: passSocketSession ? socketSessionId : null,
      toolServers: toolServers,
      backgroundTasks: bgTasks,
      responseMessageId: assistantMessageId,
    );

    final stream = response.stream;
    final sessionId = response.sessionId;

    // New unified streaming path via helper; bypass old inline socket block
    final bool isBackgroundFlow =
        isBackgroundToolsFlowPre ||
        isBackgroundWebSearchPre ||
        imageGenerationEnabled ||
        wantSessionBinding;
    try {
      ref.read(chatMessagesProvider.notifier).updateLastMessageWithFunction((
        m,
      ) {
        final mergedMeta = {
          if (m.metadata != null) ...m.metadata!,
          'backgroundFlow': isBackgroundFlow,
          if (isBackgroundWebSearchPre) 'webSearchFlow': true,
          if (imageGenerationEnabled) 'imageGenerationFlow': true,
        };
        return m.copyWith(metadata: mergedMeta);
      });
    } catch (_) {}

    final sendStreamSub = attachUnifiedChunkedStreaming(
      stream: stream,
      webSearchEnabled: webSearchEnabled,
      isBackgroundFlow: isBackgroundFlow,
      suppressSocketContentInitially: !isBackgroundFlow,
      usingDynamicChannelInitially: false,
      assistantMessageId: assistantMessageId,
      modelId: selectedModel.id,
      modelItem: modelItem,
      sessionId: sessionId,
      activeConversationId: activeConversation.id,
      api: api,
      socketService: socketService,
      appendToLastMessage: (c) =>
          ref.read(chatMessagesProvider.notifier).appendToLastMessage(c),
      replaceLastMessageContent: (c) =>
          ref.read(chatMessagesProvider.notifier).replaceLastMessageContent(c),
      updateLastMessageWith: (updater) => ref
          .read(chatMessagesProvider.notifier)
          .updateLastMessageWithFunction(updater),
      finishStreaming: () =>
          ref.read(chatMessagesProvider.notifier).finishStreaming(),
      getMessages: () => ref.read(chatMessagesProvider),
    );
    ref.read(chatMessagesProvider.notifier).setMessageStream(sendStreamSub);
    return;
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

  Map<String, dynamic>? userSettingsData;
  String? userSystemPrompt;
  if (!reviewerMode && api != null) {
    try {
      userSettingsData = await api.getUserSettings();
      userSystemPrompt = _extractSystemPromptFromSettings(userSettingsData);
    } catch (_) {}
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
      systemPrompt: userSystemPrompt,
      messages: [userMessage], // Include the user message
    );

    // Set as active conversation locally
    ref.read(activeConversationProvider.notifier).set(localConversation);
    activeConversation = localConversation;

    if (!reviewerMode) {
      // Try to create on server with the first message included
      try {
        final serverConversation = await api.createConversation(
          title: 'New Chat',
          messages: [userMessage], // Include the first message in creation
          model: selectedModel.id,
          systemPrompt: userSystemPrompt,
        );
        final updatedConversation = localConversation.copyWith(
          id: serverConversation.id,
          systemPrompt: serverConversation.systemPrompt ?? userSystemPrompt,
          messages: serverConversation.messages.isNotEmpty
              ? serverConversation.messages
              : [userMessage],
        );
        ref.read(activeConversationProvider.notifier).set(updatedConversation);
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

  if (activeConversation != null &&
      (activeConversation.systemPrompt == null ||
          activeConversation.systemPrompt!.trim().isEmpty) &&
      (userSystemPrompt?.isNotEmpty ?? false)) {
    final updated = activeConversation.copyWith(systemPrompt: userSystemPrompt);
    ref.read(activeConversationProvider.notifier).set(updated);
    activeConversation = updated;
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
      // Prepare cleaned text content (strip tool details etc.)
      final cleaned = ToolCallsParser.sanitizeForApi(msg.content);

      final List<String> ids = msg.attachmentIds ?? const <String>[];
      if (ids.isNotEmpty) {
        final messageMap = await _buildMessagePayloadWithAttachments(
          api: api,
          role: msg.role,
          cleanedText: cleaned,
          attachmentIds: ids,
        );
        conversationMessages.add(messageMap);
      } else {
        // Regular text-only message
        conversationMessages.add({'role': msg.role, 'content': cleaned});
      }
    }
  }

  final conversationSystemPrompt = activeConversation?.systemPrompt?.trim();
  final effectiveSystemPrompt =
      (conversationSystemPrompt != null && conversationSystemPrompt.isNotEmpty)
      ? conversationSystemPrompt
      : userSystemPrompt;
  if (effectiveSystemPrompt != null && effectiveSystemPrompt.isNotEmpty) {
    final hasSystemMessage = conversationMessages.any(
      (m) => (m['role']?.toString().toLowerCase() ?? '') == 'system',
    );
    if (!hasSystemMessage) {
      conversationMessages.insert(0, {
        'role': 'system',
        'content': effectiveSystemPrompt,
      });
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
    // Pre-seed assistant skeleton on server to ensure correct chain
    // Generate assistant message id now (must be consistent across client/server)
    final String assistantMessageId = const Uuid().v4();

    // Add assistant placeholder locally before sending
    final assistantPlaceholder = ChatMessage(
      id: assistantMessageId,
      role: 'assistant',
      content: '',
      timestamp: DateTime.now(),
      model: selectedModel.id,
      isStreaming: true,
    );
    ref.read(chatMessagesProvider.notifier).addMessage(assistantPlaceholder);

    // Persist skeleton chain to server so web can load correct history
    try {
      final activeConvForSeed = ref.read(activeConversationProvider);
      if (activeConvForSeed != null) {
        final msgsForSeed = ref.read(chatMessagesProvider);
        await api.updateConversationWithMessages(
          activeConvForSeed.id,
          msgsForSeed,
          model: selectedModel.id,
          systemPrompt: effectiveSystemPrompt,
        );
      }
    } catch (_) {}
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

    // Stream response using server-push via Socket when available, otherwise fallback
    // Resolve Socket session for background tasks parity
    final socketService = ref.read(socketServiceProvider);
    final socketSessionId = socketService?.sessionId;
    final bool wantSessionBinding =
        (socketService?.isConnected == true) &&
        (socketSessionId != null && socketSessionId.isNotEmpty);

    // Resolve tool servers from user settings (if any)
    List<Map<String, dynamic>>? toolServers;
    final uiSettings = userSettingsData?['ui'] as Map<String, dynamic>?;
    final rawServers = uiSettings != null
        ? (uiSettings['toolServers'] as List?)
        : null;
    if (rawServers != null && rawServers.isNotEmpty) {
      try {
        toolServers = await _resolveToolServers(rawServers, api);
      } catch (_) {}
    }

    // Background tasks parity with Web client (safe defaults)
    // Enable title/tags generation on the very first user turn of a new chat.
    bool shouldGenerateTitle = false;
    try {
      final conv = ref.read(activeConversationProvider);
      // Use the outbound conversationMessages we just built (excludes streaming placeholders)
      final nonSystemCount = conversationMessages
          .where((m) => (m['role']?.toString() ?? '') != 'system')
          .length;
      shouldGenerateTitle =
          (conv == null) ||
          ((conv.title == 'New Chat' || (conv.title.isEmpty)) &&
              nonSystemCount == 1);
    } catch (_) {}

    // Match web client: request background follow-ups always; title/tags on first turn
    final bgTasks = <String, dynamic>{
      if (shouldGenerateTitle) 'title_generation': true,
      if (shouldGenerateTitle) 'tags_generation': true,
      'follow_up_generation': true,
      if (webSearchEnabled) 'web_search': true, // enable bg web search
      if (imageGenerationEnabled)
        'image_generation': true, // enable bg image flow
    };

    // Determine if we need background task flow (tools/tool servers or web search)
    final bool isBackgroundToolsFlowPre =
        (toolIdsForApi != null && toolIdsForApi.isNotEmpty) ||
        (toolServers != null && toolServers.isNotEmpty);
    final bool isBackgroundWebSearchPre = webSearchEnabled;

    final response = await api.sendMessage(
      messages: conversationMessages,
      model: selectedModel.id,
      conversationId: activeConversation?.id,
      toolIds: toolIdsForApi,
      enableWebSearch: webSearchEnabled,
      // Enable image generation on the server when requested
      enableImageGeneration: imageGenerationEnabled,
      modelItem: modelItem,
      // Bind to Socket session whenever available so the server can push
      // streaming updates to this client (improves first-turn streaming).
      sessionIdOverride: wantSessionBinding ? socketSessionId : null,
      toolServers: toolServers,
      backgroundTasks: bgTasks,
      responseMessageId: assistantMessageId,
    );

    final stream = response.stream;
    final sessionId = response.sessionId;

    // (socket handlers attached below after flow flags are set)

    // If socket is available, start listening for chat-events immediately
    // Background-tools flow OR any session-bound flow relies on socket/dynamic channel for
    // streaming content. Allow socket TEXT in those modes. For pure SSE/polling flows, suppress
    // socket TEXT to avoid duplicates (still surface tool_call status).
    final bool isBackgroundFlow =
        isBackgroundToolsFlowPre ||
        isBackgroundWebSearchPre ||
        wantSessionBinding;
    bool suppressSocketContent =
        !isBackgroundFlow; // allow socket text when session-bound or tools
    bool usingDynamicChannel = false; // set true when server provides a channel
    // Attach socket handlers for background flows/dynamic channels
    if (socketService != null) {
      _attachSocketStreamingHandlers(
        ref: ref,
        socketService: socketService,
        assistantMessageId: assistantMessageId,
        modelId: selectedModel.id,
        modelItem: modelItem,
        sessionId: sessionId,
        isBackgroundFlow: isBackgroundFlow,
        suppressSocketContentInitially: suppressSocketContent,
        activeConversationId: activeConversation?.id,
      );
    }
    // Enrich the assistant placeholder metadata so the typing guard can use longer timeouts
    try {
      ref.read(chatMessagesProvider.notifier).updateLastMessageWithFunction((
        m,
      ) {
        final mergedMeta = {
          if (m.metadata != null) ...m.metadata!,
          'backgroundFlow': isBackgroundFlow,
          if (isBackgroundWebSearchPre) 'webSearchFlow': true,
          if (imageGenerationEnabled) 'imageGenerationFlow': true,
        };
        return m.copyWith(metadata: mergedMeta);
      });
    } catch (_) {}

    if (socketService != null) {
      // Activity-based watchdog for chat/channel events (resets on activity)
      final chatWatchdog = InactivityWatchdog(
        window: const Duration(minutes: 5),
        onTimeout: () {
          try {
            socketService.offChatEvents();
            socketService.offChannelEvents();
          } catch (_) {}
          // As a final safeguard, if we're still in streaming state, finish it
          try {
            final msgs = ref.read(chatMessagesProvider);
            if (msgs.isNotEmpty &&
                msgs.last.role == 'assistant' &&
                msgs.last.isStreaming) {
              ref.read(chatMessagesProvider.notifier).finishStreaming();
            }
          } catch (_) {}
        },
      )..start();

      void chatHandler(Map<String, dynamic> ev) {
        try {
          final data = ev['data'];
          if (data == null) return;
          final type = data['type'];
          final payload = data['data'];
          DebugLogger.stream('Socket chat-events: type=$type');
          // Any chat event indicates activity; reset inactivity watchdog
          // (watchdog defined below, near handler registration)
          chatWatchdog.ping();
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
                      final name = (fn is Map && fn['name'] is String)
                          ? fn['name'] as String
                          : null;
                      if (name is String && name.isNotEmpty) {
                        final msgs = ref.read(chatMessagesProvider);
                        final exists =
                            (msgs.isNotEmpty) &&
                            RegExp(
                              '<details\\s+type="tool_calls"[^>]*\\bname="${RegExp.escape(name)}"',
                              multiLine: true,
                            ).hasMatch(msgs.last.content);
                        if (!exists) {
                          final status =
                              '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                          ref
                              .read(chatMessagesProvider.notifier)
                              .appendToLastMessage(status);
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
                            final name = (fn is Map && fn['name'] is String)
                                ? fn['name'] as String
                                : null;
                            if (name is String && name.isNotEmpty) {
                              final msgs = ref.read(chatMessagesProvider);
                              final exists =
                                  (msgs.isNotEmpty) &&
                                  RegExp(
                                    '<details\\s+type="tool_calls"[^>]*\\bname="${RegExp.escape(name)}"',
                                    multiLine: true,
                                  ).hasMatch(msgs.last.content);
                              if (!exists) {
                                final status =
                                    '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                                ref
                                    .read(chatMessagesProvider.notifier)
                                    .appendToLastMessage(status);
                              }
                            }
                          }
                        }
                      }
                    }
                    final content = delta['content']?.toString() ?? '';
                    if (content.isNotEmpty) {
                      ref
                          .read(chatMessagesProvider.notifier)
                          .appendToLastMessage(content);
                      _updateImagesFromCurrentContent(ref);
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
                    _updateImagesFromCurrentContent(ref);
                  } else {
                    ref
                        .read(chatMessagesProvider.notifier)
                        .appendToLastMessage(content);
                    _updateImagesFromCurrentContent(ref);
                  }
                }
              }
              if (payload['done'] == true) {
                // Stop listening to further socket events for this session.
                try {
                  socketService.offChatEvents();
                } catch (_) {}
                try {
                  chatWatchdog.ping(); // ensure timer exists
                  chatWatchdog.stop();
                } catch (_) {}

                // Notify server that chat is completed (mirrors web client)
                try {
                  final apiSvc = ref.read(apiServiceProvider);
                  final chatId = activeConversation?.id ?? '';
                  if (apiSvc != null && chatId.isNotEmpty) {
                    unawaited(
                      apiSvc
                          .sendChatCompleted(
                            chatId: chatId,
                            messageId: assistantMessageId,
                            messages: const [],
                            model: selectedModel.id,
                            modelItem: modelItem,
                            sessionId: sessionId,
                          )
                          .timeout(const Duration(seconds: 3))
                          .catchError((_) {}),
                    );
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
                          final resp = await apiSvc.dio.get(
                            '/api/v1/chats/$chatId',
                          );
                          final data = resp.data as Map<String, dynamic>;
                          String content = '';
                          final chatObj = data['chat'] as Map<String, dynamic>?;
                          if (chatObj != null) {
                            // Prefer chat.messages list
                            final list = chatObj['messages'];
                            if (list is List) {
                              final target = list.firstWhere(
                                (m) =>
                                    (m is Map &&
                                    (m['id']?.toString() == msgId)),
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
                                    content =
                                        textItem['text']?.toString() ?? '';
                                  }
                                }
                              }
                            }
                            // Fallback to history map
                            if (content.isEmpty) {
                              final history = chatObj['history'];
                              if (history is Map &&
                                  history['messages'] is Map) {
                                final Map<String, dynamic> messagesMap =
                                    (history['messages'] as Map)
                                        .cast<String, dynamic>();
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
                                      content =
                                          textItem['text']?.toString() ?? '';
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
                          ref
                              .read(chatMessagesProvider.notifier)
                              .finishStreaming();
                        }
                      });
                      return; // Defer finish to microtask
                    }
                  }
                }
                // Normal path: finish now
                ref.read(chatMessagesProvider.notifier).finishStreaming();
                try {
                  chatWatchdog.stop();
                } catch (_) {}
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
                DebugLogger.stream(
                  'Socket request:chat:completion channel=$channel',
                );
              }
              void channelLineHandler(dynamic line) {
                try {
                  if (line is String) {
                    final s = line.trim();
                    // Dynamic channel activity
                    try {
                      chatWatchdog.ping();
                    } catch (_) {}
                    DebugLogger.stream(
                      'Socket [$channel] line=${s.length > 160 ? '${s.substring(0, 160)}…' : s}',
                    );
                    if (s == '[DONE]' || s == 'DONE') {
                      socketService.offEvent(channel);
                      // Channel completed
                      try {
                        unawaited(
                          api.sendChatCompleted(
                            chatId: activeConversation?.id ?? '',
                            messageId: assistantMessageId,
                            messages: const [],
                            model: selectedModel.id,
                            modelItem: modelItem,
                            sessionId: sessionId,
                          ),
                        );
                      } catch (_) {}
                      ref.read(chatMessagesProvider.notifier).finishStreaming();
                      return;
                    }
                    if (s.startsWith('data:')) {
                      final dataStr = s.substring(5).trim();
                      if (dataStr == '[DONE]') {
                        socketService.offEvent(channel);
                        try {
                          unawaited(
                            api.sendChatCompleted(
                              chatId: activeConversation?.id ?? '',
                              messageId: assistantMessageId,
                              messages: const [],
                              model: selectedModel.id,
                              modelItem: modelItem,
                              sessionId: sessionId,
                            ),
                          );
                        } catch (_) {}
                        ref
                            .read(chatMessagesProvider.notifier)
                            .finishStreaming();
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
                                DebugLogger.stream(
                                  'Socket [$channel] delta.content len=${c.length}',
                                );
                              }
                            }
                            // Surface tool_calls status
                            if (delta.containsKey('tool_calls')) {
                              if (kSocketVerboseLogging) {
                                DebugLogger.stream(
                                  'Socket [$channel] delta.tool_calls detected',
                                );
                              }
                              final tc = delta['tool_calls'];
                              if (tc is List) {
                                for (final call in tc) {
                                  if (call is Map<String, dynamic>) {
                                    final fn = call['function'];
                                    final name =
                                        (fn is Map && fn['name'] is String)
                                        ? fn['name'] as String
                                        : null;
                                    if (name is String && name.isNotEmpty) {
                                      final msgs = ref.read(
                                        chatMessagesProvider,
                                      );
                                      final exists =
                                          (msgs.isNotEmpty) &&
                                          RegExp(
                                            '<details\\s+type="tool_calls"[^>]*\\bname="${RegExp.escape(name)}"',
                                            multiLine: true,
                                          ).hasMatch(msgs.last.content);
                                      if (!exists) {
                                        final status =
                                            '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                                        ref
                                            .read(chatMessagesProvider.notifier)
                                            .appendToLastMessage(status);
                                      }
                                    }
                                  }
                                }
                              }
                            }
                            // Append streamed content
                            final content = delta['content']?.toString() ?? '';
                            if (content.isNotEmpty) {
                              ref
                                  .read(chatMessagesProvider.notifier)
                                  .appendToLastMessage(content);
                              _updateImagesFromCurrentContent(ref);
                            }
                          }
                        }
                      } catch (_) {
                        // Non-JSON line: append as-is
                        if (s.isNotEmpty) {
                          ref
                              .read(chatMessagesProvider.notifier)
                              .appendToLastMessage(s);
                          _updateImagesFromCurrentContent(ref);
                        }
                      }
                    } else {
                      // Plain text line
                      if (s.isNotEmpty) {
                        ref
                            .read(chatMessagesProvider.notifier)
                            .appendToLastMessage(s);
                        _updateImagesFromCurrentContent(ref);
                      }
                    }
                  } else if (line is Map) {
                    // If server sends { done: true } via channel
                    final done = line['done'] == true;
                    if (done) {
                      socketService.offEvent(channel);
                      try {
                        unawaited(
                          api.sendChatCompleted(
                            chatId: activeConversation?.id ?? '',
                            messageId: assistantMessageId,
                            messages: const [],
                            model: selectedModel.id,
                            modelItem: modelItem,
                            sessionId: sessionId,
                          ),
                        );
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
          } else if (type == 'chat:message:error' && payload != null) {
            // Surface error associated with the current assistant message
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
                ref
                    .read(chatMessagesProvider.notifier)
                    .replaceLastMessageContent('⚠️ $content');
              }
            } catch (_) {}
            ref.read(chatMessagesProvider.notifier).finishStreaming();
          } else if (type == 'execute:tool' && payload != null) {
            // Show an executing tile immediately using provided tool info
            try {
              final name = payload['name']?.toString() ?? 'tool';
              DebugLogger.stream('Socket execute:tool name=$name');
              final status =
                  '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
              ref
                  .read(chatMessagesProvider.notifier)
                  .appendToLastMessage(status);
              // If tool payload already carries files/result, try to extract images for grid
              try {
                final files = _extractFilesFromResult(payload['files']);
                final resultFiles = _extractFilesFromResult(payload['result']);
                final all = [...files, ...resultFiles];
                if (all.isNotEmpty) {
                  final msgs = ref.read(chatMessagesProvider);
                  if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
                    final existing =
                        msgs.last.files ?? <Map<String, dynamic>>[];
                    final seen = <String>{
                      for (final f in existing)
                        if (f['url'] is String) (f['url'] as String) else '',
                    }..removeWhere((e) => e.isEmpty);
                    final merged = <Map<String, dynamic>>[...existing];
                    for (final f in all) {
                      final url = f['url'] as String?;
                      if (url != null &&
                          url.isNotEmpty &&
                          !seen.contains(url)) {
                        merged.add({'type': 'image', 'url': url});
                        seen.add(url);
                      }
                    }
                    if (merged.length != existing.length) {
                      ref
                          .read(chatMessagesProvider.notifier)
                          .updateLastMessageWithFunction(
                            (m) => m.copyWith(files: merged),
                          );
                    }
                  }
                }
              } catch (_) {}
            } catch (_) {}
          } else if ((type == 'files' || type == 'chat:message:files') &&
              payload != null) {
            // Handle files event from socket (image generation results)
            try {
              DebugLogger.stream(
                'Socket files event received: ${payload.toString()}',
              );
              final files = _extractFilesFromResult(payload);
              if (files.isNotEmpty) {
                final msgs = ref.read(chatMessagesProvider);
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
                    DebugLogger.stream(
                      'Socket files: Adding ${merged.length - existing.length} new images',
                    );
                    final updatedMessage = ref
                        .read(chatMessagesProvider)
                        .last
                        .copyWith(files: merged);
                    DebugLogger.stream(
                      'Socket files: Updated message files count: ${updatedMessage.files?.length}',
                    );
                    ref
                        .read(chatMessagesProvider.notifier)
                        .updateLastMessageWithFunction(
                          (ChatMessage m) => m.copyWith(files: merged),
                        );
                  }
                }
              }
            } catch (e) {
              DebugLogger.stream('Socket files event error: $e');
            }
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
          DebugLogger.stream('Socket channel-events: type=$type');
          // Handle generic channel progress messages if needed
          if (type == 'message' && payload is Map) {
            final content = payload['content']?.toString() ?? '';
            if (content.isNotEmpty) {
              ref
                  .read(chatMessagesProvider.notifier)
                  .appendToLastMessage(content);
              _updateImagesFromCurrentContent(ref);
              chatWatchdog.ping();
            }
          }
        } catch (_) {}
      }

      socketService.onChannelEvents(channelEventsHandler);
      // Start activity watchdog
      chatWatchdog.ping();
    }

    // Prepare streaming and background handling
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

    final streamId = persistentService.registerStream(
      subscription: chunkedStream.listen(
        (chunk) {
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

    // Image generation handled server-side via tools; no client pre-request

    // For built-in web search, the status will be updated when function calls are detected
    // in the streaming response. Manual status update is not needed here.

    // (moved above) streaming registration is already set up

    // Track web search status
    bool isSearching = false;

    // Helpers were defined above

    int chunkSeq = 0;
    final streamSubscription = persistentController.stream.listen(
      (chunk) {
        chunkSeq += 1;
        try {
          persistentService.updateStreamProgress(
            streamId,
            chunkSequence: chunkSeq,
            appendedContent: chunk,
          );
        } catch (_) {}
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
                (message) =>
                    message.copyWith(metadata: {'webSearchActive': false}),
              );
          // Strip markers from this chunk and continue processing
          effectiveChunk = effectiveChunk
              .replaceAll('[SEARCHING]', '')
              .replaceAll('[/SEARCHING]', '');
        }

        // Regular content - append to message (markers removed above)
        if (effectiveChunk.trim().isNotEmpty) {
          ref
              .read(chatMessagesProvider.notifier)
              .appendToLastMessage(effectiveChunk);
          _updateImagesFromCurrentContent(ref);
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
        // Allow socket content again for future sessions (harmless if already false)
        suppressSocketContent = false;
        // If this path was SSE-driven (no background tools/dynamic channel), finish now.
        // Otherwise keep streaming state until socket/dynamic channel signals done.
        if (!usingDynamicChannel && !isBackgroundFlow) {
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
              if (!isBackgroundFlow && !usingDynamicChannel) {
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

                  ref
                      .read(activeConversationProvider.notifier)
                      .set(updatedConversation);
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

        // Do not persist conversation to server here. Server manages chat state.
        // Keep local save only for quick resume.
        await Future.delayed(const Duration(milliseconds: 50));
        await _saveConversationLocally(ref);

        // Removed post-assistant image generation; images are handled immediately after user message
      },
      onError: (error) {
        // Mark streaming as complete on error
        ref.read(chatMessagesProvider.notifier).finishStreaming();
        // Stop socket events to avoid duplicates after error (only for SSE-driven)
        if (socketService != null && suppressSocketContent == true) {
          try {
            socketService.offChatEvents();
          } catch (_) {}
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
  // Enqueue background title generation task
  try {
    await ref
        .read(taskQueueProvider.notifier)
        .enqueueGenerateTitle(conversationId: conversationId);
  } catch (_) {
    // Best effort background check remains
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
            ref.read(activeConversationProvider.notifier).set(updated);

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
// Removed server persistence; only local caching is used in mobile app.

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
    ref.read(activeConversationProvider.notifier).set(updatedConversation);
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
      ref
          .read(activeConversationProvider.notifier)
          .set(activeConversation!.copyWith(pinned: pinned));
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
    ref.read(activeConversationProvider.notifier).clear();
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
      ref.read(activeConversationProvider.notifier).set(activeConversation);
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
    ref.read(activeConversationProvider.notifier).set(clonedConversation);
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
      final prev = ref.read(imageGenerationEnabledProvider);
      try {
        // Force image generation enabled during regeneration
        ref.read(imageGenerationEnabledProvider.notifier).set(true);
        await regenerateMessage(
          ref,
          lastUserMessage.content,
          lastUserMessage.attachmentIds,
        );
      } finally {
        // restore previous state
        ref.read(imageGenerationEnabledProvider.notifier).set(prev);
      }
      return;
    }

    // Text regeneration without duplicating user message
    await regenerateMessage(
      ref,
      lastUserMessage.content,
      lastUserMessage.attachmentIds,
    );
  };
});

// Stop generation provider
final stopGenerationProvider = Provider<void Function()>((ref) {
  return () {
    try {
      final messages = ref.read(chatMessagesProvider);
      if (messages.isNotEmpty &&
          messages.last.role == 'assistant' &&
          messages.last.isStreaming) {
        final lastId = messages.last.id;

        // Cancel the network stream (SSE) if active
        final api = ref.read(apiServiceProvider);
        api?.cancelStreamingMessage(lastId);

        // Stop any active socket listeners for chat/channel events
        try {
          final socketService = ref.read(socketServiceProvider);
          socketService?.offChatEvents();
          socketService?.offChannelEvents();
        } catch (_) {}

        // Cancel local stream subscription to stop propagating further chunks
        ref.read(chatMessagesProvider.notifier).cancelActiveMessageStream();
      }
    } catch (_) {}

    // Best-effort: stop any background tasks associated with this chat (parity with web)
    try {
      final api = ref.read(apiServiceProvider);
      final activeConv = ref.read(activeConversationProvider);
      if (api != null && activeConv != null) {
        unawaited(() async {
          try {
            final ids = await api.getTaskIdsByChat(activeConv.id);
            for (final t in ids) {
              try {
                await api.stopTask(t);
              } catch (_) {}
            }
          } catch (_) {}
        }());

        // Also cancel local queue tasks for this conversation
        try {
          // Fire-and-forget local queue cancellation
          // ignore: unawaited_futures
          ref
              .read(taskQueueProvider.notifier)
              .cancelByConversation(activeConv.id);
        } catch (_) {}
      }
    } catch (_) {}

    // Ensure UI transitions out of streaming state
    ref.read(chatMessagesProvider.notifier).finishStreaming();
  };
});

// ========== Shared Streaming Utilities ==========

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

void _updateImagesFromCurrentContent(dynamic ref) {
  try {
    final msgs = ref.read(chatMessagesProvider);
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
      ref
          .read(chatMessagesProvider.notifier)
          .updateLastMessageWithFunction((m) => m.copyWith(files: merged));
    }
  } catch (_) {}
}

void _attachSocketStreamingHandlers({
  required dynamic ref,
  required dynamic socketService,
  required String assistantMessageId,
  required String modelId,
  required Map<String, dynamic> modelItem,
  required String sessionId,
  required bool isBackgroundFlow,
  required bool suppressSocketContentInitially,
  String? activeConversationId,
}) {
  bool suppressSocketContent = suppressSocketContentInitially;

  final api = ref.read(apiServiceProvider);

  // Activity-based watchdog for socket-driven streaming (resets on activity)
  final socketWatchdog = InactivityWatchdog(
    window: const Duration(minutes: 5),
    onTimeout: () {
      try {
        socketService.offChatEvents();
        socketService.offChannelEvents();
      } catch (_) {}
      try {
        final msgs = ref.read(chatMessagesProvider);
        if (msgs.isNotEmpty &&
            msgs.last.role == 'assistant' &&
            msgs.last.isStreaming) {
          ref.read(chatMessagesProvider.notifier).finishStreaming();
        }
      } catch (_) {}
    },
  )..start();

  void channelLineHandlerFactory(String channel) {
    void handler(dynamic line) {
      try {
        if (line is String) {
          final s = line.trim();
          // Any socket line is activity
          socketWatchdog.ping();
          if (s == '[DONE]' || s == 'DONE') {
            try {
              socketService.offEvent(channel);
            } catch (_) {}
            try {
              unawaited(
                api?.sendChatCompleted(
                  chatId: activeConversationId ?? '',
                  messageId: assistantMessageId,
                  messages: const [],
                  model: modelId,
                  modelItem: modelItem,
                  sessionId: sessionId,
                ),
              );
            } catch (_) {}
            ref.read(chatMessagesProvider.notifier).finishStreaming();
            socketWatchdog.stop();
            return;
          }
          if (s.startsWith('data:')) {
            final dataStr = s.substring(5).trim();
            if (dataStr == '[DONE]') {
              try {
                socketService.offEvent(channel);
              } catch (_) {}
              try {
                unawaited(
                  api?.sendChatCompleted(
                    chatId: activeConversationId ?? '',
                    messageId: assistantMessageId,
                    messages: const [],
                    model: modelId,
                    modelItem: modelItem,
                    sessionId: sessionId,
                  ),
                );
              } catch (_) {}
              ref.read(chatMessagesProvider.notifier).finishStreaming();
              socketWatchdog.stop();
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
                            final msgs = ref.read(chatMessagesProvider);
                            final exists =
                                (msgs.isNotEmpty) &&
                                RegExp(
                                  '<details\\s+type="tool_calls"[^>]*\\bname="${RegExp.escape(name)}"',
                                  multiLine: true,
                                ).hasMatch(msgs.last.content);
                            if (!exists) {
                              final status =
                                  '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                              ref
                                  .read(chatMessagesProvider.notifier)
                                  .appendToLastMessage(status);
                            }
                          }
                        }
                      }
                    }
                  }
                  final content = delta['content']?.toString() ?? '';
                  if (content.isNotEmpty) {
                    ref
                        .read(chatMessagesProvider.notifier)
                        .appendToLastMessage(content);
                    _updateImagesFromCurrentContent(ref);
                  }
                }
              }
            } catch (_) {
              if (s.isNotEmpty) {
                ref.read(chatMessagesProvider.notifier).appendToLastMessage(s);
                _updateImagesFromCurrentContent(ref);
              }
            }
          } else {
            if (s.isNotEmpty) {
              ref.read(chatMessagesProvider.notifier).appendToLastMessage(s);
              _updateImagesFromCurrentContent(ref);
            }
          }
        } else if (line is Map) {
          socketWatchdog.ping();
          if (line['done'] == true) {
            try {
              socketService.offEvent(channel);
            } catch (_) {}
            ref.read(chatMessagesProvider.notifier).finishStreaming();
            socketWatchdog.stop();
            return;
          }
        }
      } catch (_) {}
    }

    socketService.onEvent(channel, handler);
    // Start activity watchdog now that handler is attached
    socketWatchdog.ping();
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
                    final msgs = ref.read(chatMessagesProvider);
                    final exists =
                        (msgs.isNotEmpty) &&
                        RegExp(
                          '<details\\s+type="tool_calls"[^>]*\\bname="${RegExp.escape(name)}"',
                          multiLine: true,
                        ).hasMatch(msgs.last.content);
                    if (!exists) {
                      final status =
                          '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                      ref
                          .read(chatMessagesProvider.notifier)
                          .appendToLastMessage(status);
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
                          final msgs = ref.read(chatMessagesProvider);
                          final exists =
                              (msgs.isNotEmpty) &&
                              RegExp(
                                '<details\\s+type="tool_calls"[^>]*\\bname="${RegExp.escape(name)}"',
                                multiLine: true,
                              ).hasMatch(msgs.last.content);
                          if (!exists) {
                            final status =
                                '\n<details type="tool_calls" done="false" name="$name"><summary>Executing...</summary>\n</details>\n';
                            ref
                                .read(chatMessagesProvider.notifier)
                                .appendToLastMessage(status);
                          }
                        }
                      }
                    }
                  }
                }
                final content = delta['content']?.toString() ?? '';
                if (content.isNotEmpty) {
                  ref
                      .read(chatMessagesProvider.notifier)
                      .appendToLastMessage(content);
                  _updateImagesFromCurrentContent(ref);
                }
              }
            }
          }
          if (payload['done'] == true) {
            try {
              socketService.offChatEvents();
            } catch (_) {}
            try {
              socketWatchdog.stop();
            } catch (_) {}
            try {
              unawaited(
                api
                    ?.sendChatCompleted(
                      chatId: activeConversationId ?? '',
                      messageId: assistantMessageId,
                      messages: const [],
                      model: modelId,
                      modelItem: modelItem,
                      sessionId: sessionId,
                    )
                    ?.timeout(const Duration(seconds: 3))
                    .catchError((_) {}),
              );
            } catch (_) {}

            final msgs = ref.read(chatMessagesProvider);
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
                        ref
                            .read(chatMessagesProvider.notifier)
                            .replaceLastMessageContent(content);
                      }
                    }
                  } catch (_) {
                  } finally {
                    ref.read(chatMessagesProvider.notifier).finishStreaming();
                  }
                });
                return;
              }
            }
            ref.read(chatMessagesProvider.notifier).finishStreaming();
          }
        }
      } else if (type == 'request:chat:completion' && payload != null) {
        final channel = payload['channel'];
        if (channel is String && channel.isNotEmpty) {
          suppressSocketContent = true;
          channelLineHandlerFactory(channel);
        }
      } else if (type == 'event:status' && payload != null) {
        final status = payload['status']?.toString() ?? '';
        if (status.isNotEmpty) {
          ref
              .read(chatMessagesProvider.notifier)
              .updateLastMessageWithFunction(
                (m) => m.copyWith(metadata: {...?m.metadata, 'status': status}),
              );
        }
      } else if (type == 'event:tool' && payload != null) {
        final files = _extractFilesFromResult(payload['result']);
        if (files.isNotEmpty) {
          final msgs = ref.read(chatMessagesProvider);
          if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
            final existing = msgs.last.files ?? <Map<String, dynamic>>[];
            final merged = [...existing, ...files];
            ref
                .read(chatMessagesProvider.notifier)
                .updateLastMessageWithFunction(
                  (m) => m.copyWith(files: merged),
                );
          }
        }
      } else if (type == 'event:message:delta' && payload != null) {
        if (suppressSocketContent) return;
        final content = payload['content']?.toString() ?? '';
        if (content.isNotEmpty) {
          ref.read(chatMessagesProvider.notifier).appendToLastMessage(content);
          _updateImagesFromCurrentContent(ref);
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
          ref.read(chatMessagesProvider.notifier).appendToLastMessage(content);
          _updateImagesFromCurrentContent(ref);
        }
      }
    } catch (_) {}
  }

  socketService.onChatEvents(chatHandler);
  socketService.onChannelEvents(channelEventsHandler);
  // Start activity watchdog for chat/channel events
  socketWatchdog.ping();
}

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

Map<String, dynamic>? _resolveRef(
  String ref,
  Map<String, dynamic>? components,
) {
  // e.g., #/components/schemas/MySchema
  if (!ref.startsWith('#/')) return null;
  final parts = ref.split('/');
  if (parts.length < 4) return null;
  final type = parts[2]; // schemas
  final name = parts[3];
  final section = components?[type];
  if (section is Map<String, dynamic>) {
    final schema = section[name];
    if (schema is Map<String, dynamic>) {
      return Map<String, dynamic>.from(schema);
    }
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
      if (schema['description'] != null) {
        out['description'] = schema['description'];
      }
      if (type == 'object') {
        out['properties'] = <String, dynamic>{};
        if (schema['required'] is List) {
          out['required'] = List.from(schema['required']);
        }
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

List<Map<String, dynamic>> _convertOpenApiToToolPayload(
  Map<String, dynamic> openApi,
) {
  final tools = <Map<String, dynamic>>[];
  final paths = openApi['paths'];
  if (paths is! Map) return tools;
  paths.forEach((path, methods) {
    if (methods is! Map) return;
    methods.forEach((method, operation) {
      if (operation is Map && operation['operationId'] != null) {
        final tool = <String, dynamic>{
          'name': operation['operationId'],
          'description':
              operation['description'] ??
              operation['summary'] ??
              'No description available.',
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
                String desc = (schema['description'] ?? p['description'] ?? '')
                    .toString();
                if (schema['enum'] is List) {
                  desc =
                      '$desc. Possible values: ${(schema['enum'] as List).join(', ')}';
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
            final resolved = _resolveSchemaSimple(
              schema,
              openApi['components'] as Map<String, dynamic>?,
            );
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
