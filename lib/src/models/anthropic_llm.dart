/// Anthropic Claude model adapter integration.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../tools/base_tool.dart';
import '../types/content.dart';
import '../utils/system_environment/system_environment.dart';
import '../version.dart';
import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

const String _anthropicApiKeyEnv = 'ANTHROPIC_API_KEY';
const String _anthropicBaseUrlEnv = 'ANTHROPIC_BASE_URL';
const String _anthropicVersionEnv = 'ANTHROPIC_VERSION';
const String _defaultAnthropicBaseUrl = 'https://api.anthropic.com/v1';
const String _defaultAnthropicVersion = '2023-06-01';
const String _outputSchemaToolName = 'structured_output';
const String _outputSchemaToolDescription =
    'Provide your final answer. Call this tool exactly once, with your whole '
    'answer in the structure its input describes.';
const String _outputSchemaValueKey = 'response';
const Set<String> _validAnthropicEfforts = <String>{
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
};

/// Specialized generation configuration for Anthropic Claude models.
class AnthropicGenerateContentConfig extends GenerateContentConfig {
  /// Creates an Anthropic generation configuration.
  AnthropicGenerateContentConfig({
    this.effort,
    super.tools,
    super.systemInstruction,
    super.temperature,
    super.topP,
    super.topK,
    super.maxOutputTokens,
    super.stopSequences,
    super.frequencyPenalty,
    super.presencePenalty,
    super.seed,
    super.candidateCount,
    super.responseLogprobs,
    super.logprobs,
    super.thinkingConfig,
    super.responseSchema,
    super.responseJsonSchema,
    super.responseMimeType,
    super.toolConfig,
    super.automaticFunctionCalling,
    super.cachedContent,
    super.httpOptions,
    super.labels,
  }) {
    if (effort != null && !_validAnthropicEfforts.contains(effort)) {
      throw ArgumentError.value(
        effort,
        'effort',
        'Must be one of ${_validAnthropicEfforts.join(", ")}.',
      );
    }
    if (_thinkingLevelValue(thinkingConfig) != null) {
      throw ArgumentError(
        'thinking_level is not supported in AnthropicGenerateContentConfig. '
        'Use the `effort` field directly to configure reasoning effort.',
      );
    }
  }

  /// Reasoning effort level for adaptive extended thinking (`low`, `medium`,
  /// `high`, `xhigh`, `max`).
  String? effort;

  @override
  AnthropicGenerateContentConfig copyWith({
    Object? effort = _configSentinel,
    Object? tools = _configSentinel,
    Object? systemInstruction = _configSentinel,
    Object? temperature = _configSentinel,
    Object? topP = _configSentinel,
    Object? topK = _configSentinel,
    Object? maxOutputTokens = _configSentinel,
    List<String>? stopSequences,
    Object? frequencyPenalty = _configSentinel,
    Object? presencePenalty = _configSentinel,
    Object? seed = _configSentinel,
    Object? candidateCount = _configSentinel,
    Object? responseLogprobs = _configSentinel,
    Object? logprobs = _configSentinel,
    Object? thinkingConfig = _configSentinel,
    Object? responseSchema = _configSentinel,
    Object? responseJsonSchema = _configSentinel,
    Object? responseMimeType = _configSentinel,
    Object? responseModalities = _configSentinel,
    Object? speechConfig = _configSentinel,
    Object? toolConfig = _configSentinel,
    Object? automaticFunctionCalling = _configSentinel,
    Object? cachedContent = _configSentinel,
    Object? httpOptions = _configSentinel,
    Map<String, String>? labels,
  }) {
    final GenerateContentConfig base = super.copyWith(
      tools: identical(tools, _configSentinel) ? this.tools : tools,
      systemInstruction: identical(systemInstruction, _configSentinel)
          ? this.systemInstruction
          : systemInstruction,
      temperature: identical(temperature, _configSentinel)
          ? this.temperature
          : temperature,
      topP: identical(topP, _configSentinel) ? this.topP : topP,
      topK: identical(topK, _configSentinel) ? this.topK : topK,
      maxOutputTokens: identical(maxOutputTokens, _configSentinel)
          ? this.maxOutputTokens
          : maxOutputTokens,
      stopSequences: stopSequences,
      frequencyPenalty: identical(frequencyPenalty, _configSentinel)
          ? this.frequencyPenalty
          : frequencyPenalty,
      presencePenalty: identical(presencePenalty, _configSentinel)
          ? this.presencePenalty
          : presencePenalty,
      seed: identical(seed, _configSentinel) ? this.seed : seed,
      candidateCount: identical(candidateCount, _configSentinel)
          ? this.candidateCount
          : candidateCount,
      responseLogprobs: identical(responseLogprobs, _configSentinel)
          ? this.responseLogprobs
          : responseLogprobs,
      logprobs: identical(logprobs, _configSentinel) ? this.logprobs : logprobs,
      thinkingConfig: identical(thinkingConfig, _configSentinel)
          ? this.thinkingConfig
          : thinkingConfig,
      responseSchema: identical(responseSchema, _configSentinel)
          ? this.responseSchema
          : responseSchema,
      responseJsonSchema: identical(responseJsonSchema, _configSentinel)
          ? this.responseJsonSchema
          : responseJsonSchema,
      responseMimeType: identical(responseMimeType, _configSentinel)
          ? this.responseMimeType
          : responseMimeType,
      responseModalities: identical(responseModalities, _configSentinel)
          ? this.responseModalities
          : responseModalities,
      speechConfig: identical(speechConfig, _configSentinel)
          ? this.speechConfig
          : speechConfig,
      toolConfig: identical(toolConfig, _configSentinel)
          ? this.toolConfig
          : toolConfig,
      automaticFunctionCalling:
          identical(automaticFunctionCalling, _configSentinel)
          ? this.automaticFunctionCalling
          : automaticFunctionCalling,
      cachedContent: identical(cachedContent, _configSentinel)
          ? this.cachedContent
          : cachedContent,
      httpOptions: identical(httpOptions, _configSentinel)
          ? this.httpOptions
          : httpOptions,
      labels: labels,
    );
    return AnthropicGenerateContentConfig(
      effort: identical(effort, _configSentinel)
          ? this.effort
          : effort as String?,
      tools: base.tools,
      systemInstruction: base.systemInstruction,
      temperature: base.temperature,
      topP: base.topP,
      topK: base.topK,
      maxOutputTokens: base.maxOutputTokens,
      stopSequences: base.stopSequences,
      frequencyPenalty: base.frequencyPenalty,
      presencePenalty: base.presencePenalty,
      seed: base.seed,
      candidateCount: base.candidateCount,
      responseLogprobs: base.responseLogprobs,
      logprobs: base.logprobs,
      thinkingConfig: base.thinkingConfig,
      responseSchema: base.responseSchema,
      responseJsonSchema: base.responseJsonSchema,
      responseMimeType: base.responseMimeType,
      toolConfig: base.toolConfig,
      automaticFunctionCalling: base.automaticFunctionCalling,
      cachedContent: base.cachedContent,
      httpOptions: base.httpOptions,
      labels: base.labels,
    );
  }
}

const Object _configSentinel = Object();

class _OutputSchemaTool {
  const _OutputSchemaTool({required this.param, required this.nestsValue});

  final Map<String, Object?> param;
  final bool nestsValue;

  factory _OutputSchemaTool.forSchema(Object responseSchema) {
    Map<String, Object?> inputSchema = _schemaToMap(responseSchema);
    _updateTypeStrings(inputSchema);

    final bool nestsValue = inputSchema['type'] != 'object';
    if (nestsValue) {
      final Object? defs = inputSchema.remove(r'$defs');
      inputSchema = <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{_outputSchemaValueKey: inputSchema},
        'required': <String>[_outputSchemaValueKey],
        r'$defs': ?defs,
      };
    }

    return _OutputSchemaTool(
      param: <String, Object?>{
        'name': _outputSchemaToolName,
        'description': _outputSchemaToolDescription,
        'input_schema': inputSchema,
      },
      nestsValue: nestsValue,
    );
  }

  Map<String, Object?> choice({required bool thinkingEnabled}) {
    if (thinkingEnabled) {
      return <String, Object?>{
        'type': 'auto',
        'disable_parallel_tool_use': true,
      };
    }
    return <String, Object?>{
      'type': 'tool',
      'name': _outputSchemaToolName,
      'disable_parallel_tool_use': true,
    };
  }

  String toText(Map<String, dynamic> args) {
    final Object? value = nestsValue ? args[_outputSchemaValueKey] : args;
    return jsonEncode(value);
  }

  LlmResponse unwrap(LlmResponse response) {
    final Content? content = response.content;
    if (content == null || content.parts.isEmpty) {
      return response;
    }
    FunctionCall? call;
    for (final Part part in content.parts) {
      if (part.functionCall != null &&
          part.functionCall!.name == _outputSchemaToolName) {
        call = part.functionCall;
        break;
      }
    }
    if (call == null) {
      return response;
    }
    final List<Part> parts = <Part>[
      for (final Part part in content.parts)
        if (part.thought) part,
      Part.text(toText(call.args)),
    ];
    content.parts = parts;
    return response;
  }
}

Map<String, Object?> _schemaToMap(Object schema) {
  if (schema is Map) {
    return _deepCopyJsonMap(schema.cast<String, Object?>());
  }
  try {
    final dynamic dynamicSchema = schema;
    final Object? json = dynamicSchema.toJson();
    if (json is Map) {
      return _deepCopyJsonMap(json.cast<String, Object?>());
    }
  } catch (_) {
    // Fall through.
  }
  return <String, Object?>{'type': 'object', 'properties': <String, Object?>{}};
}

/// Callback that invokes Anthropic message APIs and returns raw responses.
typedef AnthropicApiInvoker =
    Future<List<Map<String, Object?>>> Function({
      required Map<String, Object?> request,
      required bool stream,
    });

/// Callback that streams raw Anthropic SSE event payloads.
typedef AnthropicStreamInvoker =
    Stream<Map<String, Object?>> Function({
      required Map<String, Object?> request,
    });

/// Hook for overriding Anthropic generation behavior.
typedef AnthropicGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);

/// Transport abstraction for Anthropic Messages API calls.
abstract class AnthropicRestTransport {
  /// Executes a non-streaming messages request.
  Future<Map<String, Object?>> createMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  });

  /// Executes a streaming messages request.
  Stream<Map<String, Object?>> streamMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  });
}

/// Anthropic API exception with HTTP and body context.
class AnthropicApiException implements Exception {
  /// Creates an Anthropic API exception.
  AnthropicApiException(this.statusCode, this.message, {this.responseBody});

  /// HTTP status code.
  final int statusCode;

  /// Human-readable error message.
  final String message;

  /// Raw response body if available.
  final String? responseBody;

  @override
  String toString() {
    return 'AnthropicApiException($statusCode): $message';
  }
}

/// Default HTTP-backed transport for the Anthropic Messages API.
class AnthropicRestHttpTransport implements AnthropicRestTransport {
  /// Creates an HTTP transport.
  AnthropicRestHttpTransport({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _ownsHttpClient = httpClient == null;

  final http.Client _httpClient;
  final bool _ownsHttpClient;

  @override
  Future<Map<String, Object?>> createMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async {
    final Uri uri = Uri.parse(_messagesEndpoint(baseUrl));
    final http.Response response = await _httpClient.post(
      uri,
      headers: _buildHeaders(
        apiKey: apiKey,
        apiVersion: apiVersion,
        headers: headers,
      ),
      body: jsonEncode(request),
    );
    if (response.statusCode >= 400) {
      throw AnthropicApiException(
        response.statusCode,
        _extractErrorMessage(response.body),
        responseBody: response.body,
      );
    }
    return _decodeJsonObject(response.body);
  }

  @override
  Stream<Map<String, Object?>> streamMessage({
    required Map<String, Object?> request,
    required String apiKey,
    required String baseUrl,
    required String apiVersion,
    required Map<String, String> headers,
  }) async* {
    final http.Request httpRequest =
        http.Request('POST', Uri.parse(_messagesEndpoint(baseUrl)))
          ..headers.addAll(
            _buildHeaders(
              apiKey: apiKey,
              apiVersion: apiVersion,
              headers: headers,
            ),
          )
          ..body = jsonEncode(request);

    final http.StreamedResponse response = await _httpClient.send(httpRequest);
    if (response.statusCode >= 400) {
      final String body = await _readStreamedBody(response);
      throw AnthropicApiException(
        response.statusCode,
        _extractErrorMessage(body),
        responseBody: body,
      );
    }

    final StringBuffer dataBuffer = StringBuffer();
    bool sawRecognizedSseField = false;
    bool sawUnexpectedContent = false;
    bool emittedChunks = false;
    bool isFirstLine = true;
    final StringBuffer unexpectedPreview = StringBuffer();
    final Stream<String> lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final String rawLine in lines) {
      String line = rawLine;
      if (isFirstLine) {
        line = _stripUtf8Bom(line);
        isFirstLine = false;
      }

      if (line.isEmpty) {
        final Map<String, Object?>? parsed = _decodeSseData(
          dataBuffer.toString(),
        );
        dataBuffer.clear();
        if (parsed != null) {
          emittedChunks = true;
          yield parsed;
        }
        continue;
      }

      if (line.startsWith(':')) {
        continue;
      }

      final _SseField? field = _parseSseField(line);
      if (field == null) {
        sawUnexpectedContent = true;
        _appendSseUnexpectedLine(unexpectedPreview, line);
        continue;
      }

      switch (field.name) {
        case 'event':
        case 'id':
        case 'retry':
          sawRecognizedSseField = true;
          break;
        case 'data':
          sawRecognizedSseField = true;
          dataBuffer.writeln(field.value);
          break;
        default:
          sawUnexpectedContent = true;
          _appendSseUnexpectedLine(unexpectedPreview, line);
          break;
      }
    }

    final Map<String, Object?>? parsed = _decodeSseData(dataBuffer.toString());
    if (parsed != null) {
      emittedChunks = true;
      yield parsed;
    }

    if (!emittedChunks && sawUnexpectedContent && !sawRecognizedSseField) {
      throw AnthropicApiException(
        500,
        'Anthropic SSE response is not a valid event stream.',
        responseBody: unexpectedPreview.toString().trimRight(),
      );
    }
  }

  Future<String> _readStreamedBody(http.StreamedResponse response) async {
    final List<int> bytes = await response.stream.toBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  Map<String, String> _buildHeaders({
    required String apiKey,
    required String apiVersion,
    required Map<String, String> headers,
  }) {
    return <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json, text/event-stream',
      'anthropic-version': apiVersion,
      'x-api-key': apiKey,
      'user-agent': 'adk-dart/$adkVersion',
      ...headers,
    };
  }

  String _messagesEndpoint(String baseUrl) {
    final String normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$normalized/messages';
  }

  /// Closes the owned HTTP client.
  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}

class _AnthropicToolUseAccumulator {
  _AnthropicToolUseAccumulator({required this.id, required this.name});

  final String id;
  final String name;
  String argsJson = '';
}

class _AnthropicThinkingAccumulator {
  _AnthropicThinkingAccumulator({String? text, this.signature})
    : text = StringBuffer(text ?? '');

  final StringBuffer text;
  String? signature;
}

class _AnthropicRedactedThinkingAccumulator {
  _AnthropicRedactedThinkingAccumulator({this.data});

  String? data;
}

class _ToolUseIdSanitizer {
  final Map<String, String> _mapping = <String, String>{};
  int _nextFallback = 0;

  static final RegExp _validToolUseId = RegExp(r'^[a-zA-Z0-9_-]+$');

  String sanitize(String? toolId) {
    if (toolId != null &&
        toolId.isNotEmpty &&
        _validToolUseId.hasMatch(toolId)) {
      return toolId;
    }
    final String key = toolId ?? '';
    return _mapping.putIfAbsent(key, () {
      final String fallback = 'toolu_fallback_$_nextFallback';
      _nextFallback += 1;
      return fallback;
    });
  }
}

/// Anthropic Claude adapter for ADK model requests.
///
/// ```dart
/// final model = AnthropicLlm(
///   model: 'claude-3-5-sonnet-20241022',
///   maxTokens: 4096,
/// );
/// final agent = LlmAgent(
///   name: 'claude_assistant',
///   model: model,
///   instruction: 'Answer concisely.',
/// );
/// ```
class AnthropicLlm extends BaseLlm {
  /// Creates an Anthropic adapter for [model].
  AnthropicLlm({
    super.model = 'claude-3-5-sonnet-20241022',
    this.maxTokens = 8192,
    this.apiInvoker,
    this.streamInvoker,
    this.environment,
    this.baseUrl,
    this.apiVersion,
    AnthropicRestTransport? restTransport,
    AnthropicGenerateHook? generateHook,
  }) : _generateHook = generateHook,
       _restTransport = restTransport;

  /// Max tokens requested for each Anthropic completion.
  final int maxTokens;

  /// Optional API invoker used for integration tests and custom transports.
  final AnthropicApiInvoker? apiInvoker;

  /// Optional stream invoker for custom SSE event streams.
  final AnthropicStreamInvoker? streamInvoker;

  /// Optional environment variable map used to resolve API keys and endpoints.
  final Map<String, String>? environment;

  /// Optional base URL override for the Anthropic Messages API.
  final String? baseUrl;

  /// Optional `anthropic-version` header override.
  final String? apiVersion;
  final AnthropicGenerateHook? _generateHook;
  final AnthropicRestTransport? _restTransport;

  late final AnthropicRestTransport _defaultRestTransport =
      AnthropicRestHttpTransport();

  AnthropicRestTransport get _resolvedRestTransport =>
      _restTransport ?? _defaultRestTransport;

  /// Regex patterns supported by this adapter.
  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'claude-.*'), RegExp(r'anthropic\/.*')];
  }

  /// Maps ADK roles to Anthropic message roles.
  static String toClaudeRole(String? role) {
    if (role == 'model' || role == 'assistant') {
      return 'assistant';
    }
    return 'user';
  }

  /// Maps Anthropic stop reasons to ADK finish reason strings.
  static String? toGoogleFinishReason(String? anthropicStopReason) {
    if (anthropicStopReason == null) {
      return null;
    }
    if (anthropicStopReason == 'end_turn' ||
        anthropicStopReason == 'stop_sequence' ||
        anthropicStopReason == 'tool_use' ||
        anthropicStopReason == 'pause_turn') {
      return 'STOP';
    }
    if (anthropicStopReason == 'max_tokens' ||
        anthropicStopReason == 'model_context_window_exceeded') {
      return 'MAX_TOKENS';
    }
    if (anthropicStopReason == 'refusal') {
      return 'SAFETY';
    }
    return 'FINISH_REASON_UNSPECIFIED';
  }

  /// Whether [part] represents an image payload.
  static bool isImagePart(Part part) {
    final InlineData? inlineData = part.inlineData;
    return inlineData != null && inlineData.mimeType.startsWith('image');
  }

  /// Whether [part] represents a PDF payload.
  static bool isPdfPart(Part part) {
    final InlineData? inlineData = part.inlineData;
    if (inlineData == null) {
      return false;
    }
    return inlineData.mimeType.split(';').first.trim().toLowerCase() ==
        'application/pdf';
  }

  /// Converts a [Part] into an Anthropic content block.
  static Map<String, Object?> partToMessageBlock(Part part) {
    return _partToMessageBlock(part, _ToolUseIdSanitizer());
  }

  static Map<String, Object?> _partToMessageBlock(
    Part part,
    _ToolUseIdSanitizer sanitizer,
  ) {
    if (part.thought) {
      if (part.text != null && part.text!.isNotEmpty) {
        return <String, Object?>{
          'type': 'thinking',
          'thinking': part.text,
          if (part.thoughtSignature != null)
            'signature': utf8.decode(
              part.thoughtSignature!,
              allowMalformed: true,
            ),
        };
      }
      if (part.thoughtSignature != null) {
        return <String, Object?>{
          'type': 'redacted_thinking',
          'data': utf8.decode(part.thoughtSignature!, allowMalformed: true),
        };
      }
    }
    if (part.text != null) {
      return <String, Object?>{'type': 'text', 'text': part.text};
    }
    if (part.functionCall != null) {
      return <String, Object?>{
        'type': 'tool_use',
        'id': sanitizer.sanitize(part.functionCall!.id),
        'name': part.functionCall!.name,
        'input': Map<String, dynamic>.from(part.functionCall!.args),
      };
    }
    if (part.functionResponse != null) {
      final Object response = part.functionResponse!.response;
      String content = '';
      if (response is Map && response['content'] is List) {
        final List<String> lines = <String>[];
        for (final Object? item in response['content'] as List<Object?>) {
          if (item is Map && item['type'] == 'text' && item['text'] is String) {
            lines.add(item['text'] as String);
          } else if (item is Map || item is List) {
            try {
              lines.add(jsonEncode(item));
            } catch (_) {
              lines.add('$item');
            }
          } else if (item != null) {
            lines.add('$item');
          }
        }
        content = lines.join('\n');
      } else if (response is Map &&
          response['content'] is String &&
          (response['content'] as String).isNotEmpty) {
        content = response['content'] as String;
      } else if (response is Map && response['result'] != null) {
        final Object result = response['result'] as Object;
        if (result is Map || result is List) {
          content = jsonEncode(result);
        } else {
          content = '$result';
        }
      } else if (response is Map || response is List) {
        try {
          content = jsonEncode(response);
        } catch (_) {
          content = '$response';
        }
      } else {
        content = '$response';
      }
      final bool isError =
          response is Map &&
          (_isTruthy(response['isError']) || _isTruthy(response['is_error']));
      return <String, Object?>{
        'type': 'tool_result',
        'tool_use_id': sanitizer.sanitize(part.functionResponse!.id),
        'is_error': isError,
        'content': content,
      };
    }
    if (isImagePart(part)) {
      return <String, Object?>{
        'type': 'image',
        'source': <String, Object?>{
          'type': 'base64',
          'media_type': part.inlineData!.mimeType,
          'data': base64Encode(part.inlineData!.data),
        },
      };
    }
    if (isPdfPart(part)) {
      return <String, Object?>{
        'type': 'document',
        'source': <String, Object?>{
          'type': 'base64',
          'media_type': part.inlineData!.mimeType,
          'data': base64Encode(part.inlineData!.data),
        },
      };
    }
    if (part.executableCode != null) {
      return <String, Object?>{
        'type': 'text',
        'text': 'Code:```python\n${part.executableCode}\n```',
      };
    }
    if (part.codeExecutionResult != null) {
      return <String, Object?>{
        'type': 'text',
        'text':
            'Execution Result:```code_output\n${part.codeExecutionResult}\n```',
      };
    }
    return <String, Object?>{'type': 'text', 'text': _fallbackPartText(part)};
  }

  /// Converts one [Content] into an Anthropic message payload.
  static Map<String, Object?> contentToMessageParam(Content content) {
    return _contentToMessageParam(content, _ToolUseIdSanitizer());
  }

  static Map<String, Object?> _contentToMessageParam(
    Content content,
    _ToolUseIdSanitizer sanitizer,
  ) {
    final List<Map<String, Object?>> blocks = <Map<String, Object?>>[];
    for (final Part part in content.parts) {
      if (content.role != 'user' && (isImagePart(part) || isPdfPart(part))) {
        continue;
      }
      blocks.add(_partToMessageBlock(part, sanitizer));
    }
    return <String, Object?>{
      'role': toClaudeRole(content.role),
      'content': blocks,
    };
  }

  /// Converts one Anthropic content [block] into a [Part].
  static Part contentBlockToPart(Map<String, Object?> block) {
    final String type = '${block['type'] ?? ''}';
    if (type == 'text') {
      return Part.text('${block['text'] ?? ''}');
    }
    if (type == 'thinking') {
      final String? signature = block['signature'] as String?;
      return Part.text(
        '${block['thinking'] ?? ''}',
        thought: true,
        thoughtSignature: signature == null ? null : utf8.encode(signature),
      );
    }
    if (type == 'redacted_thinking' || type == 'redacted') {
      final String data = '${block['data'] ?? block['signature'] ?? ''}';
      return Part(thought: true, thoughtSignature: utf8.encode(data));
    }
    if (type == 'tool_use') {
      final Object? input = block['input'];
      return Part.fromFunctionCall(
        name: '${block['name'] ?? ''}',
        args: input is Map
            ? input.cast<String, dynamic>()
            : <String, dynamic>{},
        id: block['id'] as String?,
      );
    }
    return Part.text(_fallbackContentBlockText(block));
  }

  /// Converts a function [declaration] to Anthropic tool schema format.
  static Map<String, Object?> functionDeclarationToToolParam(
    FunctionDeclaration declaration,
  ) {
    final Map<String, Object?> inputSchema = declaration.parameters.isEmpty
        ? <String, Object?>{'type': 'object', 'properties': <String, Object?>{}}
        : _deepCopyJsonMap(declaration.parameters);
    _updateTypeStrings(inputSchema);
    return <String, Object?>{
      'name': declaration.name,
      'description': declaration.description,
      'input_schema': inputSchema,
    };
  }

  /// Converts an Anthropic message object into [LlmResponse].
  static LlmResponse messageToLlmResponse(Map<String, Object?> message) {
    final List<Object?> contentBlocks =
        (message['content'] as List<Object?>?) ?? <Object?>[];
    final List<Part> parts = <Part>[];
    for (final Object? block in contentBlocks) {
      if (block is Map) {
        parts.add(contentBlockToPart(block.cast<String, Object?>()));
        continue;
      }
      if (block != null) {
        parts.add(Part.text('$block'));
      }
    }

    final Map<String, Object?> usage =
        (message['usage'] as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final int inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? 0;
    final int outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? 0;
    final int? cacheCreationInputTokens = _toInt(
      usage['cache_creation_input_tokens'] ?? usage['cacheCreationInputTokens'],
    );

    final String? model = message['model'] as String?;

    return LlmResponse(
      content: Content(role: 'model', parts: parts),
      usageMetadata: <String, Object?>{
        'prompt_token_count': inputTokens,
        'candidates_token_count': outputTokens,
        'total_token_count': inputTokens + outputTokens,
      },
      cacheCreationTokenCount: cacheCreationInputTokens,
      finishReason: toGoogleFinishReason(message['stop_reason'] as String?),
      modelVersion: model,
    );
  }

  /// Generates model responses using Anthropic-compatible request/response flow.
  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = _cloneRequestPreservingFunctionCallIds(request);
    prepared.model ??= model;
    maybeAppendUserContent(prepared);
    prepared.config.httpOptions ??= HttpOptions();
    final _OutputSchemaTool? outputSchemaTool = _resolveOutputSchemaTool(
      prepared,
    );
    final Map<String, Object?> anthropicRequest = _buildAnthropicRequest(
      prepared,
      stream: stream,
      outputSchemaTool: outputSchemaTool,
    );

    if (!stream && apiInvoker != null) {
      final List<Map<String, Object?>> messages = await apiInvoker!(
        request: anthropicRequest,
        stream: stream,
      );
      for (final Map<String, Object?> message in messages) {
        LlmResponse resp = messageToLlmResponse(message);
        if (outputSchemaTool != null) {
          resp = outputSchemaTool.unwrap(resp);
        }
        yield resp.copyWith(
          modelVersion: resp.modelVersion ?? prepared.model,
          turnComplete: true,
        );
      }
      return;
    }

    if (_generateHook != null) {
      yield* _generateHook(prepared, stream);
      return;
    }

    if (stream) {
      final Stream<Map<String, Object?>> rawStream = streamInvoker != null
          ? streamInvoker!(request: anthropicRequest)
          : _resolvedRestTransport.streamMessage(
              request: anthropicRequest,
              apiKey: _resolveApiKey(),
              baseUrl: _resolveBaseUrl(),
              apiVersion: _resolveApiVersion(prepared),
              headers: _resolveHeaders(prepared),
            );
      yield* _streamAnthropicResponses(
        rawStream,
        prepared,
        outputSchemaTool: outputSchemaTool,
      );
      return;
    }

    final Map<String, Object?> message = await _resolvedRestTransport
        .createMessage(
          request: anthropicRequest,
          apiKey: _resolveApiKey(),
          baseUrl: _resolveBaseUrl(),
          apiVersion: _resolveApiVersion(prepared),
          headers: _resolveHeaders(prepared),
        );
    LlmResponse resp = messageToLlmResponse(message);
    if (outputSchemaTool != null) {
      resp = outputSchemaTool.unwrap(resp);
    }
    yield resp.copyWith(
      modelVersion: resp.modelVersion ?? prepared.model,
      turnComplete: true,
    );
  }

  _OutputSchemaTool? _resolveOutputSchemaTool(LlmRequest request) {
    final Object? schema =
        request.config.responseSchema ?? request.config.responseJsonSchema;
    if (schema == null) {
      return null;
    }
    final List<ToolDeclaration>? declarations = request.config.tools;
    final bool hasFunctionDeclarations =
        declarations != null &&
        declarations.any(
          (ToolDeclaration tool) => tool.functionDeclarations.isNotEmpty,
        );
    if (hasFunctionDeclarations) {
      return null;
    }
    return _OutputSchemaTool.forSchema(schema);
  }

  Map<String, Object?> _buildAnthropicRequest(
    LlmRequest request, {
    required bool stream,
    _OutputSchemaTool? outputSchemaTool,
  }) {
    final _ToolUseIdSanitizer sanitizer = _ToolUseIdSanitizer();
    final List<Map<String, Object?>> messages = request.contents
        .map((Content content) => _contentToMessageParam(content, sanitizer))
        .toList();
    List<Map<String, Object?>> tools = <Map<String, Object?>>[];
    final List<ToolDeclaration>? declarations = request.config.tools;
    if (declarations != null) {
      for (final ToolDeclaration tool in declarations) {
        for (final FunctionDeclaration declaration
            in tool.functionDeclarations) {
          tools.add(functionDeclarationToToolParam(declaration));
        }
      }
    }
    final Map<String, Object?>? thinking = _anthropicThinkingConfig(
      request.config.thinkingConfig,
    );
    final bool thinkingEnabled = _thinkingIsEnabled(thinking);
    final String? effort = _extractEffort(request.config);
    final bool excludeSampling = thinkingEnabled || effort != null;

    Map<String, Object?>? toolChoice = request.toolsDict.isNotEmpty
        ? <String, Object?>{'type': 'auto'}
        : null;
    if (outputSchemaTool != null) {
      tools = <Map<String, Object?>>[outputSchemaTool.param];
      toolChoice = outputSchemaTool.choice(thinkingEnabled: thinkingEnabled);
    }

    return <String, Object?>{
      'model': request.model,
      'max_tokens': request.config.maxOutputTokens ?? maxTokens,
      'thinking': ?thinking,
      if (effort != null)
        'output_config': <String, Object?>{'effort': effort},
      if (!excludeSampling && request.config.temperature != null)
        'temperature': request.config.temperature,
      if (!excludeSampling && request.config.topP != null)
        'top_p': request.config.topP,
      if (!excludeSampling && request.config.topK != null)
        'top_k': request.config.topK,
      if (request.config.stopSequences.isNotEmpty)
        'stop_sequences': List<String>.from(request.config.stopSequences),
      if (stream) 'stream': true,
      if ((request.config.systemInstruction ?? '').isNotEmpty)
        'system': request.config.systemInstruction,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      'tool_choice': ?toolChoice,
    };
  }

  LlmRequest _cloneRequestPreservingFunctionCallIds(LlmRequest request) {
    return LlmRequest(
      model: request.model,
      contents: request.contents
          .map((Content content) => content.copyWith())
          .toList(),
      config: request.config.copyWith(),
      liveConnectConfig: request.liveConnectConfig.copyWith(),
      toolsDict: Map<String, BaseTool>.from(request.toolsDict),
      cacheConfig: request.cacheConfig,
      cacheMetadata: request.cacheMetadata,
      cacheableContentsTokenCount: request.cacheableContentsTokenCount,
      previousInteractionId: request.previousInteractionId,
    );
  }

  Map<String, Object?>? _anthropicThinkingConfig(Object? thinkingConfig) {
    if (thinkingConfig == null) {
      return null;
    }
    if (thinkingConfig is Map) {
      final Object? explicitType = thinkingConfig['type'];
      if (explicitType == 'adaptive') {
        return <String, Object?>{
          'type': 'adaptive',
          if (thinkingConfig['display'] != null)
            'display': thinkingConfig['display'],
        };
      }
      if (explicitType == 'disabled') {
        return <String, Object?>{'type': 'disabled'};
      }
      if (explicitType == 'enabled' &&
          thinkingConfig['budget_tokens'] != null) {
        final int? explicitBudget = _intValueOrNull(
          thinkingConfig['budget_tokens'],
        );
        if (explicitBudget == null) {
          throw ArgumentError('Anthropic thinking budget must be numeric.');
        }
        return <String, Object?>{
          'type': 'enabled',
          'budget_tokens': explicitBudget,
        };
      }
    }
    final Object? rawBudget = _thinkingBudgetValue(thinkingConfig);
    if (rawBudget == null) {
      if (thinkingConfig is Map && thinkingConfig.containsKey('effort')) {
        return null;
      }
      throw ArgumentError(
        'Anthropic thinkingConfig requires a thinking_budget, thinkingBudget, or budget value.',
      );
    }
    final int? budget = _intValueOrNull(rawBudget);
    if (budget == null) {
      throw ArgumentError('Anthropic thinking budget must be numeric.');
    }
    if (budget < 0) {
      return <String, Object?>{
        'type': 'adaptive',
        if (thinkingConfig is Map && thinkingConfig['display'] != null)
          'display': thinkingConfig['display'],
      };
    }
    if (budget == 0) {
      return <String, Object?>{'type': 'disabled'};
    }
    return <String, Object?>{'type': 'enabled', 'budget_tokens': budget};
  }

  Stream<LlmResponse> _streamAnthropicResponses(
    Stream<Map<String, Object?>> rawStream,
    LlmRequest request, {
    _OutputSchemaTool? outputSchemaTool,
  }) async* {
    final Map<int, StringBuffer> textBlocks = <int, StringBuffer>{};
    final Map<int, _AnthropicToolUseAccumulator> toolUseBlocks =
        <int, _AnthropicToolUseAccumulator>{};
    final Map<int, _AnthropicThinkingAccumulator> thinkingBlocks =
        <int, _AnthropicThinkingAccumulator>{};
    final Map<int, _AnthropicRedactedThinkingAccumulator>
    redactedThinkingBlocks = <int, _AnthropicRedactedThinkingAccumulator>{};
    int inputTokens = 0;
    int outputTokens = 0;
    int cacheCreationInputTokens = 0;
    String? finishReason;
    String? modelVersion;

    await for (final Map<String, Object?> event in rawStream) {
      final String type = '${event['type'] ?? ''}';
      switch (type) {
        case 'message_start':
          final Map<String, Object?> message = _mapOf(event['message']);
          final Map<String, Object?> usage = _mapOf(message['usage']);
          inputTokens = _intValue(usage['input_tokens']);
          outputTokens = _intValue(usage['output_tokens']);
          cacheCreationInputTokens =
              _toInt(
                usage['cache_creation_input_tokens'] ??
                    usage['cacheCreationInputTokens'],
              ) ??
              0;
          modelVersion = message['model'] as String?;
          break;
        case 'content_block_start':
          final int index = _intValue(event['index']);
          final Map<String, Object?> block = _mapOf(event['content_block']);
          final String blockType = '${block['type'] ?? ''}';
          if (blockType == 'text') {
            textBlocks[index] = StringBuffer('${block['text'] ?? ''}');
          } else if (blockType == 'thinking') {
            thinkingBlocks[index] = _AnthropicThinkingAccumulator(
              text: '${block['thinking'] ?? ''}',
              signature: block['signature'] as String?,
            );
          } else if (blockType == 'redacted_thinking') {
            redactedThinkingBlocks[index] =
                _AnthropicRedactedThinkingAccumulator(
                  data: block['data'] as String?,
                );
          } else if (blockType == 'tool_use') {
            toolUseBlocks[index] = _AnthropicToolUseAccumulator(
              id: '${block['id'] ?? ''}',
              name: '${block['name'] ?? ''}',
            );
          }
          break;
        case 'content_block_delta':
          final int index = _intValue(event['index']);
          final Map<String, Object?> delta = _mapOf(event['delta']);
          final String deltaType = '${delta['type'] ?? ''}';
          if (deltaType == 'text_delta') {
            final String text = '${delta['text'] ?? ''}';
            if (text.isEmpty) {
              continue;
            }
            final StringBuffer buffer = textBlocks.putIfAbsent(
              index,
              StringBuffer.new,
            );
            buffer.write(text);
            yield LlmResponse(
              modelVersion: modelVersion ?? request.model,
              content: Content(role: 'model', parts: <Part>[Part.text(text)]),
              partial: true,
              turnComplete: false,
            );
          } else if (deltaType == 'thinking_delta') {
            final String thinking = '${delta['thinking'] ?? ''}';
            if (thinking.isEmpty) {
              continue;
            }
            final _AnthropicThinkingAccumulator accumulator = thinkingBlocks
                .putIfAbsent(index, _AnthropicThinkingAccumulator.new);
            accumulator.text.write(thinking);
            yield LlmResponse(
              modelVersion: modelVersion ?? request.model,
              content: Content(
                role: 'model',
                parts: <Part>[Part.text(thinking, thought: true)],
              ),
              partial: true,
              turnComplete: false,
            );
          } else if (deltaType == 'signature_delta') {
            final _AnthropicThinkingAccumulator accumulator = thinkingBlocks
                .putIfAbsent(index, _AnthropicThinkingAccumulator.new);
            accumulator.signature = delta['signature'] as String?;
          } else if (deltaType == 'input_json_delta') {
            final _AnthropicToolUseAccumulator? tool = toolUseBlocks[index];
            if (tool == null) {
              continue;
            }
            final String partialJson = '${delta['partial_json'] ?? ''}';
            tool.argsJson += partialJson;
            if (outputSchemaTool != null &&
                tool.name == _outputSchemaToolName) {
              if (partialJson.isNotEmpty && !outputSchemaTool.nestsValue) {
                yield LlmResponse(
                  modelVersion: modelVersion ?? request.model,
                  content: Content(
                    role: 'model',
                    parts: <Part>[Part.text(partialJson)],
                  ),
                  partial: true,
                  turnComplete: false,
                );
              }
              continue;
            }
          }
          break;
        case 'content_block_stop':
          break;
        case 'message_delta':
          final Map<String, Object?> delta = _mapOf(event['delta']);
          final String? reason = delta['stop_reason'] as String?;
          if (reason != null) {
            finishReason = toGoogleFinishReason(reason);
          }
          final Map<String, Object?> usage = _mapOf(event['usage']);
          final int deltaOutput = _intValue(usage['output_tokens']);
          if (deltaOutput > 0) {
            outputTokens = deltaOutput;
          }
          final int? deltaCacheCreation = _toInt(
            usage['cache_creation_input_tokens'] ??
                usage['cacheCreationInputTokens'],
          );
          if (deltaCacheCreation != null) {
            cacheCreationInputTokens = deltaCacheCreation;
          }
          break;
        case 'message_stop':
          break;
        default:
          break;
      }
    }

    final List<int> sortedIndices = <int>{
      ...textBlocks.keys,
      ...toolUseBlocks.keys,
      ...thinkingBlocks.keys,
      ...redactedThinkingBlocks.keys,
    }.toList()..sort();

    final List<Part> parts = <Part>[];
    for (final int index in sortedIndices) {
      final _AnthropicThinkingAccumulator? thinking = thinkingBlocks[index];
      if (thinking != null && thinking.text.isNotEmpty) {
        parts.add(
          Part.text(
            thinking.text.toString(),
            thought: true,
            thoughtSignature: thinking.signature == null
                ? null
                : utf8.encode(thinking.signature!),
          ),
        );
      }
      final _AnthropicRedactedThinkingAccumulator? redacted =
          redactedThinkingBlocks[index];
      if (redacted?.data != null) {
        parts.add(
          Part(thought: true, thoughtSignature: utf8.encode(redacted!.data!)),
        );
      }
      final StringBuffer? text = textBlocks[index];
      if (text != null && text.isNotEmpty) {
        parts.add(Part.text(text.toString()));
      }
      final _AnthropicToolUseAccumulator? tool = toolUseBlocks[index];
      if (tool != null) {
        parts.add(
          Part.fromFunctionCall(
            name: tool.name,
            id: tool.id,
            args: _decodeToolArgs(tool.argsJson),
          ),
        );
      }
    }

    LlmResponse finalResponse = LlmResponse(
      modelVersion: modelVersion ?? request.model,
      content: Content(role: 'model', parts: parts),
      usageMetadata: <String, Object?>{
        'prompt_token_count': inputTokens,
        'candidates_token_count': outputTokens,
        'total_token_count': inputTokens + outputTokens,
      },
      cacheCreationTokenCount: cacheCreationInputTokens,
      finishReason: finishReason,
      partial: false,
      turnComplete: true,
    );
    if (outputSchemaTool != null) {
      finalResponse = outputSchemaTool.unwrap(finalResponse);
    }
    yield finalResponse;
  }

  Map<String, dynamic> _decodeToolArgs(String jsonText) {
    if (jsonText.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final Object? decoded = jsonDecode(jsonText);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  String _resolveApiKey() {
    final String? value =
        (environment ?? readSystemEnvironment())[_anthropicApiKeyEnv];
    if (value == null || value.isEmpty) {
      throw StateError(
        'AnthropicLlm.generateContent requires ANTHROPIC_API_KEY to be set.',
      );
    }
    return value;
  }

  String _resolveBaseUrl() {
    return baseUrl ??
        (environment ?? readSystemEnvironment())[_anthropicBaseUrlEnv] ??
        _defaultAnthropicBaseUrl;
  }

  String _resolveApiVersion(LlmRequest request) {
    return apiVersion ??
        request.config.httpOptions?.apiVersion ??
        (environment ?? readSystemEnvironment())[_anthropicVersionEnv] ??
        _defaultAnthropicVersion;
  }

  Map<String, String> _resolveHeaders(LlmRequest request) {
    return Map<String, String>.from(
      request.config.httpOptions?.headers ?? const <String, String>{},
    );
  }
}

Map<String, Object?> _deepCopyJsonMap(Map<String, Object?> source) {
  final Object? cloned = _deepCopyJsonValue(source);
  if (cloned is Map<String, Object?>) {
    return cloned;
  }
  if (cloned is Map) {
    return cloned.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  return <String, Object?>{};
}

Object? _deepCopyJsonValue(Object? value) {
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry('$key', _deepCopyJsonValue(item)),
    );
  }
  if (value is List) {
    return value
        .map((Object? item) => _deepCopyJsonValue(item))
        .toList(growable: false);
  }
  return value;
}

void _updateTypeStrings(Object? value) {
  if (value is List) {
    for (final Object? item in value) {
      _updateTypeStrings(item);
    }
    return;
  }
  if (value is! Map) {
    return;
  }

  final Object? schemaType = value['type'];
  if (schemaType is String) {
    value['type'] = schemaType.toLowerCase();
  }

  for (final String dictKey in const <String>[
    r'$defs',
    'defs',
    'dependentSchemas',
    'patternProperties',
    'properties',
  ]) {
    final Object? childDict = value[dictKey];
    if (childDict is! Map) {
      continue;
    }
    for (final Object? childValue in childDict.values) {
      _updateTypeStrings(childValue);
    }
  }

  for (final String singleKey in const <String>[
    'additionalProperties',
    'additional_properties',
    'contains',
    'else',
    'if',
    'items',
    'not',
    'propertyNames',
    'then',
    'unevaluatedProperties',
  ]) {
    final Object? childValue = value[singleKey];
    if (childValue is Map || childValue is List) {
      _updateTypeStrings(childValue);
    }
  }

  for (final String listKey in const <String>[
    'allOf',
    'all_of',
    'anyOf',
    'any_of',
    'oneOf',
    'one_of',
    'prefixItems',
  ]) {
    final Object? childList = value[listKey];
    if (childList is List) {
      _updateTypeStrings(childList);
    }
  }
}

Map<String, Object?> _decodeJsonObject(String body) {
  final String normalized = body.trim();
  if (normalized.isEmpty) {
    throw AnthropicApiException(
      500,
      'Anthropic API response body is empty.',
      responseBody: body,
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(normalized);
  } on FormatException {
    throw AnthropicApiException(
      500,
      'Anthropic API response is not valid JSON.',
      responseBody: body,
    );
  }
  if (decoded is! Map) {
    throw AnthropicApiException(
      500,
      'Anthropic API response is not a JSON object.',
      responseBody: body,
    );
  }
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
}

Map<String, Object?> _mapOf(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? nested) => MapEntry('$key', nested));
  }
  return const <String, Object?>{};
}

bool _thinkingIsEnabled(Map<String, Object?>? thinking) {
  if (thinking == null) {
    return false;
  }
  final Object? type = thinking['type'];
  return type == 'enabled' || type == 'adaptive';
}

Object? _thinkingLevelValue(Object? thinkingConfig) {
  if (thinkingConfig is Map) {
    return thinkingConfig['thinking_level'] ?? thinkingConfig['thinkingLevel'];
  }
  try {
    final dynamic dynamicConfig = thinkingConfig;
    return dynamicConfig.thinkingLevel;
  } catch (_) {
    return null;
  }
}

String? _extractEffort(GenerateContentConfig config) {
  if (config is AnthropicGenerateContentConfig && config.effort != null) {
    return config.effort;
  }
  final Object? thinkingConfig = config.thinkingConfig;
  if (thinkingConfig is Map && thinkingConfig['effort'] != null) {
    final String effort = '${thinkingConfig['effort']}';
    if (!_validAnthropicEfforts.contains(effort)) {
      throw ArgumentError.value(
        effort,
        'effort',
        'Must be one of ${_validAnthropicEfforts.join(", ")}.',
      );
    }
    return effort;
  }
  return null;
}

Object? _thinkingBudgetValue(Object? thinkingConfig) {
  if (thinkingConfig is Map) {
    return thinkingConfig['thinking_budget'] ??
        thinkingConfig['thinkingBudget'] ??
        thinkingConfig['budget'];
  }
  try {
    final dynamic dynamicConfig = thinkingConfig;
    return dynamicConfig.thinkingBudget;
  } catch (_) {
    return null;
  }
}

int? _intValueOrNull(Object? value) {
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

int _intValue(Object? value, {int fallback = 0}) {
  return (value as num?)?.toInt() ?? fallback;
}

Map<String, Object?>? _decodeSseData(String rawData) {
  final String data = rawData.trim();
  if (data.isEmpty || data == '[DONE]') {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    throw AnthropicApiException(
      500,
      'Anthropic SSE event contains malformed JSON.',
      responseBody: data,
    );
  }
  if (decoded is! Map) {
    throw AnthropicApiException(
      500,
      'Anthropic SSE event is not a JSON object.',
      responseBody: data,
    );
  }
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
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

String _stripUtf8Bom(String value) {
  if (value.startsWith('\ufeff')) {
    return value.substring(1);
  }
  return value;
}

void _appendSseUnexpectedLine(StringBuffer preview, String line) {
  const int maxPreviewLength = 2048;
  if (preview.length >= maxPreviewLength) {
    return;
  }
  final String trimmedLine = line.trimRight();
  if (trimmedLine.isEmpty) {
    return;
  }
  if (preview.isNotEmpty) {
    preview.writeln();
  }
  if (preview.length + trimmedLine.length > maxPreviewLength) {
    preview.write(trimmedLine.substring(0, maxPreviewLength - preview.length));
    return;
  }
  preview.write(trimmedLine);
}

String _extractErrorMessage(String body) {
  try {
    final Map<String, Object?> decoded = _decodeJsonObject(body);
    final Map<String, Object?> error = _mapOf(decoded['error']);
    final String message = '${error['message'] ?? decoded['message'] ?? ''}'
        .trim();
    if (message.isNotEmpty) {
      return message;
    }
  } on Object {
    // Fall back to the raw body below.
  }
  final String trimmed = body.trim();
  if (trimmed.isNotEmpty) {
    return trimmed;
  }
  return 'Anthropic API request failed.';
}

class _SseField {
  _SseField({required this.name, required this.value});

  final String name;
  final String value;
}

String _fallbackPartText(Part part) {
  final Map<String, Object?> payload = <String, Object?>{};
  if (part.text != null) {
    payload['text'] = part.text;
  }
  if (part.fileData != null) {
    payload['file_data'] = <String, Object?>{
      'file_uri': part.fileData!.fileUri,
      'mime_type': part.fileData!.mimeType,
      'display_name': part.fileData!.displayName,
    };
  }
  if (part.inlineData != null) {
    payload['inline_data'] = <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'display_name': part.inlineData!.displayName,
      'byte_count': part.inlineData!.data.length,
    };
  }
  if (part.executableCode != null) {
    payload['executable_code'] = part.executableCode;
  }
  if (part.codeExecutionResult != null) {
    payload['code_execution_result'] = part.codeExecutionResult;
  }

  if (payload.isEmpty) {
    return 'Unsupported anthropic part payload.';
  }
  try {
    return 'Unsupported anthropic part payload: ${jsonEncode(payload)}';
  } catch (_) {
    return 'Unsupported anthropic part payload: $payload';
  }
}

String _fallbackContentBlockText(Map<String, Object?> block) {
  final Object? text = block['text'];
  if (text is String && text.isNotEmpty) {
    return text;
  }

  final Object? content = block['content'];
  if (content is String && content.isNotEmpty) {
    return content;
  }
  if (content is List) {
    final String joined = content
        .where((Object? item) => item != null)
        .map((Object? item) => '$item')
        .join('\n')
        .trim();
    if (joined.isNotEmpty) {
      return joined;
    }
  }

  try {
    return 'Unsupported anthropic content block: ${jsonEncode(block)}';
  } catch (_) {
    return 'Unsupported anthropic content block: $block';
  }
}

bool _isTruthy(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value.isNotEmpty;
  }
  if (value is Iterable) {
    return value.isNotEmpty;
  }
  if (value is Map) {
    return value.isNotEmpty;
  }
  return value != null;
}

int? _toInt(Object? value) {
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

/// Backward-compatible alias for [AnthropicLlm].
typedef Claude = AnthropicLlm;
