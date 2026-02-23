import 'dart:convert';

import '../events/event.dart';
import 'base_session_service.dart';
import 'in_memory_session_service.dart';
import 'session.dart';
import 'sqlite_session_service.dart';

class DatabaseSessionService extends BaseSessionService {
  DatabaseSessionService(String dbUrl) : _delegate = _buildDelegate(dbUrl);

  final BaseSessionService _delegate;

  static BaseSessionService _buildDelegate(String dbUrl) {
    if (dbUrl.trim().isEmpty) {
      throw ArgumentError('Database url must not be empty.');
    }
    if (dbUrl.startsWith('sqlite:') || dbUrl.startsWith('sqlite+aiosqlite:')) {
      return SqliteSessionService(dbUrl);
    }
    if (dbUrl == ':memory:' || dbUrl.startsWith('memory:')) {
      return InMemorySessionService();
    }
    final String encoded = base64Url
        .encode(utf8.encode(dbUrl))
        .replaceAll('=', '');
    return SqliteSessionService('.adk/session_dbs/$encoded.json');
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) {
    return _delegate.createSession(
      appName: appName,
      userId: userId,
      state: state,
      sessionId: sessionId,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) {
    return _delegate.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      config: config,
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) {
    return _delegate.listSessions(appName: appName, userId: userId);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) {
    return _delegate.deleteSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  @override
  Future<Event> appendEvent({required Session session, required Event event}) {
    return _delegate.appendEvent(session: session, event: event);
  }
}
