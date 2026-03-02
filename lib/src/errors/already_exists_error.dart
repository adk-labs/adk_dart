/// Error thrown when attempting to create an already existing resource.
library;

/// Exception indicating that a resource already exists.
class AlreadyExistsError implements Exception {
  /// Creates an already-exists error with optional [message].
  AlreadyExistsError([this.message = 'The resource already exists.']);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'AlreadyExistsError: $message';
}
