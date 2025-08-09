import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registry for OpenAPI schemas
/// Loads and provides access to request/response schemas for validation
class SchemaRegistry {
  static final SchemaRegistry _instance = SchemaRegistry._internal();
  factory SchemaRegistry() => _instance;
  SchemaRegistry._internal();

  Map<String, dynamic>? _openApiSpec;
  final Map<String, Map<String, dynamic>> _requestSchemaCache = {};
  final Map<String, Map<String, dynamic>> _responseSchemaCache = {};

  bool get isLoaded => _openApiSpec != null;

  /// Load schemas from OpenAPI specification
  Future<void> loadSchemas() async {
    try {
      debugPrint('SchemaRegistry: Loading OpenAPI specification...');

      // Try to load from assets first, then from file system as fallback
      String openApiContent;
      try {
        openApiContent = await rootBundle.loadString('assets/openapi.json');
      } catch (e) {
        debugPrint(
          'SchemaRegistry: Could not load from assets, trying file system...',
        );
        // Fallback - in a real app you might load from network or local file
        throw Exception('OpenAPI specification not found in assets');
      }

      _openApiSpec = jsonDecode(openApiContent) as Map<String, dynamic>;

      debugPrint(
        'SchemaRegistry: Successfully loaded OpenAPI spec with ${_getPaths().length} paths',
      );

      // Pre-process and cache commonly used schemas
      await _buildSchemaCache();
    } catch (e) {
      debugPrint('SchemaRegistry: Failed to load schemas: $e');
      rethrow;
    }
  }

  /// Get request schema for endpoint and method
  Map<String, dynamic>? getRequestSchema(String endpoint, String method) {
    if (!isLoaded) return null;

    final cacheKey = '${method.toUpperCase()}:$endpoint:request';
    if (_requestSchemaCache.containsKey(cacheKey)) {
      return _requestSchemaCache[cacheKey];
    }

    try {
      final pathItem = _findPathItem(endpoint);
      if (pathItem == null) return null;

      final operation = pathItem[method.toLowerCase()] as Map<String, dynamic>?;
      if (operation == null) return null;

      final requestBody = operation['requestBody'] as Map<String, dynamic>?;
      if (requestBody == null) return null;

      final content = requestBody['content'] as Map<String, dynamic>?;
      if (content == null) return null;

      // Try to find JSON content type
      final jsonContent =
          content['application/json'] as Map<String, dynamic>? ??
          content.values.first as Map<String, dynamic>?;

      if (jsonContent == null) return null;

      final schema = _resolveSchema(
        jsonContent['schema'] as Map<String, dynamic>?,
      );

      if (schema != null) {
        _requestSchemaCache[cacheKey] = schema;
      }

      return schema;
    } catch (e) {
      debugPrint(
        'SchemaRegistry: Error getting request schema for $method $endpoint: $e',
      );
      return null;
    }
  }

  /// Get response schema for endpoint, method, and status code
  Map<String, dynamic>? getResponseSchema(
    String endpoint,
    String method,
    int? statusCode,
  ) {
    if (!isLoaded) return null;

    final code = statusCode?.toString() ?? '200';
    final cacheKey = '${method.toUpperCase()}:$endpoint:response:$code';

    if (_responseSchemaCache.containsKey(cacheKey)) {
      return _responseSchemaCache[cacheKey];
    }

    try {
      final pathItem = _findPathItem(endpoint);
      if (pathItem == null) return null;

      final operation = pathItem[method.toLowerCase()] as Map<String, dynamic>?;
      if (operation == null) return null;

      final responses = operation['responses'] as Map<String, dynamic>?;
      if (responses == null) return null;

      // Try to find the specific status code, or fall back to 'default' or '200'
      final response =
          responses[code] as Map<String, dynamic>? ??
          responses['default'] as Map<String, dynamic>? ??
          responses['200'] as Map<String, dynamic>?;

      if (response == null) return null;

      final content = response['content'] as Map<String, dynamic>?;
      if (content == null) return null;

      // Try to find JSON content type
      final jsonContent =
          content['application/json'] as Map<String, dynamic>? ??
          content.values.first as Map<String, dynamic>?;

      if (jsonContent == null) return null;

      final schema = _resolveSchema(
        jsonContent['schema'] as Map<String, dynamic>?,
      );

      if (schema != null) {
        _responseSchemaCache[cacheKey] = schema;
      }

      return schema;
    } catch (e) {
      debugPrint(
        'SchemaRegistry: Error getting response schema for $method $endpoint ($code): $e',
      );
      return null;
    }
  }

  /// Find path item that matches the given endpoint
  Map<String, dynamic>? _findPathItem(String endpoint) {
    final paths = _getPaths();

    // Try exact match first
    if (paths.containsKey(endpoint)) {
      return paths[endpoint] as Map<String, dynamic>?;
    }

    // Try to find parameterized routes
    for (final pathPattern in paths.keys) {
      if (_matchesPathPattern(endpoint, pathPattern)) {
        return paths[pathPattern] as Map<String, dynamic>?;
      }
    }

    return null;
  }

  /// Check if endpoint matches a path pattern with parameters
  bool _matchesPathPattern(String endpoint, String pattern) {
    // Convert OpenAPI path parameters {id} to regex
    final regexPattern = pattern.replaceAllMapped(
      RegExp(r'\{([^}]+)\}'),
      (match) => r'([^/]+)',
    );

    final regex = RegExp('^$regexPattern\$');
    return regex.hasMatch(endpoint);
  }

  /// Get paths from OpenAPI spec
  Map<String, dynamic> _getPaths() {
    return _openApiSpec?['paths'] as Map<String, dynamic>? ?? {};
  }

  /// Resolve schema references ($ref)
  Map<String, dynamic>? _resolveSchema(Map<String, dynamic>? schema) {
    if (schema == null) return null;

    // Handle $ref
    final ref = schema['\$ref'] as String?;
    if (ref != null) {
      return _resolveReference(ref);
    }

    // Handle allOf, oneOf, anyOf
    if (schema.containsKey('allOf')) {
      return _mergeAllOfSchemas(schema['allOf'] as List);
    }

    if (schema.containsKey('oneOf') || schema.containsKey('anyOf')) {
      // For now, just take the first schema in oneOf/anyOf
      final schemas = (schema['oneOf'] ?? schema['anyOf']) as List;
      if (schemas.isNotEmpty) {
        return _resolveSchema(schemas.first as Map<String, dynamic>?);
      }
    }

    // Recursively resolve nested schemas
    final resolved = Map<String, dynamic>.from(schema);

    if (resolved.containsKey('properties')) {
      final properties = resolved['properties'] as Map<String, dynamic>;
      final resolvedProperties = <String, dynamic>{};

      for (final entry in properties.entries) {
        resolvedProperties[entry.key] = _resolveSchema(
          entry.value as Map<String, dynamic>?,
        );
      }

      resolved['properties'] = resolvedProperties;
    }

    if (resolved.containsKey('items')) {
      resolved['items'] = _resolveSchema(
        resolved['items'] as Map<String, dynamic>?,
      );
    }

    return resolved;
  }

  /// Resolve $ref reference
  Map<String, dynamic>? _resolveReference(String ref) {
    if (!ref.startsWith('#/')) {
      debugPrint('SchemaRegistry: External references not supported: $ref');
      return null;
    }

    final path = ref.substring(2).split('/');
    dynamic current = _openApiSpec;

    for (final segment in path) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        debugPrint('SchemaRegistry: Could not resolve reference: $ref');
        return null;
      }
    }

    return _resolveSchema(current as Map<String, dynamic>?);
  }

  /// Merge allOf schemas
  Map<String, dynamic> _mergeAllOfSchemas(List schemas) {
    final merged = <String, dynamic>{};
    final mergedProperties = <String, dynamic>{};
    final mergedRequired = <String>[];

    for (final schema in schemas) {
      final resolvedSchema = _resolveSchema(schema as Map<String, dynamic>?);
      if (resolvedSchema == null) continue;

      // Merge top-level properties
      merged.addAll(resolvedSchema);

      // Merge properties
      if (resolvedSchema.containsKey('properties')) {
        mergedProperties.addAll(
          resolvedSchema['properties'] as Map<String, dynamic>,
        );
      }

      // Merge required fields
      if (resolvedSchema.containsKey('required')) {
        mergedRequired.addAll(
          (resolvedSchema['required'] as List).cast<String>(),
        );
      }
    }

    if (mergedProperties.isNotEmpty) {
      merged['properties'] = mergedProperties;
    }

    if (mergedRequired.isNotEmpty) {
      merged['required'] = mergedRequired;
    }

    return merged;
  }

  /// Pre-build cache of commonly used schemas
  Future<void> _buildSchemaCache() async {
    if (!isLoaded) return;

    final paths = _getPaths();
    int cachedCount = 0;

    for (final pathEntry in paths.entries) {
      final path = pathEntry.key;
      final pathItem = pathEntry.value as Map<String, dynamic>;

      for (final method in ['get', 'post', 'put', 'delete', 'patch']) {
        if (pathItem.containsKey(method)) {
          // Cache request schema
          getRequestSchema(path, method);

          // Cache common response schemas
          getResponseSchema(path, method, 200);
          getResponseSchema(path, method, 201);
          getResponseSchema(path, method, 400);
          getResponseSchema(path, method, 401);
          getResponseSchema(path, method, 403);
          getResponseSchema(path, method, 404);
          getResponseSchema(path, method, 422);
          getResponseSchema(path, method, 500);

          cachedCount++;
        }
      }
    }

    debugPrint(
      'SchemaRegistry: Pre-cached schemas for $cachedCount operations',
    );
  }

  /// Get all available endpoints
  List<String> getAvailableEndpoints() {
    if (!isLoaded) return [];
    return _getPaths().keys.toList();
  }

  /// Get available methods for an endpoint
  List<String> getAvailableMethods(String endpoint) {
    final pathItem = _findPathItem(endpoint);
    if (pathItem == null) return [];

    return pathItem.keys
        .where(
          (key) => [
            'get',
            'post',
            'put',
            'delete',
            'patch',
            'head',
            'options',
          ].contains(key),
        )
        .toList();
  }

  /// Clear all caches
  void clearCache() {
    _requestSchemaCache.clear();
    _responseSchemaCache.clear();
  }
}
