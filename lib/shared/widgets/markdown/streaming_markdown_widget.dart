import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../theme/theme_extensions.dart';
import 'markdown_config.dart';
import 'markdown_preprocessor.dart';

typedef MarkdownLinkTapCallback = void Function(String url, String title);

class StreamingMarkdownWidget extends StatelessWidget {
  const StreamingMarkdownWidget({
    super.key,
    required this.content,
    required this.isStreaming,
    this.onTapLink,
  });

  final String content;
  final bool isStreaming;
  final MarkdownLinkTapCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final normalized = ConduitMarkdownPreprocessor.normalize(content);

    const featureFlags = MarkdownFeatureFlags(
      enableSyntaxHighlighting: true,
      enableMermaid: true,
    );

    final markdownTheme = ConduitMarkdownConfig.resolve(
      context,
      flags: featureFlags,
    );
    final textScaler = MediaQuery.maybeOf(context)?.textScaler;

    return GptMarkdownTheme(
      gptThemeData: markdownTheme.themeData,
      child: SelectionArea(
        child: GptMarkdown(
          normalized,
          style: markdownTheme.textStyle,
          followLinkColor: markdownTheme.followLinkColor,
          textDirection: Directionality.of(context),
          textScaler: textScaler,
          onLinkTap: onTapLink,
          codeBuilder: markdownTheme.codeBuilder,
          imageBuilder: markdownTheme.imageBuilder,
          useDollarSignsForLatex: true,
          highlightBuilder: (highlightContext, inline, baseStyle) {
            final softened = ConduitMarkdownPreprocessor.softenInlineCode(
              inline,
            );
            final theme = highlightContext.conduitTheme;
            final base = baseStyle;
            final fontSize = (base.fontSize ?? 13).clamp(11, 15).toDouble();
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.xs,
                vertical: Spacing.xxs,
              ),
              decoration: BoxDecoration(
                color: theme.surfaceBackground.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppBorderRadius.xs),
                border: Border.all(
                  color: theme.cardBorder.withValues(alpha: 0.2),
                  width: BorderWidth.micro,
                ),
              ),
              child: Text(
                softened,
                style: base.copyWith(
                  fontFamily: AppTypography.monospaceFontFamily,
                  fontSize: fontSize,
                  height: 1.35,
                  color: theme.code?.color ?? theme.textSecondary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

extension StreamingMarkdownExtension on String {
  Widget toMarkdown({
    required BuildContext context,
    bool isStreaming = false,
    MarkdownLinkTapCallback? onTapLink,
  }) {
    return StreamingMarkdownWidget(
      content: this,
      isStreaming: isStreaming,
      onTapLink: onTapLink,
    );
  }
}

class MarkdownWithLoading extends StatelessWidget {
  const MarkdownWithLoading({super.key, this.content, required this.isLoading});

  final String? content;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final value = content ?? '';
    if (isLoading && value.trim().isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamingMarkdownWidget(content: value, isStreaming: isLoading);
  }
}
