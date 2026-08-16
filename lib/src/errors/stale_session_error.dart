/// Error thrown when a session write loses an optimistic concurrency race.
library;

/// Exception indicating an optimistic concurrency conflict during session update.
class StaleSessionError extends StateError {
  /// Creates a stale-session error with optional [message].
  StaleSessionError([super.message = 'Session has been updated by another process.']);

  @override
  String toString() => 'StaleSessionError: $message';
}
