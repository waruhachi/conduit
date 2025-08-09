import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/chat_message.dart';

/// Advanced conversation search service with multiple search strategies
class ConversationSearchService {
  static const int maxResults = 50;
  static const int contextLines = 2; // Lines before/after match for context

  /// Search through conversations with various criteria
  Future<ConversationSearchResults> searchConversations({
    required List<Conversation> conversations,
    required String query,
    ConversationSearchOptions options = const ConversationSearchOptions(),
  }) async {
    if (query.trim().isEmpty) {
      return ConversationSearchResults.empty();
    }

    final normalizedQuery = query.toLowerCase().trim();
    final results = <ConversationSearchMatch>[];

    // Search through each conversation
    for (final conversation in conversations) {
      final matches = await _searchInConversation(
        conversation: conversation,
        query: normalizedQuery,
        options: options,
      );
      results.addAll(matches);
    }

    // Sort results by relevance and date
    results.sort((a, b) {
      // First by relevance score (higher is better)
      final relevanceCompare = b.relevanceScore.compareTo(a.relevanceScore);
      if (relevanceCompare != 0) return relevanceCompare;

      // Then by date (newer first)
      return b.timestamp.compareTo(a.timestamp);
    });

    // Limit results
    final limitedResults = results.take(maxResults).toList();

    return ConversationSearchResults(
      query: query,
      results: limitedResults,
      totalMatches: results.length,
      searchDuration: DateTime.now().difference(DateTime.now()),
    );
  }

  /// Search within a single conversation
  Future<List<ConversationSearchMatch>> _searchInConversation({
    required Conversation conversation,
    required String query,
    required ConversationSearchOptions options,
  }) async {
    final matches = <ConversationSearchMatch>[];

    // Search in conversation title
    if (options.searchTitles && _containsQuery(conversation.title, query)) {
      matches.add(
        ConversationSearchMatch(
          conversationId: conversation.id,
          conversationTitle: conversation.title,
          matchType: SearchMatchType.title,
          snippet: conversation.title,
          highlightedSnippet: _highlightQuery(conversation.title, query),
          relevanceScore: _calculateTitleRelevance(conversation.title, query),
          timestamp: conversation.updatedAt,
        ),
      );
    }

    // Search in messages
    if (options.searchMessages) {
      final messageMatches = await _searchInMessages(
        conversation: conversation,
        query: query,
        options: options,
      );
      matches.addAll(messageMatches);
    }

    // Search in tags
    if (options.searchTags) {
      for (final tag in conversation.tags) {
        if (_containsQuery(tag, query)) {
          matches.add(
            ConversationSearchMatch(
              conversationId: conversation.id,
              conversationTitle: conversation.title,
              matchType: SearchMatchType.tag,
              snippet: tag,
              highlightedSnippet: _highlightQuery(tag, query),
              relevanceScore: _calculateTagRelevance(tag, query),
              timestamp: conversation.updatedAt,
              additionalInfo: {'tag': tag},
            ),
          );
        }
      }
    }

    return matches;
  }

  /// Search within messages of a conversation
  Future<List<ConversationSearchMatch>> _searchInMessages({
    required Conversation conversation,
    required String query,
    required ConversationSearchOptions options,
  }) async {
    final matches = <ConversationSearchMatch>[];

    for (int i = 0; i < conversation.messages.length; i++) {
      final message = conversation.messages[i];

      // Skip system messages if not enabled
      if (!options.includeSystemMessages && message.role == 'system') {
        continue;
      }

      // Filter by role if specified
      if (options.roleFilter != null && message.role != options.roleFilter) {
        continue;
      }

      // Check if message contains query
      if (_containsQuery(message.content, query)) {
        final snippet = _extractSnippet(message.content, query);
        final contextMessages = _getContextMessages(conversation.messages, i);

        matches.add(
          ConversationSearchMatch(
            conversationId: conversation.id,
            conversationTitle: conversation.title,
            messageId: message.id,
            matchType: SearchMatchType.message,
            snippet: snippet,
            highlightedSnippet: _highlightQuery(snippet, query),
            relevanceScore: _calculateMessageRelevance(message.content, query),
            timestamp: message.timestamp,
            messageRole: message.role,
            messageIndex: i,
            contextMessages: contextMessages,
          ),
        );
      }
    }

    return matches;
  }

  /// Extract relevant snippet around the query match
  String _extractSnippet(String content, String query) {
    const maxSnippetLength = 200;
    final queryIndex = content.toLowerCase().indexOf(query);

    if (queryIndex == -1) {
      return content.substring(0, maxSnippetLength.clamp(0, content.length));
    }

    // Calculate snippet bounds
    final start = (queryIndex - 50).clamp(0, content.length);
    final end = (queryIndex + query.length + 50).clamp(0, content.length);

    String snippet = content.substring(start, end);

    // Add ellipsis if needed
    if (start > 0) snippet = '...$snippet';
    if (end < content.length) snippet = '$snippet...';

    return snippet;
  }

  /// Get context messages around a matched message
  List<ChatMessage> _getContextMessages(List<ChatMessage> messages, int index) {
    final start = (index - contextLines).clamp(0, messages.length);
    final end = (index + contextLines + 1).clamp(0, messages.length);
    return messages.sublist(start, end);
  }

  /// Highlight query matches in text
  String _highlightQuery(String text, String query) {
    if (query.isEmpty) return text;

    final regex = RegExp(RegExp.escape(query), caseSensitive: false);
    return text.replaceAllMapped(regex, (match) {
      return '<mark>${match.group(0)}</mark>';
    });
  }

  /// Check if text contains the query
  bool _containsQuery(String text, String query) {
    return text.toLowerCase().contains(query);
  }

  /// Calculate relevance score for title matches
  double _calculateTitleRelevance(String title, String query) {
    final titleLower = title.toLowerCase();
    final queryLower = query.toLowerCase();

    // Exact match gets highest score
    if (titleLower == queryLower) return 100.0;

    // Title starts with query gets high score
    if (titleLower.startsWith(queryLower)) return 90.0;

    // Title contains query as whole word gets medium score
    if (RegExp(
      r'\b' + RegExp.escape(queryLower) + r'\b',
    ).hasMatch(titleLower)) {
      return 70.0;
    }

    // Partial match gets lower score
    return 50.0;
  }

  /// Calculate relevance score for message matches
  double _calculateMessageRelevance(String content, String query) {
    final contentLower = content.toLowerCase();
    final queryLower = query.toLowerCase();

    // Count occurrences
    final occurrences = queryLower.allMatches(contentLower).length;

    // Base score for containing the query
    double score = 30.0;

    // Bonus for multiple occurrences
    score += (occurrences - 1) * 10.0;

    // Bonus for whole word matches
    if (RegExp(
      r'\b' + RegExp.escape(queryLower) + r'\b',
    ).hasMatch(contentLower)) {
      score += 20.0;
    }

    // Penalty for very long messages (relevance dilution)
    if (content.length > 1000) {
      score *= 0.8;
    }

    return score.clamp(0.0, 100.0);
  }

  /// Calculate relevance score for tag matches
  double _calculateTagRelevance(String tag, String query) {
    final tagLower = tag.toLowerCase();
    final queryLower = query.toLowerCase();

    // Exact match gets highest score
    if (tagLower == queryLower) return 80.0;

    // Tag starts with query gets high score
    if (tagLower.startsWith(queryLower)) return 70.0;

    // Partial match gets medium score
    return 50.0;
  }
}

/// Search options for conversation search
@immutable
class ConversationSearchOptions {
  final bool searchTitles;
  final bool searchMessages;
  final bool searchTags;
  final bool includeSystemMessages;
  final String? roleFilter; // 'user', 'assistant', 'system'
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool caseSensitive;

  const ConversationSearchOptions({
    this.searchTitles = true,
    this.searchMessages = true,
    this.searchTags = true,
    this.includeSystemMessages = false,
    this.roleFilter,
    this.dateFrom,
    this.dateTo,
    this.caseSensitive = false,
  });

  ConversationSearchOptions copyWith({
    bool? searchTitles,
    bool? searchMessages,
    bool? searchTags,
    bool? includeSystemMessages,
    String? roleFilter,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? caseSensitive,
  }) {
    return ConversationSearchOptions(
      searchTitles: searchTitles ?? this.searchTitles,
      searchMessages: searchMessages ?? this.searchMessages,
      searchTags: searchTags ?? this.searchTags,
      includeSystemMessages:
          includeSystemMessages ?? this.includeSystemMessages,
      roleFilter: roleFilter ?? this.roleFilter,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
      caseSensitive: caseSensitive ?? this.caseSensitive,
    );
  }
}

/// Search results container
@immutable
class ConversationSearchResults {
  final String query;
  final List<ConversationSearchMatch> results;
  final int totalMatches;
  final Duration searchDuration;

  const ConversationSearchResults({
    required this.query,
    required this.results,
    required this.totalMatches,
    required this.searchDuration,
  });

  factory ConversationSearchResults.empty() {
    return ConversationSearchResults(
      query: '',
      results: const [],
      totalMatches: 0,
      searchDuration: Duration.zero,
    );
  }

  bool get isEmpty => results.isEmpty;
  bool get isNotEmpty => results.isNotEmpty;
  int get length => results.length;
}

/// Individual search match
@immutable
class ConversationSearchMatch {
  final String conversationId;
  final String conversationTitle;
  final String? messageId;
  final SearchMatchType matchType;
  final String snippet;
  final String highlightedSnippet;
  final double relevanceScore;
  final DateTime timestamp;
  final String? messageRole;
  final int? messageIndex;
  final List<ChatMessage>? contextMessages;
  final Map<String, dynamic>? additionalInfo;

  const ConversationSearchMatch({
    required this.conversationId,
    required this.conversationTitle,
    this.messageId,
    required this.matchType,
    required this.snippet,
    required this.highlightedSnippet,
    required this.relevanceScore,
    required this.timestamp,
    this.messageRole,
    this.messageIndex,
    this.contextMessages,
    this.additionalInfo,
  });
}

/// Types of search matches
enum SearchMatchType { title, message, tag }

/// Provider for conversation search service
final conversationSearchServiceProvider = Provider<ConversationSearchService>((
  ref,
) {
  return ConversationSearchService();
});

/// Provider for search results
final conversationSearchResultsProvider =
    StateProvider<ConversationSearchResults?>((ref) {
      return null;
    });

/// Provider for search options
final searchOptionsProvider = StateProvider<ConversationSearchOptions>((ref) {
  return const ConversationSearchOptions();
});
