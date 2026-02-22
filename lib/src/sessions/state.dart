import 'dart:collection';

class State extends MapBase<String, Object?> {
  State({
    required Map<String, Object?> value,
    required Map<String, Object?> delta,
  }) : _value = value,
       _delta = delta;

  static const String appPrefix = 'app:';
  static const String userPrefix = 'user:';
  static const String tempPrefix = 'temp:';

  final Map<String, Object?> _value;
  final Map<String, Object?> _delta;

  @override
  Object? operator [](Object? key) {
    if (key is! String) {
      return null;
    }
    if (_delta.containsKey(key)) {
      return _delta[key];
    }
    return _value[key];
  }

  @override
  void operator []=(String key, Object? value) {
    _value[key] = value;
    _delta[key] = value;
  }

  @override
  void clear() {
    final List<String> currentKeys = keys.toList(growable: false);
    for (final String key in currentKeys) {
      remove(key);
    }
  }

  @override
  Iterable<String> get keys => <String>{..._value.keys, ..._delta.keys};

  @override
  Object? remove(Object? key) {
    if (key is! String) {
      return null;
    }
    final Object? old = this[key];
    _value.remove(key);
    _delta[key] = null;
    return old;
  }

  bool hasDelta() => _delta.isNotEmpty;

  Map<String, Object?> toMap() {
    return <String, Object?>{..._value, ..._delta};
  }
}
