import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../errors/already_exists_error.dart';
import '../events/event.dart';
import '../events/event_actions.dart';
import '../types/content.dart';
import '../types/id.dart';
import 'base_session_service.dart';
import 'session.dart';
import 'session_util.dart';
import 'state.dart';

const String _appStatesTableSchema = '''
CREATE TABLE IF NOT EXISTS app_states (
    app_name TEXT PRIMARY KEY,
    state TEXT NOT NULL,
    update_time REAL NOT NULL
);
''';

const String _userStatesTableSchema = '''
CREATE TABLE IF NOT EXISTS user_states (
    app_name TEXT NOT NULL,
    user_id TEXT NOT NULL,
    state TEXT NOT NULL,
    update_time REAL NOT NULL,
    PRIMARY KEY (app_name, user_id)
);
''';

const String _sessionsTableSchema = '''
CREATE TABLE IF NOT EXISTS sessions (
    app_name TEXT NOT NULL,
    user_id TEXT NOT NULL,
    id TEXT NOT NULL,
    state TEXT NOT NULL,
    create_time REAL NOT NULL,
    update_time REAL NOT NULL,
    PRIMARY KEY (app_name, user_id, id)
);
''';

const String _eventsTableSchema = '''
CREATE TABLE IF NOT EXISTS events (
    id TEXT NOT NULL,
    app_name TEXT NOT NULL,
    user_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    invocation_id TEXT NOT NULL,
    timestamp REAL NOT NULL,
    event_data TEXT NOT NULL,
    PRIMARY KEY (app_name, user_id, session_id, id),
    FOREIGN KEY (app_name, user_id, session_id) REFERENCES sessions(app_name, user_id, id) ON DELETE CASCADE
);
''';

class SqliteSessionService extends BaseSessionService {
  SqliteSessionService(String dbPath) : this._(_resolveStorePath(dbPath));

  SqliteSessionService._(_ResolvedStorePath resolved)
    : _storePath = resolved.path,
      _connectPath = resolved.connectPath,
      _connectAsUri = resolved.connectUri,
      _readOnly = resolved.readOnly,
      _inMemory = resolved.inMemory;

  final String _storePath;
  final String _connectPath;
  final bool _connectAsUri;
  final bool _readOnly;
  final bool _inMemory;

  _SqliteDatabase? _memoryDatabase;
  Future<void> _lock = Future<void>.value();

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) {
    return _withLock<Session>(() async {
      final String resolvedSessionId =
          (sessionId != null && sessionId.trim().isNotEmpty)
          ? sessionId.trim()
          : newAdkId(prefix: 'session_');
      final SessionStateDelta deltas = extractStateDelta(state);
      final double now = DateTime.now().millisecondsSinceEpoch / 1000;

      return _withDatabase<Session>((_SqliteDatabase db) {
        final List<Map<String, Object?>> existing = db.query(
          'SELECT 1 FROM sessions WHERE app_name=? AND user_id=? AND id=? LIMIT 1',
          <Object?>[appName, userId, resolvedSessionId],
        );
        if (existing.isNotEmpty) {
          throw AlreadyExistsError(
            'Session with id $resolvedSessionId already exists.',
          );
        }

        _runTransaction(db, () {
          if (deltas.app.isNotEmpty) {
            _upsertAppState(
              db,
              appName: appName,
              delta: deltas.app,
              updateTime: now,
            );
          }
          if (deltas.user.isNotEmpty) {
            _upsertUserState(
              db,
              appName: appName,
              userId: userId,
              delta: deltas.user,
              updateTime: now,
            );
          }

          db.execute(
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
        });

        final Map<String, Object?> appState = _getAppState(db, appName);
        final Map<String, Object?> userState = _getUserState(
          db,
          appName,
          userId,
        );

        return Session(
          id: resolvedSessionId,
          appName: appName,
          userId: userId,
          state: _mergeState(
            appState: appState,
            userState: userState,
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
      return _withDatabase<Session?>((_SqliteDatabase db) {
        final List<Map<String, Object?>> rows = db.query(
          'SELECT state, update_time FROM sessions WHERE app_name=? AND user_id=? AND id=?',
          <Object?>[appName, userId, sessionId],
        );
        if (rows.isEmpty) {
          return null;
        }

        final Map<String, Object?> sessionState = _decodeJsonMap(
          rows.first['state'],
        );
        final double lastUpdateTime = _asDouble(rows.first['update_time']);

        final List<Object?> eventParams = <Object?>[appName, userId, sessionId];
        final StringBuffer eventQuery = StringBuffer(
          'SELECT event_data FROM events '
          'WHERE app_name=? AND user_id=? AND session_id=?',
        );
        if (config?.afterTimestamp != null) {
          eventQuery.write(' AND timestamp >= ?');
          eventParams.add(config!.afterTimestamp);
        }
        eventQuery.write(' ORDER BY timestamp DESC');
        if (config?.numRecentEvents != null && config!.numRecentEvents! > 0) {
          eventQuery.write(' LIMIT ?');
          eventParams.add(config.numRecentEvents);
        }

        final List<Map<String, Object?>> eventRows = db.query(
          eventQuery.toString(),
          eventParams,
        );

        final List<Event> events = eventRows.reversed
            .map(
              (Map<String, Object?> row) =>
                  _eventFromJson(_decodeJsonMap(row['event_data'])),
            )
            .toList();

        final Map<String, Object?> appState = _getAppState(db, appName);
        final Map<String, Object?> userState = _getUserState(
          db,
          appName,
          userId,
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
          lastUpdateTime: lastUpdateTime,
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
      return _withDatabase<ListSessionsResponse>((_SqliteDatabase db) {
        final List<Map<String, Object?>> rows = userId == null
            ? db.query(
                'SELECT id, user_id, state, update_time FROM sessions WHERE app_name=?',
                <Object?>[appName],
              )
            : db.query(
                'SELECT id, user_id, state, update_time FROM sessions '
                'WHERE app_name=? AND user_id=?',
                <Object?>[appName, userId],
              );

        final Map<String, Object?> appState = _getAppState(db, appName);
        final Map<String, Map<String, Object?>> userStates =
            <String, Map<String, Object?>>{};

        if (userId != null) {
          userStates[userId] = _getUserState(db, appName, userId);
        } else {
          final List<Map<String, Object?>> userRows = db.query(
            'SELECT user_id, state FROM user_states WHERE app_name=?',
            <Object?>[appName],
          );
          for (final Map<String, Object?> row in userRows) {
            final String rowUserId = (row['user_id'] ?? '') as String;
            userStates[rowUserId] = _decodeJsonMap(row['state']);
          }
        }

        final List<Session> sessions = rows
            .map((Map<String, Object?> row) {
              final String rowUserId = (row['user_id'] ?? '') as String;
              final Map<String, Object?> sessionState = _decodeJsonMap(
                row['state'],
              );
              return Session(
                id: (row['id'] ?? '') as String,
                appName: appName,
                userId: rowUserId,
                state: _mergeState(
                  appState: appState,
                  userState: userStates[rowUserId],
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
      _withDatabase<void>((_SqliteDatabase db) {
        db.execute(
          'DELETE FROM sessions WHERE app_name=? AND user_id=? AND id=?',
          <Object?>[appName, userId, sessionId],
        );
      });
    });
  }

  @override
  Future<Event> appendEvent({required Session session, required Event event}) {
    return _withLock<Event>(() async {
      if (event.partial == true) {
        return event;
      }

      _trimTempDeltaState(event);
      final SessionStateDelta delta = extractStateDelta(
        event.actions.stateDelta,
      );

      _withDatabase<void>((_SqliteDatabase db) {
        _runTransaction(db, () {
          final List<Map<String, Object?>> rows = db.query(
            'SELECT update_time FROM sessions WHERE app_name=? AND user_id=? AND id=?',
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
            _upsertAppState(
              db,
              appName: session.appName,
              delta: delta.app,
              updateTime: event.timestamp,
            );
          }

          if (delta.user.isNotEmpty) {
            _upsertUserState(
              db,
              appName: session.appName,
              userId: session.userId,
              delta: delta.user,
              updateTime: event.timestamp,
            );
          }

          if (delta.session.isNotEmpty) {
            db.execute(
              'UPDATE sessions '
              'SET state=json_patch(state, ?), update_time=? '
              'WHERE app_name=? AND user_id=? AND id=?',
              <Object?>[
                jsonEncode(delta.session),
                event.timestamp,
                session.appName,
                session.userId,
                session.id,
              ],
            );
          } else {
            db.execute(
              'UPDATE sessions '
              'SET update_time=? '
              'WHERE app_name=? AND user_id=? AND id=?',
              <Object?>[
                event.timestamp,
                session.appName,
                session.userId,
                session.id,
              ],
            );
          }

          db.execute(
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
              jsonEncode(_eventToJson(event)),
            ],
          );
        });
      });

      session.lastUpdateTime = event.timestamp;
      final Event appended = await super.appendEvent(
        session: session,
        event: event,
      );
      return appended;
    });
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

  T _withDatabase<T>(T Function(_SqliteDatabase db) action) {
    if (_inMemory) {
      final _SqliteDatabase db = _memoryDatabase ??= _SqliteDatabase.open(
        connectPath: _connectPath,
        displayPath: _storePath,
        uri: _connectAsUri,
        readOnly: _readOnly,
      );
      _prepareDatabase(db);
      return action(db);
    }

    _ensureWritableParentDirectory();
    final _SqliteDatabase db = _SqliteDatabase.open(
      connectPath: _connectPath,
      displayPath: _storePath,
      uri: _connectAsUri,
      readOnly: _readOnly,
    );
    try {
      _prepareDatabase(db);
      return action(db);
    } finally {
      db.dispose();
    }
  }

  void _ensureWritableParentDirectory() {
    if (_readOnly || _inMemory) {
      return;
    }
    File(_storePath).parent.createSync(recursive: true);
  }

  void _prepareDatabase(_SqliteDatabase db) {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute(_appStatesTableSchema);
    db.execute(_userStatesTableSchema);
    db.execute(_sessionsTableSchema);
    db.execute(_eventsTableSchema);
  }

  void _runTransaction(_SqliteDatabase db, void Function() action) {
    db.execute('BEGIN');
    bool committed = false;
    try {
      action();
      db.execute('COMMIT');
      committed = true;
    } finally {
      if (!committed) {
        try {
          db.execute('ROLLBACK');
        } catch (_) {
          // Best effort rollback only.
        }
      }
    }
  }

  void _upsertAppState(
    _SqliteDatabase db, {
    required String appName,
    required Map<String, Object?> delta,
    required double updateTime,
  }) {
    db.execute(
      'INSERT INTO app_states (app_name, state, update_time) VALUES (?, ?, ?) '
      'ON CONFLICT(app_name) DO UPDATE '
      'SET state=json_patch(state, excluded.state), '
      'update_time=excluded.update_time',
      <Object?>[appName, jsonEncode(delta), updateTime],
    );
  }

  void _upsertUserState(
    _SqliteDatabase db, {
    required String appName,
    required String userId,
    required Map<String, Object?> delta,
    required double updateTime,
  }) {
    db.execute(
      'INSERT INTO user_states (app_name, user_id, state, update_time) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(app_name, user_id) DO UPDATE '
      'SET state=json_patch(state, excluded.state), '
      'update_time=excluded.update_time',
      <Object?>[appName, userId, jsonEncode(delta), updateTime],
    );
  }

  Map<String, Object?> _getAppState(_SqliteDatabase db, String appName) {
    final List<Map<String, Object?>> rows = db.query(
      'SELECT state FROM app_states WHERE app_name=?',
      <Object?>[appName],
    );
    if (rows.isEmpty) {
      return <String, Object?>{};
    }
    return _decodeJsonMap(rows.first['state']);
  }

  Map<String, Object?> _getUserState(
    _SqliteDatabase db,
    String appName,
    String userId,
  ) {
    final List<Map<String, Object?>> rows = db.query(
      'SELECT state FROM user_states WHERE app_name=? AND user_id=?',
      <Object?>[appName, userId],
    );
    if (rows.isEmpty) {
      return <String, Object?>{};
    }
    return _decodeJsonMap(rows.first['state']);
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

class _ResolvedStorePath {
  const _ResolvedStorePath({
    required this.path,
    required this.connectPath,
    required this.connectUri,
    required this.readOnly,
    required this.inMemory,
  });

  final String path;
  final String connectPath;
  final bool connectUri;
  final bool readOnly;
  final bool inMemory;
}

_ResolvedStorePath _resolveStorePath(String dbPath) {
  final String input = dbPath.trim();
  if (input.isEmpty) {
    throw ArgumentError('Database path must not be empty.');
  }

  final String lowerInput = input.toLowerCase();
  if (!lowerInput.startsWith('sqlite:') &&
      !lowerInput.startsWith('sqlite+aiosqlite:')) {
    return _ResolvedStorePath(
      path: input,
      connectPath: input,
      connectUri: input.startsWith('file:'),
      readOnly: false,
      inMemory: _isInMemoryStorePath(input),
    );
  }

  final RegExp shorthandMemoryUrl = RegExp(
    r'^sqlite(?:\+aiosqlite)?:\/\/:memory:(?:\?(.*))?$',
    caseSensitive: false,
  );
  final Match? shorthandMatch = shorthandMemoryUrl.firstMatch(input);
  if (shorthandMatch != null) {
    final String queryText = shorthandMatch.group(1) ?? '';
    final Map<String, List<String>> query = _parseQueryParameters(queryText);
    return _buildResolvedStorePath(
      path: ':memory:',
      query: query,
      dbPath: dbPath,
    );
  }

  final String sanitizedInput = _escapeInvalidPercents(input);
  final Uri uri;
  try {
    uri = Uri.parse(sanitizedInput);
  } on FormatException catch (e) {
    throw ArgumentError.value(
      dbPath,
      'dbPath',
      'Invalid sqlite URL: ${e.message}',
    );
  }

  final String rawPath = _extractRawSqlitePath(sanitizedInput);
  final String path = _resolveSqliteUriPath(rawPath, dbPath);

  final Map<String, List<String>> query = _parseQueryParameters(uri.query);
  return _buildResolvedStorePath(path: path, query: query, dbPath: dbPath);
}

_ResolvedStorePath _buildResolvedStorePath({
  required String path,
  required Map<String, List<String>> query,
  required String dbPath,
}) {
  if (path.isEmpty) {
    throw ArgumentError.value(
      dbPath,
      'dbPath',
      'SQLite URL must include a file path.',
    );
  }

  final bool readOnly = _parseSqliteReadOnlyMode(query);
  final bool inMemory =
      _isInMemoryStorePath(path) || _parseSqliteInMemoryMode(query);
  final String connectQuery = _buildSqliteConnectionQuery(query);

  if (connectQuery.isNotEmpty) {
    return _ResolvedStorePath(
      path: path,
      connectPath: 'file:$path?$connectQuery',
      connectUri: true,
      readOnly: readOnly,
      inMemory: inMemory,
    );
  }

  return _ResolvedStorePath(
    path: path,
    connectPath: path,
    connectUri: path.startsWith('file:'),
    readOnly: readOnly,
    inMemory: inMemory,
  );
}

String _resolveSqliteUriPath(String rawPath, String dbPath) {
  String path = Uri.decodeComponent(rawPath);
  if (path == ':memory:' || path == '/:memory:') {
    return ':memory:';
  }
  if (path.isEmpty || path == '/') {
    throw ArgumentError.value(
      dbPath,
      'dbPath',
      'SQLite URL must include a file path.',
    );
  }

  if (path.startsWith('//')) {
    // sqlite:////abs/path.db -> /abs/path.db
    path = path.substring(1);
  } else if (_looksLikeWindowsDrivePath(path) ||
      path.startsWith('/./') ||
      path == '/.' ||
      path.startsWith('/../') ||
      path == '/..' ||
      _looksLikeRelativePlaceholderPath(path)) {
    // sqlite:///./rel.db and placeholder-style relative paths stay relative.
    path = path.substring(1);
  }

  if (path.isEmpty) {
    throw ArgumentError.value(
      dbPath,
      'dbPath',
      'SQLite URL must include a file path.',
    );
  }
  return path;
}

bool _looksLikeWindowsDrivePath(String path) {
  if (!path.startsWith('/') || path.length < 3) {
    return false;
  }
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path.substring(1));
}

bool _looksLikeRelativePlaceholderPath(String path) {
  if (!path.startsWith('/')) {
    return false;
  }
  final String firstSegment = path.substring(1).split('/').first;
  return firstSegment.contains('%') ||
      firstSegment.contains('{') ||
      firstSegment.contains('}');
}

String _extractRawSqlitePath(String sqliteUrl) {
  final int schemeSeparator = sqliteUrl.indexOf('://');
  if (schemeSeparator < 0) {
    return '';
  }

  String rest = sqliteUrl.substring(schemeSeparator + 3);
  final int queryIndex = rest.indexOf('?');
  final int fragmentIndex = rest.indexOf('#');
  int end = rest.length;
  if (queryIndex >= 0 && queryIndex < end) {
    end = queryIndex;
  }
  if (fragmentIndex >= 0 && fragmentIndex < end) {
    end = fragmentIndex;
  }
  rest = rest.substring(0, end);
  if (rest.isEmpty) {
    return '';
  }

  if (!rest.startsWith('/')) {
    if (rest == ':memory:') {
      return ':memory:';
    }
    final int slash = rest.indexOf('/');
    if (slash < 0) {
      return '';
    }
    return rest.substring(slash);
  }

  return rest;
}

bool _parseSqliteReadOnlyMode(Map<String, List<String>> query) {
  final List<String> modeValues = query['mode'] ?? <String>[];
  for (final String rawMode in modeValues) {
    if (rawMode.trim().toLowerCase() == 'ro') {
      return true;
    }
  }
  return false;
}

bool _parseSqliteInMemoryMode(Map<String, List<String>> query) {
  final List<String> modeValues = query['mode'] ?? <String>[];
  for (final String rawMode in modeValues) {
    if (rawMode.trim().toLowerCase() == 'memory') {
      return true;
    }
  }
  return false;
}

bool _isInMemoryStorePath(String path) {
  final String normalized = path.trim().toLowerCase();
  return normalized == ':memory:' || normalized == 'file::memory:';
}

Map<String, List<String>> _parseQueryParameters(String query) {
  if (query.isEmpty) {
    return <String, List<String>>{};
  }

  final Map<String, List<String>> parsed = <String, List<String>>{};
  for (final String pair in query.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final int separator = pair.indexOf('=');
    final String keyPart = separator < 0 ? pair : pair.substring(0, separator);
    final String valuePart = separator < 0 ? '' : pair.substring(separator + 1);
    final String key = Uri.decodeQueryComponent(keyPart);
    final String value = Uri.decodeQueryComponent(valuePart);
    parsed.putIfAbsent(key, () => <String>[]).add(value);
  }
  return parsed;
}

String _buildSqliteConnectionQuery(Map<String, List<String>> query) {
  if (query.isEmpty) {
    return '';
  }

  const Set<String> validModes = <String>{'ro', 'rw', 'rwc', 'memory'};
  final List<String> encodedPairs = <String>[];

  query.forEach((String key, List<String> values) {
    if (values.isEmpty) {
      return;
    }

    if (key == 'mode') {
      final List<String> validValues = values
          .where(
            (String value) => validModes.contains(value.trim().toLowerCase()),
          )
          .toList(growable: false);
      for (final String value in validValues) {
        encodedPairs.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
        );
      }
      return;
    }

    for (final String value in values) {
      encodedPairs.add(
        '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}',
      );
    }
  });

  return encodedPairs.join('&');
}

String _escapeInvalidPercents(String input) {
  final StringBuffer escaped = StringBuffer();
  for (int index = 0; index < input.length; index++) {
    final String char = input[index];
    if (char != '%') {
      escaped.write(char);
      continue;
    }

    if (index + 2 < input.length &&
        _isHexDigit(input.codeUnitAt(index + 1)) &&
        _isHexDigit(input.codeUnitAt(index + 2))) {
      escaped.write(char);
      continue;
    }
    escaped.write('%25');
  }
  return escaped.toString();
}

bool _isHexDigit(int codeUnit) {
  return (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 70) ||
      (codeUnit >= 97 && codeUnit <= 102);
}

Map<String, Object?> _mergeState({
  required Map<String, Object?>? appState,
  required Map<String, Object?>? userState,
  required Map<String, Object?> sessionState,
}) {
  final Map<String, Object?> merged = Map<String, Object?>.from(sessionState);
  if (appState != null) {
    appState.forEach((String key, Object? value) {
      merged['${State.appPrefix}$key'] = value;
    });
  }
  if (userState != null) {
    userState.forEach((String key, Object? value) {
      merged['${State.userPrefix}$key'] = value;
    });
  }
  return merged;
}

Map<String, Object?> _decodeJsonMap(Object? value) {
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

Map<String, Object?> _eventToJson(Event event) {
  return <String, Object?>{
    'invocationId': event.invocationId,
    'author': event.author,
    'id': event.id,
    'timestamp': event.timestamp,
    'actions': _eventActionsToJson(event.actions),
    if (event.longRunningToolIds != null)
      'longRunningToolIds': event.longRunningToolIds!.toList(),
    if (event.branch != null) 'branch': event.branch,
    if (event.modelVersion != null) 'modelVersion': event.modelVersion,
    if (event.content != null) 'content': _contentToJson(event.content!),
    if (event.partial != null) 'partial': event.partial,
    if (event.turnComplete != null) 'turnComplete': event.turnComplete,
    if (event.finishReason != null) 'finishReason': event.finishReason,
    if (event.errorCode != null) 'errorCode': event.errorCode,
    if (event.errorMessage != null) 'errorMessage': event.errorMessage,
    if (event.interrupted != null) 'interrupted': event.interrupted,
    if (event.customMetadata != null) 'customMetadata': event.customMetadata,
    if (event.usageMetadata != null) 'usageMetadata': event.usageMetadata,
    if (event.inputTranscription != null)
      'inputTranscription': event.inputTranscription,
    if (event.outputTranscription != null)
      'outputTranscription': event.outputTranscription,
    if (event.avgLogprobs != null) 'avgLogprobs': event.avgLogprobs,
    if (event.logprobsResult != null) 'logprobsResult': event.logprobsResult,
    if (event.cacheMetadata != null) 'cacheMetadata': event.cacheMetadata,
    if (event.citationMetadata != null)
      'citationMetadata': event.citationMetadata,
    if (event.groundingMetadata != null)
      'groundingMetadata': event.groundingMetadata,
    if (event.interactionId != null) 'interactionId': event.interactionId,
  };
}

Event _eventFromJson(Map<String, Object?> json) {
  return Event(
    invocationId: (json['invocationId'] ?? '') as String,
    author: (json['author'] ?? '') as String,
    id: (json['id'] ?? '') as String,
    timestamp: _asDouble(json['timestamp']),
    actions: _eventActionsFromJson(_castMap(json['actions'])),
    longRunningToolIds: _asStringSet(json['longRunningToolIds']),
    branch: json['branch'] as String?,
    modelVersion: json['modelVersion'] as String?,
    content: json['content'] is Map
        ? _contentFromJson(_castMap(json['content']))
        : null,
    partial: json['partial'] as bool?,
    turnComplete: json['turnComplete'] as bool?,
    finishReason: json['finishReason'] as String?,
    errorCode: json['errorCode'] as String?,
    errorMessage: json['errorMessage'] as String?,
    interrupted: json['interrupted'] as bool?,
    customMetadata: _castDynamicMap(json['customMetadata']),
    usageMetadata: json['usageMetadata'],
    inputTranscription: json['inputTranscription'],
    outputTranscription: json['outputTranscription'],
    avgLogprobs: _asNullableDouble(json['avgLogprobs']),
    logprobsResult: json['logprobsResult'],
    cacheMetadata: json['cacheMetadata'],
    citationMetadata: json['citationMetadata'],
    groundingMetadata: json['groundingMetadata'],
    interactionId: json['interactionId'] as String?,
  );
}

Map<String, Object?> _eventActionsToJson(EventActions actions) {
  return <String, Object?>{
    if (actions.skipSummarization != null)
      'skipSummarization': actions.skipSummarization,
    'stateDelta': actions.stateDelta,
    'artifactDelta': actions.artifactDelta,
    if (actions.transferToAgent != null)
      'transferToAgent': actions.transferToAgent,
    if (actions.escalate != null) 'escalate': actions.escalate,
    if (actions.requestedAuthConfigs.isNotEmpty)
      'requestedAuthConfigs': actions.requestedAuthConfigs,
    if (actions.requestedToolConfirmations.isNotEmpty)
      'requestedToolConfirmations': actions.requestedToolConfirmations,
    if (actions.compaction != null)
      'compaction': <String, Object?>{
        'startTimestamp': actions.compaction!.startTimestamp,
        'endTimestamp': actions.compaction!.endTimestamp,
        'compactedContent': _contentToJson(
          actions.compaction!.compactedContent,
        ),
      },
    if (actions.endOfAgent != null) 'endOfAgent': actions.endOfAgent,
    if (actions.agentState != null) 'agentState': actions.agentState,
    if (actions.rewindBeforeInvocationId != null)
      'rewindBeforeInvocationId': actions.rewindBeforeInvocationId,
  };
}

EventActions _eventActionsFromJson(Map<String, Object?> json) {
  EventCompaction? compaction;
  if (json['compaction'] is Map) {
    final Map<String, Object?> compactionMap = _castMap(json['compaction']);
    compaction = EventCompaction(
      startTimestamp: _asDouble(compactionMap['startTimestamp']),
      endTimestamp: _asDouble(compactionMap['endTimestamp']),
      compactedContent: _contentFromJson(
        _castMap(compactionMap['compactedContent']),
      ),
    );
  }
  return EventActions(
    skipSummarization: json['skipSummarization'] as bool?,
    stateDelta: _castMap(json['stateDelta']),
    artifactDelta: _castIntMap(json['artifactDelta']),
    transferToAgent: json['transferToAgent'] as String?,
    escalate: json['escalate'] as bool?,
    requestedAuthConfigs: _castObjectMap(json['requestedAuthConfigs']),
    requestedToolConfirmations: _castObjectMap(
      json['requestedToolConfirmations'],
    ),
    compaction: compaction,
    endOfAgent: json['endOfAgent'] as bool?,
    agentState: _castMap(json['agentState']),
    rewindBeforeInvocationId: json['rewindBeforeInvocationId'] as String?,
  );
}

Map<String, Object?> _contentToJson(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map((Part value) => _partToJson(value)).toList(),
  };
}

Content _contentFromJson(Map<String, Object?> json) {
  final List<Part> parts = <Part>[];
  final Object? rawParts = json['parts'];
  if (rawParts is List) {
    for (final Object? item in rawParts) {
      if (item is Map) {
        parts.add(_partFromJson(_castMap(item)));
      }
    }
  }
  return Content(role: json['role'] as String?, parts: parts);
}

Map<String, Object?> _partToJson(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    'thought': part.thought,
    if (part.thoughtSignature != null)
      'thoughtSignature': List<int>.from(part.thoughtSignature!),
    if (part.functionCall != null)
      'functionCall': <String, Object?>{
        'name': part.functionCall!.name,
        'args': part.functionCall!.args,
        if (part.functionCall!.id != null) 'id': part.functionCall!.id,
        if (part.functionCall!.partialArgs != null)
          'partialArgs': part.functionCall!.partialArgs
              ?.map(
                (Map<String, Object?> value) =>
                    Map<String, Object?>.from(value),
              )
              .toList(growable: false),
        if (part.functionCall!.willContinue != null)
          'willContinue': part.functionCall!.willContinue,
      },
    if (part.functionResponse != null)
      'functionResponse': <String, Object?>{
        'name': part.functionResponse!.name,
        'response': part.functionResponse!.response,
        if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
      },
    if (part.inlineData != null)
      'inlineData': <String, Object?>{
        'mimeType': part.inlineData!.mimeType,
        'data': part.inlineData!.data,
        if (part.inlineData!.displayName != null)
          'displayName': part.inlineData!.displayName,
      },
    if (part.fileData != null)
      'fileData': <String, Object?>{
        'fileUri': part.fileData!.fileUri,
        if (part.fileData!.mimeType != null)
          'mimeType': part.fileData!.mimeType,
        if (part.fileData!.displayName != null)
          'displayName': part.fileData!.displayName,
      },
    if (part.executableCode != null) 'executableCode': part.executableCode,
    if (part.codeExecutionResult != null)
      'codeExecutionResult': part.codeExecutionResult,
  };
}

Part _partFromJson(Map<String, Object?> json) {
  FunctionCall? functionCall;
  if (json['functionCall'] is Map) {
    final Map<String, Object?> functionMap = _castMap(json['functionCall']);
    functionCall = FunctionCall(
      name: (functionMap['name'] ?? '') as String,
      args: _castDynamicMap(functionMap['args']) ?? <String, dynamic>{},
      id: functionMap['id'] as String?,
      partialArgs: _castMapList(
        functionMap['partialArgs'] ?? functionMap['partial_args'],
      ),
      willContinue: _asNullableBool(
        functionMap['willContinue'] ?? functionMap['will_continue'],
      ),
    );
  }

  FunctionResponse? functionResponse;
  if (json['functionResponse'] is Map) {
    final Map<String, Object?> functionMap = _castMap(json['functionResponse']);
    functionResponse = FunctionResponse(
      name: (functionMap['name'] ?? '') as String,
      response: _castDynamicMap(functionMap['response']) ?? <String, dynamic>{},
      id: functionMap['id'] as String?,
    );
  }

  InlineData? inlineData;
  if (json['inlineData'] is Map) {
    final Map<String, Object?> inlineMap = _castMap(json['inlineData']);
    final Object? rawData = inlineMap['data'];
    final List<int> bytes = <int>[];
    if (rawData is List) {
      for (final Object? item in rawData) {
        if (item is num) {
          bytes.add(item.toInt());
        }
      }
    }
    inlineData = InlineData(
      mimeType: (inlineMap['mimeType'] ?? '') as String,
      data: bytes,
      displayName: inlineMap['displayName'] as String?,
    );
  }

  FileData? fileData;
  if (json['fileData'] is Map) {
    final Map<String, Object?> fileMap = _castMap(json['fileData']);
    fileData = FileData(
      fileUri: (fileMap['fileUri'] ?? '') as String,
      mimeType: fileMap['mimeType'] as String?,
      displayName: fileMap['displayName'] as String?,
    );
  }

  return Part(
    text: json['text'] as String?,
    thought: (json['thought'] as bool?) ?? false,
    thoughtSignature: _castNullableIntList(
      json['thoughtSignature'] ?? json['thought_signature'],
    ),
    functionCall: functionCall,
    functionResponse: functionResponse,
    inlineData: inlineData,
    fileData: fileData,
    executableCode: json['executableCode'],
    codeExecutionResult: json['codeExecutionResult'],
  );
}

Map<String, Object?> _castMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, int> _castIntMap(Object? value) {
  final Map<String, int> map = <String, int>{};
  if (value is Map) {
    value.forEach((Object? key, Object? raw) {
      if (raw is num) {
        map['$key'] = raw.toInt();
      }
    });
  }
  return map;
}

Map<String, Object> _castObjectMap(Object? value) {
  final Map<String, Object> map = <String, Object>{};
  if (value is Map) {
    value.forEach((Object? key, Object? raw) {
      if (raw != null) {
        map['$key'] = raw;
      }
    });
  }
  return map;
}

Map<String, dynamic>? _castDynamicMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return null;
}

List<int>? _castNullableIntList(Object? value) {
  if (value is! List) {
    return null;
  }
  final List<int> output = <int>[];
  for (final Object? item in value) {
    if (item is num) {
      output.add(item.toInt());
    }
  }
  if (output.isEmpty) {
    return null;
  }
  return output;
}

List<Map<String, Object?>>? _castMapList(Object? value) {
  if (value is! List) {
    return null;
  }
  final List<Map<String, Object?>> output = <Map<String, Object?>>[];
  for (final Object? item in value) {
    if (item is Map<String, Object?>) {
      output.add(Map<String, Object?>.from(item));
      continue;
    }
    if (item is Map) {
      output.add(
        item.map((Object? key, Object? entry) => MapEntry('$key', entry)),
      );
    }
  }
  if (output.isEmpty) {
    return null;
  }
  return output;
}

bool? _asNullableBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final String normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  if (value is num) {
    if (value == 1) {
      return true;
    }
    if (value == 0) {
      return false;
    }
  }
  return null;
}

Set<String>? _asStringSet(Object? value) {
  if (value is List) {
    return value.whereType<String>().toSet();
  }
  return null;
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

double? _asNullableDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

final class _Sqlite3Handle extends Opaque {}

final class _Sqlite3Statement extends Opaque {}

const int _sqliteOk = 0;
const int _sqliteRow = 100;
const int _sqliteDone = 101;

const int _sqliteInteger = 1;
const int _sqliteFloat = 2;
const int _sqliteText = 3;
const int _sqliteBlob = 4;
const int _sqliteNull = 5;

const int _sqliteOpenReadOnly = 0x00000001;
const int _sqliteOpenReadWrite = 0x00000002;
const int _sqliteOpenCreate = 0x00000004;
const int _sqliteOpenUri = 0x00000040;
const int _sqliteOpenFullMutex = 0x00010000;

class _SqliteDatabase {
  _SqliteDatabase._({
    required _SqliteBindings bindings,
    required Pointer<_Sqlite3Handle> handle,
    required String displayPath,
  }) : _bindings = bindings,
       _handle = handle,
       _displayPath = displayPath;

  factory _SqliteDatabase.open({
    required String connectPath,
    required String displayPath,
    required bool uri,
    required bool readOnly,
  }) {
    final _SqliteBindings bindings = _SqliteBindings.instance;
    final Pointer<Pointer<_Sqlite3Handle>> dbOut = _NativeMemory.allocate(
      sizeOf<Pointer<_Sqlite3Handle>>(),
    ).cast<Pointer<_Sqlite3Handle>>();
    dbOut.value = nullptr;

    final _NativeString path = _NativeString.fromDart(connectPath);
    final int flags =
        (readOnly
            ? _sqliteOpenReadOnly
            : (_sqliteOpenReadWrite | _sqliteOpenCreate)) |
        (uri ? _sqliteOpenUri : 0) |
        _sqliteOpenFullMutex;

    final int resultCode;
    try {
      resultCode = bindings.sqlite3OpenV2(
        path.pointer,
        dbOut,
        flags,
        nullptr.cast<Uint8>(),
      );
    } finally {
      path.dispose();
    }

    final Pointer<_Sqlite3Handle> handle = dbOut.value;
    _NativeMemory.free(dbOut.cast<Void>());

    if (resultCode != _sqliteOk) {
      String message = 'Failed to open SQLite database.';
      if (handle != nullptr) {
        message = _decodeCString(bindings.sqlite3Errmsg(handle));
        bindings.sqlite3CloseV2(handle);
      }
      throw FileSystemException(
        'SQLite open error ($resultCode): $message',
        displayPath,
      );
    }

    return _SqliteDatabase._(
      bindings: bindings,
      handle: handle,
      displayPath: displayPath,
    );
  }

  final _SqliteBindings _bindings;
  final Pointer<_Sqlite3Handle> _handle;
  final String _displayPath;
  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _bindings.sqlite3CloseV2(_handle);
    _disposed = true;
  }

  void execute(String sql, [List<Object?> params = const <Object?>[]]) {
    _ensureOpen();
    final _PreparedStatement statement = _prepare(sql);
    try {
      _bindParameters(statement, params);
      int stepCode = _bindings.sqlite3Step(statement.handle);
      while (stepCode == _sqliteRow) {
        stepCode = _bindings.sqlite3Step(statement.handle);
      }
      if (stepCode != _sqliteDone) {
        _throwSqliteError(operation: 'execute', code: stepCode);
      }
    } finally {
      statement.dispose();
    }
  }

  List<Map<String, Object?>> query(
    String sql, [
    List<Object?> params = const <Object?>[],
  ]) {
    _ensureOpen();
    final _PreparedStatement statement = _prepare(sql);
    try {
      _bindParameters(statement, params);
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];

      while (true) {
        final int stepCode = _bindings.sqlite3Step(statement.handle);
        if (stepCode == _sqliteDone) {
          break;
        }
        if (stepCode != _sqliteRow) {
          _throwSqliteError(operation: 'query', code: stepCode);
        }

        final int columnCount = _bindings.sqlite3ColumnCount(statement.handle);
        final Map<String, Object?> row = <String, Object?>{};
        for (int index = 0; index < columnCount; index++) {
          final String name = _decodeCString(
            _bindings.sqlite3ColumnName(statement.handle, index),
          );
          row[name] = _readColumn(statement.handle, index);
        }
        rows.add(row);
      }

      return rows;
    } finally {
      statement.dispose();
    }
  }

  _PreparedStatement _prepare(String sql) {
    final _NativeString sqlString = _NativeString.fromDart(sql);
    final Pointer<Pointer<_Sqlite3Statement>> stmtOut = _NativeMemory.allocate(
      sizeOf<Pointer<_Sqlite3Statement>>(),
    ).cast<Pointer<_Sqlite3Statement>>();
    stmtOut.value = nullptr;

    final int resultCode;
    try {
      resultCode = _bindings.sqlite3PrepareV2(
        _handle,
        sqlString.pointer,
        -1,
        stmtOut,
        nullptr.cast<Pointer<Uint8>>(),
      );
    } finally {
      sqlString.dispose();
    }

    final Pointer<_Sqlite3Statement> statement = stmtOut.value;
    _NativeMemory.free(stmtOut.cast<Void>());

    if (resultCode != _sqliteOk) {
      if (statement != nullptr) {
        _bindings.sqlite3Finalize(statement);
      }
      _throwSqliteError(operation: 'prepare', code: resultCode);
    }

    return _PreparedStatement(_bindings, statement);
  }

  void _bindParameters(_PreparedStatement statement, List<Object?> params) {
    for (int index = 0; index < params.length; index++) {
      final Object? value = params[index];
      final int parameterIndex = index + 1;
      int resultCode;

      if (value == null) {
        resultCode = _bindings.sqlite3BindNull(
          statement.handle,
          parameterIndex,
        );
      } else if (value is bool) {
        resultCode = _bindings.sqlite3BindInt(
          statement.handle,
          parameterIndex,
          value ? 1 : 0,
        );
      } else if (value is int) {
        resultCode = _bindings.sqlite3BindInt64(
          statement.handle,
          parameterIndex,
          value,
        );
      } else if (value is double) {
        resultCode = _bindings.sqlite3BindDouble(
          statement.handle,
          parameterIndex,
          value,
        );
      } else if (value is num) {
        resultCode = _bindings.sqlite3BindDouble(
          statement.handle,
          parameterIndex,
          value.toDouble(),
        );
      } else {
        final _NativeString textValue = _NativeString.fromDart('$value');
        statement.registerOwnedString(textValue);
        resultCode = _bindings.sqlite3BindText(
          statement.handle,
          parameterIndex,
          textValue.pointer,
          -1,
          nullptr.cast<NativeFunction<_SqliteDestructorNative>>(),
        );
      }

      if (resultCode != _sqliteOk) {
        _throwSqliteError(operation: 'bind', code: resultCode);
      }
    }
  }

  Object? _readColumn(Pointer<_Sqlite3Statement> statement, int index) {
    final int type = _bindings.sqlite3ColumnType(statement, index);
    switch (type) {
      case _sqliteNull:
        return null;
      case _sqliteInteger:
        return _bindings.sqlite3ColumnInt64(statement, index);
      case _sqliteFloat:
        return _bindings.sqlite3ColumnDouble(statement, index);
      case _sqliteText:
        return _decodeCString(_bindings.sqlite3ColumnText(statement, index));
      case _sqliteBlob:
        final int length = _bindings.sqlite3ColumnBytes(statement, index);
        if (length <= 0) {
          return Uint8List(0);
        }
        final Pointer<Void> blobPointer = _bindings.sqlite3ColumnBlob(
          statement,
          index,
        );
        if (blobPointer == nullptr) {
          return Uint8List(0);
        }
        return Uint8List.fromList(
          blobPointer.cast<Uint8>().asTypedList(length),
        );
      default:
        return null;
    }
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('SQLite database connection is already closed.');
    }
  }

  Never _throwSqliteError({required String operation, required int code}) {
    final String message = _decodeCString(_bindings.sqlite3Errmsg(_handle));
    throw FileSystemException(
      'SQLite $operation error ($code): $message',
      _displayPath,
    );
  }
}

class _PreparedStatement {
  _PreparedStatement(this._bindings, this.handle);

  final _SqliteBindings _bindings;
  final Pointer<_Sqlite3Statement> handle;
  final List<_NativeString> _ownedStrings = <_NativeString>[];
  bool _disposed = false;

  void registerOwnedString(_NativeString value) {
    _ownedStrings.add(value);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _bindings.sqlite3Finalize(handle);
    for (final _NativeString string in _ownedStrings) {
      string.dispose();
    }
    _ownedStrings.clear();
    _disposed = true;
  }
}

class _SqliteBindings {
  _SqliteBindings._(DynamicLibrary library)
    : sqlite3OpenV2 = library
          .lookupFunction<_SqliteOpenV2Native, _SqliteOpenV2Dart>(
            'sqlite3_open_v2',
          ),
      sqlite3CloseV2 = library
          .lookupFunction<_SqliteCloseV2Native, _SqliteCloseV2Dart>(
            'sqlite3_close_v2',
          ),
      sqlite3Errmsg = library
          .lookupFunction<_SqliteErrmsgNative, _SqliteErrmsgDart>(
            'sqlite3_errmsg',
          ),
      sqlite3PrepareV2 = library
          .lookupFunction<_SqlitePrepareV2Native, _SqlitePrepareV2Dart>(
            'sqlite3_prepare_v2',
          ),
      sqlite3Step = library.lookupFunction<_SqliteStepNative, _SqliteStepDart>(
        'sqlite3_step',
      ),
      sqlite3Finalize = library
          .lookupFunction<_SqliteFinalizeNative, _SqliteFinalizeDart>(
            'sqlite3_finalize',
          ),
      sqlite3BindNull = library
          .lookupFunction<_SqliteBindNullNative, _SqliteBindNullDart>(
            'sqlite3_bind_null',
          ),
      sqlite3BindInt = library
          .lookupFunction<_SqliteBindIntNative, _SqliteBindIntDart>(
            'sqlite3_bind_int',
          ),
      sqlite3BindInt64 = library
          .lookupFunction<_SqliteBindInt64Native, _SqliteBindInt64Dart>(
            'sqlite3_bind_int64',
          ),
      sqlite3BindDouble = library
          .lookupFunction<_SqliteBindDoubleNative, _SqliteBindDoubleDart>(
            'sqlite3_bind_double',
          ),
      sqlite3BindText = library
          .lookupFunction<_SqliteBindTextNative, _SqliteBindTextDart>(
            'sqlite3_bind_text',
          ),
      sqlite3ColumnCount = library
          .lookupFunction<_SqliteColumnCountNative, _SqliteColumnCountDart>(
            'sqlite3_column_count',
          ),
      sqlite3ColumnName = library
          .lookupFunction<_SqliteColumnNameNative, _SqliteColumnNameDart>(
            'sqlite3_column_name',
          ),
      sqlite3ColumnType = library
          .lookupFunction<_SqliteColumnTypeNative, _SqliteColumnTypeDart>(
            'sqlite3_column_type',
          ),
      sqlite3ColumnInt64 = library
          .lookupFunction<_SqliteColumnInt64Native, _SqliteColumnInt64Dart>(
            'sqlite3_column_int64',
          ),
      sqlite3ColumnDouble = library
          .lookupFunction<_SqliteColumnDoubleNative, _SqliteColumnDoubleDart>(
            'sqlite3_column_double',
          ),
      sqlite3ColumnText = library
          .lookupFunction<_SqliteColumnTextNative, _SqliteColumnTextDart>(
            'sqlite3_column_text',
          ),
      sqlite3ColumnBlob = library
          .lookupFunction<_SqliteColumnBlobNative, _SqliteColumnBlobDart>(
            'sqlite3_column_blob',
          ),
      sqlite3ColumnBytes = library
          .lookupFunction<_SqliteColumnBytesNative, _SqliteColumnBytesDart>(
            'sqlite3_column_bytes',
          );

  static final _SqliteBindings instance = _SqliteBindings._(
    _openSqliteLibrary(),
  );

  final _SqliteOpenV2Dart sqlite3OpenV2;
  final _SqliteCloseV2Dart sqlite3CloseV2;
  final _SqliteErrmsgDart sqlite3Errmsg;
  final _SqlitePrepareV2Dart sqlite3PrepareV2;
  final _SqliteStepDart sqlite3Step;
  final _SqliteFinalizeDart sqlite3Finalize;
  final _SqliteBindNullDart sqlite3BindNull;
  final _SqliteBindIntDart sqlite3BindInt;
  final _SqliteBindInt64Dart sqlite3BindInt64;
  final _SqliteBindDoubleDart sqlite3BindDouble;
  final _SqliteBindTextDart sqlite3BindText;
  final _SqliteColumnCountDart sqlite3ColumnCount;
  final _SqliteColumnNameDart sqlite3ColumnName;
  final _SqliteColumnTypeDart sqlite3ColumnType;
  final _SqliteColumnInt64Dart sqlite3ColumnInt64;
  final _SqliteColumnDoubleDart sqlite3ColumnDouble;
  final _SqliteColumnTextDart sqlite3ColumnText;
  final _SqliteColumnBlobDart sqlite3ColumnBlob;
  final _SqliteColumnBytesDart sqlite3ColumnBytes;
}

class _NativeMemory {
  static final DynamicLibrary _library = _openCLibrary();

  static final Pointer<Void> Function(int) _malloc = _library
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('malloc');

  static final void Function(Pointer<Void>) _free = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');

  static Pointer<Void> allocate(int byteCount) {
    final Pointer<Void> pointer = _malloc(byteCount);
    if (pointer == nullptr) {
      throw StateError('Native allocation failed.');
    }
    return pointer;
  }

  static void free(Pointer<Void> pointer) {
    if (pointer == nullptr) {
      return;
    }
    _free(pointer);
  }
}

class _NativeString {
  _NativeString._(this.pointer);

  final Pointer<Uint8> pointer;

  factory _NativeString.fromDart(String value) {
    final List<int> bytes = utf8.encode(value);
    final Pointer<Uint8> buffer = _NativeMemory.allocate(
      bytes.length + 1,
    ).cast<Uint8>();
    final Uint8List nativeBytes = buffer.asTypedList(bytes.length + 1);
    nativeBytes.setRange(0, bytes.length, bytes);
    nativeBytes[bytes.length] = 0;
    return _NativeString._(buffer);
  }

  void dispose() {
    _NativeMemory.free(pointer.cast<Void>());
  }
}

String _decodeCString(Pointer<Uint8> pointer) {
  if (pointer == nullptr) {
    return '';
  }

  int length = 0;
  while (pointer[length] != 0) {
    length += 1;
  }

  if (length == 0) {
    return '';
  }

  return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
}

DynamicLibrary _openSqliteLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('/usr/lib/libsqlite3.dylib');
  }
  if (Platform.isLinux) {
    try {
      return DynamicLibrary.open('libsqlite3.so.0');
    } catch (_) {
      return DynamicLibrary.open('libsqlite3.so');
    }
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('sqlite3.dll');
  }
  return DynamicLibrary.process();
}

DynamicLibrary _openCLibrary() {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libc.so.6');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('msvcrt.dll');
  }
  return DynamicLibrary.process();
}

typedef _SqliteDestructorNative = Void Function(Pointer<Void>);

typedef _SqliteOpenV2Native =
    Int32 Function(
      Pointer<Uint8> filename,
      Pointer<Pointer<_Sqlite3Handle>> db,
      Int32 flags,
      Pointer<Uint8> vfs,
    );

typedef _SqliteOpenV2Dart =
    int Function(
      Pointer<Uint8> filename,
      Pointer<Pointer<_Sqlite3Handle>> db,
      int flags,
      Pointer<Uint8> vfs,
    );

typedef _SqliteCloseV2Native = Int32 Function(Pointer<_Sqlite3Handle> db);
typedef _SqliteCloseV2Dart = int Function(Pointer<_Sqlite3Handle> db);

typedef _SqliteErrmsgNative =
    Pointer<Uint8> Function(Pointer<_Sqlite3Handle> db);
typedef _SqliteErrmsgDart = Pointer<Uint8> Function(Pointer<_Sqlite3Handle> db);

typedef _SqlitePrepareV2Native =
    Int32 Function(
      Pointer<_Sqlite3Handle> db,
      Pointer<Uint8> sql,
      Int32 byteCount,
      Pointer<Pointer<_Sqlite3Statement>> statement,
      Pointer<Pointer<Uint8>> tail,
    );

typedef _SqlitePrepareV2Dart =
    int Function(
      Pointer<_Sqlite3Handle> db,
      Pointer<Uint8> sql,
      int byteCount,
      Pointer<Pointer<_Sqlite3Statement>> statement,
      Pointer<Pointer<Uint8>> tail,
    );

typedef _SqliteStepNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement);
typedef _SqliteStepDart = int Function(Pointer<_Sqlite3Statement> statement);

typedef _SqliteFinalizeNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement);
typedef _SqliteFinalizeDart =
    int Function(Pointer<_Sqlite3Statement> statement);

typedef _SqliteBindNullNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement, Int32 index);
typedef _SqliteBindNullDart =
    int Function(Pointer<_Sqlite3Statement> statement, int index);

typedef _SqliteBindIntNative =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Int32 value,
    );
typedef _SqliteBindIntDart =
    int Function(Pointer<_Sqlite3Statement> statement, int index, int value);

typedef _SqliteBindInt64Native =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Int64 value,
    );
typedef _SqliteBindInt64Dart =
    int Function(Pointer<_Sqlite3Statement> statement, int index, int value);

typedef _SqliteBindDoubleNative =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Double value,
    );
typedef _SqliteBindDoubleDart =
    int Function(Pointer<_Sqlite3Statement> statement, int index, double value);

typedef _SqliteBindTextNative =
    Int32 Function(
      Pointer<_Sqlite3Statement> statement,
      Int32 index,
      Pointer<Uint8> value,
      Int32 length,
      Pointer<NativeFunction<_SqliteDestructorNative>> destructor,
    );

typedef _SqliteBindTextDart =
    int Function(
      Pointer<_Sqlite3Statement> statement,
      int index,
      Pointer<Uint8> value,
      int length,
      Pointer<NativeFunction<_SqliteDestructorNative>> destructor,
    );

typedef _SqliteColumnCountNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement);
typedef _SqliteColumnCountDart =
    int Function(Pointer<_Sqlite3Statement> statement);

typedef _SqliteColumnNameNative =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnNameDart =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnTypeNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnTypeDart =
    int Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnInt64Native =
    Int64 Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnInt64Dart =
    int Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnDoubleNative =
    Double Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnDoubleDart =
    double Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnTextNative =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnTextDart =
    Pointer<Uint8> Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnBlobNative =
    Pointer<Void> Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnBlobDart =
    Pointer<Void> Function(Pointer<_Sqlite3Statement> statement, int column);

typedef _SqliteColumnBytesNative =
    Int32 Function(Pointer<_Sqlite3Statement> statement, Int32 column);
typedef _SqliteColumnBytesDart =
    int Function(Pointer<_Sqlite3Statement> statement, int column);
