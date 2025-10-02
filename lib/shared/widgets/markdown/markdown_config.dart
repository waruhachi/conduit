import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart'
    show CodeBlockBuilder, ImageBuilder;
import 'package:gpt_markdown/gpt_markdown.dart';

import 'package:conduit/l10n/app_localizations.dart';

import '../../theme/theme_extensions.dart';

class ConduitMarkdownTheme {
  const ConduitMarkdownTheme({
    required this.textStyle,
    required this.themeData,
    required this.imageBuilder,
    required this.codeBuilder,
    this.followLinkColor = true,
  });

  final TextStyle textStyle;
  final GptMarkdownThemeData themeData;
  final ImageBuilder imageBuilder;
  final CodeBlockBuilder codeBuilder;
  final bool followLinkColor;
}

class ConduitMarkdownConfig {
  static ConduitMarkdownTheme resolve(BuildContext context) {
    final theme = context.conduitTheme;
    final materialTheme = Theme.of(context);

    final bodyStyle = AppTypography.bodyMediumStyle.copyWith(
      color: theme.textPrimary,
      height: 1.45,
    );

    final codeColor = theme.code?.color ?? theme.textSecondary;

    final markdownThemeData = GptMarkdownThemeData(
      brightness: materialTheme.brightness,
      h1: AppTypography.headlineLargeStyle.copyWith(color: theme.textPrimary),
      h2: AppTypography.headlineMediumStyle.copyWith(color: theme.textPrimary),
      h3: AppTypography.headlineSmallStyle.copyWith(color: theme.textPrimary),
      h4: AppTypography.bodyLargeStyle.copyWith(color: theme.textPrimary),
      h5: AppTypography.bodyMediumStyle.copyWith(
        color: theme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      h6: AppTypography.bodySmallStyle.copyWith(color: theme.textSecondary),
      hrLineColor: theme.dividerColor,
      highlightColor: theme.surfaceContainer.withValues(alpha: 0.4),
      linkColor: materialTheme.colorScheme.primary,
      linkHoverColor: materialTheme.colorScheme.primary.withValues(alpha: 0.8),
    );

    return ConduitMarkdownTheme(
      textStyle: bodyStyle,
      themeData: markdownThemeData,
      imageBuilder: (context, imageUrl) {
        final uri = Uri.tryParse(imageUrl);
        if (uri == null) {
          return _buildImageError(context, context.conduitTheme);
        }

        final scheme = uri.scheme;

        if (scheme == 'data') {
          return buildBase64Image(imageUrl, context, context.conduitTheme);
        }

        if (scheme.isEmpty || scheme == 'http' || scheme == 'https') {
          return buildNetworkImage(imageUrl, context, context.conduitTheme);
        }

        return const SizedBox.shrink();
      },
      codeBuilder: (context, name, code, closed) {
        final conduitTheme = context.conduitTheme;
        final textStyle = AppTypography.codeStyle.copyWith(
          color: conduitTheme.code?.color ?? codeColor,
        );

        final container = Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: conduitTheme.surfaceBackground.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            border: Border.all(
              color: conduitTheme.cardBorder.withValues(alpha: 0.2),
              width: BorderWidth.micro,
            ),
          ),
          child: SelectableText(code, style: textStyle),
        );

        final language = name.trim().isEmpty ? null : name.trim();

        return CodeBlockWrapper(
          code: code,
          language: language,
          theme: conduitTheme,
          child: container,
        );
      },
    );
  }

  static Widget buildBase64Image(
    String dataUrl,
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
    try {
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
              return _buildImageError(context, theme);
            },
          ),
        ),
      );
    } catch (e) {
      return _buildImageError(context, theme);
    }
  }

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
      errorWidget: (context, url, error) => _buildImageError(context, theme),
    );
  }

  static Widget _buildImageError(
    BuildContext context,
    ConduitThemeExtension theme,
  ) {
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
          Icon(Icons.broken_image_outlined, color: theme.error, size: 32),
          const SizedBox(height: Spacing.xs),
          Text(
            AppLocalizations.of(context)!.failedToLoadImage(''),
            style: TextStyle(color: theme.error, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class CodeBlockWrapper extends StatelessWidget {
  const CodeBlockWrapper({
    super.key,
    required this.child,
    required this.code,
    this.language,
    required this.theme,
  });

  final Widget child;
  final String code;
  final String? language;
  final ConduitThemeExtension theme;

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
                // Copy implementation provided by higher level clipboard service.
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
                style: AppTypography.bodySmallStyle.copyWith(
                  color: theme.textSecondary,
                  fontFamily: AppTypography.monospaceFontFamily,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
