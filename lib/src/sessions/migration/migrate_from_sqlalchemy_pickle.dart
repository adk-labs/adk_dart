import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'schema_check_utils.dart';
import 'sqlite_db.dart';

const String _metadataTableSchema = '''
CREATE TABLE IF NOT EXISTS adk_internal_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''';

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

Future<void> migrateFromSqlalchemyPickle(
  String sourceDbUrl,
  String destDbUrl,
) async {
  final ResolvedSqliteDbUrl source = resolveSqliteDbUrl(
    toSyncUrl(sourceDbUrl),
    argumentName: 'sourceDbUrl',
  );
  final ResolvedSqliteDbUrl destination = resolveSqliteDbUrl(
    toSyncUrl(destDbUrl),
    argumentName: 'destDbUrl',
  );

  if (!source.inMemory &&
      !source.storePath.startsWith('file:') &&
      !File(source.storePath).existsSync()) {
    throw FileSystemException(
      'Source database does not exist.',
      source.storePath,
    );
  }

  if (!destination.inMemory && !destination.storePath.startsWith('file:')) {
    await File(destination.storePath).parent.create(recursive: true);
  }

  final SqliteMigrationDatabase sourceDb = SqliteMigrationDatabase.open(
    connectPath: source.connectPath,
    displayPath: source.storePath,
    uri: source.connectUri,
    readOnly: true,
  );
  final SqliteMigrationDatabase destDb = SqliteMigrationDatabase.open(
    connectPath: destination.connectPath,
    displayPath: destination.storePath,
    uri: destination.connectUri,
    readOnly: false,
  );

  try {
    destDb.execute('PRAGMA foreign_keys = ON');
    _createDestinationSchema(destDb);

    destDb.runTransaction(() {
      _upsertSchemaVersion(destDb);
      _migrateAppStates(sourceDb, destDb);
      _migrateUserStates(sourceDb, destDb);
      _migrateSessions(sourceDb, destDb);
      _migrateEvents(sourceDb, destDb);
    });
  } finally {
    sourceDb.dispose();
    destDb.dispose();
  }
}

void _createDestinationSchema(SqliteMigrationDatabase db) {
  db.execute(_metadataTableSchema);
  db.execute(_appStatesTableSchema);
  db.execute(_userStatesTableSchema);
  db.execute(_sessionsTableSchema);
  db.execute(_eventsTableSchema);
}

void _upsertSchemaVersion(SqliteMigrationDatabase db) {
  db.execute(
    'INSERT OR REPLACE INTO adk_internal_metadata (key, value) VALUES (?, ?)',
    <Object?>[schemaVersionKey, schemaVersion1Json],
  );
}

void _migrateAppStates(
  SqliteMigrationDatabase source,
  SqliteMigrationDatabase destination,
) {
  if (!source.hasTable('app_states')) {
    return;
  }
  final List<Map<String, Object?>> rows = source.query(
    'SELECT * FROM app_states',
  );
  for (final Map<String, Object?> row in rows) {
    final String appName = _asRequiredString(
      row['app_name'],
      field: 'app_name',
    );
    final Map<String, Object?> state = _decodeJsonMap(row['state']);
    final double updateTime = _coerceTimestampSeconds(row['update_time']);
    destination.execute(
      'INSERT OR REPLACE INTO app_states (app_name, state, update_time) VALUES (?, ?, ?)',
      <Object?>[appName, jsonEncode(state), updateTime],
    );
  }
}

void _migrateUserStates(
  SqliteMigrationDatabase source,
  SqliteMigrationDatabase destination,
) {
  if (!source.hasTable('user_states')) {
    return;
  }
  final List<Map<String, Object?>> rows = source.query(
    'SELECT * FROM user_states',
  );
  for (final Map<String, Object?> row in rows) {
    final String appName = _asRequiredString(
      row['app_name'],
      field: 'app_name',
    );
    final String userId = _asRequiredString(row['user_id'], field: 'user_id');
    final Map<String, Object?> state = _decodeJsonMap(row['state']);
    final double updateTime = _coerceTimestampSeconds(row['update_time']);
    destination.execute(
      'INSERT OR REPLACE INTO user_states (app_name, user_id, state, update_time) VALUES (?, ?, ?, ?)',
      <Object?>[appName, userId, jsonEncode(state), updateTime],
    );
  }
}

void _migrateSessions(
  SqliteMigrationDatabase source,
  SqliteMigrationDatabase destination,
) {
  if (!source.hasTable('sessions')) {
    return;
  }
  final List<Map<String, Object?>> rows = source.query(
    'SELECT * FROM sessions',
  );
  for (final Map<String, Object?> row in rows) {
    final String appName = _asRequiredString(
      row['app_name'],
      field: 'app_name',
    );
    final String userId = _asRequiredString(row['user_id'], field: 'user_id');
    final String sessionId = _asRequiredString(row['id'], field: 'id');
    final Map<String, Object?> state = _decodeJsonMap(row['state']);
    final double createTime = _coerceTimestampSeconds(row['create_time']);
    final double updateTime = _coerceTimestampSeconds(row['update_time']);
    destination.execute(
      'INSERT OR REPLACE INTO sessions (app_name, user_id, id, state, create_time, update_time) VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        appName,
        userId,
        sessionId,
        jsonEncode(state),
        createTime,
        updateTime,
      ],
    );
  }
}

void _migrateEvents(
  SqliteMigrationDatabase source,
  SqliteMigrationDatabase destination,
) {
  if (!source.hasTable('events')) {
    return;
  }

  final List<Map<String, Object?>> rows = source.query('SELECT * FROM events');
  for (final Map<String, Object?> row in rows) {
    try {
      final String eventId = _asRequiredString(row['id'], field: 'id');
      final String appName = _asRequiredString(
        row['app_name'],
        field: 'app_name',
      );
      final String userId = _asRequiredString(row['user_id'], field: 'user_id');
      final String sessionId = _asRequiredString(
        row['session_id'],
        field: 'session_id',
      );
      final double timestamp = _coerceTimestampSeconds(row['timestamp']);
      final Map<String, Object?> eventData = _rowToEventData(row);
      final String invocationId = '${eventData['invocation_id'] ?? ''}';

      destination.execute(
        'INSERT OR REPLACE INTO events (id, app_name, user_id, session_id, invocation_id, timestamp, event_data) VALUES (?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          eventId,
          appName,
          userId,
          sessionId,
          invocationId,
          timestamp,
          jsonEncode(eventData),
        ],
      );
    } catch (_) {
      // Keep migration resilient row-by-row, matching Python behavior.
      continue;
    }
  }
}

Map<String, Object?> _rowToEventData(Map<String, Object?> row) {
  final String eventId = _asRequiredString(row['id'], field: 'id');
  final double timestamp = _coerceTimestampSeconds(row['timestamp']);
  final Map<String, Object?> actions = _decodeActions(row['actions']);
  final List<String> longRunningToolIds = _decodeLongRunningToolIds(
    row['long_running_tool_ids_json'],
  );

  final Map<String, Object?> eventData = <String, Object?>{
    'id': eventId,
    'invocation_id': '${row['invocation_id'] ?? ''}',
    'author': _asStringOr(row['author'], fallback: 'agent'),
    'actions': actions,
    'timestamp': timestamp,
  };

  _putIfNotNull(eventData, 'branch', row['branch']?.toString());
  if (longRunningToolIds.isNotEmpty) {
    eventData['long_running_tool_ids'] = longRunningToolIds;
  }
  _putIfNotNull(eventData, 'partial', _asNullableBool(row['partial']));
  _putIfNotNull(
    eventData,
    'turn_complete',
    _asNullableBool(row['turn_complete']),
  );
  _putIfNotNull(eventData, 'error_code', row['error_code']?.toString());
  _putIfNotNull(eventData, 'error_message', row['error_message']?.toString());
  _putIfNotNull(eventData, 'interrupted', _asNullableBool(row['interrupted']));

  _putIfNotNull(
    eventData,
    'custom_metadata',
    _decodeJsonObject(row['custom_metadata']),
  );
  _putIfNotNull(eventData, 'content', _decodeJsonObject(row['content']));
  _putIfNotNull(
    eventData,
    'grounding_metadata',
    _decodeJsonObject(row['grounding_metadata']),
  );
  _putIfNotNull(
    eventData,
    'usage_metadata',
    _decodeJsonObject(row['usage_metadata']),
  );
  _putIfNotNull(
    eventData,
    'citation_metadata',
    _decodeJsonObject(row['citation_metadata']),
  );
  _putIfNotNull(
    eventData,
    'input_transcription',
    _decodeJsonObject(row['input_transcription']),
  );
  _putIfNotNull(
    eventData,
    'output_transcription',
    _decodeJsonObject(row['output_transcription']),
  );

  return eventData;
}

Map<String, Object?> _decodeActions(Object? value) {
  final Object? decoded = _decodeJsonObject(value);
  if (decoded is Map) {
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  return <String, Object?>{};
}

List<String> _decodeLongRunningToolIds(Object? value) {
  if (value == null) {
    return <String>[];
  }
  final Object? decoded = _decodeJsonObject(value);
  if (decoded is List) {
    return decoded.map((Object? item) => '$item').toList(growable: false);
  }
  return <String>[];
}

Map<String, Object?> _decodeJsonMap(Object? value) {
  final Object? decoded = _decodeJsonObject(value);
  if (decoded is Map<String, Object?>) {
    return Map<String, Object?>.from(decoded);
  }
  if (decoded is Map) {
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  return <String, Object?>{};
}

Object? _decodeJsonObject(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map || value is List) {
    return value;
  }
  if (value is String) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }
  if (value is Uint8List) {
    if (value.isEmpty) {
      return null;
    }
    final String text = utf8.decode(value, allowMalformed: true).trim();
    if (text.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
  return null;
}

double _coerceTimestampSeconds(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('timestamp must not be empty');
    }
    final double? numeric = double.tryParse(trimmed);
    if (numeric != null) {
      return numeric;
    }
    final DateTime? parsed = _tryParseDateTime(trimmed);
    if (parsed != null) {
      return parsed.toUtc().millisecondsSinceEpoch / 1000;
    }
  }
  throw ArgumentError('timestamp is missing or malformed');
}

DateTime? _tryParseDateTime(String raw) {
  final DateTime? direct = DateTime.tryParse(raw);
  if (direct != null) {
    return direct;
  }

  final String normalized = raw.contains(' ')
      ? raw.replaceFirst(' ', 'T')
      : raw;
  final DateTime? normalizedParsed = DateTime.tryParse(normalized);
  if (normalizedParsed != null) {
    return normalizedParsed;
  }

  final RegExp legacy = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T'
    r'(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$',
  );
  final RegExpMatch? match = legacy.firstMatch(normalized);
  if (match == null) {
    return null;
  }

  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  final int hour = int.parse(match.group(4)!);
  final int minute = int.parse(match.group(5)!);
  final int second = int.parse(match.group(6)!);

  final String fractionRaw = (match.group(7) ?? '').padRight(6, '0');
  final int micros = fractionRaw.isEmpty ? 0 : int.parse(fractionRaw);
  final int milli = micros ~/ 1000;
  final int microRemainder = micros % 1000;

  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    milli,
    microRemainder,
  );
}

bool? _asNullableBool(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
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
  return null;
}

String _asRequiredString(Object? value, {required String field}) {
  final String result = '${value ?? ''}'.trim();
  if (result.isEmpty) {
    throw ArgumentError('$field is required');
  }
  return result;
}

String _asStringOr(Object? value, {required String fallback}) {
  final String result = '${value ?? ''}'.trim();
  return result.isEmpty ? fallback : result;
}

void _putIfNotNull(Map<String, Object?> map, String key, Object? value) {
  if (value != null) {
    map[key] = value;
  }
}
