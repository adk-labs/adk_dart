/// Conformance recording schema and serialization helpers.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../types/content.dart';

typedef ConformanceJson = Map<String, Object?>;

/// One recorded LLM request with all streamed responses.
class ConformanceLlmRecording {
  /// Creates an LLM recording.
  ConformanceLlmRecording({
    required this.llmRequest,
    List<ConformanceJson>? llmResponses,
  }) : llmResponses = llmResponses ?? <ConformanceJson>[];

  /// Canonical serialized request payload.
  final ConformanceJson llmRequest;

  /// Ordered streamed responses for the request.
  final List<ConformanceJson> llmResponses;

  /// Converts to a JSON-like map.
  ConformanceJson toJson() {
    return <String, Object?>{
      'llm_request': llmRequest,
      'llm_responses': llmResponses,
    };
  }

  /// Decodes a recording from JSON-like input.
  factory ConformanceLlmRecording.fromJson(ConformanceJson json) {
    return ConformanceLlmRecording(
      llmRequest: asConformanceObjectMap(json['llm_request']),
      llmResponses: asConformanceObjectList(
        json['llm_responses'],
      ).map(asConformanceObjectMap).toList(growable: false),
    );
  }
}

/// One recorded tool request/response pair.
class ConformanceToolRecording {
  /// Creates a tool recording.
  ConformanceToolRecording({required this.toolCall, this.toolResponse});

  /// Serialized function call payload.
  final ConformanceJson toolCall;

  /// Serialized function response payload.
  ConformanceJson? toolResponse;

  /// Converts to a JSON-like map.
  ConformanceJson toJson() {
    return <String, Object?>{
      'tool_call': toolCall,
      if (toolResponse != null) 'tool_response': toolResponse,
    };
  }

  /// Decodes a recording from JSON-like input.
  factory ConformanceToolRecording.fromJson(ConformanceJson json) {
    final Object? rawResponse = json['tool_response'];
    return ConformanceToolRecording(
      toolCall: asConformanceObjectMap(json['tool_call']),
      toolResponse: rawResponse is Map
          ? asConformanceObjectMap(rawResponse)
          : null,
    );
  }
}

/// One chronological conformance interaction.
class ConformanceRecording {
  /// Creates one interaction recording.
  ConformanceRecording({
    required this.userMessageIndex,
    required this.agentName,
    this.llmRecording,
    this.toolRecording,
  });

  /// Turn index this interaction belongs to.
  final int userMessageIndex;

  /// Agent that emitted the interaction.
  final String agentName;

  /// Optional LLM request/response pair.
  ConformanceLlmRecording? llmRecording;

  /// Optional tool request/response pair.
  ConformanceToolRecording? toolRecording;

  /// Converts to a JSON-like map.
  ConformanceJson toJson() {
    return <String, Object?>{
      'user_message_index': userMessageIndex,
      'agent_name': agentName,
      if (llmRecording != null) 'llm_recording': llmRecording!.toJson(),
      if (toolRecording != null) 'tool_recording': toolRecording!.toJson(),
    };
  }

  /// Decodes a recording from JSON-like input.
  factory ConformanceRecording.fromJson(ConformanceJson json) {
    final Object? rawLlm = json['llm_recording'];
    final Object? rawTool = json['tool_recording'];
    return ConformanceRecording(
      userMessageIndex: asConformanceInt(json['user_message_index']),
      agentName: '${json['agent_name'] ?? ''}',
      llmRecording: rawLlm is Map
          ? ConformanceLlmRecording.fromJson(asConformanceObjectMap(rawLlm))
          : null,
      toolRecording: rawTool is Map
          ? ConformanceToolRecording.fromJson(asConformanceObjectMap(rawTool))
          : null,
    );
  }
}

/// Full interaction list used by conformance record/replay.
class ConformanceRecordings {
  /// Creates a recordings bundle.
  ConformanceRecordings({List<ConformanceRecording>? recordings})
    : recordings = recordings ?? <ConformanceRecording>[];

  /// Chronological interaction list.
  final List<ConformanceRecording> recordings;

  /// Converts to a JSON-like map.
  ConformanceJson toJson() {
    return <String, Object?>{
      'recordings': recordings.map((item) => item.toJson()).toList(),
    };
  }

  /// Decodes recordings from JSON-like input.
  factory ConformanceRecordings.fromJson(ConformanceJson json) {
    return ConformanceRecordings(
      recordings: asConformanceObjectList(json['recordings'])
          .map(
            (item) =>
                ConformanceRecording.fromJson(asConformanceObjectMap(item)),
          )
          .toList(growable: false),
    );
  }
}

/// Serializes [request] to a stable JSON-like structure for replay checks.
ConformanceJson serializeLlmRequest(LlmRequest request) {
  return <String, Object?>{
    if (request.model != null) 'model': request.model,
    'contents': request.contents
        .map((Content content) => serializeContent(content))
        .toList(growable: false),
    'config': _serializeGenerateContentConfig(request.config),
    'live_connect_config': _serializeLiveConnectConfig(
      request.liveConnectConfig,
    ),
    if (request.cacheConfig != null)
      'cache_config': normalizeConformanceJsonValue(request.cacheConfig),
    if (request.cacheMetadata != null)
      'cache_metadata': normalizeConformanceJsonValue(request.cacheMetadata),
    if (request.cacheableContentsTokenCount != null)
      'cacheable_contents_token_count': request.cacheableContentsTokenCount,
    if (request.previousInteractionId != null)
      'previous_interaction_id': request.previousInteractionId,
  };
}

/// Serializes [response] to a stable JSON-like structure for persistence.
ConformanceJson serializeLlmResponse(LlmResponse response) {
  return <String, Object?>{
    if (response.modelVersion != null) 'model_version': response.modelVersion,
    if (response.content != null)
      'content': serializeContent(response.content!),
    if (response.partial != null) 'partial': response.partial,
    if (response.turnComplete != null) 'turn_complete': response.turnComplete,
    if (response.finishReason != null) 'finish_reason': response.finishReason,
    if (response.errorCode != null) 'error_code': response.errorCode,
    if (response.errorMessage != null) 'error_message': response.errorMessage,
    if (response.interrupted != null) 'interrupted': response.interrupted,
    if (response.customMetadata != null)
      'custom_metadata': normalizeConformanceJsonValue(response.customMetadata),
    if (response.usageMetadata != null)
      'usage_metadata': normalizeConformanceJsonValue(response.usageMetadata),
    if (response.inputTranscription != null)
      'input_transcription': normalizeConformanceJsonValue(
        response.inputTranscription,
      ),
    if (response.outputTranscription != null)
      'output_transcription': normalizeConformanceJsonValue(
        response.outputTranscription,
      ),
    if (response.avgLogprobs != null) 'avg_logprobs': response.avgLogprobs,
    if (response.logprobsResult != null)
      'logprobs_result': normalizeConformanceJsonValue(response.logprobsResult),
    if (response.cacheMetadata != null)
      'cache_metadata': normalizeConformanceJsonValue(response.cacheMetadata),
    if (response.citationMetadata != null)
      'citation_metadata': normalizeConformanceJsonValue(
        response.citationMetadata,
      ),
    if (response.groundingMetadata != null)
      'grounding_metadata': normalizeConformanceJsonValue(
        response.groundingMetadata,
      ),
    if (response.interactionId != null)
      'interaction_id': response.interactionId,
  };
}

/// Deserializes an [LlmResponse] previously produced by [serializeLlmResponse].
LlmResponse deserializeLlmResponse(ConformanceJson json) {
  return LlmResponse(
    modelVersion: json['model_version'] as String?,
    content: json['content'] is Map
        ? deserializeContent(asConformanceObjectMap(json['content']))
        : null,
    partial: json['partial'] as bool?,
    turnComplete: json['turn_complete'] as bool?,
    finishReason: json['finish_reason'] as String?,
    errorCode: json['error_code'] as String?,
    errorMessage: json['error_message'] as String?,
    interrupted: json['interrupted'] as bool?,
    customMetadata: asConformanceDynamicMap(json['custom_metadata']),
    usageMetadata: json['usage_metadata'],
    inputTranscription: json['input_transcription'],
    outputTranscription: json['output_transcription'],
    avgLogprobs: asConformanceNullableDouble(json['avg_logprobs']),
    logprobsResult: json['logprobs_result'],
    cacheMetadata: json['cache_metadata'],
    citationMetadata: json['citation_metadata'],
    groundingMetadata: json['grounding_metadata'],
    interactionId: json['interaction_id'] as String?,
  );
}

/// Serializes [content] into a JSON-like map.
ConformanceJson serializeContent(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map((Part part) => _serializePart(part)).toList(),
  };
}

/// Deserializes [content] produced by [serializeContent].
Content deserializeContent(ConformanceJson json) {
  return Content(
    role: json['role'] as String?,
    parts: asConformanceObjectList(json['parts'])
        .map((item) => _deserializePart(asConformanceObjectMap(item)))
        .toList(growable: false),
  );
}

/// Creates a tool-call map used by recordings.
ConformanceJson serializeToolCall({
  required String id,
  required String name,
  required Map<String, dynamic> args,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'args': normalizeConformanceJsonValue(args),
  };
}

/// Creates a tool-response map used by recordings.
ConformanceJson serializeToolResponse({
  required String id,
  required String name,
  required Map<String, dynamic> response,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'response': normalizeConformanceJsonValue(response),
  };
}

/// Canonicalizes a serialized request for stable replay comparison.
ConformanceJson canonicalizeSerializedLlmRequest(ConformanceJson json) {
  final ConformanceJson copy = asConformanceObjectMap(
    normalizeConformanceJsonValue(json),
  );
  copy.remove('live_connect_config');
  copy['contents'] = asConformanceObjectList(copy['contents'])
      .map((Object? item) {
        return _canonicalizeSerializedContent(asConformanceObjectMap(item));
      })
      .toList(growable: false);
  final ConformanceJson config = asConformanceObjectMap(copy['config']);
  config.remove('http_options');
  config.remove('labels');
  copy['config'] = config;
  return copy;
}

/// Stable JSON signature for deep equality checks.
String stableJsonSignature(Object? value) {
  return jsonEncode(_sortJsonValue(normalizeConformanceJsonValue(value)));
}

ConformanceJson _canonicalizeSerializedContent(ConformanceJson json) {
  final ConformanceJson copy = asConformanceObjectMap(json);
  copy['parts'] = asConformanceObjectList(copy['parts'])
      .map((Object? item) {
        return _canonicalizeSerializedPart(asConformanceObjectMap(item));
      })
      .toList(growable: false);
  return copy;
}

ConformanceJson _canonicalizeSerializedPart(ConformanceJson json) {
  final ConformanceJson copy = asConformanceObjectMap(json);
  final Object? rawCall = copy['function_call'];
  if (rawCall is Map) {
    final ConformanceJson functionCall = asConformanceObjectMap(rawCall);
    final List<ConformanceJson> partialArgs =
        asConformanceObjectList(functionCall['partial_args'])
            .map((Object? item) => asConformanceObjectMap(item))
            .toList(growable: false);
    if (partialArgs.isEmpty) {
      functionCall.remove('partial_args');
    } else {
      functionCall['partial_args'] = partialArgs;
    }
    copy['function_call'] = functionCall;
  }
  return copy;
}

ConformanceJson _serializeGenerateContentConfig(GenerateContentConfig config) {
  return <String, Object?>{
    if (config.tools != null)
      'tools': config.tools!
          .map((ToolDeclaration tool) => _serializeToolDeclaration(tool))
          .toList(growable: false),
    if (config.systemInstruction != null)
      'system_instruction': config.systemInstruction,
    if (config.temperature != null) 'temperature': config.temperature,
    if (config.topP != null) 'top_p': config.topP,
    if (config.topK != null) 'top_k': config.topK,
    if (config.maxOutputTokens != null)
      'max_output_tokens': config.maxOutputTokens,
    if (config.stopSequences.isNotEmpty)
      'stop_sequences': List<String>.from(config.stopSequences),
    if (config.frequencyPenalty != null)
      'frequency_penalty': config.frequencyPenalty,
    if (config.presencePenalty != null)
      'presence_penalty': config.presencePenalty,
    if (config.seed != null) 'seed': config.seed,
    if (config.candidateCount != null) 'candidate_count': config.candidateCount,
    if (config.responseLogprobs != null)
      'response_logprobs': config.responseLogprobs,
    if (config.logprobs != null) 'logprobs': config.logprobs,
    if (config.thinkingConfig != null)
      'thinking_config': normalizeConformanceJsonValue(config.thinkingConfig),
    if (config.responseSchema != null)
      'response_schema': normalizeConformanceJsonValue(config.responseSchema),
    if (config.responseJsonSchema != null)
      'response_json_schema': normalizeConformanceJsonValue(
        config.responseJsonSchema,
      ),
    if (config.responseMimeType != null)
      'response_mime_type': config.responseMimeType,
    if (config.toolConfig != null)
      'tool_config': _serializeToolConfig(config.toolConfig!),
    if (config.cachedContent != null) 'cached_content': config.cachedContent,
    if (config.httpOptions != null)
      'http_options': _serializeHttpOptions(config.httpOptions!),
    if (config.labels.isNotEmpty)
      'labels': Map<String, String>.from(config.labels),
  };
}

ConformanceJson _serializeLiveConnectConfig(LiveConnectConfig config) {
  return <String, Object?>{
    if (config.responseModalities != null)
      'response_modalities': List<String>.from(config.responseModalities!),
    if (config.speechConfig != null)
      'speech_config': normalizeConformanceJsonValue(config.speechConfig),
    if (config.outputAudioTranscription != null)
      'output_audio_transcription': normalizeConformanceJsonValue(
        config.outputAudioTranscription,
      ),
    if (config.inputAudioTranscription != null)
      'input_audio_transcription': normalizeConformanceJsonValue(
        config.inputAudioTranscription,
      ),
    if (config.systemInstruction != null)
      'system_instruction': normalizeConformanceJsonValue(
        config.systemInstruction,
      ),
    if (config.tools != null)
      'tools': config.tools!
          .map((ToolDeclaration tool) => _serializeToolDeclaration(tool))
          .toList(growable: false),
    if (config.httpOptions != null)
      'http_options': _serializeHttpOptions(config.httpOptions!),
    if (config.realtimeInputConfig != null)
      'realtime_input_config': normalizeConformanceJsonValue(
        config.realtimeInputConfig,
      ),
    if (config.enableAffectiveDialog != null)
      'enable_affective_dialog': config.enableAffectiveDialog,
    if (config.proactivity != null)
      'proactivity': normalizeConformanceJsonValue(config.proactivity),
    if (config.sessionResumption != null)
      'session_resumption': normalizeConformanceJsonValue(
        config.sessionResumption,
      ),
    if (config.contextWindowCompression != null)
      'context_window_compression': normalizeConformanceJsonValue(
        config.contextWindowCompression,
      ),
  };
}

ConformanceJson _serializeToolDeclaration(ToolDeclaration tool) {
  return <String, Object?>{
    if (tool.functionDeclarations.isNotEmpty)
      'function_declarations': tool.functionDeclarations
          .map((FunctionDeclaration declaration) {
            return <String, Object?>{
              'name': declaration.name,
              'description': declaration.description,
              'parameters': normalizeConformanceJsonValue(
                declaration.parameters,
              ),
            };
          })
          .toList(growable: false),
    if (tool.googleSearch != null)
      'google_search': normalizeConformanceJsonValue(tool.googleSearch),
    if (tool.googleSearchRetrieval != null)
      'google_search_retrieval': normalizeConformanceJsonValue(
        tool.googleSearchRetrieval,
      ),
    if (tool.urlContext != null)
      'url_context': normalizeConformanceJsonValue(tool.urlContext),
    if (tool.codeExecution != null)
      'code_execution': normalizeConformanceJsonValue(tool.codeExecution),
    if (tool.googleMaps != null)
      'google_maps': normalizeConformanceJsonValue(tool.googleMaps),
    if (tool.enterpriseWebSearch != null)
      'enterprise_web_search': normalizeConformanceJsonValue(
        tool.enterpriseWebSearch,
      ),
    if (tool.retrieval != null)
      'retrieval': normalizeConformanceJsonValue(tool.retrieval),
    if (tool.computerUse != null)
      'computer_use': normalizeConformanceJsonValue(tool.computerUse),
  };
}

ConformanceJson _serializeToolConfig(LlmToolConfig config) {
  return <String, Object?>{
    if (config.functionCallingConfig != null)
      'function_calling_config': <String, Object?>{
        'mode': config.functionCallingConfig!.mode.name,
        if (config.functionCallingConfig!.allowedFunctionNames.isNotEmpty)
          'allowed_function_names': List<String>.from(
            config.functionCallingConfig!.allowedFunctionNames,
          ),
      },
  };
}

ConformanceJson _serializeHttpOptions(HttpOptions options) {
  return <String, Object?>{
    if (options.retryOptions != null)
      'retry_options': <String, Object?>{
        if (options.retryOptions!.attempts != null)
          'attempts': options.retryOptions!.attempts,
        if (options.retryOptions!.initialDelay != null)
          'initial_delay': options.retryOptions!.initialDelay,
        if (options.retryOptions!.maxDelay != null)
          'max_delay': options.retryOptions!.maxDelay,
        if (options.retryOptions!.expBase != null)
          'exp_base': options.retryOptions!.expBase,
        if (options.retryOptions!.httpStatusCodes.isNotEmpty)
          'http_status_codes': List<int>.from(
            options.retryOptions!.httpStatusCodes,
          ),
      },
    if (options.headers.isNotEmpty)
      'headers': Map<String, String>.from(options.headers),
    if (options.apiVersion != null) 'api_version': options.apiVersion,
  };
}

ConformanceJson _serializePart(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    'thought': part.thought,
    if (part.thoughtSignature != null)
      'thought_signature': List<int>.from(part.thoughtSignature!),
    if (part.functionCall != null)
      'function_call': <String, Object?>{
        'name': part.functionCall!.name,
        'args': normalizeConformanceJsonValue(part.functionCall!.args),
        if (part.functionCall!.id != null) 'id': part.functionCall!.id,
        if (part.functionCall!.partialArgs != null)
          'partial_args': normalizeConformanceJsonValue(
            part.functionCall!.partialArgs,
          ),
        if (part.functionCall!.willContinue != null)
          'will_continue': part.functionCall!.willContinue,
      },
    if (part.functionResponse != null)
      'function_response': <String, Object?>{
        'name': part.functionResponse!.name,
        'response': normalizeConformanceJsonValue(
          part.functionResponse!.response,
        ),
        if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
      },
    if (part.inlineData != null)
      'inline_data': <String, Object?>{
        'mime_type': part.inlineData!.mimeType,
        'data': base64Encode(part.inlineData!.data),
        if (part.inlineData!.displayName != null)
          'display_name': part.inlineData!.displayName,
      },
    if (part.fileData != null)
      'file_data': <String, Object?>{
        'file_uri': part.fileData!.fileUri,
        if (part.fileData!.mimeType != null)
          'mime_type': part.fileData!.mimeType,
        if (part.fileData!.displayName != null)
          'display_name': part.fileData!.displayName,
      },
    if (part.executableCode != null)
      'executable_code': normalizeConformanceJsonValue(part.executableCode),
    if (part.codeExecutionResult != null)
      'code_execution_result': normalizeConformanceJsonValue(
        part.codeExecutionResult,
      ),
  };
}

Part _deserializePart(ConformanceJson json) {
  FunctionCall? functionCall;
  final Object? rawFunctionCall = json['function_call'];
  if (rawFunctionCall is Map) {
    final ConformanceJson call = asConformanceObjectMap(rawFunctionCall);
    functionCall = FunctionCall(
      name: '${call['name'] ?? ''}',
      args: asConformanceDynamicMap(call['args']) ?? <String, dynamic>{},
      id: call['id'] as String?,
      partialArgs: asConformanceObjectList(
        call['partial_args'],
      ).map((item) => asConformanceObjectMap(item)).toList(growable: false),
      willContinue: call['will_continue'] as bool?,
    );
  }

  FunctionResponse? functionResponse;
  final Object? rawFunctionResponse = json['function_response'];
  if (rawFunctionResponse is Map) {
    final ConformanceJson response = asConformanceObjectMap(
      rawFunctionResponse,
    );
    functionResponse = FunctionResponse(
      name: '${response['name'] ?? ''}',
      response:
          asConformanceDynamicMap(response['response']) ?? <String, dynamic>{},
      id: response['id'] as String?,
    );
  }

  InlineData? inlineData;
  final Object? rawInlineData = json['inline_data'];
  if (rawInlineData is Map) {
    final ConformanceJson inline = asConformanceObjectMap(rawInlineData);
    final Object? rawData = inline['data'];
    inlineData = InlineData(
      mimeType: '${inline['mime_type'] ?? ''}',
      data: rawData is String ? base64Decode(rawData) : <int>[],
      displayName: inline['display_name'] as String?,
    );
  }

  FileData? fileData;
  final Object? rawFileData = json['file_data'];
  if (rawFileData is Map) {
    final ConformanceJson file = asConformanceObjectMap(rawFileData);
    fileData = FileData(
      fileUri: '${file['file_uri'] ?? ''}',
      mimeType: file['mime_type'] as String?,
      displayName: file['display_name'] as String?,
    );
  }

  return Part(
    text: json['text'] as String?,
    thought: (json['thought'] as bool?) ?? false,
    thoughtSignature: asConformanceIntList(json['thought_signature']),
    functionCall: functionCall,
    functionResponse: functionResponse,
    inlineData: inlineData,
    fileData: fileData,
    executableCode: json['executable_code'],
    codeExecutionResult: json['code_execution_result'],
  );
}

Object? normalizeConformanceJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Uint8List) {
    return value.toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry('$key', normalizeConformanceJsonValue(item)),
    );
  }
  if (value is List) {
    return value.map(normalizeConformanceJsonValue).toList(growable: false);
  }
  final dynamic dynamicValue = value;
  try {
    final Object? json = dynamicValue.toJson();
    return normalizeConformanceJsonValue(json);
  } on NoSuchMethodError {
    return '$value';
  }
}

Object? _sortJsonValue(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList()
      ..sort();
    final ConformanceJson sorted = <String, Object?>{};
    for (final String key in keys) {
      sorted[key] = _sortJsonValue(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_sortJsonValue).toList(growable: false);
  }
  return value;
}

ConformanceJson asConformanceObjectMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

List<Object?> asConformanceObjectList(Object? value) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

Map<String, dynamic>? asConformanceDynamicMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return null;
}

List<int>? asConformanceIntList(Object? value) {
  if (value is! List) {
    return null;
  }
  final List<int> ints = <int>[];
  for (final Object? item in value) {
    if (item is num) {
      ints.add(item.toInt());
    }
  }
  return ints;
}

int asConformanceInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value') ?? 0;
}

double? asConformanceNullableDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}
