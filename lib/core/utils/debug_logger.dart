import 'package:flutter/foundation.dart';

/// Centralized debug logging utility for the entire app
class DebugLogger {
  static const bool _enabled = kDebugMode;

  /// Log debug information
  static void log(String message) {
    if (_enabled) {
      debugPrint('DEBUG: $message');
    }
  }

  /// Log errors
  static void error(String message, [Object? error]) {
    if (_enabled) {
      if (error != null) {
        debugPrint('ERROR: $message: $error');
      } else {
        debugPrint('ERROR: $message');
      }
    }
  }

  /// Log warnings
  static void warning(String message) {
    if (_enabled) {
      debugPrint('WARN: $message');
    }
  }

  /// Log success/info messages
  static void info(String message) {
    if (_enabled) {
      debugPrint('INFO: $message');
    }
  }

  /// Log navigation events
  static void navigation(String message) {
    if (_enabled) {
      debugPrint('NAV: $message');
    }
  }

  /// Log authentication events
  static void auth(String message) {
    if (_enabled) {
      debugPrint('AUTH: $message');
    }
  }

  /// Log streaming events
  static void stream(String message) {
    if (_enabled) {
      debugPrint('STREAM: $message');
    }
  }

  /// Log validation events
  static void validation(String message) {
    if (_enabled) {
      debugPrint('VALIDATION: $message');
    }
  }

  /// Log storage events
  static void storage(String message) {
    if (_enabled) {
      debugPrint('STORAGE: $message');
    }
  }
}
