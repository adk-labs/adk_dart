import 'dart:convert';

import 'package:http/http.dart' as http;

import '../types/content.dart';
import '../utils/system_environment/system_environment.dart';
import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

/// Exception thrown when a LiteLLM/Ollama HTTP request fails.
class LiteLlmException implements Exception {
  /// Creates a [LiteLlmException].
  const LiteLlmException(this.message, {this.uri});

  /// Error description.
  final String message;

  /// Target URI.
  final Uri? uri;

  @override
  String toString() => 'LiteLlmException: $message${uri != null ? ' (uri: $uri)' : ''}';
}

/// Hook for overriding LiteLLM generation behavior.
typedef LiteLlmGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);

/// Callback that invokes a LiteLLM-compatible completions endpoint.
typedef LiteLlmCompletionsInvoker =
    Future<List<Map<String, Object?>>> Function({
      required Map<String, Object?> payload,
      required bool stream,
    });

const String _thoughtSignatureSeparator = '__thought__';
const String _systemInstructionFallbackText =
    'Handle the requests as specified in the System Instruction.';

/// OpenAI-compatible adapter that targets LiteLLM providers.
class LiteLlm extends BaseLlm {
  /// Creates a LiteLLM adapter for [model].
  LiteLlm({
    required super.model,
    this.customProvider = '',
    this.completionsInvoker,
    LiteLlmGenerateHook? generateHook,
    this.apiKey,
    this.baseUrl,
  }) : _generateHook = generateHook;

  /// Optional explicit provider name override.
  final String customProvider;
  final LiteLlmGenerateHook? _generateHook;

  /// Optional invoker for completions responses.
  final LiteLlmCompletionsInvoker? completionsInvoker;

  /// Optional API key for remote completions request when using default invoker.
  final String? apiKey;

  /// Optional base URL of the completions API when using default invoker.
  final String? baseUrl;

  /// Regex patterns supported by this adapter.
  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'[a-zA-Z0-9._-]+\/[a-zA-Z0-9._:-]+')];
  }

  /// Maps provider-specific finish reasons to ADK finish reason values.
  static String mapFinishReason(Object? finishReason) {
    final String value = '$finishReason'.toLowerCase();
    if (value == 'length') {
      return 'MAX_TOKENS';
    }
    if (value == 'stop' || value == 'tool_calls' || value == 'function_call') {
      return 'STOP';
    }
    if (value == 'content_filter') {
      return 'SAFETY';
    }
    return 'OTHER';
  }

  /// Infers the LiteLLM provider from [model].
  static String getProviderFromModel(String model) {
    if (model.contains('/')) {
      return model.split('/').first.toLowerCase();
    }
    final String lower = model.toLowerCase();
    if (lower.contains('azure')) {
      return 'azure';
    }
    if (lower.startsWith('gpt-') || lower.startsWith('o1')) {
      return 'openai';
    }
    return '';
  }

  /// Builds a LiteLLM/OpenAI-style request payload from [request].
  static Map<String, Object?> buildPayload(
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
      messages.addAll(_contentToMessages(content, model: request.model ?? ''));
    }

    final Map<String, Object?> payload = <String, Object?>{
      'model': request.model ?? '',
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
    final Map<String, Object?>? responseJsonSchema = _asObjectMap(
      request.config.responseJsonSchema,
    );
    if (responseJsonSchema != null) {
      payload['response_format'] = _toLiteLlmResponseFormat(
        _deepCopyJsonMap(responseJsonSchema),
        request.model ?? '',
      );
    } else if (request.config.responseMimeType == 'application/json') {
      payload['response_format'] = const <String, Object?>{
        'type': 'json_object',
      };
    }

    final List<ToolDeclaration>? requestTools = request.config.tools;
    if (requestTools != null && requestTools.isNotEmpty) {
      final List<Map<String, Object?>> tools = <Map<String, Object?>>[];
      for (final ToolDeclaration tool in requestTools) {
        if (tool.functionDeclarations.isNotEmpty) {
          for (final FunctionDeclaration declaration in tool.functionDeclarations) {
            tools.add(<String, Object?>{
              'type': 'function',
              'function': <String, Object?>{
                'name': declaration.name,
                if (declaration.description.isNotEmpty)
                  'description': declaration.description,
                if (declaration.parameters.isNotEmpty)
                  'parameters': _deepCopyJsonValue(declaration.parameters),
              },
            });
          }
        } else {
          final Map<String, Object?> nativeDump = <String, Object?>{
            if (tool.googleSearch != null)
              'google_search': _deepCopyJsonValue(tool.googleSearch),
            if (tool.googleSearchRetrieval != null)
              'google_search_retrieval': _deepCopyJsonValue(tool.googleSearchRetrieval),
            if (tool.codeExecution != null)
              'code_execution': _deepCopyJsonValue(tool.codeExecution),
            if (tool.googleMaps != null)
              'google_maps': _deepCopyJsonValue(tool.googleMaps),
            if (tool.enterpriseWebSearch != null)
              'enterprise_web_search': _deepCopyJsonValue(tool.enterpriseWebSearch),
            if (tool.computerUse != null)
              'computer_use': _deepCopyJsonValue(tool.computerUse),
            if (tool.googleSearch != null)
              'googleSearch': _deepCopyJsonValue(tool.googleSearch),
            if (tool.googleSearchRetrieval != null)
              'googleSearchRetrieval': _deepCopyJsonValue(tool.googleSearchRetrieval),
            if (tool.codeExecution != null)
              'codeExecution': _deepCopyJsonValue(tool.codeExecution),
            if (tool.googleMaps != null)
              'googleMaps': _deepCopyJsonValue(tool.googleMaps),
            if (tool.enterpriseWebSearch != null)
              'enterpriseWebSearch': _deepCopyJsonValue(tool.enterpriseWebSearch),
            if (tool.computerUse != null)
              'computerUse': _deepCopyJsonValue(tool.computerUse),
          };
          if (nativeDump.isNotEmpty) {
            tools.add(nativeDump);
          }
        }
      }
      if (tools.isNotEmpty) {
        payload['tools'] = tools;
      }
    }

    return payload;
  }

  /// Parses one LiteLLM completion response into [LlmResponse].
  static LlmResponse parseCompletionResponse(Map<String, Object?> response) {
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
    final Set<String> reasoningTexts = <String>{};
    for (final String field in const <String>[
      'thinking_blocks',
      'reasoning_content',
      'reasoning',
    ]) {
      parts.addAll(
        _extractReasoningParts(message[field], reasoningTexts: reasoningTexts),
      );
    }
    final Object? contentRaw = message['content'];
    if (contentRaw is String && contentRaw.isNotEmpty) {
      parts.add(Part.text(contentRaw));
    }

    final List<Object?> toolCalls =
        (message['tool_calls'] as List<Object?>?) ?? <Object?>[];
    for (final Object? call in toolCalls) {
      final Map<String, Object?> callMap = _asMap(call);
      parts.add(_parseFunctionCall(callMap));
    }

    final Map<String, Object?> usage = _asMap(response['usage']);
    final String finishReason = mapFinishReason(first['finish_reason']);
    final String? errorMessage = _finishReasonToErrorMessage(finishReason);
    return LlmResponse(
      modelVersion: response['model'] as String?,
      content: Content(role: role, parts: parts),
      finishReason: finishReason,
      errorCode: errorMessage == null ? null : finishReason,
      errorMessage: errorMessage,
      usageMetadata: <String, Object?>{
        'prompt_token_count': usage['prompt_tokens'] ?? 0,
        'candidates_token_count': usage['completion_tokens'] ?? 0,
        'total_token_count': usage['total_tokens'] ?? 0,
        if (_reasoningTokens(usage) != null)
          'thoughts_token_count': _reasoningTokens(usage),
      },
      customMetadata: <String, dynamic>{
        'id': response['id'],
        'created': response['created'],
        'provider': getProviderFromModel('${response['model'] ?? ''}'),
      }..removeWhere((Object? key, Object? value) => value == null),
    );
  }

  /// Generates model responses using LiteLLM payload/response conventions.
  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model ??= model;
    maybeAppendUserContent(prepared);
    _appendFallbackUserContentIfMissing(prepared);

    if (_generateHook != null) {
      yield* _generateHook(prepared, stream);
      return;
    }

    final LiteLlmCompletionsInvoker invoker = completionsInvoker ?? _defaultHttpCompletionsInvoker;

    final List<Map<String, Object?>> responses = await invoker(
      payload: buildPayload(prepared, stream: stream),
      stream: stream,
    );
    for (final Map<String, Object?> response in responses) {
      yield parseCompletionResponse(response);
    }
  }

  Future<List<Map<String, Object?>>> _defaultHttpCompletionsInvoker({
    required Map<String, Object?> payload,
    required bool stream,
  }) async {
    final Map<String, String> env = readSystemEnvironment();
    final String resolvedBaseUrl = baseUrl ??
        env['LITELLM_API_BASE'] ??
        env['OLLAMA_API_BASE'] ??
        env['OPENAI_API_BASE'] ??
        'http://localhost:4000/v1';

    final String resolvedApiKey = apiKey ??
        env['LITELLM_API_KEY'] ??
        env['OLLAMA_API_KEY'] ??
        env['OPENAI_API_KEY'] ??
        'no-key';

    final Uri uri = Uri.parse('$resolvedBaseUrl/chat/completions');

    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      if (resolvedApiKey != 'no-key') 'Authorization': 'Bearer $resolvedApiKey',
    };

    if (stream) {
      final http.Request httpRequest = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(payload);

      final http.Client client = http.Client();
      final http.StreamedResponse streamedResponse = await client.send(httpRequest);

      if (streamedResponse.statusCode != 200) {
        final String errorBody = await streamedResponse.stream.bytesToString();
        client.close();
        throw LiteLlmException(
          'LiteLlm HTTP error ${streamedResponse.statusCode}: $errorBody',
          uri: uri,
        );
      }

      final List<Map<String, Object?>> chunks = <Map<String, Object?>>[];
      final Stream<String> lineStream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final String line in lineStream) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (trimmed.startsWith('data: ')) {
          final String dataContent = trimmed.substring(6).trim();
          if (dataContent == '[DONE]') {
            continue;
          }
          try {
            final Map<String, Object?> parsed = jsonDecode(dataContent) as Map<String, Object?>;
            chunks.add(parsed);
          } catch (_) {
            // Ignore malformed chunks
          }
        }
      }
      client.close();
      return chunks;
    } else {
      final http.Response response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 200) {
        throw LiteLlmException(
          'LiteLlm HTTP error ${response.statusCode}: ${response.body}',
          uri: uri,
        );
      }

      final Map<String, Object?> data = jsonDecode(response.body) as Map<String, Object?>;
      return <Map<String, Object?>>[data];
    }
  }
}

bool _partHasPayload(Part part) {
  if (part.text != null && part.text!.isNotEmpty) {
    return true;
  }
  if (part.inlineData != null && part.inlineData!.data.isNotEmpty) {
    return true;
  }
  if (part.fileData != null && part.fileData!.fileUri.isNotEmpty) {
    return true;
  }
  if (part.functionResponse != null) {
    return true;
  }
  return false;
}

void _appendFallbackUserContentIfMissing(LlmRequest request) {
  for (int i = request.contents.length - 1; i >= 0; i -= 1) {
    final Content content = request.contents[i];
    if (content.role != 'user') {
      continue;
    }
    if (content.parts.any(_partHasPayload)) {
      return;
    }
    content.parts.add(Part.text(_systemInstructionFallbackText));
    return;
  }

  request.contents.add(Content.userText(_systemInstructionFallbackText));
}

String? _finishReasonToErrorMessage(String finishReason) {
  if (finishReason == 'STOP') {
    return null;
  }
  if (finishReason == 'MAX_TOKENS') {
    return 'Maximum tokens reached';
  }
  return 'Finished with $finishReason';
}

Object? _reasoningTokens(Map<String, Object?> usage) {
  final Map<String, Object?> details = _asMap(
    usage['completion_tokens_details'],
  );
  return details['reasoning_tokens'] ?? details['reasoningTokens'];
}

List<Part> _extractReasoningParts(Object? raw, {Set<String>? reasoningTexts}) {
  final Set<String> seen = reasoningTexts ?? <String>{};
  final List<Part> parts = <Part>[];

  if (_isThinkingBlocksFormat(raw)) {
    for (final Object? item in raw as List<Object?>) {
      final Map<String, Object?> block = _asMap(item);
      if ('${block['type'] ?? ''}' == 'redacted') {
        continue;
      }
      final String text = '${block['thinking'] ?? ''}'.trim();
      final Object? signature = block['signature'];
      final bool hasSignature =
          signature != null && '$signature'.isNotEmpty;
      // Anthropic streams a signature in a final chunk with empty text.
      // Preserve signature-only blocks so the signature survives aggregation;
      // blocks with neither text nor signature are still skipped. Only apply
      // text-based dedup to non-empty text so distinct signature-only blocks
      // are not collapsed by an empty-string collision.
      if (text.isEmpty && !hasSignature) {
        continue;
      }
      if (text.isNotEmpty && !seen.add(text)) {
        continue;
      }
      parts.add(
        Part.text(text, thought: true).copyWith(
          thoughtSignature: hasSignature ? utf8.encode('$signature') : null,
        ),
      );
    }
    return parts;
  }

  void addThought(Object? value) {
    if (value is! String) {
      return;
    }
    final String text = value.trim();
    if (text.isEmpty || !seen.add(text)) {
      return;
    }
    parts.add(Part.text(text, thought: true));
  }

  if (raw is String) {
    addThought(raw);
    return parts;
  }
  if (raw is List) {
    for (final Object? item in raw) {
      if (item is Map) {
        addThought(item['text']);
        addThought(item['content']);
      } else {
        addThought(item);
      }
    }
    return parts;
  }
  if (raw is Map) {
    addThought(raw['text']);
    addThought(raw['content']);
  }
  return parts;
}

/// Aggregates fragmented streaming thought parts into clean individual parts.
///
/// During streaming, Anthropic splits a thinking block across many deltas:
/// text-only chunks followed by a signature-only chunk at `block_stop`. This
/// helper joins the text chunks and attaches the signature, producing clean
/// individual thought parts for session history and outbound requests.
List<Part> _aggregateStreamingThoughtParts(Iterable<Part> thoughtParts) {
  final List<Part> partsList = thoughtParts.toList(growable: false);
  if (partsList.isEmpty) {
    return const <Part>[];
  }
  final List<Part> aggregated = <Part>[];
  final List<String> currentTexts = <String>[];
  for (final Part part in partsList) {
    final String? text = part.text;
    if (text != null && text.isNotEmpty) {
      currentTexts.add(text);
    }
    if (part.thoughtSignature != null) {
      aggregated.add(
        Part.text(currentTexts.join(), thought: true).copyWith(
          thoughtSignature: part.thoughtSignature,
        ),
      );
      currentTexts.clear();
    }
  }
  if (currentTexts.isNotEmpty) {
    aggregated.add(Part.text(currentTexts.join(), thought: true));
  }
  return aggregated;
}

/// Merges reasoning text fragments into a single provider payload.
///
/// Streaming providers such as vLLM can emit reasoning as token-sized chunks.
/// ADK stores those chunks as consecutive thought parts, so inserting
/// separators here would change the model's original reasoning text.
String _mergeReasoningTexts(Iterable<Part> reasoningParts) {
  final StringBuffer buffer = StringBuffer();
  for (final Part part in reasoningParts) {
    final String? text = part.text;
    if (text != null && text.isNotEmpty) {
      buffer.write(text);
      continue;
    }
    final InlineData? inlineData = part.inlineData;
    if (inlineData != null &&
        inlineData.data.isNotEmpty &&
        inlineData.mimeType.startsWith('text/')) {
      buffer.write(utf8.decode(inlineData.data, allowMalformed: true));
    }
  }
  return buffer.toString();
}

bool _isThinkingBlocksFormat(Object? value) {
  if (value is! List || value.isEmpty) {
    return false;
  }
  final Object? first = value.first;
  return first is Map && first.containsKey('signature');
}

bool _isAnthropicModel(String model) {
  final String lower = model.toLowerCase();
  if (lower.startsWith('anthropic/')) {
    return true;
  }
  if (lower.startsWith('bedrock/')) {
    final String modelPart = lower.split('/').skip(1).join('/');
    return modelPart.contains('anthropic') || modelPart.contains('claude');
  }
  if (lower.startsWith('vertex_ai/')) {
    final String modelPart = lower.split('/').skip(1).join('/');
    return modelPart.contains('claude');
  }
  return false;
}

List<Map<String, Object?>> _contentToMessages(
  Content content, {
  String model = '',
}) {
  final String role = content.role == 'model' ? 'assistant' : '${content.role}';
  final List<Map<String, Object?>> output = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolResponses = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
  final List<Part> reasoningParts = <Part>[];

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
      final Map<String, Object?> toolCall = <String, Object?>{
        'id': part.functionCall!.id ?? 'call_${part.functionCall!.name}',
        'type': 'function',
        'function': <String, Object?>{
          'name': part.functionCall!.name,
          'arguments': jsonEncode(part.functionCall!.args),
        },
      };
      final String? thoughtSignature = _encodeThoughtSignature(
        part.thoughtSignature,
      );
      if (thoughtSignature != null) {
        toolCall['provider_specific_fields'] = <String, Object?>{
          'thought_signature': thoughtSignature,
        };
        toolCall['extra_content'] = <String, Object?>{
          'google': <String, Object?>{'thought_signature': thoughtSignature},
        };
      }
      toolCalls.add(toolCall);
      continue;
    }
    if (part.thought &&
        ((part.text != null && part.text!.isNotEmpty) ||
            part.thoughtSignature != null)) {
      // Collect thought parts that carry text or a signature. Streaming emits
      // signature-only thought parts (empty text) that must be preserved so
      // the signature survives aggregation for Anthropic outbound requests.
      reasoningParts.add(part);
      continue;
    }
    if (part.text != null && part.text!.isNotEmpty) {
      parts.add(<String, Object?>{'type': 'text', 'text': part.text});
      continue;
    }
    if (part.inlineData != null) {
      final String mimeType = part.inlineData!.mimeType;
      final String encodedData = base64Encode(part.inlineData!.data);
      if (_isAudioMimeType(mimeType)) {
        parts.add(<String, Object?>{
          'type': 'input_audio',
          'input_audio': <String, Object?>{
            'data': encodedData,
            'format': _audioFormatFromMimeType(mimeType),
          },
        });
      } else {
        parts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': 'data:$mimeType;base64,$encodedData',
          },
        });
      }
    } else if (part.fileData != null && part.fileData!.fileUri.isNotEmpty) {
      final String mimeType = part.fileData!.mimeType ?? '';
      final String provider = LiteLlm.getProviderFromModel(model);
      if (_isAudioMimeType(mimeType) &&
          (provider == 'openai' || provider == 'azure')) {
        parts.add(<String, Object?>{
          'type': 'text',
          'text': '[File reference: "${part.fileData!.fileUri}"]',
        });
      } else {
        parts.add(<String, Object?>{
          'type': 'file_url',
          'file_url': <String, Object?>{'url': part.fileData!.fileUri},
        });
      }
    }
  }

  if (toolResponses.isNotEmpty) {
    return toolResponses;
  }

  final Map<String, Object?> message = <String, Object?>{'role': role};
  if (_isAnthropicModel(model) && reasoningParts.isNotEmpty) {
    // Streaming splits one Anthropic thinking block across many deltas:
    // text-only chunks followed by a signature-only chunk at block_stop.
    // Aggregate them back into one thinking block for outbound.
    final List<Part> aggregatedParts = _aggregateStreamingThoughtParts(
      reasoningParts,
    );
    final List<Map<String, Object?>> thinkingBlocks = aggregatedParts
        .where(
          (Part part) =>
              part.thoughtSignature != null &&
              part.text != null &&
              part.text!.isNotEmpty,
        )
        .map(
          (Part part) => <String, Object?>{
            'type': 'thinking',
            'thinking': part.text!,
            'signature': utf8.decode(part.thoughtSignature!),
          },
        )
        .toList(growable: false);
    if (thinkingBlocks.isNotEmpty) {
      message['thinking_blocks'] = thinkingBlocks;
    } else {
      final String reasoningText = _mergeReasoningTexts(reasoningParts);
      if (reasoningText.isNotEmpty) {
        message['reasoning_content'] = reasoningText;
      }
    }
  } else if (reasoningParts.isNotEmpty) {
    final String reasoningText = _mergeReasoningTexts(reasoningParts);
    if (reasoningText.isNotEmpty) {
      message['reasoning_content'] = reasoningText;
    }
  }
  if (toolCalls.isNotEmpty) {
    message['tool_calls'] = toolCalls;
    if (parts.isEmpty) {
      message['content'] = null;
    }
  }
  if (parts.isNotEmpty) {
    if (parts.length == 1 && parts.first['type'] == 'text') {
      message['content'] = parts.first['text'];
    } else {
      message['content'] = parts;
    }
  }
  output.add(message);
  return output;
}

bool _isAudioMimeType(String mimeType) {
  return mimeType.trim().toLowerCase().startsWith('audio/');
}

String _audioFormatFromMimeType(String mimeType) {
  final String normalized = mimeType.split(';').first.trim().toLowerCase();
  final String subtype = normalized.contains('/')
      ? normalized.split('/').last
      : normalized;
  switch (subtype) {
    case 'mpeg':
    case 'mp3':
      return 'mp3';
    case 'wav':
    case 'wave':
    case 'x-wav':
    case 'vnd.wave':
      return 'wav';
    default:
      return subtype.startsWith('x-') ? subtype.substring(2) : subtype;
  }
}

Part _parseFunctionCall(Map<String, Object?> callMap) {
  final Map<String, Object?> function = _asMap(callMap['function']);
  final String name = '${function['name'] ?? ''}';
  final String argumentsRaw = '${function['arguments'] ?? '{}'}';
  Map<String, dynamic> parsedArgs = <String, dynamic>{};
  try {
    final Object? decoded = jsonDecode(argumentsRaw);
    if (decoded is Map) {
      parsedArgs = decoded.cast<String, dynamic>();
    }
  } catch (_) {
    parsedArgs = <String, dynamic>{};
  }
  final String? callId = callMap['id'] == null ? null : '${callMap['id']}';
  final Part part = Part.fromFunctionCall(
    name: name,
    args: parsedArgs,
    id: callId,
  );
  final List<int>? thoughtSignature = _extractThoughtSignatureFromToolCall(
    callMap,
  );
  if (thoughtSignature == null) {
    return part;
  }
  return part.copyWith(thoughtSignature: thoughtSignature);
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, Object?> _toLiteLlmResponseFormat(
  Map<String, Object?> responseSchema,
  String model,
) {
  final String? schemaType = responseSchema['type'] is String
      ? '${responseSchema['type']}'.toLowerCase()
      : null;
  if (schemaType == 'json_object' || schemaType == 'json_schema') {
    return responseSchema;
  }

  if (_isLiteLlmGeminiModel(model)) {
    return <String, Object?>{
      'type': 'json_object',
      'response_schema': responseSchema,
    };
  }

  _enforceStrictOpenAiSchema(responseSchema);
  final String schemaName =
      responseSchema['title'] is String &&
          (responseSchema['title'] as String).isNotEmpty
      ? responseSchema['title'] as String
      : 'response';
  return <String, Object?>{
    'type': 'json_schema',
    'json_schema': <String, Object?>{
      'name': schemaName,
      'strict': true,
      'schema': responseSchema,
    },
  };
}

bool _isLiteLlmGeminiModel(String model) {
  final String normalized = model.toLowerCase();
  return normalized.startsWith('gemini/gemini-') ||
      normalized.startsWith('vertex_ai/gemini-');
}

void _enforceStrictOpenAiSchema(Map<String, Object?> schema) {
  if (schema.containsKey(r'$ref')) {
    schema.removeWhere((String key, Object? _) => key != r'$ref');
    return;
  }

  final Object? schemaType = schema['type'];
  final Map<String, Object?>? properties = _asObjectMap(schema['properties']);
  final bool isObject =
      schemaType == 'object' ||
      (schemaType is List && schemaType.contains('object'));
  if (isObject && properties != null) {
    schema['additionalProperties'] = false;
    final List<String> required = properties.keys.toList()..sort();
    schema['required'] = required;
  }

  final Map<String, Object?>? defs = _asObjectMap(schema[r'$defs']);
  if (defs != null) {
    for (final MapEntry<String, Object?> entry in defs.entries) {
      final Map<String, Object?>? defSchema = _asObjectMap(entry.value);
      if (defSchema != null) {
        defs[entry.key] = defSchema;
        _enforceStrictOpenAiSchema(defSchema);
      }
    }
  }

  if (properties != null) {
    for (final MapEntry<String, Object?> entry in properties.entries) {
      final Map<String, Object?>? propertySchema = _asObjectMap(entry.value);
      if (propertySchema != null) {
        properties[entry.key] = propertySchema;
        _enforceStrictOpenAiSchema(propertySchema);
      }
    }
  }

  for (final String key in <String>['anyOf', 'oneOf', 'allOf']) {
    final Object? combinator = schema[key];
    if (combinator is! List) {
      continue;
    }
    for (int i = 0; i < combinator.length; i += 1) {
      final Map<String, Object?>? itemSchema = _asObjectMap(combinator[i]);
      if (itemSchema != null) {
        combinator[i] = itemSchema;
        _enforceStrictOpenAiSchema(itemSchema);
      }
    }
  }

  final Map<String, Object?>? items = _asObjectMap(schema['items']);
  if (items != null) {
    schema['items'] = items;
    _enforceStrictOpenAiSchema(items);
  }
}

Map<String, Object?> _deepCopyJsonMap(Map<String, Object?> source) {
  return _deepCopyJsonValue(source) as Map<String, Object?>;
}

Object? _deepCopyJsonValue(Object? value) {
  if (value is Map) {
    final Map<String, Object?> copied = <String, Object?>{};
    value.forEach((Object? key, Object? nested) {
      copied['$key'] = _deepCopyJsonValue(nested);
    });
    return copied;
  }
  if (value is List) {
    return value
        .map((Object? item) => _deepCopyJsonValue(item))
        .toList(growable: false);
  }
  return value;
}

Map<String, Object?>? _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return null;
}

String? _encodeThoughtSignature(List<int>? thoughtSignature) {
  if (thoughtSignature == null || thoughtSignature.isEmpty) {
    return null;
  }
  return base64Encode(thoughtSignature);
}

List<int>? _extractThoughtSignatureFromToolCall(Map<String, Object?> toolCall) {
  final Map<String, Object?> extraContent = _asMap(toolCall['extra_content']);
  final Map<String, Object?> googleExtra = _asMap(extraContent['google']);
  final List<int>? fromExtra = _decodeThoughtSignature(
    googleExtra['thought_signature'],
  );
  if (fromExtra != null) {
    return fromExtra;
  }

  final Map<String, Object?> providerFields = _asMap(
    toolCall['provider_specific_fields'],
  );
  final List<int>? fromProvider = _decodeThoughtSignature(
    providerFields['thought_signature'],
  );
  if (fromProvider != null) {
    return fromProvider;
  }

  final Map<String, Object?> function = _asMap(toolCall['function']);
  final Map<String, Object?> functionProviderFields = _asMap(
    function['provider_specific_fields'],
  );
  final List<int>? fromFunctionProvider = _decodeThoughtSignature(
    functionProviderFields['thought_signature'],
  );
  if (fromFunctionProvider != null) {
    return fromFunctionProvider;
  }

  final String? toolCallId = toolCall['id'] == null
      ? null
      : '${toolCall['id']}';
  if (toolCallId != null && toolCallId.contains(_thoughtSignatureSeparator)) {
    final List<String> parts = toolCallId.split(_thoughtSignatureSeparator);
    if (parts.length >= 2) {
      return _decodeThoughtSignature(
        parts.sublist(1).join(_thoughtSignatureSeparator),
      );
    }
  }

  return null;
}

List<int>? _decodeThoughtSignature(Object? value) {
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    final List<int> bytes = <int>[];
    for (final Object? item in value) {
      if (item is num) {
        bytes.add(item.toInt());
      }
    }
    return bytes.isEmpty ? null : bytes;
  }
  if (value is! String || value.isEmpty) {
    return null;
  }
  try {
    return base64Decode(value);
  } catch (_) {
    try {
      return base64Url.decode(base64Url.normalize(value));
    } catch (_) {
      return null;
    }
  }
}
