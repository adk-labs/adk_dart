/// Telemetry configuration, exporters, and tracing helpers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/base_agent.dart';
import '../agents/invocation_context.dart';
import '../agents/llm_agent.dart';
import '../errors/tool_execution_error.dart';
import '../events/event.dart';
import '../models/google_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import '../utils/model_name_utils.dart';
import '../version.dart';
import 'base_telemetry_service.dart';
import '_experimental_semconv.dart' as experimental_semconv;

/// Environment key controlling whether request and response payloads are
/// captured in span attributes.
const String adkCaptureMessageContentInSpans =
    'ADK_CAPTURE_MESSAGE_CONTENT_IN_SPANS';

/// Environment key controlling prompt and response content logs for
/// OpenTelemetry GenAI instrumentation.
const String otelInstrumentationGenaiCaptureMessageContent =
    'OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT';

/// Placeholder used when user content logging is disabled.
const String userContentElided = '<elided>';

/// In-memory representation of a trace span and its attributes.
class TraceSpanRecord implements experimental_semconv.SpanAttributeWriter {
  /// Creates a trace span record.
  TraceSpanRecord(this.name, {Map<String, Object?>? attributes})
    : attributes = attributes ?? <String, Object?>{};

  /// Span name.
  final String name;

  /// Mutable span attributes.
  final Map<String, Object?> attributes;

  @override
  void setAttribute(String key, Object? value) {
    attributes[key] = value;
  }

  /// Sets multiple [values] on this span.
  void setAttributes(Map<String, Object?> values) {
    attributes.addAll(values);
  }
}

/// In-memory OpenTelemetry log record.
class OTelLogRecord {
  /// Creates a log record.
  OTelLogRecord({
    required this.eventName,
    this.body,
    Map<String, Object?>? attributes,
  }) : attributes = attributes ?? <String, Object?>{};

  /// Event name for this log.
  final String eventName;

  /// Structured log body.
  final Object? body;

  /// Log attributes.
  final Map<String, Object?> attributes;
}

/// In-memory logger used by tracing helpers.
class AdkOtelLogger implements experimental_semconv.CompletionDetailsLogger {
  final List<OTelLogRecord> _records = <OTelLogRecord>[];

  /// Stores a [record] in memory.
  void emit(OTelLogRecord record) {
    _records.add(record);
  }

  @override
  void emitCompletionDetailsLog(
    experimental_semconv.CompletionDetailsLogRecord record,
  ) {
    emit(
      OTelLogRecord(
        eventName: record.eventName,
        body: record.body,
        attributes: record.attributes,
      ),
    );
  }

  /// Collected log records.
  List<OTelLogRecord> get records => List<OTelLogRecord>.unmodifiable(_records);

  /// Clears collected records.
  void clear() {
    _records.clear();
  }
}

/// In-memory tracer used by ADK telemetry utilities.
class AdkTracer {
  final List<TraceSpanRecord> _spanStack = <TraceSpanRecord>[];
  final List<TraceSpanRecord> _finishedSpans = <TraceSpanRecord>[];

  /// Starts a span and sets it as current.
  TraceSpanRecord startAsCurrentSpan(
    String name, {
    Map<String, Object?>? attributes,
  }) {
    final TraceSpanRecord span = TraceSpanRecord(name, attributes: attributes);
    _spanStack.add(span);
    return span;
  }

  /// The current active span, if present.
  TraceSpanRecord? get currentSpan {
    if (_spanStack.isEmpty) {
      return null;
    }
    return _spanStack.last;
  }

  /// Ends the current span.
  void endCurrentSpan() {
    if (_spanStack.isEmpty) {
      return;
    }
    _finishedSpans.add(_spanStack.removeLast());
  }

  /// Completed spans in completion order.
  List<TraceSpanRecord> get finishedSpans {
    return List<TraceSpanRecord>.unmodifiable(_finishedSpans);
  }

  /// Runs [body] inside a temporary span.
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

  /// Runs async [body] inside a temporary span.
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

  /// Clears active and finished span state.
  void clear() {
    _spanStack.clear();
    _finishedSpans.clear();
  }
}

/// Global in-memory tracer.
final AdkTracer tracer = AdkTracer();

/// Global in-memory OpenTelemetry logger.
final AdkOtelLogger otelLogger = AdkOtelLogger();

/// Clears global OpenTelemetry logs.
///
/// This is primarily used by tests.
void resetOtelLoggerForTest() {
  otelLogger.clear();
}

/// Runs [run] inside a telemetry span managed by [telemetryService].
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

/// Records span attributes for agent invocation metadata.
void traceAgentInvocation(
  TraceSpanRecord span,
  BaseAgent agent,
  InvocationContext ctx,
) {
  span
    ..setAttribute('gen_ai.operation.name', 'invoke_agent')
    ..setAttribute('gen_ai.agent.description', agent.description)
    ..setAttribute('gen_ai.agent.name', agent.name)
    ..setAttribute('gen_ai.agent.version', adkVersion)
    ..setAttribute('gen_ai.conversation.id', ctx.session.id);
}

/// Records span attributes for a single tool call.
void traceToolCall(
  BaseTool tool,
  Map<String, Object?> args,
  Event? functionResponseEvent, {
  Object? error,
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

  if (error != null) {
    final String errorType =
        error is ToolExecutionError && error.errorType != null
        ? error.errorType!
        : error.runtimeType.toString();
    targetSpan.setAttribute('error.type', errorType);
  }

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

/// Records span attributes for merged tool call responses.
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

/// Records span attributes for an LLM request and response pair.
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

  final double? topP = llmRequest.config.topP;
  if (topP != null) {
    targetSpan.setAttribute('gen_ai.request.top_p', topP);
  }
  final int? maxOutputTokens = llmRequest.config.maxOutputTokens;
  if (maxOutputTokens != null) {
    targetSpan.setAttribute('gen_ai.request.max_tokens', maxOutputTokens);
  }

  _setUsageMetadataAttributes(targetSpan, llmResponse.usageMetadata);

  final String? finishReason = llmResponse.finishReason;
  if (finishReason != null && finishReason.isNotEmpty) {
    targetSpan.setAttribute('gen_ai.response.finish_reasons', <String>[
      finishReason.toLowerCase(),
    ]);
  }
}

/// Records span attributes for send-data events.
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

/// Runs [run] inside an inference span and passes a legacy span view.
@Deprecated('Replaced by useInferenceSpan to support experimental semconv.')
Future<T> useGenerateContentSpan<T>(
  LlmRequest llmRequest,
  InvocationContext invocationContext,
  Event modelResponseEvent,
  Future<T> Function(TraceSpanRecord? span) run, {
  Map<String, String>? environment,
}) {
  return useInferenceSpan(llmRequest, invocationContext, modelResponseEvent, (
    GenerateContentSpan? generateContentSpan,
  ) {
    return run(generateContentSpan?.span);
  }, environment: environment);
}

/// Runs [run] inside a generate-content span context.
Future<T> useInferenceSpan<T>(
  LlmRequest llmRequest,
  InvocationContext invocationContext,
  Event modelResponseEvent,
  Future<T> Function(GenerateContentSpan? span) run, {
  Map<String, String>? environment,
}) async {
  final Map<String, Object?> commonAttributes = _buildCommonInferenceAttributes(
    invocationContext,
    modelResponseEvent,
  );

  if (_isGeminiAgent(invocationContext.agent) &&
      _instrumentedWithOpenTelemetryInstrumentationGoogleGenai()) {
    return _runWithExtraGenerateContentAttributes(
      commonAttributes,
      () => run(null),
    );
  }

  final bool useExperimentalSemconv = experimental_semconv
      .isExperimentalSemconv(environment: environment);
  final TraceSpanRecord span = tracer.startAsCurrentSpan(
    'generate_content ${llmRequest.model ?? ''}',
  );
  final GenerateContentSpan gcSpan = GenerateContentSpan(span);

  try {
    _setCommonGenerateContentAttributes(span, llmRequest, commonAttributes);

    if (useExperimentalSemconv) {
      await experimental_semconv.setOperationDetailsAttributesFromRequest(
        gcSpan.operationDetailsAttributes,
        llmRequest,
      );
      experimental_semconv.setOperationDetailsCommonAttributes(
        gcSpan.operationDetailsCommonAttributes,
        commonAttributes,
      );
    } else {
      span.setAttribute(
        'gen_ai.system',
        _guessGeminiSystemName(environment: environment),
      );
      _emitStablePromptLogs(llmRequest, environment: environment);
    }

    return await run(gcSpan);
  } finally {
    if (useExperimentalSemconv) {
      experimental_semconv.maybeLogCompletionDetails(
        span,
        otelLogger,
        gcSpan.operationDetailsAttributes,
        gcSpan.operationDetailsCommonAttributes,
        environment: environment,
      );
    }
    tracer.endCurrentSpan();
  }
}

/// Span wrapper for generate-content operations.
class GenerateContentSpan {
  /// Creates a generate-content span wrapper.
  GenerateContentSpan(this.span);

  /// Underlying trace span.
  final TraceSpanRecord span;

  /// Experimental operation details attributes.
  final Map<String, Object?> operationDetailsAttributes = <String, Object?>{};

  /// Common attributes shared by operation details logs.
  final Map<String, Object?> operationDetailsCommonAttributes =
      <String, Object?>{};
}

/// Records inference result attributes on a legacy span.
@Deprecated('Replaced by traceInferenceResult to support experimental semconv.')
void traceGenerateContentResult(
  TraceSpanRecord? span,
  LlmResponse llmResponse, {
  Map<String, String>? environment,
}) {
  if (span == null || llmResponse.partial == true) {
    return;
  }

  final String? finishReason = llmResponse.finishReason;
  if (finishReason != null && finishReason.isNotEmpty) {
    span.setAttribute('gen_ai.response.finish_reasons', <String>[
      finishReason.toLowerCase(),
    ]);
  }
  _setUsageMetadataAttributes(span, llmResponse.usageMetadata);
  _emitChoiceLog(llmResponse, environment: environment);
}

/// Records inference result attributes on [span].
///
/// The [span] can be either [GenerateContentSpan] or [TraceSpanRecord].
void traceInferenceResult(
  Object? span,
  LlmResponse llmResponse, {
  Map<String, String>? environment,
}) {
  GenerateContentSpan? generateContentSpan;
  TraceSpanRecord? targetSpan;

  if (span is GenerateContentSpan) {
    generateContentSpan = span;
    targetSpan = span.span;
  } else if (span is TraceSpanRecord) {
    targetSpan = span;
  }

  if (targetSpan == null || llmResponse.partial == true) {
    return;
  }

  final String? finishReason = llmResponse.finishReason;
  if (finishReason != null && finishReason.isNotEmpty) {
    targetSpan.setAttribute('gen_ai.response.finish_reasons', <String>[
      finishReason.toLowerCase(),
    ]);
  }
  _setUsageMetadataAttributes(targetSpan, llmResponse.usageMetadata);

  if (experimental_semconv.isExperimentalSemconv(environment: environment) &&
      generateContentSpan != null) {
    experimental_semconv.setOperationDetailsAttributesFromResponse(
      llmResponse,
      generateContentSpan.operationDetailsAttributes,
      generateContentSpan.operationDetailsCommonAttributes,
    );
    return;
  }

  _emitChoiceLog(llmResponse, environment: environment);
}

Map<String, Object?> _buildLlmRequestForTrace(LlmRequest llmRequest) {
  return <String, Object?>{
    'model': llmRequest.model,
    'config': _generateContentConfigToJson(llmRequest.config),
    'contents': llmRequest.contents
        .map(
          (Content content) =>
              _contentToJson(content, includeInlineData: false),
        )
        .toList(),
  };
}

Map<String, Object?> _generateContentConfigToJson(
  GenerateContentConfig config,
) {
  final Map<String, Object?> toolConfig = _dropNullEntries(<String, Object?>{
    'function_calling_config': config.toolConfig?.functionCallingConfig == null
        ? null
        : _dropNullEntries(<String, Object?>{
            'mode': config.toolConfig!.functionCallingConfig!.mode.name,
            'allowed_function_names':
                config.toolConfig!.functionCallingConfig!.allowedFunctionNames,
          }),
  });

  final Map<String, Object?> httpOptions = _dropNullEntries(<String, Object?>{
    'api_version': config.httpOptions?.apiVersion,
    'headers': config.httpOptions?.headers,
    'retry_options': config.httpOptions?.retryOptions == null
        ? null
        : _dropNullEntries(<String, Object?>{
            'attempts': config.httpOptions!.retryOptions!.attempts,
            'initial_delay': config.httpOptions!.retryOptions!.initialDelay,
            'max_delay': config.httpOptions!.retryOptions!.maxDelay,
            'exp_base': config.httpOptions!.retryOptions!.expBase,
            'http_status_codes':
                config.httpOptions!.retryOptions!.httpStatusCodes,
          }),
  });

  final List<Map<String, Object?>> tools = (config.tools ?? <ToolDeclaration>[])
      .map(_toolDeclarationToJson)
      .toList(growable: false);

  return _dropNullEntries(<String, Object?>{
    'tools': tools,
    'system_instruction': config.systemInstruction,
    'temperature': config.temperature,
    'top_p': config.topP,
    'top_k': config.topK,
    'max_output_tokens': config.maxOutputTokens,
    'stop_sequences': config.stopSequences,
    'frequency_penalty': config.frequencyPenalty,
    'presence_penalty': config.presencePenalty,
    'seed': config.seed,
    'candidate_count': config.candidateCount,
    'response_logprobs': config.responseLogprobs,
    'logprobs': config.logprobs,
    'thinking_config': config.thinkingConfig,
    'response_json_schema': config.responseJsonSchema,
    'response_mime_type': config.responseMimeType,
    'tool_config': toolConfig.isEmpty ? null : toolConfig,
    'cached_content': config.cachedContent,
    'http_options': httpOptions.isEmpty ? null : httpOptions,
    'labels': config.labels,
  });
}

Map<String, Object?> _toolDeclarationToJson(ToolDeclaration declaration) {
  return _dropNullEntries(<String, Object?>{
    'function_declarations': declaration.functionDeclarations
        .map(
          (FunctionDeclaration functionDeclaration) =>
              _dropNullEntries(<String, Object?>{
                'name': functionDeclaration.name,
                'description': functionDeclaration.description,
                'parameters': functionDeclaration.parameters,
              }),
        )
        .toList(growable: false),
    'google_search': declaration.googleSearch,
    'google_search_retrieval': declaration.googleSearchRetrieval,
    'url_context': declaration.urlContext,
    'code_execution': declaration.codeExecution,
    'google_maps': declaration.googleMaps,
    'enterprise_web_search': declaration.enterpriseWebSearch,
    'retrieval': declaration.retrieval,
    'computer_use': declaration.computerUse,
  });
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
  final Map<String, String> env = environment ?? Platform.environment;
  final String raw = (env[adkCaptureMessageContentInSpans] ?? 'true')
      .toLowerCase();
  final bool disabled = raw == 'false' || raw == '0';
  return !disabled;
}

bool _shouldLogPromptResponseContent({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String value =
      (env[otelInstrumentationGenaiCaptureMessageContent] ?? '').toLowerCase();
  return value == 'true' || value == '1';
}

Object? _serializeContent(Object? content) {
  if (content == null ||
      content is String ||
      content is num ||
      content is bool) {
    return content;
  }
  if (content is Content) {
    return _contentToJson(content, includeInlineData: true);
  }
  if (content is Part) {
    return _partToJson(content, includeInlineData: true);
  }
  if (content is Iterable) {
    return content.map((Object? item) => _serializeContent(item)).toList();
  }
  if (content is Map) {
    return content.map(
      (Object? key, Object? value) =>
          MapEntry('$key', _serializeContent(value)),
    );
  }
  return _safeJsonSerialize(content);
}

Object? _serializeContentWithElision(
  Object? content, {
  Map<String, String>? environment,
}) {
  if (!_shouldLogPromptResponseContent(environment: environment)) {
    return userContentElided;
  }
  return _serializeContent(content);
}

void _emitStablePromptLogs(
  LlmRequest llmRequest, {
  Map<String, String>? environment,
}) {
  final String systemName = _guessGeminiSystemName(environment: environment);
  otelLogger.emit(
    OTelLogRecord(
      eventName: 'gen_ai.system.message',
      body: <String, Object?>{
        'content': _serializeContentWithElision(
          llmRequest.config.systemInstruction,
          environment: environment,
        ),
      },
      attributes: <String, Object?>{'gen_ai.system': systemName},
    ),
  );

  for (final Content content in llmRequest.contents) {
    otelLogger.emit(
      OTelLogRecord(
        eventName: 'gen_ai.user.message',
        body: <String, Object?>{
          'content': _serializeContentWithElision(
            content,
            environment: environment,
          ),
        },
        attributes: <String, Object?>{'gen_ai.system': systemName},
      ),
    );
  }
}

void _emitChoiceLog(
  LlmResponse llmResponse, {
  Map<String, String>? environment,
}) {
  final Map<String, Object?> body = <String, Object?>{
    'content': _serializeContentWithElision(
      llmResponse.content,
      environment: environment,
    ),
    'index': 0,
  };
  if (llmResponse.finishReason != null) {
    body['finish_reason'] = llmResponse.finishReason;
  }

  otelLogger.emit(
    OTelLogRecord(
      eventName: 'gen_ai.choice',
      body: body,
      attributes: <String, Object?>{
        'gen_ai.system': _guessGeminiSystemName(environment: environment),
      },
    ),
  );
}

void _setUsageMetadataAttributes(TraceSpanRecord span, Object? usageMetadata) {
  final Map<String, Object?>? usage = _usageMetadataAsMap(usageMetadata);
  if (usage == null) {
    return;
  }

  final Object? promptTokenCount =
      usage['prompt_token_count'] ?? usage['promptTokenCount'];
  final Object? candidatesTokenCount =
      usage['candidates_token_count'] ?? usage['candidatesTokenCount'];

  if (promptTokenCount is num) {
    span.setAttribute('gen_ai.usage.input_tokens', promptTokenCount);
  }
  if (candidatesTokenCount is num) {
    span.setAttribute('gen_ai.usage.output_tokens', candidatesTokenCount);
  }
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

Map<String, Object?> _buildCommonInferenceAttributes(
  InvocationContext invocationContext,
  Event modelResponseEvent,
) {
  return <String, Object?>{
    'gen_ai.agent.name': invocationContext.agent.name,
    'gen_ai.agent.version': adkVersion,
    'gen_ai.conversation.id': invocationContext.session.id,
    'user.id': invocationContext.session.userId,
    'gcp.vertex.agent.event_id': modelResponseEvent.id,
    'gcp.vertex.agent.invocation_id': invocationContext.invocationId,
  };
}

void _setCommonGenerateContentAttributes(
  TraceSpanRecord span,
  LlmRequest llmRequest,
  Map<String, Object?> commonAttributes,
) {
  span
    ..setAttribute('gen_ai.operation.name', 'generate_content')
    ..setAttribute('gen_ai.request.model', llmRequest.model ?? '');
  span.setAttributes(commonAttributes);
}

/// Callback that reports whether external GenAI instrumentation is active.
typedef GenAiInstrumentationDetector = bool Function();

GenAiInstrumentationDetector _genAiInstrumentationDetector = () => false;

/// Sets the detector used to identify external GenAI instrumentation.
///
/// This is intended for tests.
void setGenAiInstrumentationDetectorForTest(
  GenAiInstrumentationDetector detector,
) {
  _genAiInstrumentationDetector = detector;
}

/// Restores the default GenAI instrumentation detector.
///
/// This is intended for tests.
void resetGenAiInstrumentationDetectorForTest() {
  _genAiInstrumentationDetector = () => false;
}

bool _instrumentedWithOpenTelemetryInstrumentationGoogleGenai() {
  return _genAiInstrumentationDetector();
}

const Object _generateContentExtraAttributesContextKey = Object();

/// The current zone-scoped extra attributes for generate-content spans.
Map<String, Object?>? getCurrentGenerateContentExtraAttributes() {
  final Object? value = Zone.current[_generateContentExtraAttributesContextKey];
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? nestedValue) =>
          MapEntry<String, Object?>('$key', nestedValue),
    );
  }
  return null;
}

T _runWithExtraGenerateContentAttributes<T>(
  Map<String, Object?> extraAttributes,
  T Function() run,
) {
  return runZoned(
    run,
    zoneValues: <Object?, Object?>{
      _generateContentExtraAttributesContextKey: Map<String, Object?>.from(
        extraAttributes,
      ),
    },
  );
}

bool _isGeminiAgent(BaseAgent agent) {
  if (agent is! LlmAgent) {
    return false;
  }

  final Object model = agent.model;
  if (model is String) {
    return isGeminiModel(model);
  }
  return model is Gemini;
}

String _guessGeminiSystemName({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final String value = (env['GOOGLE_GENAI_USE_VERTEXAI'] ?? '').toLowerCase();
  if (value == 'true' || value == '1') {
    return 'vertex_ai';
  }
  return 'gemini';
}

Map<String, Object?> _dropNullEntries(Map<String, Object?> values) {
  final Map<String, Object?> cleaned = <String, Object?>{};
  for (final MapEntry<String, Object?> entry in values.entries) {
    if (entry.value != null) {
      cleaned[entry.key] = entry.value;
    }
  }
  return cleaned;
}
