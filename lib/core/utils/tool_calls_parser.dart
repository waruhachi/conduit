import 'dart:convert';

/// Parsed representation of one tool call emitted as a `<details type="tool_calls" ...>` block
class ToolCallEntry {
  final String id;
  final String name;
  final bool done;
  final dynamic arguments; // decoded JSON when possible, else String
  final dynamic result; // decoded JSON when possible, else String
  final List<dynamic>? files; // decoded JSON array when present

  const ToolCallEntry({
    required this.id,
    required this.name,
    required this.done,
    this.arguments,
    this.result,
    this.files,
  });
}

/// Container for extracted tool calls and the remaining main content
class ToolCallsContent {
  final List<ToolCallEntry> toolCalls;
  final String mainContent;
  final String originalContent;

  const ToolCallsContent({
    required this.toolCalls,
    required this.mainContent,
    required this.originalContent,
  });
}

/// Utility to parse <details type="tool_calls"> blocks from content
class ToolCallsParser {
  /// Represents a mixed stream of text and tool-call entries in original order
  /// as they appeared in the content.
  static List<ToolCallsSegment>? segments(String content) {
    if (content.isEmpty || !content.contains('<details')) return null;

    final detailsRegex = RegExp(
      r'<details\b([^>]*)>\s*<summary>[^<]*<\/summary>\s*<\/details>',
      multiLine: true,
      dotAll: true,
    );

    final matches = detailsRegex.allMatches(content).toList();
    if (matches.isEmpty) return null;

    final segs = <ToolCallsSegment>[];
    int lastEnd = 0;

    for (final m in matches) {
      // Text before this block
      if (m.start > lastEnd) {
        segs.add(ToolCallsSegment.text(content.substring(lastEnd, m.start)));
      }

      final fullMatch = m.group(0) ?? '';
      final attrs = m.group(1) ?? '';

      if (attrs.contains('type="tool_calls"')) {
        String? _attr(String name) {
          final r = RegExp('$name="([^"]*)"');
          final mm = r.firstMatch(attrs);
          return mm != null ? _unescapeHtml(mm.group(1) ?? '') : null;
        }

        final id = _attr('id') ?? '';
        final name = _attr('name') ?? 'tool';
        final done = (_attr('done') == 'true');
        final args = _tryDecodeJson(_attr('arguments'));
        final result = _tryDecodeJson(_attr('result'));
        final files = _tryDecodeJson(_attr('files'));

        final entry = ToolCallEntry(
          id: id.isNotEmpty ? id : '${name}_${m.start}',
          name: name,
          done: done,
          arguments: args,
          result: result,
          files: (files is List) ? files : null,
        );
        segs.add(ToolCallsSegment.entry(entry));
      } else {
        // Not a tool_calls block: keep it as text
        segs.add(ToolCallsSegment.text(fullMatch));
      }

      lastEnd = m.end;
    }

    // Tail text
    if (lastEnd < content.length) {
      segs.add(ToolCallsSegment.text(content.substring(lastEnd)));
    }

    return segs;
  }
  /// Extracts tool call blocks and returns the remaining content with those blocks removed.
  static ToolCallsContent? parse(String content) {
    if (content.isEmpty || !content.contains('<details')) return null;

    final detailsRegex = RegExp(
      r'<details\b([^>]*)>\s*<summary>[^<]*<\/summary>\s*<\/details>',
      multiLine: true,
      dotAll: true,
    );

    final matches = detailsRegex.allMatches(content).toList();
    if (matches.isEmpty) return null;

    final calls = <ToolCallEntry>[];
    for (final m in matches) {
      final attrs = m.group(1) ?? '';
      if (!attrs.contains('type="tool_calls"')) continue;

      String? _attr(String name) {
        final r = RegExp('$name="([^"]*)"');
        final mm = r.firstMatch(attrs);
        return mm != null ? _unescapeHtml(mm.group(1) ?? '') : null;
      }

      final id = _attr('id') ?? '';
      final name = _attr('name') ?? 'tool';
      final done = (_attr('done') == 'true');
      final args = _tryDecodeJson(_attr('arguments'));
      final result = _tryDecodeJson(_attr('result'));
      final files = _tryDecodeJson(_attr('files'));

      calls.add(
        ToolCallEntry(
          id: id.isNotEmpty ? id : '${name}_${m.start}',
          name: name,
          done: done,
          arguments: args,
          result: result,
          files: (files is List) ? files : null,
        ),
      );
    }

    if (calls.isEmpty) return null;

    final main = content.replaceAll(detailsRegex, '').trim();
    return ToolCallsContent(toolCalls: calls, mainContent: main, originalContent: content);
  }

  /// Legacy helper that summarizes tool blocks to text (kept for fallback)
  static String summarize(String content) {
    final parsed = parse(content);
    if (parsed == null) return content;
    final buf = StringBuffer();
    for (final c in parsed.toolCalls) {
      buf.writeln(c.done ? 'Tool Executed: ${c.name}' : 'Running tool: ${c.name}…');
      final args = _prettyMaybe(c.arguments, max: 400);
      final res = _prettyMaybe(c.result, max: 800);
      if (args.isNotEmpty) {
        buf.writeln('\nArguments:\n```json');
        buf.writeln(args);
        buf.writeln('```');
      }
      if (res.isNotEmpty) {
        buf.writeln('\nResult:\n```json');
        buf.writeln(res);
        buf.writeln('```');
      }
      buf.writeln();
    }
    buf.writeln(parsed.mainContent);
    return buf.toString().trim();
  }

  static dynamic _tryDecodeJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      dynamic decoded = json.decode(raw);
      if (decoded is String) {
        final s = decoded.trim();
        if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'))) {
          try {
            decoded = json.decode(s);
          } catch (_) {}
        }
      }
      return decoded;
    } catch (_) {
      return raw;
    }
  }

  static String _prettyMaybe(dynamic value, {int max = 600}) {
    if (value == null) return '';
    try {
      final pretty = const JsonEncoder.withIndent('  ').convert(value);
      return pretty.length > max ? pretty.substring(0, max) + '\n…' : pretty;
    } catch (_) {
      final raw = value.toString();
      return raw.length > max ? raw.substring(0, max) + '…' : raw;
    }
  }

  static String _unescapeHtml(String input) {
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}

/// Ordered piece of content: either plain text or a tool-call entry
class ToolCallsSegment {
  final String? text;
  final ToolCallEntry? entry;

  const ToolCallsSegment._({this.text, this.entry});
  factory ToolCallsSegment.text(String text) => ToolCallsSegment._(text: text);
  factory ToolCallsSegment.entry(ToolCallEntry entry) =>
      ToolCallsSegment._(entry: entry);

  bool get isToolCall => entry != null;
}
