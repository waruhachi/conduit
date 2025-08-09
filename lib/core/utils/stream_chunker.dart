import 'dart:async';
import 'dart:math';

/// Utility class to chunk large text streams into smaller pieces for smoother UI updates
class StreamChunker {
  /// Splits large text chunks into smaller pieces for more fluid streaming
  /// Similar to OpenWebUI's approach for better UX
  static Stream<String> chunkStream(
    Stream<String> inputStream, {
    bool enableChunking = true,
    int minChunkSize = 16, // increase to reduce UI thrash
    int maxChunkLength = 12, // larger chunks improve performance
    Duration delayBetweenChunks = const Duration(milliseconds: 8),
  }) async* {
    final random = Random();

    await for (final chunk in inputStream) {
      if (!enableChunking || chunk.length < minChunkSize) {
        // Small chunks pass through as-is
        yield chunk;
        continue;
      }

      // Split large chunks into smaller pieces
      String remaining = chunk;
      while (remaining.isNotEmpty) {
        // Random chunk size between 4 and maxChunkLength characters
        // But prefer to break at word boundaries when possible
        int chunkSize = min(
          max(4, random.nextInt(maxChunkLength) + 1),
          remaining.length,
        );

        // Try to find a word boundary (space) within the chunk size
        if (chunkSize < remaining.length) {
          final nextSpace = remaining.indexOf(' ', chunkSize);
          if (nextSpace != -1 && nextSpace <= chunkSize + 2) {
            // Include the space in the chunk for natural word breaks
            chunkSize = nextSpace + 1;
          }
        }

        final pieceToYield = remaining.substring(0, chunkSize);
        yield pieceToYield;
        remaining = remaining.substring(chunkSize);

        // Add small delay between chunks for fluid animation
        // Skip delay for last piece to avoid unnecessary wait
        if (remaining.isNotEmpty && delayBetweenChunks.inMicroseconds > 0) {
          await Future.delayed(delayBetweenChunks);
        }
      }
    }
  }

  /// Alternative method that chunks by words instead of characters
  static Stream<String> chunkByWords(
    Stream<String> inputStream, {
    bool enableChunking = true,
    int wordsPerChunk = 1,
    Duration delayBetweenWords = const Duration(milliseconds: 50),
  }) async* {
    if (!enableChunking) {
      yield* inputStream;
      return;
    }

    String buffer = '';

    await for (final chunk in inputStream) {
      buffer += chunk;

      // Split by spaces and yield word by word
      final words = buffer.split(' ');

      // Keep the last "word" in buffer as it might be incomplete
      if (words.length > 1) {
        buffer = words.last;
        final completeWords = words.sublist(0, words.length - 1);

        for (int i = 0; i < completeWords.length; i++) {
          final word = completeWords[i];
          // Add space back except for the first word if buffer was empty
          final wordWithSpace =
              (i < completeWords.length - 1 || buffer.isNotEmpty)
              ? '$word '
              : word;

          yield wordWithSpace;

          // Add delay between words for smooth streaming effect
          if (i < completeWords.length - 1 &&
              delayBetweenWords.inMicroseconds > 0) {
            await Future.delayed(delayBetweenWords);
          }
        }
      }
    }

    // Yield any remaining buffer content
    if (buffer.isNotEmpty) {
      yield buffer;
    }
  }
}
