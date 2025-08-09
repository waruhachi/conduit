import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ThemedDialogs handles theming; no direct use of extensions here
import '../../features/chat/views/chat_page.dart';
import '../../features/auth/views/connect_signin_page.dart';
import '../../features/settings/views/searchable_settings_page.dart';
import '../../features/profile/views/profile_page.dart';
import '../../features/files/views/files_page.dart';
import '../../features/chat/views/conversation_search_page.dart';
import '../../shared/widgets/themed_dialogs.dart';

import '../../features/navigation/views/chats_list_page.dart';

/// Centralized navigation service to handle all routing logic
/// Prevents navigation stack issues and memory leaks
class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static NavigatorState? get navigator => navigatorKey.currentState;
  static BuildContext? get context => navigatorKey.currentContext;

  // Navigation stack tracking for analytics and debugging
  static final List<String> _navigationStack = [];
  static List<String> get navigationStack =>
      List.unmodifiable(_navigationStack);

  // Prevent duplicate navigation
  static String? _currentRoute;
  static bool _isNavigating = false;
  static DateTime? _lastNavigationTime;

  /// Navigate to a named route with optional arguments
  static Future<T?> navigateTo<T>(
    String routeName, {
    Object? arguments,
    bool replace = false,
    bool clearStack = false,
  }) async {
    // Only block if we're already navigating to the exact same route
    // Allow navigation to different routes even if currently navigating
    if (_isNavigating && _currentRoute == routeName) {
      debugPrint('Navigation blocked: Already navigating to same route');
      return null;
    }

    // Prevent rapid successive navigation attempts
    final now = DateTime.now();
    if (_lastNavigationTime != null &&
        now.difference(_lastNavigationTime!).inMilliseconds < 300) {
      debugPrint('Navigation blocked: Too rapid navigation attempts');
      return null;
    }

    _isNavigating = true;

    try {
      // Add haptic feedback for navigation
      HapticFeedback.lightImpact();

      // Track navigation
      if (!replace && !clearStack) {
        _navigationStack.add(routeName);
      }
      _currentRoute = routeName;

      if (clearStack) {
        _navigationStack.clear();
        _navigationStack.add(routeName);
        return await navigator?.pushNamedAndRemoveUntil<T>(
          routeName,
          (route) => false,
          arguments: arguments,
        );
      } else if (replace) {
        if (_navigationStack.isNotEmpty) {
          _navigationStack.removeLast();
        }
        _navigationStack.add(routeName);
        return await navigator?.pushReplacementNamed<T, T>(
          routeName,
          arguments: arguments,
        );
      } else {
        return await navigator?.pushNamed<T>(routeName, arguments: arguments);
      }
    } catch (e) {
      debugPrint('Navigation error: $e');
      rethrow;
    } finally {
      _isNavigating = false;
      _lastNavigationTime = DateTime.now();
    }
  }

  /// Navigate back with optional result
  static void goBack<T>([T? result]) {
    if (navigator?.canPop() == true) {
      HapticFeedback.lightImpact();
      if (_navigationStack.isNotEmpty) {
        _navigationStack.removeLast();
      }
      _currentRoute = _navigationStack.isEmpty ? null : _navigationStack.last;
      navigator?.pop<T>(result);
    }
  }

  /// Check if can navigate back
  static bool canGoBack() {
    return navigator?.canPop() == true;
  }

  /// Show confirmation dialog before navigation
  static Future<bool> confirmNavigation({
    required String title,
    required String message,
    String confirmText = 'Continue',
    String cancelText = 'Cancel',
  }) async {
    if (context == null) return false;

    final result = await ThemedDialogs.confirm(
      context!,
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      barrierDismissible: false,
    );

    return result;
  }

  // Removed tabbed main navigation

  /// Navigate to chat
  static Future<void> navigateToChat({String? conversationId}) {
    return navigateTo(
      Routes.chat,
      arguments: {'conversationId': conversationId},
      replace: true,
    );
  }

  /// Navigate to login
  static Future<void> navigateToLogin() {
    return navigateTo(Routes.login, clearStack: true);
  }

  /// Navigate to settings
  static Future<void> navigateToSettings() {
    return navigateTo(Routes.settings);
  }

  /// Navigate to profile
  static Future<void> navigateToProfile() {
    return navigateTo(Routes.profile);
  }

  /// Navigate to server connection
  static Future<void> navigateToServerConnection() {
    return navigateTo(Routes.serverConnection);
  }

  /// Navigate to search
  static Future<void> navigateToSearch() {
    return navigateTo(Routes.search);
  }

  /// Navigate to chats list
  static Future<void> navigateToChatsList() {
    return navigateTo(Routes.chatsList);
  }

  /// Clear navigation stack (useful for logout)
  static void clearNavigationStack() {
    _navigationStack.clear();
    _currentRoute = null;
  }

  /// Set current route (useful for initial app state)
  static void setCurrentRoute(String routeName) {
    _currentRoute = routeName;
    if (!_navigationStack.contains(routeName)) {
      _navigationStack.add(routeName);
    }
  }

  /// Generate routes
  static Route<dynamic>? generateRoute(RouteSettings settings) {
    Widget page;

    switch (settings.name) {
      // Removed tabbed main navigation

      case Routes.chat:
        page = const ChatPage();
        break;

      case Routes.login:
        page = const ConnectAndSignInPage();
        break;

      case Routes.settings:
        page = const SearchableSettingsPage();
        break;

      case Routes.profile:
        page = const ProfilePage();
        break;

      case Routes.serverConnection:
        page = const ConnectAndSignInPage();
        break;

      case Routes.search:
        page = const ConversationSearchPage();
        break;

      case Routes.files:
        page = const FilesPage();
        break;

      case Routes.chatsList:
        page = const ChatsListPage();
        break;

      // Removed navigation drawer route

      default:
        page = Scaffold(
          body: Center(child: Text('Route not found: ${settings.name}')),
        );
    }

    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}

/// Route names
class Routes {
  static const String chat = '/chat';
  static const String login = '/login';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String serverConnection = '/server-connection';
  static const String search = '/search';
  static const String files = '/files';
  static const String chatsList = '/chats-list';
}
