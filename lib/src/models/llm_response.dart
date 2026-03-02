import '../types/content.dart';

/// Normalized model response emitted by LLM adapters.
class LlmResponse {
  /// Creates an LLM response.
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
    this.groundingMetadata,
    this.interactionId,
  });

  /// Backend model version that produced this response.
  String? modelVersion;

  /// Generated content payload.
  Content? content;

  /// Whether this event is a partial streaming chunk.
  bool? partial;

  /// Whether the model turn has completed.
  bool? turnComplete;

  /// Backend-specific finish reason string.
  String? finishReason;

  /// Backend-specific error code.
  String? errorCode;

  /// Human-readable error message.
  String? errorMessage;

  /// Whether generation was interrupted externally.
  bool? interrupted;

  /// Optional custom metadata attached by middleware.
  Map<String, dynamic>? customMetadata;

  /// Provider usage metadata payload.
  Object? usageMetadata;

  /// Provider input transcription payload.
  Object? inputTranscription;

  /// Provider output transcription payload.
  Object? outputTranscription;

  /// Average log probability for generated tokens.
  double? avgLogprobs;

  /// Provider log-probability detail payload.
  Object? logprobsResult;

  /// Provider cache metadata payload.
  Object? cacheMetadata;

  /// Provider citation metadata payload.
  Object? citationMetadata;

  /// Provider grounding metadata payload.
  Object? groundingMetadata;

  /// Provider interaction identifier for tracing.
  String? interactionId;

  /// Returns a copy of this response with optional overrides.
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
    Object? groundingMetadata = _sentinel,
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
      groundingMetadata: identical(groundingMetadata, _sentinel)
          ? this.groundingMetadata
          : groundingMetadata,
      interactionId: identical(interactionId, _sentinel)
          ? this.interactionId
          : interactionId as String?,
    );
  }
}

const Object _sentinel = Object();
