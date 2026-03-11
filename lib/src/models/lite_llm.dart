/// LiteLLM-compatible OpenAI-style model adapter.
library;

import 'dart:convert';

import '../types/content.dart';
import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

/// Hook for overriding LiteLLM generation behavior.
typedef LiteLlmGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);

/// Callback that invokes a LiteLLM-compatible completions endpoint.
typedef LiteLlmCompletionsInvoker =
    Future<List<Map<String, Object?>>> Function({
      required Map<String, Object?> payload,
      required bool stream,
    });

/// OpenAI-compatible adapter that targets LiteLLM providers.
class LiteLlm extends BaseLlm {
  /// Creates a LiteLLM adapter for [model].
  LiteLlm({
    required super.model,
    this.customProvider = '',
    this.completionsInvoker,
    LiteLlmGenerateHook? generateHook,
  }) : _generateHook = generateHook;

  /// Optional explicit provider name override.
  final String customProvider;
  final LiteLlmGenerateHook? _generateHook;

  /// Optional invoker for completions responses.
  final LiteLlmCompletionsInvoker? completionsInvoker;

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
      messages.addAll(_contentToMessages(content));
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
      final Map<String, Object?> function = _asMap(callMap['function']);
      parts.add(_parseFunctionCall(function, callMap['id']));
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

    if (completionsInvoker != null) {
      final List<Map<String, Object?>> responses = await completionsInvoker!(
        payload: buildPayload(prepared, stream: stream),
        stream: stream,
      );
      for (final Map<String, Object?> response in responses) {
        yield parseCompletionResponse(response);
      }
      return;
    }

    if (_generateHook != null) {
      yield* _generateHook(prepared, stream);
      return;
    }

    final String text = _extractUserText(prepared);
    yield LlmResponse(
      modelVersion: prepared.model,
      content: Content.modelText('LiteLLM response: $text'),
      turnComplete: true,
    );
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
  final Map<String, Object?> details = _asMap(usage['completion_tokens_details']);
  return details['reasoning_tokens'] ?? details['reasoningTokens'];
}

List<Part> _extractReasoningParts(Object? raw, {Set<String>? reasoningTexts}) {
  final Set<String> seen = reasoningTexts ?? <String>{};
  final List<Part> parts = <Part>[];

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

List<Map<String, Object?>> _contentToMessages(Content content) {
  final String role = content.role == 'model' ? 'assistant' : '${content.role}';
  final List<Map<String, Object?>> output = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolResponses = <Map<String, Object?>>[];
  final List<Map<String, Object?>> toolCalls = <Map<String, Object?>>[];
  final List<Map<String, Object?>> parts = <Map<String, Object?>>[];

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
      parts.add(<String, Object?>{'type': 'text', 'text': part.text});
      continue;
    }
    if (part.inlineData != null) {
      parts.add(<String, Object?>{
        'type': 'image_url',
        'image_url': <String, Object?>{
          'url':
              'data:${part.inlineData!.mimeType};base64,${base64Encode(part.inlineData!.data)}',
        },
      });
    } else if (part.fileData != null && part.fileData!.fileUri.isNotEmpty) {
      parts.add(<String, Object?>{
        'type': 'file_url',
        'file_url': <String, Object?>{'url': part.fileData!.fileUri},
      });
    }
  }

  if (toolResponses.isNotEmpty) {
    return toolResponses;
  }

  final Map<String, Object?> message = <String, Object?>{'role': role};
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

Part _parseFunctionCall(Map<String, Object?> function, Object? id) {
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
  final String? callId = id == null ? null : '$id';
  return Part.fromFunctionCall(name: name, args: parsedArgs, id: callId);
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
