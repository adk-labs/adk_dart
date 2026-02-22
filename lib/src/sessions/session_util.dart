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
