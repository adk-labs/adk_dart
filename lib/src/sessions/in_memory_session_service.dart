import '../errors/already_exists_error.dart';
import '../events/event.dart';
import '../types/id.dart';
import 'base_session_service.dart';
import 'session.dart';
import 'session_util.dart';
import 'state.dart';

class InMemorySessionService extends BaseSessionService {
  final Map<String, Map<String, Map<String, Session>>> _sessions =
      <String, Map<String, Map<String, Session>>>{};

  final Map<String, Map<String, Object?>> _appState =
      <String, Map<String, Object?>>{};

  final Map<String, Map<String, Map<String, Object?>>> _userState =
      <String, Map<String, Map<String, Object?>>>{};

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    if (sessionId != null &&
        await getSession(
              appName: appName,
              userId: userId,
              sessionId: sessionId,
            ) !=
            null) {
      throw AlreadyExistsError('Session with id $sessionId already exists.');
    }

    final SessionStateDelta deltas = extractStateDelta(state);

    if (deltas.app.isNotEmpty) {
      _appState
          .putIfAbsent(appName, () => <String, Object?>{})
          .addAll(deltas.app);
    }

    if (deltas.user.isNotEmpty) {
      _userState
          .putIfAbsent(appName, () => <String, Map<String, Object?>>{})
          .putIfAbsent(userId, () => <String, Object?>{})
          .addAll(deltas.user);
    }

    final String resolvedSessionId =
        (sessionId != null && sessionId.trim().isNotEmpty)
        ? sessionId.trim()
        : newAdkId(prefix: 'session_');

    final Session session = Session(
      id: resolvedSessionId,
      appName: appName,
      userId: userId,
      state: deltas.session,
      lastUpdateTime: DateTime.now().millisecondsSinceEpoch / 1000,
    );

    _sessions
            .putIfAbsent(appName, () => <String, Map<String, Session>>{})
            .putIfAbsent(userId, () => <String, Session>{})[resolvedSessionId] =
        session;

    return _mergeState(
      appName: appName,
      userId: userId,
      session: session.copyWith(),
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    final Session? session = _sessions[appName]?[userId]?[sessionId];
    if (session == null) {
      return null;
    }

    final Session copied = session.copyWith();

    if (config != null) {
      if (config.numRecentEvents != null && config.numRecentEvents! > 0) {
        final int count = config.numRecentEvents!;
        if (copied.events.length > count) {
          copied.events = copied.events.sublist(copied.events.length - count);
        }
      }

      if (config.afterTimestamp != null) {
        copied.events = copied.events
            .where((Event event) => event.timestamp >= config.afterTimestamp!)
            .toList();
      }
    }

    return _mergeState(appName: appName, userId: userId, session: copied);
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    final Map<String, Map<String, Session>>? appSessions = _sessions[appName];
    if (appSessions == null) {
      return ListSessionsResponse();
    }

    final List<Session> sessions = <Session>[];

    if (userId == null) {
      for (final MapEntry<String, Map<String, Session>> userEntry
          in appSessions.entries) {
        for (final Session session in userEntry.value.values) {
          final Session copied = session.copyWith(events: <Event>[]);
          sessions.add(
            _mergeState(
              appName: appName,
              userId: userEntry.key,
              session: copied,
            ),
          );
        }
      }
    } else {
      final Map<String, Session>? userSessions = appSessions[userId];
      if (userSessions == null) {
        return ListSessionsResponse();
      }

      for (final Session session in userSessions.values) {
        final Session copied = session.copyWith(events: <Event>[]);
        sessions.add(
          _mergeState(appName: appName, userId: userId, session: copied),
        );
      }
    }

    return ListSessionsResponse(sessions: sessions);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final Map<String, Session>? userSessions = _sessions[appName]?[userId];
    userSessions?.remove(sessionId);
  }

  @override
  Future<Event> appendEvent({
    required Session session,
    required Event event,
  }) async {
    if (event.partial == true) {
      return event;
    }

    final Session? stored =
        _sessions[session.appName]?[session.userId]?[session.id];
    if (stored == null) {
      return event;
    }

    final Event appended = await super.appendEvent(
      session: session,
      event: event,
    );
    session.lastUpdateTime = appended.timestamp;

    stored.events.add(appended.copyWith());
    stored.lastUpdateTime = appended.timestamp;

    if (appended.actions.stateDelta.isNotEmpty) {
      final SessionStateDelta delta = extractStateDelta(
        appended.actions.stateDelta,
      );

      if (delta.app.isNotEmpty) {
        _appState
            .putIfAbsent(session.appName, () => <String, Object?>{})
            .addAll(delta.app);
      }

      if (delta.user.isNotEmpty) {
        _userState
            .putIfAbsent(
              session.appName,
              () => <String, Map<String, Object?>>{},
            )
            .putIfAbsent(session.userId, () => <String, Object?>{})
            .addAll(delta.user);
      }

      if (delta.session.isNotEmpty) {
        stored.state.addAll(delta.session);
      }
    }

    return appended;
  }

  Session _mergeState({
    required String appName,
    required String userId,
    required Session session,
  }) {
    final Map<String, Object?>? appState = _appState[appName];
    if (appState != null) {
      appState.forEach((String key, Object? value) {
        session.state['${State.appPrefix}$key'] = value;
      });
    }

    final Map<String, Object?>? userState = _userState[appName]?[userId];
    if (userState != null) {
      userState.forEach((String key, Object? value) {
        session.state['${State.userPrefix}$key'] = value;
      });
    }

    return session;
  }
}
