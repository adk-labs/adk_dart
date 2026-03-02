/// Async closer callback for resource type [T].
typedef AsyncCloser<T> = Future<void> Function(T resource);

/// Lightweight async close wrapper for a resource.
class Aclosing<T> {
  /// Creates a wrapper around [resource] and its async [_closer].
  Aclosing(this.resource, this._closer);

  /// Wrapped resource instance.
  final T resource;
  final AsyncCloser<T> _closer;
  bool _closed = false;

  /// Whether [close] has already been called.
  bool get isClosed => _closed;

  /// Closes the wrapped resource exactly once.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _closer(resource);
  }
}

/// Runs [callback] with [resource] and always invokes [closer] afterward.
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
