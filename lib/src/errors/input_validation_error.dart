/// Error thrown when input validation fails.
library;

/// Exception indicating invalid user or API input.
class InputValidationError implements Exception {
  /// Creates an input-validation error with optional [message].
  InputValidationError([this.message = 'Invalid input.']);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'InputValidationError: $message';
}
