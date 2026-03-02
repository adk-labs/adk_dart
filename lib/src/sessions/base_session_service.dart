/// Base abstractions for session storage services.
library;

import '../events/event.dart';
import 'session.dart';
import 'state.dart';

/// Options for narrowing session retrieval results.
class GetSessionConfig {
  /// Creates session query options.
  GetSessionConfig({this.numRecentEvents, this.afterTimestamp});

  /// Maximum number of most recent events to return.
  int? numRecentEvents;

  /// Minimum event timestamp (seconds since epoch) to include.
  double? afterTimestamp;
}

/// Response model for session list operations.
class ListSessionsResponse {
  /// Creates a session list response.
  ListSessionsResponse({List<Session>? sessions})
    : sessions = sessions ?? <Session>[];

  /// Sessions returned by the list query.
  List<Session> sessions;
}

/// Contract for session lifecycle and event persistence operations.
abstract class BaseSessionService {
  /// Creates and returns a new session.
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  });

  /// Returns a single session when it exists, otherwise `null`.
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  });

  /// Returns sessions for [appName], optionally scoped to [userId].
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  });

  /// Deletes one session identified by app, user, and session IDs.
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  });

  /// Appends [event] to [session] and updates persisted session state.
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
