/// Shared utilities for session-state serialization and partitioning.
library;

import 'state.dart';

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
