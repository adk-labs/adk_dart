typedef AsyncCloser<T> = Future<void> Function(T resource);

class Aclosing<T> {
  Aclosing(this.resource, this._closer);

  final T resource;
  final AsyncCloser<T> _closer;
  bool _closed = false;

  bool get isClosed => _closed;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _closer(resource);
  }
}

Future<R> withAclosing<T, R>(
  T resource,
  AsyncCloser<T> closer,
  Future<R> Function(T resource) callback,
) async {
  final Aclosing<T> wrapper = Aclosing<T>(resource, closer);
  try {
    return await callback(wrapper.resource);
  } finally {
    await wrapper.close();
  }
}
