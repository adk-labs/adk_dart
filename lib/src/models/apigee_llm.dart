/// Apigee-hosted Gemini adapter and protocol selection helpers.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../types/content.dart';
import '../utils/env_utils.dart';
import '../utils/system_environment/system_environment.dart';
import 'google_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

const String _apigeeProxyUrlEnv = 'APIGEE_PROXY_URL';
const String _projectEnv = 'GOOGLE_CLOUD_PROJECT';
const String _locationEnv = 'GOOGLE_CLOUD_LOCATION';
const String _refusalPrefix = '[[REFUSAL]]: ';

/// Apigee backend protocol families supported by this adapter.
enum ApiType {
  unknown('unknown'),
  chatCompletions('chat_completions'),
  genai('genai');

  const ApiType(this.value);

  final String value;

  /// Parses [raw] into an [ApiType], defaulting to [ApiType.unknown].
  static ApiType parse(Object? raw) {
    if (raw == null) {
      return ApiType.unknown;
    }
    if (raw is ApiType) {
      return raw;
    }
    final String value = '$raw'.trim().toLowerCase();
    for (final ApiType type in ApiType.values) {
      if (type.value == value || type.name.toLowerCase() == value) {
        return type;
      }
    }
    return ApiType.unknown;
  }
}

/// Client contract for Apigee chat-completions calls.
abstract class ApigeeCompletionsClient {
  /// Generates content responses using Apigee chat-completions endpoints.
  Stream<LlmResponse> generateContent({
    required LlmRequest request,
    required bool stream,
    required String baseUrl,
    required Map<String, String> headers,
  });
}

/// HTTP exception thrown by [ChatCompletionsHttpClient].
class ChatCompletionsHttpException implements Exception {
  /// Creates an HTTP exception for a chat-completions request.
  ChatCompletionsHttpException(
    this.statusCode,
    this.message, {
    this.responseBody,
  });

  /// HTTP status code returned by the endpoint.
  final int statusCode;

  /// Human-readable error message.
  final String message;

  /// Optional raw response body.
  final String? responseBody;

  @override
  String toString() {
    return 'ChatCompletionsHttpException('
        'statusCode: $statusCode, message: $message)';
  }
}

/// Production HTTP client for OpenAI-compatible chat-completions endpoints.
class ChatCompletionsHttpClient implements ApigeeCompletionsClient {
  /// Creates an HTTP chat-completions client.
  ChatCompletionsHttpClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Stream<LlmResponse> generateContent({
    required LlmRequest request,
    required bool stream,
    required String baseUrl,
    required Map<String, String> headers,
  }) async* {
    final Map<String, Object?> payload = ApigeeLlm.buildChatCompletionsPayload(
      request,
      stream: stream,
    );
    final Uri uri = Uri.parse(baseUrl);
    if (!stream) {
      yield await _postJson(uri: uri, headers: headers, payload: payload);
      return;
    }
    yield* _postSse(uri: uri, headers: headers, payload: payload);
  }

  Future<LlmResponse> _postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> payload,
  }) async {
    final http.Response response = await _httpClient.post(
      uri,
      headers: _buildHeaders(headers),
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 400) {
      throw ChatCompletionsHttpException(
        response.statusCode,
        _extractChatCompletionsError(response.body),
        responseBody: response.body,
      );
    }
    return ApigeeLlm.parseChatCompletionsResponse(
      _decodeChatCompletionsObject(response.body),
    );
  }

  Stream<LlmResponse> _postSse({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> payload,
  }) async* {
    final http.Request request = http.Request('POST', uri)
      ..headers.addAll(_buildHeaders(headers, acceptEventStream: true))
      ..body = jsonEncode(payload);

    final http.StreamedResponse response = await _httpClient.send(request);
    if (response.statusCode >= 400) {
      final String body = await _readStreamedBody(response);
      throw ChatCompletionsHttpException(
        response.statusCode,
        _extractChatCompletionsError(body),
        responseBody: body,
      );
    }

    final _ChatCompletionsChunkCollection collection =
        _ChatCompletionsChunkCollection();
    final StringBuffer dataBuffer = StringBuffer();
    bool firstLine = true;
    final Stream<String> lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final String rawLine in lines) {
      String line = rawLine;
      if (firstLine) {
        line = _stripUtf8Bom(line);
        firstLine = false;
      }
      if (line.isEmpty) {
        final Map<String, Object?>? chunk = _decodeSseChunk(
          dataBuffer.toString(),
        );
        dataBuffer.clear();
        if (chunk != null) {
          for (final LlmResponse item in collection.processChunk(chunk)) {
            yield item;
          }
        }
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      final _SseField? field = _parseSseField(line);
      if (field == null || field.name != 'data') {
        continue;
      }
      dataBuffer.writeln(field.value);
    }

    final Map<String, Object?>? trailing = _decodeSseChunk(
      dataBuffer.toString(),
    );
    if (trailing != null) {
      for (final LlmResponse item in collection.processChunk(trailing)) {
        yield item;
      }
    }
  }

  Map<String, String> _buildHeaders(
    Map<String, String> headers, {
    bool acceptEventStream = false,
  }) {
    final Map<String, String> merged = <String, String>{};
    bool hasAccept = false;
    headers.forEach((String key, String value) {
      final String normalized = key.toLowerCase();
      if (normalized == 'content-type') {
        return;
      }
      if (normalized == 'accept') {
        hasAccept = true;
      }
      merged[key] = value;
    });
    merged['Content-Type'] = 'application/json';
    if (acceptEventStream && !hasAccept) {
      merged['Accept'] = 'text/event-stream';
    }
    return merged;
  }

  Future<String> _readStreamedBody(http.StreamedResponse response) async {
    final List<int> bytes = await response.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _ChatCompletionsChunkCollection {
  final StringBuffer _content = StringBuffer();
  final Map<int, _StreamingToolCall> _toolCalls = <int, _StreamingToolCall>{};
  String _role = 'model';
  String? _model;
  Map<String, Object?>? _usage;
  final Map<String, Object?> _metadata = <String, Object?>{};

  List<LlmResponse> processChunk(Map<String, Object?> chunk) {
    _updateState(chunk);
    final List<Object?> choices =
        (chunk['choices'] as List<Object?>?) ?? const <Object?>[];
    if (choices.isEmpty) {
      if (_usage != null || _metadata.isNotEmpty) {
        return <LlmResponse>[_buildPartialResponse(const <Part>[])];
      }
      return const <LlmResponse>[];
    }

    final Map<String, Object?> choice = _asMap(choices.first);
    final Map<String, Object?> delta = _asMap(choice['delta']);
    final List<Part> chunkParts = _mapDeltaToParts(delta);
    final List<LlmResponse> responses = <LlmResponse>[
      _buildPartialResponse(chunkParts),
    ];

    final String finishReason = '${choice['finish_reason'] ?? ''}';
    if (finishReason.isNotEmpty && finishReason != 'null') {
      responses.add(
        LlmResponse(
          content: Content(role: _role, parts: _finalParts()),
          finishReason: ApigeeLlm._mapFinishReason(finishReason),
          modelVersion: _model,
          usageMetadata: _mapUsage(_usage),
          customMetadata: _customMetadata(),
          turnComplete: true,
        ),
      );
    }
    return responses;
  }

  void _updateState(Map<String, Object?> chunk) {
    final String model = '${chunk['model'] ?? ''}';
    if (model.isNotEmpty) {
      _model = model;
    }
    final Map<String, Object?> usage = _asMap(chunk['usage']);
    if (usage.isNotEmpty) {
      _usage = usage;
    }
    for (final String key in const <String>[
      'id',
      'created',
      'object',
      'system_fingerprint',
      'service_tier',
    ]) {
      final Object? value = chunk[key];
      if (value != null) {
        _metadata[key] = value;
      }
    }
  }

  List<Part> _mapDeltaToParts(Map<String, Object?> delta) {
    final String role = '${delta['role'] ?? ''}';
    if (role.isNotEmpty && role != 'null') {
      _role = role == 'assistant' ? 'model' : role;
    }

    final List<Part> parts = <Part>[];
    final String content = '${delta['content'] ?? ''}';
    if (content.isNotEmpty && content != 'null') {
      _content.write(content);
      parts.add(Part.text(content));
    }
    final String refusal = '${delta['refusal'] ?? ''}'.trim();
    if (refusal.isNotEmpty && refusal != 'null') {
      if (_content.isNotEmpty) {
        _content.write('\n');
      }
      final String markedRefusal = '$_refusalPrefix$refusal';
      _content.write(markedRefusal);
      parts.add(Part.text(markedRefusal));
    }

    final List<Object?> toolCalls =
        (delta['tool_calls'] as List<Object?>?) ?? const <Object?>[];
    for (final Object? item in toolCalls) {
      final Part? part = _upsertToolCall(_asMap(item));
      if (part != null) {
        parts.add(part);
      }
    }
    return parts;
  }

  Part? _upsertToolCall(Map<String, Object?> toolCall) {
    final int index = _readIndex(toolCall['index']) ?? _toolCalls.length;
    final _StreamingToolCall state = _toolCalls.putIfAbsent(
      index,
      _StreamingToolCall.new,
    );
    final String id = '${toolCall['id'] ?? ''}';
    if (id.isNotEmpty && id != 'null') {
      state.id = id;
    }
    final Map<String, Object?> function = _asMap(toolCall['function']);
    final String name = '${function['name'] ?? ''}';
    if (name.isNotEmpty && name != 'null') {
      state.name = name;
    }
    final String arguments = '${function['arguments'] ?? ''}';
    if (arguments.isNotEmpty && arguments != 'null') {
      state.arguments.write(arguments);
    }
    if ((state.name ?? '').isEmpty && (state.id ?? '').isEmpty) {
      return null;
    }
    return Part.fromFunctionCall(
      name: state.name ?? '',
      id: state.id,
      partialArgs: arguments.isEmpty || arguments == 'null'
          ? null
          : <Map<String, Object?>>[
              <String, Object?>{'arguments': arguments},
            ],
      willContinue: true,
    );
  }

  List<Part> _finalParts() {
    final List<Part> parts = <Part>[];
    if (_content.isNotEmpty) {
      parts.add(Part.text(_content.toString()));
    }
    final List<int> sortedIndexes = _toolCalls.keys.toList()..sort();
    for (final int index in sortedIndexes) {
      final _StreamingToolCall state = _toolCalls[index]!;
      parts.add(
        Part.fromFunctionCall(
          name: state.name ?? '',
          id: state.id,
          args: _decodeArguments(state.arguments.toString()),
        ),
      );
    }
    return parts;
  }

  LlmResponse _buildPartialResponse(List<Part> parts) {
    return LlmResponse(
      content: Content(role: _role, parts: parts),
      partial: true,
      modelVersion: _model,
      usageMetadata: _mapUsage(_usage),
      customMetadata: _customMetadata(),
    );
  }

  Map<String, dynamic>? _customMetadata() {
    if (_metadata.isEmpty) {
      return null;
    }
    return Map<String, dynamic>.from(_metadata);
  }
}

class _StreamingToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

/// Apigee model adapter that supports both GenAI and chat-completions flows.
class ApigeeLlm extends Gemini {
  /// Creates an Apigee adapter for [model].
  ApigeeLlm({
    required String model,
    this.proxyUrl,
    Map<String, String>? customHeaders,
    Object? apiType = ApiType.unknown,
    Map<String, String>? environment,
    this.completionsClient,
    super.retryOptions,
    super.generateHook,
  }) : customHeaders = customHeaders ?? <String, String>{},
       _apiType = ApiType.parse(apiType),
       super(model: model, environment: environment) {
    if (!validateModelString(model)) {
      throw ArgumentError('Invalid model string: $model');
    }
    _resolvedApiType = _resolveApiType(model: model, configured: _apiType);
    _isVertexAi = identifyVertexAi(
      model: model,
      apiType: _resolvedApiType,
      environment: environment,
    );
    _apiVersion = identifyApiVersion(model);

    final Map<String, String> env = this.environment ?? _safeEnvironment;
    if (_isVertexAi) {
      _project = env[_projectEnv];
      _location = env[_locationEnv];
      if ((_project ?? '').isEmpty) {
        throw ArgumentError(
          'The $_projectEnv environment variable must be set.',
        );
      }
      if ((_location ?? '').isEmpty) {
        throw ArgumentError(
          'The $_locationEnv environment variable must be set.',
        );
      }
    }
  }

  /// Optional explicit Apigee proxy URL.
  final String? proxyUrl;

  /// Custom headers forwarded to Apigee chat-completions calls.
  final Map<String, String> customHeaders;

  /// Optional custom completions client override.
  final ApigeeCompletionsClient? completionsClient;
  final ApiType _apiType;

  late final ApiType _resolvedApiType;
  late final bool _isVertexAi;
  late final String _apiVersion;
  String? _project;
  String? _location;

  /// Resolved API type used for this adapter instance.
  ApiType get resolvedApiType => _resolvedApiType;

  /// Whether this adapter targets Vertex AI routing.
  bool get isVertexAi => _isVertexAi;

  /// Resolved API version segment extracted from the model path.
  String get apiVersion => _apiVersion;

  /// Vertex project resolved from environment when using Vertex AI mode.
  String? get project => _project;

  /// Vertex location resolved from environment when using Vertex AI mode.
  String? get location => _location;

  /// Regex patterns supported by this adapter.
  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'apigee\/.*')];
  }

  /// Generates responses using Apigee routing and selected API mode.
  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model = getModelId(prepared.model ?? model);

    if (resolvedApiType == ApiType.chatCompletions) {
      final String? configuredBaseUrl =
          proxyUrl ?? (environment ?? _safeEnvironment)[_apigeeProxyUrlEnv];
      if (configuredBaseUrl == null || configuredBaseUrl.isEmpty) {
        throw ArgumentError('Apigee proxy URL is not configured.');
      }

      yield* (completionsClient ?? ChatCompletionsHttpClient()).generateContent(
        request: prepared,
        stream: stream,
        baseUrl: configuredBaseUrl,
        headers: Map<String, String>.from(customHeaders),
      );
      return;
    }

    yield* super.generateContent(prepared, stream: stream);
  }

  /// Resolves the effective API type for [model] and [configured] value.
  static ApiType _resolveApiType({
    required String model,
    required ApiType configured,
  }) {
    if (configured != ApiType.unknown) {
      return configured;
    }
    if (model.startsWith('apigee/openai/')) {
      return ApiType.chatCompletions;
    }
    if (model.startsWith('apigee/gemini/') ||
        model.startsWith('apigee/vertex_ai/')) {
      return ApiType.genai;
    }
    return ApiType.genai;
  }

  /// Whether [model] should run through Vertex AI endpoints.
  static bool identifyVertexAi({
    required String model,
    required ApiType apiType,
    Map<String, String>? environment,
  }) {
    if (apiType != ApiType.genai && apiType != ApiType.unknown) {
      return false;
    }
    if (model.startsWith('apigee/gemini/') ||
        model.startsWith('apigee/openai/')) {
      return false;
    }
    return model.startsWith('apigee/vertex_ai/') ||
        isEnvEnabled('GOOGLE_GENAI_USE_VERTEXAI', environment: environment);
  }

  /// Extracts API version from [model] when present.
  static String identifyApiVersion(String model) {
    final String normalized = model.replaceFirst(RegExp(r'^apigee/'), '');
    final List<String> segments = normalized.split('/');
    if (segments.length == 3) {
      return segments[1];
    }
    if (segments.length == 2 &&
        !_isKnownProvider(segments.first) &&
        segments.first.startsWith('v')) {
      return segments.first;
    }
    return '';
  }

  /// Extracts the provider model identifier from an Apigee model path.
  static String getModelId(String model) {
    final String normalized = model.replaceFirst(RegExp(r'^apigee/'), '');
    final List<String> segments = normalized.split('/');
    return segments.isEmpty ? model : segments.last;
  }

  /// Whether [model] matches the supported Apigee model path formats.
  static bool validateModelString(String model) {
    if (!model.startsWith('apigee/')) {
      return false;
    }
    final String normalized = model.replaceFirst(RegExp(r'^apigee/'), '');
    if (normalized.isEmpty) {
      return false;
    }
    final List<String> segments = normalized.split('/');
    if (segments.length > 3) {
      return false;
    }
    if (segments.length == 1) {
      return true;
    }
    if (segments.length == 2) {
      return _isKnownProvider(segments.first) || segments.first.startsWith('v');
    }
    return _isKnownProvider(segments[0]) && segments[1].startsWith('v');
  }

  /// Builds an OpenAI-style chat-completions payload from [request].
  static Map<String, Object?> buildChatCompletionsPayload(
    LlmRequest request, {
    required bool stream,
  }) {
    final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
    final String? systemInstruction = request.config.systemInstruction;
    if (systemInstruction != null && systemInstruction.isNotEmpty) {
      messages.add(<String, Object?>{
        'role': 'system',
        'content': systemInstruction,
      });
    }

    for (final Content content in request.contents) {
      messages.addAll(_contentToMessages(content));
    }

    final Map<String, Object?> payload = <String, Object?>{
      'model': getModelId(request.model ?? ''),
      'messages': messages,
      'stream': stream,
    };

    if (request.config.temperature != null) {
      payload['temperature'] = request.config.temperature;
    }
    if (request.config.topP != null) {
      payload['top_p'] = request.config.topP;
    }
    if (request.config.maxOutputTokens != null) {
      payload['max_tokens'] = request.config.maxOutputTokens;
    }
    if (request.config.stopSequences.isNotEmpty) {
      payload['stop'] = request.config.stopSequences;
    }
    if (request.config.frequencyPenalty != null) {
      payload['frequency_penalty'] = request.config.frequencyPenalty;
    }
    if (request.config.presencePenalty != null) {
      payload['presence_penalty'] = request.config.presencePenalty;
    }
    if (request.config.seed != null) {
      payload['seed'] = request.config.seed;
    }
    if (request.config.candidateCount != null) {
      payload['n'] = request.config.candidateCount;
    }
    if (request.config.responseLogprobs == true) {
      payload['logprobs'] = true;
      if (request.config.logprobs != null) {
        payload['top_logprobs'] = request.config.logprobs;
      }
    }
    if (request.config.responseJsonSchema != null) {
      payload['response_format'] = <String, Object?>{
        'type': 'json_schema',
        'json_schema': request.config.responseJsonSchema!,
      };
    } else if (request.config.responseMimeType == 'application/json') {
      payload['response_format'] = const <String, Object?>{
        'type': 'json_object',
      };
    }

    final List<Map<String, Object?>> tools = _mapTools(request.config);
    if (tools.isNotEmpty) {
      payload['tools'] = tools;
      final LlmToolConfig? toolConfig = request.config.toolConfig;
      final FunctionCallingConfigMode? mode =
          toolConfig?.functionCallingConfig?.mode;
      if (mode == FunctionCallingConfigMode.any) {
        payload['tool_choice'] = 'required';
      } else if (mode == FunctionCallingConfigMode.none) {
        payload['tool_choice'] = 'none';
      } else if (mode == FunctionCallingConfigMode.auto) {
        payload['tool_choice'] = 'auto';
      }
    }

    return payload;
  }

  /// Parses an Apigee chat-completions response into [LlmResponse].
  static LlmResponse parseChatCompletionsResponse(
    Map<String, Object?> response,
  ) {
    final List<Object?> choices =
        (response['choices'] as List<Object?>?) ?? <Object?>[];
    if (choices.isEmpty) {
      return LlmResponse();
    }
    final Map<String, Object?> first = _asMap(choices.first);
    final Map<String, Object?> message = _asMap(first['message']);
    final String role = message['role'] == 'assistant'
        ? 'model'
        : '${message['role'] ?? 'model'}';

    final List<Part> parts = <Part>[];
    final Object? contentRaw = message['content'];
    if (contentRaw is String && contentRaw.isNotEmpty) {
      parts.add(Part.text(contentRaw));
    }
    final String refusal = '${message['refusal'] ?? ''}'.trim();
    if (refusal.isNotEmpty) {
      final String merged = parts.isEmpty
          ? '$_refusalPrefix$refusal'
          : '${parts.removeLast().text}\n$_refusalPrefix$refusal';
      parts.add(Part.text(merged));
    }

    final List<Object?> toolCalls =
        (message['tool_calls'] as List<Object?>?) ?? <Object?>[];
    for (final Object? call in toolCalls) {
      final Map<String, Object?> callMap = _asMap(call);
      final Map<String, Object?> function = _asMap(callMap['function']);
      parts.add(_parseFunctionCall(function, id: callMap['id']));
    }
    final Map<String, Object?> functionCall = _asMap(message['function_call']);
    if (functionCall.isNotEmpty) {
      parts.add(_parseFunctionCall(functionCall));
    }

    final Map<String, Object?> usage = _asMap(response['usage']);
    final Map<String, Object?> completionTokenDetails = _asMap(
      usage['completion_tokens_details'],
    );
    final Object? reasoningTokens = completionTokenDetails['reasoning_tokens'];
    final Map<String, Object?> usageMetadata = <String, Object?>{
      'prompt_token_count': usage['prompt_tokens'] ?? 0,
      'candidates_token_count': usage['completion_tokens'] ?? 0,
      'total_token_count': usage['total_tokens'] ?? 0,
      if (reasoningTokens != null && reasoningTokens != 0)
        'thoughts_token_count': reasoningTokens,
    };

    return LlmResponse(
      modelVersion: response['model'] as String?,
      content: Content(role: role, parts: parts),
      usageMetadata: usageMetadata,
      finishReason: _mapFinishReason(first['finish_reason'] as String?),
      customMetadata: <String, dynamic>{
        'id': response['id'],
        'created': response['created'],
        'system_fingerprint': response['system_fingerprint'],
        'service_tier': response['service_tier'],
      }..removeWhere((Object? key, Object? value) => value == null),
    );
  }

  static List<Map<String, Object?>> _contentToMessages(Content content) {
    final String role = content.role == 'model'
        ? 'assistant'
        : '${content.role}';
    final List<Map<String, Object?>> toolResponses = <Map<String, Object?>>[];
    final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
    final List<Map<String, Object?>> contentParts = <Map<String, Object?>>[];
    final List<String> refusals = <String>[];

    for (final Part part in content.parts) {
      if (part.functionResponse != null) {
        toolResponses.add(<String, Object?>{
          'role': 'tool',
          'tool_call_id': part.functionResponse!.id,
          'content': jsonEncode(part.functionResponse!.response),
        });
        continue;
      }
      if (part.functionCall != null) {
        toolCalls.add(<String, Object?>{
          'id': part.functionCall!.id ?? 'call_${part.functionCall!.name}',
          'type': 'function',
          'function': <String, Object?>{
            'name': part.functionCall!.name,
            'arguments': jsonEncode(part.functionCall!.args),
          },
        });
        continue;
      }
      if (part.text != null && part.text!.isNotEmpty) {
        final ({String? content, String? refusal}) split = _splitRefusalText(
          part.text!,
        );
        if (split.content case final String text when text.isNotEmpty) {
          contentParts.add(<String, Object?>{'type': 'text', 'text': text});
        }
        if (split.refusal case final String refusalText
            when refusalText.isNotEmpty) {
          refusals.add(refusalText);
        }
        continue;
      }
      if (part.inlineData != null) {
        final String encoded = base64Encode(part.inlineData!.data);
        contentParts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': 'data:${part.inlineData!.mimeType};base64,$encoded',
          },
        });
      } else if (part.fileData != null && part.fileData!.fileUri.isNotEmpty) {
        contentParts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': part.fileData!.fileUri},
        });
      }
    }

    if (toolResponses.isNotEmpty) {
      return toolResponses;
    }

    final Map<String, Object?> message = <String, Object?>{'role': role};
    if (refusals.isNotEmpty) {
      message['refusal'] = refusals.join('\n');
    }
    if (toolCalls.isNotEmpty) {
      message['tool_calls'] = toolCalls;
      if (contentParts.isEmpty) {
        message['content'] = null;
      }
    }
    if (contentParts.isNotEmpty) {
      if (contentParts.length == 1 && contentParts.first['type'] == 'text') {
        message['content'] = contentParts.first['text'];
      } else {
        message['content'] = contentParts;
      }
    }
    return <Map<String, Object?>>[message];
  }

  static List<Map<String, Object?>> _mapTools(GenerateContentConfig config) {
    final List<Map<String, Object?>> tools = <Map<String, Object?>>[];
    final List<ToolDeclaration>? declarations = config.tools;
    if (declarations == null) {
      return tools;
    }
    for (final ToolDeclaration tool in declarations) {
      for (final FunctionDeclaration function in tool.functionDeclarations) {
        tools.add(<String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': function.name,
            'description': function.description,
            'parameters': function.parameters,
          },
        });
      }
    }
    return tools;
  }

  static Part _parseFunctionCall(Map<String, Object?> function, {Object? id}) {
    final String name = '${function['name'] ?? ''}';
    final String argumentsRaw = '${function['arguments'] ?? '{}'}';
    Map<String, dynamic> arguments = <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(argumentsRaw);
      if (decoded is Map) {
        arguments = decoded.cast<String, dynamic>();
      }
    } catch (_) {
      arguments = <String, dynamic>{};
    }
    final String? callId = id == null ? null : '$id';
    return Part.fromFunctionCall(name: name, args: arguments, id: callId);
  }

  static String _mapFinishReason(String? reason) {
    if (reason == 'stop' || reason == 'tool_calls') {
      return 'STOP';
    }
    if (reason == 'length') {
      return 'MAX_TOKENS';
    }
    if (reason == 'content_filter') {
      return 'SAFETY';
    }
    return 'FINISH_REASON_UNSPECIFIED';
  }

  static ({String? content, String? refusal}) _splitRefusalText(String text) {
    if (text.startsWith(_refusalPrefix)) {
      return (content: null, refusal: text.substring(_refusalPrefix.length));
    }

    final String separator = '\n$_refusalPrefix';
    final int index = text.indexOf(separator);
    if (index < 0) {
      return (content: text, refusal: null);
    }

    final String content = text.substring(0, index);
    final String refusal = text.substring(index + separator.length);
    return (
      content: content.isEmpty ? null : content,
      refusal: refusal.isEmpty ? null : refusal,
    );
  }
}

bool _isKnownProvider(String value) {
  return value == 'vertex_ai' || value == 'gemini' || value == 'openai';
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, Object?> _decodeChatCompletionsObject(String body) {
  final String normalized = body.trim();
  if (normalized.isEmpty) {
    throw ChatCompletionsHttpException(
      500,
      'Chat completions response body is empty.',
      responseBody: body,
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(normalized);
  } on FormatException {
    throw ChatCompletionsHttpException(
      500,
      'Chat completions response is not valid JSON.',
      responseBody: body,
    );
  }
  if (decoded is! Map) {
    throw ChatCompletionsHttpException(
      500,
      'Chat completions response is not a JSON object.',
      responseBody: body,
    );
  }
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
}

String _extractChatCompletionsError(String body) {
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is Map) {
      final Object? error = decoded['error'];
      if (error is Map) {
        final Object? message = error['message'];
        if (message != null && '$message'.trim().isNotEmpty) {
          return '$message';
        }
      }
      if (error != null && '$error'.trim().isNotEmpty) {
        return '$error';
      }
    }
  } catch (_) {
    // Fall back to the raw body.
  }
  final String trimmed = body.trim();
  return trimmed.isEmpty ? 'Chat completions request failed.' : trimmed;
}

Map<String, Object?>? _decodeSseChunk(String rawData) {
  final String data = rawData.trim();
  if (data.isEmpty || data == '[DONE]') {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(data);
    if (decoded is Map) {
      return decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    }
  } catch (_) {
    // Java parity: malformed streaming chunks are ignored.
  }
  return null;
}

_SseField? _parseSseField(String line) {
  final int separatorIndex = line.indexOf(':');
  if (separatorIndex < 0) {
    return _SseField(name: line, value: '');
  }
  final String name = line.substring(0, separatorIndex);
  if (name.isEmpty) {
    return null;
  }
  String value = line.substring(separatorIndex + 1);
  if (value.startsWith(' ')) {
    value = value.substring(1);
  }
  return _SseField(name: name, value: value);
}

class _SseField {
  _SseField({required this.name, required this.value});

  final String name;
  final String value;
}

String _stripUtf8Bom(String value) {
  if (value.startsWith('\ufeff')) {
    return value.substring(1);
  }
  return value;
}

int? _readIndex(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('${value ?? ''}');
}

Map<String, dynamic> _decodeArguments(String raw) {
  if (raw.trim().isEmpty) {
    return <String, dynamic>{};
  }
  try {
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  } catch (_) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{};
}

Map<String, Object?>? _mapUsage(Map<String, Object?>? usage) {
  if (usage == null || usage.isEmpty) {
    return null;
  }
  final Map<String, Object?> completionTokenDetails = _asMap(
    usage['completion_tokens_details'],
  );
  final Object? reasoningTokens = completionTokenDetails['reasoning_tokens'];
  return <String, Object?>{
    'prompt_token_count': usage['prompt_tokens'] ?? 0,
    'candidates_token_count': usage['completion_tokens'] ?? 0,
    'total_token_count': usage['total_tokens'] ?? 0,
    if (reasoningTokens != null && reasoningTokens != 0)
      'thoughts_token_count': reasoningTokens,
  };
}

Map<String, String> get _safeEnvironment {
  try {
    return readSystemEnvironment();
  } catch (_) {
    return <String, String>{};
  }
}
