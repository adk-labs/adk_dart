import 'state.dart';

class SessionStateDelta {
  SessionStateDelta({
    required this.app,
    required this.user,
    required this.session,
  });

  Map<String, Object?> app;
  Map<String, Object?> user;
  Map<String, Object?> session;
}

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
