/// Generic lazy session lifecycle container for MCP resources.
library;

import 'dart:async';

/// Lifecycle helper that lazily starts and closes session resources.
class SessionContext<T> {
  /// Creates a session lifecycle context.
  SessionContext({
    required Future<T> Function() startSession,
    Future<void> Function(T session)? closeSession,
    this.timeout = const Duration(seconds: 5),
  }) : _startSession = startSession,
       _closeSession = closeSession;

  final Future<T> Function() _startSession;
  final Future<void> Function(T session)? _closeSession;

  /// Timeout applied when starting sessions.
  final Duration timeout;

  Future<T>? _starting;
  T? _session;
  bool _closed = false;

  /// Current started session, if any.
  T? get session => _session;

  /// Starts the session lazily and returns the shared instance.
  Future<T> start() async {
    if (_session != null) {
      return _session as T;
    }
    if (_closed) {
      throw StateError('SessionContext is already closed.');
    }
    if (_starting != null) {
      return _starting as Future<T>;
    }

    final Completer<T> completer = Completer<T>();
    _starting = completer.future;

    () async {
      try {
        final T created = await _startSession().timeout(timeout);
        _session = created;
        completer.complete(created);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _starting = null;
      }
    }();

    return completer.future;
  }

  /// Closes the started session and marks this context as closed.
  Future<void> close() async {
    _closed = true;
    final T? created = _session;
    if (created != null && _closeSession != null) {
      await _closeSession(created);
    }
    _session = null;
  }
}
