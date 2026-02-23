import 'dart:convert';
import 'dart:io';

import '../schemas/shared.dart';
import 'schema_check_utils.dart';

Future<void> migrateFromSqlalchemyPickle(
  String sourceDbUrl,
  String destDbUrl,
) async {
  final String sourcePath = resolveDbPath(toSyncUrl(sourceDbUrl));
  final String destPath = resolveDbPath(toSyncUrl(destDbUrl));

  final Map<String, Object?> sourceStore = await _loadStore(sourcePath);
  final Map<String, Object?> migrated = _deepCopyMap(sourceStore);

  final Map<String, Object?> metadata = _coerceMetadata(migrated);
  metadata[schemaVersionKey] = schemaVersion1Json;
  migrated['metadata'] = metadata;
  migrated['schemaVersion'] = schemaVersion1Json;

  final Object? sessionsRaw = migrated['sessions'];
  if (sessionsRaw is Map) {
    for (final MapEntry<Object?, Object?> appEntry in sessionsRaw.entries) {
      final Object? usersRaw = appEntry.value;
      if (usersRaw is! Map) {
        continue;
      }
      for (final MapEntry<Object?, Object?> userEntry in usersRaw.entries) {
        final Object? perSessionRaw = userEntry.value;
        if (perSessionRaw is! Map) {
          continue;
        }
        for (final MapEntry<Object?, Object?> sessionEntry
            in perSessionRaw.entries) {
          final Object? storedSessionRaw = sessionEntry.value;
          if (storedSessionRaw is! Map) {
            continue;
          }
          final Map<String, Object?> storedSession = storedSessionRaw.map(
            (Object? key, Object? value) => MapEntry('$key', value),
          );
          final Object? eventsRaw = storedSession['events'];
          if (eventsRaw is! List) {
            continue;
          }
          for (int i = 0; i < eventsRaw.length; i += 1) {
            final Object? eventRaw = eventsRaw[i];
            if (eventRaw is! Map) {
              continue;
            }
            final Map<String, Object?> event = eventRaw.map(
              (Object? key, Object? value) => MapEntry('$key', value),
            );
            if (event.containsKey('event_data') ||
                event.containsKey('eventData')) {
              continue;
            }
            event['event_data'] = _buildEventData(event);
            eventsRaw[i] = event;
          }
        }
      }
    }
  }

  final File destFile = File(destPath);
  await destFile.parent.create(recursive: true);
  await destFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(migrated),
  );
}

Map<String, Object?> _buildEventData(Map<String, Object?> event) {
  final Set<String> longRunningToolIds = _extractLongRunningToolIds(event);

  final Map<String, Object?> eventData = <String, Object?>{
    'id': event['id'],
    'invocation_id': event['invocation_id'] ?? event['invocationId'],
    'author': event['author'],
    'branch': event['branch'],
    'actions': event['actions'],
    'timestamp': event['timestamp'],
    if (longRunningToolIds.isNotEmpty)
      'long_running_tool_ids': longRunningToolIds.toList(growable: false),
    'partial': event['partial'],
    'turn_complete': event['turn_complete'] ?? event['turnComplete'],
    'finish_reason': event['finish_reason'] ?? event['finishReason'],
    'error_code': event['error_code'] ?? event['errorCode'],
    'error_message': event['error_message'] ?? event['errorMessage'],
    'interrupted': event['interrupted'],
    'custom_metadata': event['custom_metadata'] ?? event['customMetadata'],
    'content': event['content'],
    'usage_metadata': event['usage_metadata'] ?? event['usageMetadata'],
    'citation_metadata':
        event['citation_metadata'] ?? event['citationMetadata'],
    'input_transcription':
        event['input_transcription'] ?? event['inputTranscription'],
    'output_transcription':
        event['output_transcription'] ?? event['outputTranscription'],
    'model_version': event['model_version'] ?? event['modelVersion'],
    'avg_logprobs': event['avg_logprobs'] ?? event['avgLogprobs'],
    'logprobs_result': event['logprobs_result'] ?? event['logprobsResult'],
    'cache_metadata': event['cache_metadata'] ?? event['cacheMetadata'],
    'interaction_id': event['interaction_id'] ?? event['interactionId'],
  };

  eventData.removeWhere((String _, Object? value) => value == null);
  return eventData;
}

Set<String> _extractLongRunningToolIds(Map<String, Object?> event) {
  final Object? direct =
      event['long_running_tool_ids'] ?? event['longRunningToolIds'];
  if (direct is List) {
    return direct.map((Object? item) => '$item').toSet();
  }

  final Object? encoded =
      event['long_running_tool_ids_json'] ?? event['longRunningToolIdsJson'];
  if (encoded is String && encoded.isNotEmpty) {
    final Object? decoded = DynamicJson.decode(encoded);
    if (decoded is List) {
      return decoded.map((Object? item) => '$item').toSet();
    }
  }
  return <String>{};
}

Map<String, Object?> _coerceMetadata(Map<String, Object?> store) {
  final Object? raw = store['metadata'] ?? store['adk_internal_metadata'];
  if (raw is Map<String, Object?>) {
    return Map<String, Object?>.from(raw);
  }
  if (raw is Map) {
    return raw.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  return <String, Object?>{};
}

Future<Map<String, Object?>> _loadStore(String path) async {
  final File file = File(path);
  if (!await file.exists()) {
    return <String, Object?>{
      'sessions': <String, Object?>{},
      'appState': <String, Object?>{},
      'userState': <String, Object?>{},
    };
  }
  final String raw = await file.readAsString();
  if (raw.trim().isEmpty) {
    return <String, Object?>{
      'sessions': <String, Object?>{},
      'appState': <String, Object?>{},
      'userState': <String, Object?>{},
    };
  }
  final Object? decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) {
    return Map<String, Object?>.from(decoded);
  }
  if (decoded is Map) {
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  throw StateError('Unsupported store payload in $path.');
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> source) {
  return source.map((String key, Object? value) {
    return MapEntry<String, Object?>(key, _deepCopyValue(value));
  });
}

Object? _deepCopyValue(Object? value) {
  if (value is Map<String, Object?>) {
    return _deepCopyMap(value);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _deepCopyValue(item)),
    );
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList(growable: true);
  }
  return value;
}
