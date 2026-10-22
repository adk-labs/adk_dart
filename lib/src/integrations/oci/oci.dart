/// Oracle Cloud Infrastructure (OCI) Generative AI model integration.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../types/content.dart';

/// Default service endpoint for OCI Generative AI inference.
const String defaultOciServiceEndpoint =
    'https://inference.generativeai.us-chicago-1.oci.oraclecloud.com';

/// Default system prompt injected when none is provided on [LlmRequest].
const String defaultOciSystemPrompt = 'You are a helpful assistant.';

/// Finish reason returned by OCI when the model invokes tools.
const String finishReasonToolCalls = 'TOOL_CALLS';

/// Abstract client for OCI Generative AI inference APIs.
///
/// ```dart
/// class FakeOciClient implements OciGenAiClient {
///   @override
///   Future<Map<String, Object?>> chat(Map<String, Object?> chatDetails) async {
///     return <String, Object?>{
///       'chatResult': <String, Object?>{
///         'modelId': 'google.gemini-2.5-flash',
///         'chatResponse': <String, Object?>{
///           'choices': <Object?>[
///             <String, Object?>{
///               'finishReason': 'STOP',
///               'message': <String, Object?>{
///                 'content': <Object?>[
///                   <String, Object?>{'type': 'TEXT', 'text': 'Hello from OCI!'},
///                 ],
///               },
///             },
///           ],
///         },
///       },
///     };
///   }
///
///   @override
///   Stream<Map<String, Object?>> chatStream(
///     Map<String, Object?> chatDetails,
///   ) async* {}
/// }
/// ```
abstract interface class OciGenAiClient {
  /// Sends a non-streaming OCI `chat` request and returns the decoded JSON payload.
  Future<Map<String, Object?>> chat(Map<String, Object?> chatDetails);

  /// Sends a streaming OCI `chat` request and yields decoded SSE event maps.
  Stream<Map<String, Object?>> chatStream(Map<String, Object?> chatDetails);
}

/// Default HTTP/SSE implementation of [OciGenAiClient].
///
/// ```dart
/// final client = HttpOciGenAiClient(
///   serviceEndpoint: defaultOciServiceEndpoint,
///   bearerToken: 'token',
/// );
/// ```
class HttpOciGenAiClient implements OciGenAiClient {
  /// Creates an HTTP client targeting an OCI Generative AI [serviceEndpoint].
  HttpOciGenAiClient({
    this.serviceEndpoint = defaultOciServiceEndpoint,
    this.bearerToken,
    this.defaultHeaders = const <String, String>{},
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Base URL of the OCI Generative AI inference service.
  final String serviceEndpoint;

  /// Optional bearer token or session token for authentication.
  final String? bearerToken;

  /// Additional HTTP headers included on every request.
  final Map<String, String> defaultHeaders;

  final HttpClient Function() _httpClientFactory;

  Uri _buildChatUri() {
    final String normalized = serviceEndpoint.endsWith('/')
        ? serviceEndpoint.substring(0, serviceEndpoint.length - 1)
        : serviceEndpoint;
    return Uri.parse('$normalized/20231130/actions/chat');
  }

  void _applyHeaders(HttpClientRequest request, {required bool stream}) {
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(
      HttpHeaders.acceptHeader,
      stream ? 'text/event-stream' : 'application/json',
    );
    final String? token =
        bearerToken ?? Platform.environment['OCI_SESSION_TOKEN'];
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    defaultHeaders.forEach(request.headers.set);
  }

  @override
  Future<Map<String, Object?>> chat(Map<String, Object?> chatDetails) async {
    final HttpClient httpClient = _httpClientFactory();
    try {
      final HttpClientRequest request = await httpClient.postUrl(
        _buildChatUri(),
      );
      _applyHeaders(request, stream: false);
      request.add(utf8.encode(jsonEncode(chatDetails)));
      final HttpClientResponse response = await request.close();
      final String bodyText = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'OCI Generative AI request failed (${response.statusCode}): $bodyText',
          uri: _buildChatUri(),
        );
      }
      if (bodyText.trim().isEmpty) {
        return <String, Object?>{};
      }
      final Object? decoded = jsonDecode(bodyText);
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
      }
      return <String, Object?>{'data': decoded};
    } finally {
      httpClient.close(force: false);
    }
  }

  @override
  Stream<Map<String, Object?>> chatStream(
    Map<String, Object?> chatDetails,
  ) async* {
    final HttpClient httpClient = _httpClientFactory();
    try {
      final HttpClientRequest request = await httpClient.postUrl(
        _buildChatUri(),
      );
      _applyHeaders(request, stream: true);
      request.add(utf8.encode(jsonEncode(chatDetails)));
      final HttpClientResponse response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String bodyText = await utf8.decoder.bind(response).join();
        throw HttpException(
          'OCI Generative AI stream failed (${response.statusCode}): $bodyText',
          uri: _buildChatUri(),
        );
      }

      final Stream<String> lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final StringBuffer dataBuffer = StringBuffer();
      await for (final String line in lines) {
        if (line.isEmpty) {
          if (dataBuffer.isNotEmpty) {
            final String payload = dataBuffer.toString().trim();
            dataBuffer.clear();
            final Map<String, Object?>? parsed = _parseSsePayload(payload);
            if (parsed != null) {
              yield parsed;
            }
          }
          continue;
        }
        if (line.startsWith('data:')) {
          final String chunk = line.substring(5).trimLeft();
          if (chunk == '[DONE]') {
            break;
          }
          if (dataBuffer.isNotEmpty) {
            dataBuffer.writeln();
          }
          dataBuffer.write(chunk);
        }
      }
      if (dataBuffer.isNotEmpty) {
        final Map<String, Object?>? parsed = _parseSsePayload(
          dataBuffer.toString().trim(),
        );
        if (parsed != null) {
          yield parsed;
        }
      }
    } finally {
      httpClient.close(force: false);
    }
  }

  Map<String, Object?>? _parseSsePayload(String payload) {
    if (payload.isEmpty || payload == '[DONE]') {
      return null;
    }
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map) {
      return decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
    return null;
  }
}

/// Oracle Cloud Infrastructure (OCI) Generative AI model adapter.
///
/// Supports OCI-hosted models (Gemini, Gemma, Llama, Grok, Mistral/Mixtral,
/// NVIDIA) through OCI's Generic Chat API (`GenericChatRequest`).
///
/// ```dart
/// final llm = OCIGenAILlm(
///   model: 'google.gemini-2.5-flash',
///   compartmentId: 'ocid1.compartment.oc1..example',
/// );
/// ```
class OCIGenAILlm extends BaseLlm {
  /// Creates an [OCIGenAILlm] instance.
  OCIGenAILlm({
    super.model = 'google.gemini-2.5-flash',
    this.endpointId,
    this.compartmentId,
    this.serviceEndpoint,
    this.authType = 'API_KEY',
    this.authProfile = 'DEFAULT',
    this.authFileLocation = '~/.oci/config',
    this.maxTokens = 2048,
    this.reasoningEffort,
    OciGenAiClient? client,
    Map<String, String>? environment,
  }) : _client = client,
       _environment = environment ?? Platform.environment;

  /// Optional dedicated cluster endpoint OCID.
  ///
  /// When set (or when `OCI_ENDPOINT_ID` is present in the environment),
  /// requests use `DEDICATED` serving mode instead of `ON_DEMAND`.
  final String? endpointId;

  /// Compartment OCID where the model or endpoint resides.
  ///
  /// Falls back to the `OCI_COMPARTMENT_ID` environment variable.
  final String? compartmentId;

  /// Regional OCI Generative AI service endpoint URL.
  ///
  /// Falls back to `OCI_SERVICE_ENDPOINT` or [defaultOciServiceEndpoint].
  final String? serviceEndpoint;

  /// OCI authentication strategy (`API_KEY`, `SECURITY_TOKEN`,
  /// `INSTANCE_PRINCIPAL`, `RESOURCE_PRINCIPAL`, or `OKE_WORKLOAD_IDENTITY`).
  final String authType;

  /// Profile name in the OCI config file (for `API_KEY` and `SECURITY_TOKEN`).
  final String authProfile;

  /// Path to the OCI configuration file.
  final String authFileLocation;

  /// Default maximum output tokens when not specified in [LlmRequest.config].
  final int maxTokens;

  /// Reasoning effort level for supported reasoning models
  /// (`NONE`, `MINIMAL`, `LOW`, `MEDIUM`, `HIGH`).
  final String? reasoningEffort;

  final OciGenAiClient? _client;
  final Map<String, String> _environment;

  /// Regex patterns matching OCI Generative AI model identifiers.
  static List<RegExp> supportedModels() {
    return <RegExp>[
      RegExp(r'^meta\.llama-.*$'),
      RegExp(r'^google\.gemini-.*$'),
      RegExp(r'^google\.gemma-.*$'),
      RegExp(r'^xai\.grok-.*$'),
      RegExp(r'^mistralai\.mistral-.*$'),
      RegExp(r'^mistralai\.mixtral-.*$'),
      RegExp(r'^nvidia\..*$'),
    ];
  }

  /// Resolves the active [OciGenAiClient].
  OciGenAiClient get client =>
      _client ??
      HttpOciGenAiClient(serviceEndpoint: resolvedServiceEndpoint);

  /// Resolves the compartment OCID from [compartmentId] or `OCI_COMPARTMENT_ID`.
  ///
  /// Throws an [ArgumentError] if neither is configured.
  String get resolvedCompartmentId {
    final String? value = compartmentId ?? _environment['OCI_COMPARTMENT_ID'];
    if (value == null || value.isEmpty) {
      throw ArgumentError(
        'OCI compartment_id is required. Pass compartmentId to OCIGenAILlm '
        'or set the OCI_COMPARTMENT_ID environment variable.',
      );
    }
    return value;
  }

  /// Resolves the service endpoint URL.
  String get resolvedServiceEndpoint {
    return serviceEndpoint ??
        _environment['OCI_SERVICE_ENDPOINT'] ??
        defaultOciServiceEndpoint;
  }

  /// Builds the OCI serving mode map (`DEDICATED` or `ON_DEMAND`).
  Map<String, Object?> resolveServingMode(String effectiveModel) {
    final String? endpoint = endpointId ?? _environment['OCI_ENDPOINT_ID'];
    if (endpoint != null && endpoint.isNotEmpty) {
      return <String, Object?>{
        'servingType': 'DEDICATED',
        'endpointId': endpoint,
      };
    }
    return <String, Object?>{
      'servingType': 'ON_DEMAND',
      'modelId': effectiveModel,
    };
  }

  /// Builds the OCI `ChatDetails` request map from [llmRequest].
  Map<String, Object?> buildChatDetails(
    LlmRequest llmRequest, {
    required bool stream,
  }) {
    final String effectiveModel =
        (llmRequest.model != null && llmRequest.model!.isNotEmpty)
        ? llmRequest.model!
        : model;

    final GenerateContentConfig config = llmRequest.config;
    final String systemInstruction =
        (config.systemInstruction != null &&
            config.systemInstruction!.isNotEmpty)
        ? config.systemInstruction!
        : defaultOciSystemPrompt;

    final List<Map<String, Object?>> messages = <Map<String, Object?>>[
      <String, Object?>{
        'role': 'SYSTEM',
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'TEXT', 'text': systemInstruction},
        ],
      },
    ];

    for (final Content content in llmRequest.contents) {
      messages.addAll(contentToOciMessages(content));
    }

    final List<Map<String, Object?>> tools = <Map<String, Object?>>[];
    if (config.tools != null) {
      for (final ToolDeclaration tool in config.tools!) {
        for (final FunctionDeclaration decl in tool.functionDeclarations) {
          tools.add(functionDeclarationToOciTool(decl));
        }
      }
    }

    final Map<String, Object?>? responseFormat = buildOciResponseFormat(config);

    final Map<String, Object?> chatRequest = <String, Object?>{
      'apiFormat': 'GENERIC',
      'messages': messages,
      'maxTokens': config.maxOutputTokens ?? maxTokens,
      'isStream': stream,
      'temperature': ?config.temperature,
      'topP': ?config.topP,
      'topK': ?config.topK,
      'frequencyPenalty': ?config.frequencyPenalty,
      'presencePenalty': ?config.presencePenalty,
      if (config.stopSequences.isNotEmpty) 'stop': config.stopSequences,
      'seed': ?config.seed,
      'reasoningEffort': ?reasoningEffort,
      'responseFormat': ?responseFormat,
      if (tools.isNotEmpty) ...<String, Object?>{
        'tools': tools,
        'toolChoice': <String, Object?>{'type': 'AUTO'},
      },
    };

    if (stream) {
      chatRequest['streamOptions'] = <String, Object?>{'isIncludeUsage': true};
    }

    return <String, Object?>{
      'compartmentId': resolvedCompartmentId,
      'servingMode': resolveServingMode(effectiveModel),
      'chatRequest': chatRequest,
    };
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    maybeAppendUserContent(request);
    final Map<String, Object?> chatDetails = buildChatDetails(
      request,
      stream: stream,
    );

    if (stream) {
      yield* _generateStream(chatDetails);
      return;
    }

    final Map<String, Object?> rawResponse = await client.chat(chatDetails);
    yield ociResponseToLlmResponse(rawResponse);
  }

  Stream<LlmResponse> _generateStream(
    Map<String, Object?> chatDetails,
  ) async* {
    final StringBuffer accumulatedText = StringBuffer();
    final StringBuffer accumulatedThought = StringBuffer();
    final List<Map<String, Object?>> accumulatedToolCalls =
        <Map<String, Object?>>[];
    String? finishReason;
    Map<String, Object?>? usageData;

    await for (final Map<String, Object?> eventData
        in client.chatStream(chatDetails)) {
      if (eventData['usage'] is Map) {
        usageData = _asStringMap(eventData['usage']);
      }

      if (eventData['finishReason'] is String) {
        finishReason = eventData['finishReason'] as String;
      }

      final Map<String, Object?>? message = _asStringMap(eventData['message']);
      if (message == null) {
        continue;
      }

      final String? reasoning = message['reasoningContent'] as String?;
      if (reasoning != null && reasoning.isNotEmpty) {
        accumulatedThought.write(reasoning);
        yield LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[Part.text(reasoning, thought: true)],
          ),
          partial: true,
        );
      }

      final Object? contentItems = message['content'];
      if (contentItems is List) {
        for (final Object? item in contentItems) {
          final Map<String, Object?>? block = _asStringMap(item);
          if (block != null && block['type'] == 'TEXT') {
            final String text = (block['text'] as String?) ?? '';
            if (text.isNotEmpty) {
              accumulatedText.write(text);
              yield LlmResponse(
                content: Content(role: 'model', parts: <Part>[Part.text(text)]),
                partial: true,
              );
            }
          }
        }
      }

      final Object? toolCalls = message['toolCalls'];
      if (toolCalls is List) {
        for (final Object? tc in toolCalls) {
          final Map<String, Object?>? tcMap = _asStringMap(tc);
          if (tcMap != null) {
            _accumulateToolCallChunk(accumulatedToolCalls, tcMap);
          }
        }
      }
    }

    final List<Part> finalParts = <Part>[];
    if (accumulatedThought.isNotEmpty) {
      finalParts.add(Part.text(accumulatedThought.toString(), thought: true));
    }
    if (accumulatedText.isNotEmpty) {
      finalParts.add(Part.text(accumulatedText.toString()));
    }
    for (final Map<String, Object?> tc in accumulatedToolCalls) {
      Map<String, Object?> args = <String, Object?>{};
      final String rawArgs = (tc['arguments'] as String?) ?? '';
      if (rawArgs.isNotEmpty) {
        try {
          final Object? parsed = jsonDecode(rawArgs);
          if (parsed is Map) {
            args = parsed.map(
              (Object? k, Object? v) => MapEntry('$k', v),
            );
          } else {
            args = <String, Object?>{'value': parsed};
          }
        } on FormatException {
          args = <String, Object?>{};
        }
      }
      final String? tcId = tc['id'] as String?;
      finalParts.add(
        Part.fromFunctionCall(
          name: (tc['name'] as String?) ?? '',
          args: args,
          id: (tcId != null && tcId.isNotEmpty) ? tcId : null,
        ),
      );
    }

    String? effectiveFinish = finishReason;
    if (accumulatedToolCalls.isNotEmpty) {
      effectiveFinish = finishReasonToolCalls;
    }

    yield LlmResponse(
      content: Content(role: 'model', parts: finalParts),
      finishReason: mapOciFinishReason(effectiveFinish),
      usageMetadata: extractOciUsageMetadata(usageData),
      partial: false,
      turnComplete: true,
    );
  }
}

/// Idiomatic Dart alias for [OCIGenAILlm].
typedef OciGenAiLlm = OCIGenAILlm;

/// Accumulates a streaming OCI tool call chunk into [accumulated].
void _accumulateToolCallChunk(
  List<Map<String, Object?>> accumulated,
  Map<String, Object?> chunk,
) {
  final String? tcId = chunk['id'] as String?;
  final String? tcName = chunk['name'] as String?;
  final String tcArgs = (chunk['arguments'] as String?) ?? '';

  if (tcName != null && tcName.isNotEmpty) {
    accumulated.add(<String, Object?>{
      'id': tcId ?? '',
      'name': tcName,
      'arguments': tcArgs,
    });
  } else if (accumulated.isNotEmpty) {
    final Map<String, Object?> last = accumulated.last;
    last['arguments'] = '${last['arguments'] ?? ''}$tcArgs';
    if ((last['id'] as String? ?? '').isEmpty && tcId != null) {
      last['id'] = tcId;
    }
  } else {
    accumulated.add(<String, Object?>{
      'id': tcId ?? '',
      'name': '',
      'arguments': tcArgs,
    });
  }
}

/// Converts an ADK [Content] object into one or more OCI message maps.
List<Map<String, Object?>> contentToOciMessages(Content content) {
  final String role = content.role ?? 'user';

  final List<Part> toolResponseParts = content.parts
      .where((Part p) => p.functionResponse != null)
      .toList();
  if (toolResponseParts.isNotEmpty) {
    final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
    for (final Part part in toolResponseParts) {
      final FunctionResponse fr = part.functionResponse!;
      final String serializedResponse = jsonEncode(fr.response);
      messages.add(<String, Object?>{
        'role': 'TOOL',
        'toolCallId': fr.id ?? fr.name,
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'TEXT', 'text': serializedResponse},
        ],
      });
    }
    return messages;
  }

  if (role == 'model' || role == 'assistant') {
    final List<Map<String, Object?>> textParts = <Map<String, Object?>>[];
    final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
    final List<String> thoughtTexts = <String>[];

    for (final Part part in content.parts) {
      if (part.thought && part.text != null && part.text!.isNotEmpty) {
        thoughtTexts.add(part.text!);
      } else if (part.text != null && part.text!.isNotEmpty) {
        textParts.add(<String, Object?>{'type': 'TEXT', 'text': part.text!});
      } else if (part.functionCall != null) {
        final FunctionCall fc = part.functionCall!;
        toolCalls.add(<String, Object?>{
          'type': 'FUNCTION',
          'id': fc.id ?? fc.name,
          'name': fc.name,
          'arguments': jsonEncode(fc.args),
        });
      }
    }

    return <Map<String, Object?>>[
      <String, Object?>{
        'role': 'ASSISTANT',
        if (textParts.isNotEmpty) 'content': textParts,
        if (toolCalls.isNotEmpty) 'toolCalls': toolCalls,
        if (thoughtTexts.isNotEmpty)
          'reasoningContent': thoughtTexts.join('\n'),
      },
    ];
  }

  final List<Map<String, Object?>> ociContent = <Map<String, Object?>>[];
  for (final Part part in content.parts) {
    if (part.thought) {
      continue;
    }
    final Map<String, Object?>? converted = partToOciContent(part);
    if (converted != null) {
      ociContent.add(converted);
    }
  }

  if (ociContent.isEmpty) {
    return <Map<String, Object?>>[];
  }

  return <Map<String, Object?>>[
    <String, Object?>{'role': 'USER', 'content': ociContent},
  ];
}

/// Converts a single ADK [Part] into an OCI content block map.
Map<String, Object?>? partToOciContent(Part part) {
  if (part.text != null && part.text!.isNotEmpty) {
    return <String, Object?>{'type': 'TEXT', 'text': part.text!};
  }
  if (part.inlineData != null && part.inlineData!.data.isNotEmpty) {
    final String mimeType = part.inlineData!.mimeType.isNotEmpty
        ? part.inlineData!.mimeType
        : 'application/octet-stream';
    final String b64 = base64Encode(part.inlineData!.data);
    final String dataUri = 'data:$mimeType;base64,$b64';
    return _mediaContentFromUri(dataUri, mimeType);
  }
  if (part.fileData != null && part.fileData!.fileUri.isNotEmpty) {
    final String mimeType = (part.fileData!.mimeType ?? '').isNotEmpty
        ? part.fileData!.mimeType!
        : 'application/octet-stream';
    return _mediaContentFromUri(part.fileData!.fileUri, mimeType);
  }
  return null;
}

Map<String, Object?> _mediaContentFromUri(String url, String mimeType) {
  final Map<String, Object?> urlObj = <String, Object?>{'url': url};
  if (mimeType.startsWith('image/')) {
    return <String, Object?>{'type': 'IMAGE', 'imageUrl': urlObj};
  }
  if (mimeType.startsWith('audio/')) {
    return <String, Object?>{'type': 'AUDIO', 'audioUrl': urlObj};
  }
  if (mimeType.startsWith('video/')) {
    return <String, Object?>{'type': 'VIDEO', 'videoUrl': urlObj};
  }
  return <String, Object?>{'type': 'DOCUMENT', 'documentUrl': urlObj};
}

/// Converts a Gemini/OpenAPI schema value into a JSON Schema map for OCI.
Map<String, Object?> schemaToJsonSchema(Object? schema) {
  if (schema is Map) {
    final Map<String, Object?> result = <String, Object?>{};
    schema.forEach((Object? rawKey, Object? value) {
      final String key = '$rawKey';
      if (key == 'type' && value is String) {
        result[key] = value.toLowerCase();
      } else if (key == 'properties' && value is Map) {
        result[key] = value.map(
          (Object? propName, Object? propVal) =>
              MapEntry('$propName', schemaToJsonSchema(propVal)),
        );
      } else if (key == 'items' && value != null) {
        result[key] = schemaToJsonSchema(value);
      } else if (key == 'anyOf' || key == 'any_of') {
        if (value is List) {
          result['anyOf'] = value.map(schemaToJsonSchema).toList();
        }
      } else if (value != null) {
        result[key] = value;
      }
    });
    return result;
  }
  return <String, Object?>{};
}

/// Builds an OCI `ResponseFormat` map from [config], or `null` for plain text.
Map<String, Object?>? buildOciResponseFormat(GenerateContentConfig config) {
  final Object? rawSchema = config.responseJsonSchema ?? config.responseSchema;
  if (rawSchema != null) {
    final Map<String, Object?> jsonSchema = schemaToJsonSchema(rawSchema);
    final String schemaName =
        (jsonSchema['title'] as String?) ?? 'response';
    return <String, Object?>{
      'type': 'JSON_SCHEMA',
      'jsonSchema': <String, Object?>{
        'name': schemaName,
        'schema': jsonSchema,
        'isStrict': true,
      },
    };
  }
  if (config.responseMimeType == 'application/json') {
    return <String, Object?>{'type': 'JSON_OBJECT'};
  }
  return null;
}

/// Converts an ADK [FunctionDeclaration] into an OCI `FunctionDefinition` map.
Map<String, Object?> functionDeclarationToOciTool(FunctionDeclaration decl) {
  Map<String, Object?> parameters = <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };
  if (decl.parameters.isNotEmpty) {
    parameters = schemaToJsonSchema(decl.parameters);
  }
  return <String, Object?>{
    'type': 'FUNCTION',
    'name': decl.name,
    'description': decl.description,
    'parameters': parameters,
  };
}

/// Maps an OCI finish reason string to an ADK finish reason string.
String mapOciFinishReason(String? reason) {
  if (reason == null || reason.isEmpty) {
    return 'STOP';
  }
  switch (reason.toLowerCase()) {
    case 'stop':
    case 'tool_calls':
      return 'STOP';
    case 'length':
    case 'max_tokens':
      return 'MAX_TOKENS';
    case 'content_filter':
    case 'safety':
      return 'SAFETY';
    default:
      return 'OTHER';
  }
}

/// Extracts ADK usage metadata from an OCI `Usage` map.
Map<String, Object?>? extractOciUsageMetadata(Map<String, Object?>? usage) {
  if (usage == null || usage.isEmpty) {
    return null;
  }
  final int promptTokens =
      _asInt(usage['promptTokens'] ?? usage['prompt_tokens']) ?? 0;
  final int completionTokens =
      _asInt(usage['completionTokens'] ?? usage['completion_tokens']) ?? 0;
  final int totalTokens =
      _asInt(usage['totalTokens'] ?? usage['total_tokens']) ??
      (promptTokens + completionTokens);

  final Map<String, Object?>? details = _asStringMap(
    usage['completionTokensDetails'] ?? usage['completion_tokens_details'],
  );
  final int? reasoningTokens = _asInt(
    details?['reasoningTokens'] ?? details?['reasoning_tokens'],
  );

  return <String, Object?>{
    'promptTokenCount': promptTokens,
    'candidatesTokenCount': completionTokens,
    'totalTokenCount': totalTokens,
    'thoughtsTokenCount': ?reasoningTokens,
  };
}

/// Converts a non-streaming OCI chat response payload into an [LlmResponse].
LlmResponse ociResponseToLlmResponse(Map<String, Object?> response) {
  final Map<String, Object?> chatResult =
      _asStringMap(response['chatResult'] ?? response['data']) ?? response;
  final Map<String, Object?> chatResponse =
      _asStringMap(chatResult['chatResponse']) ?? chatResult;
  final String? modelVersion = chatResult['modelId'] as String?;

  final Object? choicesObj = chatResponse['choices'];
  if (choicesObj is! List || choicesObj.isEmpty) {
    return LlmResponse(
      modelVersion: modelVersion,
      content: Content(role: 'model', parts: <Part>[]),
      errorCode: 'NO_CHOICES',
      errorMessage: 'OCI Generative AI returned no choices.',
    );
  }

  final Map<String, Object?> choice =
      _asStringMap(choicesObj.first) ?? <String, Object?>{};
  final Map<String, Object?> message =
      _asStringMap(choice['message']) ?? <String, Object?>{};
  final List<Part> parts = <Part>[];

  final String? reasoningContent = message['reasoningContent'] as String?;
  if (reasoningContent != null && reasoningContent.isNotEmpty) {
    parts.add(Part.text(reasoningContent, thought: true));
  }

  final Object? contentList = message['content'];
  if (contentList is List) {
    for (final Object? item in contentList) {
      final Map<String, Object?>? block = _asStringMap(item);
      if (block != null && block['type'] == 'TEXT') {
        final String? text = block['text'] as String?;
        if (text != null && text.isNotEmpty) {
          parts.add(Part.text(text));
        }
      }
    }
  }

  final Object? toolCalls = message['toolCalls'];
  if (toolCalls is List) {
    for (final Object? tc in toolCalls) {
      final Map<String, Object?>? tcMap = _asStringMap(tc);
      if (tcMap == null) {
        continue;
      }
      Map<String, Object?> args = <String, Object?>{};
      final String? rawArgs = tcMap['arguments'] as String?;
      if (rawArgs != null && rawArgs.isNotEmpty) {
        try {
          final Object? decoded = jsonDecode(rawArgs);
          if (decoded is Map) {
            args = decoded.map(
              (Object? k, Object? v) => MapEntry('$k', v),
            );
          } else {
            args = <String, Object?>{'value': decoded};
          }
        } on FormatException {
          args = <String, Object?>{'_raw': rawArgs};
        }
      }
      parts.add(
        Part.fromFunctionCall(
          name: (tcMap['name'] as String?) ?? '',
          args: args,
          id: tcMap['id'] as String?,
        ),
      );
    }
  }

  final Map<String, Object?>? usage = _asStringMap(chatResponse['usage']);
  final String? finishReason = choice['finishReason'] as String?;

  return LlmResponse(
    modelVersion: modelVersion,
    content: Content(role: 'model', parts: parts),
    finishReason: mapOciFinishReason(finishReason),
    usageMetadata: extractOciUsageMetadata(usage),
    turnComplete: true,
  );
}

Map<String, Object?>? _asStringMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
