import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:conduit/shared/theme/app_theme.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';

class ConduitMarkdownConfig {
  static MarkdownConfig getConfig({
    required bool isDark,
    required BuildContext context,
    bool isStreaming = false,
  }) {
    final theme = context.conduitTheme;

    return (isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig).copy(
      configs: [
        // Code block config
        PreConfig(
          theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
          decoration: BoxDecoration(
            color: theme.surfaceBackground.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.7),
              width: BorderWidth.thin,
            ),
          ),
          padding: const EdgeInsets.all(Spacing.md),
          textStyle: AppTypography.chatCodeStyle,
          wrapper: (child, text, language) => CodeBlockWrapper(
            code: text,
            language: language,
            theme: theme,
            child: child,
          ),
        ),

        // Link config
        LinkConfig(
          style: TextStyle(
            color: AppTheme.brandPrimary,
            decoration: TextDecoration.underline,
          ),
          onTap: (url) async {
            if (await canLaunchUrlString(url)) {
              launchUrlString(url, mode: LaunchMode.inAppWebView);
            }
          },
        ),

        // Image config - optimized for mobile
        ImgConfig(
          builder: (url, attributes) => CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) => Container(
              height: 200,
              color: theme.surfaceBackground,
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.brandPrimary,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: 100,
              color: theme.surfaceBackground,
              child: Center(
                child: Icon(
                  Icons.broken_image,
                  color: theme.iconSecondary,
                ),
              ),
            ),
          ),
        ),

        // Table config - mobile responsive
        TableConfig(
          wrapper: (table) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        ),

        // Paragraph config
        PConfig(
          textStyle: AppTypography.chatMessageStyle.copyWith(
            color: theme.textPrimary,
          ),
        ),

        // Headers
        H1Config(
          style: AppTypography.headlineLargeStyle.copyWith(
            color: theme.textPrimary,
          ),
        ),
        H2Config(
          style: AppTypography.headlineMediumStyle.copyWith(
            color: theme.textPrimary,
          ),
        ),
        H3Config(
          style: AppTypography.headlineSmallStyle.copyWith(
            color: theme.textPrimary,
          ),
        ),

        // Blockquote
        BlockquoteConfig(),

        // Code inline
        CodeConfig(
          style: AppTypography.chatCodeStyle.copyWith(
            color: theme.textPrimary,
            backgroundColor: theme.surfaceBackground.withValues(alpha: 0.1),
          ),
        ),
      ],
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
            color: Colors.transparent,
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