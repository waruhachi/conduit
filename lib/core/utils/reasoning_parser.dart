/// Utility class for parsing and extracting reasoning/thinking content from messages.
class ReasoningParser {
  /// Default tag pairs to detect raw reasoning blocks when providers don't emit `<details>`.
  /// This mirrors Open WebUI defaults: `<think>...</think>`, `<reasoning>...</reasoning>`.
  static const List<List<String>> defaultReasoningTagPairs = <List<String>>[
    ['<think>', '</think>'],
    ['<reasoning>', '</reasoning>'],
  ];

  /// Parses a message and extracts reasoning content
  /// Supports:
  /// - `<details type="reasoning" ...>` blocks (server-emitted)
  /// - Raw tag pairs like `<think>...</think>` or `<reasoning>...</reasoning>`
  /// - Optional custom tag pair override
  static ReasoningContent? parseReasoningContent(
    String content, {
    List<String>? customTagPair,
    bool detectDefaultTags = true,
  }) {
    if (content.isEmpty) return null;

    // 1) Prefer server-emitted `<details type="reasoning">` blocks
    final detailsRegex = RegExp(
      r'<details\s+type="reasoning"(?:\s+done="(true|false)")?(?:\s+duration="(\d+)")?[^>]*>\s*<summary>([^<]*)<\/summary>\s*([\s\S]*?)<\/details>',
      multiLine: true,
      dotAll: true,
    );
    final detailsMatch = detailsRegex.firstMatch(content);
    if (detailsMatch != null) {
      final isDone = (detailsMatch.group(1) ?? 'true') == 'true';
      final duration = int.tryParse(detailsMatch.group(2) ?? '0') ?? 0;
      final summary = (detailsMatch.group(3) ?? '').trim();
      final reasoning = (detailsMatch.group(4) ?? '').trim();

      final mainContent = content.replaceAll(detailsRegex, '').trim();

      return ReasoningContent(
        reasoning: reasoning,
        summary: summary,
        duration: duration,
        isDone: isDone,
        mainContent: mainContent,
        originalContent: content,
      );
    }

    // 2) Handle partially streamed `<details>` (opening present, no closing yet)
    final openingIdx = content.indexOf('<details type="reasoning"');
    if (openingIdx >= 0 && !content.contains('</details>')) {
      final after = content.substring(openingIdx);
      // Try to extract optional summary
      final summaryMatch = RegExp(r'<summary>([^<]*)<\/summary>').firstMatch(after);
      final summary = (summaryMatch?.group(1) ?? '').trim();
      final reasoning = after
          .replaceAll(RegExp(r'^<details[^>]*>'), '')
          .replaceAll(RegExp(r'<summary>[\s\S]*?<\/summary>'), '')
          .trim();

      final mainContent = content.substring(0, openingIdx).trim();

      return ReasoningContent(
        reasoning: reasoning,
        summary: summary,
        duration: 0,
        isDone: false,
        mainContent: mainContent,
        originalContent: content,
      );
    }

    // 3) Otherwise, look for raw tag pairs
    List<List<String>> tagPairs = [];
    if (customTagPair != null && customTagPair.length == 2) {
      tagPairs.add(customTagPair);
    }
    if (detectDefaultTags) {
      tagPairs.addAll(defaultReasoningTagPairs);
    }

    for (final pair in tagPairs) {
      final start = RegExp.escape(pair[0]);
      final end = RegExp.escape(pair[1]);
      final tagRegex = RegExp('($start)([\s\S]*?)($end)', multiLine: true, dotAll: true);
      final match = tagRegex.firstMatch(content);
      if (match != null) {
        final reasoning = (match.group(2) ?? '').trim();
        final mainContent = content.replaceAll(tagRegex, '').trim();

        return ReasoningContent(
          reasoning: reasoning,
          summary: '', // no summary available for raw tags
          duration: 0,
          isDone: true,
          mainContent: mainContent,
          originalContent: content,
        );
      }
    }

    return null;
  }

  /// Checks if a message contains reasoning content
  static bool hasReasoningContent(String content) {
    if (content.contains('<details type="reasoning"')) return true;
    for (final pair in defaultReasoningTagPairs) {
      if (content.contains(pair[0]) && content.contains(pair[1])) return true;
    }
    return false;
  }

  /// Formats the duration for display
  static String formatDuration(int seconds) {
    if (seconds == 0) return 'instant';
    if (seconds < 60) return '$seconds second${seconds == 1 ? '' : 's'}';

    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;

    if (remainingSeconds == 0) {
      return '$minutes minute${minutes == 1 ? '' : 's'}';
    }

    return '$minutes min ${remainingSeconds}s';
  }
}

/// Model class for reasoning content
class ReasoningContent {
  final String reasoning;
  final String summary;
  final int duration;
  final bool isDone;
  final String mainContent;
  final String originalContent;

  const ReasoningContent({
    required this.reasoning,
    required this.summary,
    required this.duration,
    required this.isDone,
    required this.mainContent,
    required this.originalContent,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReasoningContent &&
          runtimeType == other.runtimeType &&
          reasoning == other.reasoning &&
          summary == other.summary &&
          duration == other.duration &&
          isDone == other.isDone &&
          mainContent == other.mainContent &&
          originalContent == other.originalContent;

  @override
  int get hashCode =>
      reasoning.hashCode ^
      summary.hashCode ^
      duration.hashCode ^
      isDone.hashCode ^
      mainContent.hashCode ^
      originalContent.hashCode;

  String get formattedDuration => ReasoningParser.formatDuration(duration);

  /// Gets the cleaned reasoning text (removes leading '>')
  String get cleanedReasoning {
    // Split by lines and clean each line
    return reasoning
        .split('\n')
        .map((line) => line.startsWith('>') ? line.substring(1).trim() : line)
        .join('\n')
        .trim();
  }
}
