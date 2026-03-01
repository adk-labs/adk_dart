import 'dart:convert';

import '../types/content.dart';
import '../utils/env_utils.dart';
import '../utils/system_environment/system_environment.dart';
import 'google_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

const String _apigeeProxyUrlEnv = 'APIGEE_PROXY_URL';
const String _projectEnv = 'GOOGLE_CLOUD_PROJECT';
const String _locationEnv = 'GOOGLE_CLOUD_LOCATION';

enum ApiType {
  unknown('unknown'),
  chatCompletions('chat_completions'),
  genai('genai');

  const ApiType(this.value);

  final String value;

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

abstract class ApigeeCompletionsClient {
  Stream<LlmResponse> generateContent({
    required LlmRequest request,
    required bool stream,
    required String baseUrl,
    required Map<String, String> headers,
  });
}

class ApigeeLlm extends Gemini {
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

  final String? proxyUrl;
  final Map<String, String> customHeaders;
  final ApigeeCompletionsClient? completionsClient;
  final ApiType _apiType;

  late final ApiType _resolvedApiType;
  late final bool _isVertexAi;
  late final String _apiVersion;
  String? _project;
  String? _location;

  ApiType get resolvedApiType => _resolvedApiType;
  bool get isVertexAi => _isVertexAi;
  String get apiVersion => _apiVersion;
  String? get project => _project;
  String? get location => _location;

  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'apigee\/.*')];
  }

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

      if (completionsClient != null) {
        yield* completionsClient!.generateContent(
          request: prepared,
          stream: stream,
          baseUrl: configuredBaseUrl,
          headers: Map<String, String>.from(customHeaders),
        );
        return;
      }

      final String text = _extractUserText(prepared);
      yield LlmResponse(
        modelVersion: prepared.model,
        content: Content.modelText('Apigee completions response: $text'),
        turnComplete: true,
      );
      return;
    }

    yield* super.generateContent(prepared, stream: stream);
  }

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

  static String getModelId(String model) {
    final String normalized = model.replaceFirst(RegExp(r'^apigee/'), '');
    final List<String> segments = normalized.split('/');
    return segments.isEmpty ? model : segments.last;
  }

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
    final Map<String, Object?> usageMetadata = <String, Object?>{
      'prompt_token_count': usage['prompt_tokens'] ?? 0,
      'candidates_token_count': usage['completion_tokens'] ?? 0,
      'total_token_count': usage['total_tokens'] ?? 0,
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
        contentParts.add(<String, Object?>{'type': 'text', 'text': part.text});
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

  String _extractUserText(LlmRequest request) {
    for (int i = request.contents.length - 1; i >= 0; i -= 1) {
      final Content content = request.contents[i];
      if (content.role != 'user') {
        continue;
      }
      for (int j = content.parts.length - 1; j >= 0; j -= 1) {
        final String? text = content.parts[j].text;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    }
    return '';
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

Map<String, String> get _safeEnvironment {
  try {
    return readSystemEnvironment();
  } catch (_) {
    return <String, String>{};
  }
}
