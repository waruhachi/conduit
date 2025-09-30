import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/l10n/app_localizations.dart';

/// Configuration for GptMarkdown styling
class ConduitMarkdownStyleConfig {
  final TextStyle textStyle;

  const ConduitMarkdownStyleConfig({required this.textStyle});
}

class ConduitMarkdownConfig {
  static ConduitMarkdownStyleConfig getStyleConfig({
    required BuildContext context,
  }) {
    final theme = context.conduitTheme;

    return ConduitMarkdownStyleConfig(
      textStyle: AppTypography.chatMessageStyle.copyWith(
        color: theme.textPrimary,
        height: 1.45,
      ),
    );
  }

  /// Legacy method for base64 image support (if needed elsewhere)
  static Widget buildBase64Image(
    String dataUrl,
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    try {
      // Extract base64 part from data URL
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex == -1) {
        throw Exception('Invalid data URL format');
      }

      final base64String = dataUrl.substring(commaIndex + 1);
      final imageBytes = base64.decode(base64String);

      return Container(
        margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 100,
                decoration: BoxDecoration(
                  color: theme.surfaceBackground.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppBorderRadius.md),
                  border: Border.all(
                    color: theme.error.withValues(alpha: 0.3),
                    width: BorderWidth.thin,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: theme.error, size: 32),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      AppLocalizations.of(context)!.invalidImageFormat,
                      style: TextStyle(color: theme.error, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: theme.surfaceBackground.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context)!.invalidImageFormat,
            style: TextStyle(color: theme.error, fontSize: 12),
          ),
        ),
      );
    }
  }

  /// Build a cached network image widget
  static Widget buildNetworkImage(
    String url,
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    return CachedNetworkImage(
      imageUrl: url,
      placeholder: (context, url) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.surfaceBackground.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: theme.loadingIndicator,
            strokeWidth: 2,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        height: 100,
        decoration: BoxDecoration(
          color: theme.surfaceBackground.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
          border: Border.all(
            color: theme.error.withValues(alpha: 0.3),
            width: BorderWidth.thin,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, color: theme.error, size: 32),
            const SizedBox(height: Spacing.xs),
            Text(
              AppLocalizations.of(context)!.failedToLoadImage(''),
              style: TextStyle(color: theme.error, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom wrapper for code blocks with copy functionality
class CodeBlockWrapper extends StatelessWidget {
  final Widget child;
  final String code;
  final String? language;
  final ConduitThemeExtension theme;

  const CodeBlockWrapper({
    super.key,
    required this.child,
    required this.code,
    this.language,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: theme.surfaceBackground.withValues(alpha: 0.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppBorderRadius.sm),
              onTap: () {
                // Copy code to clipboard
                // Implementation depends on clipboard service
              },
              child: Container(
                padding: const EdgeInsets.all(Spacing.xs),
                decoration: BoxDecoration(
                  color: theme.surfaceBackground.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                ),
                child: Icon(
                  Icons.copy,
                  size: IconSize.sm,
                  color: theme.iconSecondary,
                ),
              ),
            ),
          ),
        ),
        if (language != null)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xxs,
              ),
              decoration: BoxDecoration(
                color: theme.surfaceBackground.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppBorderRadius.xs),
              ),
              child: Text(
                language!,
                style: AppTypography.captionStyle.copyWith(
                  color: theme.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
