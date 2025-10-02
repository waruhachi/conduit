import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'markdown_config.dart';

typedef MarkdownLinkTapCallback = void Function(String url, String title);

class StreamingMarkdownWidget extends StatefulWidget {
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
  State<StreamingMarkdownWidget> createState() =>
      _StreamingMarkdownWidgetState();
}

class _StreamingMarkdownWidgetState extends State<StreamingMarkdownWidget> {
  late final ValueNotifier<String> _contentNotifier;
  late String _currentContent;
  Timer? _debounce;
  String? _pendingContent;

  @override
  void initState() {
    super.initState();
    _currentContent = widget.content;
    _contentNotifier = ValueNotifier(widget.content);
  }

  @override
  void didUpdateWidget(covariant StreamingMarkdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content == _currentContent) {
      return;
    }

    // Coalesce rapid streaming updates so we only rebuild markdown a few times.
    _pendingContent = widget.content;
    _debounce ??= Timer(const Duration(milliseconds: 45), () {
      if (!mounted) {
        return;
      }
      final next = _pendingContent ?? widget.content;
      _currentContent = next;
      _contentNotifier.value = next;
      _pendingContent = null;
      _debounce = null;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _contentNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _contentNotifier,
      builder: (context, value, _) {
        return _StreamingMarkdownContent(
          content: value,
          isStreaming: widget.isStreaming,
          onTapLink: widget.onTapLink,
        );
      },
    );
  }
}

class _StreamingMarkdownContent extends StatelessWidget {
  const _StreamingMarkdownContent({
    required this.content,
    required this.isStreaming,
    required this.onTapLink,
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
        components: markdownTheme.blockComponents,
        inlineComponents: markdownTheme.inlineComponents,
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
