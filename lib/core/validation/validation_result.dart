/// Result of API validation operations
class ValidationResult {
  const ValidationResult._({
    required this.isValid,
    required this.status,
    required this.message,
    this.errors = const [],
    this.warnings = const [],
    this.data,
  });

  const ValidationResult.success(
    String message, {
    dynamic data,
    List<String> warnings = const [],
  }) : this._(
         isValid: true,
         status: ValidationStatus.success,
         message: message,
         warnings: warnings,
         data: data,
       );

  const ValidationResult.warning(
    String message, {
    List<String> warnings = const [],
    dynamic data,
  }) : this._(
         isValid: true,
         status: ValidationStatus.warning,
         message: message,
         warnings: warnings,
         data: data,
       );

  const ValidationResult.error(
    String message, {
    List<String> errors = const [],
    List<String> warnings = const [],
  }) : this._(
         isValid: false,
         status: ValidationStatus.error,
         message: message,
         errors: errors,
         warnings: warnings,
       );

  final bool isValid;
  final ValidationStatus status;
  final String message;
  final List<String> errors;
  final List<String> warnings;
  final dynamic data;

  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('ValidationResult(');
    buffer.write('status: $status, ');
    buffer.write('message: $message');

    if (hasErrors) {
      buffer.write(', errors: ${errors.length}');
    }

    if (hasWarnings) {
      buffer.write(', warnings: ${warnings.length}');
    }

    buffer.write(')');
    return buffer.toString();
  }

  /// Convert to a detailed map for logging/debugging
  Map<String, dynamic> toMap() {
    return {
      'isValid': isValid,
      'status': status.name,
      'message': message,
      'errors': errors,
      'warnings': warnings,
      'hasData': data != null,
    };
  }
}

enum ValidationStatus { success, warning, error }

/// Exception thrown when validation fails critically
class ValidationException implements Exception {
  const ValidationException(this.result);

  final ValidationResult result;

  @override
  String toString() => 'ValidationException: ${result.message}';
}
