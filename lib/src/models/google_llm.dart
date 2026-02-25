import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../types/content.dart';
import '../utils/streaming_utils.dart';
import '../utils/variant_utils.dart';
import 'base_llm.dart';
import 'base_llm_connection.dart';
import 'cache_metadata.dart';
import 'gemini_context_cache_manager.dart';
import 'gemini_llm_connection.dart';
import 'gemini_rest_api_client.dart';
import 'llm_request.dart';
import 'llm_response.dart';

typedef GeminiGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);
typedef GeminiInteractionsInvoker =
    Stream<LlmResponse> Function(LlmRequest request, {required bool stream});
typedef GeminiLiveSessionFactory =
    GeminiLiveSession Function(LlmRequest request);

class ResourceExhaustedModelException implements Exception {
  ResourceExhaustedModelException(this.message);

  final String message;

  @override
  String toString() {
    return 'ResourceExhaustedModelException: $message';
  }
}

class Gemini extends BaseLlm {
  Gemini({
    super.model = 'gemini-2.5-flash',
    this.useInteractionsApi = false,
    this.retryOptions,
    this.baseUrl,
    this.speechConfig,
    this.cacheManager = const GeminiContextCacheManager(),
    this.environment,
    this.apiBackendOverride,
    this.interactionsInvoker,
    this.liveSessionFactory,
    this.restTransport,
    GeminiGenerateHook? generateHook,
  }) : _generateHook = generateHook;

  final bool useInteractionsApi;
  final Object? retryOptions;
  final String? baseUrl;
  final Object? speechConfig;
  final GeminiContextCacheManager cacheManager;
  final Map<String, String>? environment;
  final GoogleLLMVariant? apiBackendOverride;
  final GeminiInteractionsInvoker? interactionsInvoker;
  final GeminiLiveSessionFactory? liveSessionFactory;
  final GeminiRestTransport? restTransport;
  final GeminiGenerateHook? _generateHook;

  late final GeminiRestTransport _defaultRestTransport =
      GeminiRestHttpTransport();

  GeminiRestTransport get _resolvedRestTransport =>
      restTransport ?? _defaultRestTransport;

  GoogleLLMVariant get apiBackend =>
      apiBackendOverride ?? getGoogleLlmVariant(environment: environment);

  String get _liveApiVersion =>
      apiBackend == GoogleLLMVariant.vertexAi ? 'v1beta1' : 'v1alpha';

  static List<RegExp> supportedModels() {
    return <RegExp>[
      RegExp(r'gemini-.*'),
      RegExp(r'model-optimizer-.*'),
      RegExp(r'projects\/.+\/locations\/.+\/endpoints\/.+'),
      RegExp(
        r'projects\/.+\/locations\/.+\/publishers\/google\/models\/gemini.+',
      ),
    ];
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model = prepared.model ?? model;
    _preprocessRequest(prepared);
    maybeAppendUserContent(prepared);
    prepared.config.httpOptions ??= HttpOptions();
    prepared.config.httpOptions!.headers = _mergeTrackingHeaders(
      prepared.config.httpOptions!.headers,
    );

    CacheMetadata? cacheMetadata;
    if (prepared.cacheConfig != null) {
      cacheMetadata = await cacheManager.handleContextCaching(prepared);
    }

    if (useInteractionsApi && interactionsInvoker != null) {
      await for (final LlmResponse response in interactionsInvoker!(
        prepared,
        stream: stream,
      )) {
        if (cacheMetadata != null) {
          cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
        }
        yield response;
      }
      return;
    }

    if (_generateHook != null) {
      await for (final LlmResponse response in _generateHook(
        prepared,
        stream,
      )) {
        if (cacheMetadata != null) {
          cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
        }
        yield response;
      }
      return;
    }

    try {
      final String? apiKey = _resolveApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        developer.log(
          'Warning: GEMINI_API_KEY not set. Using mock Gemini response.',
          name: 'adk_dart.models',
        );
        final String text = _defaultText(prepared);
        final LlmResponse response = LlmResponse(
          modelVersion: prepared.model,
          content: Content.modelText(text),
          partial: stream ? false : null,
          turnComplete: true,
          interactionId: _deriveInteractionId(prepared),
        );
        if (cacheMetadata != null) {
          cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
        }
        yield response;
        return;
      }

      final String computedModel = prepared.model ?? model;
      final String apiVersion =
          prepared.config.httpOptions?.apiVersion ?? 'v1beta';
      final Map<String, Object?> payload = _buildGenerateContentPayload(
        prepared,
      );

      if (stream) {
        final StreamingResponseAggregator aggregator =
            StreamingResponseAggregator();
        await for (final Map<String, Object?> chunk
            in _resolvedRestTransport.streamGenerateContent(
              model: computedModel,
              apiKey: apiKey,
              payload: payload,
              baseUrl: baseUrl,
              apiVersion: apiVersion,
              headers: prepared.config.httpOptions?.headers,
            )) {
          final LlmResponse response = _responseFromGeminiApi(
            chunk,
            fallbackModelVersion: computedModel,
          );
          await for (final LlmResponse aggregated in aggregator.processResponse(
            response,
          )) {
            final LlmResponse emitted = aggregated.copyWith();
            emitted.partial ??= true;
            emitted.turnComplete ??= emitted.finishReason != null;
            emitted.interactionId ??= _deriveInteractionId(prepared);
            if (cacheMetadata != null) {
              cacheManager.populateCacheMetadataInResponse(
                emitted,
                cacheMetadata,
              );
            }
            yield emitted;
          }
        }

        final LlmResponse? finalResponse = aggregator.close();
        if (finalResponse != null) {
          finalResponse.partial ??= false;
          finalResponse.turnComplete ??= true;
          finalResponse.interactionId ??= _deriveInteractionId(prepared);
          if (cacheMetadata != null) {
            cacheManager.populateCacheMetadataInResponse(
              finalResponse,
              cacheMetadata,
            );
          }
          yield finalResponse;
        }
      } else {
        final Map<String, Object?> rawResponse = await _resolvedRestTransport
            .generateContent(
              model: computedModel,
              apiKey: apiKey,
              payload: payload,
              baseUrl: baseUrl,
              apiVersion: apiVersion,
              headers: prepared.config.httpOptions?.headers,
            );
        final LlmResponse response = _responseFromGeminiApi(
          rawResponse,
          fallbackModelVersion: computedModel,
        );
        response.partial ??= false;
        response.turnComplete ??= true;
        response.interactionId ??= _deriveInteractionId(prepared);
        if (cacheMetadata != null) {
          cacheManager.populateCacheMetadataInResponse(response, cacheMetadata);
        }
        yield response;
      }
    } catch (error) {
      if (error is GeminiRestApiException && error.statusCode == 429) {
        throw ResourceExhaustedModelException(error.message);
      }
      final String message = '$error';
      if (message.contains('429') ||
          message.toLowerCase().contains('resource_exhausted')) {
        throw ResourceExhaustedModelException(message);
      }
      rethrow;
    }
  }

  BaseLlmConnection connect(LlmRequest request) {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model = prepared.model ?? model;
    prepared.liveConnectConfig.httpOptions ??= HttpOptions();
    prepared.liveConnectConfig.httpOptions!.headers = _mergeTrackingHeaders(
      prepared.liveConnectConfig.httpOptions!.headers,
    );
    prepared.liveConnectConfig.httpOptions!.apiVersion = _liveApiVersion;
    if (speechConfig != null) {
      prepared.liveConnectConfig.speechConfig = speechConfig;
    }
    if (prepared.config.systemInstruction != null &&
        prepared.config.systemInstruction!.isNotEmpty) {
      prepared.liveConnectConfig.systemInstruction = Content(
        role: 'system',
        parts: <Part>[Part.text(prepared.config.systemInstruction!)],
      );
    }
    prepared.liveConnectConfig.tools = prepared.config.tools
        ?.map((ToolDeclaration tool) => tool.copyWith())
        .toList();

    return GeminiLlmConnection(
      model: this,
      initialRequest: prepared,
      liveSession: liveSessionFactory?.call(prepared),
      apiBackend: apiBackend,
      modelVersion: prepared.model,
    );
  }

  String _defaultText(LlmRequest request) {
    for (int i = request.contents.length - 1; i >= 0; i -= 1) {
      final Content content = request.contents[i];
      if (content.role != 'user') {
        continue;
      }
      for (int j = content.parts.length - 1; j >= 0; j -= 1) {
        final String? text = content.parts[j].text;
        if (text != null && text.isNotEmpty) {
          return 'Gemini response: $text';
        }
      }
    }
    return 'Gemini response.';
  }

  String? _deriveInteractionId(LlmRequest request) {
    final String? previous = request.previousInteractionId;
    if (previous == null || previous.isEmpty) {
      return null;
    }
    return '${previous}_next';
  }

  String? _resolveApiKey() {
    final Map<String, String> env = environment ?? Platform.environment;
    final String? key = env['GEMINI_API_KEY'] ?? env['GOOGLE_API_KEY'];
    if (key == null || key.isEmpty) {
      return null;
    }
    return key;
  }

  void _preprocessRequest(LlmRequest request) {
    if (apiBackend == GoogleLLMVariant.geminiApi) {
      request.config.labels = <String, String>{};
      for (final Content content in request.contents) {
        for (final Part part in content.parts) {
          if (part.inlineData != null && part.inlineData!.displayName != null) {
            part.inlineData = part.inlineData!.copyWith(displayName: null);
          }
          if (part.fileData != null && part.fileData!.displayName != null) {
            part.fileData = part.fileData!.copyWith(displayName: null);
          }
        }
      }
    }

    final List<ToolDeclaration>? tools = request.config.tools;
    if (tools != null &&
        tools.any((ToolDeclaration tool) => tool.computerUse != null)) {
      request.config.systemInstruction = null;
    }
  }

  Map<String, String> _mergeTrackingHeaders(Map<String, String>? headers) {
    final Map<String, String> merged = <String, String>{
      'x-goog-api-client': 'adk_dart',
    };
    if (headers != null) {
      merged.addAll(headers);
    }
    return merged;
  }

  Map<String, Object?> _buildGenerateContentPayload(LlmRequest request) {
    final Map<String, Object?> payload = <String, Object?>{};

    final List<Map<String, Object?>> contents = _serializeContents(
      request.contents,
    );
    if (contents.isNotEmpty) {
      payload['contents'] = contents;
    }

    final String? systemInstruction = request.config.systemInstruction;
    if (systemInstruction != null && systemInstruction.isNotEmpty) {
      payload['systemInstruction'] = <String, Object?>{
        'parts': <Map<String, Object?>>[
          <String, Object?>{'text': systemInstruction},
        ],
      };
    }

    final List<Map<String, Object?>> tools = _serializeTools(
      request.config.tools,
    );
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
    }

    final Map<String, Object?>? toolConfig = _serializeToolConfig(
      request.config.toolConfig,
    );
    if (toolConfig != null && toolConfig.isNotEmpty) {
      payload['toolConfig'] = toolConfig;
    }

    final Map<String, Object?> generationConfig = _serializeGenerationConfig(
      request.config,
    );
    if (generationConfig.isNotEmpty) {
      payload['generationConfig'] = generationConfig;
    }

    final String? cachedContent = request.config.cachedContent;
    if (cachedContent != null && cachedContent.isNotEmpty) {
      payload['cachedContent'] = cachedContent;
    }

    if (request.config.labels.isNotEmpty) {
      payload['labels'] = Map<String, String>.from(request.config.labels);
    }

    return payload;
  }

  List<Map<String, Object?>> _serializeContents(List<Content> contents) {
    final List<Map<String, Object?>> output = <Map<String, Object?>>[];
    for (final Content content in contents) {
      final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
      for (final Part part in content.parts) {
        final Map<String, Object?>? encoded = _serializePart(part);
        if (encoded != null) {
          parts.add(encoded);
        }
      }
      if (parts.isEmpty) {
        continue;
      }
      output.add(<String, Object?>{
        'role': content.role ?? 'user',
        'parts': parts,
      });
    }
    return output;
  }

  Map<String, Object?>? _serializePart(Part part) {
    final String? text = part.text;
    if (text != null) {
      return _withPartMetadata(<String, Object?>{
        'text': text,
        if (part.thought) 'thought': true,
      }, part);
    }

    final FunctionCall? functionCall = part.functionCall;
    if (functionCall != null) {
      return _withPartMetadata(<String, Object?>{
        'functionCall': <String, Object?>{
          'name': functionCall.name,
          'args': Map<String, dynamic>.from(functionCall.args),
          if (functionCall.id != null && functionCall.id!.isNotEmpty)
            'id': functionCall.id,
          if (functionCall.partialArgs != null)
            'partialArgs': functionCall.partialArgs
                ?.map(
                  (Map<String, Object?> value) =>
                      Map<String, Object?>.from(value),
                )
                .toList(growable: false),
          if (functionCall.willContinue != null)
            'willContinue': functionCall.willContinue,
        },
      }, part);
    }

    final FunctionResponse? functionResponse = part.functionResponse;
    if (functionResponse != null) {
      return _withPartMetadata(<String, Object?>{
        'functionResponse': <String, Object?>{
          'name': functionResponse.name,
          'response': Map<String, dynamic>.from(functionResponse.response),
          if (functionResponse.id != null && functionResponse.id!.isNotEmpty)
            'id': functionResponse.id,
        },
      }, part);
    }

    final InlineData? inlineData = part.inlineData;
    if (inlineData != null) {
      return _withPartMetadata(<String, Object?>{
        'inlineData': <String, Object?>{
          'mimeType': inlineData.mimeType,
          'data': base64Encode(inlineData.data),
          if (inlineData.displayName != null &&
              inlineData.displayName!.isNotEmpty)
            'displayName': inlineData.displayName,
        },
      }, part);
    }

    final FileData? fileData = part.fileData;
    if (fileData != null) {
      return _withPartMetadata(<String, Object?>{
        'fileData': <String, Object?>{
          'fileUri': fileData.fileUri,
          if (fileData.mimeType != null && fileData.mimeType!.isNotEmpty)
            'mimeType': fileData.mimeType,
          if (fileData.displayName != null && fileData.displayName!.isNotEmpty)
            'displayName': fileData.displayName,
        },
      }, part);
    }

    if (part.executableCode != null) {
      return _withPartMetadata(<String, Object?>{
        'text': '${part.executableCode}',
      }, part);
    }
    if (part.codeExecutionResult != null) {
      return _withPartMetadata(<String, Object?>{
        'text': '${part.codeExecutionResult}',
      }, part);
    }

    return null;
  }

  Map<String, Object?> _withPartMetadata(
    Map<String, Object?> partMap,
    Part part,
  ) {
    final List<int>? thoughtSignature = part.thoughtSignature;
    if (thoughtSignature != null && thoughtSignature.isNotEmpty) {
      partMap['thoughtSignature'] = base64Encode(thoughtSignature);
    }
    return partMap;
  }

  List<Map<String, Object?>> _serializeTools(List<ToolDeclaration>? tools) {
    if (tools == null || tools.isEmpty) {
      return const <Map<String, Object?>>[];
    }

    final List<Map<String, Object?>> output = <Map<String, Object?>>[];
    for (final ToolDeclaration tool in tools) {
      final Map<String, Object?> encoded = <String, Object?>{};

      if (tool.functionDeclarations.isNotEmpty) {
        encoded['functionDeclarations'] = tool.functionDeclarations
            .map(
              (FunctionDeclaration declaration) => <String, Object?>{
                'name': declaration.name,
                if (declaration.description.isNotEmpty)
                  'description': declaration.description,
                if (declaration.parameters.isNotEmpty)
                  'parameters': _jsonCompatible(declaration.parameters),
              },
            )
            .toList(growable: false);
      }

      if (tool.computerUse != null) {
        encoded['computerUse'] = _jsonCompatible(tool.computerUse);
      }

      if (encoded.isNotEmpty) {
        output.add(encoded);
      }
    }

    return output;
  }

  Map<String, Object?>? _serializeToolConfig(LlmToolConfig? toolConfig) {
    if (toolConfig == null) {
      return null;
    }

    final FunctionCallingConfig? functionCallingConfig =
        toolConfig.functionCallingConfig;
    if (functionCallingConfig == null) {
      return null;
    }

    return <String, Object?>{
      'functionCallingConfig': <String, Object?>{
        'mode': _functionCallingModeValue(functionCallingConfig.mode),
        if (functionCallingConfig.allowedFunctionNames.isNotEmpty)
          'allowedFunctionNames': List<String>.from(
            functionCallingConfig.allowedFunctionNames,
          ),
      },
    };
  }

  String _functionCallingModeValue(FunctionCallingConfigMode mode) {
    switch (mode) {
      case FunctionCallingConfigMode.auto:
        return 'AUTO';
      case FunctionCallingConfigMode.any:
        return 'ANY';
      case FunctionCallingConfigMode.none:
        return 'NONE';
      case FunctionCallingConfigMode.modeUnspecified:
        return 'MODE_UNSPECIFIED';
    }
  }

  Map<String, Object?> _serializeGenerationConfig(
    GenerateContentConfig config,
  ) {
    final Map<String, Object?> output = <String, Object?>{};
    if (config.temperature != null) {
      output['temperature'] = config.temperature;
    }
    if (config.topP != null) {
      output['topP'] = config.topP;
    }
    if (config.topK != null) {
      output['topK'] = config.topK;
    }
    if (config.maxOutputTokens != null) {
      output['maxOutputTokens'] = config.maxOutputTokens;
    }
    if (config.stopSequences.isNotEmpty) {
      output['stopSequences'] = List<String>.from(config.stopSequences);
    }
    if (config.frequencyPenalty != null) {
      output['frequencyPenalty'] = config.frequencyPenalty;
    }
    if (config.presencePenalty != null) {
      output['presencePenalty'] = config.presencePenalty;
    }
    if (config.seed != null) {
      output['seed'] = config.seed;
    }
    if (config.candidateCount != null) {
      output['candidateCount'] = config.candidateCount;
    }
    if (config.responseLogprobs != null) {
      output['responseLogprobs'] = config.responseLogprobs;
    }
    if (config.logprobs != null) {
      output['logprobs'] = config.logprobs;
    }
    if (config.thinkingConfig != null) {
      output['thinkingConfig'] = _jsonCompatible(config.thinkingConfig);
    }
    if (config.responseSchema != null) {
      output['responseSchema'] = _jsonCompatible(config.responseSchema);
    }
    if (config.responseJsonSchema != null) {
      output['responseJsonSchema'] = _jsonCompatible(config.responseJsonSchema);
    }
    if (config.responseMimeType != null &&
        config.responseMimeType!.isNotEmpty) {
      output['responseMimeType'] = config.responseMimeType;
    }
    return output;
  }

  LlmResponse _responseFromGeminiApi(
    Map<String, Object?> responseMap, {
    required String fallbackModelVersion,
  }) {
    final String modelVersion =
        _stringValue(responseMap['modelVersion']) ?? fallbackModelVersion;
    final Object? usageMetadata = _nullableMap(responseMap['usageMetadata']);
    final Object? responseGroundingMetadata =
        _nullableMap(responseMap['groundingMetadata']) ??
        responseMap['groundingMetadata'];
    final String? interactionId =
        _stringValue(responseMap['interactionId']) ??
        _stringValue(responseMap['interaction_id']);
    final List<Object?> candidates = _asList(responseMap['candidates']);

    if (candidates.isNotEmpty) {
      final Map<String, Object?> candidate = _asMap(candidates.first);
      final Content? content = _parseContent(_asMap(candidate['content']));
      final String? finishReason = _stringValue(candidate['finishReason']);
      final Object? groundingMetadata =
          _nullableMap(candidate['groundingMetadata']) ??
          candidate['groundingMetadata'] ??
          responseGroundingMetadata;
      final bool hasContent = content != null && content.parts.isNotEmpty;
      if (hasContent || finishReason == 'STOP') {
        return LlmResponse(
          modelVersion: modelVersion,
          content: content,
          finishReason: finishReason,
          usageMetadata: usageMetadata,
          citationMetadata: _nullableMap(candidate['citationMetadata']),
          groundingMetadata: groundingMetadata,
          avgLogprobs: _doubleValue(candidate['avgLogprobs']),
          logprobsResult:
              _nullableMap(candidate['logprobsResult']) ??
              candidate['logprobsResult'],
          interactionId: interactionId,
        );
      }

      return LlmResponse(
        modelVersion: modelVersion,
        errorCode: finishReason ?? 'UNKNOWN_ERROR',
        errorMessage:
            _stringValue(candidate['finishMessage']) ??
            'Model returned no content.',
        usageMetadata: usageMetadata,
        finishReason: finishReason,
        citationMetadata: _nullableMap(candidate['citationMetadata']),
        groundingMetadata: groundingMetadata,
        avgLogprobs: _doubleValue(candidate['avgLogprobs']),
        logprobsResult:
            _nullableMap(candidate['logprobsResult']) ??
            candidate['logprobsResult'],
        interactionId: interactionId,
      );
    }

    final Map<String, Object?> promptFeedback = _asMap(
      responseMap['promptFeedback'],
    );
    if (promptFeedback.isNotEmpty) {
      return LlmResponse(
        modelVersion: modelVersion,
        errorCode:
            _stringValue(promptFeedback['blockReason']) ?? 'UNKNOWN_ERROR',
        errorMessage:
            _stringValue(promptFeedback['blockReasonMessage']) ??
            'Request blocked.',
        usageMetadata: usageMetadata,
        groundingMetadata: responseGroundingMetadata,
        interactionId: interactionId,
      );
    }

    return LlmResponse(
      modelVersion: modelVersion,
      errorCode: 'UNKNOWN_ERROR',
      errorMessage: 'Unknown error.',
      usageMetadata: usageMetadata,
      groundingMetadata: responseGroundingMetadata,
      interactionId: interactionId,
    );
  }

  Content? _parseContent(Map<String, Object?> contentMap) {
    if (contentMap.isEmpty) {
      return null;
    }
    final List<Object?> partsRaw = _asList(contentMap['parts']);
    final List<Part> parts = partsRaw
        .map(_parsePart)
        .whereType<Part>()
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }
    return Content(
      role: _stringValue(contentMap['role']) ?? 'model',
      parts: parts,
    );
  }

  Part? _parsePart(Object? rawPart) {
    final Map<String, Object?> partMap = _asMap(rawPart);
    if (partMap.isEmpty) {
      return null;
    }
    final List<int>? thoughtSignature = _decodeThoughtSignature(
      partMap['thoughtSignature'] ?? partMap['thought_signature'],
    );

    if (partMap.containsKey('text')) {
      final Object? rawText = partMap['text'];
      final String text = rawText == null ? '' : '$rawText';
      if (text.isEmpty &&
          thoughtSignature == null &&
          partMap['thought'] != true) {
        return null;
      }
      return Part.text(
        text,
        thought: partMap['thought'] == true,
        thoughtSignature: thoughtSignature,
      );
    }

    final Map<String, Object?> functionCall = _asMap(partMap['functionCall']);
    if (functionCall.isNotEmpty) {
      final String? name = _stringValue(functionCall['name']);
      if (name != null && name.isNotEmpty) {
        final JsonMap args = _coerceJsonMap(functionCall['args']);
        final List<Map<String, Object?>>? partialArgs = _coercePartialArgs(
          functionCall['partialArgs'] ??
              functionCall['partial_args'] ??
              args['partialArgs'] ??
              args['partial_args'],
        );
        final bool? willContinue = _coerceBool(
          functionCall['willContinue'] ??
              functionCall['will_continue'] ??
              args['willContinue'] ??
              args['will_continue'],
        );
        return Part.fromFunctionCall(
          name: name,
          args: args,
          id:
              _stringValue(functionCall['id']) ??
              _stringValue(functionCall['callId']) ??
              _stringValue(functionCall['call_id']),
          partialArgs: partialArgs,
          willContinue: willContinue,
          thoughtSignature: thoughtSignature,
        );
      }
    }

    final Map<String, Object?> functionResponse = _asMap(
      partMap['functionResponse'],
    );
    if (functionResponse.isNotEmpty) {
      final String? name = _stringValue(functionResponse['name']);
      if (name != null && name.isNotEmpty) {
        final Part parsed = Part.fromFunctionResponse(
          name: name,
          response: _coerceFunctionResponse(functionResponse['response']),
          id:
              _stringValue(functionResponse['id']) ??
              _stringValue(functionResponse['callId']) ??
              _stringValue(functionResponse['call_id']),
        );
        if (thoughtSignature == null) {
          return parsed;
        }
        return parsed.copyWith(thoughtSignature: thoughtSignature);
      }
    }

    final Map<String, Object?> inlineData = _asMap(partMap['inlineData']);
    if (inlineData.isNotEmpty) {
      final String? mimeType = _stringValue(inlineData['mimeType']);
      final String? encodedData = _stringValue(inlineData['data']);
      if (mimeType != null && encodedData != null) {
        final Part parsed = Part.fromInlineData(
          mimeType: mimeType,
          data: _decodeBase64(encodedData),
          displayName: _stringValue(inlineData['displayName']),
        );
        if (thoughtSignature == null) {
          return parsed;
        }
        return parsed.copyWith(thoughtSignature: thoughtSignature);
      }
    }

    final Map<String, Object?> fileData = _asMap(partMap['fileData']);
    if (fileData.isNotEmpty) {
      final String? fileUri = _stringValue(fileData['fileUri']);
      if (fileUri != null && fileUri.isNotEmpty) {
        final Part parsed = Part.fromFileData(
          fileUri: fileUri,
          mimeType: _stringValue(fileData['mimeType']),
          displayName: _stringValue(fileData['displayName']),
        );
        if (thoughtSignature == null) {
          return parsed;
        }
        return parsed.copyWith(thoughtSignature: thoughtSignature);
      }
    }

    return null;
  }

  JsonMap _coerceJsonMap(Object? value) {
    if (value is Map) {
      return value.map((Object? key, Object? item) => MapEntry('$key', item));
    }
    if (value is String && value.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map(
            (Object? key, Object? item) => MapEntry('$key', item),
          );
        }
      } catch (_) {
        return const <String, dynamic>{};
      }
    }
    return const <String, dynamic>{};
  }

  JsonMap _coerceFunctionResponse(Object? value) {
    if (value is Map) {
      return value.map((Object? key, Object? item) => MapEntry('$key', item));
    }
    if (value is String && value.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map(
            (Object? key, Object? item) => MapEntry('$key', item),
          );
        }
      } catch (_) {
        return <String, dynamic>{'result': value};
      }
      return <String, dynamic>{'result': value};
    }
    if (value == null) {
      return const <String, dynamic>{};
    }
    return <String, dynamic>{'result': value};
  }

  List<Map<String, Object?>>? _coercePartialArgs(Object? value) {
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

  bool? _coerceBool(Object? value) {
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

  List<int>? _decodeThoughtSignature(Object? value) {
    if (value is List) {
      final List<int> bytes = <int>[];
      for (final Object? item in value) {
        if (item is num) {
          bytes.add(item.toInt());
        }
      }
      if (bytes.isEmpty) {
        return null;
      }
      return bytes;
    }
    final String? encoded = _stringValue(value);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return base64Decode(encoded);
    } catch (_) {
      try {
        return base64Url.decode(base64Url.normalize(encoded));
      } catch (_) {
        return null;
      }
    }
  }

  List<int> _decodeBase64(String encoded) {
    try {
      return base64Decode(encoded);
    } catch (_) {
      return const <int>[];
    }
  }

  Object? _jsonCompatible(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? item) => MapEntry('$key', _jsonCompatible(item)),
      );
    }
    if (value is Iterable) {
      return value.map(_jsonCompatible).toList(growable: false);
    }
    return '$value';
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return const <String, Object?>{};
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

Map<String, Object?>? _nullableMap(Object? value) {
  final Map<String, Object?> map = _asMap(value);
  if (map.isEmpty) {
    return null;
  }
  return map;
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final String text = '$value';
  if (text.isEmpty) {
    return null;
  }
  return text;
}

double? _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

typedef GoogleLlm = Gemini;
