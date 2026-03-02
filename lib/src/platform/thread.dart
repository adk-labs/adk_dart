/// Lightweight threading abstraction used for runtime parity.
library;

import 'dart:async';

/// Factory signature for creating platform-specific thread wrappers.
typedef InternalThreadCreator =
    AdkThread Function(
      Function target,
      List<Object?> args,
      Map<Symbol, Object?> namedArgs,
    );

InternalThreadCreator? _internalThreadCreator;

/// Sets a custom internal thread creator for platform overrides.
void setInternalThreadCreator(InternalThreadCreator? creator) {
  _internalThreadCreator = creator;
}

/// Async thread-like wrapper around a target function invocation.
class AdkThread {
  /// Creates an ADK thread wrapper.
  AdkThread(
    this._target, {
    List<Object?>? args,
    Map<Symbol, Object?>? namedArgs,
  }) : _args = args ?? <Object?>[],
       _namedArgs = namedArgs ?? <Symbol, Object?>{};

  final Function _target;
  final List<Object?> _args;
  final Map<Symbol, Object?> _namedArgs;

  Future<void>? _future;
  bool _completed = false;

  /// Whether the thread has been started.
  bool get isStarted => _future != null;

  /// Whether the thread completed execution.
  bool get isCompleted => _completed;

  /// Starts the thread if it has not started yet.
  void start() {
    if (_future != null) {
      return;
    }
    _future =
        Future<void>(
          () => Future<void>.sync(
            () => Function.apply(_target, _args, _namedArgs),
          ),
        ).whenComplete(() {
          _completed = true;
        });
  }

  /// Waits for thread completion, starting it if needed.
  Future<void> join() async {
    start();
    await _future;
  }
}

/// Creates a new thread wrapper for [target].
AdkThread createThread(
  Function target, {
  List<Object?> args = const <Object?>[],
  Map<Symbol, Object?> namedArgs = const <Symbol, Object?>{},
}) {
  final InternalThreadCreator? internalThread = _internalThreadCreator;
  if (internalThread != null) {
    return internalThread(target, args, namedArgs);
  }
  return AdkThread(target, args: args, namedArgs: namedArgs);
}
