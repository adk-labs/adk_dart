/// Anthropic Claude model adapter integration.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

/// Anthropic Claude adapter for ADK model requests.
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
  final AnthropicStreamInvoker? streamInvoker;
  final Map<String, String>? environment;
  final String? baseUrl;
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
  static String toGoogleFinishReason(String? anthropicStopReason) {
    if (anthropicStopReason == 'end_turn' ||
        anthropicStopReason == 'stop_sequence' ||
        anthropicStopReason == 'tool_use') {
      return 'STOP';
    }
    if (anthropicStopReason == 'max_tokens') {
      return 'MAX_TOKENS';
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
    if (part.text != null) {
      return <String, Object?>{'type': 'text', 'text': part.text};
    }
    if (part.functionCall != null) {
      return <String, Object?>{
        'type': 'tool_use',
        'id': part.functionCall!.id ?? '',
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
          } else if (item != null) {
            lines.add('$item');
          }
        }
        content = lines.join('\n');
      } else if (response is Map && response['result'] != null) {
        final Object result = response['result'] as Object;
        if (result is Map || result is List) {
          content = jsonEncode(result);
        } else {
          content = '$result';
        }
      } else {
        content = '$response';
      }
      return <String, Object?>{
        'type': 'tool_result',
        'tool_use_id': part.functionResponse!.id ?? '',
        'is_error': false,
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
    final List<Map<String, Object?>> blocks = <Map<String, Object?>>[];
    for (final Part part in content.parts) {
      if (content.role != 'user' && (isImagePart(part) || isPdfPart(part))) {
        continue;
      }
      blocks.add(partToMessageBlock(part));
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
    return <String, Object?>{
      'name': declaration.name,
      'description': declaration.description,
      'input_schema': declaration.parameters.isEmpty
          ? <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            }
          : declaration.parameters,
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

    return LlmResponse(
      content: Content(role: 'model', parts: parts),
      usageMetadata: <String, Object?>{
        'prompt_token_count': inputTokens,
        'candidates_token_count': outputTokens,
        'total_token_count': inputTokens + outputTokens,
      },
      finishReason: toGoogleFinishReason(message['stop_reason'] as String?),
    );
  }

  /// Generates model responses using Anthropic-compatible request/response flow.
  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model ??= model;
    maybeAppendUserContent(prepared);
    prepared.config.httpOptions ??= HttpOptions();
    final Map<String, Object?> anthropicRequest = _buildAnthropicRequest(
      prepared,
      stream: stream,
    );

    if (!stream && apiInvoker != null) {
      final List<Map<String, Object?>> messages = await apiInvoker!(
        request: anthropicRequest,
        stream: stream,
      );
      for (final Map<String, Object?> message in messages) {
        yield messageToLlmResponse(
          message,
        ).copyWith(modelVersion: prepared.model, turnComplete: true);
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
      yield* _streamAnthropicResponses(rawStream, prepared);
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
    yield messageToLlmResponse(
      message,
    ).copyWith(modelVersion: prepared.model, turnComplete: true);
  }

  Map<String, Object?> _buildAnthropicRequest(
    LlmRequest request, {
    required bool stream,
  }) {
    final List<Map<String, Object?>> messages = request.contents
        .map(contentToMessageParam)
        .toList();
    final List<Map<String, Object?>> tools = <Map<String, Object?>>[];
    final List<ToolDeclaration>? declarations = request.config.tools;
    if (declarations != null) {
      for (final ToolDeclaration tool in declarations) {
        for (final FunctionDeclaration declaration
            in tool.functionDeclarations) {
          tools.add(functionDeclarationToToolParam(declaration));
        }
      }
    }
    return <String, Object?>{
      'model': request.model,
      'max_tokens': maxTokens,
      if (stream) 'stream': true,
      if ((request.config.systemInstruction ?? '').isNotEmpty)
        'system': request.config.systemInstruction,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      if (request.toolsDict.isNotEmpty)
        'tool_choice': <String, Object?>{'type': 'auto'},
    };
  }

  Stream<LlmResponse> _streamAnthropicResponses(
    Stream<Map<String, Object?>> rawStream,
    LlmRequest request,
  ) async* {
    final Map<int, StringBuffer> textBlocks = <int, StringBuffer>{};
    final Map<int, _AnthropicToolUseAccumulator> toolUseBlocks =
        <int, _AnthropicToolUseAccumulator>{};
    int inputTokens = 0;
    int outputTokens = 0;
    String? finishReason;

    await for (final Map<String, Object?> event in rawStream) {
      final String type = '${event['type'] ?? ''}';
      switch (type) {
        case 'message_start':
          final Map<String, Object?> message = _mapOf(event['message']);
          final Map<String, Object?> usage = _mapOf(message['usage']);
          inputTokens = _intValue(usage['input_tokens']);
          outputTokens = _intValue(usage['output_tokens']);
          break;
        case 'content_block_start':
          final int index = _intValue(event['index']);
          final Map<String, Object?> block = _mapOf(event['content_block']);
          final String blockType = '${block['type'] ?? ''}';
          if (blockType == 'text') {
            textBlocks[index] = StringBuffer('${block['text'] ?? ''}');
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
              modelVersion: request.model,
              content: Content(role: 'model', parts: <Part>[Part.text(text)]),
              partial: true,
              turnComplete: false,
            );
          } else if (deltaType == 'input_json_delta') {
            final _AnthropicToolUseAccumulator? tool = toolUseBlocks[index];
            if (tool == null) {
              continue;
            }
            tool.argsJson += '${delta['partial_json'] ?? ''}';
          }
          break;
        case 'message_delta':
          final Map<String, Object?> delta = _mapOf(event['delta']);
          finishReason = toGoogleFinishReason(delta['stop_reason'] as String?);
          final Map<String, Object?> usage = _mapOf(event['usage']);
          outputTokens = _intValue(
            usage['output_tokens'],
            fallback: outputTokens,
          );
          break;
        case 'message_stop':
        case 'content_block_stop':
          break;
      }
    }

    final List<Part> parts = <Part>[];
    final List<int> indices = <int>{
      ...textBlocks.keys,
      ...toolUseBlocks.keys,
    }.toList()..sort();
    for (final int index in indices) {
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

    yield LlmResponse(
      modelVersion: request.model,
      content: Content(role: 'model', parts: parts),
      usageMetadata: <String, Object?>{
        'prompt_token_count': inputTokens,
        'candidates_token_count': outputTokens,
        'total_token_count': inputTokens + outputTokens,
      },
      finishReason: finishReason,
      partial: false,
      turnComplete: true,
    );
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

/// Backward-compatible alias for [AnthropicLlm].
typedef Claude = AnthropicLlm;
