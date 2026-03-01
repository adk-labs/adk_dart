import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mysql_client_plus/mysql_client_plus.dart' as mysql;
import 'package:postgres/postgres.dart' as pg;

import '../errors/already_exists_error.dart';
import '../events/event.dart';
import '../types/id.dart';
import 'base_session_service.dart';
import 'schemas/v1.dart' show decodeEventData, encodeEventData;
import 'session.dart';
import 'session_util.dart';
import 'state.dart';

const String _postgresCreateAppStatesTable = '''
CREATE TABLE IF NOT EXISTS app_states (
    app_name TEXT PRIMARY KEY,
    state TEXT NOT NULL,
    update_time DOUBLE PRECISION NOT NULL
);
''';

const String _postgresCreateUserStatesTable = '''
CREATE TABLE IF NOT EXISTS user_states (
    app_name TEXT NOT NULL,
    user_id TEXT NOT NULL,
    state TEXT NOT NULL,
    update_time DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (app_name, user_id)
);
''';

const String _postgresCreateSessionsTable = '''
CREATE TABLE IF NOT EXISTS sessions (
    app_name TEXT NOT NULL,
    user_id TEXT NOT NULL,
    id TEXT NOT NULL,
    state TEXT NOT NULL,
    create_time DOUBLE PRECISION NOT NULL,
    update_time DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (app_name, user_id, id)
);
''';

const String _postgresCreateEventsTable = '''
CREATE TABLE IF NOT EXISTS events (
    id TEXT NOT NULL,
    app_name TEXT NOT NULL,
    user_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    invocation_id TEXT NOT NULL,
    timestamp DOUBLE PRECISION NOT NULL,
    event_data TEXT NOT NULL,
    PRIMARY KEY (app_name, user_id, session_id, id),
    FOREIGN KEY (app_name, user_id, session_id)
      REFERENCES sessions(app_name, user_id, id)
      ON DELETE CASCADE
);
''';

const String _postgresCreateEventsLookupIndex = '''
CREATE INDEX IF NOT EXISTS idx_events_lookup
ON events (app_name, user_id, session_id, timestamp);
''';

const String _mysqlCreateAppStatesTable = '''
CREATE TABLE IF NOT EXISTS app_states (
    app_name VARCHAR(191) PRIMARY KEY,
    state LONGTEXT NOT NULL,
    update_time DOUBLE NOT NULL
) ENGINE=InnoDB;
''';

const String _mysqlCreateUserStatesTable = '''
CREATE TABLE IF NOT EXISTS user_states (
    app_name VARCHAR(191) NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    state LONGTEXT NOT NULL,
    update_time DOUBLE NOT NULL,
    PRIMARY KEY (app_name, user_id)
) ENGINE=InnoDB;
''';

const String _mysqlCreateSessionsTable = '''
CREATE TABLE IF NOT EXISTS sessions (
    app_name VARCHAR(191) NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    id VARCHAR(191) NOT NULL,
    state LONGTEXT NOT NULL,
    create_time DOUBLE NOT NULL,
    update_time DOUBLE NOT NULL,
    PRIMARY KEY (app_name, user_id, id)
) ENGINE=InnoDB;
''';

const String _mysqlCreateEventsTable = '''
CREATE TABLE IF NOT EXISTS events (
    id VARCHAR(191) NOT NULL,
    app_name VARCHAR(191) NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    session_id VARCHAR(191) NOT NULL,
    invocation_id VARCHAR(191) NOT NULL,
    timestamp DOUBLE NOT NULL,
    event_data LONGTEXT NOT NULL,
    PRIMARY KEY (app_name, user_id, session_id, id),
    CONSTRAINT fk_events_session
      FOREIGN KEY (app_name, user_id, session_id)
      REFERENCES sessions(app_name, user_id, id)
      ON DELETE CASCADE
) ENGINE=InnoDB;
''';

const String _mysqlCreateEventsLookupIndex = '''
CREATE INDEX idx_events_lookup
ON events (app_name, user_id, session_id, timestamp);
''';

enum _NetworkDriver { postgres, mysql }

class NetworkDatabaseSessionService extends BaseSessionService {
  NetworkDatabaseSessionService(String dbUrl)
    : _dbUrl = dbUrl.trim(),
      _normalizedDbUrl = _normalizeDbUrl(dbUrl.trim()),
      _driver = _parseDriver(_normalizeDbUrl(dbUrl.trim())) {
    if (_dbUrl.isEmpty) {
      throw ArgumentError('Database url must not be empty.');
    }
  }

  final String _dbUrl;
  final String _normalizedDbUrl;
  final _NetworkDriver _driver;

  pg.Connection? _postgresConnection;
  mysql.MySQLConnection? _mysqlConnection;

  Future<void>? _initialization;
  Future<void> _lock = Future<void>.value();

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) {
    return _withLock<Session>(() async {
      await _ensureInitialized();
      final SessionStateDelta deltas = extractStateDelta(state);
      final String resolvedSessionId =
          (sessionId != null && sessionId.trim().isNotEmpty)
          ? sessionId.trim()
          : newAdkId(prefix: 'session_');
      final double now = DateTime.now().millisecondsSinceEpoch / 1000;

      return _withTransaction<Session>((_NetworkDbExecutor db) async {
        final List<Map<String, Object?>> existing = await db.query(
          'SELECT 1 FROM sessions WHERE app_name=? AND user_id=? AND id=? LIMIT 1',
          <Object?>[appName, userId, resolvedSessionId],
        );
        if (existing.isNotEmpty) {
          throw AlreadyExistsError(
            'Session with id $resolvedSessionId already exists.',
          );
        }

        final Map<String, Object?> appStateBefore = await _getAppState(
          db: db,
          appName: appName,
        );
        final Map<String, Object?> userStateBefore = await _getUserState(
          db: db,
          appName: appName,
          userId: userId,
        );

        final Map<String, Object?> appStateAfter = _mergeJsonState(
          appStateBefore,
          deltas.app,
        );
        final Map<String, Object?> userStateAfter = _mergeJsonState(
          userStateBefore,
          deltas.user,
        );

        if (deltas.app.isNotEmpty) {
          await _upsertAppState(
            db: db,
            appName: appName,
            state: appStateAfter,
            updateTime: now,
          );
        }

        if (deltas.user.isNotEmpty) {
          await _upsertUserState(
            db: db,
            appName: appName,
            userId: userId,
            state: userStateAfter,
            updateTime: now,
          );
        }

        await db.execute(
          'INSERT INTO sessions (app_name, user_id, id, state, create_time, update_time) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          <Object?>[
            appName,
            userId,
            resolvedSessionId,
            jsonEncode(deltas.session),
            now,
            now,
          ],
        );

        return Session(
          id: resolvedSessionId,
          appName: appName,
          userId: userId,
          state: _mergeState(
            appState: appStateAfter,
            userState: userStateAfter,
            sessionState: deltas.session,
          ),
          events: <Event>[],
          lastUpdateTime: now,
        );
      });
    });
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) {
    return _withLock<Session?>(() async {
      await _ensureInitialized();

      return _withExecutor<Session?>((_NetworkDbExecutor db) async {
        final List<Map<String, Object?>> sessionRows = await db.query(
          'SELECT state, update_time '
          'FROM sessions '
          'WHERE app_name=? AND user_id=? AND id=?',
          <Object?>[appName, userId, sessionId],
        );
        if (sessionRows.isEmpty) {
          return null;
        }

        final Map<String, Object?> sessionState = _decodeJsonMap(
          sessionRows.first['state'],
        );

        final bool hasAfterTimestamp = config?.afterTimestamp != null;
        final int? recentLimit = config?.numRecentEvents;
        final bool hasLimit = recentLimit != null && recentLimit > 0;
        final List<Object?> parameters = <Object?>[appName, userId, sessionId];
        final StringBuffer eventQuery = StringBuffer(
          'SELECT id, invocation_id, timestamp, event_data '
          'FROM events '
          'WHERE app_name=? AND user_id=? AND session_id=?',
        );
        if (hasAfterTimestamp) {
          eventQuery.write(' AND timestamp > ?');
          parameters.add(config!.afterTimestamp);
        }
        eventQuery.write(
          hasLimit ? ' ORDER BY timestamp DESC' : ' ORDER BY timestamp ASC',
        );
        if (hasLimit) {
          eventQuery.write(' LIMIT $recentLimit');
        }

        final List<Map<String, Object?>> eventRows = await db.query(
          eventQuery.toString(),
          parameters,
        );
        if (hasLimit) {
          eventRows.sort(
            (Map<String, Object?> a, Map<String, Object?> b) =>
                _asDouble(a['timestamp']).compareTo(_asDouble(b['timestamp'])),
          );
        }
        final List<Event> events = eventRows
            .map(
              (Map<String, Object?> row) => decodeEventData(
                _decodeJsonMap(row['event_data']),
                id: '${row['id'] ?? ''}',
                invocationId: '${row['invocation_id'] ?? ''}',
                timestamp: _asDouble(row['timestamp']),
              ),
            )
            .toList(growable: false);

        final Map<String, Object?> appState = await _getAppState(
          db: db,
          appName: appName,
        );
        final Map<String, Object?> userState = await _getUserState(
          db: db,
          appName: appName,
          userId: userId,
        );

        return Session(
          id: sessionId,
          appName: appName,
          userId: userId,
          state: _mergeState(
            appState: appState,
            userState: userState,
            sessionState: sessionState,
          ),
          events: events,
          lastUpdateTime: _asDouble(sessionRows.first['update_time']),
        );
      });
    });
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) {
    return _withLock<ListSessionsResponse>(() async {
      await _ensureInitialized();

      return _withExecutor<ListSessionsResponse>((_NetworkDbExecutor db) async {
        final List<Object?> parameters = <Object?>[appName];
        final StringBuffer sessionQuery = StringBuffer(
          'SELECT id, user_id, state, update_time '
          'FROM sessions '
          'WHERE app_name=?',
        );
        if (userId != null) {
          sessionQuery.write(' AND user_id=?');
          parameters.add(userId);
        }
        sessionQuery.write(' ORDER BY update_time DESC');

        final List<Map<String, Object?>> sessionRows = await db.query(
          sessionQuery.toString(),
          parameters,
        );
        if (sessionRows.isEmpty) {
          return ListSessionsResponse(sessions: <Session>[]);
        }

        final Map<String, Object?> appState = await _getAppState(
          db: db,
          appName: appName,
        );

        final List<Object?> userStateParameters = <Object?>[appName];
        final StringBuffer userStateQuery = StringBuffer(
          'SELECT user_id, state FROM user_states WHERE app_name=?',
        );
        if (userId != null) {
          userStateQuery.write(' AND user_id=?');
          userStateParameters.add(userId);
        }

        final List<Map<String, Object?>> userRows = await db.query(
          userStateQuery.toString(),
          userStateParameters,
        );
        final Map<String, Map<String, Object?>> userStates =
            <String, Map<String, Object?>>{};
        for (final Map<String, Object?> row in userRows) {
          final String rowUserId = '${row['user_id'] ?? ''}';
          userStates[rowUserId] = _decodeJsonMap(row['state']);
        }

        final List<Session> sessions = sessionRows
            .map((Map<String, Object?> row) {
              final String rowUserId = '${row['user_id'] ?? ''}';
              final Map<String, Object?> sessionState = _decodeJsonMap(
                row['state'],
              );
              return Session(
                id: '${row['id'] ?? ''}',
                appName: appName,
                userId: rowUserId,
                state: _mergeState(
                  appState: appState,
                  userState: userStates[rowUserId] ?? <String, Object?>{},
                  sessionState: sessionState,
                ),
                events: <Event>[],
                lastUpdateTime: _asDouble(row['update_time']),
              );
            })
            .toList(growable: false);

        return ListSessionsResponse(sessions: sessions);
      });
    });
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) {
    return _withLock<void>(() async {
      await _ensureInitialized();
      await _withExecutor<void>((_NetworkDbExecutor db) {
        return db.execute(
          'DELETE FROM sessions WHERE app_name=? AND user_id=? AND id=?',
          <Object?>[appName, userId, sessionId],
        );
      });
    });
  }

  @override
  Future<Event> appendEvent({required Session session, required Event event}) {
    return _withLock<Event>(() async {
      await _ensureInitialized();
      if (event.partial == true) {
        return event;
      }

      _trimTempDeltaState(event);
      final SessionStateDelta delta = extractStateDelta(
        event.actions.stateDelta,
      );

      await _withTransaction<void>((_NetworkDbExecutor db) async {
        final List<Map<String, Object?>> rows = await db.query(
          'SELECT state, update_time '
          'FROM sessions '
          'WHERE app_name=? AND user_id=? AND id=? '
          'FOR UPDATE',
          <Object?>[session.appName, session.userId, session.id],
        );
        if (rows.isEmpty) {
          throw StateError('Session ${session.id} not found.');
        }

        final double storedLastUpdateTime = _asDouble(
          rows.first['update_time'],
        );
        if (storedLastUpdateTime > session.lastUpdateTime) {
          throw StateError(
            'The provided session has stale lastUpdateTime. Reload the session and retry.',
          );
        }

        if (delta.app.isNotEmpty) {
          final Map<String, Object?> current = await _getAppState(
            db: db,
            appName: session.appName,
          );
          await _upsertAppState(
            db: db,
            appName: session.appName,
            state: _mergeJsonState(current, delta.app),
            updateTime: event.timestamp,
          );
        }

        if (delta.user.isNotEmpty) {
          final Map<String, Object?> current = await _getUserState(
            db: db,
            appName: session.appName,
            userId: session.userId,
          );
          await _upsertUserState(
            db: db,
            appName: session.appName,
            userId: session.userId,
            state: _mergeJsonState(current, delta.user),
            updateTime: event.timestamp,
          );
        }

        final Map<String, Object?> sessionState = _mergeJsonState(
          _decodeJsonMap(rows.first['state']),
          delta.session,
        );
        await db.execute(
          'UPDATE sessions '
          'SET state=?, update_time=? '
          'WHERE app_name=? AND user_id=? AND id=?',
          <Object?>[
            jsonEncode(sessionState),
            event.timestamp,
            session.appName,
            session.userId,
            session.id,
          ],
        );

        await db.execute(
          'INSERT INTO events '
          '(id, app_name, user_id, session_id, invocation_id, timestamp, event_data) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            event.id,
            session.appName,
            session.userId,
            session.id,
            event.invocationId,
            event.timestamp,
            jsonEncode(encodeEventData(event)),
          ],
        );
      });

      session.lastUpdateTime = event.timestamp;
      return super.appendEvent(session: session, event: event);
    });
  }

  Future<void> _ensureInitialized() {
    _initialization ??= _initialize();
    return _initialization!;
  }

  Future<void> _initialize() async {
    try {
      if (_driver == _NetworkDriver.postgres) {
        _postgresConnection = await pg.Connection.openFromUrl(_normalizedDbUrl);
        final _PostgresExecutor db = _PostgresExecutor(_postgresConnection!);
        await db.execute(_postgresCreateAppStatesTable);
        await db.execute(_postgresCreateUserStatesTable);
        await db.execute(_postgresCreateSessionsTable);
        await db.execute(_postgresCreateEventsTable);
        await db.execute(_postgresCreateEventsLookupIndex);
      } else {
        _mysqlConnection = await _openMysqlConnection(_normalizedDbUrl);
        final _MySqlExecutor db = _MySqlExecutor(_mysqlConnection!);
        await db.execute(_mysqlCreateAppStatesTable);
        await db.execute(_mysqlCreateUserStatesTable);
        await db.execute(_mysqlCreateSessionsTable);
        await db.execute(_mysqlCreateEventsTable);
        try {
          await db.execute(_mysqlCreateEventsLookupIndex);
        } catch (_) {
          // MySQL has no IF NOT EXISTS for CREATE INDEX in some versions.
        }
      }
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<T> _withTransaction<T>(
    Future<T> Function(_NetworkDbExecutor db) action,
  ) async {
    if (_driver == _NetworkDriver.postgres) {
      final pg.Connection connection = _postgresConnection!;
      return connection.runTx((pg.TxSession tx) {
        return action(_PostgresExecutor(tx));
      });
    }

    final mysql.MySQLConnection connection = _mysqlConnection!;
    return connection.transactional<T>((mysql.MySQLConnection tx) {
      return action(_MySqlExecutor(tx));
    });
  }

  Future<T> _withExecutor<T>(Future<T> Function(_NetworkDbExecutor db) action) {
    if (_driver == _NetworkDriver.postgres) {
      return action(_PostgresExecutor(_postgresConnection!));
    }
    return action(_MySqlExecutor(_mysqlConnection!));
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final Completer<void> next = Completer<void>();
    final Future<void> previous = _lock;
    _lock = next.future;
    try {
      await previous;
      return await action();
    } finally {
      next.complete();
    }
  }

  Future<Map<String, Object?>> _getAppState({
    required _NetworkDbExecutor db,
    required String appName,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT state FROM app_states WHERE app_name=?',
      <Object?>[appName],
    );
    if (rows.isEmpty) {
      return <String, Object?>{};
    }
    return _decodeJsonMap(rows.first['state']);
  }

  Future<Map<String, Object?>> _getUserState({
    required _NetworkDbExecutor db,
    required String appName,
    required String userId,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT state FROM user_states WHERE app_name=? AND user_id=?',
      <Object?>[appName, userId],
    );
    if (rows.isEmpty) {
      return <String, Object?>{};
    }
    return _decodeJsonMap(rows.first['state']);
  }

  Future<void> _upsertAppState({
    required _NetworkDbExecutor db,
    required String appName,
    required Map<String, Object?> state,
    required double updateTime,
  }) async {
    if (_driver == _NetworkDriver.postgres) {
      await db.execute(
        'INSERT INTO app_states (app_name, state, update_time) '
        'VALUES (?, ?, ?) '
        'ON CONFLICT (app_name) DO UPDATE '
        'SET state=EXCLUDED.state, update_time=EXCLUDED.update_time',
        <Object?>[appName, jsonEncode(state), updateTime],
      );
      return;
    }

    await db.execute(
      'INSERT INTO app_states (app_name, state, update_time) '
      'VALUES (?, ?, ?) '
      'ON DUPLICATE KEY UPDATE '
      'state=VALUES(state), update_time=VALUES(update_time)',
      <Object?>[appName, jsonEncode(state), updateTime],
    );
  }

  Future<void> _upsertUserState({
    required _NetworkDbExecutor db,
    required String appName,
    required String userId,
    required Map<String, Object?> state,
    required double updateTime,
  }) async {
    if (_driver == _NetworkDriver.postgres) {
      await db.execute(
        'INSERT INTO user_states (app_name, user_id, state, update_time) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT (app_name, user_id) DO UPDATE '
        'SET state=EXCLUDED.state, update_time=EXCLUDED.update_time',
        <Object?>[appName, userId, jsonEncode(state), updateTime],
      );
      return;
    }

    await db.execute(
      'INSERT INTO user_states (app_name, user_id, state, update_time) '
      'VALUES (?, ?, ?, ?) '
      'ON DUPLICATE KEY UPDATE '
      'state=VALUES(state), update_time=VALUES(update_time)',
      <Object?>[appName, userId, jsonEncode(state), updateTime],
    );
  }

  void _trimTempDeltaState(Event event) {
    if (event.actions.stateDelta.isEmpty) {
      return;
    }
    event.actions.stateDelta.removeWhere(
      (String key, Object? _) => key.startsWith(State.tempPrefix),
    );
  }
}

abstract class _NetworkDbExecutor {
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]);

  Future<void> execute(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]);
}

class _PostgresExecutor implements _NetworkDbExecutor {
  _PostgresExecutor(this._session);

  final pg.Session _session;

  @override
  Future<void> execute(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    await _session.execute(
      pg.Sql.indexed(sql, substitution: '?'),
      parameters: parameters,
    );
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    final pg.Result result = await _session.execute(
      pg.Sql.indexed(sql, substitution: '?'),
      parameters: parameters,
    );
    return result
        .map((pg.ResultRow row) => _castMap(row.toColumnMap()))
        .toList(growable: false);
  }
}

class _MySqlExecutor implements _NetworkDbExecutor {
  _MySqlExecutor(this._connection);

  final mysql.MySQLConnection _connection;

  @override
  Future<void> execute(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    final (String query, Map<String, dynamic>? queryParams) =
        _toMysqlNamedParams(sql, parameters);
    await _connection.execute(query, queryParams);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) async {
    final (String query, Map<String, dynamic>? queryParams) =
        _toMysqlNamedParams(sql, parameters);
    final mysql.IResultSet result = await _connection.execute(
      query,
      queryParams,
    );
    return result.rows
        .map((mysql.ResultSetRow row) => _castMap(row.typedAssoc()))
        .toList(growable: false);
  }
}

Future<mysql.MySQLConnection> _openMysqlConnection(String dbUrl) async {
  final Uri uri = Uri.parse(dbUrl);
  final String databaseName = _extractMysqlDatabaseName(uri.path, dbUrl);
  final (String? user, String? password) = _parseUserInfo(uri.userInfo);
  final Duration timeout = Duration(
    seconds: _parsePositiveInt(uri.queryParameters['connect_timeout']) ?? 30,
  );
  final bool secure = _parseMysqlSecure(uri);
  final bool secureExplicitlyDisabled = _isMysqlSecureExplicitlyDisabled(uri);
  final _MysqlTlsOptions tlsOptions = _parseMysqlTlsOptions(uri);
  final String host = uri.host.isEmpty ? 'localhost' : uri.host;
  final int port = uri.hasPort ? uri.port : 3306;
  final String userName = user ?? '';
  final String resolvedPassword = password ?? '';

  try {
    return await _connectMysql(
      host: host,
      port: port,
      userName: userName,
      password: resolvedPassword,
      databaseName: databaseName,
      secure: secure,
      timeout: timeout,
      tlsOptions: tlsOptions,
    );
  } catch (error) {
    if (!secure &&
        !secureExplicitlyDisabled &&
        _shouldRetryMysqlWithSecure(error)) {
      return await _connectMysql(
        host: host,
        port: port,
        userName: userName,
        password: resolvedPassword,
        databaseName: databaseName,
        secure: true,
        timeout: timeout,
        tlsOptions: tlsOptions,
      );
    }
    rethrow;
  }
}

String _extractMysqlDatabaseName(String path, String dbUrl) {
  String normalized = path;
  if (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      dbUrl,
      'dbUrl',
      'MySQL URL must include a database name path.',
    );
  }
  return Uri.decodeComponent(normalized);
}

(String?, String?) _parseUserInfo(String userInfo) {
  if (userInfo.isEmpty) {
    return (null, null);
  }
  final int separator = userInfo.indexOf(':');
  if (separator < 0) {
    return (Uri.decodeComponent(userInfo), null);
  }
  final String user = userInfo.substring(0, separator);
  final String password = userInfo.substring(separator + 1);
  return (Uri.decodeComponent(user), Uri.decodeComponent(password));
}

int? _parsePositiveInt(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final int? parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) {
    return null;
  }
  return parsed;
}

bool _parseMysqlSecure(Uri uri) {
  final String? sslMode = uri.queryParameters['sslmode']?.trim().toLowerCase();
  if (sslMode != null) {
    switch (sslMode) {
      case 'disable':
      case 'disabled':
        return false;
      case 'require':
      case 'verify_ca':
      case 'verify_identity':
        return true;
    }
  }

  final bool? secure =
      _parseOptionalBool(uri.queryParameters['secure']) ??
      _parseOptionalBool(uri.queryParameters['ssl']) ??
      _parseOptionalBool(uri.queryParameters['tls']);
  // Keep compatibility with prior plain-connection behavior unless TLS is explicit.
  return secure ?? false;
}

bool _isMysqlSecureExplicitlyDisabled(Uri uri) {
  final String? sslMode = uri.queryParameters['sslmode']?.trim().toLowerCase();
  if (sslMode == 'disable' || sslMode == 'disabled') {
    return true;
  }

  final bool? secure =
      _parseOptionalBool(uri.queryParameters['secure']) ??
      _parseOptionalBool(uri.queryParameters['ssl']) ??
      _parseOptionalBool(uri.queryParameters['tls']);
  return secure == false;
}

bool? _parseOptionalBool(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  switch (value.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
    case 'require':
      return true;
    case '0':
    case 'false':
    case 'no':
    case 'off':
    case 'disable':
    case 'disabled':
      return false;
  }
  return null;
}

_MysqlTlsOptions _parseMysqlTlsOptions(Uri uri) {
  final String? caFile = _firstNonEmptyQueryParameter(uri, <String>[
    'ssl_ca_file',
    'tls_ca_file',
    'ca_file',
  ]);
  final String? certFile = _firstNonEmptyQueryParameter(uri, <String>[
    'ssl_cert_file',
    'tls_cert_file',
    'client_cert_file',
  ]);
  final String? keyFile = _firstNonEmptyQueryParameter(uri, <String>[
    'ssl_key_file',
    'tls_key_file',
    'client_key_file',
  ]);
  final String? certPassword = _firstNonEmptyQueryParameter(uri, <String>[
    'ssl_cert_password',
    'tls_cert_password',
  ]);
  final String? keyPassword = _firstNonEmptyQueryParameter(uri, <String>[
    'ssl_key_password',
    'tls_key_password',
  ]);

  SecurityContext? securityContext;
  if (caFile != null || certFile != null || keyFile != null) {
    securityContext = SecurityContext(withTrustedRoots: true);
  }

  if (caFile != null) {
    _requireExistingFile(caFile, parameterName: 'ssl_ca_file');
    securityContext!.setTrustedCertificates(caFile);
  }

  if ((certFile == null) != (keyFile == null)) {
    throw ArgumentError(
      'MySQL TLS client auth requires both ssl_cert_file and ssl_key_file.',
    );
  }

  if (certFile != null && keyFile != null) {
    _requireExistingFile(certFile, parameterName: 'ssl_cert_file');
    _requireExistingFile(keyFile, parameterName: 'ssl_key_file');
    securityContext!.useCertificateChain(certFile, password: certPassword);
    securityContext.usePrivateKey(keyFile, password: keyPassword);
  }

  final bool verifyPeer =
      _parseOptionalBool(uri.queryParameters['ssl_verify']) ??
      _parseOptionalBool(uri.queryParameters['tls_verify']) ??
      true;
  final bool Function(X509Certificate cert)? onBadCertificate = verifyPeer
      ? null
      : (X509Certificate _) => true;

  return _MysqlTlsOptions(
    securityContext: securityContext,
    onBadCertificate: onBadCertificate,
  );
}

String? _firstNonEmptyQueryParameter(Uri uri, List<String> keys) {
  for (final String key in keys) {
    final String? value = uri.queryParameters[key];
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

void _requireExistingFile(String path, {required String parameterName}) {
  if (!File(path).existsSync()) {
    throw ArgumentError.value(path, parameterName, 'TLS file does not exist.');
  }
}

Future<mysql.MySQLConnection> _connectMysql({
  required String host,
  required int port,
  required String userName,
  required String password,
  required String databaseName,
  required bool secure,
  required Duration timeout,
  required _MysqlTlsOptions tlsOptions,
}) async {
  final mysql.MySQLConnection connection =
      await mysql.MySQLConnection.createConnection(
        host: host,
        port: port,
        userName: userName,
        password: password,
        secure: secure,
        databaseName: databaseName,
        securityContext: tlsOptions.securityContext,
        onBadCertificate: tlsOptions.onBadCertificate,
      );
  await connection.connect(timeoutMs: timeout.inMilliseconds);
  return connection;
}

bool _shouldRetryMysqlWithSecure(Object error) {
  final String message = '$error'.toLowerCase();
  return message.contains('supported only with secure connections');
}

class _MysqlTlsOptions {
  const _MysqlTlsOptions({
    required this.securityContext,
    required this.onBadCertificate,
  });

  final SecurityContext? securityContext;
  final bool Function(X509Certificate cert)? onBadCertificate;
}

(String, Map<String, dynamic>?) _toMysqlNamedParams(
  String sql,
  List<Object?> parameters,
) {
  if (parameters.isEmpty) {
    return (sql, null);
  }

  final StringBuffer transformed = StringBuffer();
  final Map<String, dynamic> named = <String, dynamic>{};
  int parameterIndex = 0;
  bool inSingleQuote = false;
  bool inDoubleQuote = false;
  bool escaped = false;

  for (int index = 0; index < sql.length; index++) {
    final String char = sql[index];

    if (escaped) {
      transformed.write(char);
      escaped = false;
      continue;
    }

    if ((inSingleQuote || inDoubleQuote) && char == r'\') {
      transformed.write(char);
      escaped = true;
      continue;
    }

    if (!inDoubleQuote && char == "'") {
      inSingleQuote = !inSingleQuote;
      transformed.write(char);
      continue;
    }

    if (!inSingleQuote && char == '"') {
      inDoubleQuote = !inDoubleQuote;
      transformed.write(char);
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && char == '?') {
      if (parameterIndex >= parameters.length) {
        throw ArgumentError('SQL has more placeholders than bound parameters.');
      }
      final String key = 'p$parameterIndex';
      transformed.write(':$key');
      named[key] = parameters[parameterIndex];
      parameterIndex++;
      continue;
    }

    transformed.write(char);
  }

  if (parameterIndex != parameters.length) {
    throw ArgumentError(
      'SQL has fewer placeholders ($parameterIndex) than parameters (${parameters.length}).',
    );
  }

  return (transformed.toString(), named);
}

String _normalizeDbUrl(String dbUrl) {
  final String trimmed = dbUrl.trim();
  final int separator = trimmed.indexOf('://');
  if (separator <= 0) {
    return trimmed;
  }
  final String scheme = trimmed.substring(0, separator);
  if (!scheme.contains('+')) {
    return trimmed;
  }
  final String normalizedScheme = scheme.split('+').first;
  return '$normalizedScheme${trimmed.substring(separator)}';
}

_NetworkDriver _parseDriver(String normalizedDbUrl) {
  final Uri uri = Uri.parse(normalizedDbUrl);
  final String scheme = uri.scheme.toLowerCase();
  if (scheme == 'postgresql' || scheme == 'postgres') {
    return _NetworkDriver.postgres;
  }
  if (scheme == 'mysql' || scheme == 'mariadb') {
    return _NetworkDriver.mysql;
  }
  throw UnsupportedError(
    'Unsupported network database scheme in URL: $normalizedDbUrl',
  );
}

Map<String, Object?> _decodeJsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return _castMap(value);
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map) {
        return _castMap(decoded);
      }
    } catch (_) {
      return <String, Object?>{};
    }
  }
  return <String, Object?>{};
}

Map<String, Object?> _castMap(Map value) {
  return value.map((Object? key, Object? item) => MapEntry('$key', item));
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0.0;
  }
  return 0.0;
}

Map<String, Object?> _mergeState({
  required Map<String, Object?> appState,
  required Map<String, Object?> userState,
  required Map<String, Object?> sessionState,
}) {
  final Map<String, Object?> merged = Map<String, Object?>.from(sessionState);
  appState.forEach((String key, Object? value) {
    merged['${State.appPrefix}$key'] = value;
  });
  userState.forEach((String key, Object? value) {
    merged['${State.userPrefix}$key'] = value;
  });
  return merged;
}

Map<String, Object?> _mergeJsonState(
  Map<String, Object?> base,
  Map<String, Object?> delta,
) {
  if (delta.isEmpty) {
    return Map<String, Object?>.from(base);
  }
  final Map<String, Object?> merged = Map<String, Object?>.from(base);
  delta.forEach((String key, Object? value) {
    merged[key] = value;
  });
  return merged;
}
