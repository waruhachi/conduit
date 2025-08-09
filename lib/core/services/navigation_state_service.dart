import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Navigation state data model
class NavigationState {
  final String routeName;
  final Map<String, dynamic> arguments;
  final DateTime timestamp;
  final String? conversationId;
  final int? tabIndex;

  NavigationState({
    required this.routeName,
    this.arguments = const {},
    DateTime? timestamp,
    this.conversationId,
    this.tabIndex,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'routeName': routeName,
    'arguments': arguments,
    'timestamp': timestamp.toIso8601String(),
    'conversationId': conversationId,
    'tabIndex': tabIndex,
  };

  factory NavigationState.fromJson(Map<String, dynamic> json) {
    return NavigationState(
      routeName: json['routeName'] ?? '/',
      arguments: json['arguments'] ?? {},
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      conversationId: json['conversationId'],
      tabIndex: json['tabIndex'],
    );
  }
}

/// Service to manage navigation state preservation and restoration
class NavigationStateService {
  static final NavigationStateService _instance =
      NavigationStateService._internal();
  factory NavigationStateService() => _instance;
  NavigationStateService._internal();

  static const String _navigationStackKey = 'navigation_stack';
  static const String _currentStateKey = 'current_navigation_state';
  static const String _deepLinkStateKey = 'deep_link_state';

  SharedPreferences? _prefs;
  final List<NavigationState> _navigationStack = [];
  NavigationState? _currentState;
  final ValueNotifier<NavigationState?> _stateNotifier = ValueNotifier(null);

  /// Initialize the service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadNavigationState();
      debugPrint('DEBUG: NavigationStateService initialized');
    } catch (e) {
      debugPrint('ERROR: Failed to initialize NavigationStateService: $e');
    }
  }

  /// Get current navigation state as a ValueNotifier for listening to changes
  ValueNotifier<NavigationState?> get stateNotifier => _stateNotifier;

  /// Get current navigation state
  NavigationState? get currentState => _currentState;

  /// Get navigation stack
  List<NavigationState> get navigationStack =>
      List.unmodifiable(_navigationStack);

  /// Push a new navigation state
  Future<void> pushState({
    required String routeName,
    Map<String, dynamic> arguments = const {},
    String? conversationId,
    int? tabIndex,
  }) async {
    try {
      final state = NavigationState(
        routeName: routeName,
        arguments: arguments,
        conversationId: conversationId,
        tabIndex: tabIndex,
      );

      _navigationStack.add(state);
      _currentState = state;
      _stateNotifier.value = state;

      await _saveNavigationState();

      debugPrint('DEBUG: Navigation state pushed - ${state.routeName}');
    } catch (e) {
      debugPrint('ERROR: Failed to push navigation state: $e');
    }
  }

  /// Pop the last navigation state
  Future<NavigationState?> popState() async {
    try {
      if (_navigationStack.isEmpty) return null;

      final poppedState = _navigationStack.removeLast();
      _currentState = _navigationStack.isNotEmpty
          ? _navigationStack.last
          : null;
      _stateNotifier.value = _currentState;

      await _saveNavigationState();

      debugPrint('DEBUG: Navigation state popped - ${poppedState.routeName}');
      return poppedState;
    } catch (e) {
      debugPrint('ERROR: Failed to pop navigation state: $e');
      return null;
    }
  }

  /// Update current state with new information
  Future<void> updateCurrentState({
    String? conversationId,
    int? tabIndex,
    Map<String, dynamic>? additionalArgs,
  }) async {
    try {
      if (_currentState == null) return;

      final updatedArgs = <String, dynamic>{
        ..._currentState!.arguments,
        if (additionalArgs != null) ...additionalArgs,
      };

      final updatedState = NavigationState(
        routeName: _currentState!.routeName,
        arguments: updatedArgs,
        conversationId: conversationId ?? _currentState!.conversationId,
        tabIndex: tabIndex ?? _currentState!.tabIndex,
        timestamp: _currentState!.timestamp,
      );

      // Update both current state and last item in stack
      _currentState = updatedState;
      if (_navigationStack.isNotEmpty) {
        _navigationStack[_navigationStack.length - 1] = updatedState;
      }

      _stateNotifier.value = updatedState;
      await _saveNavigationState();

      debugPrint('DEBUG: Navigation state updated');
    } catch (e) {
      debugPrint('ERROR: Failed to update navigation state: $e');
    }
  }

  /// Clear navigation stack but preserve current state
  Future<void> clearStack() async {
    try {
      _navigationStack.clear();
      if (_currentState != null) {
        _navigationStack.add(_currentState!);
      }
      await _saveNavigationState();
      debugPrint('DEBUG: Navigation stack cleared');
    } catch (e) {
      debugPrint('ERROR: Failed to clear navigation stack: $e');
    }
  }

  /// Replace entire navigation stack
  Future<void> replaceStack(List<NavigationState> newStack) async {
    try {
      _navigationStack.clear();
      _navigationStack.addAll(newStack);
      _currentState = newStack.isNotEmpty ? newStack.last : null;
      _stateNotifier.value = _currentState;

      await _saveNavigationState();
      debugPrint(
        'DEBUG: Navigation stack replaced with ${newStack.length} states',
      );
    } catch (e) {
      debugPrint('ERROR: Failed to replace navigation stack: $e');
    }
  }

  /// Handle deep link by preserving navigation context
  Future<void> handleDeepLink({
    required String routeName,
    Map<String, dynamic> arguments = const {},
    String? conversationId,
    bool preserveStack = true,
  }) async {
    try {
      // Save deep link state for restoration
      final deepLinkState = NavigationState(
        routeName: routeName,
        arguments: arguments,
        conversationId: conversationId,
      );

      await _saveDeepLinkState(deepLinkState);

      if (preserveStack) {
        // Add to existing stack instead of replacing
        await pushState(
          routeName: routeName,
          arguments: arguments,
          conversationId: conversationId,
        );
      } else {
        // Replace stack with deep link
        await replaceStack([deepLinkState]);
      }

      debugPrint('DEBUG: Deep link handled - $routeName');
    } catch (e) {
      debugPrint('ERROR: Failed to handle deep link: $e');
    }
  }

  /// Get the conversation context from current navigation state
  String? getConversationContext() {
    return _currentState?.conversationId;
  }

  /// Get the current tab index
  int? getCurrentTabIndex() {
    return _currentState?.tabIndex;
  }

  /// Generate breadcrumb navigation based on current stack
  List<NavigationBreadcrumb> generateBreadcrumbs() {
    final breadcrumbs = <NavigationBreadcrumb>[];

    for (int i = 0; i < _navigationStack.length; i++) {
      final state = _navigationStack[i];
      final isLast = i == _navigationStack.length - 1;

      breadcrumbs.add(
        NavigationBreadcrumb(
          title: _getRouteTitle(state.routeName),
          routeName: state.routeName,
          arguments: state.arguments,
          isActive: isLast,
          canNavigateBack: i > 0,
        ),
      );
    }

    return breadcrumbs;
  }

  /// Check if we can navigate back
  bool canGoBack() {
    return _navigationStack.length > 1;
  }

  /// Get previous state without popping
  NavigationState? getPreviousState() {
    if (_navigationStack.length < 2) return null;
    return _navigationStack[_navigationStack.length - 2];
  }

  /// Restore navigation state on app startup
  Future<void> restoreNavigationState(NavigatorState navigator) async {
    try {
      await _loadNavigationState();

      if (_currentState != null) {
        // Attempt to restore to the last known state
        debugPrint(
          'DEBUG: Restoring navigation to ${_currentState!.routeName}',
        );

        // This would need to be implemented based on your routing setup
        // navigator.pushNamedAndRemoveUntil(
        //   _currentState!.routeName,
        //   (route) => false,
        //   arguments: _currentState!.arguments,
        // );
      }
    } catch (e) {
      debugPrint('ERROR: Failed to restore navigation state: $e');
    }
  }

  /// Clear all navigation state
  Future<void> clearAll() async {
    try {
      _navigationStack.clear();
      _currentState = null;
      _stateNotifier.value = null;

      await _prefs?.remove(_navigationStackKey);
      await _prefs?.remove(_currentStateKey);
      await _prefs?.remove(_deepLinkStateKey);

      debugPrint('DEBUG: All navigation state cleared');
    } catch (e) {
      debugPrint('ERROR: Failed to clear navigation state: $e');
    }
  }

  /// Save navigation state to persistent storage
  Future<void> _saveNavigationState() async {
    if (_prefs == null) return;

    try {
      // Save navigation stack
      final stackJson = _navigationStack
          .map((state) => state.toJson())
          .toList();
      await _prefs!.setString(_navigationStackKey, jsonEncode(stackJson));

      // Save current state
      if (_currentState != null) {
        await _prefs!.setString(
          _currentStateKey,
          jsonEncode(_currentState!.toJson()),
        );
      } else {
        await _prefs!.remove(_currentStateKey);
      }
    } catch (e) {
      debugPrint('ERROR: Failed to save navigation state: $e');
    }
  }

  /// Load navigation state from persistent storage
  Future<void> _loadNavigationState() async {
    if (_prefs == null) return;

    try {
      // Load navigation stack
      final stackJsonString = _prefs!.getString(_navigationStackKey);
      if (stackJsonString != null) {
        final stackJson = jsonDecode(stackJsonString) as List;
        _navigationStack.clear();
        for (final stateJson in stackJson) {
          if (stateJson is Map<String, dynamic>) {
            _navigationStack.add(NavigationState.fromJson(stateJson));
          }
        }
      }

      // Load current state
      final currentStateJsonString = _prefs!.getString(_currentStateKey);
      if (currentStateJsonString != null) {
        final currentStateJson =
            jsonDecode(currentStateJsonString) as Map<String, dynamic>;
        _currentState = NavigationState.fromJson(currentStateJson);
        _stateNotifier.value = _currentState;
      }

      debugPrint(
        'DEBUG: Navigation state loaded - ${_navigationStack.length} states',
      );
    } catch (e) {
      debugPrint('ERROR: Failed to load navigation state: $e');
      // Clear corrupted state
      await clearAll();
    }
  }

  /// Save deep link state for restoration
  Future<void> _saveDeepLinkState(NavigationState state) async {
    if (_prefs == null) return;

    try {
      await _prefs!.setString(_deepLinkStateKey, jsonEncode(state.toJson()));
    } catch (e) {
      debugPrint('ERROR: Failed to save deep link state: $e');
    }
  }

  /// Get user-friendly title for route name
  String _getRouteTitle(String routeName) {
    switch (routeName) {
      case '/':
      case '/home':
        return 'Home';
      case '/chat':
        return 'Chat';
      case '/settings':
        return 'Settings';
      case '/profile':
        return 'Profile';
      case '/conversations':
        return 'Conversations';
      default:
        // Convert route name to title case
        return routeName
            .replaceAll('/', '')
            .split('_')
            .map(
              (word) => word.isNotEmpty
                  ? '${word[0].toUpperCase()}${word.substring(1)}'
                  : '',
            )
            .join(' ');
    }
  }
}

/// Breadcrumb navigation item
class NavigationBreadcrumb {
  final String title;
  final String routeName;
  final Map<String, dynamic> arguments;
  final bool isActive;
  final bool canNavigateBack;

  NavigationBreadcrumb({
    required this.title,
    required this.routeName,
    required this.arguments,
    required this.isActive,
    required this.canNavigateBack,
  });
}
