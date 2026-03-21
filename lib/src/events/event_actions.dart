/// Event action models used to carry side-channel run instructions.
library;

import '../types/content.dart';
import 'ui_widget.dart';

/// Compaction summary metadata attached to an event.
class EventCompaction {
  /// Creates event compaction metadata.
  EventCompaction({
    required this.startTimestamp,
    required this.endTimestamp,
    required this.compactedContent,
  });

  /// Start timestamp of the compacted range.
  double startTimestamp;

  /// End timestamp of the compacted range.
  double endTimestamp;

  /// Compacted content payload.
  Content compactedContent;
}

/// Mutable action payload attached to one event.
class EventActions {
  /// Creates event actions.
  EventActions({
    this.skipSummarization,
    Map<String, Object?>? stateDelta,
    Map<String, int>? artifactDelta,
    this.transferToAgent,
    this.escalate,
    Map<String, Object>? requestedAuthConfigs,
    Map<String, Object>? requestedToolConfirmations,
    this.compaction,
    this.endOfAgent,
    this.agentState,
    this.rewindBeforeInvocationId,
    List<UiWidget>? renderUiWidgets,
  }) : stateDelta = stateDelta ?? <String, Object?>{},
       artifactDelta = artifactDelta ?? <String, int>{},
       requestedAuthConfigs = requestedAuthConfigs ?? <String, Object>{},
       requestedToolConfirmations =
           requestedToolConfirmations ?? <String, Object>{},
       renderUiWidgets = renderUiWidgets ?? <UiWidget>[];

  /// Whether this event should be excluded from summarization.
  bool? skipSummarization;

  /// State updates produced by the event.
  Map<String, Object?> stateDelta;

  /// Artifact version deltas produced by the event.
  Map<String, int> artifactDelta;

  /// Optional target agent name for transfer.
  String? transferToAgent;

  /// Whether escalation was requested.
  bool? escalate;

  /// Requested auth configurations keyed by tool/operation.
  Map<String, Object> requestedAuthConfigs;

  /// Requested tool confirmations keyed by tool/operation.
  Map<String, Object> requestedToolConfirmations;

  /// Optional compaction metadata.
  EventCompaction? compaction;

  /// Whether this marks the end of the agent run.
  bool? endOfAgent;

  /// Optional serialized agent state snapshot.
  Map<String, Object?>? agentState;

  /// Optional invocation ID to rewind before replay.
  String? rewindBeforeInvocationId;

  /// UI widgets that the client should render for this event.
  List<UiWidget> renderUiWidgets;

  /// Returns copied actions with optional overrides.
  EventActions copyWith({
    Object? skipSummarization = _sentinel,
    Map<String, Object?>? stateDelta,
    Map<String, int>? artifactDelta,
    Object? transferToAgent = _sentinel,
    Object? escalate = _sentinel,
    Map<String, Object>? requestedAuthConfigs,
    Map<String, Object>? requestedToolConfirmations,
    Object? compaction = _sentinel,
    Object? endOfAgent = _sentinel,
    Object? agentState = _sentinel,
    Object? rewindBeforeInvocationId = _sentinel,
    List<UiWidget>? renderUiWidgets,
  }) {
    return EventActions(
      skipSummarization: identical(skipSummarization, _sentinel)
          ? this.skipSummarization
          : skipSummarization as bool?,
      stateDelta: stateDelta ?? Map<String, Object?>.from(this.stateDelta),
      artifactDelta: artifactDelta ?? Map<String, int>.from(this.artifactDelta),
      transferToAgent: identical(transferToAgent, _sentinel)
          ? this.transferToAgent
          : transferToAgent as String?,
      escalate: identical(escalate, _sentinel)
          ? this.escalate
          : escalate as bool?,
      requestedAuthConfigs:
          requestedAuthConfigs ??
          Map<String, Object>.from(this.requestedAuthConfigs),
      requestedToolConfirmations:
          requestedToolConfirmations ??
          Map<String, Object>.from(this.requestedToolConfirmations),
      compaction: identical(compaction, _sentinel)
          ? this.compaction
          : compaction as EventCompaction?,
      endOfAgent: identical(endOfAgent, _sentinel)
          ? this.endOfAgent
          : endOfAgent as bool?,
      agentState: identical(agentState, _sentinel)
          ? (this.agentState == null
                ? null
                : Map<String, Object?>.from(this.agentState!))
          : agentState as Map<String, Object?>?,
      rewindBeforeInvocationId: identical(rewindBeforeInvocationId, _sentinel)
          ? this.rewindBeforeInvocationId
          : rewindBeforeInvocationId as String?,
      renderUiWidgets:
          renderUiWidgets ??
          this.renderUiWidgets
              .map((UiWidget widget) => widget.copyWith())
              .toList(growable: false),
    );
  }
}

/// Serializes [actions] into a JSON-compatible map.
Map<String, Object?> eventActionsToJson(EventActions actions) {
  return <String, Object?>{
    if (actions.skipSummarization != null)
      'skipSummarization': actions.skipSummarization,
    'stateDelta': Map<String, Object?>.from(actions.stateDelta),
    'artifactDelta': Map<String, int>.from(actions.artifactDelta),
    if (actions.transferToAgent != null)
      'transferToAgent': actions.transferToAgent,
    if (actions.escalate != null) 'escalate': actions.escalate,
    if (actions.requestedAuthConfigs.isNotEmpty)
      'requestedAuthConfigs': Map<String, Object>.from(
        actions.requestedAuthConfigs,
      ),
    if (actions.requestedToolConfirmations.isNotEmpty)
      'requestedToolConfirmations': Map<String, Object>.from(
        actions.requestedToolConfirmations,
      ),
    if (actions.renderUiWidgets.isNotEmpty)
      'renderUiWidgets': actions.renderUiWidgets
          .map((UiWidget widget) => widget.toJson())
          .toList(growable: false),
    if (actions.compaction != null)
      'compaction': <String, Object?>{
        'startTimestamp': actions.compaction!.startTimestamp,
        'endTimestamp': actions.compaction!.endTimestamp,
        'compactedContent': _contentToJson(
          actions.compaction!.compactedContent,
        ),
      },
    if (actions.endOfAgent != null) 'endOfAgent': actions.endOfAgent,
    if (actions.agentState != null)
      'agentState': Map<String, Object?>.from(actions.agentState!),
    if (actions.rewindBeforeInvocationId != null)
      'rewindBeforeInvocationId': actions.rewindBeforeInvocationId,
  };
}

/// Deserializes [json] into [EventActions].
EventActions eventActionsFromJson(Map<String, Object?> json) {
  EventCompaction? compaction;
  final Map<String, Object?>? compactionMap = _castMap(json['compaction']);
  if (compactionMap != null) {
    final Map<String, Object?>? compactedContentMap = _castMap(
      compactionMap['compactedContent'],
    );
    if (compactedContentMap != null) {
      compaction = EventCompaction(
        startTimestamp: _asDouble(compactionMap['startTimestamp']),
        endTimestamp: _asDouble(compactionMap['endTimestamp']),
        compactedContent: _contentFromJson(compactedContentMap),
      );
    }
  }

  return EventActions(
    skipSummarization: json['skipSummarization'] as bool?,
    stateDelta: _castMap(json['stateDelta']) ?? <String, Object?>{},
    artifactDelta: _castIntMap(json['artifactDelta']),
    transferToAgent: json['transferToAgent'] as String?,
    escalate: json['escalate'] as bool?,
    requestedAuthConfigs: _castObjectMap(json['requestedAuthConfigs']),
    requestedToolConfirmations: _castObjectMap(
      json['requestedToolConfirmations'],
    ),
    renderUiWidgets: _castObjectList(
      json['renderUiWidgets'],
    ).map(_uiWidgetFromJson).toList(growable: false),
    compaction: compaction,
    endOfAgent: json['endOfAgent'] as bool?,
    agentState: _castMap(json['agentState']),
    rewindBeforeInvocationId: json['rewindBeforeInvocationId'] as String?,
  );
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
      final Map<String, Object?>? partMap = _castMap(item);
      if (partMap != null) {
        parts.add(_partFromJson(partMap));
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
        'data': List<int>.from(part.inlineData!.data),
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
  final Map<String, Object?>? functionCallMap = _castMap(json['functionCall']);
  if (functionCallMap != null) {
    functionCall = FunctionCall(
      name: '${functionCallMap['name'] ?? ''}',
      args: _castDynamicMap(functionCallMap['args']) ?? <String, dynamic>{},
      id: functionCallMap['id'] as String?,
      partialArgs: _castMapList(
        functionCallMap['partialArgs'] ?? functionCallMap['partial_args'],
      ),
      willContinue: _asNullableBool(
        functionCallMap['willContinue'] ?? functionCallMap['will_continue'],
      ),
    );
  }

  FunctionResponse? functionResponse;
  final Map<String, Object?>? functionResponseMap = _castMap(
    json['functionResponse'],
  );
  if (functionResponseMap != null) {
    functionResponse = FunctionResponse(
      name: '${functionResponseMap['name'] ?? ''}',
      response:
          _castDynamicMap(functionResponseMap['response']) ??
          <String, dynamic>{},
      id: functionResponseMap['id'] as String?,
    );
  }

  InlineData? inlineData;
  final Map<String, Object?>? inlineDataMap = _castMap(json['inlineData']);
  if (inlineDataMap != null) {
    inlineData = InlineData(
      mimeType: '${inlineDataMap['mimeType'] ?? ''}',
      data: _castIntList(inlineDataMap['data']),
      displayName: inlineDataMap['displayName'] as String?,
    );
  }

  FileData? fileData;
  final Map<String, Object?>? fileDataMap = _castMap(json['fileData']);
  if (fileDataMap != null) {
    fileData = FileData(
      fileUri: '${fileDataMap['fileUri'] ?? ''}',
      mimeType: fileDataMap['mimeType'] as String?,
      displayName: fileDataMap['displayName'] as String?,
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

UiWidget _uiWidgetFromJson(Object? value) {
  final Map<String, Object?>? json = _castMap(value);
  if (json == null) {
    return UiWidget(id: '', provider: '');
  }
  return UiWidget.fromJson(json);
}

Map<String, Object?>? _castMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return null;
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
  if (value is! Map) {
    return <String, Object>{};
  }
  final Map<String, Object> result = <String, Object>{};
  value.forEach((Object? key, Object? item) {
    if (item != null) {
      result['$key'] = item;
    }
  });
  return result;
}

Map<String, int> _castIntMap(Object? value) {
  if (value is Map<String, int>) {
    return Map<String, int>.from(value);
  }
  if (value is! Map) {
    return <String, int>{};
  }
  return value.map((Object? key, Object? item) {
    final int parsed = item is int ? item : int.tryParse('$item') ?? 0;
    return MapEntry('$key', parsed);
  });
}

List<Object?> _castObjectList(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.from(value);
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

List<Map<String, Object?>>? _castMapList(Object? value) {
  if (value is! List) {
    return null;
  }
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final Object? item in value) {
    final Map<String, Object?>? map = _castMap(item);
    if (map != null) {
      result.add(map);
    }
  }
  return result;
}

List<int> _castIntList(Object? value) {
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is! List) {
    return const <int>[];
  }
  return value
      .map((Object? item) => item is int ? item : int.parse('$item'))
      .toList();
}

List<int>? _castNullableIntList(Object? value) {
  if (value == null) {
    return null;
  }
  return _castIntList(value);
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.parse('${value ?? 0}');
}

bool? _asNullableBool(Object? value) {
  return value is bool ? value : null;
}

const Object _sentinel = Object();
