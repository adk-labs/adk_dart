/// State wrapper that tracks value mutations as deltas.
library;

import 'dart:collection';

/// Map-like state container with change tracking.
class State extends MapBase<String, Object?> {
  /// Creates state from base [value] and mutable [delta] map.
  State({
    required Map<String, Object?> value,
    required Map<String, Object?> delta,
  }) : _value = value,
       _delta = delta;

  /// Prefix used for app-scoped state keys.
  static const String appPrefix = 'app:';

  /// Prefix used for user-scoped state keys.
  static const String userPrefix = 'user:';

  /// Prefix used for transient state keys.
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

  /// Whether any state changes are currently recorded in delta.
  bool hasDelta() => _delta.isNotEmpty;

  /// Returns an existing value or sets [defaultValue] for missing [key].
  Object? setDefault(String key, [Object? defaultValue]) {
    return putIfAbsent(key, () => defaultValue);
  }

  /// Returns value for [key], or [defaultValue] when missing.
  Object? getValue(String key, [Object? defaultValue]) {
    if (!containsKey(key)) {
      return defaultValue;
    }
    return this[key];
  }

  /// Applies [delta] updates to this state.
  void updateFromDelta(Map<String, Object?> delta) {
    addAll(delta);
  }

  /// Returns a merged map of base values and current delta.
  Map<String, Object?> toMap() {
    return <String, Object?>{..._value, ..._delta};
  }

  /// Alias of [toMap] for compatibility with Python naming.
  Map<String, Object?> toDict() => toMap();
}
