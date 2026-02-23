import 'dart:convert';
import 'dart:io';

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
  if (!dbUrl.startsWith('sqlite:') && !dbUrl.startsWith('sqlite+aiosqlite:')) {
    return dbUrl;
  }
  final Uri uri = Uri.parse(dbUrl);
  String path = Uri.decodeComponent(uri.path);
  if (path.isEmpty) {
    return dbUrl;
  }
  if (path.startsWith('//')) {
    path = path.substring(1);
  } else if (path.startsWith('/')) {
    path = path.substring(1);
  }
  return path;
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
  final String path = resolveDbPath(toSyncUrl(dbUrl));
  final File file = File(path);
  if (!await file.exists()) {
    return latestSchemaVersion;
  }
  final String raw = await file.readAsString();
  if (raw.trim().isEmpty) {
    return latestSchemaVersion;
  }
  final Object? decoded = jsonDecode(raw);
  return getDbSchemaVersionFromDecoded(decoded);
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
