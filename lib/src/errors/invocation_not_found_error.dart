/// Error thrown when an invocation id cannot be found in the session's events.
library;

import 'not_found_error.dart';

/// Exception indicating an invocation ID was not found in a session.
class InvocationNotFoundError extends NotFoundError implements ArgumentError {
  /// Creates an invocation-not-found error with optional [message].
  InvocationNotFoundError([
    super.message = 'Invocation ID not found.',
    this.invalidValue,
    this.name,
  ]);

  @override
  final Object? invalidValue;

  @override
  final String? name;

  @override
  StackTrace? get stackTrace => null;

  @override
  String toString() => 'InvocationNotFoundError: $message';
}
