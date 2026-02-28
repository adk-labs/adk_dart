import '../events/event.dart';
import 'base_session_service.dart';
import 'in_memory_session_service.dart';
import 'session.dart';
import 'sqlite_session_service.dart';

typedef DatabaseSessionServiceFactory =
    BaseSessionService Function(String dbUrl);

typedef DatabaseSessionServiceResolver =
    BaseSessionService? Function(String dbUrl);

class DatabaseSessionService extends BaseSessionService {
  DatabaseSessionService(String dbUrl) : _delegate = _buildDelegate(dbUrl);

  final BaseSessionService _delegate;
  static final Map<String, DatabaseSessionServiceFactory> _customFactories =
      <String, DatabaseSessionServiceFactory>{};
  static final List<DatabaseSessionServiceResolver> _customResolvers =
      <DatabaseSessionServiceResolver>[];

  static void registerCustomFactory({
    required String scheme,
    required DatabaseSessionServiceFactory factory,
  }) {
    final String normalizedScheme = _normalizeScheme(scheme);
    _customFactories[normalizedScheme] = factory;
  }

  static bool unregisterCustomFactory(String scheme) {
    final String normalizedScheme = _normalizeScheme(scheme);
    return _customFactories.remove(normalizedScheme) != null;
  }

  static void registerCustomResolver(DatabaseSessionServiceResolver resolver) {
    _customResolvers.add(resolver);
  }

  static bool unregisterCustomResolver(
    DatabaseSessionServiceResolver resolver,
  ) {
    return _customResolvers.remove(resolver);
  }

  static void resetCustomResolversAndFactories() {
    _customFactories.clear();
    _customResolvers.clear();
  }

  static BaseSessionService _buildDelegate(String dbUrl) {
    final String normalizedDbUrl = dbUrl.trim();
    if (normalizedDbUrl.isEmpty) {
      throw ArgumentError('Database url must not be empty.');
    }
    if (normalizedDbUrl.startsWith('sqlite:') ||
        normalizedDbUrl.startsWith('sqlite+aiosqlite:')) {
      return SqliteSessionService(normalizedDbUrl);
    }
    if (normalizedDbUrl == ':memory:' ||
        normalizedDbUrl.startsWith('memory:')) {
      return InMemorySessionService();
    }

    final String? scheme = _extractScheme(normalizedDbUrl);
    if (scheme != null) {
      final DatabaseSessionServiceFactory? factory = _customFactories[scheme];
      if (factory != null) {
        return factory(normalizedDbUrl);
      }
    }

    for (final DatabaseSessionServiceResolver resolver
        in _customResolvers.reversed) {
      final BaseSessionService? resolved = resolver(normalizedDbUrl);
      if (resolved != null) {
        return resolved;
      }
    }

    throw UnsupportedError(
      'Unsupported database url: $normalizedDbUrl. '
      'Supported urls are sqlite:, sqlite+aiosqlite:, :memory:, and memory:. '
      'Register custom non-sqlite handling via '
      'registerCustomFactory(...) or registerCustomResolver(...).',
    );
  }

  static String _normalizeScheme(String scheme) {
    final String normalized = scheme.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw ArgumentError('Database scheme must not be empty.');
    }
    if (normalized.contains(':')) {
      throw ArgumentError('Database scheme must not include ":"; got: $scheme');
    }
    return normalized;
  }

  static String? _extractScheme(String dbUrl) {
    final int separatorIndex = dbUrl.indexOf(':');
    if (separatorIndex <= 0) {
      return null;
    }
    return dbUrl.substring(0, separatorIndex).toLowerCase();
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
