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
  final Map<String, (Object?, Object?)> _snapshots =
      <String, (Object?, Object?)>{};

  @override
  Object? operator [](Object? key) {
    if (key is! String) {
      return null;
    }
    final Object? value = _delta.containsKey(key) ? _delta[key] : _value[key];
    if ((value is Map || value is List) && !_snapshots.containsKey(key)) {
      _takeSnapshot(key, value);
    }
    return value;
  }

  @override
  void operator []=(String key, Object? value) {
    _value[key] = value;
    _delta[key] = value;
    _snapshots.remove(key);
  }

  void _takeSnapshot(String key, Object? value) {
    _snapshots.remove(key);
    try {
      final Object? snapshot = _deepCopyContainer(
        value,
        <Object, Object?>{},
      );
      if (!_deepEquals(value, snapshot, <Object>{})) {
        return;
      }
      _snapshots[key] = (value, snapshot);
    } catch (_) {
      return;
    }
  }

  /// Records any in-place mutations made to `Map` or `List` containers
  /// previously read from this state into the pending delta.
  void recordNestedWrites() {
    for (final MapEntry<String, (Object?, Object?)> entry
        in _snapshots.entries.toList(growable: false)) {
      final String key = entry.key;
      final (Object? handedOut, Object? snapshot) = entry.value;
      final Object? current;
      if (_delta.containsKey(key)) {
        current = _delta[key];
      } else if (_value.containsKey(key)) {
        current = _value[key];
      } else {
        _snapshots.remove(key);
        continue;
      }

      if (!identical(current, handedOut)) {
        _snapshots.remove(key);
        continue;
      }

      bool changed = false;
      try {
        changed = !_deepEquals(current, snapshot, <Object>{});
      } catch (_) {
        _snapshots.remove(key);
        continue;
      }

      if (changed) {
        _value[key] = current;
        _delta[key] = current;
        _takeSnapshot(key, current);
      }
    }
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
    _snapshots.remove(key);
    return old;
  }

  /// Whether any state changes are currently recorded in delta.
  bool hasDelta() {
    recordNestedWrites();
    return _delta.isNotEmpty;
  }

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
    for (final String key in delta.keys) {
      _snapshots.remove(key);
    }
  }

  /// Returns a merged map of base values and current delta.
  Map<String, Object?> toMap() {
    recordNestedWrites();
    return <String, Object?>{..._value, ..._delta};
  }

  /// Alias of [toMap] for compatibility with Python naming.
  Map<String, Object?> toDict() => toMap();
}

Object? _deepCopyContainer(Object? value, Map<Object, Object?> seen) {
  if (value is Map) {
    if (seen.containsKey(value)) {
      return seen[value];
    }
    final Map<Object?, Object?> copy = <Object?, Object?>{};
    seen[value] = copy;
    value.forEach((Object? key, Object? nested) {
      copy[_deepCopyContainer(key, seen)] = _deepCopyContainer(nested, seen);
    });
    return copy;
  }
  if (value is List) {
    if (seen.containsKey(value)) {
      return seen[value];
    }
    final List<Object?> copy = <Object?>[];
    seen[value] = copy;
    for (final Object? item in value) {
      copy.add(_deepCopyContainer(item, seen));
    }
    return copy;
  }
  return value;
}

bool _deepEquals(Object? a, Object? b, Set<Object> activePairs) {
  if (identical(a, b)) {
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    if (!activePairs.add(a)) {
      return true;
    }
    try {
      for (int i = 0; i < a.length; i += 1) {
        if (!_deepEquals(a[i], b[i], activePairs)) {
          return false;
        }
      }
      return true;
    } finally {
      activePairs.remove(a);
    }
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    if (!activePairs.add(a)) {
      return true;
    }
    try {
      for (final Object? key in a.keys) {
        if (!b.containsKey(key) ||
            !_deepEquals(a[key], b[key], activePairs)) {
          return false;
        }
      }
      return true;
    } finally {
      activePairs.remove(a);
    }
  }
  return a == b;
}
