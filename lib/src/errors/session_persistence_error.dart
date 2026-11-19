/// Error thrown when buffered session writes could not be persisted.
library;

/// Raised when buffered session writes could not be persisted.
///
/// [cause] holds the error of the last attempt, such as `StaleSessionError`
/// when the session object was behind storage. Read the session again before
/// appending to it.
class SessionPersistenceError implements Exception {
  /// Creates a session persistence error with [message], optional [cause], and
  /// optional diagnostic [notes].
  SessionPersistenceError(
    this.message, {
    this.cause,
    List<String>? notes,
  }) : notes = List<String>.unmodifiable(notes ?? const <String>[]);

  /// Human-readable error message.
  final String message;

  /// Underlying error from the last persistence attempt, if any.
  final Object? cause;

  /// Additional notes describing other failed sessions when flushing all.
  final List<String> notes;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer(
      'SessionPersistenceError: $message',
    );
    if (cause != null) {
      buffer.write(' (cause: $cause)');
    }
    for (final String note in notes) {
      buffer.write('\n  $note');
    }
    return buffer.toString();
  }
}
