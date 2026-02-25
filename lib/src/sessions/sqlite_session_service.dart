import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors/already_exists_error.dart';
import '../events/event.dart';
import '../events/event_actions.dart';
import '../types/content.dart';
import '../types/id.dart';
import 'base_session_service.dart';
import 'session.dart';
import 'session_util.dart';
import 'state.dart';

class SqliteSessionService extends BaseSessionService {
  SqliteSessionService(String dbPath) : _storePath = _resolveStorePath(dbPath);

  final String _storePath;
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
      final _PersistedStore store = await _loadStore();

      if (store.sessions[appName]?[userId]?.containsKey(resolvedSessionId) ??
          false) {
        throw AlreadyExistsError(
          'Session with id $resolvedSessionId already exists.',
        );
      }

      final SessionStateDelta deltas = extractStateDelta(state);
      if (deltas.app.isNotEmpty) {
        store.appState
            .putIfAbsent(appName, () => <String, Object?>{})
            .addAll(deltas.app);
      }
      if (deltas.user.isNotEmpty) {
        store.userState
            .putIfAbsent(appName, () => <String, Map<String, Object?>>{})
            .putIfAbsent(userId, () => <String, Object?>{})
            .addAll(deltas.user);
      }

      final double now = DateTime.now().millisecondsSinceEpoch / 1000;
      store.sessions
          .putIfAbsent(appName, () => <String, Map<String, _StoredSession>>{})
          .putIfAbsent(
            userId,
            () => <String, _StoredSession>{},
          )[resolvedSessionId] = _StoredSession(
        state: Map<String, Object?>.from(deltas.session),
        events: <Map<String, Object?>>[],
        lastUpdateTime: now,
      );

      await _saveStore(store);

      final Session session = Session(
        id: resolvedSessionId,
        appName: appName,
        userId: userId,
        state: _mergeState(
          appState: store.appState[appName],
          userState: store.userState[appName]?[userId],
          sessionState: deltas.session,
        ),
        events: <Event>[],
        lastUpdateTime: now,
      );
      return session;
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
      final _PersistedStore store = await _loadStore();
      final _StoredSession? stored =
          store.sessions[appName]?[userId]?[sessionId];
      if (stored == null) {
        return null;
      }

      List<Event> events = stored.events
          .map((Map<String, Object?> eventJson) => _eventFromJson(eventJson))
          .toList();
      if (config != null) {
        if (config.afterTimestamp != null) {
          events = events
              .where((Event event) => event.timestamp >= config.afterTimestamp!)
              .toList();
        }
        if (config.numRecentEvents != null && config.numRecentEvents! > 0) {
          final int count = config.numRecentEvents!;
          if (events.length > count) {
            events = events.sublist(events.length - count);
          }
        }
      }

      return Session(
        id: sessionId,
        appName: appName,
        userId: userId,
        state: _mergeState(
          appState: store.appState[appName],
          userState: store.userState[appName]?[userId],
          sessionState: stored.state,
        ),
        events: events,
        lastUpdateTime: stored.lastUpdateTime,
      );
    });
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) {
    return _withLock<ListSessionsResponse>(() async {
      final _PersistedStore store = await _loadStore();
      final Map<String, Map<String, _StoredSession>> appSessions =
          store.sessions[appName] ?? <String, Map<String, _StoredSession>>{};
      final List<Session> result = <Session>[];

      if (userId == null) {
        for (final MapEntry<String, Map<String, _StoredSession>> userEntry
            in appSessions.entries) {
          for (final MapEntry<String, _StoredSession> entry
              in userEntry.value.entries) {
            result.add(
              Session(
                id: entry.key,
                appName: appName,
                userId: userEntry.key,
                state: _mergeState(
                  appState: store.appState[appName],
                  userState: store.userState[appName]?[userEntry.key],
                  sessionState: entry.value.state,
                ),
                events: <Event>[],
                lastUpdateTime: entry.value.lastUpdateTime,
              ),
            );
          }
        }
      } else {
        final Map<String, _StoredSession> userSessions =
            appSessions[userId] ?? <String, _StoredSession>{};
        for (final MapEntry<String, _StoredSession> entry
            in userSessions.entries) {
          result.add(
            Session(
              id: entry.key,
              appName: appName,
              userId: userId,
              state: _mergeState(
                appState: store.appState[appName],
                userState: store.userState[appName]?[userId],
                sessionState: entry.value.state,
              ),
              events: <Event>[],
              lastUpdateTime: entry.value.lastUpdateTime,
            ),
          );
        }
      }

      return ListSessionsResponse(sessions: result);
    });
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) {
    return _withLock<void>(() async {
      final _PersistedStore store = await _loadStore();
      store.sessions[appName]?[userId]?.remove(sessionId);
      await _saveStore(store);
    });
  }

  @override
  Future<Event> appendEvent({required Session session, required Event event}) {
    return _withLock<Event>(() async {
      if (event.partial == true) {
        return event;
      }
      final _PersistedStore store = await _loadStore();
      final _StoredSession? stored =
          store.sessions[session.appName]?[session.userId]?[session.id];
      if (stored == null) {
        throw StateError('Session ${session.id} not found.');
      }
      if (stored.lastUpdateTime > session.lastUpdateTime) {
        throw StateError(
          'The provided session has stale lastUpdateTime. Reload the session and retry.',
        );
      }

      final Event appended = await super.appendEvent(
        session: session,
        event: event,
      );
      stored.events.add(_eventToJson(appended));
      stored.lastUpdateTime = appended.timestamp;

      final SessionStateDelta delta = extractStateDelta(
        appended.actions.stateDelta,
      );
      if (delta.app.isNotEmpty) {
        store.appState
            .putIfAbsent(session.appName, () => <String, Object?>{})
            .addAll(delta.app);
      }
      if (delta.user.isNotEmpty) {
        store.userState
            .putIfAbsent(
              session.appName,
              () => <String, Map<String, Object?>>{},
            )
            .putIfAbsent(session.userId, () => <String, Object?>{})
            .addAll(delta.user);
      }
      if (delta.session.isNotEmpty) {
        stored.state.addAll(delta.session);
      }
      await _saveStore(store);
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

  Future<_PersistedStore> _loadStore() async {
    final File file = File(_storePath);
    if (!await file.exists()) {
      return _PersistedStore.empty();
    }
    final String content = await file.readAsString();
    if (content.trim().isEmpty) {
      return _PersistedStore.empty();
    }
    final Object? decoded = jsonDecode(content);
    if (decoded is Map) {
      return _PersistedStore.fromJson(
        decoded.map((Object? key, Object? value) => MapEntry('$key', value)),
      );
    }
    return _PersistedStore.empty();
  }

  Future<void> _saveStore(_PersistedStore store) async {
    final File file = File(_storePath);
    await file.parent.create(recursive: true);
    final String jsonText = const JsonEncoder.withIndent(
      '  ',
    ).convert(store.toJson());
    await file.writeAsString(jsonText);
  }
}

class _PersistedStore {
  _PersistedStore({
    required this.sessions,
    required this.appState,
    required this.userState,
  });

  factory _PersistedStore.empty() {
    return _PersistedStore(
      sessions: <String, Map<String, Map<String, _StoredSession>>>{},
      appState: <String, Map<String, Object?>>{},
      userState: <String, Map<String, Map<String, Object?>>>{},
    );
  }

  final Map<String, Map<String, Map<String, _StoredSession>>> sessions;
  final Map<String, Map<String, Object?>> appState;
  final Map<String, Map<String, Map<String, Object?>>> userState;

  factory _PersistedStore.fromJson(Map<String, Object?> json) {
    final Map<String, Map<String, Map<String, _StoredSession>>> sessions =
        <String, Map<String, Map<String, _StoredSession>>>{};
    final Map<String, Object?> rawSessions = _castMap(json['sessions']);
    rawSessions.forEach((String appName, Object? usersValue) {
      final Map<String, Map<String, _StoredSession>> byUser =
          <String, Map<String, _StoredSession>>{};
      final Map<String, Object?> usersMap = _castMap(usersValue);
      usersMap.forEach((String userId, Object? sessionValue) {
        final Map<String, _StoredSession> bySession =
            <String, _StoredSession>{};
        final Map<String, Object?> sessionsMap = _castMap(sessionValue);
        sessionsMap.forEach((String sessionId, Object? storedValue) {
          bySession[sessionId] = _StoredSession.fromJson(_castMap(storedValue));
        });
        byUser[userId] = bySession;
      });
      sessions[appName] = byUser;
    });

    final Map<String, Map<String, Object?>> appState =
        <String, Map<String, Object?>>{};
    _castMap(json['appState']).forEach((String appName, Object? value) {
      appState[appName] = _castMap(value);
    });

    final Map<String, Map<String, Map<String, Object?>>> userState =
        <String, Map<String, Map<String, Object?>>>{};
    _castMap(json['userState']).forEach((String appName, Object? value) {
      final Map<String, Map<String, Object?>> byUser =
          <String, Map<String, Object?>>{};
      _castMap(value).forEach((String userId, Object? userMap) {
        byUser[userId] = _castMap(userMap);
      });
      userState[appName] = byUser;
    });

    return _PersistedStore(
      sessions: sessions,
      appState: appState,
      userState: userState,
    );
  }

  Map<String, Object?> toJson() {
    final Map<String, Object?> encodedSessions = <String, Object?>{};
    sessions.forEach((
      String appName,
      Map<String, Map<String, _StoredSession>> byUser,
    ) {
      final Map<String, Object?> encodedUsers = <String, Object?>{};
      byUser.forEach((String userId, Map<String, _StoredSession> bySession) {
        final Map<String, Object?> encodedPerSession = <String, Object?>{};
        bySession.forEach((String sessionId, _StoredSession stored) {
          encodedPerSession[sessionId] = stored.toJson();
        });
        encodedUsers[userId] = encodedPerSession;
      });
      encodedSessions[appName] = encodedUsers;
    });
    return <String, Object?>{
      'sessions': encodedSessions,
      'appState': appState,
      'userState': userState,
    };
  }
}

class _StoredSession {
  _StoredSession({
    required this.state,
    required this.events,
    required this.lastUpdateTime,
  });

  final Map<String, Object?> state;
  final List<Map<String, Object?>> events;
  double lastUpdateTime;

  factory _StoredSession.fromJson(Map<String, Object?> json) {
    final List<Map<String, Object?>> events = <Map<String, Object?>>[];
    final Object? rawEvents = json['events'];
    if (rawEvents is List) {
      for (final Object? item in rawEvents) {
        if (item is Map) {
          events.add(_castMap(item));
        }
      }
    }
    return _StoredSession(
      state: _castMap(json['state']),
      events: events,
      lastUpdateTime: _asDouble(json['lastUpdateTime']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state,
      'events': events,
      'lastUpdateTime': lastUpdateTime,
    };
  }
}

String _resolveStorePath(String dbPath) {
  if (!dbPath.startsWith('sqlite:') &&
      !dbPath.startsWith('sqlite+aiosqlite:')) {
    return dbPath;
  }
  final Uri uri = Uri.parse(dbPath);
  String path = Uri.decodeComponent(uri.path);
  if (path.isEmpty) {
    return dbPath;
  }
  if (path.startsWith('//')) {
    path = path.substring(1);
  } else if (path.startsWith('/')) {
    path = path.substring(1);
  }
  return path;
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
