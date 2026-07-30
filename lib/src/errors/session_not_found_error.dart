/// Error thrown when a session cannot be found.
library;

import 'not_found_error.dart';

/// Exception indicating missing session resource.
class SessionNotFoundError extends NotFoundError {
  /// Creates a session-not-found error with optional [message].
  SessionNotFoundError([super.message = 'Session not found.']);

  @override
  String toString() => 'SessionNotFoundError: $message';
}
