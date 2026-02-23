import 'dart:async';

typedef InternalThreadCreator =
    AdkThread Function(
      Function target,
      List<Object?> args,
      Map<Symbol, Object?> namedArgs,
    );

InternalThreadCreator? _internalThreadCreator;

void setInternalThreadCreator(InternalThreadCreator? creator) {
  _internalThreadCreator = creator;
}

class AdkThread {
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

  bool get isStarted => _future != null;
  bool get isCompleted => _completed;

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

  Future<void> join() async {
    start();
    await _future;
  }
}

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
