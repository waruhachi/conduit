/// Utility class for parsing and extracting reasoning/thinking content from messages
class ReasoningParser {
  /// Parses a message and extracts reasoning content
  static ReasoningContent? parseReasoningContent(String content) {
    if (content.isEmpty) return null;

    // Check if content contains reasoning
    if (!content.contains('<details type="reasoning"')) {
      return null;
    }

    // Match the <details> tag with type="reasoning"
    final reasoningRegex = RegExp(
      r'<details\s+type="reasoning"\s+done="(true|false)"\s+duration="(\d+)"[^>]*>\s*<summary>([^<]*)</summary>\s*(.*?)\s*</details>',
      multiLine: true,
      dotAll: true,
    );

    final match = reasoningRegex.firstMatch(content);
    if (match == null) {
      return null;
    }

    final isDone = match.group(1) == 'true';
    final duration = int.tryParse(match.group(2) ?? '0') ?? 0;
    final summary = match.group(3)?.trim() ?? '';
    final reasoning = match.group(4)?.trim() ?? '';

    // Remove the reasoning section from the main content
    final mainContent = content.replaceAll(reasoningRegex, '').trim();

    return ReasoningContent(
      reasoning: reasoning,
      summary: summary,
      duration: duration,
      isDone: isDone,
      mainContent: mainContent,
      originalContent: content,
    );
  }

  /// Checks if a message contains reasoning content
  static bool hasReasoningContent(String content) {
    return content.contains('<details type="reasoning"');
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
