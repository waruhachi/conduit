import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';

/// Centralized helper for building themed dialogs consistently
class ThemedDialogs {
  ThemedDialogs._();

  /// Build a base themed AlertDialog
  static AlertDialog buildBase({
    required BuildContext context,
    required String title,
    Widget? content,
    List<Widget>? actions,
  }) {
    return AlertDialog(
      backgroundColor: context.conduitTheme.surfaceBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.dialog),
      ),
      title: Text(
        title,
        style: TextStyle(color: context.conduitTheme.textPrimary),
      ),
      content: content,
      actions: actions,
    );
  }

  /// Show a simple confirmation dialog with Cancel/Confirm actions
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
    bool barrierDismissible = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => buildBase(
        context: ctx,
        title: title,
        content: Text(
          message,
          style: TextStyle(color: ctx.conduitTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              cancelText,
              style: TextStyle(color: ctx.conduitTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: isDestructive
                  ? ctx.conduitTheme.error
                  : ctx.conduitTheme.buttonPrimary,
            ),
            child: Text(
              confirmText,
              style: TextStyle(
                color: isDestructive
                    ? ctx.conduitTheme.error
                    : ctx.conduitTheme.buttonPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// Show a generic themed dialog
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => buildBase(
        context: ctx,
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }
}
