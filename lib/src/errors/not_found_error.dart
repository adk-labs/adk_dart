/// Error thrown when a requested resource cannot be found.
library;

/// Exception indicating missing resources.
class NotFoundError implements Exception {
  /// Creates a not-found error with optional [message].
  NotFoundError([this.message = 'The requested resource was not found.']);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'NotFoundError: $message';
}
