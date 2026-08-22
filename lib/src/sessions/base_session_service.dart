/// Base abstractions for session storage services.
library;

import '../events/event.dart';
import 'session.dart';
import 'state.dart';

/// Options for narrowing session retrieval results.
class GetSessionConfig {
  /// Creates session query options.
  GetSessionConfig({int? numRecentEvents, this.afterTimestamp}) {
    if (numRecentEvents != null) {
      this.numRecentEvents = numRecentEvents;
    }
  }

  int? _numRecentEvents;

  /// Maximum number of most recent events to return.
  int? get numRecentEvents => _numRecentEvents;
  set numRecentEvents(int? value) {
    if (value != null && value < 0) {
      throw ArgumentError('num_recent_events must be greater than or equal to 0.');
    }
    _numRecentEvents = value;
  }

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

  /// Returns raw user-scoped state for [appName] and [userId].
  ///
  /// Returned keys do not include the `user:` prefix. Implementations that
  /// cannot read user state independently of a session should throw
  /// [UnimplementedError].
  Future<Map<String, Object?>> getUserState({
    required String appName,
    required String userId,
  }) async {
    throw UnimplementedError(
      '$runtimeType does not support getUserState. '
      'Enumerate sessions and call getSession to read merged user state.',
    );
  }

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

  /// Flushes buffered events for session services that batch writes.
  ///
  /// Non-buffering implementations can keep this no-op default.
  Future<void> flush() async {}

  /// Eagerly prepares and initializes underlying database tables/schemas.
  ///
  /// Database-backed implementations can create tables and indexes proactively
  /// before processing incoming user requests.
  Future<void> prepareTables() async {}

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
