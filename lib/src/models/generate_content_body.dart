/// Converts an [LlmRequest] into a Gemini / Vertex AI `generateContent` JSON
/// request body.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../types/content.dart';
import '../utils/variant_utils.dart';
import 'llm_request.dart';

final RegExp _configFieldErrorPattern = RegExp(
  r'^(\w+) parameter is not supported in (?:Vertex AI|Gemini API)\.?$',
);

final RegExp _vertexCachedContentFullPattern = RegExp(
  r'^projects/[^/]+/locations/[^/]+/cachedContents/[^/]+$',
);

/// Annotates a backend-compatibility [exc] with its [LlmRequest.config]
/// field path and target [vertexai] backend.
ArgumentError annotateValueError(ArgumentError exc, {required bool vertexai}) {
  final String message = '${exc.message ?? exc}';
  final String target = vertexai ? 'Vertex AI' : 'the Gemini Developer API';
  final RegExpMatch? match = _configFieldErrorPattern.firstMatch(message);
  if (match != null) {
    final String field = match.group(1)!;
    return ArgumentError(
      '$message (set as LlmRequest.config.$field; '
      'this request targets $target.)',
    );
  }
  if (message.contains('cached_content')) {
    return ArgumentError(
      '$message (set as LlmRequest.config.cached_content; '
      'this request targets $target.)',
    );
  }
  return ArgumentError('$message (this request targets $target.)');
}

Object _unwrapApiClient(Object apiClient) {
  if (apiClient is Map) {
    if (apiClient.containsKey('_api_client') &&
        apiClient['_api_client'] != null) {
      return apiClient['_api_client'] as Object;
    }
    if (apiClient.containsKey('_apiClient') &&
        apiClient['_apiClient'] != null) {
      return apiClient['_apiClient'] as Object;
    }
    if (apiClient.containsKey('apiClient') && apiClient['apiClient'] != null) {
      return apiClient['apiClient'] as Object;
    }
    return apiClient;
  }
  final dynamic dyn = apiClient;
  try {
    final Object? inner = dyn._api_client;
    if (inner != null) {
      return inner;
    }
  } catch (_) {}
  try {
    final Object? inner = dyn._apiClient;
    if (inner != null) {
      return inner;
    }
  } catch (_) {}
  try {
    final Object? inner = dyn.apiClient;
    if (inner != null) {
      return inner;
    }
  } catch (_) {}
  return apiClient;
}

bool? _clientVertexAi(Object client) {
  if (client is Map) {
    final Object? v = client['vertexai'];
    if (v is bool) {
      return v;
    }
    return null;
  }
  final dynamic dyn = client;
  try {
    final Object? v = dyn.vertexai;
    if (v is bool) {
      return v;
    }
  } catch (_) {}
  return null;
}

String? _clientStringProperty(Object client, String property) {
  if (client is Map) {
    final Object? v = client[property];
    if (v is String && v.isNotEmpty) {
      return v;
    }
    return null;
  }
  final dynamic dyn = client;
  try {
    final Object? v = property == 'project' ? dyn.project : dyn.location;
    if (v is String && v.isNotEmpty) {
      return v;
    }
  } catch (_) {}
  return null;
}

/// Converts [llmRequest] into a `generateContent` JSON request body.
///
/// Uses [vertexai], [apiClient], or [environment] to determine whether the
/// request targets Vertex AI or the Gemini Developer API.
Map<String, dynamic> toGenerateContentBody(
  LlmRequest llmRequest, {
  bool? vertexai,
  Object? apiClient,
  Map<String, String>? environment,
}) {
  Object? unwrappedClient;
  late final bool isVertex;
  if (apiClient != null) {
    unwrappedClient = _unwrapApiClient(apiClient);
    isVertex =
        _clientVertexAi(unwrappedClient) ??
        vertexai ??
        (getGoogleLlmVariant(environment: environment) ==
            GoogleLLMVariant.vertexAi);
  } else {
    isVertex =
        vertexai ??
        (getGoogleLlmVariant(environment: environment) ==
            GoogleLLMVariant.vertexAi);
  }

  try {
    return _buildGenerateContentBody(
      llmRequest,
      isVertex: isVertex,
      apiClient: unwrappedClient,
    );
  } on ArgumentError catch (exc) {
    throw annotateValueError(exc, vertexai: isVertex);
  }
}

Map<String, dynamic> _buildGenerateContentBody(
  LlmRequest llmRequest, {
  required bool isVertex,
  required Object? apiClient,
}) {
  final GenerateContentConfig config = llmRequest.config;

  // Validate backend-exclusive fields before building the body.
  if (!isVertex) {
    if (config.modelArmorConfig != null) {
      throw ArgumentError(
        'model_armor_config parameter is not supported in Gemini API.',
      );
    }
    if (config.generationOutputConfig != null) {
      throw ArgumentError(
        'generation_output_config parameter is not supported in Gemini API.',
      );
    }
    if (config.routingConfig != null) {
      throw ArgumentError(
        'routing_config parameter is not supported in Gemini API.',
      );
    }
    if (config.modelSelectionConfig != null) {
      throw ArgumentError(
        'model_selection_config parameter is not supported in Gemini API.',
      );
    }
    if (config.audioTimestamp != null) {
      throw ArgumentError(
        'audio_timestamp parameter is not supported in Gemini API.',
      );
    }
    if (config.labels.isNotEmpty) {
      throw ArgumentError('labels parameter is not supported in Gemini API.');
    }
    if (config.audioTranscriptionConfig != null) {
      throw ArgumentError(
        'audio_transcription_config parameter is not supported in Gemini API.',
      );
    }
    if (config.continuationToken != null) {
      throw ArgumentError(
        'continuation_token parameter is not supported in Gemini API.',
      );
    }
  } else {
    if (config.enableEnhancedCivicAnswers != null) {
      throw ArgumentError(
        'enable_enhanced_civic_answers parameter is not supported in Vertex AI.',
      );
    }
    if (config.store != null) {
      throw ArgumentError('store parameter is not supported in Vertex AI.');
    }
  }

  final Map<String, dynamic> body = <String, dynamic>{};

  if (llmRequest.contents.isNotEmpty) {
    body['contents'] = llmRequest.contents
        .map<Map<String, dynamic>>(_serializeContent)
        .toList();
  }

  // Top-level config fields.
  if (config.systemInstruction != null) {
    body['systemInstruction'] = <String, dynamic>{
      'parts': <Map<String, dynamic>>[
        <String, dynamic>{'text': config.systemInstruction},
      ],
    };
  }
  if (config.tools != null && config.tools!.isNotEmpty) {
    body['tools'] = config.tools!
        .map<Object?>(_serializeToolDeclaration)
        .toList();
  }
  if (config.toolConfig != null) {
    final Map<String, dynamic> serializedToolConfig = _serializeToolConfig(
      config.toolConfig!,
    );
    if (serializedToolConfig.isNotEmpty) {
      body['toolConfig'] = serializedToolConfig;
    }
  }
  if (config.safetySettings != null && config.safetySettings!.isNotEmpty) {
    body['safetySettings'] = config.safetySettings!
        .map<Object?>(_serializeDynamic)
        .toList();
  }
  if (config.cachedContent != null && config.cachedContent!.isNotEmpty) {
    body['cachedContent'] = _resolveCachedContent(
      config.cachedContent!,
      isVertex: isVertex,
      apiClient: apiClient,
    );
  }
  if (isVertex && config.labels.isNotEmpty) {
    body['labels'] = Map<String, dynamic>.from(config.labels);
  }
  if (isVertex && config.modelArmorConfig != null) {
    body['modelArmorConfig'] = _serializeDynamic(config.modelArmorConfig);
  }
  final Object? effectiveServiceTier =
      config.serviceTier ?? llmRequest.serviceTier;
  if (effectiveServiceTier != null) {
    body['serviceTier'] = _serializeDynamic(effectiveServiceTier);
  }
  if (isVertex && config.continuationToken != null) {
    body['continuationToken'] = _serializeDynamic(config.continuationToken);
  }
  if (isVertex && config.generationOutputConfig != null) {
    body['outputConfig'] = _serializeDynamic(config.generationOutputConfig);
  }
  if (!isVertex && config.store != null) {
    body['store'] = config.store;
  }

  // GenerationConfig fields.
  final Map<String, dynamic> generationConfig = <String, dynamic>{};
  if (config.temperature != null) {
    generationConfig['temperature'] = config.temperature;
  }
  if (config.topP != null) {
    generationConfig['topP'] = config.topP;
  }
  if (config.topK != null) {
    generationConfig['topK'] = config.topK;
  }
  if (config.candidateCount != null) {
    generationConfig['candidateCount'] = config.candidateCount;
  }
  if (config.maxOutputTokens != null) {
    generationConfig['maxOutputTokens'] = config.maxOutputTokens;
  }
  if (config.stopSequences.isNotEmpty) {
    generationConfig['stopSequences'] = List<String>.from(config.stopSequences);
  }
  if (config.responseLogprobs != null) {
    generationConfig['responseLogprobs'] = config.responseLogprobs;
  }
  if (config.logprobs != null) {
    generationConfig['logprobs'] = config.logprobs;
  }
  if (config.presencePenalty != null) {
    generationConfig['presencePenalty'] = config.presencePenalty;
  }
  if (config.frequencyPenalty != null) {
    generationConfig['frequencyPenalty'] = config.frequencyPenalty;
  }
  if (config.seed != null) {
    generationConfig['seed'] = config.seed;
  }
  if (config.responseMimeType != null) {
    generationConfig['responseMimeType'] = config.responseMimeType;
  }
  if (config.responseSchema != null) {
    generationConfig['responseSchema'] = _serializeDynamic(
      config.responseSchema,
    );
  }
  if (config.responseJsonSchema != null) {
    generationConfig['responseJsonSchema'] = _serializeDynamic(
      config.responseJsonSchema,
    );
  }
  if (isVertex && config.routingConfig != null) {
    generationConfig['routingConfig'] = _serializeDynamic(config.routingConfig);
  }
  if (isVertex && config.modelSelectionConfig != null) {
    generationConfig['modelConfig'] = _serializeDynamic(
      config.modelSelectionConfig,
    );
  }
  if (config.responseModalities != null &&
      config.responseModalities!.isNotEmpty) {
    generationConfig['responseModalities'] = List<String>.from(
      config.responseModalities!,
    );
  }
  if (config.mediaResolution != null) {
    generationConfig['mediaResolution'] = _serializeDynamic(
      config.mediaResolution,
    );
  }
  if (config.speechConfig != null) {
    generationConfig['speechConfig'] = _serializeDynamic(config.speechConfig);
  }
  if (isVertex && config.audioTimestamp != null) {
    generationConfig['audioTimestamp'] = config.audioTimestamp;
  }
  if (config.thinkingConfig != null) {
    generationConfig['thinkingConfig'] = _serializeDynamic(
      config.thinkingConfig,
    );
  }
  if (config.imageConfig != null) {
    generationConfig['imageConfig'] = _serializeDynamic(config.imageConfig);
  }
  if (isVertex && config.audioTranscriptionConfig != null) {
    generationConfig['audioTranscriptionConfig'] = _serializeDynamic(
      config.audioTranscriptionConfig,
    );
  }
  if (!isVertex && config.enableEnhancedCivicAnswers != null) {
    generationConfig['enableEnhancedCivicAnswers'] =
        config.enableEnhancedCivicAnswers;
  }
  if (config.enableAffectiveDialog != null) {
    generationConfig['enableAffectiveDialog'] = config.enableAffectiveDialog;
  }

  if (generationConfig.isNotEmpty) {
    body['generationConfig'] = generationConfig;
  }

  body.remove('_url');
  body.remove('config');
  body.remove('model');
  return body;
}

String _resolveCachedContent(
  String cachedContent, {
  required bool isVertex,
  required Object? apiClient,
}) {
  if (isVertex) {
    if (_vertexCachedContentFullPattern.hasMatch(cachedContent)) {
      return cachedContent;
    }
    final String? project = apiClient == null
        ? null
        : _clientStringProperty(apiClient, 'project');
    final String? location = apiClient == null
        ? null
        : _clientStringProperty(apiClient, 'location');
    if (project == null || location == null) {
      throw ArgumentError(
        'cached_content must be a full resource name '
        '(projects/{project}/locations/{location}/cachedContents/{id}) '
        'unless an api_client is given, because Vertex AI needs a '
        'project and location to expand a short name.',
      );
    }
    final String id = cachedContent.startsWith('cachedContents/')
        ? cachedContent.substring('cachedContents/'.length)
        : cachedContent;
    return 'projects/$project/locations/$location/cachedContents/$id';
  }

  if (cachedContent.startsWith('cachedContents/') ||
      cachedContent.startsWith('projects/')) {
    return cachedContent;
  }
  return 'cachedContents/$cachedContent';
}

Map<String, dynamic> _serializeContent(Content content) {
  return <String, dynamic>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map<Map<String, dynamic>>(_serializePart).toList(),
  };
}

Map<String, dynamic> _serializePart(Part part) {
  final Map<String, dynamic> result = <String, dynamic>{};
  if (part.text != null) {
    result['text'] = part.text;
  }
  if (part.thought) {
    result['thought'] = true;
  }
  if (part.thoughtSignature != null) {
    result['thoughtSignature'] = base64Encode(part.thoughtSignature!);
  }
  if (part.inlineData != null) {
    result['inlineData'] = <String, dynamic>{
      'mimeType': part.inlineData!.mimeType,
      'data': base64Encode(part.inlineData!.data),
      if (part.inlineData!.displayName != null)
        'displayName': part.inlineData!.displayName,
    };
  }
  if (part.fileData != null) {
    result['fileData'] = <String, dynamic>{
      'fileUri': part.fileData!.fileUri,
      if (part.fileData!.mimeType != null) 'mimeType': part.fileData!.mimeType,
      if (part.fileData!.displayName != null)
        'displayName': part.fileData!.displayName,
    };
  }
  if (part.functionCall != null) {
    result['functionCall'] = <String, dynamic>{
      'name': part.functionCall!.name,
      'args': _serializeDynamic(part.functionCall!.args),
      if (part.functionCall!.id != null) 'id': part.functionCall!.id,
    };
  }
  if (part.functionResponse != null) {
    result['functionResponse'] = <String, dynamic>{
      'name': part.functionResponse!.name,
      'response': _serializeDynamic(part.functionResponse!.response),
      if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
    };
  }
  if (part.executableCode != null) {
    result['executableCode'] = _serializeDynamic(part.executableCode);
  }
  if (part.codeExecutionResult != null) {
    result['codeExecutionResult'] = _serializeDynamic(part.codeExecutionResult);
  }
  return result;
}

Map<String, dynamic> _serializeToolDeclaration(ToolDeclaration tool) {
  final Map<String, dynamic> result = <String, dynamic>{};
  if (tool.functionDeclarations.isNotEmpty) {
    result['functionDeclarations'] = tool.functionDeclarations
        .map<Map<String, dynamic>>(
          (FunctionDeclaration decl) => <String, dynamic>{
            'name': decl.name,
            if (decl.description.isNotEmpty) 'description': decl.description,
            if (decl.parameters.isNotEmpty)
              'parameters': _serializeDynamic(decl.parameters),
          },
        )
        .toList();
  }
  if (tool.googleSearch != null) {
    result['googleSearch'] = _serializeDynamic(tool.googleSearch);
  }
  if (tool.googleSearchRetrieval != null) {
    result['googleSearchRetrieval'] = _serializeDynamic(
      tool.googleSearchRetrieval,
    );
  }
  if (tool.urlContext != null) {
    result['urlContext'] = _serializeDynamic(tool.urlContext);
  }
  if (tool.codeExecution != null) {
    result['codeExecution'] = _serializeDynamic(tool.codeExecution);
  }
  if (tool.googleMaps != null) {
    result['googleMaps'] = _serializeDynamic(tool.googleMaps);
  }
  if (tool.enterpriseWebSearch != null) {
    result['enterpriseWebSearch'] = _serializeDynamic(tool.enterpriseWebSearch);
  }
  if (tool.retrieval != null) {
    result['retrieval'] = _serializeDynamic(tool.retrieval);
  }
  if (tool.computerUse != null) {
    result['computerUse'] = _serializeDynamic(tool.computerUse);
  }
  return result;
}

Map<String, dynamic> _serializeToolConfig(LlmToolConfig toolConfig) {
  final Map<String, dynamic> result = <String, dynamic>{};
  final FunctionCallingConfig? fcc = toolConfig.functionCallingConfig;
  if (fcc != null) {
    result['functionCallingConfig'] = <String, dynamic>{
      if (fcc.mode != FunctionCallingConfigMode.modeUnspecified)
        'mode': switch (fcc.mode) {
          FunctionCallingConfigMode.auto => 'AUTO',
          FunctionCallingConfigMode.any => 'ANY',
          FunctionCallingConfigMode.none => 'NONE',
          FunctionCallingConfigMode.modeUnspecified => 'MODE_UNSPECIFIED',
        },
      if (fcc.allowedFunctionNames.isNotEmpty)
        'allowedFunctionNames': List<String>.from(fcc.allowedFunctionNames),
    };
  }
  return result;
}

Object? _serializeDynamic(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Uint8List) {
    return base64Encode(value);
  }
  if (value is List<int>) {
    return base64Encode(value);
  }
  if (value is List) {
    return value.map<Object?>(_serializeDynamic).toList();
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _serializeDynamic(entry.value),
    };
  }
  if (value is Enum) {
    return value.name;
  }
  final dynamic dyn = value;
  try {
    final Object? jsonVal = dyn.toJson();
    return _serializeDynamic(jsonVal);
  } catch (e) {
    if (e is ArgumentError) {
      rethrow;
    }
  }
  return '$value';
}
