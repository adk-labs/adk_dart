/// Event model used by runners, sessions, and streaming APIs.
library;

import '../models/llm_response.dart';
import '../platform/time.dart';
import '../types/content.dart';
import '../types/id.dart';
import 'event_actions.dart';
import 'node_path_builder.dart';

/// One runtime event emitted during an invocation.
class Event extends LlmResponse {
  /// Creates an event.
  Event({
    required this.invocationId,
    required this.author,
    EventActions? actions,
    NodeInfo? nodeInfo,
    Object? output = _sentinel,
    this.longRunningToolIds,
    this.branch,
    this.isolationScope,
    String? id,
    double? timestamp,
    super.modelVersion,
    super.content,
    super.partial,
    super.turnComplete,
    super.finishReason,
    super.errorCode,
    super.errorMessage,
    super.interrupted,
    super.customMetadata,
    super.usageMetadata,
    super.inputTranscription,
    super.outputTranscription,
    super.avgLogprobs,
    super.logprobsResult,
    super.cacheMetadata,
    super.citationMetadata,
    super.groundingMetadata,
    super.interactionId,
    super.liveSessionId,
    super.liveSessionResumptionUpdate,
    super.goAway,
  }) : actions = actions ?? EventActions(),
       nodeInfo = nodeInfo ?? NodeInfo(),
       output = identical(output, _sentinel) ? null : output,
       hasOutput = !identical(output, _sentinel),
       id = id ?? Event.newId(),
       timestamp = timestamp ?? getTime();

  /// Invocation ID that produced this event.
  String invocationId;

  /// Author label, such as `user`, `model`, or agent name.
  String author;

  /// Side-channel actions associated with this event.
  EventActions actions;

  /// Workflow node metadata associated with this event.
  NodeInfo nodeInfo;

  /// Generic workflow node output associated with this event.
  Object? output;

  /// Whether [output] was explicitly provided.
  bool hasOutput;

  /// Long-running tool IDs associated with this event.
  Set<String>? longRunningToolIds;

  /// Optional branch identifier for branching conversations.
  String? branch;

  /// Internal logical scope tag used to isolate task-agent conversation views.
  String? isolationScope;

  /// Event identifier.
  String id;

  /// Event timestamp in seconds since epoch.
  double timestamp;

  /// Whether this event should be treated as a final user-visible response.
  bool isFinalResponse() {
    if (actions.skipSummarization == true ||
        (longRunningToolIds != null && longRunningToolIds!.isNotEmpty)) {
      return true;
    }
    return getFunctionCalls().isEmpty &&
        getFunctionResponses().isEmpty &&
        partial != true &&
        !hasTrailingCodeExecutionResult();
  }

  /// Returns function-call parts embedded in [content].
  @override
  List<FunctionCall> getFunctionCalls() {
    final Content? value = content;
    if (value == null) {
      return const <FunctionCall>[];
    }

    final List<FunctionCall> calls = <FunctionCall>[];
    for (final Part part in value.parts) {
      if (part.functionCall != null) {
        calls.add(part.functionCall!);
      }
    }
    return calls;
  }

  /// Returns function-response parts embedded in [content].
  @override
  List<FunctionResponse> getFunctionResponses() {
    final Content? value = content;
    if (value == null) {
      return const <FunctionResponse>[];
    }

    final List<FunctionResponse> responses = <FunctionResponse>[];
    for (final Part part in value.parts) {
      if (part.functionResponse != null) {
        responses.add(part.functionResponse!);
      }
    }
    return responses;
  }

  /// Whether the last content part is a code-execution result.
  bool hasTrailingCodeExecutionResult() {
    final Content? value = content;
    if (value == null || value.parts.isEmpty) {
      return false;
    }
    return value.parts.last.codeExecutionResult != null;
  }

  @override
  Event copyWith({
    Object? invocationId = _sentinel,
    Object? author = _sentinel,
    EventActions? actions,
    NodeInfo? nodeInfo,
    Object? output = _sentinel,
    Object? longRunningToolIds = _sentinel,
    Object? branch = _sentinel,
    Object? isolationScope = _sentinel,
    Object? id = _sentinel,
    Object? timestamp = _sentinel,
    Object? modelVersion = _sentinel,
    Object? content = _sentinel,
    Object? partial = _sentinel,
    Object? turnComplete = _sentinel,
    Object? finishReason = _sentinel,
    Object? errorCode = _sentinel,
    Object? errorMessage = _sentinel,
    Object? interrupted = _sentinel,
    Object? customMetadata = _sentinel,
    Object? usageMetadata = _sentinel,
    Object? inputTranscription = _sentinel,
    Object? outputTranscription = _sentinel,
    Object? avgLogprobs = _sentinel,
    Object? logprobsResult = _sentinel,
    Object? cacheMetadata = _sentinel,
    Object? citationMetadata = _sentinel,
    Object? groundingMetadata = _sentinel,
    Object? interactionId = _sentinel,
    Object? liveSessionId = _sentinel,
    Object? liveSessionResumptionUpdate = _sentinel,
    Object? goAway = _sentinel,
  }) {
    final bool nextHasOutput = identical(output, _sentinel) ? hasOutput : true;
    return Event(
      invocationId: identical(invocationId, _sentinel)
          ? this.invocationId
          : invocationId as String,
      author: identical(author, _sentinel) ? this.author : author as String,
      actions: actions ?? this.actions.copyWith(),
      nodeInfo: nodeInfo ?? this.nodeInfo.copyWith(),
      output: nextHasOutput
          ? (identical(output, _sentinel) ? this.output : output)
          : _sentinel,
      longRunningToolIds: identical(longRunningToolIds, _sentinel)
          ? longRunningToolIds == null
                ? null
                : this.longRunningToolIds == null
                ? null
                : Set<String>.from(this.longRunningToolIds!)
          : longRunningToolIds as Set<String>?,
      branch: identical(branch, _sentinel) ? this.branch : branch as String?,
      isolationScope: identical(isolationScope, _sentinel)
          ? this.isolationScope
          : isolationScope as String?,
      id: identical(id, _sentinel) ? this.id : id as String,
      timestamp: identical(timestamp, _sentinel)
          ? this.timestamp
          : timestamp as double,
      modelVersion: identical(modelVersion, _sentinel)
          ? this.modelVersion
          : modelVersion as String?,
      content: identical(content, _sentinel)
          ? this.content?.copyWith()
          : content as Content?,
      partial: identical(partial, _sentinel) ? this.partial : partial as bool?,
      turnComplete: identical(turnComplete, _sentinel)
          ? this.turnComplete
          : turnComplete as bool?,
      finishReason: identical(finishReason, _sentinel)
          ? this.finishReason
          : finishReason as String?,
      errorCode: identical(errorCode, _sentinel)
          ? this.errorCode
          : errorCode as String?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      interrupted: identical(interrupted, _sentinel)
          ? this.interrupted
          : interrupted as bool?,
      customMetadata: identical(customMetadata, _sentinel)
          ? this.customMetadata == null
                ? null
                : Map<String, dynamic>.from(this.customMetadata!)
          : customMetadata as Map<String, dynamic>?,
      usageMetadata: identical(usageMetadata, _sentinel)
          ? this.usageMetadata
          : usageMetadata,
      inputTranscription: identical(inputTranscription, _sentinel)
          ? this.inputTranscription
          : inputTranscription,
      outputTranscription: identical(outputTranscription, _sentinel)
          ? this.outputTranscription
          : outputTranscription,
      avgLogprobs: identical(avgLogprobs, _sentinel)
          ? this.avgLogprobs
          : avgLogprobs as double?,
      logprobsResult: identical(logprobsResult, _sentinel)
          ? this.logprobsResult
          : logprobsResult,
      cacheMetadata: identical(cacheMetadata, _sentinel)
          ? this.cacheMetadata
          : cacheMetadata,
      citationMetadata: identical(citationMetadata, _sentinel)
          ? this.citationMetadata
          : citationMetadata,
      groundingMetadata: identical(groundingMetadata, _sentinel)
          ? this.groundingMetadata
          : groundingMetadata,
      interactionId: identical(interactionId, _sentinel)
          ? this.interactionId
          : interactionId as String?,
      liveSessionId: identical(liveSessionId, _sentinel)
          ? this.liveSessionId
          : liveSessionId as String?,
      liveSessionResumptionUpdate:
          identical(liveSessionResumptionUpdate, _sentinel)
          ? this.liveSessionResumptionUpdate
          : liveSessionResumptionUpdate,
      goAway: identical(goAway, _sentinel) ? this.goAway : goAway,
    );
  }

  /// Creates a new runtime event identifier.
  static String newId() => newAdkId(prefix: 'evt_');
}

/// Workflow node metadata attached to an [Event].
class NodeInfo {
  /// Creates workflow node metadata.
  NodeInfo({this.path = '', List<String>? outputFor, this.messageAsOutput})
    : outputFor = outputFor == null ? null : List<String>.from(outputFor);

  /// The path of the workflow node that generated the event.
  String path;

  /// Node paths whose output this event represents.
  List<String>? outputFor;

  /// Whether this event's [Event.content] should be treated as node output.
  bool? messageAsOutput;

  /// Whether this metadata contains no meaningful fields.
  bool get isEmpty =>
      path.isEmpty &&
      (outputFor == null || outputFor!.isEmpty) &&
      messageAsOutput == null;

  /// The run ID parsed from the final path segment.
  String get runId => NodePathBuilder.fromString(path).runId ?? '';

  /// The run ID parsed from the parent path segment, if present.
  String? get parentRunId {
    return NodePathBuilder.fromString(path).parent?.runId;
  }

  /// The node name parsed from the final path segment.
  String get name => NodePathBuilder.fromString(path).nodeName;

  /// Returns copied node metadata with optional overrides.
  NodeInfo copyWith({
    String? path,
    List<String>? outputFor,
    Object? messageAsOutput = _sentinel,
  }) {
    return NodeInfo(
      path: path ?? this.path,
      outputFor: outputFor ?? this.outputFor,
      messageAsOutput: identical(messageAsOutput, _sentinel)
          ? this.messageAsOutput
          : messageAsOutput as bool?,
    );
  }
}

/// Serializes [nodeInfo] into a JSON-compatible map.
Map<String, Object?> eventNodeInfoToJson(
  NodeInfo nodeInfo, {
  bool snakeCase = false,
}) {
  final Map<String, Object?> json = <String, Object?>{};
  if (nodeInfo.path.isNotEmpty) {
    json['path'] = nodeInfo.path;
  }
  if (nodeInfo.outputFor != null) {
    json[snakeCase ? 'output_for' : 'outputFor'] = List<String>.from(
      nodeInfo.outputFor!,
    );
  }
  if (nodeInfo.messageAsOutput != null) {
    json[snakeCase ? 'message_as_output' : 'messageAsOutput'] =
        nodeInfo.messageAsOutput;
  }
  return json;
}

/// Deserializes [json] into workflow [NodeInfo].
NodeInfo eventNodeInfoFromJson(Map<String, Object?> json) {
  return NodeInfo(
    path: '${json['path'] ?? ''}',
    outputFor: _stringListFromObject(json['outputFor'] ?? json['output_for']),
    messageAsOutput:
        (json['messageAsOutput'] ?? json['message_as_output']) as bool?,
  );
}

List<String>? _stringListFromObject(Object? value) {
  if (value is! List) {
    return null;
  }
  return value.map((Object? item) => '$item').toList(growable: false);
}

const Object _sentinel = Object();
