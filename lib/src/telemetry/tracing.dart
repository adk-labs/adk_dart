import 'dart:async';
import 'dart:convert';

import '../agents/invocation_context.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import 'base_telemetry_service.dart';

const String adkCaptureMessageContentInSpans =
    'ADK_CAPTURE_MESSAGE_CONTENT_IN_SPANS';

class TraceSpanRecord {
  TraceSpanRecord(this.name, {Map<String, Object?>? attributes})
    : attributes = attributes ?? <String, Object?>{};

  final String name;
  final Map<String, Object?> attributes;

  void setAttribute(String key, Object? value) {
    attributes[key] = value;
  }
}

class AdkTracer {
  final List<TraceSpanRecord> _spanStack = <TraceSpanRecord>[];
  final List<TraceSpanRecord> _finishedSpans = <TraceSpanRecord>[];

  TraceSpanRecord startAsCurrentSpan(
    String name, {
    Map<String, Object?>? attributes,
  }) {
    final TraceSpanRecord span = TraceSpanRecord(name, attributes: attributes);
    _spanStack.add(span);
    return span;
  }

  TraceSpanRecord? get currentSpan {
    if (_spanStack.isEmpty) {
      return null;
    }
    return _spanStack.last;
  }

  void endCurrentSpan() {
    if (_spanStack.isEmpty) {
      return;
    }
    _finishedSpans.add(_spanStack.removeLast());
  }

  List<TraceSpanRecord> get finishedSpans {
    return List<TraceSpanRecord>.unmodifiable(_finishedSpans);
  }

  T inSpan<T>(
    String name,
    T Function(TraceSpanRecord span) body, {
    Map<String, Object?>? attributes,
  }) {
    final TraceSpanRecord span = startAsCurrentSpan(
      name,
      attributes: attributes,
    );
    try {
      return body(span);
    } finally {
      endCurrentSpan();
    }
  }

  Future<T> inSpanAsync<T>(
    String name,
    Future<T> Function(TraceSpanRecord span) body, {
    Map<String, Object?>? attributes,
  }) async {
    final TraceSpanRecord span = startAsCurrentSpan(
      name,
      attributes: attributes,
    );
    try {
      return body(span);
    } finally {
      endCurrentSpan();
    }
  }

  void clear() {
    _spanStack.clear();
    _finishedSpans.clear();
  }
}

final AdkTracer tracer = AdkTracer();

Future<T> traceSpan<T>(
  BaseTelemetryService telemetryService,
  String name,
  Future<T> Function(TelemetrySpan span) run, {
  String? parentSpanId,
  Map<String, Object?>? attributes,
}) async {
  final TelemetrySpan span = telemetryService.startSpan(
    name,
    parentSpanId: parentSpanId,
    attributes: attributes,
  );
  try {
    final T value = await run(span);
    telemetryService.endSpan(span.id);
    return value;
  } catch (error) {
    telemetryService.endSpan(span.id, error: error);
    rethrow;
  }
}

void traceToolCall(
  BaseTool tool,
  Map<String, Object?> args,
  Event? functionResponseEvent, {
  TraceSpanRecord? span,
  Map<String, String>? environment,
}) {
  final TraceSpanRecord targetSpan =
      span ?? tracer.currentSpan ?? tracer.startAsCurrentSpan('execute_tool');
  targetSpan
    ..setAttribute('gen_ai.operation.name', 'execute_tool')
    ..setAttribute('gen_ai.tool.description', tool.description)
    ..setAttribute('gen_ai.tool.name', tool.name)
    ..setAttribute('gen_ai.tool.type', tool.runtimeType.toString())
    ..setAttribute('gcp.vertex.agent.llm_request', '{}')
    ..setAttribute('gcp.vertex.agent.llm_response', '{}');

  if (_shouldAddRequestResponseToSpans(environment: environment)) {
    targetSpan.setAttribute(
      'gcp.vertex.agent.tool_call_args',
      _safeJsonSerialize(args),
    );
  } else {
    targetSpan.setAttribute('gcp.vertex.agent.tool_call_args', '{}');
  }

  String toolCallId = '<not specified>';
  Object? toolResponse = '<not specified>';
  if (functionResponseEvent?.content?.parts.isNotEmpty ?? false) {
    final FunctionResponse? functionResponse =
        functionResponseEvent!.content!.parts.first.functionResponse;
    if (functionResponse != null) {
      toolCallId = functionResponse.id ?? toolCallId;
      toolResponse = functionResponse.response;
    }
  }

  targetSpan.setAttribute('gen_ai.tool_call.id', toolCallId);
  if (functionResponseEvent != null) {
    targetSpan.setAttribute(
      'gcp.vertex.agent.event_id',
      functionResponseEvent.id,
    );
  }

  if (toolResponse is! Map) {
    toolResponse = <String, Object?>{'result': toolResponse};
  }
  if (_shouldAddRequestResponseToSpans(environment: environment)) {
    targetSpan.setAttribute(
      'gcp.vertex.agent.tool_response',
      _safeJsonSerialize(toolResponse),
    );
  } else {
    targetSpan.setAttribute('gcp.vertex.agent.tool_response', '{}');
  }
}

void traceMergedToolCalls(
  String responseEventId,
  Event functionResponseEvent, {
  TraceSpanRecord? span,
  Map<String, String>? environment,
}) {
  final TraceSpanRecord targetSpan =
      span ?? tracer.currentSpan ?? tracer.startAsCurrentSpan('execute_tool');

  targetSpan
    ..setAttribute('gen_ai.operation.name', 'execute_tool')
    ..setAttribute('gen_ai.tool.name', '(merged tools)')
    ..setAttribute('gen_ai.tool.description', '(merged tools)')
    ..setAttribute('gen_ai.tool_call.id', responseEventId)
    ..setAttribute('gcp.vertex.agent.tool_call_args', 'N/A')
    ..setAttribute('gcp.vertex.agent.event_id', responseEventId)
    ..setAttribute('gcp.vertex.agent.llm_request', '{}')
    ..setAttribute('gcp.vertex.agent.llm_response', '{}');

  final String eventJson = _safeJsonSerialize(
    _eventToJson(functionResponseEvent),
  );
  if (_shouldAddRequestResponseToSpans(environment: environment)) {
    targetSpan.setAttribute('gcp.vertex.agent.tool_response', eventJson);
  } else {
    targetSpan.setAttribute('gcp.vertex.agent.tool_response', '{}');
  }
}

void traceCallLlm(
  InvocationContext invocationContext,
  String eventId,
  LlmRequest llmRequest,
  LlmResponse llmResponse, {
  TraceSpanRecord? span,
  Map<String, String>? environment,
}) {
  final TraceSpanRecord targetSpan =
      span ?? tracer.currentSpan ?? tracer.startAsCurrentSpan('call_llm');
  targetSpan
    ..setAttribute('gen_ai.system', 'gcp.vertex.agent')
    ..setAttribute('gen_ai.request.model', llmRequest.model)
    ..setAttribute(
      'gcp.vertex.agent.invocation_id',
      invocationContext.invocationId,
    )
    ..setAttribute('gcp.vertex.agent.session_id', invocationContext.session.id)
    ..setAttribute('gcp.vertex.agent.event_id', eventId);

  if (_shouldAddRequestResponseToSpans(environment: environment)) {
    targetSpan.setAttribute(
      'gcp.vertex.agent.llm_request',
      _safeJsonSerialize(_buildLlmRequestForTrace(llmRequest)),
    );
    targetSpan.setAttribute(
      'gcp.vertex.agent.llm_response',
      _safeJsonSerialize(_llmResponseToJson(llmResponse)),
    );
  } else {
    targetSpan
      ..setAttribute('gcp.vertex.agent.llm_request', '{}')
      ..setAttribute('gcp.vertex.agent.llm_response', '{}');
  }

  if (llmResponse.usageMetadata is Map<String, Object?>) {
    final Map<String, Object?> usage =
        llmResponse.usageMetadata! as Map<String, Object?>;
    final Object? promptTokenCount = usage['promptTokenCount'];
    final Object? candidatesTokenCount = usage['candidatesTokenCount'];
    if (promptTokenCount is num) {
      targetSpan.setAttribute('gen_ai.usage.input_tokens', promptTokenCount);
    }
    if (candidatesTokenCount is num) {
      targetSpan.setAttribute(
        'gen_ai.usage.output_tokens',
        candidatesTokenCount,
      );
    }
  }

  final String? finishReason = llmResponse.finishReason;
  if (finishReason != null && finishReason.isNotEmpty) {
    targetSpan.setAttribute('gen_ai.response.finish_reasons', <String>[
      finishReason.toLowerCase(),
    ]);
  }
}

void traceSendData(
  InvocationContext invocationContext,
  String eventId,
  List<Content> data, {
  TraceSpanRecord? span,
  Map<String, String>? environment,
}) {
  final TraceSpanRecord targetSpan =
      span ?? tracer.currentSpan ?? tracer.startAsCurrentSpan('send_data');
  targetSpan
    ..setAttribute(
      'gcp.vertex.agent.invocation_id',
      invocationContext.invocationId,
    )
    ..setAttribute('gcp.vertex.agent.event_id', eventId);

  if (_shouldAddRequestResponseToSpans(environment: environment)) {
    targetSpan.setAttribute(
      'gcp.vertex.agent.data',
      _safeJsonSerialize(
        data
            .map(
              (Content content) =>
                  _contentToJson(content, includeInlineData: true),
            )
            .toList(),
      ),
    );
  } else {
    targetSpan.setAttribute('gcp.vertex.agent.data', '{}');
  }
}

Map<String, Object?> _buildLlmRequestForTrace(LlmRequest llmRequest) {
  return <String, Object?>{
    'model': llmRequest.model,
    'config': <String, Object?>{
      'system_instruction': llmRequest.config.systemInstruction,
      'response_mime_type': llmRequest.config.responseMimeType,
      'labels': llmRequest.config.labels,
    },
    'contents': llmRequest.contents
        .map(
          (Content content) =>
              _contentToJson(content, includeInlineData: false),
        )
        .toList(),
  };
}

Map<String, Object?> _llmResponseToJson(LlmResponse llmResponse) {
  return <String, Object?>{
    'model_version': llmResponse.modelVersion,
    'content': llmResponse.content == null
        ? null
        : _contentToJson(llmResponse.content!, includeInlineData: true),
    'partial': llmResponse.partial,
    'turn_complete': llmResponse.turnComplete,
    'finish_reason': llmResponse.finishReason,
    'error_code': llmResponse.errorCode,
    'error_message': llmResponse.errorMessage,
    'interrupted': llmResponse.interrupted,
    'custom_metadata': llmResponse.customMetadata,
    'usage_metadata': llmResponse.usageMetadata,
    'grounding_metadata': llmResponse.groundingMetadata,
    'interaction_id': llmResponse.interactionId,
  };
}

Map<String, Object?> _eventToJson(Event event) {
  return <String, Object?>{
    'id': event.id,
    'author': event.author,
    'invocation_id': event.invocationId,
    'content': event.content == null
        ? null
        : _contentToJson(event.content!, includeInlineData: true),
    'timestamp': event.timestamp,
  };
}

Map<String, Object?> _contentToJson(
  Content content, {
  required bool includeInlineData,
}) {
  return <String, Object?>{
    'role': content.role,
    'parts': content.parts
        .where((Part part) => includeInlineData || part.inlineData == null)
        .map(
          (Part part) =>
              _partToJson(part, includeInlineData: includeInlineData),
        )
        .toList(),
  };
}

Map<String, Object?> _partToJson(Part part, {required bool includeInlineData}) {
  final Map<String, Object?> data = <String, Object?>{};
  if (part.text != null) {
    data['text'] = part.text;
  }
  if (part.thought) {
    data['thought'] = true;
  }
  if (part.thoughtSignature != null) {
    data['thought_signature'] = List<int>.from(part.thoughtSignature!);
  }
  if (part.functionCall != null) {
    data['function_call'] = <String, Object?>{
      'name': part.functionCall!.name,
      'args': part.functionCall!.args,
      'id': part.functionCall!.id,
      if (part.functionCall!.partialArgs != null)
        'partial_args': part.functionCall!.partialArgs
            ?.map(
              (Map<String, Object?> value) => Map<String, Object?>.from(value),
            )
            .toList(growable: false),
      if (part.functionCall!.willContinue != null)
        'will_continue': part.functionCall!.willContinue,
    };
  }
  if (part.functionResponse != null) {
    data['function_response'] = <String, Object?>{
      'name': part.functionResponse!.name,
      'response': part.functionResponse!.response,
      'id': part.functionResponse!.id,
    };
  }
  if (includeInlineData && part.inlineData != null) {
    data['inline_data'] = <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'data': part.inlineData!.data,
      'display_name': part.inlineData!.displayName,
    };
  }
  if (part.fileData != null) {
    data['file_data'] = <String, Object?>{
      'file_uri': part.fileData!.fileUri,
      'mime_type': part.fileData!.mimeType,
      'display_name': part.fileData!.displayName,
    };
  }
  if (part.executableCode != null) {
    data['executable_code'] = part.executableCode;
  }
  if (part.codeExecutionResult != null) {
    data['code_execution_result'] = part.codeExecutionResult;
  }
  return data;
}

String _safeJsonSerialize(Object? value) {
  try {
    return jsonEncode(_normalizeForJson(value));
  } catch (_) {
    return '<not serializable>';
  }
}

Object? _normalizeForJson(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? nested) =>
          MapEntry('$key', _normalizeForJson(nested)),
    );
  }
  if (value is Iterable) {
    return value.map(_normalizeForJson).toList();
  }
  return '$value';
}

bool _shouldAddRequestResponseToSpans({Map<String, String>? environment}) {
  final Map<String, String>? env = environment;
  final String raw = (env?[adkCaptureMessageContentInSpans] ?? 'true')
      .toLowerCase();
  final bool disabled = raw == 'false' || raw == '0';
  return !disabled;
}
