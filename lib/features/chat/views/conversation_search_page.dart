import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../../../shared/utils/platform_utils.dart';
import '../widgets/conversation_search_widget.dart';
import '../../../core/providers/app_providers.dart';
import '../providers/chat_providers.dart';
import 'chat_page.dart';

/// Dedicated page for conversation search functionality
class ConversationSearchPage extends ConsumerStatefulWidget {
  const ConversationSearchPage({super.key});

  @override
  ConsumerState<ConversationSearchPage> createState() =>
      _ConversationSearchPageState();
}

class _ConversationSearchPageState
    extends ConsumerState<ConversationSearchPage> {
  @override
  Widget build(BuildContext context) {
    final conduitTheme = context.conduitTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context, conduitTheme),
      body: ConversationSearchWidget(
        onResultTap: _onSearchResultTap,
        showFilters: true,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    if (Platform.isIOS) {
      return CupertinoNavigationBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.cardBorder, width: 0.5)),
        leading: CupertinoNavigationBarBackButton(
          color: context.conduitTheme.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        middle: Text(
          'Search Conversations',
          style: TextStyle(
            color: context.conduitTheme.textPrimary,
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: Elevation.none,
      title: Text(
        'Search Conversations',
        style: TextStyle(
          color: context.conduitTheme.textPrimary,
          fontSize: AppTypography.headlineMedium,
          fontWeight: FontWeight.w600,
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: context.conduitTheme.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: theme.cardBorder),
      ),
    );
  }

  void _onSearchResultTap(String conversationId, String? messageId) {
    PlatformUtils.lightHaptic();

    // Set the active conversation
    final conversationsAsync = ref.read(conversationsProvider);
    conversationsAsync.whenData((conversations) {
      final conversation = conversations.firstWhere(
        (c) => c.id == conversationId,
        orElse: () => throw Exception('Conversation not found'),
      );

      // Set active conversation
      ref.read(activeConversationProvider.notifier).state = conversation;

      // Navigate back to chat
      Navigator.of(context).pop();

      // If we have a specific message, navigate to it and highlight it
      if (messageId != null) {
        // Use a custom navigation approach with message highlighting
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) =>
                ChatPageWithHighlight(messageIdToHighlight: messageId),
          ),
        );
      }
    });
  }
}

/// Chat page wrapper that highlights a specific message
class ChatPageWithHighlight extends ConsumerStatefulWidget {
  final String messageIdToHighlight;

  const ChatPageWithHighlight({super.key, required this.messageIdToHighlight});

  @override
  ConsumerState<ChatPageWithHighlight> createState() =>
      _ChatPageWithHighlightState();
}

class _ChatPageWithHighlightState extends ConsumerState<ChatPageWithHighlight> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Schedule highlighting after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToAndHighlightMessage();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToAndHighlightMessage() async {
    try {
      final messages = ref.read(chatMessagesProvider);
      final messageIndex = messages.indexWhere(
        (msg) => msg.id == widget.messageIdToHighlight,
      );

      if (messageIndex >= 0 && _scrollController.hasClients) {
        // Calculate the approximate position (assuming 100px per message)
        final targetOffset = messageIndex * 100.0;

        // Scroll to the message
        await _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );

        // Show a highlight indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Found message'),
              duration: const Duration(seconds: 2),
              backgroundColor: context.conduitTheme.buttonPrimary,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Message not found'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const ChatPage();
  }
}

/// Search icon button for app bars
class ConversationSearchButton extends ConsumerWidget {
  final VoidCallback? onPressed;

  const ConversationSearchButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(
        Platform.isIOS ? CupertinoIcons.search : Icons.search,
        color: context.conduitTheme.iconPrimary.withValues(alpha: 0.8),
        size: IconSize.lg,
      ),
      onPressed:
          onPressed ??
          () {
            PlatformUtils.lightHaptic();
            Navigator.of(context).push(
              Platform.isIOS
                  ? CupertinoPageRoute(
                      builder: (context) => const ConversationSearchPage(),
                    )
                  : MaterialPageRoute(
                      builder: (context) => const ConversationSearchPage(),
                    ),
            );
          },
      tooltip: 'Search conversations',
    );
  }
}

/// Quick search overlay that can be shown from any page
class QuickSearchOverlay extends ConsumerStatefulWidget {
  final VoidCallback? onDismiss;

  const QuickSearchOverlay({super.key, this.onDismiss});

  @override
  ConsumerState<QuickSearchOverlay> createState() => _QuickSearchOverlayState();
}

class _QuickSearchOverlayState extends ConsumerState<QuickSearchOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _animationController.reverse();
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Stack(
          children: [
            // Backdrop
            GestureDetector(
              onTap: _dismiss,
              child: Container(
                color: context.conduitTheme.surfaceBackground.withValues(
                  alpha: 0.7 * _fadeAnimation.value,
                ),
              ),
            ),

            // Search panel
            SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.8,
                  margin: const EdgeInsets.only(top: Spacing.xxxl + Spacing.md),
                  decoration: BoxDecoration(
                    color: context.conduitTheme.surfaceBackground,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppBorderRadius.lg),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle bar
                      Container(
                        margin: const EdgeInsets.only(top: Spacing.sm),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.conduitTheme.textPrimary.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppBorderRadius.xs,
                          ),
                        ),
                      ),

                      // Search content
                      Expanded(
                        child: ConversationSearchWidget(
                          onResultTap: (conversationId, messageId) {
                            _onSearchResultTap(conversationId, messageId);
                            _dismiss();
                          },
                          showFilters: false, // Simplified for overlay
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onSearchResultTap(String conversationId, String? messageId) {
    // Same logic as the search page
    final conversationsAsync = ref.read(conversationsProvider);
    conversationsAsync.whenData((conversations) {
      final conversation = conversations.firstWhere(
        (c) => c.id == conversationId,
        orElse: () => throw Exception('Conversation not found'),
      );

      ref.read(activeConversationProvider.notifier).state = conversation;

      if (messageId != null) {
        debugPrint(
          'Navigate to message: $messageId in conversation: $conversationId',
        );
      }
    });
  }
}

/// Show quick search overlay
void showQuickSearch(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return QuickSearchOverlay(onDismiss: () => Navigator.of(context).pop());
    },
  );
}
