/// URL-dispatched session service wrapper.
library;

import '../events/event.dart';
import 'base_session_service.dart';
import 'in_memory_session_service.dart';
import 'network_database_session_service.dart';
import 'session.dart';
import 'sqlite_session_service.dart';

/// Factory signature for creating session services from database URLs.
typedef DatabaseSessionServiceFactory =
    BaseSessionService Function(String dbUrl);

/// Resolver signature for dynamically resolving custom session services.
typedef DatabaseSessionServiceResolver =
    BaseSessionService? Function(String dbUrl);

/// Session service that dispatches to concrete implementations by URL scheme.
class DatabaseSessionService extends BaseSessionService {
  /// Creates a database-backed session service from [dbUrl].
  DatabaseSessionService(String dbUrl) : _delegate = _buildDelegate(dbUrl);

  final BaseSessionService _delegate;
  static final Map<String, DatabaseSessionServiceFactory> _customFactories =
      <String, DatabaseSessionServiceFactory>{};
  static final List<DatabaseSessionServiceResolver> _customResolvers =
      <DatabaseSessionServiceResolver>[];

  /// Registers a custom [factory] for a database URL [scheme].
  static void registerCustomFactory({
    required String scheme,
    required DatabaseSessionServiceFactory factory,
  }) {
    final String normalizedScheme = _normalizeScheme(scheme);
    _customFactories[normalizedScheme] = factory;
  }

  /// Unregisters a custom factory for [scheme].
  static bool unregisterCustomFactory(String scheme) {
    final String normalizedScheme = _normalizeScheme(scheme);
    return _customFactories.remove(normalizedScheme) != null;
  }

  /// Registers a custom URL [resolver].
  static void registerCustomResolver(DatabaseSessionServiceResolver resolver) {
    _customResolvers.add(resolver);
  }

  /// Unregisters a previously registered custom [resolver].
  static bool unregisterCustomResolver(
    DatabaseSessionServiceResolver resolver,
  ) {
    return _customResolvers.remove(resolver);
  }

  /// Clears all custom resolvers and factories, intended for tests.
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

    if (scheme != null && _isBuiltInNetworkScheme(scheme)) {
      return NetworkDatabaseSessionService(normalizedDbUrl);
    }

    throw UnsupportedError(
      'Unsupported database url: $normalizedDbUrl. '
      'Supported urls are sqlite:, sqlite+aiosqlite:, :memory:, memory:, '
      'postgresql://, postgres://, mysql://, and mariadb://. '
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
    final String rawScheme = dbUrl.substring(0, separatorIndex).toLowerCase();
    if (!rawScheme.contains('+')) {
      return rawScheme;
    }
    return rawScheme.split('+').first;
  }

  static bool _isBuiltInNetworkScheme(String scheme) {
    return scheme == 'postgresql' ||
        scheme == 'postgres' ||
        scheme == 'mysql' ||
        scheme == 'mariadb';
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
