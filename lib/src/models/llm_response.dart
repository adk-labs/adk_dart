import '../types/content.dart';

class LlmResponse {
  LlmResponse({
    this.modelVersion,
    this.content,
    this.partial,
    this.turnComplete,
    this.finishReason,
    this.errorCode,
    this.errorMessage,
    this.interrupted,
    this.customMetadata,
    this.usageMetadata,
    this.inputTranscription,
    this.outputTranscription,
    this.avgLogprobs,
    this.logprobsResult,
    this.cacheMetadata,
    this.citationMetadata,
    this.interactionId,
  });

  String? modelVersion;
  Content? content;
  bool? partial;
  bool? turnComplete;
  String? finishReason;
  String? errorCode;
  String? errorMessage;
  bool? interrupted;
  Map<String, dynamic>? customMetadata;
  Object? usageMetadata;
  Object? inputTranscription;
  Object? outputTranscription;
  double? avgLogprobs;
  Object? logprobsResult;
  Object? cacheMetadata;
  Object? citationMetadata;
  String? interactionId;

  LlmResponse copyWith({
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
    Object? interactionId = _sentinel,
  }) {
    return LlmResponse(
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
      interactionId: identical(interactionId, _sentinel)
          ? this.interactionId
          : interactionId as String?,
    );
  }
}

const Object _sentinel = Object();
