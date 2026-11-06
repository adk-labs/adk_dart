/// Shared utilities for session-state serialization and partitioning.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'state.dart';

/// Recursively coerces raw [Uint8List] byte buffers into JSON-compatible
/// strings (UTF-8 decoded when valid, or base64-encoded for binary bytes).
Object? coerceBytesForJson(Object? value) {
  if (value is Uint8List) {
    try {
      return utf8.decode(value);
    } on FormatException {
      return base64.encode(value);
    }
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': coerceBytesForJson(entry.value),
    };
  }
  if (value is List) {
    return value.map(coerceBytesForJson).toList(growable: false);
  }
  if (value is Set) {
    return value.map(coerceBytesForJson).toList(growable: false);
  }
  return value;
}

/// Split representation of app, user, and session-scoped state entries.
class SessionStateDelta {
  /// Creates a session state delta container.
  SessionStateDelta({
    required this.app,
    required this.user,
    required this.session,
  });

  /// App-scoped state entries without [State.appPrefix].
  Map<String, Object?> app;

  /// User-scoped state entries without [State.userPrefix].
  Map<String, Object?> user;

  /// Session-scoped state entries without prefixed keys.
  Map<String, Object?> session;
}

/// Decodes [data] into a model using [fromJson].
///
/// Returns `null` when [data] is `null`.
T? decodeModel<T>(
  Object? data,
  T Function(Map<String, Object?> json) fromJson,
) {
  if (data == null) {
    return null;
  }
  if (data is Map<String, Object?>) {
    return fromJson(Map<String, Object?>.from(data));
  }
  if (data is Map) {
    final Map<String, Object?> normalized = data.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    return fromJson(normalized);
  }
  throw ArgumentError('Expected JSON map, got ${data.runtimeType}.');
}

/// Splits a mixed [state] map into app, user, and session deltas.
SessionStateDelta extractStateDelta(Map<String, Object?>? state) {
  final Map<String, Object?> app = <String, Object?>{};
  final Map<String, Object?> user = <String, Object?>{};
  final Map<String, Object?> session = <String, Object?>{};

  if (state != null) {
    state.forEach((String key, Object? value) {
      if (key.startsWith(State.appPrefix)) {
        app[key.substring(State.appPrefix.length)] = value;
      } else if (key.startsWith(State.userPrefix)) {
        user[key.substring(State.userPrefix.length)] = value;
      } else if (!key.startsWith(State.tempPrefix)) {
        session[key] = value;
      }
    });
  }

  return SessionStateDelta(app: app, user: user, session: session);
}

/// Returns [state] without transient `temp:` entries.
Map<String, Object?> trimTempState(Map<String, Object?>? state) {
  if (state == null || state.isEmpty) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in state.entries)
      if (!entry.key.startsWith(State.tempPrefix)) entry.key: entry.value,
  };
}

/// Recursively converts [value] into a JSON-serializable structure.
///
/// Objects that expose `toJson()` or `toMap()` are converted via those methods
/// before nested values are normalized.
Object? makeJsonSafeValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Uint8List) {
    return coerceBytesForJson(value);
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Uri) {
    return value.toString();
  }
  if (value is Enum) {
    return value.name;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': makeJsonSafeValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(makeJsonSafeValue).toList(growable: false);
  }
  try {
    final Object? jsonValue = (value as dynamic).toJson();
    if (!identical(jsonValue, value)) {
      return makeJsonSafeValue(jsonValue);
    }
  } catch (_) {
    // Object does not provide `toJson()`.
  }
  try {
    final Object? mapValue = (value as dynamic).toMap();
    if (!identical(mapValue, value)) {
      return makeJsonSafeValue(mapValue);
    }
  } catch (_) {
    // Object does not provide `toMap()`.
  }
  return '$value';
}

/// Returns a copy of [state] with all values normalized via [makeJsonSafeValue].
Map<String, Object?> makeJsonSafeState(Map<String, Object?>? state) {
  if (state == null || state.isEmpty) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in state.entries)
      entry.key: makeJsonSafeValue(entry.value),
  };
}
