/// Agent replay test runner and event normalization utilities.
library;

import 'dart:convert';
import 'dart:io';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/apps/app.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/models/base_llm.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/models/llm_response.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/types/content.dart';
import 'utils/base_agent_loader.dart';

String _basenameWithoutExtension(String filePath) {
  final String cleaned = filePath.replaceAll(RegExp(r'[/\\]+$'), '');
  final String base = cleaned.split(RegExp(r'[/\\]')).last;
  if (base.endsWith('.test.json')) {
    return base.substring(0, base.length - '.test.json'.length);
  }
  final int dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// Event fields excluded when comparing recorded and replayed session events.
const Set<String> excludedEventFields = <String>{
  'timestamp',
  'start_time',
  'end_time',
  'model_version',
  'usage_metadata',
  'avg_logprobs',
};

/// Alias matching the Python constant name `EXCLUDED_EVENT_FIELDS`.
// ignore: constant_identifier_names
const Set<String> EXCLUDED_EVENT_FIELDS = excludedEventFields;

/// Finds all `*.test.json` files inside [agentDir] or its `tests` subdirectory.
List<File> getTestFiles(String agentDir) {
  final Directory root = Directory(agentDir);
  if (!root.existsSync()) {
    return const <File>[];
  }
  final List<File> files = <File>[];
  for (final FileSystemEntity entity in root.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.test.json')) {
      files.add(entity);
    }
  }
  files.sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

/// Mock LLM implementation that replays pre-recorded [LlmResponse] sequences.
class MockModel extends BaseLlm {
  /// Creates a [MockModel] with a queue of recorded responses per turn.
  MockModel({
    required List<List<LlmResponse>> responses,
    super.model = 'mock-model',
  }) : _responses = List<List<LlmResponse>>.from(responses);

  final List<List<LlmResponse>> _responses;
  int _callIndex = 0;

  /// Creates a [MockModel] by extracting assistant responses from recorded [events].
  factory MockModel.fromEvents(List<Map<String, Object?>> events) {
    final List<List<LlmResponse>> turns = <List<LlmResponse>>[];
    for (final Map<String, Object?> event in events) {
      final String? author = event['author'] as String?;
      if (author == null || author == 'user') {
        continue;
      }
      final Object? rawContent = event['content'];
      if (rawContent is! Map) {
        continue;
      }
      final Content content = _contentFromJson(
        Map<String, Object?>.from(rawContent),
      );
      turns.add(<LlmResponse>[
        LlmResponse(
          content: content,
          partial: event['partial'] as bool?,
          turnComplete: event['turn_complete'] as bool? ?? true,
        ),
      ]);
    }
    return MockModel(responses: turns);
  }

  /// Number of times [generateContent] has been called.
  int get callCount => _callIndex;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    if (_callIndex >= _responses.length) {
      return;
    }
    final List<LlmResponse> batch = _responses[_callIndex];
    _callIndex += 1;
    for (final LlmResponse response in batch) {
      yield response;
    }
  }
}

/// Extracts user message [Content] items from a list of serialized session events.
List<Content> extractUserContent(List<Map<String, Object?>> events) {
  final List<Content> contents = <Content>[];
  for (final Map<String, Object?> event in events) {
    if (event['author'] != 'user') {
      continue;
    }
    final Object? rawContent = event['content'];
    if (rawContent is Map) {
      contents.add(_contentFromJson(Map<String, Object?>.from(rawContent)));
    }
  }
  return contents;
}

/// Returns `true` if [event] contains a `function_response` whose ID is not yet
/// present in [idMap].
bool hasUnmappedFunctionResponse(
  Map<String, Object?> event,
  Map<String, String> idMap,
) {
  final Object? content = event['content'];
  if (content is! Map) {
    return false;
  }
  final Object? parts = content['parts'];
  if (parts is! List) {
    return false;
  }
  for (final Object? part in parts) {
    if (part is! Map) {
      continue;
    }
    final Object? fnResp =
        part['function_response'] ?? part['functionResponse'];
    if (fnResp is Map) {
      final String? id = fnResp['id'] as String?;
      if (id != null && id.isNotEmpty && !idMap.containsKey(id)) {
        return true;
      }
    }
  }
  return false;
}

/// Computes a deterministic sort key tuple representation for [event].
List<Object> makeSortKey(Map<String, Object?> event, int originalIndex) {
  final String branch = '${event['branch'] ?? ''}';
  final String author = '${event['author'] ?? ''}';
  return <Object>[branch, originalIndex, author];
}

/// Reorders parallel branch events into a deterministic sequential order while
/// ensuring `function_call` events precede their corresponding `function_response`.
List<Map<String, Object?>> makeNodesSequential(
  List<Map<String, Object?>> events,
) {
  final List<Map<String, Object?>> remaining =
      List<Map<String, Object?>>.from(events);
  final List<Map<String, Object?>> ordered = <Map<String, Object?>>[];
  final Map<String, String> seenCallIds = <String, String>{};

  while (remaining.isNotEmpty) {
    int selectedIndex = 0;
    for (int i = 0; i < remaining.length; i++) {
      if (!hasUnmappedFunctionResponse(remaining[i], seenCallIds)) {
        selectedIndex = i;
        break;
      }
    }
    final Map<String, Object?> chosen = remaining.removeAt(selectedIndex);
    _recordFunctionCallIds(chosen, seenCallIds);
    ordered.add(chosen);
  }
  return ordered;
}

void _recordFunctionCallIds(
  Map<String, Object?> event,
  Map<String, String> seenCallIds,
) {
  final Object? content = event['content'];
  if (content is! Map) {
    return;
  }
  final Object? parts = content['parts'];
  if (parts is! List) {
    return;
  }
  for (final Object? part in parts) {
    if (part is! Map) {
      continue;
    }
    final Object? fnCall = part['function_call'] ?? part['functionCall'];
    if (fnCall is Map) {
      final String? id = fnCall['id'] as String?;
      if (id != null && id.isNotEmpty) {
        seenCallIds[id] = id;
      }
    }
  }
}

/// Remaps a dot-separated node path using [nodeIdMap].
String remapNodePath(String path, Map<String, String> nodeIdMap) {
  if (path.isEmpty) {
    return path;
  }
  final List<String> segments = path.split('.');
  final List<String> mapped = segments.map((String seg) {
    final int colonIdx = seg.indexOf(':');
    if (colonIdx <= 0) {
      return nodeIdMap[seg] ?? seg;
    }
    final String prefix = seg.substring(0, colonIdx);
    final String rest = seg.substring(colonIdx + 1);
    final String mappedRest = nodeIdMap.putIfAbsent(
      rest,
      () => 'node_${nodeIdMap.length + 1}',
    );
    return '$prefix:$mappedRest';
  }).toList();
  return mapped.join('.');
}

/// Recursively remaps recorded IDs inside tool call / response argument structures.
Object? remapIdsInArgs(Object? value, Map<String, String> idMap) {
  if (value is String) {
    return idMap[value] ?? value;
  }
  if (value is List) {
    return value.map((Object? item) => remapIdsInArgs(item, idMap)).toList();
  }
  if (value is Map) {
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      result['${entry.key}'] = remapIdsInArgs(entry.value, idMap);
    }
    return result;
  }
  return value;
}

/// Normalizes dynamic UUIDs (`id`, `invocation_id`, `function_call.id`,
/// `function_response.id`, `branch`) across [events] into sequential placeholders.
List<Map<String, Object?>> normalizeIds(List<Map<String, Object?>> events) {
  final Map<String, String> eventIdMap = <String, String>{};
  final Map<String, String> invocationIdMap = <String, String>{};
  final Map<String, String> functionCallIdMap = <String, String>{};
  final Map<String, String> nodeIdMap = <String, String>{};

  return events.map((Map<String, Object?> rawEvent) {
    final Map<String, Object?> event = Map<String, Object?>.from(
      jsonDecode(jsonEncode(rawEvent)) as Map,
    );

    final String? id = event['id'] as String?;
    if (id != null && id.isNotEmpty) {
      event['id'] = eventIdMap.putIfAbsent(
        id,
        () => 'event_${eventIdMap.length + 1}',
      );
    }

    final String? invocationId =
        (event['invocation_id'] ?? event['invocationId']) as String?;
    if (invocationId != null && invocationId.isNotEmpty) {
      final String mappedInv = invocationIdMap.putIfAbsent(
        invocationId,
        () => 'inv_${invocationIdMap.length + 1}',
      );
      if (event.containsKey('invocationId')) {
        event['invocationId'] = mappedInv;
      } else {
        event['invocation_id'] = mappedInv;
      }
    }

    final String? branch = event['branch'] as String?;
    if (branch != null && branch.isNotEmpty) {
      event['branch'] = remapNodePath(branch, nodeIdMap);
    }

    final Object? content = event['content'];
    if (content is Map) {
      final Map<String, Object?> contentMap = Map<String, Object?>.from(content);
      final Object? parts = contentMap['parts'];
      if (parts is List) {
        contentMap['parts'] = parts.map((Object? rawPart) {
          if (rawPart is! Map) {
            return rawPart;
          }
          final Map<String, Object?> part = Map<String, Object?>.from(rawPart);
          for (final String key in const <String>[
            'function_call',
            'functionCall',
          ]) {
            if (part[key] is Map) {
              final Map<String, Object?> fnCall = Map<String, Object?>.from(
                part[key] as Map,
              );
              final String? callId = fnCall['id'] as String?;
              if (callId != null && callId.isNotEmpty) {
                fnCall['id'] = functionCallIdMap.putIfAbsent(
                  callId,
                  () => 'call_${functionCallIdMap.length + 1}',
                );
              }
              if (fnCall['args'] != null) {
                fnCall['args'] = remapIdsInArgs(
                  fnCall['args'],
                  functionCallIdMap,
                );
              }
              part[key] = fnCall;
            }
          }
          for (final String key in const <String>[
            'function_response',
            'functionResponse',
          ]) {
            if (part[key] is Map) {
              final Map<String, Object?> fnResp = Map<String, Object?>.from(
                part[key] as Map,
              );
              final String? callId = fnResp['id'] as String?;
              if (callId != null && callId.isNotEmpty) {
                fnResp['id'] = functionCallIdMap.putIfAbsent(
                  callId,
                  () => 'call_${functionCallIdMap.length + 1}',
                );
              }
              if (fnResp['response'] != null) {
                fnResp['response'] = remapIdsInArgs(
                  fnResp['response'],
                  functionCallIdMap,
                );
              }
              part[key] = fnResp;
            }
          }
          return part;
        }).toList();
      }
      event['content'] = contentMap;
    }

    return event;
  }).toList();
}

/// Normalizes a list of serialized session events by stripping excluded
/// volatile fields, ordering nodes sequentially, and normalizing dynamic IDs.
List<Map<String, Object?>> normalizeEvents(List<Map<String, Object?>> events) {
  final List<Map<String, Object?>> stripped = events.map((
    Map<String, Object?> raw,
  ) {
    final Map<String, Object?> copy = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in raw.entries) {
      if (!excludedEventFields.contains(entry.key)) {
        copy[entry.key] = entry.value;
      }
    }
    return copy;
  }).toList();

  final List<Map<String, Object?>> ordered = makeNodesSequential(stripped);
  return normalizeIds(ordered);
}

/// Runs a single agent replay test case against [rootAgent] (a [BaseAgent] or
/// workflow `BaseNode`) or [app] using recorded session JSON from [testFile].
Future<List<Map<String, Object?>>> runAgentReplayTest({
  Object? rootAgent,
  required File testFile,
  String? appName,
  App? app,
}) async {
  if (rootAgent == null && app == null) {
    throw ArgumentError('Either rootAgent or app must be provided.');
  }
  final BaseAgent? resolvedAgent =
      rootAgent == null ? null : asBaseAgent(rootAgent);
  final Object? decoded = jsonDecode(await testFile.readAsString());
  if (decoded is! Map) {
    throw FormatException('Invalid session test file: ${testFile.path}');
  }
  final Map<String, Object?> sessionJson = Map<String, Object?>.from(decoded);
  final List<Map<String, Object?>> recordedEvents =
      ((sessionJson['events'] as List?) ?? const <Object?>[])
          .whereType<Map>()
          .map((Map item) => Map<String, Object?>.from(item))
          .toList();

  final List<Content> userTurns = extractUserContent(recordedEvents);
  final String resolvedAppName =
      appName ??
      app?.name ??
      (sessionJson['app_name'] as String?) ??
      (sessionJson['appName'] as String?) ??
      _basenameWithoutExtension(testFile.path);
  final String userId =
      (sessionJson['user_id'] as String?) ??
      (sessionJson['userId'] as String?) ??
      'test_user';

  final Map<String, Object?> initialState = sessionJson['state'] is Map
      ? Map<String, Object?>.from(sessionJson['state'] as Map)
      : <String, Object?>{};

  final InMemoryRunner runner = app != null
      ? InMemoryRunner(app: app, appName: resolvedAppName)
      : InMemoryRunner(agent: resolvedAgent, appName: resolvedAppName);
  final Session session = await runner.sessionService.createSession(
    appName: resolvedAppName,
    userId: userId,
    state: initialState,
  );

  final List<Map<String, Object?>> actualEvents = <Map<String, Object?>>[];
  for (final Content userContent in userTurns) {
    final List<Event> turnEvents = <Event>[];
    await for (final Event event in runner.runAsync(
      userId: userId,
      sessionId: session.id,
      newMessage: userContent,
    )) {
      turnEvents.add(event);
    }
    final Event userEvent = Event(
      author: 'user',
      content: userContent,
      invocationId: turnEvents.isNotEmpty ? turnEvents.first.invocationId : '',
    );
    actualEvents.add(_eventToJson(userEvent));
    for (final Event event in turnEvents) {
      actualEvents.add(_eventToJson(event));
    }
  }

  final List<Map<String, Object?>> normalizedRecorded = normalizeEvents(
    recordedEvents,
  );
  final List<Map<String, Object?>> normalizedActual = normalizeEvents(
    actualEvents,
  );

  if (jsonEncode(normalizedRecorded) != jsonEncode(normalizedActual)) {
    throw StateError(
      'Replay test mismatch for ${testFile.path}.\n'
      'Expected: ${jsonEncode(normalizedRecorded)}\n'
      'Actual:   ${jsonEncode(normalizedActual)}',
    );
  }
  return actualEvents;
}

/// Rebuilds `*.test.json` files in [agentDir] by running [rootAgent] (a
/// [BaseAgent] or workflow `BaseNode`) or [app] and writing the updated event
/// stream back to disk.
Future<void> rebuildTests({
  Object? rootAgent,
  required String agentDir,
  String? appName,
  App? app,
}) async {
  if (rootAgent == null && app == null) {
    throw ArgumentError('Either rootAgent or app must be provided.');
  }
  final BaseAgent? resolvedAgent =
      rootAgent == null ? null : asBaseAgent(rootAgent);
  final List<File> testFiles = getTestFiles(agentDir);
  for (final File testFile in testFiles) {
    final Object? decoded = jsonDecode(await testFile.readAsString());
    if (decoded is! Map) {
      continue;
    }
    final Map<String, Object?> sessionJson = Map<String, Object?>.from(decoded);
    final List<Map<String, Object?>> recordedEvents =
        ((sessionJson['events'] as List?) ?? const <Object?>[])
            .whereType<Map>()
            .map((Map item) => Map<String, Object?>.from(item))
            .toList();
    final List<Content> userTurns = extractUserContent(recordedEvents);
    final String resolvedAppName =
        appName ??
        app?.name ??
        (sessionJson['app_name'] as String?) ??
        (sessionJson['appName'] as String?) ??
        _basenameWithoutExtension(testFile.path);
    final String userId =
        (sessionJson['user_id'] as String?) ??
        (sessionJson['userId'] as String?) ??
        'test_user';
    final Map<String, Object?> initialState = sessionJson['state'] is Map
        ? Map<String, Object?>.from(sessionJson['state'] as Map)
        : <String, Object?>{};

    final InMemoryRunner runner = app != null
        ? InMemoryRunner(app: app, appName: resolvedAppName)
        : InMemoryRunner(agent: resolvedAgent, appName: resolvedAppName);
    final Session session = await runner.sessionService.createSession(
      appName: resolvedAppName,
      userId: userId,
      state: initialState,
    );

    final List<Map<String, Object?>> rebuiltEvents = <Map<String, Object?>>[];
    for (final Content userContent in userTurns) {
      final List<Event> turnEvents = <Event>[];
      await for (final Event event in runner.runAsync(
        userId: userId,
        sessionId: session.id,
        newMessage: userContent,
      )) {
        turnEvents.add(event);
      }
      final Event userEvent = Event(
        author: 'user',
        content: userContent,
        invocationId: turnEvents.isNotEmpty
            ? turnEvents.first.invocationId
            : '',
      );
      rebuiltEvents.add(_eventToJson(userEvent));
      for (final Event event in turnEvents) {
        rebuiltEvents.add(_eventToJson(event));
      }
    }

    sessionJson['events'] = rebuiltEvents;
    await testFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(sessionJson)}\n',
    );
  }
}

Content _contentFromJson(Map<String, Object?> json) {
  final String? role = json['role'] as String?;
  final List<Part> parts = <Part>[];
  final Object? rawParts = json['parts'];
  if (rawParts is List) {
    for (final Object? item in rawParts) {
      if (item is! Map) {
        continue;
      }
      final Map<String, Object?> partMap = Map<String, Object?>.from(item);
      if (partMap['text'] is String) {
        parts.add(
          Part.text(
            partMap['text'] as String,
            thought: partMap['thought'] as bool? ?? false,
          ),
        );
      } else if (partMap['function_call'] is Map ||
          partMap['functionCall'] is Map) {
        final Map<String, Object?> fn = Map<String, Object?>.from(
          (partMap['function_call'] ?? partMap['functionCall']) as Map,
        );
        parts.add(
          Part.fromFunctionCall(
            name: '${fn['name'] ?? ''}',
            args: fn['args'] is Map
                ? Map<String, dynamic>.from(fn['args'] as Map)
                : <String, dynamic>{},
            id: fn['id'] as String?,
          ),
        );
      } else if (partMap['function_response'] is Map ||
          partMap['functionResponse'] is Map) {
        final Map<String, Object?> fn = Map<String, Object?>.from(
          (partMap['function_response'] ?? partMap['functionResponse']) as Map,
        );
        parts.add(
          Part.fromFunctionResponse(
            name: '${fn['name'] ?? ''}',
            response: fn['response'] is Map
                ? Map<String, dynamic>.from(fn['response'] as Map)
                : <String, dynamic>{},
            id: fn['id'] as String?,
          ),
        );
      }
    }
  }
  return Content(role: role, parts: parts);
}

Map<String, Object?> _eventToJson(Event event) {
  return <String, Object?>{
    'id': event.id,
    'invocation_id': event.invocationId,
    'author': event.author,
    if (event.branch != null) 'branch': event.branch,
    'timestamp': event.timestamp,
    if (event.content != null)
      'content': <String, Object?>{
        if (event.content!.role != null) 'role': event.content!.role,
        'parts': event.content!.parts.map((Part part) {
          return <String, Object?>{
            if (part.text != null) 'text': part.text,
            if (part.thought) 'thought': true,
            if (part.functionCall != null)
              'function_call': <String, Object?>{
                if (part.functionCall!.id != null) 'id': part.functionCall!.id,
                'name': part.functionCall!.name,
                'args': part.functionCall!.args,
              },
            if (part.functionResponse != null)
              'function_response': <String, Object?>{
                if (part.functionResponse!.id != null)
                  'id': part.functionResponse!.id,
                'name': part.functionResponse!.name,
                'response': part.functionResponse!.response,
              },
          };
        }).toList(),
      },
  };
}
