import 'package:flutter/foundation.dart';

/// Handles field name transformations between API and client formats
/// Converts between snake_case (API) and camelCase (client)
class FieldMapper {
  static final FieldMapper _instance = FieldMapper._internal();
  factory FieldMapper() => _instance;
  FieldMapper._internal();

  // Cache for converted field names to improve performance
  final Map<String, String> _toCamelCaseCache = {};
  final Map<String, String> _toSnakeCaseCache = {};

  // Special field mappings that don't follow standard conversion rules
  static const Map<String, String> _specialApiToClient = {
    'created_at': 'createdAt',
    'updated_at': 'updatedAt',
    'user_id': 'userId',
    'chat_id': 'chatId',
    'message_id': 'messageId',
    'session_id': 'sessionId',
    'folder_id': 'folderId',
    'share_id': 'shareId',
    'model_id': 'modelId',
    'tool_id': 'toolId',
    'function_id': 'functionId',
    'file_id': 'fileId',
    'knowledge_base_id': 'knowledgeBaseId',
    'channel_id': 'channelId',
    'note_id': 'noteId',
    'prompt_id': 'promptId',
    'memory_id': 'memoryId',
    'is_private': 'isPrivate',
    'is_enabled': 'isEnabled',
    'is_active': 'isActive',
    'is_archived': 'isArchived',
    'is_pinned': 'isPinned',
    'api_key': 'apiKey',
    'access_token': 'accessToken',
    'refresh_token': 'refreshToken',
    'content_type': 'contentType',
    'file_size': 'fileSize',
    'file_type': 'fileType',
    'mime_type': 'mimeType',
    // OpenWebUI chat message fields - keep in camelCase
    'parentId': 'parentId',
    'childrenIds': 'childrenIds',
    'currentId': 'currentId',
    'modelName': 'modelName',
    'modelIdx': 'modelIdx',
  };

  static const Map<String, String> _specialClientToApi = {
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
    'userId': 'user_id',
    'chatId': 'chat_id',
    'messageId': 'message_id',
    'sessionId': 'session_id',
    'folderId': 'folder_id',
    'shareId': 'share_id',
    'modelId': 'model_id',
    'toolId': 'tool_id',
    'functionId': 'function_id',
    'fileId': 'file_id',
    'knowledgeBaseId': 'knowledge_base_id',
    'channelId': 'channel_id',
    'noteId': 'note_id',
    'promptId': 'prompt_id',
    'memoryId': 'memory_id',
    'isPrivate': 'is_private',
    'isEnabled': 'is_enabled',
    'isActive': 'is_active',
    'isArchived': 'is_archived',
    'isPinned': 'is_pinned',
    'apiKey': 'api_key',
    'accessToken': 'access_token',
    'refreshToken': 'refresh_token',
    'contentType': 'content_type',
    'fileSize': 'file_size',
    'fileType': 'file_type',
    'mimeType': 'mime_type',
    // OpenWebUI chat message fields - keep in camelCase
    'parentId': 'parentId',
    'childrenIds': 'childrenIds',
    'currentId': 'currentId',
    'modelName': 'modelName',
    'modelIdx': 'modelIdx',
  };

  /// Transform data from client format (camelCase) to API format (snake_case)
  dynamic toApiFormat(dynamic data) {
    if (data == null) return null;

    if (data is Map<String, dynamic>) {
      return _transformMap(data, _toSnakeCase);
    } else if (data is List) {
      return data.map((item) => toApiFormat(item)).toList();
    } else {
      return data;
    }
  }

  /// Transform data from API format (snake_case) to client format (camelCase)
  dynamic fromApiFormat(dynamic data) {
    if (data == null) return null;

    if (data is Map<String, dynamic>) {
      return _transformMap(data, _toCamelCase);
    } else if (data is List) {
      return data.map((item) => fromApiFormat(item)).toList();
    } else {
      return data;
    }
  }

  /// Transform a map using the provided key transformation function
  Map<String, dynamic> _transformMap(
    Map<String, dynamic> map,
    String Function(String) keyTransform,
  ) {
    final transformed = <String, dynamic>{};

    for (final entry in map.entries) {
      final transformedKey = keyTransform(entry.key);
      dynamic transformedValue = entry.value;

      // Recursively transform nested objects and arrays
      if (transformedValue is Map<String, dynamic>) {
        transformedValue = _transformMap(transformedValue, keyTransform);
      } else if (transformedValue is List) {
        transformedValue = transformedValue.map((item) {
          if (item is Map<String, dynamic>) {
            return _transformMap(item, keyTransform);
          }
          return item;
        }).toList();
      }

      transformed[transformedKey] = transformedValue;
    }

    return transformed;
  }

  /// Convert snake_case to camelCase
  String _toCamelCase(String snakeCase) {
    // Check cache first
    if (_toCamelCaseCache.containsKey(snakeCase)) {
      return _toCamelCaseCache[snakeCase]!;
    }

    // Check special mappings
    if (_specialApiToClient.containsKey(snakeCase)) {
      final result = _specialApiToClient[snakeCase]!;
      _toCamelCaseCache[snakeCase] = result;
      return result;
    }

    // Standard conversion
    if (!snakeCase.contains('_')) {
      _toCamelCaseCache[snakeCase] = snakeCase;
      return snakeCase;
    }

    final words = snakeCase.split('_');
    final result =
        words.first + words.skip(1).map((word) => _capitalize(word)).join('');

    _toCamelCaseCache[snakeCase] = result;
    return result;
  }

  /// Convert camelCase to snake_case
  String _toSnakeCase(String camelCase) {
    // Check cache first
    if (_toSnakeCaseCache.containsKey(camelCase)) {
      return _toSnakeCaseCache[camelCase]!;
    }

    // Check special mappings
    if (_specialClientToApi.containsKey(camelCase)) {
      final result = _specialClientToApi[camelCase]!;
      _toSnakeCaseCache[camelCase] = result;
      return result;
    }

    // Standard conversion
    final result = camelCase.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );

    _toSnakeCaseCache[camelCase] = result;
    return result;
  }

  /// Capitalize first letter of a word
  String _capitalize(String word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }

  /// Convert a single field name from snake_case to camelCase
  String fieldToCamelCase(String snakeCase) {
    return _toCamelCase(snakeCase);
  }

  /// Convert a single field name from camelCase to snake_case
  String fieldToSnakeCase(String camelCase) {
    return _toSnakeCase(camelCase);
  }

  /// Get all cached transformations for debugging
  Map<String, dynamic> getCacheInfo() {
    return {
      'toCamelCacheSize': _toCamelCaseCache.length,
      'toSnakeCacheSize': _toSnakeCaseCache.length,
      'specialMappingsCount': _specialApiToClient.length,
    };
  }

  /// Clear transformation caches
  void clearCache() {
    _toCamelCaseCache.clear();
    _toSnakeCaseCache.clear();
    debugPrint('FieldMapper: Cleared transformation caches');
  }

  /// Add custom field mapping
  void addCustomMapping(String apiField, String clientField) {
    _specialApiToClient[apiField] = clientField;
    _specialClientToApi[clientField] = apiField;

    // Clear relevant cache entries
    _toCamelCaseCache.remove(apiField);
    _toSnakeCaseCache.remove(clientField);

    debugPrint('FieldMapper: Added custom mapping: $apiField <-> $clientField');
  }

  /// Validate that field transformations are reversible
  bool validateTransformations() {
    final errors = <String>[];

    // Test special mappings
    for (final entry in _specialApiToClient.entries) {
      final apiField = entry.key;
      final clientField = entry.value;

      // Test API -> Client -> API
      final backToApi = _toSnakeCase(clientField);
      if (backToApi != apiField) {
        errors.add(
          '$apiField -> $clientField -> $backToApi (should be $apiField)',
        );
      }

      // Test Client -> API -> Client
      final backToClient = _toCamelCase(apiField);
      if (backToClient != clientField) {
        errors.add(
          '$clientField -> $apiField -> $backToClient (should be $clientField)',
        );
      }
    }

    if (errors.isNotEmpty) {
      debugPrint('FieldMapper: Transformation validation errors:');
      for (final error in errors) {
        debugPrint('  $error');
      }
      return false;
    }

    debugPrint('FieldMapper: All transformations validated successfully');
    return true;
  }
}
