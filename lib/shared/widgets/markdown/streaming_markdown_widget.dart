import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'markdown_config.dart';

class StreamingMarkdownWidget extends StatelessWidget {
  const StreamingMarkdownWidget({
    super.key,
    required this.content,
    required this.isStreaming,
    this.onTapLink,
  });

  final String content;
  final bool isStreaming;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final markdownTheme = ConduitMarkdownConfig.resolve(context);

    if (content.trim().isEmpty) {
      return isStreaming ? const SizedBox.shrink() : const SizedBox.shrink();
    }

    return MarkdownBody(
      data: content,
      styleSheet: markdownTheme.styleSheet,
      softLineBreak: true,
      selectable: true,
      builders: markdownTheme.builders,
      inlineSyntaxes: markdownTheme.inlineSyntaxes,
      imageBuilder: markdownTheme.imageBuilder,
      onTapLink: onTapLink,
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
