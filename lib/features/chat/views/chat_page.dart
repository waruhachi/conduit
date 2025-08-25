import 'package:flutter/material.dart';
import 'package:conduit/l10n/app_localizations.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../shared/widgets/optimized_list.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform, File;
import 'dart:async';
import '../../../core/providers/app_providers.dart';
import '../providers/chat_providers.dart';
import '../../../core/utils/debug_logger.dart';

import '../widgets/modern_chat_input.dart';
import '../widgets/user_message_bubble.dart';
import '../widgets/assistant_message_widget.dart' as assistant;
import '../widgets/file_attachment_widget.dart';
// import '../widgets/voice_input_sheet.dart'; // deprecated: replaced by inline voice input
import '../services/voice_input_service.dart';
import '../services/file_attachment_service.dart';
import '../../tools/providers/tools_providers.dart';
import '../../navigation/widgets/chats_drawer.dart';
import '../../../shared/widgets/offline_indicator.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/model.dart';
import '../../../shared/widgets/loading_states.dart';
import 'chat_page_helpers.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../onboarding/views/onboarding_sheet.dart';
import '../../../shared/widgets/sheet_handle.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../core/services/settings_service.dart';
// Removed unused PlatformUtils import
import '../../../core/services/platform_service.dart' as ps;
import 'package:flutter/gestures.dart' show DragStartBehavior;

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  Timer? _scrollDebounceTimer;

  String _formatModelDisplayName(String name) {
    var display = name.trim();
    // Prefer the segment after the last '/'
    if (display.contains('/')) {
      display = display.split('/').last.trim();
    }
    // If an org prefix like 'OpenAI: gpt-4o' exists, use the part after ':'
    if (display.contains(':')) {
      final parts = display.split(':');
      display = parts.last.trim();
    }
    return display;
  }

  bool validateFileCount(int currentCount, int newCount, int maxCount) {
    return (currentCount + newCount) <= maxCount;
  }

  bool validateFileSize(int fileSize, int maxSizeMB) {
    return fileSize <= (maxSizeMB * 1024 * 1024);
  }

  void startNewChat() {
    // Clear current conversation
    ref.read(chatMessagesProvider.notifier).clearMessages();
    ref.read(activeConversationProvider.notifier).state = null;

    // Scroll to top
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _checkAndAutoSelectModel() async {
    // Check if a model is already selected
    final selectedModel = ref.read(selectedModelProvider);
    if (selectedModel != null) {
      DebugLogger.log('Model already selected: ${selectedModel.name}');
      return;
    }

    DebugLogger.log('No model selected, attempting auto-selection');

    try {
      // First ensure models are loaded
      final modelsAsync = ref.read(modelsProvider);
      List<Model> models;

      if (modelsAsync.hasValue) {
        models = modelsAsync.value!;
      } else {
        DebugLogger.log('Models not loaded yet, fetching...');
        models = await ref.read(modelsProvider.future);
      }

      DebugLogger.log('Found ${models.length} models available');

      if (models.isEmpty) {
        DebugLogger.log('No models available for selection');
        return;
      }

      // Try to use the default model provider
      try {
        final Model? model = await ref.read(defaultModelProvider.future);
        if (model != null) {
          DebugLogger.log('Model auto-selected via provider: ${model.name}');
        }
      } catch (e) {
        DebugLogger.log(
          'Default provider failed, selecting first model directly',
        );
        // Fallback: select the first available model
        ref.read(selectedModelProvider.notifier).state = models.first;
        DebugLogger.log('Fallback model selected: ${models.first.name}');
      }
    } catch (e) {
      DebugLogger.error('Failed to auto-select model', e);
    }
  }

  Future<void> _checkAndShowOnboarding() async {
    try {
      // Check if onboarding has been seen
      final storage = ref.read(optimizedStorageServiceProvider);
      final seen = await storage.getOnboardingSeen();
      DebugLogger.log('Chat page - Onboarding seen status: $seen');

      if (!seen && mounted) {
        // Small delay to ensure navigation has settled
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;

        DebugLogger.log('Showing onboarding from chat page');
        _showOnboarding();
        await storage.setOnboardingSeen(true);
        DebugLogger.log('Onboarding marked as seen');
      }
    } catch (e) {
      DebugLogger.error('Error checking onboarding status', e);
    }
  }

  void _showOnboarding() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppBorderRadius.modal),
          ),
          boxShadow: ConduitShadows.modal,
        ),
        child: const OnboardingSheet(),
      ),
    );
  }

  Future<void> _checkAndLoadDemoConversation() async {
    if (!mounted) return;
    final isReviewerMode = ref.read(reviewerModeProvider);
    if (!isReviewerMode) return;

    // Check if there's already an active conversation
    if (!mounted) return;
    final activeConversation = ref.read(activeConversationProvider);
    if (activeConversation != null) {
      DebugLogger.log(
        'Conversation already active: ${activeConversation.title}',
      );
      return;
    }

    // Force refresh conversations provider to ensure we get the demo conversations
    if (!mounted) return;
    ref.invalidate(conversationsProvider);

    // Try to load demo conversation
    for (int i = 0; i < 10; i++) {
      if (!mounted) return;
      final conversationsAsync = ref.read(conversationsProvider);

      if (conversationsAsync.hasValue && conversationsAsync.value!.isNotEmpty) {
        // Find and load the welcome conversation
        final welcomeConv = conversationsAsync.value!.firstWhere(
          (conv) => conv.id == 'demo-conv-1',
          orElse: () => conversationsAsync.value!.first,
        );

        if (!mounted) return;
        ref.read(activeConversationProvider.notifier).state = welcomeConv;
        debugPrint('Auto-loaded demo conversation');
        return;
      }

      // If conversations are still loading, wait a bit and retry
      if (conversationsAsync.isLoading || i == 0) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        continue;
      }

      // If there was an error or no conversations, break
      break;
    }

    debugPrint('Failed to auto-load demo conversation');
  }

  @override
  void initState() {
    super.initState();

    // Listen to scroll events to show/hide scroll to bottom button
    _scrollController.addListener(_onScroll);

    // Initialize chat page components
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // First, ensure a model is selected
      await _checkAndAutoSelectModel();
      if (!mounted) return;

      // Then check for demo conversation in reviewer mode
      await _checkAndLoadDemoConversation();
      if (!mounted) return;

      // Finally, show onboarding if needed
      await _checkAndShowOnboarding();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollDebounceTimer?.cancel();
    super.dispose();
  }

  void _handleMessageSend(String text, dynamic selectedModel) async {
    if (selectedModel == null) {
      return;
    }

    final isOnline = ref.read(isOnlineProvider);
    final isReviewerMode = ref.read(reviewerModeProvider);

    if (!isOnline && !isReviewerMode) {
      return;
    }

    try {
      // Get attached files and use uploadedFileIds when sendMessage is updated to accept file IDs
      final attachedFiles = ref.read(attachedFilesProvider);

      final uploadedFileIds = attachedFiles
          .where(
            (file) =>
                file.status == FileUploadStatus.completed &&
                file.fileId != null,
          )
          .map((file) => file.fileId!)
          .toList();

      // Get selected tools
      final toolIds = ref.read(selectedToolIdsProvider);

      // Send message with file attachments and tools using existing provider logic
      await sendMessage(
        ref,
        text,
        uploadedFileIds.isNotEmpty ? uploadedFileIds : null,
        toolIds.isNotEmpty ? toolIds : null,
      );

      // Clear attachments after successful send
      ref.read(attachedFilesProvider.notifier).clearAll();

      // Scroll to bottom after sending message (only if user was near bottom)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          final currentScroll = _scrollController.position.pixels;
          // Only auto-scroll if user was already near the bottom (within 300px)
          if (maxScroll - currentScroll < 300) {
            _scrollToBottom();
          }
        }
      });
    } catch (e) {
      // Message send failed - error already handled by sendMessage
    }
  }

  // Inline voice input now handled directly inside ModernChatInput.

  void _handleFileAttachment() async {
    // Check if selected model supports file upload
    final fileUploadCapableModels = ref.read(fileUploadCapableModelsProvider);
    if (fileUploadCapableModels.isEmpty) {
      if (!mounted) return;
      return;
    }

    final fileService = ref.read(fileAttachmentServiceProvider);
    if (fileService == null) {
      return;
    }

    try {
      final files = await fileService.pickFiles();
      if (files.isEmpty) return;

      // Validate file count
      final currentFiles = ref.read(attachedFilesProvider);
      if (!validateFileCount(currentFiles.length, files.length, 10)) {
        if (!mounted) return;
        return;
      }

      // Validate file sizes
      for (final file in files) {
        final fileSize = await file.length();
        if (!validateFileSize(fileSize, 20)) {
          if (!mounted) return;
          return;
        }
      }

      // Add files to the attachment list
      ref.read(attachedFilesProvider.notifier).addFiles(files);

      // Start uploading files
      for (final file in files) {
        final uploadStream = fileService.uploadFile(file);
        uploadStream.listen(
          (state) {
            ref
                .read(attachedFilesProvider.notifier)
                .updateFileState(file.path, state);
          },
          onError: (error) {
            if (!mounted) return;
            debugPrint('Upload failed: $error');
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('File selection failed: $e');
    }
  }

  void _handleImageAttachment({bool fromCamera = false}) async {
    debugPrint(
      'DEBUG: Starting image attachment process - fromCamera: $fromCamera',
    );

    // Check if selected model supports vision
    final visionCapableModels = ref.read(visionCapableModelsProvider);
    if (visionCapableModels.isEmpty) {
      if (!mounted) return;
      return;
    }

    final fileService = ref.read(fileAttachmentServiceProvider);
    if (fileService == null) {
      debugPrint('DEBUG: File service is null - cannot proceed');
      return;
    }

    try {
      debugPrint('DEBUG: Picking image...');
      final image = fromCamera
          ? await fileService.takePhoto()
          : await fileService.pickImage();
      if (image == null) {
        debugPrint('DEBUG: No image selected');
        return;
      }

      debugPrint('DEBUG: Image selected: ${image.path}');
      final imageSize = await image.length();
      debugPrint('DEBUG: Image size: $imageSize bytes');

      // Validate file size (default 20MB limit like OpenWebUI)
      if (!validateFileSize(imageSize, 20)) {
        if (!mounted) return;
        return;
      }

      // Validate file count (default 10 files limit like OpenWebUI)
      final currentFiles = ref.read(attachedFilesProvider);
      if (!validateFileCount(currentFiles.length, 1, 10)) {
        if (!mounted) return;
        return;
      }

      // Add image to the attachment list
      ref.read(attachedFilesProvider.notifier).addFiles([image]);
      debugPrint('DEBUG: Image added to attachment list');

      // Start uploading image
      debugPrint('DEBUG: Starting image upload...');
      final uploadStream = fileService.uploadFile(image);
      uploadStream.listen(
        (state) {
          debugPrint(
            'DEBUG: Upload state update - Status: ${state.status}, Progress: ${state.progress}, FileId: ${state.fileId}',
          );
          ref
              .read(attachedFilesProvider.notifier)
              .updateFileState(image.path, state);
        },
        onError: (error) {
          debugPrint('DEBUG: Image upload error: $error');
          if (!mounted) return;
        },
      );
    } catch (e) {
      debugPrint('DEBUG: Image attachment error: $e');
      if (!mounted) return;
    }
  }

  void _handleNewChat() {
    // Start a new chat using the existing function
    startNewChat();

    // Hide scroll-to-bottom button for a fresh chat
    if (mounted) {
      setState(() {
        _showScrollToBottom = false;
      });
    }
  }

  // Replaced bottom-sheet chat list with left drawer (see ChatsDrawer)

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    // Debounce scroll handling to reduce rebuilds
    if (_scrollDebounceTimer?.isActive == true) return;

    _scrollDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || !_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;

      // Only show button if user has scrolled up significantly
      final showButton = maxScroll > 100 && currentScroll < maxScroll - 200;

      if (showButton != _showScrollToBottom && mounted) {
        setState(() {
          _showScrollToBottom = showButton;
        });
      }
    });
  }

  void _scrollToBottom({bool smooth = true}) {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    if (smooth) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(maxScroll);
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedMessageIds.clear();
      }
    });
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  // TODO: Implement select all functionality when needed
  // void _selectAllMessages() {
  //   final messages = ref.read(chatMessagesProvider);
  //   setState(() {
  //     _selectedMessageIds.clear();
  //     _selectedMessageIds.addAll(messages.map((m) => m.id));
  //   });
  // }

  void _clearSelection() {
    setState(() {
      _selectedMessageIds.clear();
      _isSelectionMode = false;
    });
  }

  List<ChatMessage> _getSelectedMessages() {
    final messages = ref.read(chatMessagesProvider);
    return messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
  }

  Widget _buildMessagesList(ThemeData theme) {
    // Use select to watch only the messages list to reduce rebuilds
    final messages = ref.watch(
      chatMessagesProvider.select((messages) => messages),
    );
    final isLoadingConversation = ref.watch(isLoadingConversationProvider);

    // Use AnimatedSwitcher for smooth transition between loading and loaded states
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: isLoadingConversation && messages.isEmpty
          ? _buildLoadingMessagesList()
          : _buildActualMessagesList(messages),
    );
  }

  Widget _buildLoadingMessagesList() {
    return ListView.builder(
      key: const ValueKey('loading_messages'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.lg,
      ),
      physics:
          const NeverScrollableScrollPhysics(), // Prevent scrolling during load
      itemCount: 6,
      itemBuilder: (context, index) {
        final isUser = index.isOdd;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: Spacing.md),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isUser
                  ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.15)
                  : context.conduitTheme.cardBackground,
              borderRadius: BorderRadius.circular(
                AppBorderRadius.messageBubble,
              ),
              border: Border.all(
                color: context.conduitTheme.cardBorder,
                width: BorderWidth.regular,
              ),
              boxShadow: ConduitShadows.messageBubble,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: index % 3 == 0 ? 140 : 220,
                  decoration: BoxDecoration(
                    color: context.conduitTheme.shimmerBase,
                    borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                  ),
                ).animate().shimmer(duration: AnimationDuration.slow),
                const SizedBox(height: Spacing.xs),
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: context.conduitTheme.shimmerBase,
                    borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                  ),
                ).animate().shimmer(duration: AnimationDuration.slow),
                if (index % 3 != 0) ...[
                  const SizedBox(height: Spacing.xs),
                  Container(
                    height: 14,
                    width: index % 2 == 0 ? 180 : 120,
                    decoration: BoxDecoration(
                      color: context.conduitTheme.shimmerBase,
                      borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                    ),
                  ).animate().shimmer(duration: AnimationDuration.slow),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActualMessagesList(List<ChatMessage> messages) {
    if (messages.isEmpty) {
      return _buildEmptyState(Theme.of(context));
    }

    return OptimizedList<ChatMessage>(
      key: const ValueKey('actual_messages'),
      scrollController: _scrollController,
      items: messages,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.lg,
      ),
      itemBuilder: (context, message, index) {
        final isUser = message.role == 'user';
        final isStreaming = message.isStreaming;

        final isSelected = _selectedMessageIds.contains(message.id);

        // Wrap message in selection container if in selection mode
        Widget messageWidget;

        // Use documentation style for assistant messages, bubble for user messages
        if (isUser) {
          messageWidget = UserMessageBubble(
            key: ValueKey('user-${message.id}'),
            message: message,
            isUser: isUser,
            isStreaming: isStreaming,
            modelName: message.model,
            onCopy: () => _copyMessage(message.content),
            onEdit: () => _editMessage(message),
            onRegenerate: () => _regenerateMessage(message),
            onLike: () => _likeMessage(message),
            onDislike: () => _dislikeMessage(message),
          );
        } else {
          messageWidget = assistant.AssistantMessageWidget(
            key: ValueKey('assistant-${message.id}'),
            message: message,
            isStreaming: isStreaming,
            modelName: message.model,
            onCopy: () => _copyMessage(message.content),
            onRegenerate: () => _regenerateMessage(message),
            onLike: () => _likeMessage(message),
            onDislike: () => _dislikeMessage(message),
          );
        }

        // Add selection functionality if in selection mode
        if (_isSelectionMode) {
          return _SelectableMessageWrapper(
            isSelected: isSelected,
            onTap: () => _toggleMessageSelection(message.id),
            onLongPress: () {
              if (!_isSelectionMode) {
                _toggleSelectionMode();
                _toggleMessageSelection(message.id);
              }
            },
            child: messageWidget,
          );
        } else {
          return GestureDetector(
            onLongPress: () {
              _toggleSelectionMode();
              _toggleMessageSelection(message.id);
            },
            child: messageWidget,
          );
        }
      },
    );
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
  }

  void _regenerateMessage(dynamic message) async {
    final selectedModel = ref.read(selectedModelProvider);
    if (selectedModel == null) {
      return;
    }

    // Find the user message that prompted this assistant response
    final messages = ref.read(chatMessagesProvider);
    final messageIndex = messages.indexOf(message);

    if (messageIndex <= 0 || messages[messageIndex - 1].role != 'user') {
      return;
    }

    try {
      // If assistant message has generated images and it's the last message,
      // use image-only regenerate flow instead of text SSE regeneration
      if (message.role == 'assistant' &&
          (message.files?.any((f) => f['type'] == 'image') == true) &&
          messageIndex == messages.length - 1) {
        final regenerateImages = ref.read(regenerateLastMessageProvider);
        await regenerateImages();
        return;
      }

      // Remove the assistant message we want to regenerate
      ref.read(chatMessagesProvider.notifier).removeLastMessage();

      // Regenerate response for the previous user message (without duplicating it)
      final userMessage = messages[messageIndex - 1];
      await regenerateMessage(
        ref,
        userMessage.content,
        userMessage.attachmentIds,
      );
    } catch (e) {
      debugPrint('Regenerate failed: $e');
    }
  }

  void _editMessage(dynamic message) async {
    if (message.role != 'user') {
      return;
    }

    final controller = TextEditingController(text: message.content);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.conduitTheme.surfaceBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.dialog),
        ),
        title: Text(
          'Edit Message',
          style: TextStyle(color: context.conduitTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: TextStyle(color: context.conduitTheme.textPrimary),
          maxLines: null,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.messageHintText,
            hintStyle: TextStyle(color: context.conduitTheme.inputPlaceholder),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: context.conduitTheme.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: context.conduitTheme.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: context.conduitTheme.buttonPrimary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.conduitTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: TextButton.styleFrom(
              foregroundColor: context.conduitTheme.buttonPrimary,
            ),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != message.content) {
      try {
        // Find the message index and remove all messages after it
        final messages = ref.read(chatMessagesProvider);
        final messageIndex = messages.indexOf(message);

        if (messageIndex >= 0) {
          // Remove messages from this point onwards
          final messagesToKeep = messages.take(messageIndex).toList();
          ref.read(chatMessagesProvider.notifier).setMessages(messagesToKeep);

          // Send the edited message
          final selectedModel = ref.read(selectedModelProvider);
          if (selectedModel != null) {
            await sendMessage(ref, result, null);

            if (mounted) {}
          }
        }
      } catch (e) {
        if (mounted) {}
      }
    }

    controller.dispose();
  }

  void _likeMessage(dynamic message) {
    // TODO: Implement message liking
  }

  void _dislikeMessage(dynamic message) {
    // TODO: Implement message disliking
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Minimal, clean empty state
            Container(
                  width: Spacing.xxl + Spacing.xxxl,
                  height: Spacing.xxl + Spacing.xxxl,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        context.conduitTheme.buttonPrimary,
                        context.conduitTheme.buttonPrimary.withValues(
                          alpha: 0.8,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppBorderRadius.round),
                    boxShadow: ConduitShadows.glow,
                  ),
                  child: Icon(
                    Platform.isIOS ? CupertinoIcons.chat_bubble_2 : Icons.chat,
                    size: Spacing.xxxl - Spacing.xs,
                    color: context.conduitTheme.textInverse,
                  ),
                )
                .animate()
                .scale(duration: const Duration(milliseconds: 300))
                .then()
                .shimmer(duration: const Duration(milliseconds: 1200)),

            const SizedBox(height: Spacing.xl),

            Text(
              AppLocalizations.of(context)!.onboardStartTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.conduitTheme.textPrimary,
              ),
            ).animate().fadeIn(delay: const Duration(milliseconds: 150)),

            const SizedBox(height: Spacing.sm),

            Text(
              AppLocalizations.of(context)!.typeBelowToBegin,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: context.conduitTheme.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ).animate().fadeIn(delay: const Duration(milliseconds: 300)),
          ],
        ),
      ),
    );
  }

  // Removed detailed help items from chat page; guidance now lives in Onboarding

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use select to watch only connectivity status to reduce rebuilds
    final isOnline = ref.watch(isOnlineProvider.select((status) => status));

    // Use select to watch only the selected model to reduce rebuilds
    final selectedModel = ref.watch(
      selectedModelProvider.select((model) => model),
    );

    // Watch reviewer mode and auto-select model if needed
    final isReviewerMode = ref.watch(reviewerModeProvider);

    // Auto-select model when in reviewer mode with no selection
    if (isReviewerMode && selectedModel == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndAutoSelectModel();
      });
    }

    return ErrorBoundary(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) async {
          if (didPop) return;

          // Auto-handle leaving without confirmation
          final messages = ref.read(chatMessagesProvider);
          final isStreaming = messages.any((msg) => msg.isStreaming);
          if (isStreaming) {
            ref.read(chatMessagesProvider.notifier).finishStreaming();
          }

          await _saveConversationBeforeLeaving(ref);

          if (context.mounted) {
            final canPopNavigator = Navigator.of(context).canPop();
            if (canPopNavigator) {
              Navigator.of(context).pop();
            } else {
              SystemNavigator.pop();
            }
          }
        },
        child: Scaffold(
          backgroundColor: context.conduitTheme.surfaceBackground,
          // Left navigation drawer with draggable edge open (native, finger-following)
          drawerEnableOpenDragGesture: true,
          drawerDragStartBehavior: DragStartBehavior.down,
          drawerEdgeDragWidth: MediaQuery.of(context).size.width * 0.5,
          drawerScrimColor: Colors.black.withOpacity(0.32),
          drawer: Drawer(
            width: (MediaQuery.of(context).size.width * 0.88).clamp(
              280.0,
              420.0,
            ),
            backgroundColor: context.conduitTheme.surfaceBackground,
            child: const SafeArea(child: ChatsDrawer()),
          ),
          appBar: AppBar(
            backgroundColor: context.conduitTheme.surfaceBackground,
            elevation: Elevation.none,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            toolbarHeight: kToolbarHeight,
            centerTitle: true,
            titleSpacing: 0.0,
            leading: _isSelectionMode
                ? IconButton(
                    icon: Icon(
                      Platform.isIOS ? CupertinoIcons.xmark : Icons.close,
                      color: context.conduitTheme.textPrimary,
                      size: IconSize.appBar,
                    ),
                    onPressed: _clearSelection,
                  )
                : Builder(
                    builder: (ctx) => GestureDetector(
                      onTap: () {
                        // Open left drawer instead of bottom sheet
                        Scaffold.of(ctx).openDrawer();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(
                          Platform.isIOS
                              ? CupertinoIcons.line_horizontal_3
                              : Icons.menu,
                          color: context.conduitTheme.textPrimary,
                          size: IconSize.appBar,
                        ),
                      ),
                    ),
                  ),
            title: _isSelectionMode
                ? Text(
                    '${_selectedMessageIds.length} selected',
                    style: AppTypography.headlineSmallStyle.copyWith(
                      color: context.conduitTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : selectedModel != null
                ? GestureDetector(
                    onTap: () {
                      final modelsAsync = ref.read(modelsProvider);
                      modelsAsync.whenData(
                        (models) => _showModelDropdown(context, ref, models),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _formatModelDisplayName(selectedModel.name),
                                style: AppTypography.headlineSmallStyle
                                    .copyWith(
                                      color: context.conduitTheme.textPrimary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: Spacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.xs,
                                vertical: Spacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: context.conduitTheme.surfaceBackground
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(
                                  AppBorderRadius.badge,
                                ),
                                border: Border.all(
                                  color: context.conduitTheme.dividerColor,
                                  width: BorderWidth.thin,
                                ),
                              ),
                              child: Icon(
                                Platform.isIOS
                                    ? CupertinoIcons.chevron_down
                                    : Icons.keyboard_arrow_down,
                                color: context.conduitTheme.iconSecondary,
                                size: IconSize.small,
                              ),
                            ),
                          ],
                        ),
                        if (ref.watch(reviewerModeProvider))
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.sm,
                                vertical: 1.0,
                              ),
                              decoration: BoxDecoration(
                                color: context.conduitTheme.success.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppBorderRadius.badge,
                                ),
                                border: Border.all(
                                  color: context.conduitTheme.success
                                      .withValues(alpha: 0.3),
                                  width: BorderWidth.thin,
                                ),
                              ),
                              child: Text(
                                'REVIEWER MODE',
                                style: AppTypography.captionStyle.copyWith(
                                  color: context.conduitTheme.success,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: () {
                      final modelsAsync = ref.read(modelsProvider);
                      modelsAsync.whenData(
                        (models) => _showModelDropdown(context, ref, models),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'Choose Model',
                                style: AppTypography.headlineSmallStyle
                                    .copyWith(
                                      color: context.conduitTheme.textPrimary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: Spacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.xs,
                                vertical: Spacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: context.conduitTheme.surfaceBackground
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(
                                  AppBorderRadius.badge,
                                ),
                                border: Border.all(
                                  color: context.conduitTheme.dividerColor,
                                  width: BorderWidth.thin,
                                ),
                              ),
                              child: Icon(
                                Platform.isIOS
                                    ? CupertinoIcons.chevron_down
                                    : Icons.keyboard_arrow_down,
                                color: context.conduitTheme.iconSecondary,
                                size: IconSize.small,
                              ),
                            ),
                          ],
                        ),
                        if (ref.watch(reviewerModeProvider))
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.sm,
                                vertical: 1.0,
                              ),
                              decoration: BoxDecoration(
                                color: context.conduitTheme.success.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppBorderRadius.badge,
                                ),
                                border: Border.all(
                                  color: context.conduitTheme.success
                                      .withValues(alpha: 0.3),
                                  width: BorderWidth.thin,
                                ),
                              ),
                              child: Text(
                                'REVIEWER MODE',
                                style: AppTypography.captionStyle.copyWith(
                                  color: context.conduitTheme.success,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
            actions: [
              if (!_isSelectionMode) ...[
                IconButton(
                  icon: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.bubble_left
                        : Icons.add_comment,
                    color: context.conduitTheme.textPrimary,
                    size: IconSize.appBar,
                  ),
                  onPressed: _handleNewChat,
                  tooltip: AppLocalizations.of(context)!.newChat,
                ),
              ] else ...[
                IconButton(
                  icon: Icon(
                    Platform.isIOS ? CupertinoIcons.delete : Icons.delete,
                    color: context.conduitTheme.error,
                    size: IconSize.appBar,
                  ),
                  onPressed: _deleteSelectedMessages,
                ),
              ],
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Messages Area with pull-to-refresh
                  Expanded(
                    child: ConduitRefreshIndicator(
                      onRefresh: () async {
                        // Reload active conversation messages from server
                        final api = ref.read(apiServiceProvider);
                        final active = ref.read(activeConversationProvider);
                        if (api != null && active != null) {
                          try {
                            final full = await api.getConversation(active.id);
                            ref
                                    .read(activeConversationProvider.notifier)
                                    .state =
                                full;
                          } catch (e) {
                            debugPrint(
                              'DEBUG: Failed to refresh conversation: $e',
                            );
                            // Could show a snackbar here if needed
                          }
                        }
                        // Add small delay for better UX feedback
                        await Future.delayed(const Duration(milliseconds: 300));
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        child: _buildMessagesList(theme),
                      ),
                    ),
                  ),

                  // File attachments
                  const FileAttachmentWidget(),

                  // Offline indicator
                  const ChatOfflineOverlay(),

                  // Modern Input (root matches input background including safe area)
                  ModernChatInput(
                    enabled:
                        selectedModel != null &&
                        (isOnline || ref.watch(reviewerModeProvider)),
                    onSendMessage: (text) =>
                        _handleMessageSend(text, selectedModel),
                    onVoiceInput: null,
                    onFileAttachment: _handleFileAttachment,
                    onImageAttachment: _handleImageAttachment,
                    onCameraCapture: () =>
                        _handleImageAttachment(fromCamera: true),
                  ),
                ],
              ),

              // Floating Scroll to Bottom Button (only if there are messages)
              if (_showScrollToBottom &&
                  ref.watch(chatMessagesProvider).isNotEmpty)
                Positioned(
                      bottom:
                          Spacing.xxl +
                          Spacing
                              .xxxl, // Position higher to avoid overlapping chat input
                      right: Spacing.lg,
                      child: FloatingActionButton(
                        onPressed: _scrollToBottom,
                        backgroundColor: context.conduitTheme.buttonPrimary,
                        foregroundColor: context.conduitTheme.buttonPrimaryText,
                        elevation: Elevation.medium,
                        child: Icon(
                          Platform.isIOS
                              ? CupertinoIcons.arrow_down
                              : Icons.keyboard_arrow_down,
                          size: IconSize.large,
                        ),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: AnimationDuration.microInteraction)
                    .slideY(
                      begin: AnimationValues.slideInFromBottom.dy,
                      end: AnimationValues.slideCenter.dy,
                      duration: AnimationDuration.microInteraction,
                      curve: AnimationCurves.microInteraction,
                    ),
              // Edge overlay removed; rely on native interactive drawer drag
            ],
          ),
        ), // Scaffold
      ), // PopScope
    ); // ErrorBoundary
  }

  Future<void> _saveConversationBeforeLeaving(WidgetRef ref) async {
    try {
      final api = ref.read(apiServiceProvider);
      final messages = ref.read(chatMessagesProvider);
      final activeConversation = ref.read(activeConversationProvider);
      final selectedModel = ref.read(selectedModelProvider);

      if (api == null || messages.isEmpty || activeConversation == null) {
        return;
      }

      // Remove trailing assistant message only if it has no text and no files
      final lastMessage = messages.isNotEmpty ? messages.last : null;
      if (lastMessage != null &&
          lastMessage.role == 'assistant' &&
          lastMessage.content.trim().isEmpty &&
          (lastMessage.files == null || lastMessage.files!.isEmpty) &&
          (lastMessage.attachmentIds == null ||
              lastMessage.attachmentIds!.isEmpty)) {
        messages.removeLast();
        if (messages.isEmpty) return;
      }

      // Update the existing conversation with all messages
      await api.updateConversationWithMessages(
        activeConversation.id,
        messages,
        model: selectedModel?.id,
      );

      debugPrint('DEBUG: Conversation saved before leaving');
    } catch (e) {
      debugPrint('DEBUG: Failed to save conversation before leaving: $e');
      // Don't block navigation even if save fails
    }
  }

  void _showModelDropdown(
    BuildContext context,
    WidgetRef ref,
    List<Model> models,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ModelSelectorSheet(models: models, ref: ref),
    );
  }

  // TODO: Implement chat options when needed
  // void _showChatOptions() {
  //   ScaffoldMessenger.of(
  //     context,
  //   ).showSnackBar(const SnackBar(content: Text('Chat options coming soon!')));
  // }

  void _deleteSelectedMessages() {
    final selectedMessages = _getSelectedMessages();
    if (selectedMessages.isEmpty) return;

    ThemedDialogs.confirm(
      context,
      title: 'Delete Messages',
      message: 'Delete ${selectedMessages.length} messages?',
      confirmText: 'Delete',
      isDestructive: true,
    ).then((confirmed) async {
      if (confirmed == true) {
        // TODO: Implement message removal
        // for (final selectedMessage in selectedMessages) {
        //   ref.read(chatMessagesProvider.notifier).removeMessage(selectedMessage.id);
        // }
        _clearSelection();
        if (mounted) {}
      }
    });
  }
}

class _ModelSelectorSheet extends ConsumerStatefulWidget {
  final List<Model> models;
  final WidgetRef ref;

  const _ModelSelectorSheet({required this.models, required this.ref});

  @override
  ConsumerState<_ModelSelectorSheet> createState() =>
      _ModelSelectorSheetState();
}

class _ModelSelectorSheetState extends ConsumerState<_ModelSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Model> _filteredModels = [];
  Timer? _searchDebounce;
  // No capability filters
  // Grid view removed

  Widget _capabilityChip({required IconData icon, required String label}) {
    return Container(
      margin: const EdgeInsets.only(right: Spacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: context.conduitTheme.buttonPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppBorderRadius.chip),
        border: Border.all(
          color: context.conduitTheme.buttonPrimary.withValues(alpha: 0.3),
          width: BorderWidth.thin,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.conduitTheme.buttonPrimary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: context.conduitTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // Removed filter toggle UI and logic

  @override
  void initState() {
    super.initState();
    _filteredModels = widget.models;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _filterModels(String query) {
    // Debounce for fast search
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
      setState(() {
        _searchQuery = query.toLowerCase();
        Iterable<Model> list = widget.models;
        if (_searchQuery.isNotEmpty) {
          list = list.where((model) {
            return model.name.toLowerCase().contains(_searchQuery) ||
                model.id.toLowerCase().contains(_searchQuery);
          });
        }
        // No capability filters
        _filteredModels = list.toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.conduitTheme.surfaceBackground,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppBorderRadius.bottomSheet),
            ),
            border: Border.all(
              color: context.conduitTheme.dividerColor,
              width: BorderWidth.regular,
            ),
            boxShadow: ConduitShadows.modal,
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
              child: Column(
                children: [
                  // Handle bar (standardized)
                  const SheetHandle(),

                  // Search field
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: context.conduitTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context)!.searchModels,
                        hintStyle: TextStyle(
                          color: context.conduitTheme.inputPlaceholder,
                        ),
                        prefixIcon: Icon(
                          Platform.isIOS ? CupertinoIcons.search : Icons.search,
                          color: context.conduitTheme.iconSecondary,
                        ),
                        filled: true,
                        fillColor: context.conduitTheme.inputBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppBorderRadius.md,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppBorderRadius.md,
                          ),
                          borderSide: BorderSide(
                            color: context.conduitTheme.inputBorder,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppBorderRadius.md,
                          ),
                          borderSide: BorderSide(
                            color: context.conduitTheme.buttonPrimary,
                            width: 1,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                          vertical: Spacing.md,
                        ),
                      ),
                      onChanged: _filterModels,
                    ),
                  ),

                  // Removed capability filters
                  const SizedBox(height: Spacing.sm),

                  // Models list
                  Expanded(
                    child: Scrollbar(
                      controller: scrollController,
                      child: _filteredModels.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Platform.isIOS
                                        ? CupertinoIcons.search_circle
                                        : Icons.search_off,
                                    size: 48,
                                    color: context.conduitTheme.iconSecondary,
                                  ),
                                  const SizedBox(height: Spacing.md),
                                  Text(
                                    'No results',
                                    style: TextStyle(
                                      color: context.conduitTheme.textSecondary,
                                      fontSize: AppTypography.bodyLarge,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: EdgeInsets.zero,
                              itemCount: _filteredModels.length,
                              itemBuilder: (context, index) {
                                final model = _filteredModels[index];
                                final isSelected =
                                    widget.ref
                                        .watch(selectedModelProvider)
                                        ?.id ==
                                    model.id;

                                return _buildModelListTile(
                                  model: model,
                                  isSelected: isSelected,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    widget.ref
                                            .read(
                                              selectedModelProvider.notifier,
                                            )
                                            .state =
                                        model;
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Layout toggle removed

  // Removed grid card renderer (grid view removed)

  bool _modelSupportsReasoning(Model model) {
    // Only rely on supported_parameters containing 'reasoning'
    final params = model.supportedParameters ?? const [];
    return params.any((p) => p.toLowerCase().contains('reasoning'));
  }

  // Removed: _capabilityBadge no longer used

  // Removed: _capabilityPlusBadge no longer used

  Widget _buildModelListTile({
    required Model model,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppBorderRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.md),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    context.conduitTheme.buttonPrimary.withValues(alpha: 0.2),
                    context.conduitTheme.buttonPrimary.withValues(alpha: 0.1),
                  ],
                )
              : null,
          color: isSelected
              ? null
              : context.conduitTheme.surfaceBackground.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: Border.all(
            color: isSelected
                ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.5)
                : context.conduitTheme.dividerColor,
            width: BorderWidth.regular,
          ),
          boxShadow: isSelected ? ConduitShadows.card : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.conduitTheme.buttonPrimary.withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(AppBorderRadius.md),
                ),
                child: Icon(
                  Platform.isIOS ? CupertinoIcons.cube : Icons.psychology,
                  color: context.conduitTheme.buttonPrimary,
                  size: 16,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: TextStyle(
                        color: context.conduitTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.bodyMedium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Spacing.xs),
                    Row(
                      children: [
                        if (model.isMultimodal)
                          _capabilityChip(
                            icon: Platform.isIOS
                                ? CupertinoIcons.photo
                                : Icons.image,
                            label: 'Multimodal',
                          ),
                        if (_modelSupportsReasoning(model))
                          _capabilityChip(
                            icon: Platform.isIOS
                                ? CupertinoIcons.lightbulb
                                : Icons.psychology_alt,
                            label: 'Reasoning',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Spacing.md),
              AnimatedOpacity(
                opacity: isSelected ? 1 : 0.6,
                duration: AnimationDuration.fast,
                child: Container(
                  padding: const EdgeInsets.all(Spacing.xxs),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.conduitTheme.buttonPrimary
                        : context.conduitTheme.surfaceBackground,
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                    border: Border.all(
                      color: isSelected
                          ? context.conduitTheme.buttonPrimary.withValues(
                              alpha: 0.6,
                            )
                          : context.conduitTheme.dividerColor,
                    ),
                  ),
                  child: Icon(
                    isSelected
                        ? (Platform.isIOS
                              ? CupertinoIcons.check_mark
                              : Icons.check)
                        : (Platform.isIOS ? CupertinoIcons.add : Icons.add),
                    color: isSelected
                        ? context.conduitTheme.textInverse
                        : context.conduitTheme.iconSecondary,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: AnimationDuration.microInteraction);
  }

  // Intentionally left blank placeholder for nested helper; moved to top-level below
}

// Removed custom edge gesture in favor of native Drawer drag behavior.

class _VoiceInputSheet extends ConsumerStatefulWidget {
  final Function(String) onTextReceived;

  const _VoiceInputSheet({required this.onTextReceived});

  @override
  ConsumerState<_VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends ConsumerState<_VoiceInputSheet> {
  bool _isListening = false;
  String _recognizedText = '';
  late VoiceInputService _voiceService;
  StreamSubscription<int>? _intensitySub;
  int _intensity = 0;
  StreamSubscription<String>? _textSub;
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;
  bool _isTranscribing = false;
  String _languageTag = 'en';
  bool _holdToTalk = false;
  bool _autoSendFinal = false;

  @override
  void initState() {
    super.initState();
    _voiceService = ref.read(voiceInputServiceProvider);
    try {
      final preset = _voiceService.selectedLocaleId;
      if (preset != null && preset.isNotEmpty) {
        _languageTag = preset.split(RegExp('[-_]')).first.toLowerCase();
      } else {
        _languageTag = WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag()
            .split(RegExp('[-_]'))
            .first
            .toLowerCase();
      }
    } catch (_) {
      _languageTag = 'en';
    }
    // Load voice settings from app settings
    final settings = ref.read(appSettingsProvider);
    _holdToTalk = settings.voiceHoldToTalk;
    _autoSendFinal = settings.voiceAutoSendFinal;
    if (settings.voiceLocaleId != null && settings.voiceLocaleId!.isNotEmpty) {
      _voiceService.setLocale(settings.voiceLocaleId);
      _languageTag = settings.voiceLocaleId!
          .split(RegExp('[-_]'))
          .first
          .toLowerCase();
    }
  }

  void _startListening() async {
    setState(() {
      _isListening = true;
      _recognizedText = '';
      _elapsedSeconds = 0;
    });
    // Haptic: indicate start listening
    final hapticEnabled = ref.read(hapticEnabledProvider);
    ps.PlatformService.hapticFeedbackWithSettings(
      type: ps.HapticType.medium,
      hapticEnabled: hapticEnabled,
    );

    try {
      // Ensure service is initialized (local STT will request permissions itself)
      final ok = await _voiceService.initialize();
      if (!ok) {
        throw Exception('Voice service unavailable');
      }
      // Only check mic permission when falling back to recording
      if (!_voiceService.hasLocalStt) {
        final mic = await _voiceService.checkPermissions();
        if (!mic) throw Exception('Microphone permission not granted');
      }

      // Start elapsed timer for UX
      _elapsedTimer?.cancel();
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_isListening) {
          t.cancel();
          return;
        }
        setState(() => _elapsedSeconds += 1);
      });

      final stream = _voiceService.startListening();
      _intensitySub = _voiceService.intensityStream.listen((value) {
        if (!mounted) return;
        setState(() => _intensity = value);
      });
      _textSub = stream.listen(
        (text) {
          // If we receive a special token with recorded audio path, transcribe it via API (fallback)
          if (text.startsWith('[[AUDIO_FILE_PATH]]:')) {
            final filePath = text.split(':').skip(1).join(':');
            debugPrint(
              'DEBUG: VoiceInputSheet received audio file path: $filePath',
            );
            _transcribeRecordedFile(filePath);
          } else {
            setState(() {
              _recognizedText = text;
            });
          }
        },
        onDone: () {
          debugPrint('DEBUG: VoiceInputSheet stream done');
          setState(() {
            _isListening = false;
          });
          _elapsedTimer?.cancel();
          // Auto-send on final local result if enabled
          if (_autoSendFinal && _recognizedText.trim().isNotEmpty) {
            _sendText();
          }
        },
        onError: (error) {
          debugPrint('DEBUG: VoiceInputSheet stream error: $error');
          setState(() {
            _isListening = false;
          });
          _elapsedTimer?.cancel();
          if (mounted) {
            final hapticEnabled = ref.read(hapticEnabledProvider);
            ps.PlatformService.hapticFeedbackWithSettings(
              type: ps.HapticType.warning,
              hapticEnabled: hapticEnabled,
            );
          }
        },
      );
    } catch (e) {
      setState(() {
        _isListening = false;
      });
      if (mounted) {}
    }
  }

  Future<void> _transcribeRecordedFile(String filePath) async {
    try {
      setState(() => _isTranscribing = true);
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('API service unavailable');
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      // Try to use device locale; fall back to en-US
      String? language;
      try {
        language = WidgetsBinding.instance.platformDispatcher.locale
            .toLanguageTag();
      } catch (_) {
        language = 'en-US';
      }
      final text = await api.transcribeAudio(
        bytes.toList(),
        language: language,
      );
      debugPrint(
        'DEBUG: Transcription received: ${text.isEmpty ? '[empty]' : text}',
      );
      if (!mounted) return;
      setState(() {
        _recognizedText = text;
      });
      // Stop listening state if we have a result
      setState(() => _isListening = false);
      if (_autoSendFinal && _recognizedText.trim().isNotEmpty) {
        _sendText();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isListening = false);
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  Future<void> _stopListening() async {
    _intensitySub?.cancel();
    _intensitySub = null;
    // Keep text subscription active to receive final audio path emission
    await _voiceService.stopListening();
    _elapsedTimer?.cancel();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
    // Haptic: subtle stop confirmation
    final hapticEnabled = ref.read(hapticEnabledProvider);
    ps.PlatformService.hapticFeedbackWithSettings(
      type: ps.HapticType.selection,
      hapticEnabled: hapticEnabled,
    );
  }

  void _sendText() {
    if (_recognizedText.isNotEmpty) {
      // Haptic: success send
      final hapticEnabled = ref.read(hapticEnabledProvider);
      ps.PlatformService.hapticFeedbackWithSettings(
        type: ps.HapticType.success,
        hapticEnabled: hapticEnabled,
      );
      widget.onTextReceived(_recognizedText);
      Navigator.pop(context);
    }
  }

  String _formatSeconds(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _pickLanguage() async {
    // Only for local STT
    if (!_voiceService.hasLocalStt) return;
    final locales = _voiceService.locales;
    if (locales.isEmpty) return;
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: context.conduitTheme.surfaceBackground,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppBorderRadius.bottomSheet),
            ),
            border: Border.all(
              color: context.conduitTheme.dividerColor,
              width: BorderWidth.regular,
            ),
            boxShadow: ConduitShadows.modal,
          ),
          padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetHandle(),
                const SizedBox(height: Spacing.md),
                Text(
                  'Select Language',
                  style: TextStyle(
                    fontSize: AppTypography.headlineSmall,
                    color: context.conduitTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: locales.length,
                    separatorBuilder: (_, sep) => Divider(
                      height: 1,
                      color: context.conduitTheme.dividerColor,
                    ),
                    itemBuilder: (ctx, i) {
                      final l = locales[i];
                      final isSelected =
                          l.localeId == _voiceService.selectedLocaleId;
                      return ListTile(
                        title: Text(
                          l.name,
                          style: TextStyle(
                            color: context.conduitTheme.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          l.localeId,
                          style: TextStyle(
                            color: context.conduitTheme.textSecondary,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: context.conduitTheme.buttonPrimary,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, l.localeId),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _voiceService.setLocale(selected);
        _languageTag = selected.split(RegExp('[-_]')).first.toLowerCase();
      });
      // Persist preferred locale
      await ref.read(appSettingsProvider.notifier).setVoiceLocaleId(selected);
      if (_isListening) {
        // Restart listening to apply new language
        await _voiceService.stopListening();
        _startListening();
      }
    }
  }

  Widget _buildThemedSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = context.conduitTheme;
    return ps.PlatformService.getPlatformSwitch(
      value: value,
      onChanged: onChanged,
      activeColor: theme.buttonPrimary,
    );
  }

  @override
  void dispose() {
    _intensitySub?.cancel();
    _textSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isCompact = media.size.height < 680;
    return Container(
      height: media.size.height * (isCompact ? 0.45 : 0.6),
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.bottomSheet),
        ),
        border: Border.all(color: context.conduitTheme.dividerColor, width: 1),
        boxShadow: ConduitShadows.modal,
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.bottomSheetPadding),
          child: Column(
            children: [
              // Handle bar
              const SheetHandle(),

              // Header: Title + timer + language chip
              Padding(
                padding: const EdgeInsets.only(
                  top: Spacing.md,
                  bottom: Spacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isTranscribing
                          ? 'Transcribing…'
                          : _isListening
                          ? (_voiceService.hasLocalStt
                                ? 'Listening…'
                                : 'Recording…')
                          : 'Voice',
                      style: TextStyle(
                        fontSize: AppTypography.headlineMedium,
                        fontWeight: FontWeight.w600,
                        color: context.conduitTheme.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        // Language chip
                        GestureDetector(
                          onTap: _voiceService.hasLocalStt
                              ? _pickLanguage
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.xs,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: context.conduitTheme.surfaceBackground
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(
                                AppBorderRadius.badge,
                              ),
                              border: Border.all(
                                color: context.conduitTheme.dividerColor,
                                width: BorderWidth.thin,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _languageTag.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: AppTypography.labelSmall,
                                    color: context.conduitTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_voiceService.hasLocalStt) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 16,
                                    color: context.conduitTheme.iconSecondary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        // Timer
                        AnimatedOpacity(
                          opacity: _isListening ? 1 : 0.6,
                          duration: AnimationDuration.fast,
                          child: Text(
                            _formatSeconds(_elapsedSeconds),
                            style: TextStyle(
                              color: context.conduitTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        // Close sheet
                        ConduitIconButton(
                          icon: Platform.isIOS
                              ? CupertinoIcons.xmark
                              : Icons.close,
                          tooltip: AppLocalizations.of(
                            context,
                          )!.closeButtonSemantic,
                          isCompact: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Toggles row: Hold to talk, Auto-send
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildThemedSwitch(
                            value: _holdToTalk,
                            onChanged: (v) async {
                              setState(() => _holdToTalk = v);
                              await ref
                                  .read(appSettingsProvider.notifier)
                                  .setVoiceHoldToTalk(v);
                            },
                          ),
                          const SizedBox(width: Spacing.xs),
                          Text(
                            'Hold to talk',
                            style: TextStyle(
                              color: context.conduitTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildThemedSwitch(
                            value: _autoSendFinal,
                            onChanged: (v) async {
                              setState(() => _autoSendFinal = v);
                              await ref
                                  .read(appSettingsProvider.notifier)
                                  .setVoiceAutoSendFinal(v);
                            },
                          ),
                          const SizedBox(width: Spacing.xs),
                          Text(
                            'Auto-send',
                            style: TextStyle(
                              color: context.conduitTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Microphone + waveform
              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) {
                    final isUltra = media.size.height < 560;
                    final double micSize = isUltra
                        ? 64
                        : (isCompact ? 80 : 100);
                    final double micIconSize = isUltra
                        ? 26
                        : (isCompact ? 32 : 40);
                    // Extra top padding so scale animation (up to 1.2x) never clips
                    final double topPaddingForScale =
                        ((micSize * 1.2) - micSize) / 2 + 8;

                    final content = Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Top spacer (baseline); additional padding handled by scroll view
                          SizedBox(height: isUltra ? Spacing.sm : Spacing.md),
                          // Microphone control
                          GestureDetector(
                                onTapDown: _holdToTalk
                                    ? (_) {
                                        if (!_isListening) _startListening();
                                      }
                                    : null,
                                onTapUp: _holdToTalk
                                    ? (_) {
                                        if (_isListening) _stopListening();
                                      }
                                    : null,
                                onTapCancel: _holdToTalk
                                    ? () {
                                        if (_isListening) _stopListening();
                                      }
                                    : null,
                                onTap: () => _holdToTalk
                                    ? null
                                    : (_isListening
                                          ? _stopListening()
                                          : _startListening()),
                                child: Container(
                                  width: micSize,
                                  height: micSize,
                                  decoration: BoxDecoration(
                                    color: _isListening
                                        ? context.conduitTheme.error.withValues(
                                            alpha: 0.2,
                                          )
                                        : context.conduitTheme.surfaceBackground
                                              .withValues(alpha: Alpha.subtle),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _isListening
                                          ? context.conduitTheme.error
                                                .withValues(alpha: 0.5)
                                          : context.conduitTheme.dividerColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: Icon(
                                    _isListening
                                        ? (Platform.isIOS
                                              ? CupertinoIcons.mic_fill
                                              : Icons.mic)
                                        : (Platform.isIOS
                                              ? CupertinoIcons.mic_off
                                              : Icons.mic_off),
                                    size: micIconSize,
                                    color: _isListening
                                        ? context.conduitTheme.error
                                        : context.conduitTheme.iconSecondary,
                                  ),
                                ),
                              )
                              .animate(
                                onPlay: (controller) =>
                                    _isListening ? controller.repeat() : null,
                              )
                              .scale(
                                duration: const Duration(milliseconds: 1000),
                                begin: const Offset(1, 1),
                                end: const Offset(1.2, 1.2),
                              )
                              .then()
                              .scale(
                                duration: const Duration(milliseconds: 1000),
                                begin: const Offset(1.2, 1.2),
                                end: const Offset(1, 1),
                              ),

                          SizedBox(
                            height: isUltra
                                ? Spacing.xs
                                : (isCompact ? Spacing.sm : Spacing.md),
                          ),
                          // Simple animated bars waveform based on intensity proxy
                          SizedBox(
                            height: isUltra ? 18 : (isCompact ? 24 : 32),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: Row(
                                key: ValueKey<int>(_intensity),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(isUltra ? 10 : 12, (i) {
                                  final normalized =
                                      ((_intensity + i) % 10) / 10.0;
                                  final base = isUltra
                                      ? 4
                                      : (isCompact ? 6 : 8);
                                  final range = isUltra
                                      ? 14
                                      : (isCompact ? 18 : 24);
                                  final barHeight = base + (normalized * range);
                                  return Container(
                                    width: isUltra ? 2.5 : (isCompact ? 3 : 4),
                                    height: barHeight,
                                    margin: EdgeInsets.symmetric(
                                      horizontal: isUltra
                                          ? 1
                                          : (isCompact ? 1.5 : 2),
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.conduitTheme.buttonPrimary
                                          .withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: isUltra
                                ? Spacing.sm
                                : (isCompact ? Spacing.md : Spacing.xl),
                          ),

                          // Recognized text / Transcribing state with Clear action
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  media.size.height *
                                  (isUltra ? 0.13 : (isCompact ? 0.16 : 0.2)),
                              minHeight: isUltra ? 56 : (isCompact ? 64 : 80),
                            ),
                            child: ConduitCard(
                              isCompact: isCompact,
                              padding: EdgeInsets.all(
                                isCompact ? Spacing.md : Spacing.md,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Inline clear action aligned to the end
                                  Row(
                                    children: [
                                      Text(
                                        'Transcript',
                                        style: TextStyle(
                                          fontSize: AppTypography.labelSmall,
                                          fontWeight: FontWeight.w600,
                                          color: context
                                              .conduitTheme
                                              .textSecondary,
                                        ),
                                      ),
                                      const Spacer(),
                                      ConduitIconButton(
                                        icon: Icons.close,
                                        isCompact: true,
                                        tooltip: AppLocalizations.of(
                                          context,
                                        )!.clear,
                                        onPressed:
                                            _recognizedText.isNotEmpty &&
                                                !_isTranscribing
                                            ? () {
                                                setState(
                                                  () => _recognizedText = '',
                                                );
                                              }
                                            : null,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: Spacing.xs),
                                  if (_isTranscribing)
                                    Center(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          ConduitLoadingIndicator(
                                            size: isUltra
                                                ? 14
                                                : (isCompact ? 16 : 18),
                                            isCompact: true,
                                          ),
                                          const SizedBox(width: Spacing.xs),
                                          Text(
                                            'Transcribing…',
                                            style: TextStyle(
                                              fontSize: isUltra
                                                  ? AppTypography.bodySmall
                                                  : (isCompact
                                                        ? AppTypography
                                                              .bodyMedium
                                                        : AppTypography
                                                              .bodyLarge),
                                              color: context
                                                  .conduitTheme
                                                  .textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Flexible(
                                      child: SingleChildScrollView(
                                        child: Text(
                                          _recognizedText.isEmpty
                                              ? (_isListening
                                                    ? (_voiceService.hasLocalStt
                                                          ? 'Speak now…'
                                                          : 'Recording…')
                                                    : 'Tap Start to begin')
                                              : _recognizedText,
                                          style: TextStyle(
                                            fontSize: isUltra
                                                ? AppTypography.bodySmall
                                                : (isCompact
                                                      ? AppTypography.bodyMedium
                                                      : AppTypography
                                                            .bodyLarge),
                                            color: _recognizedText.isEmpty
                                                ? context
                                                      .conduitTheme
                                                      .inputPlaceholder
                                                : context
                                                      .conduitTheme
                                                      .textPrimary,
                                            height: 1.4,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    // Make scrollable if content exceeds available height
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: EdgeInsets.only(top: topPaddingForScale),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: viewport.maxHeight,
                        ),
                        child: content,
                      ),
                    );
                  },
                ),
              ),

              // Action buttons
              Builder(
                builder: (context) {
                  final showStartStop = !_holdToTalk;
                  final showSend = !_autoSendFinal;
                  if (!showStartStop && !showSend) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: EdgeInsets.only(
                      top: isCompact ? Spacing.sm : Spacing.md,
                    ),
                    child: Row(
                      children: [
                        if (showStartStop) ...[
                          Expanded(
                            child: ConduitButton(
                              text: _isListening ? 'Stop' : 'Start',
                              isSecondary: true,
                              isCompact: isCompact,
                              onPressed: _isListening
                                  ? _stopListening
                                  : _startListening,
                            ),
                          ),
                        ],
                        if (showStartStop && showSend)
                          const SizedBox(width: Spacing.xs),
                        if (showSend) ...[
                          Expanded(
                            child: ConduitButton(
                              text: 'Send',
                              isCompact: isCompact,
                              onPressed: _recognizedText.isNotEmpty
                                  ? _sendText
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper widget for selectable messages with visual selection indicators
class _SelectableMessageWrapper extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _SelectableMessageWrapper({
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
        decoration: BoxDecoration(
          color: isSelected
              ? context.conduitTheme.buttonPrimary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: isSelected
              ? Border.all(
                  color: context.conduitTheme.buttonPrimary.withValues(
                    alpha: 0.3,
                  ),
                  width: 2,
                )
              : null,
        ),
        child: Stack(
          children: [
            child,
            if (isSelected)
              Positioned(
                top: Spacing.sm,
                right: Spacing.sm,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: context.conduitTheme.buttonPrimary,
                    shape: BoxShape.circle,
                    boxShadow: ConduitShadows.medium,
                  ),
                  child: Icon(
                    Icons.check,
                    color: context.conduitTheme.textInverse,
                    size: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Extension on _ChatPageState for utility methods
extension on _ChatPageState {}
