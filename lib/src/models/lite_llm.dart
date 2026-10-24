import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../platform/uuid.dart';
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
  String toString() =>
      'LiteLlmException: $message${uri != null ? ' (uri: $uri)' : ''}';
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
///
/// ```dart
/// final model = LiteLlm(
///   model: 'openai/gpt-4o-mini',
///   baseUrl: 'https://api.openai.com/v1',
/// );
/// final agent = LlmAgent(
///   name: 'litellm_agent',
///   model: model,
///   instruction: 'Provide concise answers.',
/// );
/// ```
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
    String? baseUrl,
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
      messages.addAll(
        _contentToMessages(
          content,
          model: request.model ?? '',
          baseUrl: baseUrl,
        ),
      );
    }
    final List<Map<String, Object?>> normalizedMessages = _ensureToolResults(
      messages,
      model: request.model ?? '',
      baseUrl: baseUrl,
    );

    final Map<String, Object?> payload = <String, Object?>{
      'model': request.model ?? '',
      'messages': normalizedMessages,
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
    if (request.config.topK != null) {
      payload['top_k'] = request.config.topK;
    }
    _applyThinkingConfigToPayload(
      payload,
      request.config.thinkingConfig,
      model: request.model ?? '',
    );
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
          for (final FunctionDeclaration declaration
              in tool.functionDeclarations) {
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
              'google_search_retrieval': _deepCopyJsonValue(
                tool.googleSearchRetrieval,
              ),
            if (tool.codeExecution != null)
              'code_execution': _deepCopyJsonValue(tool.codeExecution),
            if (tool.googleMaps != null)
              'google_maps': _deepCopyJsonValue(tool.googleMaps),
            if (tool.enterpriseWebSearch != null)
              'enterprise_web_search': _deepCopyJsonValue(
                tool.enterpriseWebSearch,
              ),
            if (tool.computerUse != null)
              'computer_use': _deepCopyJsonValue(tool.computerUse),
            if (tool.googleSearch != null)
              'googleSearch': _deepCopyJsonValue(tool.googleSearch),
            if (tool.googleSearchRetrieval != null)
              'googleSearchRetrieval': _deepCopyJsonValue(
                tool.googleSearchRetrieval,
              ),
            if (tool.codeExecution != null)
              'codeExecution': _deepCopyJsonValue(tool.codeExecution),
            if (tool.googleMaps != null)
              'googleMaps': _deepCopyJsonValue(tool.googleMaps),
            if (tool.enterpriseWebSearch != null)
              'enterpriseWebSearch': _deepCopyJsonValue(
                tool.enterpriseWebSearch,
              ),
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
  static LlmResponse parseCompletionResponse(
    Map<String, Object?> response, {
    bool parseInlineToolCalls = true,
    bool allowBareJson = true,
  }) {
    final List<Object?> choices =
        (response['choices'] as List<Object?>?) ?? <Object?>[];
    final Map<String, Object?> usage = _asMap(response['usage']);
    final int? cachedTokenCount = _extractCachedTokens(usage);
    final int? cacheCreationTokenCount = _extractCacheCreationTokens(usage);
    if (choices.isEmpty) {
      if (usage.isNotEmpty) {
        return LlmResponse(
          modelVersion: response['model'] as String?,
          usageMetadata: <String, Object?>{
            'prompt_token_count': usage['prompt_tokens'] ?? 0,
            'candidates_token_count': usage['completion_tokens'] ?? 0,
            'total_token_count': usage['total_tokens'] ?? 0,
            if (_reasoningTokens(usage) != null)
              'thoughts_token_count': _reasoningTokens(usage),
            'cached_content_token_count': ?cachedTokenCount,
            'cache_creation_input_tokens': ?cacheCreationTokenCount,
          },
          cacheCreationTokenCount: cacheCreationTokenCount,
        );
      }
      return LlmResponse();
    }
    if (choices.length > 1) {
      developer.log(
        'Multiple choices found in response but only the first one will be used.',
        name: 'adk_dart.models.lite_llm',
        level: 1000,
      );
    }
    final Map<String, Object?> first = _asMap(choices.first);
    final Map<String, Object?> message = _asMap(first['message']);
    final Map<String, Object?> delta = _asMap(first['delta']);
    final Map<String, Object?> effectiveMessage = message.isNotEmpty
        ? message
        : delta;
    final String role = effectiveMessage['role'] == 'assistant'
        ? 'model'
        : '${effectiveMessage['role'] ?? 'model'}';
    final List<Part> parts = <Part>[];
    final Set<String> reasoningTexts = <String>{};
    for (final String field in const <String>[
      'thinking_blocks',
      'reasoning_content',
      'reasoning',
    ]) {
      parts.addAll(
        _extractReasoningParts(
          effectiveMessage[field],
          reasoningTexts: reasoningTexts,
        ),
      );
    }
    final (Object? contentRaw, List<Object?> toolCalls) =
        _splitMessageContentAndToolCalls(
          effectiveMessage,
          parseInlineToolCalls: parseInlineToolCalls,
          allowBareJson: allowBareJson,
        );
    if (contentRaw is String && contentRaw.isNotEmpty) {
      parts.add(Part.text(contentRaw));
    }

    for (final Object? call in toolCalls) {
      final Map<String, Object?> callMap = _asMap(call);
      parts.add(_parseFunctionCall(callMap));
    }

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
        'cached_content_token_count': ?cachedTokenCount,
        'cache_creation_input_tokens': ?cacheCreationTokenCount,
      },
      cacheCreationTokenCount: cacheCreationTokenCount,
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

    final LiteLlmCompletionsInvoker invoker =
        completionsInvoker ?? _defaultHttpCompletionsInvoker;

    final List<Map<String, Object?>> responses = await invoker(
      payload: buildPayload(prepared, stream: stream, baseUrl: baseUrl),
      stream: stream,
    );
    final bool filterThoughts = _shouldFilterThoughts(
      prepared.config.thinkingConfig,
    );
    bool multipleChoicesLogged = false;
    final Map<int, List<int>> pendingToolSignatures = <int, List<int>>{};
    final _StreamTextTracker textTracker = _StreamTextTracker();
    final List<String> rawStreamTexts = <String>[];
    bool sawStructuredToolCalls = false;
    bool emittedInlineToolCalls = false;
    String? lastStreamModel;
    String? lastStreamFinishReason;
    for (final Map<String, Object?> response in responses) {
      if (stream) {
        if (response['model'] is String) {
          lastStreamModel = response['model'] as String;
        }
        final List<Object?> choices =
            (response['choices'] as List<Object?>?) ?? <Object?>[];
        if (!multipleChoicesLogged &&
            (choices.length > 1 ||
                choices.any((Object? c) {
                  final Object? idx = _asMap(c)['index'];
                  return idx != null && idx != 0;
                }))) {
          multipleChoicesLogged = true;
          developer.log(
            'Multiple choices found in streaming response but only the first one will be used.',
            name: 'adk_dart.models.lite_llm',
            level: 1000,
          );
        }
        final List<Object?> filteredChoices = choices
            .where((Object? c) {
              final Object? idx = _asMap(c)['index'];
              return idx == null || idx == 0;
            })
            .toList(growable: false);
        if (choices.isNotEmpty && filteredChoices.isEmpty) {
          continue;
        }
        final Map<String, Object?> modified = choices.isEmpty
            ? response
            : <String, Object?>{...response, 'choices': filteredChoices};
        final Map<String, Object?> firstChoice = filteredChoices.isNotEmpty
            ? _asMap(filteredChoices.first)
            : const <String, Object?>{};
        if (firstChoice['finish_reason'] != null) {
          lastStreamFinishReason = '${firstChoice['finish_reason']}';
        }
        final Map<String, Object?> msg = _asMap(firstChoice['message']);
        final Map<String, Object?> dlt = _asMap(firstChoice['delta']);
        final Map<String, Object?> eff = msg.isNotEmpty ? msg : dlt;
        final List<Object?> existingCalls =
            (eff['tool_calls'] as List<Object?>?) ?? const <Object?>[];
        if (existingCalls.isNotEmpty || eff['function_call'] != null) {
          sawStructuredToolCalls = true;
        }
        final String deltaText = eff['content'] is String
            ? eff['content'] as String
            : '';
        final bool parseInlineToolCalls = !(textTracker.inCode ||
            textTracker.inThink ||
            (deltaText.isNotEmpty &&
                (deltaText.contains('`') ||
                    deltaText.contains('~') ||
                    textTracker.inThinkFor(deltaText) ||
                    textTracker.completesLine(deltaText))));
        final bool allowBareJson = !textTracker.hasNonWhitespace;
        if (deltaText.isNotEmpty) {
          rawStreamTexts.add(deltaText);
          textTracker.feed(deltaText);
        }
        final LlmResponse parsed = _parseStreamCompletionChunk(
          modified,
          pendingToolSignatures: pendingToolSignatures,
          parseInlineToolCalls: parseInlineToolCalls,
          allowBareJson: allowBareJson,
        );
        if (!sawStructuredToolCalls &&
            parsed.content != null &&
            parsed.content!.parts.any((Part p) => p.functionCall != null)) {
          emittedInlineToolCalls = true;
        }
        if (filterThoughts) {
          _filterThoughtParts(parsed);
          if ((parsed.content == null || parsed.content!.parts.isEmpty) &&
              parsed.finishReason == 'OTHER' &&
              _asMap(modified['usage']).isEmpty) {
            continue;
          }
        }
        yield parsed;
      } else {
        final LlmResponse parsed = parseCompletionResponse(response);
        if (filterThoughts) {
          _filterThoughtParts(parsed);
        }
        yield parsed;
      }
    }
    if (stream &&
        !sawStructuredToolCalls &&
        !emittedInlineToolCalls &&
        rawStreamTexts.isNotEmpty) {
      final (List<Map<String, Object?>> heldBackCalls, String? remainder) =
          parseToolCallsFromText(rawStreamTexts.join());
      if (heldBackCalls.isNotEmpty) {
        final List<Part> finalParts = <Part>[
          if (remainder != null && remainder.isNotEmpty) Part.text(remainder),
          for (final Map<String, Object?> callMap in heldBackCalls)
            _parseFunctionCall(callMap),
        ];
        yield LlmResponse(
          modelVersion: lastStreamModel,
          content: Content(role: 'model', parts: finalParts),
          finishReason: mapFinishReason(lastStreamFinishReason ?? 'stop'),
        );
      }
    }
  }

  Future<List<Map<String, Object?>>> _defaultHttpCompletionsInvoker({
    required Map<String, Object?> payload,
    required bool stream,
  }) async {
    final Map<String, String> env = readSystemEnvironment();
    final String resolvedBaseUrl =
        baseUrl ??
        env['LITELLM_API_BASE'] ??
        env['OLLAMA_API_BASE'] ??
        env['OPENAI_API_BASE'] ??
        'http://localhost:4000/v1';

    final String resolvedApiKey =
        apiKey ??
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
      final http.StreamedResponse streamedResponse = await client.send(
        httpRequest,
      );

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
            final Map<String, Object?> parsed =
                jsonDecode(dataContent) as Map<String, Object?>;
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

      final Map<String, Object?> data =
          jsonDecode(response.body) as Map<String, Object?>;
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

int? _asNullableInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    return int.tryParse(raw.trim());
  }
  return null;
}

int? _extractCachedTokens(Map<String, Object?> usage) {
  for (final String key in const <String>[
    'cache_read_input_tokens',
    'cacheReadInputTokens',
  ]) {
    final int? value = _asNullableInt(usage[key]);
    if (value != null) {
      return value;
    }
  }
  final Map<String, Object?> details = _asMap(
    usage['prompt_tokens_details'] ?? usage['promptTokensDetails'],
  );
  for (final String key in const <String>[
    'cached_tokens',
    'cachedTokens',
    'cache_read_input_tokens',
    'cacheReadInputTokens',
  ]) {
    final int? value = _asNullableInt(details[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

int? _extractCacheCreationTokens(Map<String, Object?> usage) {
  for (final String key in const <String>[
    'cache_creation_input_tokens',
    'cacheCreationInputTokens',
    'cache_write_input_tokens',
    'cacheWriteInputTokens',
  ]) {
    final int? value = _asNullableInt(usage[key]);
    if (value != null) {
      return value;
    }
  }
  final Map<String, Object?> details = _asMap(
    usage['prompt_tokens_details'] ?? usage['promptTokensDetails'],
  );
  for (final String key in const <String>[
    'cache_creation_tokens',
    'cacheCreationTokens',
    'cache_creation_input_tokens',
    'cacheCreationInputTokens',
  ]) {
    final int? value = _asNullableInt(details[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
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
      final bool hasSignature = signature != null && '$signature'.isNotEmpty;
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
        Part.text(
          currentTexts.join(),
          thought: true,
        ).copyWith(thoughtSignature: part.thoughtSignature),
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

bool _isGemma4Model(String model, {String? baseUrl}) {
  final String lower = model.toLowerCase();
  if (!lower.contains('gemma-4') && !lower.contains('gemma4')) {
    return false;
  }
  final String provider = LiteLlm.getProviderFromModel(model);
  if (provider == 'openai' || provider == 'azure' || provider == 'lm_studio') {
    return false;
  }
  if (baseUrl != null && baseUrl.isNotEmpty) {
    return false;
  }
  return true;
}

String _toolResponseRoleForModel(String model, {String? baseUrl}) {
  return _isGemma4Model(model, baseUrl: baseUrl) ? 'tool_responses' : 'tool';
}

const String _missingToolResultContent =
    '{"error": "Tool execution was interrupted before a result was returned."}';

List<Map<String, Object?>> _ensureToolResults(
  List<Map<String, Object?>> messages, {
  String model = '',
  String? baseUrl,
}) {
  if (messages.isEmpty) {
    return messages;
  }
  final String toolRole = _toolResponseRoleForModel(model, baseUrl: baseUrl);
  final List<Map<String, Object?>> repaired = <Map<String, Object?>>[];
  int i = 0;
  while (i < messages.length) {
    final Map<String, Object?> msg = messages[i];
    repaired.add(msg);
    final Object? rawToolCalls = msg['tool_calls'];
    if (msg['role'] != 'assistant' ||
        rawToolCalls is! List ||
        rawToolCalls.isEmpty) {
      i += 1;
      continue;
    }

    int j = i + 1;
    final Set<String> answeredIds = <String>{};
    while (j < messages.length) {
      final Object? nextRole = messages[j]['role'];
      if (nextRole != 'tool' && nextRole != 'tool_responses') {
        break;
      }
      final Object? callId = messages[j]['tool_call_id'];
      if (callId is String && callId.isNotEmpty) {
        answeredIds.add(callId);
      }
      repaired.add(messages[j]);
      j += 1;
    }

    if (j < messages.length || answeredIds.isNotEmpty) {
      for (final Object? tc in rawToolCalls) {
        final Map<String, Object?> tcMap = _asMap(tc);
        final String? tcId = tcMap['id'] == null ? null : '${tcMap['id']}';
        if (tcId != null && tcId.isNotEmpty && !answeredIds.contains(tcId)) {
          repaired.add(<String, Object?>{
            'role': toolRole,
            'tool_call_id': tcId,
            'content': _missingToolResultContent,
          });
        }
      }
    }
    i = j;
  }
  return repaired;
}

List<Map<String, Object?>> _contentToMessages(
  Content content, {
  String model = '',
  String? baseUrl,
}) {
  final String role = content.role == 'model' ? 'assistant' : '${content.role}';
  final String toolRole = _toolResponseRoleForModel(model, baseUrl: baseUrl);
  final List<Map<String, Object?>> output = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolResponses = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
  final List<Part> reasoningParts = <Part>[];

  for (final Part part in content.parts) {
    if (part.functionResponse != null) {
      toolResponses.add(<String, Object?>{
        'role': toolRole,
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
      if (mimeType.isEmpty || mimeType == 'application/octet-stream') {
        final String typeLabel = mimeType.isEmpty ? '(unknown)' : mimeType;
        final String redactedFileUri = redactFileUriForLog(
          part.fileData!.fileUri,
          displayName: part.fileData!.displayName,
        );
        throw ArgumentError(
          "Cannot process file_uri '$redactedFileUri': MIME type "
          "'$typeLabel' is not supported. Please set a specific MIME "
          "type on `file_data.mime_type`.",
        );
      }
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
    if (role == 'assistant') {
      final List<String> textBlocks = <String>[
        for (final Map<String, Object?> block in parts)
          if (block['type'] == 'text' && block['text'] is String)
            block['text'] as String,
      ];
      if (textBlocks.isNotEmpty && textBlocks.length == parts.length) {
        message['content'] = textBlocks.join('\n');
      } else if (parts.length == 1 && parts.first['type'] == 'text') {
        message['content'] = parts.first['text'];
      } else {
        message['content'] = parts;
      }
    } else if (parts.length == 1 && parts.first['type'] == 'text') {
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

final RegExp _markdownCodeBlockPattern = RegExp(
  r'^\s*```(?:json)?\s*(.*?)\s*```\s*$',
  dotAll: true,
);

String _quoteUnquotedJsonObjectKeys(String rawArguments) {
  final StringBuffer result = StringBuffer();
  bool inString = false;
  String quoteChar = '';
  bool escaped = false;
  bool expectingKey = false;
  final int length = rawArguments.length;
  int i = 0;

  while (i < length) {
    final String ch = rawArguments[i];
    if (inString) {
      result.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == quoteChar) {
        inString = false;
      }
      i += 1;
      continue;
    }

    if (ch == '"' || ch == "'") {
      inString = true;
      quoteChar = ch;
      expectingKey = false;
      result.write(ch);
      i += 1;
      continue;
    }

    if (ch == '{' || ch == ',') {
      expectingKey = true;
      result.write(ch);
      i += 1;
      continue;
    }

    if (expectingKey) {
      if (ch.trim().isEmpty) {
        result.write(ch);
        i += 1;
        continue;
      }
      if (ch == '}') {
        expectingKey = false;
        result.write(ch);
        i += 1;
        continue;
      }
      if (_isIdentifierStart(ch)) {
        int j = i + 1;
        while (j < length && _isIdentifierContinuation(rawArguments[j])) {
          j += 1;
        }
        int k = j;
        while (k < length && rawArguments[k].trim().isEmpty) {
          k += 1;
        }
        if (k < length && rawArguments[k] == ':') {
          final String key = rawArguments.substring(i, j);
          result.write('"$key"');
          result.write(rawArguments.substring(j, k));
          result.write(':');
          expectingKey = false;
          i = k + 1;
          continue;
        }
      }
      expectingKey = false;
    }

    result.write(ch);
    i += 1;
  }

  return result.toString();
}

bool _isIdentifierStart(String ch) {
  final int code = ch.codeUnitAt(0);
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      ch == '_' ||
      ch == r'$';
}

bool _isIdentifierContinuation(String ch) {
  final int code = ch.codeUnitAt(0);
  return _isIdentifierStart(ch) ||
      (code >= 48 && code <= 57) ||
      ch == '-' ||
      ch == '.';
}

Map<String, dynamic> _parseToolCallArguments(Object? rawArgs, String toolName) {
  if (rawArgs == null) {
    return <String, dynamic>{};
  }
  if (rawArgs is Map) {
    return rawArgs.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  if (rawArgs is! String) {
    return <String, dynamic>{};
  }
  String cleaned = rawArgs.trim();
  if (cleaned.isEmpty) {
    return <String, dynamic>{};
  }
  final RegExpMatch? fenceMatch = _markdownCodeBlockPattern.firstMatch(cleaned);
  if (fenceMatch != null) {
    cleaned = (fenceMatch.group(1) ?? '').trim();
  }
  final String quotedKeys = _quoteUnquotedJsonObjectKeys(cleaned);
  for (final String candidate in <String>[
    cleaned,
    quotedKeys,
    _normalizePythonLiteralJson(quotedKeys),
  ]) {
    try {
      final Object? decoded = jsonDecode(candidate);
      if (decoded is Map) {
        return decoded.map((Object? k, Object? v) => MapEntry('$k', v));
      }
    } catch (_) {
      // Try next fallback candidate.
    }
  }
  developer.log(
    "Malformed JSON in tool call arguments for function '$toolName'; dispatching with empty arguments so the tool can return a structured error and the model can retry.",
    name: 'adk_dart.models.lite_llm',
    level: 900,
  );
  return <String, dynamic>{};
}

String _normalizePythonLiteralJson(String input) {
  final StringBuffer out = StringBuffer();
  bool inDouble = false;
  bool inSingle = false;
  bool escaped = false;
  for (int i = 0; i < input.length; i += 1) {
    final String ch = input[i];
    if (inDouble) {
      out.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inDouble = false;
      }
      continue;
    }
    if (inSingle) {
      if (escaped) {
        if (ch == "'") {
          out.write("'");
        } else {
          out.write(r'\');
          out.write(ch);
        }
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == "'") {
        out.write('"');
        inSingle = false;
      } else if (ch == '"') {
        out.write(r'\"');
      } else {
        out.write(ch);
      }
      continue;
    }
    if (ch == '"') {
      inDouble = true;
      out.write(ch);
      continue;
    }
    if (ch == "'") {
      inSingle = true;
      out.write('"');
      continue;
    }
    out.write(ch);
  }
  String normalized = out.toString();
  normalized = normalized.replaceAllMapped(
    RegExp(r'(?<=[:,\[\s])(True|False|None)(?=[,}\]\s])'),
    (Match m) {
      switch (m.group(1)) {
        case 'True':
          return 'true';
        case 'False':
          return 'false';
        default:
          return 'null';
      }
    },
  );
  normalized = normalized.replaceAllMapped(
    RegExp(r',\s*([}\]])'),
    (Match m) => m.group(1)!,
  );
  return normalized;
}

Part _parseFunctionCall(
  Map<String, Object?> callMap, {
  Map<int, List<int>>? pendingToolSignatures,
  int fallbackIndex = 0,
}) {
  final Map<String, Object?> function = _asMap(callMap['function']);
  final String name = '${function['name'] ?? ''}';
  final Map<String, dynamic> parsedArgs = _parseToolCallArguments(
    function['arguments'],
    name,
  );
  final String? callId = callMap['id'] == null ? null : '${callMap['id']}';
  final int callIndex = callMap['index'] is num
      ? (callMap['index'] as num).toInt()
      : fallbackIndex;
  final List<int>? extractedSignature = _extractThoughtSignatureFromToolCall(
    callMap,
  );
  if (name.isEmpty &&
      (function['arguments'] == null || '${function['arguments']}'.isEmpty) &&
      extractedSignature != null &&
      pendingToolSignatures != null) {
    pendingToolSignatures[callIndex] = extractedSignature;
  }
  final List<int>? thoughtSignature =
      extractedSignature ?? pendingToolSignatures?.remove(callIndex);
  final Part part = Part.fromFunctionCall(
    name: name,
    args: parsedArgs,
    id: callId,
  );
  if (thoughtSignature == null) {
    return part;
  }
  return part.copyWith(thoughtSignature: thoughtSignature);
}

LlmResponse _parseStreamCompletionChunk(
  Map<String, Object?> response, {
  required Map<int, List<int>> pendingToolSignatures,
  bool parseInlineToolCalls = true,
  bool allowBareJson = true,
}) {
  final List<Object?> choices =
      (response['choices'] as List<Object?>?) ?? <Object?>[];
  if (choices.isEmpty) {
    return LiteLlm.parseCompletionResponse(
      response,
      parseInlineToolCalls: parseInlineToolCalls,
      allowBareJson: allowBareJson,
    );
  }
  final Map<String, Object?> first = _asMap(choices.first);
  final Map<String, Object?> message = _asMap(first['message']);
  final Map<String, Object?> delta = _asMap(first['delta']);
  final Map<String, Object?> effectiveMessage = message.isNotEmpty
      ? message
      : delta;
  final List<Object?> toolCalls =
      (effectiveMessage['tool_calls'] as List<Object?>?) ?? <Object?>[];
  if (toolCalls.isEmpty) {
    return LiteLlm.parseCompletionResponse(
      response,
      parseInlineToolCalls: parseInlineToolCalls,
      allowBareJson: allowBareJson,
    );
  }
  final List<Object?> filteredToolCalls = <Object?>[];
  for (int i = 0; i < toolCalls.length; i += 1) {
    final Map<String, Object?> callMap = _asMap(toolCalls[i]);
    final Map<String, Object?> fn = _asMap(callMap['function']);
    final String name = '${fn['name'] ?? ''}';
    final String args = '${fn['arguments'] ?? ''}';
    final int idx = callMap['index'] is num
        ? (callMap['index'] as num).toInt()
        : i;
    final List<int>? sig = _extractThoughtSignatureFromToolCall(callMap);
    if (name.isEmpty && args.isEmpty) {
      if (sig != null) {
        pendingToolSignatures[idx] = sig;
      }
      continue;
    }
    if (sig == null && pendingToolSignatures.containsKey(idx)) {
      final String encoded = base64Encode(pendingToolSignatures.remove(idx)!);
      filteredToolCalls.add(<String, Object?>{
        ...callMap,
        'provider_specific_fields': <String, Object?>{
          ..._asMap(callMap['provider_specific_fields']),
          'thought_signature': encoded,
        },
      });
    } else {
      if (sig != null) {
        pendingToolSignatures.remove(idx);
      }
      filteredToolCalls.add(callMap);
    }
  }
  final Map<String, Object?> patchedMessage = <String, Object?>{
    ...effectiveMessage,
    'tool_calls': filteredToolCalls,
  };
  final Map<String, Object?> patchedFirst = <String, Object?>{
    ...first,
    if (message.isNotEmpty) 'message': patchedMessage else 'delta': patchedMessage,
  };
  return LiteLlm.parseCompletionResponse(
    <String, Object?>{
      ...response,
      'choices': <Object?>[patchedFirst],
    },
    parseInlineToolCalls: false,
    allowBareJson: false,
  );
}

const int _anthropicMinThinkingBudgetTokens = 1024;
const Map<String, int> _anthropicEffortBudgets = <String, int>{
  'minimal': _anthropicMinThinkingBudgetTokens,
  'low': 1024,
  'medium': 2048,
  'high': 4096,
};
const List<String> _claude46Substrings = <String>[
  'opus-4-6',
  'opus_4_6',
  'opus-4.6',
  'opus_4.6',
  'sonnet-4-6',
  'sonnet_4_6',
  'sonnet-4.6',
  'sonnet_4.6',
];
const List<String> _claude47Substrings = <String>[
  'opus-4-7',
  'opus_4_7',
  'opus-4.7',
  'opus_4.7',
];
const Map<String, int> _geminiMinThinkingBudgets = <String, int>{
  'gemini-2.5-pro': 128,
  'gemini-2.5-flash-lite': 512,
};

Map<String, Object?>? _thinkingConfigToMap(Object? rawConfig) {
  if (rawConfig == null) {
    return null;
  }
  if (rawConfig is Map) {
    return rawConfig.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }
  final dynamic dyn = rawConfig;
  try {
    final Object? json = dyn.toJson();
    if (json is Map) {
      return json.map(
        (Object? key, Object? value) =>
            MapEntry<String, Object?>('$key', value),
      );
    }
  } catch (_) {}
  final Map<String, Object?> result = <String, Object?>{};
  try {
    final Object? includeThoughts = dyn.includeThoughts;
    if (includeThoughts != null) {
      result['include_thoughts'] = includeThoughts;
    }
  } catch (_) {}
  try {
    final Object? thinkingBudget = dyn.thinkingBudget;
    if (thinkingBudget != null) {
      result['thinking_budget'] = thinkingBudget;
    }
  } catch (_) {}
  try {
    final Object? thinkingLevel = dyn.thinkingLevel;
    if (thinkingLevel != null) {
      result['thinking_level'] = thinkingLevel;
    }
  } catch (_) {}
  return result.isEmpty ? null : result;
}

bool _shouldFilterThoughts(Object? rawThinkingConfig) {
  final Map<String, Object?>? map = _thinkingConfigToMap(rawThinkingConfig);
  if (map == null) {
    return false;
  }
  final Object? includeThoughts =
      map['include_thoughts'] ?? map['includeThoughts'];
  return includeThoughts == false;
}

void _filterThoughtParts(LlmResponse response) {
  final Content? content = response.content;
  if (content == null || content.parts.isEmpty) {
    return;
  }
  final bool hasToolCalls = content.parts.any(
    (Part part) => part.functionCall != null,
  );
  content.parts = <Part>[
    for (final Part part in content.parts)
      if (!part.thought || (hasToolCalls && part.thoughtSignature != null))
        part,
  ];
}

void _dropParamsRejectedByAnthropicThinking(Map<String, Object?> params) {
  final Object? thinking = params['thinking'];
  final Object? reasoningEffort = params['reasoning_effort'];
  final bool thinkingEnabled =
      (reasoningEffort != null && reasoningEffort != 'none') ||
      (thinking is Map &&
          (thinking['type'] == 'enabled' || thinking['type'] == 'adaptive'));
  if (!thinkingEnabled) {
    return;
  }
  if (params['temperature'] != 1 && params['temperature'] != 1.0) {
    params.remove('temperature');
  }
  params.remove('top_k');
  final Object? topP = params['top_p'];
  if (topP is num && topP < 0.95) {
    params.remove('top_p');
  }
}

void _applyThinkingConfigToPayload(
  Map<String, Object?> payload,
  Object? rawThinkingConfig, {
  required String model,
}) {
  final Map<String, Object?>? config = _thinkingConfigToMap(rawThinkingConfig);
  if (config == null || config.isEmpty) {
    return;
  }
  final String lowerModel = model.toLowerCase();
  final bool isAnthropic =
      _isAnthropicModel(model) || lowerModel.contains('claude');
  final bool isClaude47 =
      isAnthropic && _claude47Substrings.any(lowerModel.contains);
  final bool isAdaptiveAnthropic =
      isAnthropic &&
      (isClaude47 || _claude46Substrings.any(lowerModel.contains));
  final bool isGemini = lowerModel.contains('gemini-');
  final bool isGemini3OrNewer = isGemini && lowerModel.contains('gemini-3');
  final int? effectiveMaxTokens =
      (payload['max_completion_tokens'] as int?) ??
      (payload['max_tokens'] as int?);

  final Object? rawLevel =
      config['thinking_level'] ?? config['thinkingLevel'];
  final String? levelStr = rawLevel == null
      ? null
      : '$rawLevel'.split('.').last;
  final Object? rawBudget =
      config['thinking_budget'] ?? config['thinkingBudget'];
  final int? thinkingBudget = rawBudget is num ? rawBudget.toInt() : null;
  final Object? includeThoughts =
      config['include_thoughts'] ?? config['includeThoughts'];

  if (levelStr != null &&
      levelStr.isNotEmpty &&
      levelStr.toUpperCase() != 'THINKING_LEVEL_UNSPECIFIED' &&
      levelStr.toLowerCase() != 'unspecified') {
    final String effort = levelStr.toLowerCase();
    if (isAnthropic && !isAdaptiveAnthropic) {
      final int? effortBudget = _anthropicEffortBudgets[effort];
      if (effectiveMaxTokens != null &&
          effectiveMaxTokens <= _anthropicMinThinkingBudgetTokens) {
        // Skip thinking when max_tokens cannot fit the minimum budget.
      } else if (effort == 'minimal' ||
          (effectiveMaxTokens != null &&
              effortBudget != null &&
              effectiveMaxTokens <= effortBudget)) {
        final int budget =
            (effectiveMaxTokens != null && effortBudget != null)
            ? (effortBudget < effectiveMaxTokens - 1
                  ? effortBudget
                  : effectiveMaxTokens - 1)
            : _anthropicMinThinkingBudgetTokens;
        payload['thinking'] = <String, Object?>{
          'type': 'enabled',
          'budget_tokens': budget,
        };
      } else {
        payload['reasoning_effort'] = effort;
      }
    } else {
      payload['reasoning_effort'] = effort;
    }
  } else if (thinkingBudget == 0) {
    if (!isGemini3OrNewer && (isAnthropic || isGemini)) {
      if (isGemini) {
        if (!lowerModel.contains('gemini-2.5-pro')) {
          payload['thinking'] = <String, Object?>{
            'type': 'enabled',
            'budget_tokens': 0,
          };
        }
      } else {
        payload['thinking'] = <String, Object?>{'type': 'disabled'};
      }
    } else if (isGemini3OrNewer) {
      payload['reasoning_effort'] = 'none';
    }
  } else if (thinkingBudget != null && thinkingBudget > 0) {
    if (!isGemini3OrNewer && !isClaude47 && (isAnthropic || isGemini)) {
      int minBudget = 0;
      if (isAnthropic) {
        minBudget = _anthropicMinThinkingBudgetTokens;
      } else if (isGemini) {
        for (final MapEntry<String, int> entry
            in _geminiMinThinkingBudgets.entries) {
          if (lowerModel.contains(entry.key)) {
            minBudget = entry.value;
            break;
          }
        }
      }
      final int rawBudgetVal =
          thinkingBudget < minBudget ? minBudget : thinkingBudget;
      int? budgetVal = rawBudgetVal;
      if (isAnthropic && effectiveMaxTokens != null) {
        budgetVal = effectiveMaxTokens > _anthropicMinThinkingBudgetTokens
            ? (rawBudgetVal < effectiveMaxTokens - 1
                  ? rawBudgetVal
                  : effectiveMaxTokens - 1)
            : null;
      }
      if (budgetVal != null) {
        payload['thinking'] = <String, Object?>{
          'type': 'enabled',
          'budget_tokens': budgetVal,
        };
      }
    } else {
      if (thinkingBudget <= 1024) {
        payload['reasoning_effort'] = 'low';
      } else if (thinkingBudget <= 2048) {
        payload['reasoning_effort'] = 'medium';
      } else {
        payload['reasoning_effort'] = 'high';
      }
    }
  }

  if (!payload.containsKey('thinking') &&
      !payload.containsKey('reasoning_effort') &&
      (levelStr == null ||
          levelStr.isEmpty ||
          levelStr.toUpperCase() == 'THINKING_LEVEL_UNSPECIFIED' ||
          levelStr.toLowerCase() == 'unspecified') &&
      (thinkingBudget == null || thinkingBudget < 0)) {
    if (includeThoughts == true && !isGemini3OrNewer) {
      if (isAnthropic) {
        if (isClaude47) {
          payload['thinking'] = <String, Object?>{'type': 'adaptive'};
        } else if (effectiveMaxTokens == null ||
            effectiveMaxTokens > _anthropicMinThinkingBudgetTokens) {
          payload['thinking'] = <String, Object?>{
            'type': 'enabled',
            'budget_tokens': _anthropicMinThinkingBudgetTokens,
          };
        }
      } else if (isGemini) {
        payload['thinking'] = <String, Object?>{'type': 'enabled'};
      }
    } else if (includeThoughts == false && isGemini) {
      payload['thinking'] = <String, Object?>{'type': 'disabled'};
    }
  }

  if (isAnthropic) {
    _dropParamsRejectedByAnthropicThinking(payload);
  }
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

/// Returns a privacy-preserving identifier for logs and error messages.
String redactFileUriForLog(String fileUri, {String? displayName}) {
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  if (fileUri.startsWith('assistant-')) {
    return 'assistant-<redacted>';
  }
  final RegExp openAiPrefixRegex =
      RegExp(r'^(file|cfile|batch|model|vs|asst)-[A-Za-z0-9]+');
  if (openAiPrefixRegex.hasMatch(fileUri)) {
    final String prefix = fileUri.split('-').first;
    return '$prefix-<redacted>';
  }
  final Uri? parsed = Uri.tryParse(fileUri);
  if (parsed == null || !parsed.hasScheme) {
    return '<unknown>';
  }
  final List<String> segments =
      parsed.pathSegments.where((String s) => s.isNotEmpty).toList();
  final String tail = segments.isNotEmpty ? segments.last : '';
  if (tail.isNotEmpty) {
    return '${parsed.scheme}://<redacted>/$tail';
  }
  return '${parsed.scheme}://<redacted>';
}

const String _dsTcallsBegin = '\u003c\uff5ctool\u2581calls\u2581begin\uff5c\u003e';
const String _dsTcallsEnd = '\u003c\uff5ctool\u2581calls\u2581end\uff5c\u003e';
const String _dsTcallBegin = '\u003c\uff5ctool\u2581call\u2581begin\uff5c\u003e';
const String _dsTcallEnd = '\u003c\uff5ctool\u2581call\u2581end\uff5c\u003e';
const String _dsTsep = '\u003c\uff5ctool\u2581sep\uff5c\u003e';

final RegExp _dsToolCallRe = RegExp(
  '${RegExp.escape(_dsTcallBegin)}function${RegExp.escape(_dsTsep)}'
  r'([^\n\r]+?)\s*?\n(.*?)'
  '${RegExp.escape(_dsTcallEnd)}',
  dotAll: true,
);

const String _toolCallOpen = '<tool_call>';
const String _toolCallClose = '</tool_call>';

final RegExp _fenceOpenRe = RegExp(
  r' {0,3}(`{3,}(?=[^`\n]*$)|~{3,})',
  multiLine: true,
);
final RegExp _fenceCloseRe = RegExp(
  r'^ {0,3}(`{3,}|~{3,})[ \t]*\r?$',
  multiLine: true,
);

const Map<String, String> _callBlockEnds = <String, String>{
  _toolCallOpen: _toolCallClose,
  _dsTcallsBegin: _dsTcallsEnd,
  _dsTcallBegin: _dsTcallEnd,
};

final String _callBlockPattern = _callBlockEnds.keys
    .map(RegExp.escape)
    .join('|');
final RegExp _callBlockRe = RegExp(_callBlockPattern);
final RegExp _codeScanRe = RegExp('$_callBlockPattern|<think>|`+|~{3,}');
final RegExp _inlineCodeScanRe = RegExp('$_callBlockPattern|`+');
final RegExp _paragraphEndRe = RegExp(
  r'\n(?=[ \t]*\r?(?:\n|$)| {0,3}(?:```|~~~))',
);
final RegExp _codeIndentRe = RegExp(r' {4}| {0,3}\t');
final RegExp _atxHeadingRe = RegExp(r' {0,3}#{1,6}(?:[ \t]|\r?$)');
final RegExp _indentedCodeRe = RegExp(
  r'(?:\A|^(?:[ \t]*| {0,3}(?:#{1,6}(?:[ \t].*)?|`{3,}[ \t]*|~{3,}[ \t]*))'
  r'\r?\n)((?: {4}| {0,3}\t).*(?:\n(?:[ \t]*\r?$|(?: {4}| {0,3}\t).*))*)',
  multiLine: true,
);
final RegExp _leadingCallPrefixRe = RegExp(
  r'(?:<\|python_tag\|>|\[TOOL_CALLS\])?\s*',
);
final RegExp _thinkTagRe = RegExp(r'</?think>');
final RegExp _backtickRunRe = RegExp(r'`+');
final RegExp _tagPayloadFenceRe = RegExp(
  r'(`{3,}|~{3,})[ \t]*(?:json)?[ \t]*\r?\n',
  caseSensitive: false,
);
final RegExp _dsFenceArgsRe = RegExp(
  r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
);

Map<String, Object?>? _buildToolCallFromJsonDict(
  Object? candidate, {
  required int index,
}) {
  if (candidate is! Map) {
    return null;
  }
  final Object? nameRaw = candidate['name'];
  final Object? argsRaw = candidate['arguments'];
  if (nameRaw is! String || argsRaw == null) {
    return null;
  }
  String argumentsPayload;
  if (argsRaw is String) {
    argumentsPayload = argsRaw;
  } else {
    try {
      argumentsPayload = jsonEncode(argsRaw);
    } catch (_) {
      argumentsPayload = '$argsRaw';
    }
  }
  final Object? rawId = candidate['id'];
  final String callId =
      (rawId != null && '$rawId'.isNotEmpty)
          ? '$rawId'
          : 'adk_tool_call_${newUuid().replaceAll('-', '')}';
  final Object? rawIndex = candidate['index'];
  final int resolvedIndex = rawIndex is int ? rawIndex : index;
  return <String, Object?>{
    'type': 'function',
    'id': callId,
    'index': resolvedIndex,
    'function': <String, Object?>{
      'name': nameRaw,
      'arguments': argumentsPayload,
    },
  };
}

(Object?, int)? _rawJsonDecode(String text, int start) {
  if (start < 0 || start >= text.length) {
    return null;
  }
  final String first = text[start];
  if (first != '{' && first != '[') {
    return null;
  }
  int depth = 0;
  bool inString = false;
  bool escaped = false;
  int end = -1;
  for (int i = start; i < text.length; i += 1) {
    final String ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == '{' || ch == '[') {
      depth += 1;
    } else if (ch == '}' || ch == ']') {
      depth -= 1;
      if (depth == 0) {
        end = i + 1;
        break;
      }
      if (depth < 0) {
        return null;
      }
    }
  }
  if (end == -1) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(text.substring(start, end));
    return (decoded, end);
  } catch (_) {
    return null;
  }
}

String? _extractJsonFromDeepseekArgs(String argsText) {
  if (argsText.isEmpty) {
    return null;
  }
  final RegExpMatch? fenceMatch = _dsFenceArgsRe.firstMatch(argsText);
  if (fenceMatch != null) {
    final String candidate = (fenceMatch.group(1) ?? '').trim();
    try {
      jsonDecode(candidate);
      return candidate;
    } catch (_) {}
  }
  final int openBrace = argsText.indexOf('{');
  if (openBrace == -1) {
    return null;
  }
  final (Object? decoded, int _)? raw = _rawJsonDecode(argsText, openBrace);
  if (raw == null) {
    return null;
  }
  return jsonEncode(raw.$1);
}

(List<Map<String, Object?>>, String?) _parseDeepseekToolCallsFromText(
  String textBlock, {
  int startIndex = 0,
}) {
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  if (textBlock.isEmpty) {
    return (toolCalls, null);
  }
  if (!textBlock.contains(_dsTcallsBegin) &&
      !textBlock.contains(_dsTcallBegin)) {
    return (toolCalls, null);
  }
  final List<String> remainderParts = <String>[];
  int cursor = 0;
  while (true) {
    final int callsIdx = textBlock.indexOf(_dsTcallsBegin, cursor);
    final int callIdx = textBlock.indexOf(_dsTcallBegin, cursor);
    if (callsIdx == -1 && callIdx == -1) {
      remainderParts.add(textBlock.substring(cursor));
      break;
    }
    final int beginIdx;
    final bool inWrappedBlock;
    if (callsIdx != -1 && (callIdx == -1 || callsIdx < callIdx)) {
      beginIdx = callsIdx;
      inWrappedBlock = true;
    } else {
      beginIdx = callIdx;
      inWrappedBlock = false;
    }
    if (beginIdx > cursor) {
      remainderParts.add(textBlock.substring(cursor, beginIdx));
    }
    String block;
    if (inWrappedBlock) {
      final int endIdx = textBlock.indexOf(
        _dsTcallsEnd,
        beginIdx + _dsTcallsBegin.length,
      );
      if (endIdx == -1) {
        remainderParts.add(textBlock.substring(beginIdx));
        break;
      }
      block = textBlock.substring(beginIdx + _dsTcallsBegin.length, endIdx);
      cursor = endIdx + _dsTcallsEnd.length;
    } else {
      final int endIdx = textBlock.indexOf(
        _dsTcallEnd,
        beginIdx + _dsTcallBegin.length,
      );
      if (endIdx == -1) {
        remainderParts.add(textBlock.substring(beginIdx));
        break;
      }
      block = textBlock.substring(beginIdx, endIdx + _dsTcallEnd.length);
      cursor = endIdx + _dsTcallEnd.length;
    }
    for (final RegExpMatch match in _dsToolCallRe.allMatches(block)) {
      final String funcName = (match.group(1) ?? '').trim();
      final String argsRaw = (match.group(2) ?? '').trim();
      final String? argsJson = _extractJsonFromDeepseekArgs(argsRaw);
      if (funcName.isEmpty || argsJson == null) {
        continue;
      }
      final Map<String, Object?>? toolCall = _buildToolCallFromJsonDict(
        <String, Object?>{'name': funcName, 'arguments': argsJson},
        index: startIndex + toolCalls.length,
      );
      if (toolCall != null) {
        toolCalls.add(toolCall);
      }
    }
  }
  final String remainder = remainderParts
      .where((String p) => p.isNotEmpty)
      .join()
      .trim();
  return (toolCalls, remainder.isEmpty ? null : remainder);
}

int _skipWhitespace(String text, int pos) {
  int i = pos;
  while (i < text.length && text[i].trim().isEmpty) {
    i += 1;
  }
  return i;
}

int? _spanEndAt(List<(int, int)> spans, int pos) {
  int lo = 0;
  int hi = spans.length;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (spans[mid].$1 <= pos) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  final int idx = lo - 1;
  if (idx >= 0 && pos < spans[idx].$2) {
    return spans[idx].$2;
  }
  return null;
}

(List<Map<String, Object?>>, int) _decodeToolCalls(
  String text,
  int pos, {
  int startIndex = 0,
  List<(int, int)> indentedCode = const <(int, int)>[],
}) {
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  int cursor = pos;
  while (cursor < text.length &&
      (text.startsWith('{', cursor) || text.startsWith('[', cursor)) &&
      _spanEndAt(indentedCode, cursor) == null) {
    final (Object? candidate, int end)? decoded = _rawJsonDecode(text, cursor);
    if (decoded == null) {
      break;
    }
    final List<Object?> candidates = decoded.$1 is List
        ? List<Object?>.from(decoded.$1 as List)
        : <Object?>[decoded.$1];
    final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
    for (int i = 0; i < candidates.length; i += 1) {
      final Map<String, Object?>? call = _buildToolCallFromJsonDict(
        candidates[i],
        index: startIndex + toolCalls.length + i,
      );
      if (call != null) {
        calls.add(call);
      }
    }
    if (calls.isEmpty || calls.length != candidates.length) {
      break;
    }
    toolCalls.addAll(calls);
    cursor = _skipWhitespace(text, decoded.$2);
  }
  return (toolCalls, cursor);
}

(List<Map<String, Object?>>, int)? _matchToolCallTag(
  String text,
  int pos, {
  int startIndex = 0,
}) {
  int start = _skipWhitespace(text, pos + _toolCallOpen.length);
  final Match? fence = _tagPayloadFenceRe.matchAsPrefix(text, start);
  if (fence != null) {
    start = _skipWhitespace(text, fence.end);
  }
  final (List<Map<String, Object?>> toolCalls, int decodedEnd) =
      _decodeToolCalls(text, start, startIndex: startIndex);
  int end = decodedEnd;
  if (fence != null) {
    final String fenceMark = fence.group(1)!;
    if (!text.startsWith(fenceMark, end)) {
      return null;
    }
    end = _skipWhitespace(text, end + fenceMark.length);
  }
  if (toolCalls.isEmpty || !text.startsWith(_toolCallClose, end)) {
    return null;
  }
  return (toolCalls, end + _toolCallClose.length);
}

int? _callBlockEnd(String text, int start, String token) {
  if (token == _toolCallOpen) {
    final (List<Map<String, Object?>>, int)? tag = _matchToolCallTag(
      text,
      start,
    );
    return tag?.$2;
  }
  final String endToken = _callBlockEnds[token]!;
  final int end = text.indexOf(endToken, start + token.length);
  if (end == -1) {
    return null;
  }
  final int inner = start + token.length;
  final int nextSame = text.indexOf(token, inner);
  if (nextSame != -1 && nextSame < end) {
    return null;
  }
  final int nextOuter = text.indexOf(_dsTcallsBegin, inner);
  if (nextOuter != -1 && nextOuter < end) {
    return null;
  }
  final int blockEnd = end + endToken.length;
  final (List<Map<String, Object?>> dsCalls, String? dsRemainder) =
      _parseDeepseekToolCallsFromText(text.substring(start, blockEnd));
  return dsCalls.isNotEmpty && dsRemainder == null ? blockEnd : null;
}

RegExpMatch? _searchRe(RegExp re, String text, int start, [int? end]) {
  final int limit = end ?? text.length;
  if (start >= limit) {
    return null;
  }
  for (final RegExpMatch m in re.allMatches(text, start)) {
    if (m.start >= limit) {
      return null;
    }
    if (m.end <= limit) {
      return m;
    }
  }
  return null;
}

int? _findThinkClose(String text, int pos) {
  int scanPos = pos;
  while (true) {
    final int close = text.indexOf('</think>', scanPos);
    if (close == -1) {
      return null;
    }
    bool jumpedPastClose = false;
    while (true) {
      final RegExpMatch? call = _searchRe(_callBlockRe, text, scanPos, close);
      if (call == null) {
        break;
      }
      final int? blockEnd = _callBlockEnd(text, call.start, call.group(0)!);
      scanPos = blockEnd ?? call.end;
      if (blockEnd != null && blockEnd > close) {
        jumpedPastClose = true;
        break;
      }
    }
    if (!jumpedPastClose) {
      return close + '</think>'.length;
    }
  }
}

List<(int, int)> _callBlockSpans(String text) {
  final List<(int, int)> spans = <(int, int)>[];
  int pos = 0;
  while (pos < text.length) {
    final RegExpMatch? call = _searchRe(_callBlockRe, text, pos);
    if (call == null) {
      break;
    }
    final int? blockEnd = _callBlockEnd(text, call.start, call.group(0)!);
    if (blockEnd != null) {
      spans.add((call.start, blockEnd));
    }
    pos = blockEnd ?? call.end;
  }
  return spans;
}

int _rfindNewline(String text, int start, int end) {
  for (int i = math.min(end, text.length) - 1; i >= start; i -= 1) {
    if (text.codeUnitAt(i) == 0x0A) {
      return i;
    }
  }
  return -1;
}

List<(int, int)> _indentedCodeSpans(String text, List<(int, int)> opaque) {
  final List<String> parts = <String>[];
  int prev = 0;
  for (final (int rawStart, int end) in opaque) {
    if (end <= prev) {
      continue;
    }
    final int start = math.max(rawStart, prev);
    parts.add(text.substring(prev, start));
    final int lineStart = _rfindNewline(text, 0, start) + 1;
    final int closeLineStart = _rfindNewline(text, start, end) + 1;
    if (text.substring(start, end).contains('\n') &&
        (_codeIndentRe.matchAsPrefix(text, lineStart) == null ||
            (text.startsWith('<think>', start) &&
                _codeIndentRe.matchAsPrefix(text, closeLineStart) == null))) {
      parts.add('x\n${'x' * math.max(0, end - start - 2)}');
    } else {
      parts.add('x' * (end - start));
    }
    prev = end;
  }
  parts.add(text.substring(prev));
  final String masked = parts.join();
  final List<(int, int)> result = <(int, int)>[];
  for (final RegExpMatch m in _indentedCodeRe.allMatches(masked)) {
    final String? g1 = m.group(1);
    if (g1 != null) {
      final int g1End = m.end;
      final int g1Start = g1End - g1.length;
      result.add((g1Start, g1End));
    }
  }
  return result;
}

int _openInlineTicks(int initialTicks, String line) {
  int ticks = initialTicks;
  for (final RegExpMatch run in _backtickRunRe.allMatches(line)) {
    final String group = run.group(0)!;
    if (ticks != 0) {
      if (group.length == ticks) {
        ticks = 0;
      }
      continue;
    }
    int escapeStart = run.start;
    while (escapeStart > 0 && line[escapeStart - 1] == r'\') {
      escapeStart -= 1;
    }
    ticks = group.length - ((run.start - escapeStart) % 2);
  }
  return ticks;
}

List<(int, int)> _sortSpans(List<(int, int)> spans) {
  final List<(int, int)> copy = List<(int, int)>.from(spans);
  copy.sort(((int, int) a, (int, int) b) {
    final int cmp = a.$1.compareTo(b.$1);
    return cmp != 0 ? cmp : a.$2.compareTo(b.$2);
  });
  return copy;
}

List<(int, int)> _markdownCodeSpans(
  String text, {
  int startPos = 0,
  List<(int, int)>? opaque,
}) {
  if (opaque == null) {
    final List<(int, int)> prefix = startPos > 0
        ? <(int, int)>[(0, startPos)]
        : const <(int, int)>[];
    final List<(int, int)> callBlocks = _sortSpans(<(int, int)>[
      ...prefix,
      ..._callBlockSpans(text),
    ]);
    final List<(int, int)> firstPass = _markdownCodeSpans(
      text,
      startPos: startPos,
      opaque: callBlocks,
    );
    final List<(int, int)> thinkBlocks = <(int, int)>[
      for (final (int s, int e) in firstPass)
        if (text.startsWith('<think>', s)) (s, e),
    ];
    if (thinkBlocks.isEmpty) {
      return firstPass;
    }
    return _markdownCodeSpans(
      text,
      startPos: startPos,
      opaque: _sortSpans(<(int, int)>[...callBlocks, ...thinkBlocks]),
    );
  }

  final List<(int, int)> indented = <(int, int)>[
    for (final (int s, int e) in _indentedCodeSpans(text, opaque))
      if (e > startPos) (s, e),
  ];
  final List<(int, int)> spans = <(int, int)>[];
  int pos = startPos;
  int paragraphEndPos = -1;
  bool thinkUnclosed = false;
  final Map<String, int> unclosedFenceLen = <String, int>{};

  while (pos < text.length) {
    final RegExpMatch? match = _searchRe(_codeScanRe, text, pos);
    if (match == null) {
      break;
    }
    int start = match.start;
    String run = match.group(0)!;
    pos = match.end;
    int? end;

    if (run == '<think>') {
      final int? thinkClose = thinkUnclosed ? null : _findThinkClose(text, pos);
      if (thinkClose == null) {
        thinkUnclosed = true;
        continue;
      }
      spans.add((start, thinkClose));
      pos = thinkClose;
      continue;
    }

    final int? blockEnd = _spanEndAt(indented, start);
    if (blockEnd != null) {
      spans.add((start, blockEnd));
      pos = blockEnd;
      continue;
    }

    if (_callBlockEnds.containsKey(run)) {
      pos = _callBlockEnd(text, start, run) ?? pos;
      continue;
    }

    final int lineStart = _rfindNewline(text, 0, start) + 1;
    final Match? fence = _fenceOpenRe.matchAsPrefix(text, lineStart);
    if (fence != null &&
        fence.group(1) != null &&
        lineStart + fence.group(0)!.indexOf(fence.group(1)!) == start) {
      final String fenceChar = run[0];
      final int minUnclosed = unclosedFenceLen[fenceChar] ?? (run.length + 1);
      if (run.length >= minUnclosed) {
        continue;
      }
      int scanPos = pos;
      while (scanPos < text.length) {
        final RegExpMatch? close = _searchRe(_fenceCloseRe, text, scanPos);
        if (close == null) {
          break;
        }
        bool jumpedPastClose = false;
        while (true) {
          final RegExpMatch? call = _searchRe(
            _callBlockRe,
            text,
            scanPos,
            close.start,
          );
          if (call == null) {
            break;
          }
          final int? callEnd = _callBlockEnd(text, call.start, call.group(0)!);
          scanPos = callEnd ?? call.end;
          if (callEnd != null && callEnd > close.start) {
            jumpedPastClose = true;
            break;
          }
        }
        if (!jumpedPastClose) {
          final String closeGroup = close.group(1)!;
          if (closeGroup[0] == fenceChar && closeGroup.length >= run.length) {
            end = close.end;
            break;
          }
          scanPos = close.end;
        }
      }
      if (end == null) {
        unclosedFenceLen[fenceChar] = run.length;
      }
    } else if (run.startsWith('`')) {
      int escapeStart = start;
      while (escapeStart > 0 && text[escapeStart - 1] == r'\') {
        escapeStart -= 1;
      }
      if ((start - escapeStart) % 2 == 1) {
        start += 1;
        run = run.substring(1);
        if (run.isEmpty) {
          continue;
        }
      }
      if (pos > paragraphEndPos) {
        final RegExpMatch? paragraphEnd = _searchRe(
          _paragraphEndRe,
          text,
          pos,
        );
        paragraphEndPos = paragraphEnd?.start ?? text.length;
      }
      int scanPos = pos;
      while (scanPos < paragraphEndPos) {
        final RegExpMatch? inner = _searchRe(
          _inlineCodeScanRe,
          text,
          scanPos,
          paragraphEndPos,
        );
        if (inner == null) {
          break;
        }
        final String innerGroup = inner.group(0)!;
        if (_callBlockEnds.containsKey(innerGroup)) {
          scanPos = _callBlockEnd(text, inner.start, innerGroup) ?? inner.end;
          if (paragraphEndPos < scanPos) {
            final RegExpMatch? paragraphEnd = _searchRe(
              _paragraphEndRe,
              text,
              scanPos,
            );
            paragraphEndPos = paragraphEnd?.start ?? text.length;
          }
        } else if (innerGroup == run) {
          end = inner.end;
          break;
        } else {
          scanPos = inner.end;
        }
      }
    }
    if (end != null) {
      spans.add((start, end));
      pos = end;
    }
  }
  return spans;
}

String _nextFence(String fence, String line) {
  if (fence.isEmpty) {
    final Match? match = _fenceOpenRe.matchAsPrefix(line);
    return match?.group(1) ?? '';
  }
  final RegExpMatch? close = _fenceCloseRe.firstMatch(line);
  if (close != null &&
      close.start == 0 &&
      close.end == line.length &&
      close.group(1)![0] == fence[0] &&
      close.group(1)!.length >= fence.length) {
    return '';
  }
  return fence;
}

class _StreamTextTracker {
  _StreamTextTracker() {
    reset();
  }

  bool hasNonWhitespace = false;
  String _fence = '';
  final List<String> _lineParts = <String>[];
  String _lineHead = '';
  bool _lineHasText = false;
  int _lineStartTicks = 0;
  bool _paragraphHasCodeMark = false;
  bool _indentedCodeMayFollow = true;
  bool inThink = false;
  final List<String> _thinkParts = <String>[];
  String _thinkTail = '';
  final List<int> _maybeThinkOffsets = <int>[];
  bool _maybeInThink = false;

  void reset() {
    hasNonWhitespace = false;
    _fence = '';
    _lineParts.clear();
    _lineHead = '';
    _lineHasText = false;
    _lineStartTicks = 0;
    _paragraphHasCodeMark = false;
    _indentedCodeMayFollow = true;
    inThink = false;
    _thinkParts.clear();
    _thinkTail = '';
    _maybeThinkOffsets.clear();
    _maybeInThink = false;
  }

  bool get inCode {
    if (_fence.isNotEmpty || _paragraphHasCodeMark) {
      return true;
    }
    return _indentedCodeMayFollow &&
        _lineHead.isNotEmpty &&
        (_lineHead.trim().isEmpty ||
            _codeIndentRe.matchAsPrefix(_lineHead) != null);
  }

  bool inThinkFor(String text) {
    return inThink ||
        _maybeInThink ||
        _thinkTagRe.hasMatch('$_thinkTail$text');
  }

  bool completesLine(String text) {
    return _lineHasText && text.contains('\n');
  }

  void feed(String text) {
    if (text.trim().isNotEmpty) {
      hasNonWhitespace = true;
    }
    final String window = '$_thinkTail$text';
    final int offset = _thinkTail.length;
    int pos = 0;
    for (final RegExpMatch tag in _thinkTagRe.allMatches(window)) {
      if (tag.end <= offset) {
        continue;
      }
      final int tagStart = math.max(tag.start - offset, pos);
      final int tagEnd = tag.end - offset;
      if (inThink) {
        _thinkParts.add(text.substring(pos, tagStart));
        if (tag.group(0) == '</think>') {
          _closeThink();
        }
        if (inThink) {
          _thinkParts.add(text.substring(tagStart, tagEnd));
        }
      } else {
        _feedMarkdown(text.substring(pos, tagStart));
        final String line = _lineParts.join();
        if (tag.group(0) == '<think>' && _fence.isEmpty) {
          if (_openInlineTicks(_lineStartTicks, line) != 0) {
            _maybeThinkOffsets.add(
              line.length + math.min(0, tag.start - offset),
            );
          } else {
            inThink = true;
            _thinkParts.clear();
            _feedMarkdown('<think>');
          }
        }
        if (!inThink) {
          _feedMarkdown(text.substring(tagStart, tagEnd));
        }
      }
      pos = tagEnd;
    }
    if (inThink) {
      _thinkParts.add(text.substring(pos));
    } else {
      _feedMarkdown(text.substring(pos));
    }
    const int tailKeep = '</think'.length;
    _thinkTail = window.length <= tailKeep
        ? window
        : window.substring(window.length - tailKeep);
  }

  void _closeThink() {
    final String body = _thinkParts.join();
    int scanPos = 0;
    while (scanPos < body.length) {
      final RegExpMatch? call = _searchRe(_callBlockRe, body, scanPos);
      if (call == null) {
        break;
      }
      final String callGroup = call.group(0)!;
      final int? blockEnd = _callBlockEnd(body, call.start, callGroup);
      if (blockEnd == null &&
          body.indexOf(_callBlockEnds[callGroup]!, call.end) == -1) {
        return;
      }
      scanPos = blockEnd ?? call.end;
    }
    inThink = false;
    if (!body.contains('\n')) {
      _feedMarkdown('</think>');
    } else if (_codeIndentRe.matchAsPrefix(_lineParts.join()) != null &&
        _codeIndentRe.matchAsPrefix(body, body.lastIndexOf('\n') + 1) != null) {
      _feedMarkdown('\n    </think>');
    } else {
      _feedMarkdown('\n</think>');
    }
  }

  void _feedMarkdown(String text) {
    final List<String> split = text.split('\n');
    final String tail = split.last;
    for (int i = 0; i < split.length - 1; i += 1) {
      _lineParts.add(split[i]);
      final String line = _lineParts.join();
      _lineParts.clear();
      _lineHead = '';
      _lineHasText = false;
      if (_maybeThinkOffsets.isNotEmpty) {
        final int textStart = line.length - line.trimLeft().length;
        final List<(int, int)> spans = _markdownCodeSpans(
          line.substring(textStart),
        );
        final bool allInsideCode = _maybeThinkOffsets.every(
          (int tagPos) => spans.any(
            ((int, int) span) =>
                span.$1 < tagPos - textStart && tagPos - textStart < span.$2,
          ),
        );
        if (!allInsideCode) {
          _maybeInThink = true;
        }
        _maybeThinkOffsets.clear();
      }
      final String fence = _nextFence(_fence, line);
      if (fence.isNotEmpty || _fence.isNotEmpty || line.trim().isEmpty) {
        _paragraphHasCodeMark = false;
        _lineStartTicks = 0;
      } else {
        if (line.contains('`') || line.contains('~')) {
          _paragraphHasCodeMark = true;
        }
        _lineStartTicks = _openInlineTicks(_lineStartTicks, line);
      }
      if (fence.isNotEmpty || _fence.isNotEmpty) {
        _indentedCodeMayFollow = fence.isEmpty;
      } else if (line.trim().isNotEmpty) {
        _indentedCodeMayFollow =
            _atxHeadingRe.matchAsPrefix(line) != null ||
            (_indentedCodeMayFollow &&
                _codeIndentRe.matchAsPrefix(line) != null);
      } else {
        _indentedCodeMayFollow = true;
      }
      _fence = fence;
    }
    _lineParts.add(tail);
    final String combinedHead =
        '$_lineHead${tail.length > 4 ? tail.substring(0, 4) : tail}';
    _lineHead = combinedHead.length > 4
        ? combinedHead.substring(0, 4)
        : combinedHead;
    _lineHasText = _lineHasText || tail.trim().isNotEmpty;
    if (tail.contains('`') || tail.contains('~')) {
      _paragraphHasCodeMark = true;
    }
  }
}

/// Extracts inline JSON tool calls from LiteLLM text responses while ignoring
/// tool calls quoted inside Markdown code spans/fences, `<think>` blocks, or
/// bare JSON following prose.
(List<Map<String, Object?>>, String?) parseToolCallsFromText(
  String? textBlock, {
  bool allowBareJson = true,
}) {
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  if (textBlock == null || textBlock.isEmpty) {
    return (toolCalls, null);
  }

  List<(int, int)>? codeSpans;
  int codeStart = 0;
  int pos = _skipWhitespace(textBlock, 0);
  final List<(int, int)> thinkBlocks = <(int, int)>[];
  while (textBlock.startsWith('<think>', pos)) {
    final int? thinkClose = _findThinkClose(
      textBlock,
      pos + '<think>'.length,
    );
    if (thinkClose == null) {
      break;
    }
    thinkBlocks.add((pos, thinkClose));
    pos = _skipWhitespace(textBlock, thinkClose);
  }
  final Match? prefix = _leadingCallPrefixRe.matchAsPrefix(textBlock, pos);
  int runPos = allowBareJson ? (prefix?.end ?? pos) : -1;
  final List<(int, int)> callBlocks = allowBareJson
      ? _callBlockSpans(textBlock)
      : const <(int, int)>[];
  List<(int, int)> indentedCode = allowBareJson
      ? _indentedCodeSpans(
          textBlock,
          _sortSpans(<(int, int)>[...thinkBlocks, ...callBlocks]),
        )
      : const <(int, int)>[];
  final List<String> remainderParts = <String>[];
  int cursor = 0;

  while (true) {
    if (pos == runPos) {
      final (List<Map<String, Object?>> jsonCalls, int end) = _decodeToolCalls(
        textBlock,
        pos,
        startIndex: toolCalls.length,
        indentedCode: indentedCode,
      );
      if (jsonCalls.isNotEmpty) {
        final int jsonEnd = textBlock.substring(0, end).trimRight().length;
        final bool multiLine = textBlock.substring(pos, jsonEnd).contains('\n');
        if (multiLine && _spanEndAt(indentedCode, end) != null) {
          indentedCode = _indentedCodeSpans(
            textBlock,
            _sortSpans(<(int, int)>[(0, jsonEnd), ...callBlocks]),
          );
        }
        if (multiLine || _searchRe(_codeScanRe, textBlock, pos, jsonEnd) != null) {
          codeStart = jsonEnd;
        }
        remainderParts.add(textBlock.substring(cursor, pos));
        toolCalls.addAll(jsonCalls);
        cursor = pos = runPos = end;
        continue;
      }
    }
    final int searchEnd = pos < runPos ? runPos : textBlock.length;
    final RegExpMatch? match = _searchRe(_callBlockRe, textBlock, pos, searchEnd);
    if (match == null) {
      if (pos >= runPos) {
        break;
      }
      pos = runPos;
      continue;
    }
    final int start = match.start;
    final String token = match.group(0)!;
    final int? spanEnd;
    if (start == runPos) {
      spanEnd = _spanEndAt(indentedCode, start);
    } else {
      codeSpans ??= _markdownCodeSpans(textBlock, startPos: codeStart);
      spanEnd = _spanEndAt(codeSpans, start);
    }
    if (spanEnd != null) {
      pos = spanEnd;
      continue;
    }
    (List<Map<String, Object?>>, int)? found;
    if (token == _toolCallOpen) {
      found = _matchToolCallTag(
        textBlock,
        start,
        startIndex: toolCalls.length,
      );
    } else {
      final int? blockEnd = _callBlockEnd(textBlock, start, token);
      if (blockEnd != null) {
        final (List<Map<String, Object?>> dsCalls, String? _) =
            _parseDeepseekToolCallsFromText(
              textBlock.substring(start, blockEnd),
              startIndex: toolCalls.length,
            );
        if (dsCalls.isNotEmpty) {
          found = (dsCalls, blockEnd);
        }
      }
    }
    if (found == null) {
      if (token == _toolCallOpen && start == runPos) {
        pos = runPos = _skipWhitespace(textBlock, match.end);
      } else {
        pos = match.end;
      }
      continue;
    }
    final (List<Map<String, Object?>> blockCalls, int end) = found;
    remainderParts.add(textBlock.substring(cursor, start));
    toolCalls.addAll(blockCalls);
    cursor = pos = end;
    if (start == runPos) {
      pos = runPos = _skipWhitespace(textBlock, end);
    }
  }
  remainderParts.add(textBlock.substring(cursor));
  final String joinedRemainder = remainderParts.join().trim();
  return (toolCalls, joinedRemainder.isEmpty ? null : joinedRemainder);
}

(Object?, List<Object?>) _splitMessageContentAndToolCalls(
  Map<String, Object?> message, {
  bool parseInlineToolCalls = true,
  bool allowBareJson = true,
}) {
  final List<Object?> existingToolCalls =
      (message['tool_calls'] as List<Object?>?) ?? const <Object?>[];
  final List<Object?> normalizedToolCalls = existingToolCalls.isNotEmpty
      ? List<Object?>.from(existingToolCalls)
      : <Object?>[];
  final Object? content = message['content'];

  if (normalizedToolCalls.isNotEmpty ||
      content is! String ||
      !parseInlineToolCalls) {
    return (content, normalizedToolCalls);
  }

  final (List<Map<String, Object?>> fallbackToolCalls, String? remainder) =
      parseToolCallsFromText(content, allowBareJson: allowBareJson);
  if (fallbackToolCalls.isNotEmpty) {
    return (remainder, fallbackToolCalls);
  }

  return (content, <Object?>[]);
}


