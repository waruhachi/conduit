import 'package:flutter/material.dart';
// ThemedDialogs handles theming; no direct use of extensions here
import '../../features/auth/views/connect_signin_page.dart';
import '../../features/chat/views/chat_page.dart';
import '../../features/files/views/files_page.dart';
import '../../features/profile/views/profile_page.dart';
import '../../shared/widgets/themed_dialogs.dart';

/// Service for handling navigation throughout the app
class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static NavigatorState? get navigator => navigatorKey.currentState;
  static BuildContext? get context => navigatorKey.currentContext;

  static final List<String> _navigationStack = [];
  static String? _currentRoute;

  /// Get current route
  static String? get currentRoute => _currentRoute;

  /// Get navigation stack
  static List<String> get navigationStack =>
      List.unmodifiable(_navigationStack);

  /// Navigate to a specific route
  static Future<void> navigateTo(String routeName) async {
    if (_currentRoute != routeName) {
      _navigationStack.add(routeName);
      _currentRoute = routeName;
    }
  }

  /// Navigate back with optional result
  static void goBack<T>([T? result]) {
    if (navigator?.canPop() == true) {
      if (_navigationStack.isNotEmpty) {
        _navigationStack.removeLast();
      }
      _currentRoute = _navigationStack.isNotEmpty
          ? _navigationStack.last
          : null;
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

  /// Navigate to chat
  static Future<void> navigateToChat() {
    return navigateTo(Routes.chat);
  }

  /// Navigate to login
  static Future<void> navigateToLogin() {
    return navigateTo(Routes.login);
  }

  /// Navigate to profile
  static Future<void> navigateToProfile() {
    return navigateTo(Routes.profile);
  }

  /// Navigate to server connection
  static Future<void> navigateToServerConnection() {
    return navigateTo(Routes.serverConnection);
  }

  // Chats list is now provided as a left drawer in ChatPage

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

      case Routes.profile:
        page = const ProfilePage();
        break;

      case Routes.serverConnection:
        page = const ConnectAndSignInPage();
        break;

      case Routes.files:
        page = const FilesPage();
        break;

      // chats list route removed (replaced by drawer)

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
  static const String profile = '/profile';
  static const String serverConnection = '/server-connection';
  static const String files = '/files';
}
