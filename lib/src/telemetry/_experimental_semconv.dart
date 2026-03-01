import 'dart:convert';
import 'dart:io';

import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../types/content.dart';

abstract class SpanAttributeWriter {
  void setAttribute(String key, Object? value);
}

class CompletionDetailsLogRecord {
  CompletionDetailsLogRecord({
    required this.eventName,
    this.body,
    Map<String, Object?>? attributes,
  }) : attributes = attributes ?? <String, Object?>{};

  final String eventName;
  final Object? body;
  final Map<String, Object?> attributes;
}

abstract class CompletionDetailsLogger {
  void emitCompletionDetailsLog(CompletionDetailsLogRecord record);
}

const String otelSemconvStabilityOptIn = 'OTEL_SEMCONV_STABILITY_OPT_IN';
const String otelInstrumentationGenaiCaptureMessageContent =
    'OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT';

const String genAiInputMessages = 'gen_ai.input.messages';
const String genAiOutputMessages = 'gen_ai.output.messages';
const String genAiResponseFinishReasons = 'gen_ai.response.finish_reasons';
const String genAiSystemInstructions = 'gen_ai.system.instructions';
const String genAiUsageInputTokens = 'gen_ai.usage.input_tokens';
const String genAiUsageOutputTokens = 'gen_ai.usage.output_tokens';
const String genAiToolDefinitions = 'gen_ai.tool_definitions';

const String functionToolDefinitionType = 'function';

bool isExperimentalSemconv({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String? optIns = env[otelSemconvStabilityOptIn];
  if (optIns == null || optIns.isEmpty) {
    return false;
  }

  for (final String value in optIns.split(',')) {
    if (value.trim() == 'gen_ai_latest_experimental') {
      return true;
    }
  }
  return false;
}

String getContentCapturingMode({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  return (env[otelInstrumentationGenaiCaptureMessageContent] ?? '')
      .toUpperCase();
}

Future<void> setOperationDetailsAttributesFromRequest(
  Map<String, Object?> operationDetailsAttributes,
  LlmRequest llmRequest,
) async {
  final List<Map<String, Object?>> inputMessages = _toInputMessages(
    llmRequest.contents,
  );
  final List<Map<String, Object?>> systemInstructions = _toSystemInstructions(
    llmRequest.config.systemInstruction,
  );

  final List<Map<String, Object?>> toolDefinitions = <Map<String, Object?>>[];
  final List<ToolDeclaration> tools =
      llmRequest.config.tools ?? const <ToolDeclaration>[];
  for (final ToolDeclaration tool in tools) {
    toolDefinitions.addAll(_toolToToolDefinition(tool));
  }

  operationDetailsAttributes[genAiInputMessages] = inputMessages;
  operationDetailsAttributes[genAiSystemInstructions] = systemInstructions;
  operationDetailsAttributes[genAiToolDefinitions] = toolDefinitions;
}

void setOperationDetailsCommonAttributes(
  Map<String, Object?> operationDetailsCommonAttributes,
  Map<String, Object?> attributes,
) {
  operationDetailsCommonAttributes.addAll(attributes);
}

void setOperationDetailsAttributesFromResponse(
  LlmResponse llmResponse,
  Map<String, Object?> operationDetailsAttributes,
  Map<String, Object?> operationDetailsCommonAttributes,
) {
  final String? normalizedFinishReason = _toFinishReason(
    llmResponse.finishReason,
  );
  if (normalizedFinishReason != null && normalizedFinishReason.isNotEmpty) {
    operationDetailsCommonAttributes[genAiResponseFinishReasons] = <String>[
      normalizedFinishReason,
    ];
  }

  final Map<String, Object?>? usage = _usageMetadataAsMap(
    llmResponse.usageMetadata,
  );
  if (usage != null) {
    final Object? promptTokenCount =
        usage['prompt_token_count'] ?? usage['promptTokenCount'];
    final Object? candidatesTokenCount =
        usage['candidates_token_count'] ?? usage['candidatesTokenCount'];

    if (promptTokenCount is num) {
      operationDetailsCommonAttributes[genAiUsageInputTokens] =
          promptTokenCount;
    }
    if (candidatesTokenCount is num) {
      operationDetailsCommonAttributes[genAiUsageOutputTokens] =
          candidatesTokenCount;
    }
  }

  final Map<String, Object?>? outputMessage = _toOutputMessage(llmResponse);
  if (outputMessage != null) {
    operationDetailsAttributes[genAiOutputMessages] = <Map<String, Object?>>[
      outputMessage,
    ];
  }
}

void maybeLogCompletionDetails(
  SpanAttributeWriter? span,
  CompletionDetailsLogger otelLogger,
  Map<String, Object?> operationDetailsAttributes,
  Map<String, Object?> operationDetailsCommonAttributes, {
  Map<String, String>? environment,
}) {
  if (span == null || !isExperimentalSemconv(environment: environment)) {
    return;
  }

  final String capturingMode = getContentCapturingMode(
    environment: environment,
  );
  final Map<String, Object?> finalAttributes = Map<String, Object?>.from(
    operationDetailsCommonAttributes,
  );

  if (capturingMode == 'EVENT_ONLY' || capturingMode == 'SPAN_AND_EVENT') {
    finalAttributes.addAll(operationDetailsAttributes);
  } else {
    finalAttributes.addAll(
      _operationDetailsAttributesNoContent(operationDetailsAttributes),
    );
  }

  otelLogger.emitCompletionDetailsLog(
    CompletionDetailsLogRecord(
      eventName: 'gen_ai.client.inference.operation.details',
      attributes: finalAttributes,
    ),
  );

  if (capturingMode == 'SPAN_ONLY' || capturingMode == 'SPAN_AND_EVENT') {
    for (final MapEntry<String, Object?> entry
        in operationDetailsAttributes.entries) {
      span.setAttribute(
        entry.key,
        _safeJsonSerializeNoWhitespaces(entry.value),
      );
    }
    return;
  }

  final Map<String, Object?> sanitized = _operationDetailsAttributesNoContent(
    operationDetailsAttributes,
  );
  for (final MapEntry<String, Object?> entry in sanitized.entries) {
    span.setAttribute(entry.key, _safeJsonSerializeNoWhitespaces(entry.value));
  }
}

Map<String, Object?> _operationDetailsAttributesNoContent(
  Map<String, Object?> operationDetailsAttributes,
) {
  final Object? toolDefinitionAttribute =
      operationDetailsAttributes[genAiToolDefinitions];
  if (toolDefinitionAttribute is! List) {
    return <String, Object?>{};
  }

  final List<Map<String, Object?>> sanitized = <Map<String, Object?>>[];
  for (final Object? definition in toolDefinitionAttribute) {
    if (definition is! Map) {
      continue;
    }

    final Map<String, Object?> asMap = definition.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
    if (asMap.containsKey('parameters')) {
      sanitized.add(<String, Object?>{
        'name': asMap['name'],
        'description': asMap['description'],
        'parameters': null,
        'type': asMap['type'],
      });
    } else {
      sanitized.add(asMap);
    }
  }

  if (sanitized.isEmpty) {
    return <String, Object?>{};
  }

  return <String, Object?>{genAiToolDefinitions: sanitized};
}

List<Map<String, Object?>> _toolToToolDefinition(ToolDeclaration tool) {
  final List<Map<String, Object?>> definitions = <Map<String, Object?>>[];

  for (final FunctionDeclaration declaration in tool.functionDeclarations) {
    definitions.add(<String, Object?>{
      'name': declaration.name,
      'description': declaration.description,
      'parameters': _cleanParameters(declaration.parameters),
      'type': functionToolDefinitionType,
    });
  }

  final Map<String, Object?> genericToolMap = <String, Object?>{
    'googleSearch': tool.googleSearch,
    'googleSearchRetrieval': tool.googleSearchRetrieval,
    'urlContext': tool.urlContext,
    'codeExecution': tool.codeExecution,
    'googleMaps': tool.googleMaps,
    'enterpriseWebSearch': tool.enterpriseWebSearch,
    'retrieval': tool.retrieval,
    'computerUse': tool.computerUse,
  };

  for (final MapEntry<String, Object?> entry in genericToolMap.entries) {
    if (entry.value != null) {
      definitions.add(<String, Object?>{'name': entry.key, 'type': entry.key});
    }
  }

  return definitions;
}

Object? _cleanParameters(Object? parameters) {
  if (parameters == null) {
    return null;
  }
  if (parameters is Map) {
    return parameters;
  }

  try {
    jsonEncode(parameters);
    return parameters;
  } catch (_) {
    return <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'serialization_error': <String, Object?>{
          'type': 'string',
          'description':
              'Failed to serialize parameters: ${parameters.runtimeType}',
        },
      },
    };
  }
}

List<Map<String, Object?>> _toInputMessages(List<Content> contents) {
  return contents.map(_toInputMessage).toList(growable: false);
}

Map<String, Object?> _toInputMessage(Content content) {
  final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
  for (int idx = 0; idx < content.parts.length; idx += 1) {
    final Map<String, Object?>? part = _toPart(content.parts[idx], idx);
    if (part != null) {
      parts.add(part);
    }
  }

  return <String, Object?>{'role': _toRole(content.role), 'parts': parts};
}

Map<String, Object?>? _toOutputMessage(LlmResponse llmResponse) {
  final Content? content = llmResponse.content;
  if (content == null) {
    return null;
  }

  final Map<String, Object?> message = _toInputMessage(content);
  return <String, Object?>{
    'role': message['role'],
    'parts': message['parts'],
    'finish_reason': _toFinishReason(llmResponse.finishReason) ?? '',
  };
}

Map<String, Object?>? _toPart(Part part, int idx) {
  String fallbackId(String? name) {
    if (name != null && name.isNotEmpty) {
      return '${name}_$idx';
    }
    return '$idx';
  }

  if (part.text != null) {
    return <String, Object?>{'content': part.text, 'type': 'text'};
  }

  if (part.inlineData != null) {
    return <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'data': part.inlineData!.data,
      'type': 'blob',
    };
  }

  if (part.fileData != null) {
    return <String, Object?>{
      'mime_type': part.fileData!.mimeType ?? '',
      'uri': part.fileData!.fileUri,
      'type': 'file_data',
    };
  }

  if (part.functionCall != null) {
    return <String, Object?>{
      'id': part.functionCall!.id ?? fallbackId(part.functionCall!.name),
      'name': part.functionCall!.name,
      'arguments': part.functionCall!.args,
      'type': 'tool_call',
    };
  }

  if (part.functionResponse != null) {
    return <String, Object?>{
      'id':
          part.functionResponse!.id ?? fallbackId(part.functionResponse!.name),
      'response': part.functionResponse!.response,
      'type': 'tool_call_response',
    };
  }

  return null;
}

String _toRole(String? role) {
  if (role == 'user') {
    return 'user';
  }
  if (role == 'model') {
    return 'assistant';
  }
  return '';
}

List<Map<String, Object?>> _toSystemInstructions(String? systemInstruction) {
  if (systemInstruction == null || systemInstruction.isEmpty) {
    return const <Map<String, Object?>>[];
  }

  return <Map<String, Object?>>[
    <String, Object?>{'content': systemInstruction, 'type': 'text'},
  ];
}

String? _toFinishReason(String? finishReason) {
  if (finishReason == null || finishReason.isEmpty) {
    return null;
  }

  final String normalized = finishReason.toLowerCase();
  if (normalized == 'finish_reason_unspecified' ||
      normalized == 'other' ||
      normalized == 'unspecified') {
    return 'error';
  }
  if (normalized == 'stop') {
    return 'stop';
  }
  if (normalized == 'max_tokens' || normalized == 'max_output_tokens') {
    return 'length';
  }
  return normalized;
}

Map<String, Object?>? _usageMetadataAsMap(Object? usageMetadata) {
  if (usageMetadata is Map<String, Object?>) {
    return usageMetadata;
  }
  if (usageMetadata is Map<String, dynamic>) {
    return usageMetadata.map(
      (String key, dynamic value) => MapEntry<String, Object?>(key, value),
    );
  }
  if (usageMetadata is Map) {
    return usageMetadata.map(
      (Object? key, Object? value) => MapEntry<String, Object?>('$key', value),
    );
  }
  return null;
}

String _safeJsonSerializeNoWhitespaces(Object? value) {
  try {
    return jsonEncode(_normalize(value));
  } catch (_) {
    return '<not serializable>';
  }
}

Object? _normalize(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? nestedValue) =>
          MapEntry<String, Object?>('$key', _normalize(nestedValue)),
    );
  }
  if (value is Iterable) {
    return value.map(_normalize).toList(growable: false);
  }
  return '$value';
}
