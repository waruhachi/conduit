import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:conduit/l10n/app_localizations.dart';

import '../../theme/theme_extensions.dart';

class ConduitMarkdownTheme {
  const ConduitMarkdownTheme({
    required this.styleSheet,
    required this.builders,
    required this.imageBuilder,
    this.inlineSyntaxes = const <md.InlineSyntax>[],
  });

  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final MarkdownImageBuilder imageBuilder;
  final List<md.InlineSyntax> inlineSyntaxes;
}

class ConduitMarkdownConfig {
  static ConduitMarkdownTheme resolve(BuildContext context) {
    final theme = context.conduitTheme;
    final materialTheme = Theme.of(context);

    final baseSheet = MarkdownStyleSheet.fromTheme(materialTheme);
    final bodyStyle = AppTypography.bodyMediumStyle.copyWith(
      color: theme.textPrimary,
      height: 1.45,
    );

    final codeColor = theme.code?.color ?? theme.textSecondary;

    final styleSheet = baseSheet.copyWith(
      p: bodyStyle,
      h1: AppTypography.headlineLargeStyle.copyWith(color: theme.textPrimary),
      h2: AppTypography.headlineMediumStyle.copyWith(color: theme.textPrimary),
      h3: AppTypography.headlineSmallStyle.copyWith(color: theme.textPrimary),
      strong: bodyStyle.copyWith(fontWeight: FontWeight.w600),
      em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
      blockquote: bodyStyle.copyWith(
        color: theme.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      code: AppTypography.codeStyle.copyWith(color: codeColor),
      listBullet: bodyStyle,
      tableBody: bodyStyle,
      tableHead: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    );

    final builders = <String, MarkdownElementBuilder>{
      'codeblock': _ConduitCodeBlockBuilder(theme),
    };

    return ConduitMarkdownTheme(
      styleSheet: styleSheet,
      builders: builders,
      imageBuilder: (uri, title, alt) {
        final scheme = uri.scheme;

        if (scheme == 'data') {
          return buildBase64Image(uri.toString(), context, theme);
        }

        if (scheme.isEmpty || scheme == 'http' || scheme == 'https') {
          return buildNetworkImage(uri.toString(), context, theme);
        }

        return const SizedBox.shrink();
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

class _ConduitCodeBlockBuilder extends MarkdownElementBuilder {
  _ConduitCodeBlockBuilder(this.theme);

  final ConduitThemeExtension theme;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final rawText = element.textContent;
    final classAttribute = element.attributes['class'];
    String? language;
    if (classAttribute != null && classAttribute.startsWith('language-')) {
      language = classAttribute.substring('language-'.length);
    }

    final textStyle = (preferredStyle ?? AppTypography.codeStyle).copyWith(
      color: theme.code?.color ?? theme.textSecondary,
    );

    final container = Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: theme.surfaceBackground.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        border: Border.all(
          color: theme.cardBorder.withValues(alpha: 0.2),
          width: BorderWidth.micro,
        ),
      ),
      child: SelectableText(rawText, style: textStyle),
    );

    return CodeBlockWrapper(
      code: rawText,
      language: language,
      theme: theme,
      child: container,
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
