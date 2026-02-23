import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../sessions/session.dart';
import '../../types/content.dart';
import 'shared.dart';

class StorageSessionV0 {
  StorageSessionV0({
    required this.appName,
    required this.userId,
    required this.id,
    Map<String, Object?>? state,
    DateTime? createTime,
    DateTime? updateTime,
    List<StorageEventV0>? storageEvents,
  }) : state = state ?? <String, Object?>{},
       createTime = createTime ?? DateTime.now().toUtc(),
       updateTime = updateTime ?? DateTime.now().toUtc(),
       storageEvents = storageEvents ?? <StorageEventV0>[];

  final String appName;
  final String userId;
  final String id;
  final Map<String, Object?> state;
  final DateTime createTime;
  final DateTime updateTime;
  final List<StorageEventV0> storageEvents;

  factory StorageSessionV0.fromJson(Map<String, Object?> json) {
    final List<StorageEventV0> events = <StorageEventV0>[];
    final Object? rawEvents = json['storage_events'] ?? json['storageEvents'];
    if (rawEvents is List) {
      for (final Object? item in rawEvents) {
        if (item is Map<String, Object?>) {
          events.add(StorageEventV0.fromJson(item));
        } else if (item is Map) {
          events.add(
            StorageEventV0.fromJson(
              item.map((Object? key, Object? value) => MapEntry('$key', value)),
            ),
          );
        }
      }
    }

    return StorageSessionV0(
      appName: '${json['app_name'] ?? json['appName'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
      id: '${json['id'] ?? ''}',
      state: _castMap(json['state']),
      createTime: _parseDateTime(json['create_time'] ?? json['createTime']),
      updateTime: _parseDateTime(json['update_time'] ?? json['updateTime']),
      storageEvents: events,
    );
  }

  double getUpdateTimestamp({bool isSqlite = false}) {
    return PreciseTimestamp.toSeconds(updateTime);
  }

  Session toSession({
    Map<String, Object?>? stateOverride,
    List<Event>? events,
    bool isSqlite = false,
  }) {
    return Session(
      appName: appName,
      userId: userId,
      id: id,
      state: stateOverride ?? <String, Object?>{},
      events: events ?? <Event>[],
      lastUpdateTime: getUpdateTimestamp(isSqlite: isSqlite),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'id': id,
      'state': state,
      'create_time': createTime.toUtc().toIso8601String(),
      'update_time': updateTime.toUtc().toIso8601String(),
      'storage_events': storageEvents
          .map((StorageEventV0 event) => event.toJson())
          .toList(growable: false),
    };
  }
}

class StorageEventV0 {
  StorageEventV0({
    required this.id,
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.invocationId,
    required this.author,
    EventActions? actions,
    this.longRunningToolIdsJson,
    this.branch,
    DateTime? timestamp,
    this.content,
    this.customMetadata,
    this.usageMetadata,
    this.citationMetadata,
    this.partial,
    this.turnComplete,
    this.finishReason,
    this.errorCode,
    this.errorMessage,
    this.interrupted,
    this.inputTranscription,
    this.outputTranscription,
    this.modelVersion,
    this.avgLogprobs,
    this.logprobsResult,
    this.cacheMetadata,
    this.interactionId,
  }) : actions = actions ?? EventActions(),
       timestamp = timestamp ?? DateTime.now().toUtc();

  final String id;
  final String appName;
  final String userId;
  final String sessionId;
  final String invocationId;
  final String author;
  final EventActions actions;
  final String? longRunningToolIdsJson;
  final String? branch;
  final DateTime timestamp;
  final Content? content;
  final Map<String, dynamic>? customMetadata;
  final Object? usageMetadata;
  final Object? citationMetadata;
  final bool? partial;
  final bool? turnComplete;
  final String? finishReason;
  final String? errorCode;
  final String? errorMessage;
  final bool? interrupted;
  final Object? inputTranscription;
  final Object? outputTranscription;
  final String? modelVersion;
  final double? avgLogprobs;
  final Object? logprobsResult;
  final Object? cacheMetadata;
  final String? interactionId;

  factory StorageEventV0.fromJson(Map<String, Object?> json) {
    return StorageEventV0(
      id: '${json['id'] ?? ''}',
      appName: '${json['app_name'] ?? json['appName'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
      sessionId: '${json['session_id'] ?? json['sessionId'] ?? ''}',
      invocationId: '${json['invocation_id'] ?? json['invocationId'] ?? ''}',
      author: '${json['author'] ?? ''}',
      actions: _eventActionsFromJson(_castMap(json['actions'])),
      longRunningToolIdsJson:
          json['long_running_tool_ids_json']?.toString() ??
          json['longRunningToolIdsJson']?.toString(),
      branch: json['branch']?.toString(),
      timestamp: _parseDateTime(json['timestamp']),
      content: json['content'] is Map
          ? _contentFromJson(_castMap(json['content']))
          : null,
      customMetadata: _castDynamicMap(
        json['custom_metadata'] ?? json['customMetadata'],
      ),
      usageMetadata: json['usage_metadata'] ?? json['usageMetadata'],
      citationMetadata: json['citation_metadata'] ?? json['citationMetadata'],
      partial: json['partial'] as bool?,
      turnComplete: (json['turn_complete'] ?? json['turnComplete']) as bool?,
      finishReason: (json['finish_reason'] ?? json['finishReason'])?.toString(),
      errorCode: (json['error_code'] ?? json['errorCode'])?.toString(),
      errorMessage: (json['error_message'] ?? json['errorMessage'])?.toString(),
      interrupted: json['interrupted'] as bool?,
      inputTranscription:
          json['input_transcription'] ?? json['inputTranscription'],
      outputTranscription:
          json['output_transcription'] ?? json['outputTranscription'],
      modelVersion: (json['model_version'] ?? json['modelVersion'])?.toString(),
      avgLogprobs: _asNullableDouble(
        json['avg_logprobs'] ?? json['avgLogprobs'],
      ),
      logprobsResult: json['logprobs_result'] ?? json['logprobsResult'],
      cacheMetadata: json['cache_metadata'] ?? json['cacheMetadata'],
      interactionId: (json['interaction_id'] ?? json['interactionId'])
          ?.toString(),
    );
  }

  factory StorageEventV0.fromEvent({
    required Session session,
    required Event event,
  }) {
    return StorageEventV0(
      id: event.id,
      appName: session.appName,
      userId: session.userId,
      sessionId: session.id,
      invocationId: event.invocationId,
      author: event.author,
      actions: event.actions.copyWith(),
      longRunningToolIdsJson: event.longRunningToolIds == null
          ? null
          : '[${event.longRunningToolIds!.map((String v) => '"$v"').join(',')}]',
      branch: event.branch,
      timestamp: PreciseTimestamp.fromSeconds(event.timestamp),
      content: event.content?.copyWith(),
      customMetadata: event.customMetadata == null
          ? null
          : Map<String, dynamic>.from(event.customMetadata!),
      usageMetadata: event.usageMetadata,
      citationMetadata: event.citationMetadata,
      partial: event.partial,
      turnComplete: event.turnComplete,
      finishReason: event.finishReason,
      errorCode: event.errorCode,
      errorMessage: event.errorMessage,
      interrupted: event.interrupted,
      inputTranscription: event.inputTranscription,
      outputTranscription: event.outputTranscription,
      modelVersion: event.modelVersion,
      avgLogprobs: event.avgLogprobs,
      logprobsResult: event.logprobsResult,
      cacheMetadata: event.cacheMetadata,
      interactionId: event.interactionId,
    );
  }

  Set<String> get longRunningToolIds {
    final String? raw = longRunningToolIdsJson;
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    final Object? decoded = DynamicJson.decode(raw);
    if (decoded is List) {
      return decoded.map((Object? item) => '$item').toSet();
    }
    return <String>{};
  }

  Event toEvent() {
    return Event(
      id: id,
      invocationId: invocationId,
      author: author,
      branch: branch,
      actions: actions.copyWith(),
      timestamp: PreciseTimestamp.toSeconds(timestamp),
      longRunningToolIds: longRunningToolIds,
      partial: partial,
      turnComplete: turnComplete,
      finishReason: finishReason,
      errorCode: errorCode,
      errorMessage: errorMessage,
      interrupted: interrupted,
      customMetadata: customMetadata == null
          ? null
          : Map<String, dynamic>.from(customMetadata!),
      content: content?.copyWith(),
      usageMetadata: usageMetadata,
      citationMetadata: citationMetadata,
      inputTranscription: inputTranscription,
      outputTranscription: outputTranscription,
      modelVersion: modelVersion,
      avgLogprobs: avgLogprobs,
      logprobsResult: logprobsResult,
      cacheMetadata: cacheMetadata,
      interactionId: interactionId,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
      'invocation_id': invocationId,
      'author': author,
      'actions': _eventActionsToJson(actions),
      if (longRunningToolIdsJson != null)
        'long_running_tool_ids_json': longRunningToolIdsJson,
      if (branch != null) 'branch': branch,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (content != null) 'content': _contentToJson(content!),
      if (customMetadata != null) 'custom_metadata': customMetadata,
      if (usageMetadata != null) 'usage_metadata': usageMetadata,
      if (citationMetadata != null) 'citation_metadata': citationMetadata,
      if (partial != null) 'partial': partial,
      if (turnComplete != null) 'turn_complete': turnComplete,
      if (finishReason != null) 'finish_reason': finishReason,
      if (errorCode != null) 'error_code': errorCode,
      if (errorMessage != null) 'error_message': errorMessage,
      if (interrupted != null) 'interrupted': interrupted,
      if (inputTranscription != null) 'input_transcription': inputTranscription,
      if (outputTranscription != null)
        'output_transcription': outputTranscription,
      if (modelVersion != null) 'model_version': modelVersion,
      if (avgLogprobs != null) 'avg_logprobs': avgLogprobs,
      if (logprobsResult != null) 'logprobs_result': logprobsResult,
      if (cacheMetadata != null) 'cache_metadata': cacheMetadata,
      if (interactionId != null) 'interaction_id': interactionId,
    };
  }
}

class StorageAppStateV0 {
  StorageAppStateV0({
    required this.appName,
    Map<String, Object?>? state,
    DateTime? updateTime,
  }) : state = state ?? <String, Object?>{},
       updateTime = updateTime ?? DateTime.now().toUtc();

  final String appName;
  final Map<String, Object?> state;
  final DateTime updateTime;

  factory StorageAppStateV0.fromJson(Map<String, Object?> json) {
    return StorageAppStateV0(
      appName: '${json['app_name'] ?? json['appName'] ?? ''}',
      state: _castMap(json['state']),
      updateTime: _parseDateTime(json['update_time'] ?? json['updateTime']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'app_name': appName,
      'state': state,
      'update_time': updateTime.toUtc().toIso8601String(),
    };
  }
}

class StorageUserStateV0 {
  StorageUserStateV0({
    required this.appName,
    required this.userId,
    Map<String, Object?>? state,
    DateTime? updateTime,
  }) : state = state ?? <String, Object?>{},
       updateTime = updateTime ?? DateTime.now().toUtc();

  final String appName;
  final String userId;
  final Map<String, Object?> state;
  final DateTime updateTime;

  factory StorageUserStateV0.fromJson(Map<String, Object?> json) {
    return StorageUserStateV0(
      appName: '${json['app_name'] ?? json['appName'] ?? ''}',
      userId: '${json['user_id'] ?? json['userId'] ?? ''}',
      state: _castMap(json['state']),
      updateTime: _parseDateTime(json['update_time'] ?? json['updateTime']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'app_name': appName,
      'user_id': userId,
      'state': state,
      'update_time': updateTime.toUtc().toIso8601String(),
    };
  }
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

Map<String, Object?> _contentToJson(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map(_partToJson).toList(growable: false),
  };
}

Content _contentFromJson(Map<String, Object?> json) {
  final List<Part> parts = <Part>[];
  final Object? rawParts = json['parts'];
  if (rawParts is List) {
    for (final Object? item in rawParts) {
      if (item is Map<String, Object?>) {
        parts.add(_partFromJson(item));
      } else if (item is Map) {
        parts.add(
          _partFromJson(
            item.map((Object? key, Object? value) => MapEntry('$key', value)),
          ),
        );
      }
    }
  }
  return Content(role: json['role'] as String?, parts: parts);
}

Map<String, Object?> _partToJson(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    'thought': part.thought,
    if (part.functionCall != null)
      'functionCall': <String, Object?>{
        'name': part.functionCall!.name,
        'args': part.functionCall!.args,
        if (part.functionCall!.id != null) 'id': part.functionCall!.id,
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
    final Map<String, Object?> map = _castMap(json['functionCall']);
    functionCall = FunctionCall(
      name: '${map['name'] ?? ''}',
      args: _castDynamicMap(map['args']) ?? <String, dynamic>{},
      id: map['id'] as String?,
    );
  }

  FunctionResponse? functionResponse;
  if (json['functionResponse'] is Map) {
    final Map<String, Object?> map = _castMap(json['functionResponse']);
    functionResponse = FunctionResponse(
      name: '${map['name'] ?? ''}',
      response: _castDynamicMap(map['response']) ?? <String, dynamic>{},
      id: map['id'] as String?,
    );
  }

  InlineData? inlineData;
  if (json['inlineData'] is Map) {
    final Map<String, Object?> map = _castMap(json['inlineData']);
    inlineData = InlineData(
      mimeType: '${map['mimeType'] ?? ''}',
      data: _castIntList(map['data']),
      displayName: map['displayName'] as String?,
    );
  }

  FileData? fileData;
  if (json['fileData'] is Map) {
    final Map<String, Object?> map = _castMap(json['fileData']);
    fileData = FileData(
      fileUri: '${map['fileUri'] ?? ''}',
      mimeType: map['mimeType'] as String?,
      displayName: map['displayName'] as String?,
    );
  }

  return Part(
    text: json['text'] as String?,
    thought: (json['thought'] as bool?) ?? false,
    functionCall: functionCall,
    functionResponse: functionResponse,
    inlineData: inlineData,
    fileData: fileData,
    executableCode: json['executableCode'],
    codeExecutionResult: json['codeExecutionResult'],
  );
}

Map<String, Object?> _castMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, dynamic>? _castDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return null;
}

Map<String, Object> _castObjectMap(Object? value) {
  if (value is Map<String, Object>) {
    return Map<String, Object>.from(value);
  }
  if (value is Map) {
    final Map<String, Object> casted = <String, Object>{};
    value.forEach((Object? key, Object? item) {
      if (item != null) {
        casted['$key'] = item;
      }
    });
    return casted;
  }
  return <String, Object>{};
}

Map<String, int> _castIntMap(Object? value) {
  if (value is Map<String, int>) {
    return Map<String, int>.from(value);
  }
  if (value is Map) {
    final Map<String, int> casted = <String, int>{};
    value.forEach((Object? key, Object? item) {
      if (item is int) {
        casted['$key'] = item;
      } else if (item is num) {
        casted['$key'] = item.toInt();
      }
    });
    return casted;
  }
  return <String, int>{};
}

List<int> _castIntList(Object? value) {
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    return value
        .whereType<num>()
        .map((num item) => item.toInt())
        .toList(growable: false);
  }
  return <int>[];
}

DateTime _parseDateTime(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is num) {
    return PreciseTimestamp.fromSeconds(value);
  }
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
    final double? asDouble = double.tryParse(value);
    if (asDouble != null) {
      return PreciseTimestamp.fromSeconds(asDouble);
    }
  }
  return DateTime.now().toUtc();
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}

double? _asNullableDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
