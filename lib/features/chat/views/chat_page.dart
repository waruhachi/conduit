import 'package:flutter/material.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../shared/widgets/optimized_list.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform, File;
import 'dart:async';
import 'package:path/path.dart' as path;
import '../../../core/providers/app_providers.dart';
import '../providers/chat_providers.dart';

import '../widgets/modern_chat_input.dart';
import '../widgets/modern_message_bubble.dart';
import '../widgets/documentation_message_widget.dart';
import '../widgets/file_attachment_widget.dart';
import '../services/voice_input_service.dart';
import '../services/file_attachment_service.dart';
import '../../navigation/views/chats_list_page.dart';
import '../../files/views/files_page.dart';
import '../../profile/views/profile_page.dart';
import '../../../shared/widgets/offline_indicator.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/model.dart';
import '../../../shared/widgets/loading_states.dart';
import 'chat_page_helpers.dart';
import '../../../shared/widgets/themed_dialogs.dart';

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

  @override
  void initState() {
    super.initState();

    // Listen to scroll events to show/hide scroll to bottom button
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollDebounceTimer?.cancel();
    super.dispose();
  }

  void _handleMessageSend(String text, dynamic selectedModel) async {
    debugPrint('DEBUG: Starting message send process');
    debugPrint('DEBUG: Message text: $text');
    debugPrint('DEBUG: Selected model: ${selectedModel?.name ?? 'null'}');

    if (selectedModel == null) {
      debugPrint('DEBUG: No model selected');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a model first')),
        );
      }
      return;
    }

    final isOnline = ref.read(isOnlineProvider);
    debugPrint('DEBUG: Online status: $isOnline');
    if (!isOnline) {
      debugPrint('DEBUG: Offline - cannot send message');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'You\'re offline. Message will be sent when connection is restored.',
            ),
            backgroundColor: context.conduitTheme.warning,
          ),
        );
      }
      // TODO: Implement message queueing for offline mode
      return;
    }

    try {
      // Get attached files and use uploadedFileIds when sendMessage is updated to accept file IDs
      final attachedFiles = ref.read(attachedFilesProvider);
      debugPrint('DEBUG: Attached files count: ${attachedFiles.length}');

      for (final file in attachedFiles) {
        debugPrint(
          'DEBUG: File - Name: ${file.fileName}, Status: ${file.status}, FileId: ${file.fileId}',
        );
      }

      final uploadedFileIds = attachedFiles
          .where(
            (file) =>
                file.status == FileUploadStatus.completed &&
                file.fileId != null,
          )
          .map((file) => file.fileId!)
          .toList();

      debugPrint('DEBUG: Uploaded file IDs: $uploadedFileIds');

      // Send message with file attachments using existing provider logic
      await sendMessage(
        ref,
        text,
        uploadedFileIds.isNotEmpty ? uploadedFileIds : null,
      );

      debugPrint('DEBUG: Message sent successfully');

      // Clear attachments after successful send
      ref.read(attachedFilesProvider.notifier).clearAll();
      debugPrint('DEBUG: Attachments cleared');

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
      debugPrint('DEBUG: Message send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Message failed to send. Please try again.'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
      }
    }
  }

  void _handleVoiceInput() async {
    // TODO: Implement voice input functionality
    final isAvailable = await ref.read(voiceInputAvailableProvider.future);

    if (!isAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Voice input unavailable. Check permissions.'),
          backgroundColor: context.conduitTheme.warning,
        ),
      );
      return;
    }

    // Show voice input dialog
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _VoiceInputSheet(
        onTextReceived: (text) {
          if (text.isNotEmpty) {
            final selectedModel = ref.read(selectedModelProvider);
            if (selectedModel != null) {
              _handleMessageSend(text, selectedModel);
            }
          }
        },
      ),
    );
  }

  void _handleFileAttachment() async {
    // Check if selected model supports file upload
    final fileUploadCapableModels = ref.read(fileUploadCapableModelsProvider);
    if (fileUploadCapableModels.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selected model does not support file upload'),
          backgroundColor: context.conduitTheme.error,
        ),
      );
      return;
    }

    final fileService = ref.read(fileAttachmentServiceProvider);
    if (fileService == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File service unavailable')));
      return;
    }

    try {
      final files = await fileService.pickFiles();
      if (files.isEmpty) return;

      // Validate file count
      final currentFiles = ref.read(attachedFilesProvider);
      if (!validateFileCount(currentFiles.length, files.length, 10)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Maximum 10 files allowed'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
        return;
      }

      // Validate file sizes
      for (final file in files) {
        final fileSize = await file.length();
        if (!validateFileSize(fileSize, 20)) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File ${path.basename(file.path)} exceeds 20MB limit',
              ),
              backgroundColor: context.conduitTheme.error,
            ),
          );
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Upload failed: $error'),
                backgroundColor: context.conduitTheme.error,
              ),
            );
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File selection failed: $e'),
          backgroundColor: context.conduitTheme.error,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selected model does not support image inputs'),
          backgroundColor: context.conduitTheme.error,
        ),
      );
      return;
    }

    final fileService = ref.read(fileAttachmentServiceProvider);
    if (fileService == null) {
      debugPrint('DEBUG: File service is null - cannot proceed');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File service unavailable')));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image size exceeds 20MB limit'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
        return;
      }

      // Validate file count (default 10 files limit like OpenWebUI)
      final currentFiles = ref.read(attachedFilesProvider);
      if (!validateFileCount(currentFiles.length, 1, 10)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Maximum 10 files allowed'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image upload failed: $error'),
              backgroundColor: context.conduitTheme.error,
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('DEBUG: Image attachment error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image attachment failed: $e'),
          backgroundColor: context.conduitTheme.error,
        ),
      );
    }
  }

  void _handleNewChat() {
    // Start a new chat using the existing function
    startNewChat(ref);

    // Hide scroll-to-bottom button for a fresh chat
    if (mounted) {
      setState(() {
        _showScrollToBottom = false;
      });
    }

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New chat started'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showChatsListOverlay() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
                decoration: BoxDecoration(
                  color: context.conduitTheme.dividerColor,
                  borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                ),
              ),
              Expanded(child: const ChatsListPage(isOverlay: true)),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickAccessMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.conduitTheme.surfaceBackground,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppBorderRadius.modal),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
                decoration: BoxDecoration(
                  color: context.conduitTheme.dividerColor,
                  borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                ),
              ),
              // Hint text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                child: Text(
                  'Quick Actions',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: context.conduitTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              // Menu items
              ListTile(
                leading: Icon(
                  Platform.isIOS ? CupertinoIcons.plus : Icons.add_rounded,
                  color: context.conduitTheme.iconPrimary,
                ),
                title: Text(
                  'New Chat',
                  style: AppTypography.bodyLargeStyle.copyWith(
                    color: context.conduitTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Start a new conversation',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: context.conduitTheme.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleNewChat();
                },
              ),
              ListTile(
                leading: Icon(
                  Platform.isIOS
                      ? CupertinoIcons.doc
                      : Icons.description_outlined,
                  color: context.conduitTheme.iconPrimary,
                ),
                title: Text(
                  'Files',
                  style: AppTypography.bodyLargeStyle.copyWith(
                    color: context.conduitTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Manage your files and documents',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: context.conduitTheme.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToFiles();
                },
              ),
              ListTile(
                leading: Icon(
                  Platform.isIOS ? CupertinoIcons.person : Icons.person_outline,
                  color: context.conduitTheme.iconPrimary,
                ),
                title: Text(
                  'Profile',
                  style: AppTypography.bodyLargeStyle.copyWith(
                    color: context.conduitTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'View and manage your profile',
                  style: AppTypography.bodySmallStyle.copyWith(
                    color: context.conduitTheme.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToProfile();
                },
              ),
              const SizedBox(height: Spacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToFiles() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const FilesPage()));
  }

  void _navigateToProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ProfilePage()));
  }

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

    if (isLoadingConversation && messages.isEmpty) {
      // Show message skeletons during conversation load
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.xl,
          Spacing.lg,
          Spacing.lg,
        ),
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

    if (messages.isEmpty) {
      return _buildEmptyState(theme);
    }

    return OptimizedList<ChatMessage>(
      scrollController: _scrollController,
      items: messages,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
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
          messageWidget = ModernMessageBubble(
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
          messageWidget = DocumentationMessageWidget(
            key: ValueKey('assistant-${message.id}'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _regenerateMessage(dynamic message) async {
    final selectedModel = ref.read(selectedModelProvider);
    if (selectedModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a model first')),
      );
      return;
    }

    // Find the user message that prompted this assistant response
    final messages = ref.read(chatMessagesProvider);
    final messageIndex = messages.indexOf(message);

    if (messageIndex <= 0 || messages[messageIndex - 1].role != 'user') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot regenerate this message')),
      );
      return;
    }

    try {
      // Remove the assistant message we want to regenerate
      ref.read(chatMessagesProvider.notifier).removeLastMessage();

      // Resend the previous user message to get a new response
      final userMessage = messages[messageIndex - 1];
      await sendMessage(ref, userMessage.content, null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Regenerating...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate message: $e'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
      }
    }
  }

  void _editMessage(dynamic message) async {
    if (message.role != 'user') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only user messages can be edited')),
      );
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
            hintText: 'Enter your message',
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
            child: const Text('Save'),
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

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message updated'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to edit message: $e'),
              backgroundColor: context.conduitTheme.error,
            ),
          );
        }
      }
    }

    controller.dispose();
  }

  void _likeMessage(dynamic message) {
    // TODO: Implement message liking
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Message liked!')));
  }

  void _dislikeMessage(dynamic message) {
    // TODO: Implement message disliking
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Message disliked!')));
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
              'Start a conversation',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.conduitTheme.textPrimary,
              ),
            ).animate().fadeIn(delay: const Duration(milliseconds: 150)),

            const SizedBox(height: Spacing.sm),

            Text(
              'Type below to begin',
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

    return ErrorBoundary(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) async {
          if (didPop) return;

          // Check if there's unsaved content
          final messages = ref.read(chatMessagesProvider);
          if (messages.isNotEmpty) {
            // Check if currently streaming
            final isStreaming = messages.any((msg) => msg.isStreaming);
            
            final shouldPop = await NavigationService.confirmNavigation(
              title: 'Leave Chat?',
              message: isStreaming 
                ? 'The AI is still responding. Leave anyway?'
                : 'Your conversation will be saved.',
              confirmText: 'Leave',
              cancelText: 'Stay',
            );
            if (shouldPop && context.mounted) {
              // If streaming, stop it first
              if (isStreaming) {
                ref.read(chatMessagesProvider.notifier).finishStreaming();
              }
              
              // Save the conversation before leaving
              await _saveConversationBeforeLeaving(ref);
              
              if (context.mounted) {
                final canPopNavigator = Navigator.of(context).canPop();
                if (canPopNavigator) {
                  Navigator.of(context).pop();
                } else {
                  SystemNavigator.pop();
                }
              }
            }
          } else if (context.mounted) {
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
          appBar: AppBar(
            backgroundColor: context.conduitTheme.surfaceBackground,
            elevation: Elevation.none,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            toolbarHeight: kToolbarHeight,
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
                : GestureDetector(
                    onTap: () {
                      _showChatsListOverlay();
                    },
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      _showQuickAccessMenu();
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatModelDisplayName(selectedModel.name),
                          style: AppTypography.headlineSmallStyle.copyWith(
                            color: context.conduitTheme.textPrimary,
                            fontWeight: FontWeight.w400,
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
                  )
                : GestureDetector(
                    onTap: () {
                      final modelsAsync = ref.read(modelsProvider);
                      modelsAsync.whenData(
                        (models) => _showModelDropdown(context, ref, models),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Choose Model',
                          style: AppTypography.headlineSmallStyle.copyWith(
                            color: context.conduitTheme.textPrimary,
                            fontWeight: FontWeight.w400,
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
                  ),
            actions: [
              if (!_isSelectionMode) ...[
                IconButton(
                  icon: Icon(
                    Platform.isIOS
                        ? CupertinoIcons.bubble_left
                        : Icons.chat_bubble_outline,
                    color: context.conduitTheme.textPrimary,
                    size: IconSize.appBar,
                  ),
                  onPressed: _handleNewChat,
                  tooltip: 'New Chat',
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
                  // Server banners
                  Consumer(
                    builder: (context, ref, child) {
                      final banners = ref.watch(serverBannersProvider);
                      return banners.when(
                        data: (bannerList) => bannerList.isNotEmpty
                            ? Container(
                                color: theme.colorScheme.primaryContainer
                                    .withValues(alpha: Alpha.badgeBackground),
                                child: Column(
                                  children: bannerList
                                      .take(1)
                                      .map(
                                        (banner) =>
                                            _buildChatBanner(context, banner),
                                      )
                                      .toList(),
                                ),
                              )
                            : const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      );
                    },
                  ),

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
                            debugPrint('DEBUG: Failed to refresh conversation: $e');
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
                    enabled: selectedModel != null && isOnline,
                    onSendMessage: (text) =>
                        _handleMessageSend(text, selectedModel),
                    onVoiceInput: _handleVoiceInput,
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

      // Check if the last message (assistant) has content
      final lastMessage = messages.last;
      if (lastMessage.role == 'assistant' && lastMessage.content.trim().isEmpty) {
        // Remove empty assistant message before saving
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Messages removed'),
              duration: Duration(seconds: 2),
            ),
          );
        }
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
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(
                      top: Spacing.sm,
                      bottom: Spacing.md,
                    ),
                    width: Spacing.xxl,
                    height: Spacing.xs,
                    decoration: BoxDecoration(
                      color: context.conduitTheme.dividerColor,
                      borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Choose Model',
                            style: TextStyle(
                              color: context.conduitTheme.textPrimary,
                              fontSize: AppTypography.headlineMedium,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Removed capabilities legend to reduce icon noise
                      ],
                    ),
                  ),

                  // Search field
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.md),
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: context.conduitTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search...',
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

  @override
  void initState() {
    super.initState();
    _voiceService = ref.read(voiceInputServiceProvider);
    try {
      _languageTag = WidgetsBinding.instance.platformDispatcher.locale
          .toLanguageTag()
          .split(RegExp('[-_]'))
          .first
          .toLowerCase();
    } catch (_) {
      _languageTag = 'en';
    }
  }

  void _startListening() async {
    setState(() {
      _isListening = true;
      _recognizedText = '';
      _elapsedSeconds = 0;
    });

    try {
      // Ensure service is initialized and has permission
      final ok = await _voiceService.initialize();
      if (!ok || !await _voiceService.checkPermissions()) {
        throw Exception('Microphone permission not granted');
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
          // If we receive a special token with recorded audio path, transcribe it via API
          if (text.startsWith('[[AUDIO_FILE_PATH]]:')) {
            final filePath = text.split(':').skip(1).join(':');
            debugPrint(
              'DEBUG: VoiceInputSheet received audio file path: ' + filePath,
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
        },
        onError: (error) {
          debugPrint('DEBUG: VoiceInputSheet stream error: $error');
          setState(() {
            _isListening = false;
          });
          _elapsedTimer?.cancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Voice input error: $error'),
                backgroundColor: context.conduitTheme.error,
              ),
            );
          }
        },
      );
    } catch (e) {
      setState(() {
        _isListening = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start voice input: $e'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
      }
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
        'DEBUG: Transcription received: ' + (text.isEmpty ? '[empty]' : text),
      );
      if (!mounted) return;
      setState(() {
        _recognizedText = text;
      });
      // Stop listening state if we have a result
      setState(() => _isListening = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transcription failed: $e'),
          backgroundColor: context.conduitTheme.error,
        ),
      );
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
  }

  void _sendText() {
    if (_recognizedText.isNotEmpty) {
      widget.onTextReceived(_recognizedText);
      Navigator.pop(context);
    }
  }

  String _formatSeconds(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _cancel() {
    _stopListening();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _intensitySub?.cancel();
    _textSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.lg),
        ),
        border: Border.all(color: context.conduitTheme.dividerColor, width: 1),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: Spacing.sm),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.conduitTheme.dividerColor,
              borderRadius: BorderRadius.circular(AppBorderRadius.xs),
            ),
          ),

          // Header: Title + timer + language chip
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isListening
                      ? 'Listening\u2026'
                      : _isTranscribing
                      ? 'Transcribing\u2026'
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
                    Container(
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
                      child: Text(
                        _languageTag.toUpperCase(),
                        style: TextStyle(
                          fontSize: AppTypography.labelSmall,
                          color: context.conduitTheme.textSecondary,
                          fontWeight: FontWeight.w600,
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
                  ],
                ),
              ],
            ),
          ),

          // Microphone animation and waveform
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Microphone icon with animation (tap to toggle)
                  GestureDetector(
                        onTap: () =>
                            _isListening ? _stopListening() : _startListening(),
                        child: Container(
                          width: 100,
                          height: 100,
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
                                  ? context.conduitTheme.error.withValues(
                                      alpha: 0.5,
                                    )
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
                            size: 40,
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

                  const SizedBox(height: Spacing.md),
                  // Simple animated bars waveform based on intensity proxy
                  SizedBox(
                    height: 32,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Row(
                        key: ValueKey<int>(_intensity),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(12, (i) {
                          final normalized = ((_intensity + i) % 10) / 10.0;
                          final barHeight = 8 + (normalized * 24);
                          return Container(
                            width: 4,
                            height: barHeight,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
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
                  const SizedBox(height: Spacing.xl),

                  // Recognized text / Transcribing state
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(Spacing.md),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.2,
                      minHeight: 80,
                    ),
                    decoration: BoxDecoration(
                      color: context.conduitTheme.inputBackground,
                      borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      border: Border.all(
                        color: context.conduitTheme.inputBorder,
                        width: 1,
                      ),
                    ),
                    child: _isTranscribing
                        ? Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.conduitTheme.buttonPrimary,
                                  ),
                                ),
                                const SizedBox(width: Spacing.xs),
                                Text(
                                  'Transcribing…',
                                  style: TextStyle(
                                    fontSize: AppTypography.bodyLarge,
                                    color: context.conduitTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: Text(
                              _recognizedText.isEmpty
                                  ? (_isListening
                                        ? 'Speak now…'
                                        : 'Tap Start to begin')
                                  : _recognizedText,
                              style: TextStyle(
                                fontSize: AppTypography.bodyLarge,
                                color: _recognizedText.isEmpty
                                    ? context.conduitTheme.inputPlaceholder
                                    : context.conduitTheme.textPrimary,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              children: [
                // Start/Stop toggle button
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _isListening ? _stopListening : _startListening,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      ),
                    ),
                    child: Text(
                      _isListening ? 'Stop' : 'Start',
                      style: TextStyle(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                        color: context.conduitTheme.textPrimary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: Spacing.xs),
                // Cancel button
                Expanded(
                  child: TextButton(
                    onPressed: _cancel,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                        side: BorderSide(
                          color: context.conduitTheme.dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: context.conduitTheme.textPrimary,
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: Spacing.xs),

                // Send button
                Expanded(
                  child: FilledButton(
                    onPressed: _recognizedText.isNotEmpty ? _sendText : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.conduitTheme.buttonPrimary,
                      foregroundColor: context.conduitTheme.buttonPrimaryText,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppBorderRadius.md),
                      ),
                    ),
                    child: Text(
                      'Send',
                      style: TextStyle(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
extension on _ChatPageState {
  Widget _buildChatBanner(BuildContext context, Map<String, dynamic> banner) {
    final theme = Theme.of(context);

    final type = banner['type'] as String? ?? 'info';
    final content = banner['content'] as String? ?? '';

    if (content.isEmpty) return const SizedBox.shrink();

    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (type) {
      case 'warning':
        backgroundColor = context.conduitTheme.warning.withValues(alpha: 0.2);
        textColor = context.conduitTheme.warning;
        icon = Platform.isIOS
            ? CupertinoIcons.exclamationmark_triangle
            : Icons.warning;
        break;
      case 'error':
        backgroundColor = theme.colorScheme.errorContainer;
        textColor = theme.colorScheme.onErrorContainer;
        icon = Platform.isIOS ? CupertinoIcons.xmark_circle : Icons.error;
        break;
      default: // info
        backgroundColor = theme.colorScheme.primaryContainer;
        textColor = theme.colorScheme.onPrimaryContainer;
        icon = Platform.isIOS ? CupertinoIcons.info_circle : Icons.info;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: backgroundColor,
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 16),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              content,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
