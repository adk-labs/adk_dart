/// Cooperative cancellation primitives for ADK invocations.
library;

/// Exception thrown when an operation observes an aborted ADK signal.
class AdkAbortException implements Exception {
  /// Creates an abort exception with an optional [reason].
  AdkAbortException([this.reason]);

  /// Caller-provided cancellation reason.
  final Object? reason;

  @override
  String toString() {
    final Object? value = reason;
    return value == null ? 'AdkAbortException' : 'AdkAbortException: $value';
  }
}

/// Read-only cancellation signal propagated through an invocation.
class AdkAbortSignal {
  AdkAbortSignal._();

  bool _aborted = false;
  Object? _reason;
  final List<void Function(Object? reason)> _listeners =
      <void Function(Object? reason)>[];

  /// Whether cancellation has been requested.
  bool get aborted => _aborted;

  /// Optional cancellation reason.
  Object? get reason => _reason;

  /// Registers [listener] to run when the signal is aborted.
  ///
  /// If already aborted, the listener runs synchronously.
  void addListener(void Function(Object? reason) listener) {
    if (_aborted) {
      listener(_reason);
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a previously registered [listener].
  void removeListener(void Function(Object? reason) listener) {
    _listeners.remove(listener);
  }

  /// Throws [AdkAbortException] when [aborted] is true.
  void throwIfAborted() {
    if (_aborted) {
      throw AdkAbortException(_reason);
    }
  }

  void _abort(Object? reason) {
    if (_aborted) {
      return;
    }
    _aborted = true;
    _reason = reason;
    final List<void Function(Object? reason)> listeners =
        List<void Function(Object? reason)>.from(_listeners);
    _listeners.clear();
    for (final void Function(Object? reason) listener in listeners) {
      listener(reason);
    }
  }
}

/// Controller used by callers to cancel an ADK invocation.
class AdkAbortController {
  /// Creates a cancellation controller.
  AdkAbortController() : signal = AdkAbortSignal._();

  /// Signal passed to runner APIs and exposed through invocation contexts.
  final AdkAbortSignal signal;

  /// Requests cancellation.
  void abort([Object? reason]) {
    signal._abort(reason);
  }
}
