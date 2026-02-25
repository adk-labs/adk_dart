import '../models/llm_response.dart';
import '../types/content.dart';
import '../types/id.dart';
import 'event_actions.dart';

class Event extends LlmResponse {
  Event({
    required this.invocationId,
    required this.author,
    EventActions? actions,
    this.longRunningToolIds,
    this.branch,
    String? id,
    double? timestamp,
    String? modelVersion,
    Content? content,
    bool? partial,
    bool? turnComplete,
    String? finishReason,
    String? errorCode,
    String? errorMessage,
    bool? interrupted,
    Map<String, dynamic>? customMetadata,
    Object? usageMetadata,
    Object? inputTranscription,
    Object? outputTranscription,
    double? avgLogprobs,
    Object? logprobsResult,
    Object? cacheMetadata,
    Object? citationMetadata,
    Object? groundingMetadata,
    String? interactionId,
  }) : actions = actions ?? EventActions(),
       id = id ?? Event.newId(),
       timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch / 1000,
       super(
         modelVersion: modelVersion,
         content: content,
         partial: partial,
         turnComplete: turnComplete,
         finishReason: finishReason,
         errorCode: errorCode,
         errorMessage: errorMessage,
         interrupted: interrupted,
         customMetadata: customMetadata,
         usageMetadata: usageMetadata,
         inputTranscription: inputTranscription,
         outputTranscription: outputTranscription,
         avgLogprobs: avgLogprobs,
         logprobsResult: logprobsResult,
         cacheMetadata: cacheMetadata,
         citationMetadata: citationMetadata,
         groundingMetadata: groundingMetadata,
         interactionId: interactionId,
       );

  String invocationId;
  String author;
  EventActions actions;
  Set<String>? longRunningToolIds;
  String? branch;
  String id;
  double timestamp;

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
    Object? longRunningToolIds = _sentinel,
    Object? branch = _sentinel,
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
  }) {
    return Event(
      invocationId: identical(invocationId, _sentinel)
          ? this.invocationId
          : invocationId as String,
      author: identical(author, _sentinel) ? this.author : author as String,
      actions: actions ?? this.actions.copyWith(),
      longRunningToolIds: identical(longRunningToolIds, _sentinel)
          ? longRunningToolIds == null
                ? null
                : this.longRunningToolIds == null
                ? null
                : Set<String>.from(this.longRunningToolIds!)
          : longRunningToolIds as Set<String>?,
      branch: identical(branch, _sentinel) ? this.branch : branch as String?,
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
    );
  }

  static String newId() => newAdkId(prefix: 'evt_');
}

const Object _sentinel = Object();
