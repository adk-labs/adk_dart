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
  /// Creates a session service.
  BaseSessionService();

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

    _updateSessionState(session: session, event: event);
    final Event persisted = eventForPersistence(event);
    session.events.add(persisted);
    return persisted;
  }

  /// Returns the persistable form of [event].
  ///
  /// Transient `temp:` keys stay visible in the live session state during the
  /// current invocation, but must not be written into stored event history.
  Event eventForPersistence(Event event) {
    if (event.actions.stateDelta.isEmpty) {
      return event;
    }

    final bool hasTempKeys = event.actions.stateDelta.keys.any(
      (String key) => key.startsWith(State.tempPrefix),
    );
    if (!hasTempKeys) {
      return event;
    }

    final Map<String, Object?> persistedDelta = Map<String, Object?>.from(
      event.actions.stateDelta,
    )..removeWhere((String key, Object? _) => key.startsWith(State.tempPrefix));
    return event.copyWith(
      actions: event.actions.copyWith(stateDelta: persistedDelta),
    );
  }

  void _updateSessionState({required Session session, required Event event}) {
    if (event.actions.stateDelta.isEmpty) {
      return;
    }

    event.actions.stateDelta.forEach((String key, Object? value) {
      session.state[key] = value;
    });
  }
}
