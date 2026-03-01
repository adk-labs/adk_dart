import 'dart:io';

import 'sqlite_db.dart';

const String schemaVersionKey = 'schema_version';
const String schemaVersion0Pickle = '0';
const String schemaVersion1Json = '1';
const String latestSchemaVersion = schemaVersion1Json;

String toSyncUrl(String dbUrl) {
  if (!dbUrl.contains('://')) {
    return dbUrl;
  }
  final List<String> split = dbUrl.split('://');
  if (split.length < 2) {
    return dbUrl;
  }
  final String scheme = split.first;
  final String rest = dbUrl.substring(scheme.length + 3);
  if (!scheme.contains('+')) {
    return dbUrl;
  }
  final String dialect = scheme.split('+').first;
  return '$dialect://$rest';
}

String resolveDbPath(String dbUrl) {
  final String normalized = dbUrl.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  if (!normalized.startsWith('sqlite:') &&
      !normalized.startsWith('sqlite+aiosqlite:')) {
    return normalized;
  }
  return resolveSqliteDbUrl(
    toSyncUrl(normalized),
    argumentName: 'dbUrl',
  ).storePath;
}

String getDbSchemaVersionFromConnection(SqliteMigrationDatabase db) {
  return _getSchemaVersionImpl(db);
}

String getDbSchemaVersionFromDecoded(Object? decoded) {
  if (decoded is! Map) {
    return latestSchemaVersion;
  }

  final Map<String, Object?> map = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );

  final String? fromMetadata = _schemaVersionFromMetadata(
    map['adk_internal_metadata'] ?? map['metadata'],
  );
  if (fromMetadata != null) {
    return fromMetadata;
  }

  final Object? topLevelVersion = map['schemaVersion'] ?? map['schema_version'];
  if (topLevelVersion != null && '$topLevelVersion'.isNotEmpty) {
    return '$topLevelVersion';
  }

  for (final Map<String, Object?> event in _iterEventsFromStore(map)) {
    if (event.containsKey('event_data') || event.containsKey('eventData')) {
      return schemaVersion1Json;
    }
    if (event.containsKey('actions')) {
      return schemaVersion0Pickle;
    }
  }

  return latestSchemaVersion;
}

Future<String> getDbSchemaVersion(String dbUrl) async {
  final String normalizedUrl = toSyncUrl(dbUrl.trim());
  final ResolvedSqliteDbUrl resolved = resolveSqliteDbUrl(
    normalizedUrl,
    argumentName: 'dbUrl',
  );
  if (!resolved.inMemory &&
      !resolved.storePath.startsWith('file:') &&
      !await File(resolved.storePath).exists()) {
    return latestSchemaVersion;
  }

  final SqliteMigrationDatabase db = SqliteMigrationDatabase.open(
    connectPath: resolved.connectPath,
    displayPath: resolved.storePath,
    uri: resolved.connectUri,
    readOnly: true,
  );
  try {
    return _getSchemaVersionImpl(db);
  } finally {
    db.dispose();
  }
}

String? _schemaVersionFromMetadata(Object? metadata) {
  if (metadata is Map) {
    final Map<String, Object?> map = metadata.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    final Object? direct = map[schemaVersionKey];
    if (direct != null && '$direct'.isNotEmpty) {
      return '$direct';
    }
    if (map.containsKey('key') && map.containsKey('value')) {
      if ('${map['key']}' == schemaVersionKey) {
        return '${map['value']}';
      }
    }
  }
  if (metadata is List) {
    for (final Object? item in metadata) {
      if (item is! Map) {
        continue;
      }
      final Map<String, Object?> row = item.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      if ('${row['key']}' == schemaVersionKey &&
          row['value'] != null &&
          '${row['value']}'.isNotEmpty) {
        return '${row['value']}';
      }
    }
  }
  return null;
}

Iterable<Map<String, Object?>> _iterEventsFromStore(
  Map<String, Object?> map,
) sync* {
  final Object? sessionsRaw = map['sessions'];
  if (sessionsRaw is! Map) {
    return;
  }

  for (final Object? usersValue in sessionsRaw.values) {
    if (usersValue is! Map) {
      continue;
    }
    for (final Object? sessionValue in usersValue.values) {
      if (sessionValue is! Map) {
        continue;
      }
      for (final Object? storedSession in sessionValue.values) {
        if (storedSession is! Map) {
          continue;
        }
        final Map<String, Object?> stored = storedSession.map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
        final Object? eventsRaw = stored['events'];
        if (eventsRaw is! List) {
          continue;
        }
        for (final Object? eventRaw in eventsRaw) {
          if (eventRaw is! Map) {
            continue;
          }
          yield eventRaw.map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
        }
      }
    }
  }
}

String _getSchemaVersionImpl(SqliteMigrationDatabase db) {
  if (db.hasTable('adk_internal_metadata')) {
    final List<Map<String, Object?>> rows = db.query(
      'SELECT value FROM adk_internal_metadata WHERE key=? LIMIT 1',
      <Object?>[schemaVersionKey],
    );
    if (rows.isEmpty || rows.first['value'] == null) {
      throw StateError(
        'Schema version not found in adk_internal_metadata. '
        'The database might be malformed.',
      );
    }
    final String value = '${rows.first['value']}'.trim();
    if (value.isEmpty) {
      throw StateError(
        'Schema version not found in adk_internal_metadata. '
        'The database might be malformed.',
      );
    }
    return value;
  }

  if (db.hasTable('events')) {
    final Set<String> columns = db.tableColumns('events');
    if (columns.contains('actions') && !columns.contains('event_data')) {
      return schemaVersion0Pickle;
    }
  }

  return latestSchemaVersion;
}
