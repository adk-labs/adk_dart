import '../events/event.dart';
import 'session.dart';
import 'state.dart';

class GetSessionConfig {
  GetSessionConfig({this.numRecentEvents, this.afterTimestamp});

  int? numRecentEvents;
  double? afterTimestamp;
}

class ListSessionsResponse {
  ListSessionsResponse({List<Session>? sessions})
    : sessions = sessions ?? <Session>[];

  List<Session> sessions;
}

abstract class BaseSessionService {
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  });

  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  });

  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  });

  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  });

  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    if (event.partial == true) {
      return event;
    }

    final Event trimmed = _trimTempDeltaState(event);
    _updateSessionState(session: session, event: trimmed);
    session.events.add(trimmed);
    return trimmed;
  }

  Event _trimTempDeltaState(Event event) {
    if (event.actions.stateDelta.isEmpty) {
      return event;
    }

    event.actions.stateDelta.removeWhere(
      (String key, Object? _) => key.startsWith(State.tempPrefix),
    );
    return event;
  }

  void _updateSessionState({required Session session, required Event event}) {
    if (event.actions.stateDelta.isEmpty) {
      return;
    }

    event.actions.stateDelta.forEach((String key, Object? value) {
      if (key.startsWith(State.tempPrefix)) {
        return;
      }
      session.state[key] = value;
    });
  }
}
