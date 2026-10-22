/// OpenAI Chat Completions and Responses API model integrations.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../models/apigee_llm.dart';
import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../types/content.dart';
import '../../utils/system_environment/system_environment.dart';

const String _openAiApiKeyEnv = 'OPENAI_API_KEY';
const String _openAiBaseUrlEnv = 'OPENAI_BASE_URL';
const String _azureOpenAiApiKeyEnv = 'AZURE_OPENAI_API_KEY';
const String _defaultOpenAiChatUrl =
    'https://api.openai.com/v1/chat/completions';
const String _defaultOpenAiResponsesUrl = 'https://api.openai.com/v1/responses';
const String _refusalPrefix = 'OpenAI refusal: ';
const num _defaultSamplingValue = 1;

/// Supported OpenAI reasoning effort tiers ordered from least to most effort.
const Set<String> openAiReasoningEfforts = <String>{
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
};

final RegExp _reasoningModelRegex = RegExp(
  r'(?:^|/)(?:o\d+|gpt-[56](?!.*-chat))(?:\..*|-.*|$)',
  caseSensitive: false,
);
final RegExp _advancedReasoningModelRegex = RegExp(
  r'(?:^|/)(?:gpt-6|gpt-5\.[56])(?:[.\-]|$)',
  caseSensitive: false,
);
final RegExp _gpt5ModelRegex = RegExp(
  r'(?:^|/)gpt-5(?![.\d])',
  caseSensitive: false,
);
final RegExp _o1NoEffortRegex = RegExp(
  r'(?:^|/)o1-(?:mini|preview)(?:[.\-]|$)',
  caseSensitive: false,
);
final RegExp _validCallIdRegex = RegExp(r'^[a-zA-Z0-9_-]+$');

const Set<String> _effortsAdvancedChat = <String>{
  'low',
  'medium',
  'high',
  'xhigh',
};
const Set<String> _effortsAdvancedResponses = <String>{
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
};
const Set<String> _effortsGpt5 = <String>{'minimal', 'low', 'medium', 'high'};
const Set<String> _effortsOSeries = <String>{'low', 'medium', 'high'};

/// Callback signature for supplying an OpenAI API key synchronously or asynchronously.
typedef OpenAiApiKeyProvider = FutureOr<String> Function();

/// Alias for [OpenAILlm] matching Dart naming conventions.
typedef OpenAiLlm = OpenAILlm;

/// Alias for [OpenAIResponsesLlm] matching Dart naming conventions.
typedef OpenAiResponsesLlm = OpenAIResponsesLlm;

/// Alias for [AzureOpenAIResponsesLlm] matching Dart naming conventions.
typedef AzureOpenAiResponsesLlm = AzureOpenAIResponsesLlm;

/// Alias for [OpenAIGenerateContentConfig] matching Dart naming conventions.
typedef OpenAiGenerateContentConfig = OpenAIGenerateContentConfig;

/// Returns `true` when [model] is an OpenAI reasoning model (`o*`, `gpt-5*`, `gpt-6*` excluding `-chat`).
bool isReasoningModel(String? model) {
  if (model == null || model.isEmpty) {
    return false;
  }
  return _reasoningModelRegex.hasMatch(model);
}

/// Strips non-default `temperature` and `top_p` parameters from [kwargs] when [model] is a reasoning model.
void stripUnsupportedSamplingParams(
  Map<String, Object?> kwargs,
  String? model,
) {
  if (!isReasoningModel(model)) {
    return;
  }
  for (final String name in const <String>['temperature', 'top_p']) {
    final Object? value = kwargs[name];
    if (value != null && value != _defaultSamplingValue) {
      kwargs.remove(name);
      developer.log(
        'Ignoring $name=$value: reasoning model $model accepts only the default '
        'value ($_defaultSamplingValue); set it to that or remove it from the request config.',
        name: 'adk_dart.integrations.openai',
      );
    }
  }
}

/// Returns the set of reasoning effort tiers that [model] accepts on [api] (`'chat'` or `'responses'`).
Set<String> supportedEfforts(String? model, String api) {
  if (api != 'chat' && api != 'responses') {
    throw ArgumentError.value(api, 'api', 'Unknown API surface.');
  }
  if (model == null || model.isEmpty || !isReasoningModel(model)) {
    return const <String>{};
  }
  if (_o1NoEffortRegex.hasMatch(model)) {
    return const <String>{};
  }
  if (_advancedReasoningModelRegex.hasMatch(model)) {
    return api == 'responses'
        ? _effortsAdvancedResponses
        : _effortsAdvancedChat;
  }
  if (_gpt5ModelRegex.hasMatch(model)) {
    return _effortsGpt5;
  }
  return _effortsOSeries;
}

/// Returns `true` when the request targets the default `api.openai.com` host rather than a compatible backend.
bool targetsDefaultOpenAiHost({
  Object? client,
  String? baseUrl,
  String? azureEndpoint,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? _safeEnvironment;
  final bool hasCustomBaseUrl =
      baseUrl != null &&
      baseUrl.isNotEmpty &&
      baseUrl != _defaultOpenAiChatUrl &&
      baseUrl != _defaultOpenAiResponsesUrl;
  final String? envBaseUrl = env[_openAiBaseUrlEnv];
  return client == null &&
      !hasCustomBaseUrl &&
      (azureEndpoint == null || azureEndpoint.isEmpty) &&
      (envBaseUrl == null || envBaseUrl.isEmpty);
}

/// Resolves the reasoning effort tier to send for [model] on [api] (`'chat'` or `'responses'`).
String? buildReasoningEffort(
  GenerateContentConfig? config,
  String? model,
  String api, {
  bool validate = true,
}) {
  if (config == null) {
    return null;
  }
  String? effort;
  if (config is OpenAIGenerateContentConfig &&
      config.effort != null &&
      config.effort!.isNotEmpty) {
    effort = config.effort;
  } else {
    if (_hasThinkingConfig(config.thinkingConfig)) {
      developer.log(
        'Standard thinkingConfig is not supported for OpenAI models and '
        'will be ignored. Use OpenAIGenerateContentConfig and set the '
        '`effort` field directly to configure reasoning effort.',
        name: 'adk_dart.integrations.openai',
      );
    }
    return null;
  }

  if (!validate) {
    return effort;
  }

  final Set<String> supported = supportedEfforts(model, api);
  if (supported.isEmpty) {
    throw ArgumentError(
      'Model "$model" does not accept a reasoning effort parameter; remove '
      '`effort` (got "$effort") from the config for this model.',
    );
  }
  if (!supported.contains(effort)) {
    final List<String> sorted = supported.toList()..sort();
    throw ArgumentError(
      'Reasoning effort "$effort" is not supported by model "$model" on '
      'the $api API. Supported tiers: $sorted.',
    );
  }
  return effort;
}

/// Serializes an ADK [systemInstruction] into plain text for OpenAI requests.
String? serializeSystemInstruction(Object? systemInstruction) {
  if (systemInstruction == null) {
    return null;
  }
  if (systemInstruction is String) {
    return systemInstruction.isEmpty ? null : systemInstruction;
  }
  if (systemInstruction is Part) {
    final String? text = systemInstruction.text;
    return (text == null || text.isEmpty) ? null : text;
  }
  if (systemInstruction is Content) {
    final String text = systemInstruction.parts
        .map((Part p) => p.text ?? '')
        .join();
    return text.isEmpty ? null : text;
  }
  if (systemInstruction is Map) {
    if (systemInstruction.containsKey('parts')) {
      final Object? rawParts = systemInstruction['parts'];
      if (rawParts is List) {
        final String text = rawParts
            .map((Object? item) => serializeSystemInstruction(item) ?? '')
            .join();
        return text.isEmpty ? null : text;
      }
      return null;
    }
    if (systemInstruction['text'] is String) {
      final String text = systemInstruction['text'] as String;
      return text.isEmpty ? null : text;
    }
    return null;
  }
  if (systemInstruction is Iterable) {
    final List<String> texts = <String>[];
    for (final Object? item in systemInstruction) {
      final String? serialized = serializeSystemInstruction(item);
      if (serialized != null && serialized.isNotEmpty) {
        texts.add(serialized);
      }
    }
    return texts.isEmpty ? null : texts.join('\n');
  }
  return null;
}

/// Maps an ADK [GenerateContentConfig] function-calling mode to an OpenAI `tool_choice` value.
String? toolChoice(GenerateContentConfig? config) {
  final FunctionCallingConfigMode? mode =
      config?.toolConfig?.functionCallingConfig?.mode;
  if (mode == null) {
    return null;
  }
  switch (mode) {
    case FunctionCallingConfigMode.any:
      return 'required';
    case FunctionCallingConfigMode.none:
      return 'none';
    case FunctionCallingConfigMode.auto:
      return 'auto';
    case FunctionCallingConfigMode.modeUnspecified:
      return null;
  }
}

/// Maps an OpenAI chat-completion [finishReason] string to an ADK finish reason string.
String? mapFinishReason(String? finishReason) {
  if (finishReason == null || finishReason.isEmpty) {
    return null;
  }
  if (finishReason == 'stop' ||
      finishReason == 'tool_calls' ||
      finishReason == 'function_call') {
    return 'STOP';
  }
  if (finishReason == 'length') {
    return 'MAX_TOKENS';
  }
  if (finishReason == 'content_filter') {
    return 'SAFETY';
  }
  return 'FINISH_REASON_UNSPECIFIED';
}

/// Recursively transforms a JSON [schema] in place for OpenAI strict structured outputs.
void enforceStrictOpenAiSchema(Map<String, dynamic> schema) {
  if (schema.containsKey(r'$ref')) {
    final Object? ref = schema[r'$ref'];
    schema
      ..clear()
      ..[r'$ref'] = ref;
    return;
  }
  if (schema['type'] == 'object' && schema['properties'] is Map) {
    final Map<Object?, Object?> props =
        schema['properties'] as Map<Object?, Object?>;
    schema['additionalProperties'] = false;
    final List<String> keys = props.keys.map((Object? k) => '$k').toList()
      ..sort();
    schema['required'] = keys;
  }
  final Object? defs = schema[r'$defs'];
  if (defs is Map) {
    for (final Object? defn in defs.values) {
      if (defn is Map<String, dynamic>) {
        enforceStrictOpenAiSchema(defn);
      } else if (defn is Map) {
        final Map<String, dynamic> converted = defn.map(
          (Object? k, Object? v) => MapEntry('$k', v),
        );
        enforceStrictOpenAiSchema(converted);
        defs[defs.keys.firstWhere((Object? k) => defs[k] == defn)] = converted;
      }
    }
  }
  final Object? properties = schema['properties'];
  if (properties is Map) {
    for (final MapEntry<Object?, Object?> entry
        in properties.entries.toList()) {
      final Object? prop = entry.value;
      if (prop is Map<String, dynamic>) {
        enforceStrictOpenAiSchema(prop);
      } else if (prop is Map) {
        final Map<String, dynamic> converted = prop.map(
          (Object? k, Object? v) => MapEntry('$k', v),
        );
        enforceStrictOpenAiSchema(converted);
        properties[entry.key] = converted;
      }
    }
  }
  for (final String key in const <String>['anyOf', 'oneOf', 'allOf']) {
    final Object? list = schema[key];
    if (list is List) {
      for (int i = 0; i < list.length; i++) {
        final Object? item = list[i];
        if (item is Map<String, dynamic>) {
          enforceStrictOpenAiSchema(item);
        } else if (item is Map) {
          final Map<String, dynamic> converted = item.map(
            (Object? k, Object? v) => MapEntry('$k', v),
          );
          enforceStrictOpenAiSchema(converted);
          list[i] = converted;
        }
      }
    }
  }
  final Object? items = schema['items'];
  if (items is Map<String, dynamic>) {
    enforceStrictOpenAiSchema(items);
  } else if (items is Map) {
    final Map<String, dynamic> converted = items.map(
      (Object? k, Object? v) => MapEntry('$k', v),
    );
    enforceStrictOpenAiSchema(converted);
    schema['items'] = converted;
  }
}

/// Converts a schema map into a normalized OpenAI JSON schema, optionally enforcing [strict] mode.
Map<String, dynamic> toOpenAiSchema(
  Map<String, dynamic> schema, {
  bool strict = false,
}) {
  final Map<String, dynamic> copy = _deepCopySchemaMap(schema);
  _lowercaseSchemaTypes(copy);
  if (strict) {
    enforceStrictOpenAiSchema(copy);
  }
  return copy;
}

/// Converts ADK [ToolDeclaration] items into OpenAI Chat Completions tool definitions.
List<Map<String, Object?>> toOpenAiChatTools(List<ToolDeclaration>? tools) {
  if (tools == null || tools.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final ToolDeclaration tool in tools) {
    for (final FunctionDeclaration declaration in tool.functionDeclarations) {
      if (declaration.name.isEmpty) {
        throw ArgumentError('FunctionDeclaration must have a name.');
      }
      final Map<String, dynamic> parameters = declaration.parameters.isEmpty
          ? <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            }
          : toOpenAiSchema(declaration.parameters);
      result.add(<String, Object?>{
        'type': 'function',
        'function': <String, Object?>{
          'name': declaration.name,
          'description': declaration.description,
          'parameters': parameters,
        },
      });
    }
  }
  return result;
}

/// Converts ADK [ToolDeclaration] items into OpenAI Responses API tool definitions.
List<Map<String, Object?>> toOpenAiResponsesTools(
  List<ToolDeclaration>? tools,
) {
  if (tools == null || tools.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  for (final ToolDeclaration tool in tools) {
    for (final FunctionDeclaration declaration in tool.functionDeclarations) {
      if (declaration.name.isEmpty) {
        throw ArgumentError('FunctionDeclaration must have a name.');
      }
      final Map<String, dynamic> parameters = declaration.parameters.isEmpty
          ? <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{},
            }
          : toOpenAiSchema(declaration.parameters);
      result.add(<String, Object?>{
        'type': 'function',
        'name': declaration.name,
        'description': declaration.description,
        'parameters': parameters,
        'strict': false,
      });
    }
  }
  return result;
}

/// Generation configuration with OpenAI-specific reasoning effort controls.
///
/// ```dart
/// final config = OpenAIGenerateContentConfig(
///   effort: 'high',
///   maxOutputTokens: 2048,
/// );
/// ```
class OpenAIGenerateContentConfig extends GenerateContentConfig {
  /// Creates an OpenAI generation configuration.
  OpenAIGenerateContentConfig({
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
    super.responseModalities,
    super.speechConfig,
    super.toolConfig,
    super.automaticFunctionCalling,
    super.cachedContent,
    super.httpOptions,
    super.labels,
  }) {
    if (effort != null && !openAiReasoningEfforts.contains(effort)) {
      throw ArgumentError.value(
        effort,
        'effort',
        'Must be one of ${openAiReasoningEfforts.join(", ")}.',
      );
    }
    if (_hasThinkingConfig(thinkingConfig)) {
      throw ArgumentError(
        'thinking_config (thinking_level / thinking_budget) is not supported '
        'in OpenAIGenerateContentConfig. Use the `effort` field directly to '
        'configure reasoning effort.',
      );
    }
  }

  /// OpenAI reasoning effort tier (`minimal`, `low`, `medium`, `high`, `xhigh`, `max`).
  String? effort;

  @override
  OpenAIGenerateContentConfig copyWith({
    Object? effort = _sentinel,
    Object? tools = _sentinel,
    Object? systemInstruction = _sentinel,
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    Object? topK = _sentinel,
    Object? maxOutputTokens = _sentinel,
    List<String>? stopSequences,
    Object? frequencyPenalty = _sentinel,
    Object? presencePenalty = _sentinel,
    Object? seed = _sentinel,
    Object? candidateCount = _sentinel,
    Object? responseLogprobs = _sentinel,
    Object? logprobs = _sentinel,
    Object? thinkingConfig = _sentinel,
    Object? responseSchema = _sentinel,
    Object? responseJsonSchema = _sentinel,
    Object? responseMimeType = _sentinel,
    Object? responseModalities = _sentinel,
    Object? speechConfig = _sentinel,
    Object? toolConfig = _sentinel,
    Object? automaticFunctionCalling = _sentinel,
    Object? cachedContent = _sentinel,
    Object? httpOptions = _sentinel,
    Map<String, String>? labels,
  }) {
    final GenerateContentConfig base = super.copyWith(
      tools: identical(tools, _sentinel) ? this.tools : tools,
      systemInstruction: identical(systemInstruction, _sentinel)
          ? this.systemInstruction
          : systemInstruction,
      temperature: identical(temperature, _sentinel)
          ? this.temperature
          : temperature,
      topP: identical(topP, _sentinel) ? this.topP : topP,
      topK: identical(topK, _sentinel) ? this.topK : topK,
      maxOutputTokens: identical(maxOutputTokens, _sentinel)
          ? this.maxOutputTokens
          : maxOutputTokens,
      stopSequences: stopSequences,
      frequencyPenalty: identical(frequencyPenalty, _sentinel)
          ? this.frequencyPenalty
          : frequencyPenalty,
      presencePenalty: identical(presencePenalty, _sentinel)
          ? this.presencePenalty
          : presencePenalty,
      seed: identical(seed, _sentinel) ? this.seed : seed,
      candidateCount: identical(candidateCount, _sentinel)
          ? this.candidateCount
          : candidateCount,
      responseLogprobs: identical(responseLogprobs, _sentinel)
          ? this.responseLogprobs
          : responseLogprobs,
      logprobs: identical(logprobs, _sentinel) ? this.logprobs : logprobs,
      thinkingConfig: identical(thinkingConfig, _sentinel)
          ? this.thinkingConfig
          : thinkingConfig,
      responseSchema: identical(responseSchema, _sentinel)
          ? this.responseSchema
          : responseSchema,
      responseJsonSchema: identical(responseJsonSchema, _sentinel)
          ? this.responseJsonSchema
          : responseJsonSchema,
      responseMimeType: identical(responseMimeType, _sentinel)
          ? this.responseMimeType
          : responseMimeType,
      responseModalities: identical(responseModalities, _sentinel)
          ? this.responseModalities
          : responseModalities,
      speechConfig: identical(speechConfig, _sentinel)
          ? this.speechConfig
          : speechConfig,
      toolConfig: identical(toolConfig, _sentinel)
          ? this.toolConfig
          : toolConfig,
      automaticFunctionCalling: identical(automaticFunctionCalling, _sentinel)
          ? this.automaticFunctionCalling
          : automaticFunctionCalling,
      cachedContent: identical(cachedContent, _sentinel)
          ? this.cachedContent
          : cachedContent,
      httpOptions: identical(httpOptions, _sentinel)
          ? this.httpOptions
          : httpOptions,
      labels: labels,
    );
    return OpenAIGenerateContentConfig(
      effort: identical(effort, _sentinel) ? this.effort : effort as String?,
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
      responseModalities: base.responseModalities,
      speechConfig: base.speechConfig,
      toolConfig: base.toolConfig,
      automaticFunctionCalling: base.automaticFunctionCalling,
      cachedContent: base.cachedContent,
      httpOptions: base.httpOptions,
      labels: base.labels,
    );
  }
}

/// Client interface for OpenAI Chat Completions requests.
abstract class OpenAiChatCompletionsClient {
  /// Executes a non-streaming Chat Completions request with [payload].
  Future<Map<String, Object?>> create({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  });

  /// Executes a streaming Chat Completions request and yields SSE event maps.
  Stream<Map<String, Object?>> createStream({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  });
}

/// HTTP-backed [OpenAiChatCompletionsClient] for the OpenAI Chat Completions API.
class HttpOpenAiChatCompletionsClient implements OpenAiChatCompletionsClient {
  /// Creates an HTTP Chat Completions client.
  HttpOpenAiChatCompletionsClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<Map<String, Object?>> create({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    final Uri uri = _resolveEndpointUri(baseUrl, '/chat/completions');
    final http.Response response = await _httpClient.post(
      uri,
      headers: _buildJsonHeaders(headers),
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 400) {
      throw ChatCompletionsHttpException(
        response.statusCode,
        response.body,
        responseBody: response.body,
      );
    }
    return _decodeJsonMap(response.body);
  }

  @override
  Stream<Map<String, Object?>> createStream({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  }) async* {
    final Uri uri = _resolveEndpointUri(baseUrl, '/chat/completions');
    final http.Request request = http.Request('POST', uri)
      ..headers.addAll(_buildJsonHeaders(headers, acceptSse: true))
      ..body = jsonEncode(payload);
    final http.StreamedResponse response = await _httpClient.send(request);
    if (response.statusCode >= 400) {
      final String body = await utf8.decodeStream(response.stream);
      throw ChatCompletionsHttpException(
        response.statusCode,
        body,
        responseBody: body,
      );
    }
    yield* _parseSseStream(response.stream);
  }
}

/// Integration with OpenAI Chat Completions models.
///
/// ```dart
/// final llm = OpenAILlm(
///   model: 'gpt-4o',
///   apiKey: 'sk-...',
/// );
/// ```
class OpenAILlm extends BaseLlm {
  /// Creates an OpenAI Chat Completions adapter for [model].
  OpenAILlm({
    super.model = 'gpt-4o',
    this.maxTokens = 4096,
    this.apiKey,
    this.apiKeyProvider,
    this.baseUrl = _defaultOpenAiChatUrl,
    Map<String, String>? headers,
    Map<String, String>? environment,
    this.client,
    ApigeeCompletionsClient? completionsClient,
  }) : headers = headers ?? const <String, String>{},
       environment = environment ?? _safeEnvironment,
       _completionsClient = completionsClient;

  /// Maximum number of tokens to generate.
  final int maxTokens;

  /// Optional explicit API key. Falls back to `OPENAI_API_KEY`.
  final String? apiKey;

  /// Optional synchronous or asynchronous callback returning an API key per request.
  final OpenAiApiKeyProvider? apiKeyProvider;

  /// Chat completions endpoint or base URL.
  final String baseUrl;

  /// Additional headers sent with each request.
  final Map<String, String> headers;

  /// Environment map used for API key and base URL lookup.
  final Map<String, String> environment;

  /// Optional custom [OpenAiChatCompletionsClient] override.
  final OpenAiChatCompletionsClient? client;

  final ApigeeCompletionsClient? _completionsClient;

  /// Regex patterns supported by this OpenAI Chat Completions adapter.
  static List<RegExp> supportedModels() {
    return <RegExp>[
      RegExp(r'gpt-.*'),
      RegExp(r'o\d+-.*'),
      RegExp(r'openai\/.+'),
    ];
  }

  /// Builds the OpenAI Chat Completions request payload for [request].
  Map<String, Object?> buildRequestPayload(
    LlmRequest request, {
    bool stream = false,
  }) {
    final String effectiveModel = _openAiModelId(request.model ?? model);
    final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
    final String? systemText = serializeSystemInstruction(
      request.config.systemInstruction,
    );
    if (systemText != null && systemText.isNotEmpty) {
      messages.add(<String, Object?>{'role': 'system', 'content': systemText});
    }
    for (final Content content in request.contents) {
      messages.addAll(_contentToOpenAiChatMessages(content));
    }

    final List<Map<String, Object?>> tools = toOpenAiChatTools(
      request.config.tools,
    );
    final String? resolvedToolChoice = tools.isNotEmpty
        ? (toolChoice(request.config) ?? 'auto')
        : null;
    final Map<String, Object?>? responseFormat = _buildChatResponseFormat(
      request.config,
    );

    final Map<String, Object?> kwargs = <String, Object?>{
      'model': effectiveModel,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      'tool_choice': ?resolvedToolChoice,
      'max_tokens': request.config.maxOutputTokens ?? maxTokens,
      'response_format': ?responseFormat,
      'temperature': ?request.config.temperature,
      'top_p': ?request.config.topP,
      if (request.config.stopSequences.isNotEmpty)
        'stop': List<String>.from(request.config.stopSequences),
    };

    if (isReasoningModel(effectiveModel)) {
      kwargs['max_completion_tokens'] = kwargs.remove('max_tokens');
    }
    stripUnsupportedSamplingParams(kwargs, effectiveModel);

    final bool validate = targetsDefaultOpenAiHost(
      client: client ?? _completionsClient,
      baseUrl: baseUrl,
      environment: environment,
    );
    final String? effort = buildReasoningEffort(
      request.config,
      effectiveModel,
      'chat',
      validate: validate,
    );
    if (effort != null) {
      kwargs['reasoning_effort'] = effort;
    }

    if (stream) {
      kwargs['stream'] = true;
      kwargs['stream_options'] = const <String, Object?>{
        'include_usage': true,
      };
    }
    return kwargs;
  }

  /// Parses a non-streaming OpenAI Chat Completions [response] map into an [LlmResponse].
  static LlmResponse parseChatResponse(Map<String, Object?> response) {
    final Map<String, Object?>? usage = _chatUsageMetadata(response['usage']);
    final Object? rawChoices = response['choices'];
    if (rawChoices is! List || rawChoices.isEmpty) {
      return LlmResponse(
        errorCode: 'OTHER',
        errorMessage: 'OpenAI response contained no choices.',
        finishReason: 'OTHER',
        usageMetadata: usage,
      );
    }

    final Map<String, Object?> choice = _asObjectMap(rawChoices.first);
    final Map<String, Object?> message = _asObjectMap(choice['message']);
    final List<Part> parts = <Part>[];
    final Object? content = message['content'];
    if (content is String && content.isNotEmpty) {
      parts.add(Part.text(content));
    }
    parts.addAll(_chatToolCallParts(message['tool_calls']));

    final String? rawFinishReason = choice['finish_reason'] as String?;
    final String? finishReason = mapFinishReason(rawFinishReason);
    if (parts.isEmpty && finishReason != null && finishReason != 'STOP') {
      return LlmResponse(
        errorCode: finishReason,
        errorMessage:
            'OpenAI response finished with reason "$rawFinishReason" and no content.',
        finishReason: finishReason,
        usageMetadata: usage,
      );
    }

    return LlmResponse(
      modelVersion: response['model'] as String?,
      content: parts.isEmpty ? null : Content(role: 'model', parts: parts),
      usageMetadata: usage,
      finishReason: finishReason,
    );
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String resolvedApiKey = await _resolveApiKey(
      apiKey: apiKey,
      apiKeyProvider: apiKeyProvider,
      environment: environment,
      envVarName: _openAiApiKeyEnv,
    );
    if (resolvedApiKey.isEmpty && client == null) {
      throw ArgumentError(
        'The $_openAiApiKeyEnv environment variable must be set.',
      );
    }

    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model = _openAiModelId(prepared.model ?? model);
    maybeAppendUserContent(prepared);

    final Map<String, String> requestHeaders = <String, String>{
      ...headers,
      if (resolvedApiKey.isNotEmpty) 'Authorization': 'Bearer $resolvedApiKey',
    };

    if (_completionsClient != null && client == null) {
      yield* _completionsClient.generateContent(
        request: prepared,
        stream: stream,
        baseUrl: baseUrl,
        headers: requestHeaders,
      );
      return;
    }

    final Map<String, Object?> payload = buildRequestPayload(
      prepared,
      stream: stream,
    );
    final OpenAiChatCompletionsClient activeClient =
        client ?? HttpOpenAiChatCompletionsClient();

    if (!stream) {
      final Map<String, Object?> raw = await activeClient.create(
        payload: payload,
        baseUrl: baseUrl,
        headers: requestHeaders,
      );
      yield parseChatResponse(raw);
      return;
    }

    final StringBuffer textAccumulated = StringBuffer();
    final Map<int, Map<String, String>> toolCallsAccumulated =
        <int, Map<String, String>>{};
    Object? usage;
    String? finishReason;

    await for (final Map<String, Object?> chunk in activeClient.createStream(
      payload: payload,
      baseUrl: baseUrl,
      headers: requestHeaders,
    )) {
      if (chunk['usage'] != null) {
        usage = chunk['usage'];
      }
      final Object? rawChoices = chunk['choices'];
      if (rawChoices is! List || rawChoices.isEmpty) {
        continue;
      }
      final Map<String, Object?> choice = _asObjectMap(rawChoices.first);
      if (choice['finish_reason'] is String &&
          (choice['finish_reason'] as String).isNotEmpty) {
        finishReason = choice['finish_reason'] as String;
      }
      final Map<String, Object?> delta = _asObjectMap(choice['delta']);
      final Object? deltaContent = delta['content'];
      if (deltaContent is String && deltaContent.isNotEmpty) {
        textAccumulated.write(deltaContent);
        yield LlmResponse(
          content: Content(role: 'model', parts: <Part>[Part.text(deltaContent)]),
          partial: true,
        );
      }

      final Object? deltaToolCalls = delta['tool_calls'];
      if (deltaToolCalls is List) {
        for (int i = 0; i < deltaToolCalls.length; i++) {
          final Map<String, Object?> tcDelta = _asObjectMap(deltaToolCalls[i]);
          final int index = (tcDelta['index'] as num?)?.toInt() ?? i;
          final Map<String, Object?> fn = _asObjectMap(tcDelta['function']);
          final Map<String, String> acc = toolCallsAccumulated.putIfAbsent(
            index,
            () => <String, String>{
              'id': '${tcDelta['id'] ?? ''}',
              'name': '${fn['name'] ?? ''}',
              'arguments': '',
            },
          );
          if (tcDelta['id'] is String && (tcDelta['id'] as String).isNotEmpty) {
            acc['id'] = tcDelta['id'] as String;
          }
          if (fn['name'] is String && (fn['name'] as String).isNotEmpty) {
            acc['name'] = fn['name'] as String;
          }
          final String argsDelta = '${fn['arguments'] ?? ''}';
          if (argsDelta.isNotEmpty) {
            acc['arguments'] = '${acc['arguments'] ?? ''}$argsDelta';
          }
          yield LlmResponse(
            partial: true,
            content: Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: acc['name'] ?? '',
                  id: (acc['id'] ?? '').isEmpty ? null : acc['id'],
                  partialArgs: argsDelta.isEmpty
                      ? null
                      : <Map<String, Object?>>[
                          <String, Object?>{'arguments': argsDelta},
                        ],
                  willContinue: true,
                ),
              ],
            ),
          );
        }
      }
    }

    final List<Part> finalParts = <Part>[];
    if (textAccumulated.isNotEmpty) {
      finalParts.add(Part.text(textAccumulated.toString()));
    }
    final List<int> sortedIndices = toolCallsAccumulated.keys.toList()..sort();
    for (final int idx in sortedIndices) {
      final Map<String, String> acc = toolCallsAccumulated[idx]!;
      finalParts.add(
        Part.fromFunctionCall(
          name: acc['name'] ?? '',
          id: (acc['id'] ?? '').isEmpty ? null : acc['id'],
          args: _loadsJsonObject(acc['arguments']),
        ),
      );
    }

    final String? mappedFinishReason = mapFinishReason(finishReason);
    if (finalParts.isEmpty &&
        mappedFinishReason != null &&
        mappedFinishReason != 'STOP') {
      yield LlmResponse(
        errorCode: mappedFinishReason,
        errorMessage:
            'OpenAI streaming response finished with reason "$finishReason" and no content.',
        finishReason: mappedFinishReason,
        usageMetadata: _chatUsageMetadata(usage),
      );
      return;
    }

    yield LlmResponse(
      content: Content(role: 'model', parts: finalParts),
      partial: false,
      usageMetadata: _chatUsageMetadata(usage),
      finishReason: mappedFinishReason,
    );
  }
}

/// Client interface for the OpenAI Responses API.
abstract class OpenAiResponsesClient {
  /// Creates a non-streaming response from [payload].
  Future<Map<String, Object?>> create({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  });

  /// Creates a streaming response from [payload] and yields event objects.
  Stream<Map<String, Object?>> createStream({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  });
}

/// HTTP-backed [OpenAiResponsesClient] for the OpenAI Responses API.
class HttpOpenAiResponsesClient implements OpenAiResponsesClient {
  /// Creates an HTTP client for the OpenAI Responses API.
  HttpOpenAiResponsesClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<Map<String, Object?>> create({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  }) async {
    final Uri uri = _resolveEndpointUri(baseUrl, '/responses');
    final http.Response response = await _httpClient.post(
      uri,
      headers: _buildJsonHeaders(headers),
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 400) {
      throw ChatCompletionsHttpException(
        response.statusCode,
        response.body,
        responseBody: response.body,
      );
    }
    return _decodeJsonMap(response.body);
  }

  @override
  Stream<Map<String, Object?>> createStream({
    required Map<String, Object?> payload,
    required String baseUrl,
    required Map<String, String> headers,
  }) async* {
    final Uri uri = _resolveEndpointUri(baseUrl, '/responses');
    final http.Request request = http.Request('POST', uri)
      ..headers.addAll(_buildJsonHeaders(headers, acceptSse: true))
      ..body = jsonEncode(payload);
    final http.StreamedResponse response = await _httpClient.send(request);
    if (response.statusCode >= 400) {
      final String body = await utf8.decodeStream(response.stream);
      throw ChatCompletionsHttpException(
        response.statusCode,
        body,
        responseBody: body,
      );
    }
    yield* _parseSseStream(response.stream);
  }
}

/// Accumulates OpenAI Responses API streaming events into incremental and final [LlmResponse]s.
class OpenAiResponsesStreamAccumulator {
  /// Creates a stream accumulator for OpenAI Responses API events.
  OpenAiResponsesStreamAccumulator({this.includeResponseMetadata = true});

  /// Whether to attach raw OpenAI response metadata to emitted responses.
  final bool includeResponseMetadata;

  /// Accumulated output items by key.
  final Map<Object, Map<String, Object?>> outputItems =
      <Object, Map<String, Object?>>{};

  /// Insertion order of output item keys.
  final List<Object> outputOrder = <Object>[];

  /// Tracked function call state by key.
  final Map<Object, Map<String, Object?>> functionCalls =
      <Object, Map<String, Object?>>{};

  /// Completed or incomplete response payload from terminal events.
  Map<String, Object?>? response;

  /// Model version reported by the stream.
  String? model;

  /// Response ID reported by the stream.
  String? responseId;

  /// Usage payload reported by the stream.
  Map<String, Object?>? usage;

  /// Whether the stream terminated with an error event.
  bool failed = false;

  /// Whether a reasoning delta stream is currently open.
  bool reasoningOpen = false;

  /// Processes one [event] from the Responses SSE stream and returns any [LlmResponse]s to emit.
  List<LlmResponse> processEvent(Map<String, Object?> event) {
    final String? eventType = event['type'] as String?;
    final List<LlmResponse> responses = <LlmResponse>[];

    if (eventType == 'response.created') {
      final Map<String, Object?> resp = _asObjectMap(event['response']);
      responseId = resp['id'] as String?;
      model = resp['model'] as String?;
    } else if (eventType == 'response.output_text.delta') {
      responses.addAll(_closeReasoningStream(event));
      final String delta = '${event['delta'] ?? ''}';
      final Object key = _streamOutputKey(event, 'message');
      final Map<String, Object?> item = _ensureOutputItem(key, 'message');
      _appendIndexedText(item, 'text', event, delta, 'content_index');
      responses.add(
        LlmResponse(
          content: Content(role: 'model', parts: <Part>[Part.text(delta)]),
          partial: true,
          modelVersion: model,
          interactionId: responseId,
        ),
      );
    } else if (eventType == 'response.reasoning_summary_text.delta' ||
        eventType == 'response.reasoning_text.delta') {
      final String delta = '${event['delta'] ?? ''}';
      reasoningOpen = true;
      final Object key = _streamOutputKey(event, 'reasoning');
      final Map<String, Object?> item = _ensureOutputItem(key, 'reasoning');
      _appendIndexedText(item, 'reasoning', event, delta, 'summary_index');
      responses.add(
        LlmResponse(
          content: Content(
            role: 'model',
            parts: <Part>[Part.text(delta, thought: true)],
          ),
          partial: true,
          modelVersion: model,
          interactionId: responseId,
        ),
      );
    } else if (eventType == 'response.output_item.added') {
      final Map<String, Object?> item = _asObjectMap(event['item']);
      final String? itemType = item['type'] as String?;
      if (itemType != 'reasoning') {
        responses.addAll(_closeReasoningStream(event));
      }
      final Object key = _streamOutputKey(event, item['call_id']);
      _ensureOutputItem(key, itemType);
      if (itemType == 'function_call') {
        _trackFunctionCallItem(key, item);
        final Map<String, Object?> call = functionCalls[key]!;
        responses.add(_partialFunctionCallResponse(call));
      }
    } else if (eventType == 'response.content_part.done' ||
        eventType == 'response.output_text.done') {
      responses.addAll(_closeReasoningStream(event));
      final Object key = _streamOutputKey(event, 'message');
      final Map<String, Object?> item = _ensureOutputItem(key, 'message');
      final Map<String, Object?> part = _asObjectMap(event['part']);
      final String text = '${event['text'] ?? part['text'] ?? ''}';
      if (text.isNotEmpty) {
        _setIndexedText(item, 'text', event, text, 'content_index');
      }
    } else if (eventType == 'response.reasoning_summary_text.done' ||
        eventType == 'response.reasoning_text.done' ||
        eventType == 'response.reasoning_summary_part.done') {
      final Object key = _streamOutputKey(event, 'reasoning');
      final Map<String, Object?> item = _ensureOutputItem(key, 'reasoning');
      final Map<String, Object?> part = _asObjectMap(event['part']);
      final String text = '${event['text'] ?? part['text'] ?? ''}';
      if (text.isNotEmpty) {
        _setIndexedText(item, 'reasoning', event, text, 'summary_index');
      }
      responses.addAll(_closeReasoningStream(event));
    } else if (eventType == 'response.function_call_arguments.delta') {
      responses.addAll(_closeReasoningStream(event));
      final Object key = _streamOutputKey(event, event['call_id']);
      _ensureOutputItem(key, 'function_call');
      final Map<String, Object?> call = functionCalls.putIfAbsent(
        key,
        () => <String, Object?>{
          'name': '${event['name'] ?? ''}',
          'call_id': event['call_id'],
          'arguments': '',
          'argument_deltas_emitted': false,
        },
      );
      if (event['name'] is String && (event['name'] as String).isNotEmpty) {
        call['name'] = event['name'];
      }
      if (call['call_id'] == null || '${call['call_id']}'.isEmpty) {
        call['call_id'] = event['call_id'] ?? '$key';
      }
      final String argumentDelta = '${event['delta'] ?? ''}';
      call['arguments'] = '${call['arguments'] ?? ''}$argumentDelta';
      if (argumentDelta.isNotEmpty) {
        call['argument_deltas_emitted'] = true;
        responses.add(
          _partialFunctionCallResponse(call, argumentDelta: argumentDelta),
        );
      }
    } else if (eventType == 'response.function_call_arguments.done') {
      responses.addAll(_closeReasoningStream(event));
      final Object key = _streamOutputKey(event, event['call_id']);
      _ensureOutputItem(key, 'function_call');
      final Map<String, Object?> call = functionCalls.putIfAbsent(
        key,
        () => <String, Object?>{
          'name': '${event['name'] ?? ''}',
          'call_id': event['call_id'],
          'arguments': '',
          'argument_deltas_emitted': false,
        },
      );
      if (event['name'] is String && (event['name'] as String).isNotEmpty) {
        call['name'] = event['name'];
      }
      if (call['call_id'] == null || '${call['call_id']}'.isEmpty) {
        call['call_id'] = event['call_id'] ?? '$key';
      }
      if (event['arguments'] is String) {
        call['arguments'] = event['arguments'];
      }
      final String argsStr = '${call['arguments'] ?? ''}';
      if (argsStr.isNotEmpty && call['argument_deltas_emitted'] != true) {
        responses.add(
          _partialFunctionCallResponse(call, argumentDelta: argsStr),
        );
        call['argument_deltas_emitted'] = true;
      }
    } else if (eventType == 'response.output_item.done') {
      final Map<String, Object?> item = _asObjectMap(event['item']);
      final String? itemType = item['type'] as String?;
      if (itemType != 'reasoning') {
        responses.addAll(_closeReasoningStream(event));
      }
      final Object key = _streamOutputKey(event, item['call_id']);
      final Map<String, Object?> outputItem = _ensureOutputItem(key, itemType);
      outputItem['done_item'] = item;
      if (itemType == 'function_call') {
        _trackFunctionCallItem(key, item);
        final Map<String, Object?> call = functionCalls[key]!;
        final String argsStr = '${call['arguments'] ?? ''}';
        if (argsStr.isNotEmpty && call['argument_deltas_emitted'] != true) {
          responses.add(
            _partialFunctionCallResponse(call, argumentDelta: argsStr),
          );
          call['argument_deltas_emitted'] = true;
        }
      }
    } else if (eventType == 'response.completed' ||
        eventType == 'response.incomplete') {
      response = _asObjectMap(event['response']);
      final Map<String, Object?> respUsage = _asObjectMap(response?['usage']);
      if (respUsage.isNotEmpty) {
        usage = respUsage;
      }
    } else if (eventType == 'response.failed' || eventType == 'error') {
      failed = true;
      responses.add(
        LlmResponse(
          errorCode: 'OTHER',
          errorMessage: jsonEncode(event),
          finishReason: 'OTHER',
          interactionId: responseId,
        ),
      );
    }
    return responses;
  }

  /// Builds the final aggregated [LlmResponse] when the stream finishes.
  LlmResponse? finalResponse() {
    if (failed) {
      return null;
    }
    if (response != null && response!.isNotEmpty) {
      return OpenAIResponsesLlm.parseResponsesOutput(
        response!,
        includeResponseMetadata: includeResponseMetadata,
      );
    }

    final List<Part> parts = <Part>[];
    for (final Object key in outputOrder) {
      final Map<String, Object?> item = outputItems[key]!;
      final Map<String, Object?> doneItem = _asObjectMap(item['done_item']);
      final String? itemType = doneItem.isNotEmpty
          ? doneItem['type'] as String?
          : item['type'] as String?;
      if (doneItem.isNotEmpty && itemType == 'message') {
        final List<Part> messageParts = _messageContentParts(doneItem);
        if (messageParts.isNotEmpty) {
          parts.addAll(messageParts);
          continue;
        }
      }
      if (doneItem.isNotEmpty && itemType == 'reasoning') {
        final (List<Part> reasoningParts, _) = _reasoningParts(doneItem);
        if (reasoningParts.isNotEmpty) {
          parts.addAll(reasoningParts);
          continue;
        }
      }
      if (itemType == 'reasoning') {
        final String reasoningText = _assembledText(item, 'reasoning');
        if (reasoningText.isNotEmpty) {
          parts.add(Part.text(reasoningText, thought: true));
        }
      } else if (itemType == 'message') {
        final String text = _assembledText(item, 'text');
        if (text.isNotEmpty) {
          parts.add(Part.text(text));
        }
      } else if (itemType == 'function_call' &&
          functionCalls.containsKey(key)) {
        parts.add(_functionCallPartFromAccumulator(key));
      }
    }
    for (final Object key in functionCalls.keys) {
      if (!outputItems.containsKey(key)) {
        parts.add(_functionCallPartFromAccumulator(key));
      }
    }
    if (parts.isEmpty) {
      return null;
    }
    return LlmResponse(
      content: Content(role: 'model', parts: parts),
      partial: false,
      finishReason: 'STOP',
      interactionId: responseId,
      modelVersion: model,
      usageMetadata: _responsesUsageMetadata(usage),
    );
  }

  LlmResponse _partialFunctionCallResponse(
    Map<String, Object?> call, {
    String? argumentDelta,
  }) {
    return LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[
          Part.fromFunctionCall(
            id: call['call_id'] as String?,
            name: '${call['name'] ?? ''}',
            partialArgs: (argumentDelta == null || argumentDelta.isEmpty)
                ? null
                : <Map<String, Object?>>[
                    <String, Object?>{'arguments': argumentDelta},
                  ],
            willContinue: true,
          ),
        ],
      ),
      partial: true,
      modelVersion: model,
      interactionId: responseId,
    );
  }

  List<LlmResponse> _closeReasoningStream(Map<String, Object?> event) {
    if (!reasoningOpen) {
      return const <LlmResponse>[];
    }
    reasoningOpen = false;
    if (!includeResponseMetadata) {
      return const <LlmResponse>[];
    }
    final Map<String, Object?> streamEvent = <String, Object?>{
      'type': event['type'],
      'reasoning_done': true,
      for (final String key in const <String>[
        'output_index',
        'item_id',
        'summary_index',
      ])
        if (event[key] != null) key: event[key],
    };
    return <LlmResponse>[
      LlmResponse(
        partial: true,
        modelVersion: model,
        interactionId: responseId,
        customMetadata: <String, dynamic>{
          'openai_response': <String, Object?>{'stream_event': streamEvent},
        },
      ),
    ];
  }

  Object _streamOutputKey(Map<String, Object?> event, Object? fallback) {
    final Object? outputIndex = event['output_index'];
    if (outputIndex is int) {
      return outputIndex;
    }
    final Object? itemId = event['item_id'];
    if (itemId != null && '$itemId'.isNotEmpty) {
      return '$itemId';
    }
    return '${fallback ?? ''}';
  }

  Map<String, Object?> _ensureOutputItem(Object key, String? itemType) {
    final Map<String, Object?> item = outputItems.putIfAbsent(key, () {
      outputOrder.add(key);
      return <String, Object?>{};
    });
    if (itemType != null && !item.containsKey('type')) {
      item['type'] = itemType;
    }
    return item;
  }

  void _appendIndexedText(
    Map<String, Object?> item,
    String field,
    Map<String, Object?> event,
    String delta,
    String indexField,
  ) {
    final Object? index = event[indexField];
    if (index == null) {
      item[field] = '${item[field] ?? ''}$delta';
      return;
    }
    final Map<int, String> parts =
        (item.putIfAbsent('${field}_parts', () => <int, String>{})
            as Map<int, String>);
    final int idx = (index as num).toInt();
    parts[idx] = '${parts[idx] ?? ''}$delta';
  }

  void _setIndexedText(
    Map<String, Object?> item,
    String field,
    Map<String, Object?> event,
    String text,
    String indexField,
  ) {
    final Object? index = event[indexField];
    if (index == null) {
      item[field] = text;
      item.remove('${field}_parts');
      return;
    }
    final Map<int, String> parts =
        (item.putIfAbsent('${field}_parts', () => <int, String>{})
            as Map<int, String>);
    parts[(index as num).toInt()] = text;
  }

  String _assembledText(Map<String, Object?> item, String field) {
    final String text = '${item[field] ?? ''}';
    final Map<int, String>? parts = item['${field}_parts'] as Map<int, String>?;
    if (parts == null || parts.isEmpty) {
      return text;
    }
    final List<int> keys = parts.keys.toList()..sort();
    return text + keys.map((int k) => parts[k] ?? '').join();
  }

  void _trackFunctionCallItem(Object key, Map<String, Object?> item) {
    _ensureOutputItem(key, 'function_call');
    final Map<String, Object?> existing =
        functionCalls[key] ?? const <String, Object?>{};
    final String? arguments = item['arguments'] as String?;
    final String callId =
        '${item['call_id'] ?? item['id'] ?? existing['call_id'] ?? key}';
    functionCalls[key] = <String, Object?>{
      'name': '${item['name'] ?? existing['name'] ?? ''}',
      'call_id': callId,
      'arguments': (arguments != null && arguments.isNotEmpty)
          ? arguments
          : '${existing['arguments'] ?? ''}',
      'argument_deltas_emitted': existing['argument_deltas_emitted'] == true,
    };
  }

  Part _functionCallPartFromAccumulator(Object key) {
    final Map<String, Object?> call = functionCalls[key]!;
    return Part.fromFunctionCall(
      name: '${call['name'] ?? ''}',
      args: _loadsJsonObject(call['arguments'] as String?),
      id: call['call_id'] as String?,
    );
  }
}

/// ADK model implementation backed by the OpenAI Responses API.
///
/// ```dart
/// final llm = OpenAIResponsesLlm(
///   model: 'gpt-5',
///   apiKey: 'sk-...',
///   reasoning: {'effort': 'medium', 'summary': 'concise'},
/// );
/// ```
class OpenAIResponsesLlm extends BaseLlm {
  /// Creates an OpenAI Responses API model adapter.
  OpenAIResponsesLlm({
    super.model = 'gpt-5',
    this.apiKey,
    this.apiKeyProvider,
    this.baseUrl,
    this.client,
    this.store,
    this.include,
    this.reasoning,
    this.parallelToolCalls,
    this.truncation,
    this.serviceTier,
    this.includeResponseMetadata = true,
    Map<String, Object?>? extraRequestArgs,
    Map<String, String>? headers,
    Map<String, String>? environment,
  }) : extraRequestArgs = extraRequestArgs ?? const <String, Object?>{},
       headers = headers ?? const <String, String>{},
       environment = environment ?? _safeEnvironment;

  /// Optional explicit API key. Falls back to `OPENAI_API_KEY`.
  final String? apiKey;

  /// Optional synchronous or asynchronous callback returning an API key per request.
  final OpenAiApiKeyProvider? apiKeyProvider;

  /// Optional base URL override for the OpenAI Responses endpoint.
  final String? baseUrl;

  /// Optional injected [OpenAiResponsesClient].
  final OpenAiResponsesClient? client;

  /// Whether the response should be stored on the OpenAI backend.
  final bool? store;

  /// Additional output data to include in the model response.
  final List<String>? include;

  /// Instance-level reasoning configuration map (for example, `{'effort': 'medium', 'summary': 'concise'}`).
  final Map<String, Object?>? reasoning;

  /// Whether to allow parallel function tool calls.
  final bool? parallelToolCalls;

  /// Truncation strategy (`'auto'` or `'disabled'`).
  final String? truncation;

  /// Service tier used for processing the request.
  final String? serviceTier;

  /// Whether raw OpenAI response metadata is included in `LlmResponse.customMetadata`.
  final bool includeResponseMetadata;

  /// Additional top-level request arguments merged into the Responses API payload.
  final Map<String, Object?> extraRequestArgs;

  /// Additional HTTP headers sent with each request.
  final Map<String, String> headers;

  /// Environment map used for API key and base URL lookup.
  final Map<String, String> environment;

  /// Regex patterns supported by this adapter (empty by default, explicit instantiation).
  static List<RegExp> supportedModels() => const <RegExp>[];

  /// Azure endpoint URL if this instance is an [AzureOpenAIResponsesLlm], or `null`.
  String? get azureEndpointOrNull => null;

  /// Environment variable name used for API key fallback.
  String get defaultApiKeyEnv => _openAiApiKeyEnv;

  /// Effective base URL used for HTTP requests.
  String get effectiveBaseUrl {
    if (baseUrl != null && baseUrl!.isNotEmpty) {
      return baseUrl!;
    }
    final String? envBase = environment[_openAiBaseUrlEnv];
    if (envBase != null && envBase.isNotEmpty) {
      return envBase;
    }
    return _defaultOpenAiResponsesUrl;
  }

  /// Assembles the OpenAI Responses API request payload for [request].
  Map<String, Object?> buildResponseCreateKwargs(
    LlmRequest request, {
    required bool stream,
  }) {
    final GenerateContentConfig config = request.config;
    final String effectiveModel = _openAiModelId(request.model ?? model);
    final Map<String, Object?> kwargs = <String, Object?>{
      'model': effectiveModel,
      'input': _getResponseInput(request),
      'stream': stream,
    };

    final String? instructions = serializeSystemInstruction(
      config.systemInstruction,
    );
    if (instructions != null && instructions.isNotEmpty) {
      kwargs['instructions'] = instructions;
    }
    if (request.previousInteractionId != null &&
        request.previousInteractionId!.isNotEmpty) {
      kwargs['previous_response_id'] = request.previousInteractionId;
    }

    _applyConfig(config, kwargs);
    stripUnsupportedSamplingParams(kwargs, kwargs['model'] as String?);
    _applyModelOptions(kwargs);

    final Map<String, Object?> extraArgs = Map<String, Object?>.from(
      extraRequestArgs,
    );
    final Map<String, Object?> extraBody = <String, Object?>{
      ..._asObjectMap(kwargs['extra_body']),
      ..._asObjectMap(extraArgs.remove('extra_body')),
    };
    kwargs.addAll(extraArgs);

    final Object? tools = kwargs['tools'];
    if (tools is List &&
        tools.isNotEmpty &&
        !kwargs.containsKey('tool_choice')) {
      final String? choice = toolChoice(config);
      if (choice != null) {
        kwargs['tool_choice'] = choice;
      }
    }
    if (extraBody.isNotEmpty) {
      kwargs['extra_body'] = extraBody;
    }

    kwargs.removeWhere((String key, Object? value) => value == null);
    return kwargs;
  }

  List<Map<String, Object?>> _getResponseInput(LlmRequest request) {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    final _CallIdSanitizer sanitizer = _CallIdSanitizer();
    for (final Content content in request.contents) {
      items.addAll(_contentToResponseInputItems(content, sanitizer));
    }
    return items;
  }

  void _applyConfig(
    GenerateContentConfig config,
    Map<String, Object?> kwargs,
  ) {
    if (config.temperature != null) {
      kwargs['temperature'] = config.temperature;
    }
    if (config.topP != null) {
      kwargs['top_p'] = config.topP;
    }
    if (config.maxOutputTokens != null) {
      kwargs['max_output_tokens'] = config.maxOutputTokens;
    }
    if (config.stopSequences.isNotEmpty) {
      kwargs['extra_body'] = <String, Object?>{
        ..._asObjectMap(kwargs['extra_body']),
        'stop': List<String>.from(config.stopSequences),
      };
    }
    final Map<String, Object?>? textConfig = _responseTextConfig(config);
    if (textConfig != null) {
      kwargs['text'] = textConfig;
    }

    final bool validateEffort = targetsDefaultOpenAiHost(
      client: client,
      baseUrl: baseUrl,
      azureEndpoint: azureEndpointOrNull,
      environment: environment,
    );
    final String? effort = buildReasoningEffort(
      config,
      kwargs['model'] as String?,
      'responses',
      validate: validateEffort,
    );
    if (effort != null) {
      if (reasoning != null) {
        kwargs['reasoning'] = <String, Object?>{
          ...reasoning!,
          'effort': effort,
        };
      } else {
        kwargs['reasoning'] = <String, Object?>{
          'effort': effort,
          'summary': 'concise',
        };
      }
    }

    final List<Map<String, Object?>> tools = toOpenAiResponsesTools(
      config.tools,
    );
    if (tools.isNotEmpty) {
      kwargs['tools'] = tools;
    }
  }

  void _applyModelOptions(Map<String, Object?> kwargs) {
    kwargs['store'] = store;
    kwargs['include'] = include == null ? null : List<String>.from(include!);
    if (!kwargs.containsKey('reasoning') && reasoning != null) {
      kwargs['reasoning'] = Map<String, Object?>.from(reasoning!);
    }
    kwargs['parallel_tool_calls'] = parallelToolCalls;
    kwargs['truncation'] = truncation;
    kwargs['service_tier'] = serviceTier;
  }

  /// Converts a raw Responses API [response] map into an ADK [LlmResponse].
  static LlmResponse parseResponsesOutput(
    Map<String, Object?> response, {
    bool includeResponseMetadata = true,
  }) {
    final List<Part> parts = <Part>[];
    final List<Map<String, Object?>> outputMetadata = <Map<String, Object?>>[];
    final List<Map<String, Object?>> reasoningMetadata =
        <Map<String, Object?>>[];
    final List<Map<String, Object?>> unmappedOutput = <Map<String, Object?>>[];

    final Object? rawOutput = response['output'];
    if (rawOutput is List) {
      for (final Object? rawItem in rawOutput) {
        final Map<String, Object?> item = _asObjectMap(rawItem);
        final String? itemType = item['type'] as String?;
        if (itemType == 'message') {
          parts.addAll(_messageContentParts(item));
        } else if (itemType == 'function_call') {
          parts.add(_functionCallPart(item));
        } else if (itemType == 'reasoning') {
          final (
            List<Part> reasoningParts,
            Map<String, Object?> meta,
          ) = _reasoningParts(item);
          parts.addAll(reasoningParts);
          if (meta.isNotEmpty) {
            reasoningMetadata.add(meta);
          }
        } else {
          unmappedOutput.add(item);
        }
        if (itemType != null) {
          outputMetadata.add(item);
        }
      }
    }

    final Map<String, Object?> usage = _asObjectMap(response['usage']);
    Map<String, dynamic>? customMetadata;
    if (includeResponseMetadata) {
      final Map<String, Object?> openaiResponse = <String, Object?>{
        'id': response['id'],
        'status': response['status'],
        'output': outputMetadata,
        if (usage.isNotEmpty) 'usage': usage,
        if (reasoningMetadata.isNotEmpty) 'reasoning': reasoningMetadata,
        if (unmappedOutput.isNotEmpty) 'unmapped_output': unmappedOutput,
      };
      customMetadata = <String, dynamic>{'openai_response': openaiResponse};
    }

    final String? finishReason = _mapResponsesFinishReason(response);
    final LlmResponse llmResponse = LlmResponse(
      content: parts.isEmpty ? null : Content(role: 'model', parts: parts),
      usageMetadata: _responsesUsageMetadata(usage),
      finishReason: finishReason,
      modelVersion: response['model'] as String?,
      interactionId: response['id'] as String?,
      customMetadata: customMetadata,
    );
    if (finishReason != null && finishReason != 'STOP') {
      final Object? error = response['error'] ?? response['incomplete_details'];
      llmResponse.errorCode = finishReason;
      if (error != null) {
        llmResponse.errorMessage = jsonEncode(error);
      }
    }
    return llmResponse;
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final String resolvedApiKey = await _resolveApiKey(
      apiKey: apiKey,
      apiKeyProvider: apiKeyProvider,
      environment: environment,
      envVarName: defaultApiKeyEnv,
    );
    final Map<String, String> requestHeaders = <String, String>{
      ...headers,
      if (resolvedApiKey.isNotEmpty) 'Authorization': 'Bearer $resolvedApiKey',
    };

    final Map<String, Object?> kwargs = buildResponseCreateKwargs(
      request,
      stream: stream,
    );
    final OpenAiResponsesClient activeClient =
        client ?? HttpOpenAiResponsesClient();

    if (!stream) {
      final Map<String, Object?> response = await activeClient.create(
        payload: kwargs,
        baseUrl: effectiveBaseUrl,
        headers: requestHeaders,
      );
      yield parseResponsesOutput(
        response,
        includeResponseMetadata: includeResponseMetadata,
      );
      return;
    }

    final OpenAiResponsesStreamAccumulator accumulator =
        OpenAiResponsesStreamAccumulator(
          includeResponseMetadata: includeResponseMetadata,
        );
    await for (final Map<String, Object?> event in activeClient.createStream(
      payload: kwargs,
      baseUrl: effectiveBaseUrl,
      headers: requestHeaders,
    )) {
      for (final LlmResponse partial in accumulator.processEvent(event)) {
        yield partial;
      }
    }
    final LlmResponse? finalResp = accumulator.finalResponse();
    if (finalResp != null) {
      yield finalResp;
    }
  }
}

/// Azure OpenAI-compatible Responses API model adapter.
///
/// ```dart
/// final llm = AzureOpenAIResponsesLlm(
///   model: 'my-gpt-5-deployment',
///   azureEndpoint: 'https://my-resource.openai.azure.com',
///   apiKey: 'azure-api-key',
/// );
/// ```
class AzureOpenAIResponsesLlm extends OpenAIResponsesLlm {
  /// Creates an Azure OpenAI Responses API model adapter.
  AzureOpenAIResponsesLlm({
    super.model = 'gpt-5',
    this.azureEndpoint,
    super.apiKey,
    super.apiKeyProvider,
    super.baseUrl,
    super.client,
    super.store,
    super.include,
    super.reasoning,
    super.parallelToolCalls,
    super.truncation,
    super.serviceTier,
    super.includeResponseMetadata = true,
    super.extraRequestArgs,
    super.headers,
    super.environment,
  });

  /// Azure OpenAI resource endpoint URL (converted into `<azureEndpoint>/openai/v1/`).
  final String? azureEndpoint;

  @override
  String? get azureEndpointOrNull => azureEndpoint;

  @override
  String get defaultApiKeyEnv => _azureOpenAiApiKeyEnv;

  @override
  String get effectiveBaseUrl {
    if (azureEndpoint != null && azureEndpoint!.isNotEmpty) {
      final String trimmed = azureEndpoint!.replaceAll(RegExp(r'/+$'), '');
      return '$trimmed/openai/v1/responses';
    }
    return super.effectiveBaseUrl;
  }
}

class _CallIdSanitizer {
  final Map<String, String> _mapping = <String, String>{};
  int _nextFallback = 0;

  String sanitize(String? callId) {
    if (callId != null &&
        callId.isNotEmpty &&
        _validCallIdRegex.hasMatch(callId)) {
      return callId;
    }
    if (callId == null || callId.isEmpty) {
      final String fallback = 'call_adk_fallback_${_nextFallback++}';
      return fallback;
    }
    return _mapping.putIfAbsent(
      callId,
      () => 'call_adk_fallback_${_nextFallback++}',
    );
  }
}

bool _hasThinkingConfig(Object? thinkingConfig) {
  if (thinkingConfig == null) {
    return false;
  }
  if (thinkingConfig is Map) {
    return thinkingConfig['thinking_level'] != null ||
        thinkingConfig['thinkingLevel'] != null ||
        thinkingConfig['thinking_budget'] != null ||
        thinkingConfig['thinkingBudget'] != null;
  }
  try {
    final dynamic dyn = thinkingConfig;
    if (dyn.thinkingLevel != null) {
      return true;
    }
  } catch (_) {}
  try {
    final dynamic dyn = thinkingConfig;
    if (dyn.thinkingBudget != null) {
      return true;
    }
  } catch (_) {}
  return false;
}

String _openAiModelId(String model) {
  final String trimmed = model.trim();
  if (trimmed.startsWith('openai/')) {
    return trimmed.substring('openai/'.length);
  }
  return trimmed;
}

Future<String> _resolveApiKey({
  required String? apiKey,
  required OpenAiApiKeyProvider? apiKeyProvider,
  required Map<String, String> environment,
  required String envVarName,
}) async {
  if (apiKeyProvider != null) {
    return await apiKeyProvider();
  }
  if (apiKey != null && apiKey.isNotEmpty) {
    return apiKey;
  }
  return environment[envVarName] ?? environment[_openAiApiKeyEnv] ?? '';
}

List<Map<String, Object?>> _contentToOpenAiChatMessages(Content content) {
  final List<Map<String, Object?>> messages = <Map<String, Object?>>[];
  final String role = _toOpenAiChatRole(content.role);
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  final List<Object> contentParts = <Object>[];

  for (final Part part in content.parts) {
    if (part.functionCall != null) {
      final FunctionCall fc = part.functionCall!;
      toolCalls.add(<String, Object?>{
        'id': fc.id ?? '',
        'type': 'function',
        'function': <String, Object?>{
          'name': fc.name,
          'arguments': fc.args.isNotEmpty ? jsonEncode(fc.args) : '{}',
        },
      });
    } else if (part.functionResponse != null) {
      final FunctionResponse fr = part.functionResponse!;
      messages.add(<String, Object?>{
        'role': 'tool',
        'tool_call_id': fr.id ?? '',
        'content': jsonEncode(fr.response),
      });
    } else {
      final Object converted = _partToOpenAiChatContent(part);
      contentParts.add(converted);
    }
  }

  final List<Map<String, Object?>> processedParts = <Map<String, Object?>>[];
  for (final Object c in contentParts) {
    if (c is String && c.isNotEmpty) {
      processedParts.add(<String, Object?>{'type': 'text', 'text': c});
    } else if (c is Map<String, Object?>) {
      processedParts.add(c);
    }
  }

  final bool hasImages = processedParts.any(
    (Map<String, Object?> p) => p['type'] == 'image_url',
  );
  final Object contentVal = !hasImages
      ? processedParts
            .where((Map<String, Object?> p) => p['type'] == 'text')
            .map((Map<String, Object?> p) => '${p['text'] ?? ''}')
            .join('\n')
      : processedParts;
  final bool hasContent = contentVal is String
      ? contentVal.isNotEmpty
      : (contentVal as List).isNotEmpty;

  if (role == 'assistant' && (hasContent || toolCalls.isNotEmpty)) {
    final Map<String, Object?> msg = <String, Object?>{'role': 'assistant'};
    if (hasContent) {
      msg['content'] = contentVal;
    }
    if (toolCalls.isNotEmpty) {
      msg['tool_calls'] = toolCalls;
    }
    messages.add(msg);
  } else if (role == 'user' && hasContent) {
    messages.add(<String, Object?>{'role': 'user', 'content': contentVal});
  } else if (role == 'system' && hasContent) {
    final String textOnly = contentVal is List
        ? contentVal
              .whereType<Map<String, Object?>>()
              .where((Map<String, Object?> p) => p['type'] == 'text')
              .map((Map<String, Object?> p) => '${p['text'] ?? ''}')
              .join('\n')
        : '$contentVal';
    messages.add(<String, Object?>{'role': 'system', 'content': textOnly});
  }

  return messages;
}

String _toOpenAiChatRole(String? role) {
  if (role == 'model' || role == 'assistant') {
    return 'assistant';
  }
  if (role == 'system') {
    return 'system';
  }
  if (role == 'tool') {
    return 'tool';
  }
  return 'user';
}

Object _partToOpenAiChatContent(Part part) {
  if (part.thought && part.text != null && part.text!.isNotEmpty) {
    return 'Thought: ${part.text}';
  }
  if (part.text != null && part.text!.isNotEmpty) {
    return part.text!;
  }
  if (part.inlineData != null) {
    final String encoded = base64Encode(part.inlineData!.data);
    return <String, Object?>{
      'type': 'image_url',
      'image_url': <String, Object?>{
        'url': 'data:${part.inlineData!.mimeType};base64,$encoded',
      },
    };
  }
  if (part.fileData != null && part.fileData!.fileUri.startsWith('http')) {
    return <String, Object?>{
      'type': 'image_url',
      'image_url': <String, Object?>{'url': part.fileData!.fileUri},
    };
  }
  return '';
}

Map<String, Object?>? _buildChatResponseFormat(GenerateContentConfig config) {
  final Object? rawSchema = config.responseSchema ?? config.responseJsonSchema;
  if (rawSchema is Map) {
    final Map<String, dynamic> schemaDict = _deepCopySchemaMap(rawSchema);
    final String schemaName = '${schemaDict['title'] ?? 'response'}';
    enforceStrictOpenAiSchema(schemaDict);
    return <String, Object?>{
      'type': 'json_schema',
      'json_schema': <String, Object?>{
        'name': schemaName,
        'strict': true,
        'schema': schemaDict,
      },
    };
  }
  if (config.responseMimeType == 'application/json') {
    return const <String, Object?>{'type': 'json_object'};
  }
  return null;
}

Map<String, Object?>? _responseTextConfig(GenerateContentConfig config) {
  final Object? rawSchema = config.responseSchema ?? config.responseJsonSchema;
  if (rawSchema is Map) {
    final Map<String, dynamic> schemaDict = toOpenAiSchema(
      rawSchema.map((Object? k, Object? v) => MapEntry('$k', v)),
      strict: true,
    );
    if (schemaDict.isEmpty) {
      return null;
    }
    final String rawName = '${schemaDict['title'] ?? 'schema'}';
    final String sanitizedName = rawName.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    return <String, Object?>{
      'format': <String, Object?>{
        'type': 'json_schema',
        'name': sanitizedName.isEmpty ? 'schema' : sanitizedName,
        'strict': true,
        'schema': schemaDict,
      },
    };
  }
  if (config.responseMimeType == 'application/json') {
    return const <String, Object?>{
      'format': <String, Object?>{'type': 'json_object'},
    };
  }
  return null;
}

List<Map<String, Object?>> _contentToResponseInputItems(
  Content content,
  _CallIdSanitizer sanitizer,
) {
  final String role = _roleToResponsesRole(content.role);
  final List<Map<String, Object?>> items = <Map<String, Object?>>[];
  final List<Map<String, Object?>> messageParts = <Map<String, Object?>>[];

  void flushMessageParts() {
    if (messageParts.isNotEmpty) {
      items.add(<String, Object?>{
        'type': 'message',
        'role': role,
        'content': List<Map<String, Object?>>.from(messageParts),
      });
      messageParts.clear();
    }
  }

  void appendAssistantText(String text) {
    flushMessageParts();
    items.add(<String, Object?>{
      'type': 'message',
      'role': 'assistant',
      'content': text,
    });
  }

  for (final Part part in content.parts) {
    if (part.functionResponse != null) {
      flushMessageParts();
      final FunctionResponse fr = part.functionResponse!;
      items.add(<String, Object?>{
        'type': 'function_call_output',
        'call_id': sanitizer.sanitize(fr.id),
        'output': _serializeJsonValue(fr.response),
      });
    } else if (part.functionCall != null) {
      flushMessageParts();
      final FunctionCall fc = part.functionCall!;
      items.add(<String, Object?>{
        'type': 'function_call',
        'call_id': sanitizer.sanitize(fc.id),
        'name': fc.name,
        'arguments': jsonEncode(fc.args),
      });
    } else if (part.thought &&
        ((part.text != null && part.text!.isNotEmpty) ||
            (part.thoughtSignature != null &&
                part.thoughtSignature!.isNotEmpty))) {
      flushMessageParts();
    } else if (part.text != null && part.text!.isNotEmpty) {
      if (role == 'assistant') {
        appendAssistantText(part.text!);
      } else {
        messageParts.add(<String, Object?>{
          'type': 'input_text',
          'text': part.text!,
        });
      }
    } else if (part.inlineData != null) {
      if (role == 'assistant') {
        continue;
      }
      final InlineData inline = part.inlineData!;
      final String encoded = base64Encode(inline.data);
      final String mimeType = inline.mimeType.isEmpty
          ? 'application/octet-stream'
          : inline.mimeType;
      if (mimeType.startsWith('image/')) {
        messageParts.add(<String, Object?>{
          'type': 'input_image',
          'detail': 'auto',
          'image_url': 'data:$mimeType;base64,$encoded',
        });
      } else {
        messageParts.add(<String, Object?>{
          'type': 'input_file',
          'filename': inline.displayName ?? 'inline_data',
          'file_data': 'data:$mimeType;base64,$encoded',
        });
      }
    } else if (part.fileData != null) {
      if (role == 'assistant') {
        continue;
      }
      final FileData file = part.fileData!;
      final String mimeType = file.mimeType ?? '';
      if (mimeType.startsWith('image/')) {
        messageParts.add(<String, Object?>{
          'type': 'input_image',
          'detail': 'auto',
          'image_url': file.fileUri,
        });
      } else if (file.fileUri.startsWith('file-')) {
        messageParts.add(<String, Object?>{
          'type': 'input_file',
          'file_id': file.fileUri,
        });
      } else {
        messageParts.add(<String, Object?>{
          'type': 'input_file',
          'file_url': file.fileUri,
        });
      }
    } else if (part.executableCode != null ||
        part.codeExecutionResult != null) {
      final String? codeText = _codePartToText(part);
      if (codeText != null && codeText.isNotEmpty) {
        if (role == 'assistant') {
          appendAssistantText(codeText);
        } else {
          messageParts.add(<String, Object?>{
            'type': 'input_text',
            'text': codeText,
          });
        }
      }
    }
  }

  flushMessageParts();
  return items;
}

String _roleToResponsesRole(String? role) {
  if (role == 'model' || role == 'assistant') {
    return 'assistant';
  }
  if (role == 'system' || role == 'developer') {
    return role!;
  }
  return 'user';
}

String? _codePartToText(Part part) {
  if (part.executableCode != null) {
    final Object exec = part.executableCode!;
    final String code = exec is Map ? '${exec['code'] ?? ''}' : '$exec';
    return 'Code:```python\n$code\n```';
  }
  if (part.codeExecutionResult != null) {
    final Object res = part.codeExecutionResult!;
    final String output = res is Map ? '${res['output'] ?? ''}' : '$res';
    return 'Execution Result:```code_output\n$output\n```';
  }
  return null;
}

String _serializeJsonValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  if (value is Map) {
    final Object? content = value['content'];
    if (content is List && content.isNotEmpty) {
      final List<String> items = <String>[];
      for (final Object? item in content) {
        if (item is Map && item['type'] == 'text' && item['text'] != null) {
          items.add('${item['text']}');
        } else {
          items.add('$item');
        }
      }
      return items.join('\n');
    }
    if (content is String && content.isNotEmpty) {
      return content;
    }
    if (value.containsKey('result') && value['result'] != null) {
      final Object? result = value['result'];
      if (result is String) {
        return result;
      }
      return jsonEncode(result);
    }
  }
  return jsonEncode(value);
}

List<Part> _chatToolCallParts(Object? rawToolCalls) {
  if (rawToolCalls is! List) {
    return const <Part>[];
  }
  final List<Part> parts = <Part>[];
  for (final Object? rawCall in rawToolCalls) {
    final Map<String, Object?> call = _asObjectMap(rawCall);
    final Map<String, Object?> fn = _asObjectMap(call['function']);
    parts.add(
      Part.fromFunctionCall(
        name: '${fn['name'] ?? ''}',
        args: _loadsJsonObject(fn['arguments'] as String?),
        id: call['id'] as String?,
      ),
    );
  }
  return parts;
}

Map<String, Object?>? _chatUsageMetadata(Object? rawUsage) {
  final Map<String, Object?> usage = _asObjectMap(rawUsage);
  if (usage.isEmpty) {
    return null;
  }
  final Map<String, Object?> promptDetails = _asObjectMap(
    usage['prompt_tokens_details'],
  );
  final Map<String, Object?> completionDetails = _asObjectMap(
    usage['completion_tokens_details'],
  );
  final int? cachedTokens = (promptDetails['cached_tokens'] as num?)?.toInt();
  final int? reasoningTokens = (completionDetails['reasoning_tokens'] as num?)
      ?.toInt();
  return <String, Object?>{
    'prompt_token_count': (usage['prompt_tokens'] as num?)?.toInt(),
    'candidates_token_count': (usage['completion_tokens'] as num?)?.toInt(),
    'total_token_count': (usage['total_tokens'] as num?)?.toInt(),
    'cached_content_token_count': ?cachedTokens,
    'thoughts_token_count': ?reasoningTokens,
  };
}

Map<String, Object?>? _responsesUsageMetadata(Object? rawUsage) {
  final Map<String, Object?> usage = _asObjectMap(rawUsage);
  if (usage.isEmpty) {
    return null;
  }
  final int? inputTokens = (usage['input_tokens'] as num?)?.toInt();
  final int? outputTokens = (usage['output_tokens'] as num?)?.toInt();
  final int? totalTokens =
      (usage['total_tokens'] as num?)?.toInt() ??
      (inputTokens != null && outputTokens != null
          ? inputTokens + outputTokens
          : null);
  final Map<String, Object?> inputDetails = _asObjectMap(
    usage['input_tokens_details'],
  );
  final Map<String, Object?> outputDetails = _asObjectMap(
    usage['output_tokens_details'],
  );
  final int? cachedTokens = (inputDetails['cached_tokens'] as num?)?.toInt();
  final int? reasoningTokens = (outputDetails['reasoning_tokens'] as num?)
      ?.toInt();
  return <String, Object?>{
    'prompt_token_count': inputTokens,
    'candidates_token_count': outputTokens,
    'total_token_count': totalTokens,
    'cached_content_token_count': ?cachedTokens,
    'thoughts_token_count': ?reasoningTokens,
  };
}

String? _mapResponsesFinishReason(Map<String, Object?> response) {
  final String? status = response['status'] as String?;
  if (status == 'completed') {
    return 'STOP';
  }
  if (status == 'incomplete') {
    final Map<String, Object?> details = _asObjectMap(
      response['incomplete_details'],
    );
    final String? reason = details['reason'] as String?;
    if (reason == 'max_output_tokens' || reason == 'max_tokens') {
      return 'MAX_TOKENS';
    }
    return 'OTHER';
  }
  if (status == 'failed' || status == 'cancelled') {
    return 'OTHER';
  }
  return null;
}

List<Part> _messageContentParts(Map<String, Object?> item) {
  final List<Part> parts = <Part>[];
  final Object? rawContent = item['content'];
  if (rawContent is! List) {
    return parts;
  }
  for (final Object? entry in rawContent) {
    final Map<String, Object?> content = _asObjectMap(entry);
    final String? contentType = content['type'] as String?;
    final String? text = content['text'] as String?;
    if (contentType == 'output_text' && text != null && text.isNotEmpty) {
      parts.add(Part.text(text));
    } else if (contentType == 'refusal') {
      final String? refusal = (content['refusal'] as String?) ?? text;
      if (refusal != null && refusal.isNotEmpty) {
        parts.add(Part.text('$_refusalPrefix$refusal'));
      }
    }
  }
  return parts;
}

(List<Part>, Map<String, Object?>) _reasoningParts(Map<String, Object?> item) {
  final List<Part> parts = <Part>[];
  final Map<String, Object?> metadata = <String, Object?>{};
  final String? encryptedContent = item['encrypted_content'] as String?;
  final List<int>? signature = encryptedContent == null
      ? null
      : utf8.encode(encryptedContent);

  final Object? summary = item['summary'];
  if (summary is List) {
    for (final Object? s in summary) {
      final Map<String, Object?> summaryPart = _asObjectMap(s);
      final String? text = summaryPart['text'] as String?;
      if (text != null && text.isNotEmpty) {
        parts.add(Part.text(text, thought: true, thoughtSignature: signature));
      }
    }
  }
  final Object? content = item['content'];
  if (content is List) {
    for (final Object? c in content) {
      final Map<String, Object?> contentPart = _asObjectMap(c);
      final String? text = contentPart['text'] as String?;
      if (text != null && text.isNotEmpty) {
        parts.add(Part.text(text, thought: true, thoughtSignature: signature));
      }
    }
  }
  if (encryptedContent != null && encryptedContent.isNotEmpty) {
    metadata['encrypted_content'] = encryptedContent;
    if (parts.isEmpty) {
      parts.add(Part(thought: true, thoughtSignature: signature));
    }
  }
  if (item['id'] != null) {
    metadata['id'] = item['id'];
  }
  return (parts, metadata);
}

Part _functionCallPart(Map<String, Object?> item) {
  final String name = '${item['name'] ?? ''}';
  final String? arguments = item['arguments'] as String?;
  final String? callId = (item['call_id'] ?? item['id']) as String?;
  return Part.fromFunctionCall(
    name: name,
    args: _loadsJsonObject(arguments),
    id: callId,
  );
}

Map<String, dynamic> _loadsJsonObject(String? value) {
  if (value == null || value.trim().isEmpty) {
    return <String, dynamic>{};
  }
  try {
    final Object? parsed = jsonDecode(value);
    if (parsed is Map) {
      return parsed.map((Object? k, Object? v) => MapEntry('$k', v));
    }
  } catch (_) {}
  return <String, dynamic>{};
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return <String, Object?>{};
}

Map<String, dynamic> _deepCopySchemaMap(Map<Object?, Object?> source) {
  final Map<String, dynamic> result = <String, dynamic>{};
  source.forEach((Object? key, Object? value) {
    result['$key'] = _deepCopySchemaValue(value);
  });
  return result;
}

Object? _deepCopySchemaValue(Object? value) {
  if (value is Map) {
    return _deepCopySchemaMap(value);
  }
  if (value is List) {
    return value.map(_deepCopySchemaValue).toList();
  }
  return value;
}

void _lowercaseSchemaTypes(Map<String, dynamic> schema) {
  final Object? typeVal = schema['type'];
  if (typeVal is String) {
    schema['type'] = typeVal.toLowerCase();
  } else if (typeVal is List) {
    schema['type'] = typeVal
        .map((Object? e) => e is String ? e.toLowerCase() : e)
        .toList();
  }
  for (final Object? value in schema.values) {
    if (value is Map<String, dynamic>) {
      _lowercaseSchemaTypes(value);
    } else if (value is List) {
      for (final Object? item in value) {
        if (item is Map<String, dynamic>) {
          _lowercaseSchemaTypes(item);
        }
      }
    }
  }
}

Uri _resolveEndpointUri(String baseUrl, String suffix) {
  final String trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.endsWith(suffix)) {
    return Uri.parse(trimmed);
  }
  return Uri.parse('$trimmed$suffix');
}

Map<String, String> _buildJsonHeaders(
  Map<String, String> headers, {
  bool acceptSse = false,
}) {
  final Map<String, String> result = <String, String>{
    ...headers,
    'Content-Type': 'application/json',
  };
  if (acceptSse) {
    result.putIfAbsent('Accept', () => 'text/event-stream');
  }
  return result;
}

Map<String, Object?> _decodeJsonMap(String body) {
  if (body.trim().isEmpty) {
    return <String, Object?>{};
  }
  final Object? decoded = jsonDecode(body);
  if (decoded is Map) {
    return decoded.map((Object? k, Object? v) => MapEntry('$k', v));
  }
  return <String, Object?>{};
}

Stream<Map<String, Object?>> _parseSseStream(
  Stream<List<int>> byteStream,
) async* {
  final Stream<String> lines = byteStream
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final StringBuffer dataBuffer = StringBuffer();
  await for (final String line in lines) {
    if (line.isEmpty) {
      final String raw = dataBuffer.toString().trim();
      dataBuffer.clear();
      if (raw.isNotEmpty && raw != '[DONE]') {
        try {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map) {
            yield decoded.map((Object? k, Object? v) => MapEntry('$k', v));
          }
        } catch (_) {}
      }
      continue;
    }
    if (line.startsWith('data:')) {
      String value = line.substring('data:'.length);
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      dataBuffer.writeln(value);
    }
  }
  final String trailing = dataBuffer.toString().trim();
  if (trailing.isNotEmpty && trailing != '[DONE]') {
    try {
      final Object? decoded = jsonDecode(trailing);
      if (decoded is Map) {
        yield decoded.map((Object? k, Object? v) => MapEntry('$k', v));
      }
    } catch (_) {}
  }
}

Map<String, String> get _safeEnvironment {
  try {
    return readSystemEnvironment();
  } catch (_) {
    return <String, String>{};
  }
}

const Object _sentinel = Object();
