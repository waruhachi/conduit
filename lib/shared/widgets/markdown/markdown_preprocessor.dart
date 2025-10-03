/// Utility helpers for normalising markdown content before handing it to
/// [GptMarkdown]. The goal is to keep streaming responsive while smoothing
/// out troublesome edge-cases (e.g. nested fences inside lists).
class ConduitMarkdownPreprocessor {
  const ConduitMarkdownPreprocessor._();

  /// Normalises common fence and hard-break issues produced by LLMs.
  static String normalize(String input) {
    if (input.isEmpty) {
      return input;
    }

    var output = input.replaceAll('\r\n', '\n');

    // Move fenced code blocks that start on the same line as a list item onto
    // their own line so the parser does not treat them as list text.
    final bulletFence = RegExp(
      r'^(\s*(?:[*+-]|\d+\.)\s+)```([^\s`]*)\s*$',
      multiLine: true,
    );
    output = output.replaceAllMapped(
      bulletFence,
      (match) => '${match[1]}\n```${match[2]}',
    );

    // Dedent opening fences to avoid partial code-block detection when the
    // model indents fences by accident.
    final dedentOpen = RegExp(r'^[ \t]+```([^\n`]*)\s*$', multiLine: true);
    output = output.replaceAllMapped(dedentOpen, (match) => '```${match[1]}');

    // Dedent closing fences for the same reason as the opening fences.
    final dedentClose = RegExp(r'^[ \t]+```\s*$', multiLine: true);
    output = output.replaceAllMapped(dedentClose, (_) => '```');

    // Ensure closing fences stand alone. Prevents situations like `}\n```foo`
    // from keeping trailing braces inside the code block.
    final inlineClosing = RegExp(r'([^\r\n`])```(?=\s*(?:\r?\n|$))');
    output = output.replaceAllMapped(
      inlineClosing,
      (match) => '${match[1]}\n```',
    );

    // Insert a blank line when a "label: value" line is followed by a
    // horizontal rule so it is not treated as a Setext heading underline.
    final labelThenDash = RegExp(
      r'^(\*\*[^\n*]+\*\*.*)\n(\s*-{3,}\s*$)',
      multiLine: true,
    );
    output = output.replaceAllMapped(
      labelThenDash,
      (match) => '${match[1]}\n\n${match[2]}',
    );

    // Allow headings like "## 1. Summary" without triggering ordered-list
    // parsing by inserting a zero-width joiner after the numeric marker.
    final atxEnum = RegExp(
      r'^(\s{0,3}#{1,6}\s+\d+)\.(\s*)(\S)',
      multiLine: true,
    );
    output = output.replaceAllMapped(
      atxEnum,
      (match) => '${match[1]}.\u200C${match[2]}${match[3]}',
    );

    // Auto-close an unmatched opening fence at EOF to avoid the entire tail
    // of the message rendering as code.
    final fenceAtBol = RegExp(r'^\s*```', multiLine: true);
    final fenceCount = fenceAtBol.allMatches(output).length;
    if (fenceCount.isOdd) {
      if (!output.endsWith('\n')) {
        output += '\n';
      }
      output += '```';
    }

    // Convert Markdown links followed by two trailing spaces into separate
    // paragraphs so that consecutive links do not collapse into a single
    // paragraph at render time.
    final linkWithTrailingSpaces = RegExp(r'\[[^\]]+\]\([^\)]+\)\s{2,}$');
    final lines = output.split('\n');
    if (lines.length > 1) {
      final buffer = StringBuffer();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        buffer.write(line);
        if (i < lines.length - 1) {
          buffer.write('\n');
        }
        if (linkWithTrailingSpaces.hasMatch(line)) {
          buffer.write('\n');
        }
      }
      output = buffer.toString();
    }

    return output;
  }

  /// Inserts zero-width break characters into long inline code spans so they
  /// remain readable and do not overflow narrow layouts.
  static String softenInlineCode(String input, {int chunkSize = 24}) {
    if (input.length <= chunkSize) {
      return input;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      buffer.write(input[i]);
      if ((i + 1) % chunkSize == 0) {
        buffer.write('\u200B');
      }
    }
    return buffer.toString();
  }
}
