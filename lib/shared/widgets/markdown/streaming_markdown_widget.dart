import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:conduit/shared/theme/theme_extensions.dart';
import 'package:conduit/shared/widgets/markdown/markdown_config.dart';

class StreamingMarkdownWidget extends StatefulWidget {
  final Stream<String>? contentStream;
  final String? staticContent;
  final bool isStreaming;

  const StreamingMarkdownWidget({
    super.key,
    this.contentStream,
    this.staticContent,
    required this.isStreaming,
  });

  @override
  State<StreamingMarkdownWidget> createState() =>
      _StreamingMarkdownWidgetState();
}

class _StreamingMarkdownWidgetState extends State<StreamingMarkdownWidget> {
  final _buffer = StringBuffer();
  Timer? _debounceTimer;
  String _renderedContent = '';
  StreamSubscription<String>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.contentStream != null) {
      _streamSubscription = widget.contentStream!.listen(_handleChunk);
    } else if (widget.staticContent != null) {
      _renderedContent = widget.staticContent!;
    }
  }

  void _handleChunk(String chunk) {
    _buffer.write(chunk);

    // Debounce rendering for performance
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() {
          _renderedContent = _fixIncompleteMarkdown(_buffer.toString());
        });
      }
    });
  }

  String _fixIncompleteMarkdown(String content) {
    // Auto-close unclosed code blocks for valid markdown during streaming
    final fenceCount = '```'.allMatches(content).length;
    if (fenceCount % 2 != 0) {
      content += '\n```';
    }

    // Fix incomplete bold/italic markers
    final boldCount = RegExp(r'\*\*').allMatches(content).length;
    if (boldCount % 2 != 0) {
      content += '**';
    }

    final italicCount = RegExp(r'(?<!\*)\*(?!\*)').allMatches(content).length;
    if (italicCount % 2 != 0) {
      content += '*';
    }

    // Fix incomplete link brackets
    final openBrackets = '['.allMatches(content).length;
    final closeBrackets = ']'.allMatches(content).length;
    if (openBrackets > closeBrackets) {
      content += ']' * (openBrackets - closeBrackets);
    }

    final openParens = '('.allMatches(content).length;
    final closeParens = ')'.allMatches(content).length;
    if (openParens > closeParens) {
      content += ')' * (openParens - closeParens);
    }

    return content;
  }

  @override
  void didUpdateWidget(StreamingMarkdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle stream changes
    if (widget.contentStream != oldWidget.contentStream) {
      _streamSubscription?.cancel();
      if (widget.contentStream != null) {
        _streamSubscription = widget.contentStream!.listen(_handleChunk);
      }
    }

    // Handle static content changes
    if (widget.staticContent != oldWidget.staticContent) {
      setState(() {
        _renderedContent = widget.staticContent ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ConduitMarkdownConfig.getStyleConfig(context: context);
    final theme = Theme.of(context);
    final styleSheet = MarkdownStyleSheet.fromTheme(
      theme,
    ).copyWith(p: config.textStyle);
    final conduitTheme = context.conduitTheme;

    if (_renderedContent.isEmpty) {
      return const SizedBox.shrink();
    }

    // MarkdownBody handles both streaming and static content elegantly
    return MarkdownBody(
      data: _renderedContent,
      styleSheet: styleSheet,
      softLineBreak: true,
      selectable: true,
      imageBuilder: (uri, title, alt) {
        final scheme = uri.scheme;

        if (scheme == 'data') {
          return ConduitMarkdownConfig.buildBase64Image(
            uri.toString(),
            context,
            conduitTheme,
          );
        }

        if (scheme.isEmpty || scheme == 'http' || scheme == 'https') {
          return ConduitMarkdownConfig.buildNetworkImage(
            uri.toString(),
            context,
            conduitTheme,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _streamSubscription?.cancel();
    super.dispose();
  }
}

/// Extension to provide easy access to streaming markdown
extension StreamingMarkdownExtension on String {
  Widget toMarkdown({required BuildContext context, bool isStreaming = false}) {
    return StreamingMarkdownWidget(
      staticContent: this,
      isStreaming: isStreaming,
    );
  }
}

/// Helper widget for displaying markdown with loading state
class MarkdownWithLoading extends StatelessWidget {
  final String? content;
  final bool isLoading;

  const MarkdownWithLoading({super.key, this.content, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading && (content == null || content!.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamingMarkdownWidget(
      staticContent: content ?? '',
      isStreaming: isLoading,
    );
  }
}
