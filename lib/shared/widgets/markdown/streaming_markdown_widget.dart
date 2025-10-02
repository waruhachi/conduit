import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'markdown_config.dart';

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
    final markdownTheme = ConduitMarkdownConfig.resolve(context);

    if (content.trim().isEmpty) {
      return isStreaming ? const SizedBox.shrink() : const SizedBox.shrink();
    }

    final textScaler = MediaQuery.maybeOf(context)?.textScaler;

    return GptMarkdownTheme(
      gptThemeData: markdownTheme.themeData,
      child: GptMarkdown(
        content,
        style: markdownTheme.textStyle,
        followLinkColor: markdownTheme.followLinkColor,
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        onLinkTap: onTapLink,
        codeBuilder: markdownTheme.codeBuilder,
        imageBuilder: markdownTheme.imageBuilder,
      ),
    );
  }
}

extension StreamingMarkdownExtension on String {
  Widget toMarkdown({required BuildContext context, bool isStreaming = false}) {
    return StreamingMarkdownWidget(content: this, isStreaming: isStreaming);
  }
}

class MarkdownWithLoading extends StatelessWidget {
  const MarkdownWithLoading({super.key, this.content, required this.isLoading});

  final String? content;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final value = content ?? '';
    if (isLoading && value.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamingMarkdownWidget(content: value, isStreaming: isLoading);
  }
}
