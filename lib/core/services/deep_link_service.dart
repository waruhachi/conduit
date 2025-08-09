import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/views/chat_page.dart';
import '../../features/files/views/files_page.dart';
import '../../features/profile/views/profile_page.dart';

/// Service for handling deep links and navigation routing
class DeepLinkService {
  /// Route to chat tab
  static void navigateToChat(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const ChatPage()),
      (route) => false,
    );
  }

  /// In single-screen mode, files/profile deep links route via navigator
  static void navigateToFiles(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FilesPage()),
    );
  }

  static void navigateToProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfilePage()),
    );
  }

  /// Parse route and determine target tab
  static String? parsePath(String route) {
    switch (route) {
      case '/chat':
      case '/main/chat':
        return '/chat';
      case '/files':
      case '/main/files':
        return '/files';
      case '/profile':
      case '/main/profile':
        return '/profile';
      default:
        return null;
    }
  }

  /// Handle deep link navigation
  static Widget handleDeepLink(String route) {
    final path = parsePath(route);
    switch (path) {
      case '/files':
        return const FilesPage();
      case '/profile':
        return const ProfilePage();
      case '/chat':
      default:
        return const ChatPage();
    }
  }
}

/// Provider for deep link navigation
final deepLinkProvider = Provider<DeepLinkService>((ref) => DeepLinkService());
