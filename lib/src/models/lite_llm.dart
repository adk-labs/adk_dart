import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../platform/uuid.dart';
import '../types/content.dart';
import '../utils/schema_utils.dart';
import '../utils/system_environment/system_environment.dart';
import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';


part 'lite_llm_message_converter.dart';
part 'lite_llm_tool_call_parser.dart';
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
const String _streamEndedWithoutFinishReason =
    'stream_ended_without_finish_reason';
const String _truncatedStreamErrorMessage =
    'The stream ended without a finish reason; the response may be truncated.';
const int _maxJsonDepth = 500;
final RegExp _hugeIntLiteralPattern = RegExp(r'\d{4301,}');

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
    bool isPartial = false,
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

    final List<(String, int)> malformedToolCalls = <(String, int)>[];
    for (final Object? call in toolCalls) {
      final Map<String, Object?> callMap = _asMap(call);
      final Object? callType = callMap['type'];
      if (callType != null && callType != '' && callType != 'function') {
        continue;
      }
      final Part? parsedPart = _tryParseFunctionCall(callMap);
      if (parsedPart == null) {
        final Map<String, Object?> fn = _asMap(callMap['function']);
        final Object? rawName = fn['name'];
        final Object? rawArguments = fn['arguments'];
        final String reportedName =
            rawName is String && rawName.isNotEmpty ? rawName : '<unnamed>';
        final int reportedLen =
            rawArguments is String ? rawArguments.length : 0;
        malformedToolCalls.add((reportedName, reportedLen));
        continue;
      }
      parts.add(parsedPart);
    }

    final LlmResponse llmResponse = LlmResponse(
      modelVersion: response['model'] as String?,
      content: Content(role: role, parts: parts),
      partial: isPartial ? true : null,
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

    if (malformedToolCalls.isNotEmpty && !isPartial) {
      for (final (String name, int argLength) in malformedToolCalls) {
        developer.log(
          "Discarding tool call '$name' with unparseable arguments ($argLength chars).",
          name: 'adk_dart.models.lite_llm',
          level: 900,
        );
      }
      llmResponse.finishReason = 'MALFORMED_FUNCTION_CALL';
      llmResponse.errorCode = 'MALFORMED_FUNCTION_CALL';
      llmResponse.errorMessage =
          'Arguments for the following function calls were not a valid JSON object: '
          '${malformedToolCalls.map(((String, int) e) => e.$1).join(', ')}';
    }

    final Object? rawFinishReason = first['finish_reason'];
    if (!isPartial || rawFinishReason != null) {
      _stampFinishReason(
        llmResponse,
        rawFinishReason == null ? null : '$rawFinishReason',
        defaultToOtherWhenNull: !isPartial,
      );
    }
    return llmResponse;
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
    final List<Part> rawStreamReasoningParts = <Part>[];
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
        for (final String field in const <String>[
          'thinking_blocks',
          'reasoning_content',
          'reasoning',
        ]) {
          rawStreamReasoningParts.addAll(_extractReasoningParts(eff[field]));
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
              (parsed.finishReason == null || parsed.finishReason == 'OTHER') &&
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
        (rawStreamTexts.isNotEmpty || rawStreamReasoningParts.isNotEmpty)) {
      final (List<Map<String, Object?>> heldBackCalls, String? remainder) =
          rawStreamTexts.isNotEmpty
          ? parseToolCallsFromText(rawStreamTexts.join())
          : (const <Map<String, Object?>>[], null);
      if (heldBackCalls.isNotEmpty) {
        final List<Part> finalParts = <Part>[
          if (remainder != null && remainder.isNotEmpty) Part.text(remainder),
          for (final Map<String, Object?> callMap in heldBackCalls)
            ?_tryParseFunctionCall(callMap),
        ];
        yield LlmResponse(
          modelVersion: lastStreamModel,
          content: Content(role: 'model', parts: finalParts),
          finishReason: mapFinishReason(lastStreamFinishReason ?? 'tool_calls'),
          partial: false,
        );
      } else if (lastStreamFinishReason == null) {
        final List<Part> finalParts = <Part>[
          if (!filterThoughts && rawStreamReasoningParts.isNotEmpty)
            Part.text(
              _mergeReasoningTexts(rawStreamReasoningParts),
              thought: true,
            ),
          if (rawStreamTexts.isNotEmpty) Part.text(rawStreamTexts.join()),
        ];
        final LlmResponse truncated = LlmResponse(
          modelVersion: lastStreamModel,
          content: Content(role: 'model', parts: finalParts),
          partial: false,
        );
        _stampFinishReason(truncated, _streamEndedWithoutFinishReason);
        yield truncated;
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

