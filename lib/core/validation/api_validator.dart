import 'package:flutter/foundation.dart';
import 'schema_registry.dart';
import 'validation_result.dart';
import 'field_mapper.dart';

/// Comprehensive API request and response validator
/// Validates against OpenAPI specification schemas
class ApiValidator {
  static final ApiValidator _instance = ApiValidator._internal();
  factory ApiValidator() => _instance;
  ApiValidator._internal();

  final SchemaRegistry _schemaRegistry = SchemaRegistry();
  final FieldMapper _fieldMapper = FieldMapper();

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Initialize validator with OpenAPI schemas
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _schemaRegistry.loadSchemas();
      _initialized = true;
      debugPrint('ApiValidator: Successfully initialized with schemas');
    } catch (e) {
      debugPrint('ApiValidator: Failed to initialize: $e');
      // Continue without validation if schemas can't be loaded
    }
  }

  /// Validate request payload before sending to API
  ValidationResult validateRequest(
    dynamic data,
    String endpoint, {
    String method = 'GET',
  }) {
    if (!_initialized) {
      return ValidationResult.warning(
        'Validator not initialized - skipping validation',
      );
    }

    try {
      final schema = _schemaRegistry.getRequestSchema(endpoint, method);
      if (schema == null) {
        return ValidationResult.warning(
          'No schema found for $method $endpoint',
        );
      }

      // Transform field names for API (camelCase -> snake_case)
      final transformedData = _fieldMapper.toApiFormat(data);

      // Validate against schema
      return _validateAgainstSchema(transformedData, schema, 'request');
    } catch (e) {
      return ValidationResult.error('Request validation failed: $e');
    }
  }

  /// Validate response payload after receiving from API
  ValidationResult validateResponse(
    dynamic data,
    String endpoint, {
    String method = 'GET',
    int? statusCode,
  }) {
    if (!_initialized) {
      return ValidationResult.warning(
        'Validator not initialized - skipping validation',
      );
    }

    try {
      final schema = _schemaRegistry.getResponseSchema(
        endpoint,
        method,
        statusCode,
      );
      if (schema == null) {
        return ValidationResult.warning(
          'No schema found for $method $endpoint response',
        );
      }

      // Validate against schema first
      final validationResult = _validateAgainstSchema(data, schema, 'response');
      if (!validationResult.isValid) {
        return validationResult;
      }

      // Transform field names from API (snake_case -> camelCase)
      final transformedData = _fieldMapper.fromApiFormat(data);

      return ValidationResult.success(
        'Response validated successfully',
        data: transformedData,
      );
    } catch (e) {
      return ValidationResult.error('Response validation failed: $e');
    }
  }

  /// Validate data against a specific schema
  ValidationResult _validateAgainstSchema(
    dynamic data,
    Map<String, dynamic> schema,
    String context,
  ) {
    final errors = <String>[];
    final warnings = <String>[];

    try {
      _validateValue(data, schema, '', errors, warnings);

      if (errors.isNotEmpty) {
        return ValidationResult.error(
          'Schema validation failed for $context',
          errors: errors,
          warnings: warnings,
        );
      }

      if (warnings.isNotEmpty) {
        return ValidationResult.warning(
          'Schema validation passed with warnings for $context',
          warnings: warnings,
        );
      }

      return ValidationResult.success('Schema validation passed for $context');
    } catch (e) {
      return ValidationResult.error('Schema validation error for $context: $e');
    }
  }

  /// Recursively validate a value against schema
  void _validateValue(
    dynamic value,
    Map<String, dynamic> schema,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    final type = schema['type'] as String?;
    final required = schema['required'] as List<dynamic>? ?? [];

    // Handle null values
    if (value == null) {
      if (required.isNotEmpty && path.isNotEmpty) {
        errors.add('Required field missing: $path');
      }
      return;
    }

    // Type validation
    switch (type) {
      case 'object':
        _validateObject(value, schema, path, errors, warnings);
        break;
      case 'array':
        _validateArray(value, schema, path, errors, warnings);
        break;
      case 'string':
        _validateString(value, schema, path, errors, warnings);
        break;
      case 'number':
      case 'integer':
        _validateNumber(value, schema, path, errors, warnings);
        break;
      case 'boolean':
        _validateBoolean(value, schema, path, errors, warnings);
        break;
      default:
        // Unknown type - add warning but don't fail
        warnings.add('Unknown schema type "$type" at $path');
    }
  }

  void _validateObject(
    dynamic value,
    Map<String, dynamic> schema,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    if (value is! Map) {
      errors.add('Expected object at $path, got ${value.runtimeType}');
      return;
    }

    final valueMap = value as Map<String, dynamic>;
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final required = (schema['required'] as List<dynamic>? ?? [])
        .cast<String>();

    // Check required fields
    for (final requiredField in required) {
      if (!valueMap.containsKey(requiredField)) {
        errors.add(
          'Required field missing: ${path.isEmpty ? '' : '$path.'}$requiredField',
        );
      }
    }

    // Validate each property
    for (final entry in valueMap.entries) {
      final fieldName = entry.key;
      final fieldValue = entry.value;
      final fieldPath = path.isEmpty ? fieldName : '$path.$fieldName';

      if (properties.containsKey(fieldName)) {
        _validateValue(
          fieldValue,
          properties[fieldName],
          fieldPath,
          errors,
          warnings,
        );
      } else {
        // Additional property - warn but don't error
        warnings.add('Additional property found: $fieldPath');
      }
    }
  }

  void _validateArray(
    dynamic value,
    Map<String, dynamic> schema,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    if (value is! List) {
      errors.add('Expected array at $path, got ${value.runtimeType}');
      return;
    }

    final array = value;
    final items = schema['items'] as Map<String, dynamic>?;
    final minItems = schema['minItems'] as int?;
    final maxItems = schema['maxItems'] as int?;

    // Validate array constraints
    if (minItems != null && array.length < minItems) {
      errors.add(
        'Array at $path has ${array.length} items, minimum is $minItems',
      );
    }

    if (maxItems != null && array.length > maxItems) {
      errors.add(
        'Array at $path has ${array.length} items, maximum is $maxItems',
      );
    }

    // Validate each item
    if (items != null) {
      for (int i = 0; i < array.length; i++) {
        _validateValue(array[i], items, '$path[$i]', errors, warnings);
      }
    }
  }

  void _validateString(
    dynamic value,
    Map<String, dynamic> schema,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    if (value is! String) {
      errors.add('Expected string at $path, got ${value.runtimeType}');
      return;
    }

    final string = value;
    final minLength = schema['minLength'] as int?;
    final maxLength = schema['maxLength'] as int?;
    final pattern = schema['pattern'] as String?;
    final format = schema['format'] as String?;

    if (minLength != null && string.length < minLength) {
      errors.add(
        'String at $path is ${string.length} chars, minimum is $minLength',
      );
    }

    if (maxLength != null && string.length > maxLength) {
      errors.add(
        'String at $path is ${string.length} chars, maximum is $maxLength',
      );
    }

    if (pattern != null) {
      try {
        final regex = RegExp(pattern);
        if (!regex.hasMatch(string)) {
          errors.add('String at $path does not match pattern: $pattern');
        }
      } catch (e) {
        warnings.add('Invalid regex pattern at $path: $pattern');
      }
    }

    // Validate common formats
    if (format != null) {
      _validateStringFormat(string, format, path, errors, warnings);
    }
  }

  void _validateStringFormat(
    String value,
    String format,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    switch (format) {
      case 'email':
        final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
        if (!emailRegex.hasMatch(value)) {
          errors.add('Invalid email format at $path: $value');
        }
        break;
      case 'uri':
      case 'url':
        try {
          Uri.parse(value);
        } catch (e) {
          errors.add('Invalid URL format at $path: $value');
        }
        break;
      case 'date':
        try {
          DateTime.parse(value);
        } catch (e) {
          errors.add('Invalid date format at $path: $value');
        }
        break;
      case 'date-time':
        try {
          DateTime.parse(value);
        } catch (e) {
          errors.add('Invalid datetime format at $path: $value');
        }
        break;
      case 'uuid':
        final uuidRegex = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          caseSensitive: false,
        );
        if (!uuidRegex.hasMatch(value)) {
          errors.add('Invalid UUID format at $path: $value');
        }
        break;
      default:
        warnings.add('Unknown string format "$format" at $path');
    }
  }

  void _validateNumber(
    dynamic value,
    Map<String, dynamic> schema,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    if (value is! num) {
      errors.add('Expected number at $path, got ${value.runtimeType}');
      return;
    }

    final number = value;
    final minimum = schema['minimum'] as num?;
    final maximum = schema['maximum'] as num?;
    final multipleOf = schema['multipleOf'] as num?;

    if (minimum != null && number < minimum) {
      errors.add('Number at $path is $number, minimum is $minimum');
    }

    if (maximum != null && number > maximum) {
      errors.add('Number at $path is $number, maximum is $maximum');
    }

    if (multipleOf != null && number % multipleOf != 0) {
      errors.add('Number at $path ($number) is not a multiple of $multipleOf');
    }
  }

  void _validateBoolean(
    dynamic value,
    Map<String, dynamic> schema,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    if (value is! bool) {
      errors.add('Expected boolean at $path, got ${value.runtimeType}');
    }
  }

  /// Transform and validate data for API consumption
  Map<String, dynamic> transformForApi(Map<String, dynamic> data) {
    return _fieldMapper.toApiFormat(data);
  }

  /// Transform and validate data from API response
  Map<String, dynamic> transformFromApi(Map<String, dynamic> data) {
    return _fieldMapper.fromApiFormat(data);
  }
}
