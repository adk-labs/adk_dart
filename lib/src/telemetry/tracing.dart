/// Telemetry configuration, exporters, and tracing helpers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../agents/base_agent.dart';
import '../agents/invocation_context.dart';
import '../agents/llm_agent.dart';
import '../agents/run_config.dart';
import '../errors/tool_execution_error.dart';
import '../events/event.dart';
import '../models/base_llm.dart';
import '../models/cache_metadata.dart';
import '../models/google_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../types/content.dart';
import '../utils/credential_names.dart';
import '../utils/function_call_names.dart';
import '../utils/model_name_utils.dart';
import 'base_telemetry_service.dart';
import 'metrics.dart';
import 'sqlite_span_exporter.dart';
import '_experimental_semconv.dart' as experimental_semconv;

export '../utils/credential_names.dart';

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

/// Attribute key indicating whether a cached content entry was hit.
const String adkExperimentalContextCacheHit =
    'adk.experimental.context_cache.hit';

/// Attribute key recording context cache content fingerprint.
const String adkExperimentalContextCacheFingerprint =
    'adk.experimental.context_cache.fingerprint';

/// Attribute key recording context cache contents count.
const String adkExperimentalContextCacheContentsCount =
    'adk.experimental.context_cache.contents_count';

/// Attribute key recording number of invocations that used the context cache.
const String adkExperimentalContextCacheInvocationsUsed =
    'adk.experimental.context_cache.invocations_used';

/// Attribute key recording the distinct count of grounding web search queries.
const String adkExperimentalGroundingQueryCount =
    'adk.experimental.grounding.query_count';

/// Attribute key recording the count of grounding chunks returned by the model.
const String adkExperimentalGroundingChunkCount =
    'adk.experimental.grounding.chunk_count';

/// Attribute key recording the grounding web search queries when content capture is enabled.
const String adkExperimentalGroundingWebSearchQueries =
    'adk.experimental.grounding.web_search_queries';

/// Attribute key recording the distinct grounding source URIs when content capture is enabled.
const String adkExperimentalGroundingSourceUris =
    'adk.experimental.grounding.source_uris';

/// Attribute key recording the model version that served the LLM response.
const String genAiResponseModel = 'gen_ai.response.model';

/// Alias for [TraceSpanRecord].
typedef TraceSpan = TraceSpanRecord;

/// Resolves the OpenTelemetry `error.type` attribute value for [error].
String resolveErrorType(Object error) {
  if (error is ToolExecutionError &&
      error.errorType != null &&
      error.errorType!.isNotEmpty) {
    return error.errorType!;
  }
  return error.runtimeType.toString();
}

/// In-memory representation of a trace span and its attributes.
class TraceSpanRecord implements experimental_semconv.SpanAttributeWriter {
  /// Creates a trace span record.
  TraceSpanRecord(
    this.name, {
    Map<String, Object?>? attributes,
    this.kind = SpanKind.internal,
    this.startTimeUnixNano,
    this.endTimeUnixNano,
  }) : attributes = attributes ?? <String, Object?>{};

  /// Span name.
  String name;

  /// Mutable span attributes.
  final Map<String, Object?> attributes;

  /// OpenTelemetry span kind.
  final SpanKind kind;

  /// Optional recorded span start timestamp in Unix nanoseconds.
  int? startTimeUnixNano;

  /// Optional recorded span end timestamp in Unix nanoseconds.
  int? endTimeUnixNano;

  /// Updates the span [name] to [newName].
  void updateName(String newName) {
    name = newName;
  }

  @override
  void setAttribute(String key, Object? value) {
    attributes[key] = value;
  }

  /// Sets multiple [values] on this span.
  void setAttributes(Map<String, Object?> values) {
    attributes.addAll(values);
  }
}

/// Formats an `execute_tool` span name for skill tools using confirmed
/// (non-hallucinated) skill and resource/script identifiers.
String formatSkillToolSpanName({
  required String toolName,
  String? confirmedSkillName,
  String? confirmedResourceOrScriptPath,
}) {
  final String? skill = confirmedSkillName?.trim();
  if (skill == null || skill.isEmpty) {
    return 'execute_tool $toolName';
  }
  final String? resource = confirmedResourceOrScriptPath?.trim();
  if (resource == null || resource.isEmpty) {
    return 'execute_tool $toolName $skill';
  }
  return 'execute_tool $toolName $skill $resource';
}

/// Telemetry helper for naming and updating skill tool execution spans.
///
/// ```dart
/// final spanName = SkillTelemetry.formatSpanName(
///   toolName: 'load_skill',
///   confirmedSkillName: 'my-skill',
/// );
/// ```
class SkillTelemetry {
  /// Creates a skill telemetry descriptor.
  const SkillTelemetry({
    required this.toolName,
    this.confirmedSkillName,
    this.confirmedResourceOrScriptPath,
  });

  /// The name of the skill tool (`load_skill`, `load_skill_resource`, `run_skill_script`).
  final String toolName;

  /// The skill name once confirmed not hallucinated.
  final String? confirmedSkillName;

  /// The resource or script path once confirmed not hallucinated.
  final String? confirmedResourceOrScriptPath;

  /// Computed span name for this skill tool invocation.
  String get spanName => formatSkillToolSpanName(
    toolName: toolName,
    confirmedSkillName: confirmedSkillName,
    confirmedResourceOrScriptPath: confirmedResourceOrScriptPath,
  );

  /// Formats an `execute_tool` span name for skill tools.
  static String formatSpanName({
    required String toolName,
    String? confirmedSkillName,
    String? confirmedResourceOrScriptPath,
  }) => formatSkillToolSpanName(
    toolName: toolName,
    confirmedSkillName: confirmedSkillName,
    confirmedResourceOrScriptPath: confirmedResourceOrScriptPath,
  );

  /// Updates [span] (or [AdkTracer.currentSpan] when omitted) with the
  /// formatted skill tool span name.
  static void updateCurrentSpanName({
    required String toolName,
    String? confirmedSkillName,
    String? confirmedResourceOrScriptPath,
    TraceSpanRecord? span,
  }) {
    final TraceSpanRecord? target = span ?? tracer.currentSpan;
    target?.updateName(
      formatSkillToolSpanName(
        toolName: toolName,
        confirmedSkillName: confirmedSkillName,
        confirmedResourceOrScriptPath: confirmedResourceOrScriptPath,
      ),
    );
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
    SpanKind kind = SpanKind.internal,
  }) {
    final TraceSpanRecord span = TraceSpanRecord(
      name,
      attributes: attributes,
      kind: kind,
    );
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

  /// Ends [span] and any spans that were started after it.
  ///
  /// Returns `false` when [span] is not currently active.
  bool endSpan(TraceSpanRecord span) {
    final int index = _spanStack.lastIndexWhere(
      (TraceSpanRecord candidate) => identical(candidate, span),
    );
    if (index < 0) {
      return false;
    }
    while (_spanStack.length > index) {
      _finishedSpans.add(_spanStack.removeLast());
    }
    return true;
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
    SpanKind kind = SpanKind.internal,
  }) {
    final TraceSpanRecord span = startAsCurrentSpan(
      name,
      attributes: attributes,
      kind: kind,
    );
    try {
      return body(span);
    } catch (error) {
      span.setAttribute('error.type', resolveErrorType(error));
      rethrow;
    } finally {
      endCurrentSpan();
    }
  }

  /// Runs async [body] inside a temporary span.
  Future<T> inSpanAsync<T>(
    String name,
    Future<T> Function(TraceSpanRecord span) body, {
    Map<String, Object?>? attributes,
    SpanKind kind = SpanKind.internal,
  }) async {
    final TraceSpanRecord span = startAsCurrentSpan(
      name,
      attributes: attributes,
      kind: kind,
    );
    try {
      return await body(span);
    } catch (error) {
      span.setAttribute('error.type', resolveErrorType(error));
      rethrow;
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
    ..setAttribute('gen_ai.conversation.id', ctx.session.id);
}

/// Records span attributes for a single tool call.
void traceToolCall(
  BaseTool tool,
  Map<String, Object?> args,
  Event? functionResponseEvent, {
  Object? error,
  String? errorType,
  InvocationContext? invocationContext,
  TraceSpanRecord? span,
  Map<String, String>? environment,
}) {
  final TraceSpanRecord targetSpan =
      span ?? tracer.currentSpan ?? tracer.startAsCurrentSpan('execute_tool');
  final TelemetryConfig telemetryConfig = telemetryConfigFromInvocationContext(
    invocationContext,
  );
  final bool captureLegacyContent =
      telemetryConfig.captureMessageContent &&
      _shouldAddRequestResponseToSpans(environment: environment);

  targetSpan
    ..setAttribute('gen_ai.operation.name', 'execute_tool')
    ..setAttribute('gen_ai.tool.description', tool.description)
    ..setAttribute('gen_ai.tool.name', tool.name)
    ..setAttribute('gen_ai.tool.type', tool.runtimeType.toString())
    ..setAttribute('gcp.vertex.agent.llm_request', '{}')
    ..setAttribute('gcp.vertex.agent.llm_response', '{}');

  if (invocationContext != null) {
    targetSpan.setAttribute(
      'gen_ai.agent.name',
      invocationContext.agent.name,
    );
  }

  if (error != null) {
    final String resolvedErrorType =
        error is ToolExecutionError && error.errorType != null
        ? error.errorType!
        : error.runtimeType.toString();
    targetSpan.setAttribute('error.type', resolvedErrorType);
  } else if (errorType != null && errorType.isNotEmpty) {
    targetSpan.setAttribute('error.type', errorType);
  }

  if (captureLegacyContent) {
    targetSpan.setAttribute(
      'gcp.vertex.agent.tool_call_args',
      _safeJsonSerialize(args),
    );
  } else {
    targetSpan.setAttribute('gcp.vertex.agent.tool_call_args', '{}');
  }

  String toolCallId = '<not specified>';
  Object? toolResponse = '<not specified>';
  bool hasResponse = false;
  if (functionResponseEvent?.content?.parts.isNotEmpty ?? false) {
    final FunctionResponse? functionResponse =
        functionResponseEvent!.content!.parts.first.functionResponse;
    if (functionResponse != null) {
      toolCallId = functionResponse.id ?? toolCallId;
      toolResponse = functionResponse.response;
      hasResponse = true;
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
  final String serializedToolResponse = _safeJsonSerialize(toolResponse);
  if (captureLegacyContent) {
    targetSpan.setAttribute(
      'gcp.vertex.agent.tool_response',
      serializedToolResponse,
    );
  } else {
    targetSpan.setAttribute('gcp.vertex.agent.tool_response', '{}');
  }
  if (resolveTelemetrySchemaVersion(environment: environment) >=
          schemaVersionSemconvAligned &&
      telemetryConfig.captureMessageContent &&
      _shouldAddContentToExperimentalSpans(environment: environment)) {
    targetSpan.setAttribute(
      'gen_ai.tool.call.arguments',
      _safeJsonSerialize(args),
    );
    if (hasResponse) {
      targetSpan.setAttribute(
        'gen_ai.tool.call.result',
        serializedToolResponse,
      );
    }
  }
}

/// Records span attributes for merged tool call responses.
void traceMergedToolCalls(
  String responseEventId,
  Event functionResponseEvent, {
  InvocationContext? invocationContext,
  TraceSpanRecord? span,
  Map<String, String>? environment,
}) {
  final TraceSpanRecord targetSpan =
      span ?? tracer.currentSpan ?? tracer.startAsCurrentSpan('execute_tool');
  final TelemetryConfig telemetryConfig = telemetryConfigFromInvocationContext(
    invocationContext,
  );

  targetSpan
    ..setAttribute('gen_ai.operation.name', 'execute_tool')
    ..setAttribute('gen_ai.tool.name', '(merged tools)')
    ..setAttribute('gen_ai.tool.description', '(merged tools)')
    ..setAttribute('gen_ai.tool_call.id', responseEventId)
    ..setAttribute('gcp.vertex.agent.tool_call_args', 'N/A')
    ..setAttribute('gcp.vertex.agent.event_id', responseEventId)
    ..setAttribute('gcp.vertex.agent.llm_request', '{}')
    ..setAttribute('gcp.vertex.agent.llm_response', '{}');

  if (telemetryConfig.captureMessageContent &&
      _shouldAddRequestResponseToSpans(environment: environment)) {
    final List<Part> parts =
        functionResponseEvent.content?.parts ?? const <Part>[];
    String toolResponseJson;
    try {
      toolResponseJson = _safeJsonSerialize(<Object?>[
        for (final Part part in parts)
          if (part.functionResponse != null)
            _redactCredentialSecrets(
              maskCredentialValues(
                part.functionResponse,
                <String, Object?>{
                  'name': part.functionResponse!.name,
                  'response': part.functionResponse!.response,
                  if (part.functionResponse!.id != null)
                    'id': part.functionResponse!.id,
                },
              ),
            ),
      ]);
    } catch (_) {
      toolResponseJson = '<not serializable>';
    }
    targetSpan.setAttribute('gcp.vertex.agent.tool_response', toolResponseJson);
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
  final Object? thinkingBudget = _thinkingBudgetValue(
    llmRequest.config.thinkingConfig,
  );
  if (thinkingBudget is num) {
    targetSpan.setAttribute(
      'gen_ai.usage.experimental.reasoning_tokens_limit',
      thinkingBudget,
    );
  }

  _setUsageMetadataAttributes(targetSpan, llmResponse.usageMetadata);
  _setContextCacheAttributes(
    targetSpan,
    llmResponse.cacheMetadata,
    environment: environment,
  );
  _setGroundingAttributes(
    targetSpan,
    llmResponse.groundingMetadata,
    captureContent: _shouldAddRequestResponseToSpans(environment: environment),
    environment: environment,
  );
  final String? responseModel = _responseModel(
    invocationContext,
    llmResponse,
    llmRequest,
  );
  if (responseModel != null && responseModel.isNotEmpty) {
    targetSpan.setAttribute(genAiResponseModel, responseModel);
  }

  final String? finishReason = llmResponse.finishReason;
  if (finishReason != null && finishReason.isNotEmpty) {
    targetSpan.setAttribute('gen_ai.response.finish_reasons', <String>[
      finishReason.toLowerCase(),
    ]);
  }
}

bool _isExperimentalTelemetryOptedIn(
  String feature, {
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  final List<String?> rawValues = <String?>[
    env['ADK_EXPERIMENTAL_TELEMETRY_OPT_IN'],
    env['adk_experimental_telemetry_opt_in'],
    env['ADK_EXPERIMENTAL_TELEMETRY'],
    env['adk_experimental_telemetry'],
    env['ADK_EXPERIMENTAL_TELEMETRY_FEATURES'],
    env['adk_experimental_telemetry_features'],
  ];
  final String normalizedFeature = feature.trim().toLowerCase();
  for (final String? raw in rawValues) {
    if (raw == null || raw.isEmpty) {
      continue;
    }
    final String lowered = raw.trim().toLowerCase();
    if (lowered == 'true' || lowered == '1') {
      return true;
    }
    for (final String token in lowered.split(',')) {
      final String trimmed = token.trim();
      if (trimmed == 'true' ||
          trimmed == '1' ||
          trimmed == normalizedFeature) {
        return true;
      }
    }
  }
  return false;
}

void _setContextCacheAttributes(
  TraceSpanRecord span,
  Object? rawCacheMetadata, {
  Map<String, String>? environment,
}) {
  if (rawCacheMetadata == null) {
    return;
  }
  CacheMetadata? cacheMetadata;
  if (rawCacheMetadata is CacheMetadata) {
    cacheMetadata = rawCacheMetadata;
  }
  if (cacheMetadata == null) {
    return;
  }
  if (!_isExperimentalTelemetryOptedIn(
    'context_cache',
    environment: environment,
  )) {
    return;
  }
  span
    ..setAttribute(
      adkExperimentalContextCacheHit,
      cacheMetadata.cacheName != null,
    )
    ..setAttribute(
      adkExperimentalContextCacheFingerprint,
      cacheMetadata.fingerprint,
    )
    ..setAttribute(
      adkExperimentalContextCacheContentsCount,
      cacheMetadata.contentsCount,
    );
  if (cacheMetadata.invocationsUsed != null) {
    span.setAttribute(
      adkExperimentalContextCacheInvocationsUsed,
      cacheMetadata.invocationsUsed!,
    );
  }
}

void _setGroundingAttributes(
  TraceSpanRecord span,
  Object? rawGroundingMetadata, {
  required bool captureContent,
  Map<String, String>? environment,
}) {
  if (rawGroundingMetadata == null) {
    return;
  }
  if (!_isExperimentalTelemetryOptedIn('grounding', environment: environment)) {
    return;
  }

  final List<String> webSearchQueries = _extractWebSearchQueries(
    rawGroundingMetadata,
  );
  final List<Object?> groundingChunks = _extractGroundingChunks(
    rawGroundingMetadata,
  );

  span
    ..setAttribute(
      adkExperimentalGroundingQueryCount,
      webSearchQueries.toSet().length,
    )
    ..setAttribute(
      adkExperimentalGroundingChunkCount,
      groundingChunks.length,
    );

  if (captureContent) {
    if (webSearchQueries.isNotEmpty) {
      span.setAttribute(
        adkExperimentalGroundingWebSearchQueries,
        webSearchQueries,
      );
    }
    final List<String> sourceUris = _groundingSourceUris(groundingChunks);
    if (sourceUris.isNotEmpty) {
      span.setAttribute(adkExperimentalGroundingSourceUris, sourceUris);
    }
  }
}

List<String> _extractWebSearchQueries(Object groundingMetadata) {
  Object? rawQueries;
  if (groundingMetadata is Map) {
    rawQueries =
        groundingMetadata['web_search_queries'] ??
        groundingMetadata['webSearchQueries'];
  } else {
    final dynamic dynamicMeta = groundingMetadata;
    try {
      rawQueries = dynamicMeta.webSearchQueries;
    } catch (_) {
      try {
        rawQueries = dynamicMeta.web_search_queries;
      } catch (_) {
        rawQueries = null;
      }
    }
  }
  if (rawQueries is! Iterable) {
    return const <String>[];
  }
  final List<String> queries = <String>[];
  for (final Object? entry in rawQueries) {
    if (entry is String && entry.isNotEmpty) {
      queries.add(entry);
    }
  }
  return queries;
}

List<Object?> _extractGroundingChunks(Object groundingMetadata) {
  Object? rawChunks;
  if (groundingMetadata is Map) {
    rawChunks =
        groundingMetadata['grounding_chunks'] ??
        groundingMetadata['groundingChunks'];
  } else {
    final dynamic dynamicMeta = groundingMetadata;
    try {
      rawChunks = dynamicMeta.groundingChunks;
    } catch (_) {
      try {
        rawChunks = dynamicMeta.grounding_chunks;
      } catch (_) {
        rawChunks = null;
      }
    }
  }
  if (rawChunks is Iterable) {
    return rawChunks.toList(growable: false);
  }
  return const <Object?>[];
}

List<String> _groundingSourceUris(List<Object?> groundingChunks) {
  final Set<String> uris = <String>{};
  for (final Object? chunk in groundingChunks) {
    if (chunk == null) {
      continue;
    }
    final List<String?> candidates = <String?>[
      _nestedStringField(chunk, const <String>['web'], const <String>['uri']),
      _nestedStringField(
        chunk,
        const <String>['retrieved_context', 'retrievedContext'],
        const <String>['uri'],
      ),
      _nestedStringField(chunk, const <String>['maps'], const <String>['uri']),
      _nestedStringField(
        chunk,
        const <String>['image'],
        const <String>['source_uri', 'sourceUri'],
      ),
    ];
    for (final String? uri in candidates) {
      if (uri != null && uri.isNotEmpty) {
        uris.add(uri);
      }
    }
  }
  return uris.toList(growable: false);
}

String? _nestedStringField(
  Object target,
  List<String> containerKeys,
  List<String> leafKeys,
) {
  Object? container;
  if (target is Map) {
    for (final String key in containerKeys) {
      if (target.containsKey(key)) {
        container = target[key];
        break;
      }
    }
  } else {
    final dynamic dynTarget = target;
    for (final String key in containerKeys) {
      try {
        if (key == 'web') {
          container = dynTarget.web;
        } else if (key == 'retrieved_context') {
          container = dynTarget.retrieved_context;
        } else if (key == 'retrievedContext') {
          container = dynTarget.retrievedContext;
        } else if (key == 'maps') {
          container = dynTarget.maps;
        } else if (key == 'image') {
          container = dynTarget.image;
        }
        if (container != null) {
          break;
        }
      } catch (_) {}
    }
  }
  if (container == null) {
    return null;
  }
  if (container is Map) {
    for (final String key in leafKeys) {
      final Object? val = container[key];
      if (val is String && val.isNotEmpty) {
        return val;
      }
    }
    return null;
  }
  final dynamic dynContainer = container;
  for (final String key in leafKeys) {
    try {
      Object? val;
      if (key == 'uri') {
        val = dynContainer.uri;
      } else if (key == 'source_uri') {
        val = dynContainer.source_uri;
      } else if (key == 'sourceUri') {
        val = dynContainer.sourceUri;
      }
      if (val is String && val.isNotEmpty) {
        return val;
      }
    } catch (_) {}
  }
  return null;
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
  final TelemetryConfig telemetryConfig =
      telemetryConfigFromInvocationContext(invocationContext);
  final Map<String, Object?> commonAttributes = _buildCommonInferenceAttributes(
    invocationContext,
    modelResponseEvent,
  );
  final Map<String, Object?> logOnlyCommonAttributes =
      _buildLogOnlyInferenceAttributes(invocationContext);

  if (!_shouldEmitNativeTelemetry(
    invocationContext.agent,
    telemetryConfig,
    environment: environment,
  )) {
    return _runWithExtraGenerateContentAttributes(
      commonAttributes,
      () => run(null),
      logOnlyExtraAttributes: logOnlyCommonAttributes,
    );
  }

  final bool useExperimentalSemconv = telemetryConfig
      .shouldUseExperimentalGenAiSemconv(environment: environment);
  final String systemName = _resolveGenAiSystemName(
    llmRequest.model,
    environment: environment,
  );
  if (useExperimentalSemconv &&
      resolveTelemetrySchemaVersion(environment: environment) >=
          schemaVersionSemconvAligned) {
    commonAttributes['gen_ai.provider.name'] = resolveGenAiProviderName(
      llmRequest.model,
      environment: environment,
    );
  }
  final TraceSpanRecord span = tracer.startAsCurrentSpan(
    'generate_content ${llmRequest.model ?? ''}',
  );
  final GenerateContentSpan gcSpan = GenerateContentSpan(
    span,
    invocationContext: invocationContext,
    requestModel: llmRequest.model,
    systemName: systemName,
    startTimeMicros: DateTime.now().microsecondsSinceEpoch,
    llmRequest: llmRequest,
  );

  Object? caughtError;
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
        logOnlyAttributes: logOnlyCommonAttributes,
        environment: environment,
      );
    } else {
      span.setAttribute('gen_ai.system', systemName);
      _emitStablePromptLogs(
        llmRequest,
        systemName: systemName,
        logOnlyCommonAttributes: logOnlyCommonAttributes,
        environment: environment,
      );
    }

    return await run(gcSpan);
  } catch (error) {
    caughtError = error;
    span.setAttribute('error.type', resolveErrorType(error));
    rethrow;
  } finally {
    final double elapsedSeconds = getElapsedSeconds(
      spanStartTimeUnixNano: span.startTimeUnixNano,
      spanEndTimeUnixNano: span.endTimeUnixNano,
      fallbackStartMicros: gcSpan.startTimeMicros,
      fallbackEndMicros: gcSpan.endedAtMicros,
    );
    final Duration duration = Duration(
      microseconds: (elapsedSeconds * 1000000.0).round(),
    );
    final TokenUsage? tokenUsage =
        TokenUsage.fromLlmResponses(gcSpan.responses) ??
        gcSpan.fallbackTokenUsage;
    final List<String> finishReasons = <String>[];
    String? responseModel = gcSpan.firstChunkModel;
    for (final LlmResponse response in gcSpan.responses) {
      if (response.modelVersion != null && response.modelVersion!.isNotEmpty) {
        responseModel = response.modelVersion;
      }
      if (response.finishReason != null && response.finishReason!.isNotEmpty) {
        final String lowered = response.finishReason!.toLowerCase();
        if (!finishReasons.contains(lowered)) {
          finishReasons.add(lowered);
        }
      }
    }
    responseModel ??= llmRequest.model;
    final Object? effectiveError =
        caughtError ?? (span.attributes['error.type']);
    final bool hasGenAiInst =
        _instrumentedWithOpenTelemetryInstrumentationGoogleGenai();
    final int schemaVer = resolveTelemetrySchemaVersion(
      environment: environment,
    );
    final String clientProviderName = schemaVer < schemaVersionSemconvAligned
        ? resolveGenAiSystemNameV1(llmRequest.model, environment: environment)
        : resolveGenAiProviderName(llmRequest.model, environment: environment);

    recordClientOperationDuration(
      invocationContext.agent.name,
      duration,
      requestModel: llmRequest.model,
      responseModel: responseModel,
      system: systemName,
      serverAddress: gcSpan.serverAddress,
      serverPort: gcSpan.serverPort,
      finishReasons: finishReasons.isEmpty ? null : finishReasons,
      error: effectiveError,
    );
    if (shouldEmitInferenceTokenMetrics(
      system: systemName,
      hasGenAiInstrumentor: hasGenAiInst,
      instrumentorVersion: _genAiInstrumentorVersion,
      environment: environment,
    )) {
      recordInferenceTokenUsage(
        tokenUsage: tokenUsage,
        agentName: invocationContext.agent.name,
        requestModel: llmRequest.model,
        responseModel: responseModel,
        system: systemName,
        providerName: clientProviderName,
        serverAddress: gcSpan.serverAddress,
        serverPort: gcSpan.serverPort,
        finishReasons: finishReasons.isEmpty ? null : finishReasons,
        error: effectiveError,
      );
    }
    if (shouldEmitSemconvInferenceTokenMetrics(
      llmRequest.model,
      hasGenAiInstrumentor: hasGenAiInst,
      instrumentorVersion: _genAiInstrumentorVersion,
      environment: environment,
    )) {
      recordSemconvInferenceTokenUsage(
        llmRequest: llmRequest,
        responses: gcSpan.responses,
        error: effectiveError,
        environment: environment,
      );
    }

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
  GenerateContentSpan(
    this.span, {
    this.invocationContext,
    this.requestModel,
    this.systemName,
    this.serverAddress,
    this.serverPort,
    int? startTimeMicros,
    LlmRequest? llmRequest,
  }) : _llmRequest = llmRequest,
       startTimeMicros =
           startTimeMicros ?? DateTime.now().microsecondsSinceEpoch;

  /// Underlying trace span.
  final TraceSpanRecord span;

  /// Invocation context associated with this inference span, if available.
  final InvocationContext? invocationContext;

  /// Requested model name for this inference span.
  final String? requestModel;

  /// Resolved `gen_ai.system` value for this inference span.
  final String? systemName;

  /// Optional server address for this inference span.
  final String? serverAddress;

  /// Optional server port for this inference span.
  final int? serverPort;

  final LlmRequest? _llmRequest;

  /// The [LlmRequest] associated with this inference span, if available.
  LlmRequest? get llmRequest => _llmRequest;

  /// Start timestamp of the inference span in microseconds.
  int startTimeMicros;

  /// Timestamp of the last received streaming chunk in microseconds.
  int? lastChunkTimeMicros;

  /// Model version observed on the first streaming chunk.
  String? firstChunkModel;

  /// Responses accumulated during this inference span.
  final List<LlmResponse> responses = <LlmResponse>[];

  /// Timestamp in microseconds when the model response finished (`finishReason`
  /// arrived), excluding any subsequent tool execution runtime.
  int? endedAtMicros;

  /// Marks this inference span's model-call phase ended at [nowMicros] (or now).
  void endInference([int? nowMicros]) {
    if (endedAtMicros != null) {
      return;
    }
    endedAtMicros = nowMicros ?? DateTime.now().microsecondsSinceEpoch;
  }

  /// Fallback token usage recorded by streaming adapters when responses are not
  /// retained or fail mid-stream.
  TokenUsage? fallbackTokenUsage;

  /// Experimental operation details attributes.
  final Map<String, Object?> operationDetailsAttributes = <String, Object?>{};

  /// Common attributes shared by operation details logs.
  final Map<String, Object?> operationDetailsCommonAttributes =
      <String, Object?>{};
}

/// Records streaming chunk timing metrics for [response] within [span].
///
/// The first chunk emits both `gen_ai.client.operation.time_to_first_chunk`
/// and `gen_ai.client.inference.chunk.duration`; subsequent chunks emit
/// `gen_ai.client.inference.chunk.duration` using the elapsed time since the
/// previous chunk.
void recordInferenceChunk(
  GenerateContentSpan? span,
  LlmResponse response, {
  int? nowMicros,
  AdkMetricsRecorder? recorder,
}) {
  if (span == null || response.partial == false) {
    return;
  }
  final int currentMicros =
      nowMicros ?? DateTime.now().microsecondsSinceEpoch;
  final bool isFirstChunk = span.lastChunkTimeMicros == null;
  final int baselineMicros = span.lastChunkTimeMicros ?? span.startTimeMicros;
  span.lastChunkTimeMicros = currentMicros;
  final int deltaMicros = currentMicros >= baselineMicros
      ? currentMicros - baselineMicros
      : 0;
  if (isFirstChunk) {
    span.firstChunkModel =
        (response.modelVersion != null && response.modelVersion!.isNotEmpty)
        ? response.modelVersion
        : span.requestModel;
  }
  final String? responseModel =
      span.firstChunkModel ?? response.modelVersion ?? span.requestModel;
  recordClientInferenceChunk(
    Duration(microseconds: deltaMicros),
    isFirstChunk: isFirstChunk,
    agentName: span.invocationContext?.agent.name,
    requestModel: span.requestModel,
    responseModel: responseModel,
    system: span.systemName,
    serverAddress: span.serverAddress,
    serverPort: span.serverPort,
    recorder: recorder,
  );
}

/// Records fallback [tokenUsage] on [span] for streaming or failed calls.
void recordInferenceOutputTokenUsage(
  GenerateContentSpan? span,
  TokenUsage tokenUsage,
) {
  if (span == null) {
    return;
  }
  span.fallbackTokenUsage = tokenUsage;
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

  final String? modelVersion = llmResponse.modelVersion;
  if (modelVersion != null && modelVersion.isNotEmpty) {
    span.setAttribute(genAiResponseModel, modelVersion);
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
  InvocationContext? invocationContext,
  Map<String, String>? environment,
}) {
  GenerateContentSpan? generateContentSpan;
  TraceSpanRecord? targetSpan;
  LlmRequest? llmRequest;

  if (span is GenerateContentSpan) {
    generateContentSpan = span;
    llmRequest = span._llmRequest;
    targetSpan = span.span;
    if (llmResponse.partial != true) {
      span.responses.add(llmResponse);
    }
    if (span.endedAtMicros != null) {
      return;
    }
  } else if (span is TraceSpanRecord) {
    targetSpan = span;
  }

  if (targetSpan == null || llmResponse.partial == true) {
    return;
  }

  final InvocationContext? effectiveInvocationContext =
      invocationContext ?? generateContentSpan?.invocationContext;

  final String? finishReason = llmResponse.finishReason;
  if (finishReason != null && finishReason.isNotEmpty) {
    targetSpan.setAttribute('gen_ai.response.finish_reasons', <String>[
      finishReason.toLowerCase(),
    ]);
  }
  final String? responseModel = _responseModel(
    effectiveInvocationContext,
    llmResponse,
    llmRequest,
  );
  if (responseModel != null && responseModel.isNotEmpty) {
    targetSpan.setAttribute(genAiResponseModel, responseModel);
  }
  _setUsageMetadataAttributes(targetSpan, llmResponse.usageMetadata);
  _setContextCacheAttributes(
    targetSpan,
    llmResponse.cacheMetadata,
    environment: environment,
  );
  _setGroundingAttributes(
    targetSpan,
    llmResponse.groundingMetadata,
    captureContent: _shouldAddContentToExperimentalSpans(
      environment: environment,
    ),
    environment: environment,
  );

  final TelemetryConfig telemetryConfig = effectiveInvocationContext != null
      ? telemetryConfigFromInvocationContext(effectiveInvocationContext)
      : const TelemetryConfig();
  if (telemetryConfig.shouldUseExperimentalGenAiSemconv(
        environment: environment,
      ) &&
      generateContentSpan != null) {
    experimental_semconv.setOperationDetailsAttributesFromResponse(
      llmResponse,
      generateContentSpan.operationDetailsAttributes,
      generateContentSpan.operationDetailsCommonAttributes,
    );
    if (finishReason != null && finishReason.isNotEmpty) {
      generateContentSpan.endInference();
    }
    return;
  }

  _emitChoiceLog(
    llmResponse,
    invocationContext: effectiveInvocationContext,
    llmRequest: llmRequest,
    environment: environment,
  );
  if (finishReason != null && finishReason.isNotEmpty) {
    generateContentSpan?.endInference();
  }
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
    'environment_id': llmResponse.environmentId,
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

const Set<String> _authCredentialTypeValues = <String>{
  'apiKey',
  'http',
  'oauth2',
  'openIdConnect',
  'serviceAccount',
  'api_key',
  'open_id_connect',
  'service_account',
};

const Set<String> _credentialSecretKeys = <String>{
  'api_key',
  'apiKey',
  'password',
  'token',
  'additional_headers',
  'additionalHeaders',
  'client_secret',
  'clientSecret',
  'nonce',
  'state',
  'auth_response_uri',
  'authResponseUri',
  'auth_code',
  'authCode',
  'access_token',
  'accessToken',
  'refresh_token',
  'refreshToken',
  'id_token',
  'idToken',
  'code_verifier',
  'codeVerifier',
  'service_account_credential',
  'serviceAccountCredential',
  'private_key_id',
  'privateKeyId',
  'private_key',
  'privateKey',
};

const Set<String> _standaloneSerializedSecretKeys = <String>{
  'password',
  'additional_headers',
  'additionalHeaders',
  'client_secret',
  'clientSecret',
  'auth_response_uri',
  'authResponseUri',
  'auth_code',
  'authCode',
  'access_token',
  'accessToken',
  'refresh_token',
  'refreshToken',
  'id_token',
  'idToken',
  'code_verifier',
  'codeVerifier',
  'service_account_credential',
  'serviceAccountCredential',
  'private_key_id',
  'privateKeyId',
  'private_key',
  'privateKey',
};

bool _isJsonSchemaDescriptor(Object? value) {
  if (value is! Map || value['type'] is! String) {
    return false;
  }
  const Set<String> schemaMetaKeys = <String>{
    'type',
    'description',
    'nullable',
    'items',
    'properties',
    'required',
    'enum',
    'default',
    'format',
    'title',
    'anyOf',
    'oneOf',
    'allOf',
    r'$ref',
  };
  return value.keys.every((Object? k) => schemaMetaKeys.contains('$k'));
}

bool _isStandaloneHttpCredentialsMap(Map<Object?, Object?> map) {
  if (map.isEmpty) {
    return false;
  }
  const Set<String> httpCredKeys = <String>{'username', 'password', 'token'};
  if (!map.keys.every((Object? k) => httpCredKeys.contains('$k'))) {
    return false;
  }
  return map.containsKey('username') || map.containsKey('password');
}

String _formatJsonMapKey(Object? key) {
  if (key is String) {
    return key;
  }
  if (key is bool) {
    return key ? 'true' : 'false';
  }
  if (key is num) {
    return '$key';
  }
  if (key is Enum) {
    try {
      final Object? customValue = (key as dynamic).value;
      if (customValue is String) {
        return customValue;
      }
      if (customValue != null) {
        return '$customValue';
      }
    } catch (_) {}
    return key.name;
  }
  if (key is Iterable) {
    return key.map((Object? item) => _formatJsonMapKey(item)).join(',');
  }
  return '$key';
}

/// Walks live [value] alongside its JSON-dumped form [dumped] and masks any
/// values whose live runtime type is a known credential carrier.
Object? maskCredentialValues(Object? value, Object? dumped) {
  if (isCredentialType(value)) {
    return redacted;
  }
  if (value is FunctionResponse && dumped is Map) {
    final Map<String, Object?> masked = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in dumped.entries)
        '${entry.key}': entry.value,
    };
    if (masked.containsKey('response')) {
      masked['response'] = maskCredentialValues(
        value.response,
        masked['response'],
      );
    }
    return masked;
  }
  if (value is FunctionCall && dumped is Map) {
    final Map<String, Object?> masked = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in dumped.entries)
        '${entry.key}': entry.value,
    };
    if (masked.containsKey('args')) {
      masked['args'] = maskCredentialValues(value.args, masked['args']);
    }
    return masked;
  }
  if (value is Part && dumped is Map) {
    final Map<String, Object?> masked = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in dumped.entries)
        '${entry.key}': entry.value,
    };
    if (value.functionCall != null) {
      for (final String k in const <String>['function_call', 'functionCall']) {
        if (masked.containsKey(k)) {
          masked[k] = maskCredentialValues(value.functionCall, masked[k]);
        }
      }
    }
    if (value.functionResponse != null) {
      for (final String k in const <String>[
        'function_response',
        'functionResponse',
      ]) {
        if (masked.containsKey(k)) {
          masked[k] = maskCredentialValues(value.functionResponse, masked[k]);
        }
      }
    }
    return masked;
  }
  if (value is Content && dumped is Map) {
    final Map<String, Object?> masked = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in dumped.entries)
        '${entry.key}': entry.value,
    };
    if (masked['parts'] is List) {
      masked['parts'] = maskCredentialValues(value.parts, masked['parts']);
    }
    return masked;
  }
  if (value is Event && dumped is Map) {
    final Map<String, Object?> masked = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in dumped.entries)
        '${entry.key}': entry.value,
    };
    if (value.content != null && masked.containsKey('content')) {
      masked['content'] = maskCredentialValues(
        value.content,
        masked['content'],
      );
    }
    return masked;
  }
  if (value is Map && dumped is Map) {
    final Map<String, Object?> byDumpKey = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      byDumpKey[_formatJsonMapKey(entry.key)] = entry.value;
    }
    final Map<String, Object?> masked = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in dumped.entries)
        '${entry.key}': entry.value,
    };
    for (final MapEntry<String, Object?> entry in byDumpKey.entries) {
      if (masked.containsKey(entry.key)) {
        masked[entry.key] = maskCredentialValues(
          entry.value,
          masked[entry.key],
        );
      }
    }
    return masked;
  }
  if (value is Iterable &&
      value is! String &&
      dumped is List &&
      value.length == dumped.length) {
    final List<Object?> liveList = value.toList(growable: false);
    return <Object?>[
      for (int i = 0; i < liveList.length; i += 1)
        maskCredentialValues(liveList[i], dumped[i]),
    ];
  }
  return dumped;
}

Map<String, Object?> _stripCredentialSecretsFromMap(Map<Object?, Object?> map) {
  final Map<String, Object?> out = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in map.entries) {
    final String key = '${entry.key}';
    if (_credentialSecretKeys.contains(key)) {
      continue;
    }
    final Object? val = entry.value;
    if (val is Map) {
      out[key] = _stripCredentialSecretsFromMap(val);
    } else if (val is List) {
      out[key] = <Object?>[
        for (final Object? item in val)
          item is Map ? _stripCredentialSecretsFromMap(item) : item,
      ];
    } else {
      out[key] = val;
    }
  }
  return out;
}

Map<String, Object?> _redactAuthConfigSecrets(Map<Object?, Object?> config) {
  final Map<String, Object?> redactedConfig = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in config.entries) {
    final String key = '${entry.key}';
    final Object? val = entry.value;
    if ((key == 'raw_auth_credential' ||
            key == 'rawAuthCredential' ||
            key == 'exchanged_auth_credential' ||
            key == 'exchangedAuthCredential') &&
        val is Map) {
      redactedConfig[key] = _stripCredentialSecretsFromMap(val);
    } else {
      redactedConfig[key] = _redactCredentialSecrets(val);
    }
  }
  return redactedConfig;
}

Object? _redactCredentialSecrets(Object? value) {
  if (value is List) {
    return <Object?>[
      for (final Object? item in value) _redactCredentialSecrets(item),
    ];
  }
  if (value is! Map) {
    return value;
  }
  final Object? authType = value['auth_type'] ?? value['authType'];
  if (authType is String && _authCredentialTypeValues.contains(authType)) {
    return _stripCredentialSecretsFromMap(value);
  }
  if (value['raw_auth_credential'] is Map ||
      value['rawAuthCredential'] is Map ||
      value['exchanged_auth_credential'] is Map ||
      value['exchangedAuthCredential'] is Map ||
      value['auth_scheme'] is Map ||
      value['authScheme'] is Map) {
    return _redactAuthConfigSecrets(value);
  }
  if (_isStandaloneHttpCredentialsMap(value)) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}':
            ('${entry.key}' == 'password' || '${entry.key}' == 'token') &&
                entry.value != null
            ? redacted
            : entry.value,
    };
  }
  final bool isStandaloneHttpAuthMap =
      value['scheme'] is String && value['credentials'] is Map;

  final Map<String, Object?> out = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final String key = '${entry.key}';
    final Object? item = entry.value;
    if (key == 'args' &&
        value['name'] == requestEucFunctionCallName &&
        item is Map) {
      final Map<String, Object?> argsCopy = <String, Object?>{};
      for (final MapEntry<Object?, Object?> argEntry in item.entries) {
        final String argKey = '${argEntry.key}';
        if ((argKey == 'auth_config' || argKey == 'authConfig') &&
            argEntry.value is Map) {
          argsCopy[argKey] = _redactAuthConfigSecrets(argEntry.value as Map);
        } else {
          argsCopy[argKey] = _redactCredentialSecrets(argEntry.value);
        }
      }
      out[key] = argsCopy;
    } else if (key == 'response' &&
        value['name'] == requestEucFunctionCallName &&
        item is Map) {
      out[key] = _redactAuthConfigSecrets(item);
    } else if ((key == 'requested_auth_configs' ||
            key == 'requestedAuthConfigs') &&
        item is Map) {
      out[key] = <String, Object?>{
        for (final MapEntry<Object?, Object?> cfgEntry in item.entries)
          '${cfgEntry.key}': cfgEntry.value is Map
              ? _redactAuthConfigSecrets(cfgEntry.value as Map)
              : _redactCredentialSecrets(cfgEntry.value),
      };
    } else if (isStandaloneHttpAuthMap &&
        key == 'credentials' &&
        item is Map) {
      out[key] = <String, Object?>{
        for (final MapEntry<Object?, Object?> credEntry in item.entries)
          '${credEntry.key}':
              ('${credEntry.key}' == 'password' ||
                      '${credEntry.key}' == 'token') &&
                  credEntry.value != null
              ? redacted
              : _redactCredentialSecrets(credEntry.value),
      };
    } else if (_standaloneSerializedSecretKeys.contains(key) &&
        item != null &&
        !_isJsonSchemaDescriptor(item)) {
      out[key] = redacted;
    } else {
      out[key] = _redactCredentialSecrets(item);
    }
  }
  return out;
}

Object? _redactCredentials(Object? value, Set<int> active) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (isCredentialType(value)) {
    return redacted;
  }
  if (value is Enum) {
    try {
      final Object? enumValue = (value as dynamic).value;
      if (enumValue == null ||
          enumValue is String ||
          enumValue is num ||
          enumValue is bool) {
        return enumValue;
      }
    } catch (_) {}
    return value.name;
  }

  final int id = identityHashCode(value);
  if (!active.add(id)) {
    throw const FormatException('Circular reference detected');
  }
  try {
    if (value is Map) {
      final Map<String, Object?> out = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        out[_formatJsonMapKey(entry.key)] = _redactCredentials(
          entry.value,
          active,
        );
      }
      return out;
    }
    if (value is Iterable) {
      return <Object?>[
        for (final Object? item in value) _redactCredentials(item, active),
      ];
    }
    if (value is Event) {
      return _redactCredentials(_eventToJson(value), active);
    }
    if (value is Content) {
      return _redactCredentials(
        _contentToJson(value, includeInlineData: true),
        active,
      );
    }
    if (value is Part) {
      return _redactCredentials(
        _partToJson(value, includeInlineData: true),
        active,
      );
    }
    try {
      final Object? dumped = (value as dynamic).toJson();
      final Object? masked = maskCredentialValues(value, dumped);
      return _redactCredentials(masked, active);
    } on NoSuchMethodError {
      // Fall through to `toMap` or string representation when `toJson` is absent.
    }
    try {
      final Object? dumped = (value as dynamic).toMap();
      final Object? masked = maskCredentialValues(value, dumped);
      return _redactCredentials(masked, active);
    } on NoSuchMethodError {
      // Fall through to string representation when `toMap` is absent.
    }
    return '$value';
  } finally {
    active.remove(id);
  }
}

/// Serializes [value] to JSON while masking live credential carriers,
/// stripping dumped `AuthCredential` / `AuthConfig` secret fields, and
/// returning `'<not serializable>'` on circular references or failures.
String safeJsonSerialize(Object? value) {
  try {
    final Object? normalized = _redactCredentialSecrets(
      _redactCredentials(value, <int>{}),
    );
    return jsonEncode(normalized);
  } catch (_) {
    return '<not serializable>';
  }
}

String _safeJsonSerialize(Object? value) => safeJsonSerialize(value);

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

bool _shouldAddContentToExperimentalSpans({Map<String, String>? environment}) {
  final String mode = experimental_semconv.getContentCapturingMode(
    environment: environment,
  );
  return mode == 'SPAN_ONLY' || mode == 'SPAN_AND_EVENT';
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
  String? systemName,
  Map<String, Object?> logOnlyCommonAttributes = const <String, Object?>{},
  Map<String, String>? environment,
}) {
  final String resolvedSystemName =
      systemName ??
      _resolveGenAiSystemName(llmRequest.model, environment: environment);
  otelLogger.emit(
    OTelLogRecord(
      eventName: 'gen_ai.system.message',
      body: <String, Object?>{
        'content': _serializeContentWithElision(
          llmRequest.config.systemInstruction,
          environment: environment,
        ),
      },
      attributes: <String, Object?>{'gen_ai.system': resolvedSystemName},
    ),
  );

  final Map<String, Object?> userMessageAttributes = <String, Object?>{
    'gen_ai.system': resolvedSystemName,
  };
  if (_shouldLogPromptResponseContent(environment: environment)) {
    final Object? userId = logOnlyCommonAttributes['user.id'];
    if (userId != null) {
      userMessageAttributes['user.id'] = userId;
    }
  }

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
        attributes: userMessageAttributes,
      ),
    );
  }
}

void _emitChoiceLog(
  LlmResponse llmResponse, {
  InvocationContext? invocationContext,
  LlmRequest? llmRequest,
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
        'gen_ai.system': _inferenceSystemName(
          invocationContext,
          llmResponse,
          llmRequest: llmRequest,
          environment: environment,
        ),
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
  final Object? reasoningTokens =
      usage['thoughts_token_count'] ??
      usage['thoughtsTokenCount'] ??
      usage['reasoning_tokens'] ??
      usage['reasoningTokens'];
  final Object? systemInstructionTokens =
      usage['system_instruction_tokens'] ?? usage['systemInstructionTokens'];

  if (promptTokenCount is num) {
    span.setAttribute('gen_ai.usage.input_tokens', promptTokenCount);
  }
  if (candidatesTokenCount is num) {
    final num outputTokens = reasoningTokens is num
        ? candidatesTokenCount + reasoningTokens
        : candidatesTokenCount;
    span.setAttribute('gen_ai.usage.output_tokens', outputTokens);
  }
  if (reasoningTokens is num) {
    span.setAttribute('gen_ai.usage.reasoning.output_tokens', reasoningTokens);
  }
  if (systemInstructionTokens is num) {
    span.setAttribute(
      'gen_ai.usage.experimental.system_instruction_tokens',
      systemInstructionTokens,
    );
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

Object? _thinkingBudgetValue(Object? thinkingConfig) {
  if (thinkingConfig is Map<String, Object?>) {
    return thinkingConfig['thinking_budget'] ??
        thinkingConfig['thinkingBudget'] ??
        thinkingConfig['budget'];
  }
  if (thinkingConfig is Map<String, dynamic>) {
    return thinkingConfig['thinking_budget'] ??
        thinkingConfig['thinkingBudget'] ??
        thinkingConfig['budget'];
  }
  if (thinkingConfig is Map) {
    return thinkingConfig['thinking_budget'] ??
        thinkingConfig['thinkingBudget'] ??
        thinkingConfig['budget'];
  }
  return null;
}

Map<String, Object?> _buildCommonInferenceAttributes(
  InvocationContext invocationContext,
  Event modelResponseEvent,
) {
  return <String, Object?>{
    'gen_ai.agent.name': invocationContext.agent.name,
    'gen_ai.conversation.id': invocationContext.session.id,
    'gcp.vertex.agent.event_id': modelResponseEvent.id,
    'gcp.vertex.agent.invocation_id': invocationContext.invocationId,
  };
}

Map<String, Object?> _buildLogOnlyInferenceAttributes(
  InvocationContext invocationContext,
) {
  return <String, Object?>{'user.id': invocationContext.session.userId};
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
String? _genAiInstrumentorVersion;

/// Sets the detector used to identify external GenAI instrumentation.
///
/// This is intended for tests.
void setGenAiInstrumentationDetectorForTest(
  GenAiInstrumentationDetector detector, {
  String? version,
}) {
  _genAiInstrumentationDetector = detector;
  _genAiInstrumentorVersion = version;
}

/// Sets the simulated `opentelemetry-instrumentation-google-genai` version for tests.
void setGenAiInstrumentorVersionForTest(String? version) {
  _genAiInstrumentorVersion = version;
}

/// Returns the simulated `opentelemetry-instrumentation-google-genai` version, if set.
String? getGenAiInstrumentorVersionForTest() => _genAiInstrumentorVersion;

/// Restores the default GenAI instrumentation detector.
///
/// This is intended for tests.
void resetGenAiInstrumentationDetectorForTest() {
  _genAiInstrumentationDetector = () => false;
  _genAiInstrumentorVersion = null;
}

/// Returns `true` when external `opentelemetry-instrumentation-google-genai`
/// instrumentation is active.
bool isGenAiInstrumented() {
  return _genAiInstrumentationDetector();
}

bool _instrumentedWithOpenTelemetryInstrumentationGoogleGenai() {
  return _genAiInstrumentationDetector();
}

final Object _generateContentExtraAttributesContextKey = Object();
final Object _generateContentEventOnlyExtraAttributesContextKey = Object();

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

/// The current zone-scoped event-only attributes for generate-content logs.
Map<String, Object?>? getCurrentGenerateContentEventOnlyExtraAttributes() {
  final Object? value =
      Zone.current[_generateContentEventOnlyExtraAttributesContextKey];
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
  T Function() run, {
  Map<String, Object?> logOnlyExtraAttributes = const <String, Object?>{},
}) {
  return runZoned(
    run,
    zoneValues: <Object?, Object?>{
      _generateContentExtraAttributesContextKey: Map<String, Object?>.from(
        extraAttributes,
      ),
      if (logOnlyExtraAttributes.isNotEmpty)
        _generateContentEventOnlyExtraAttributesContextKey:
            Map<String, Object?>.from(logOnlyExtraAttributes),
    },
  );
}

String? _agentModelName(BaseAgent agent) {
  if (agent is! LlmAgent) {
    return null;
  }
  final Object model = agent.model;
  if (model is String) {
    if (model.isEmpty) {
      try {
        return agent.canonicalModel.model;
      } catch (_) {
        return LlmAgent.defaultModel;
      }
    }
    return model;
  }
  if (model is BaseLlm) {
    return model.model;
  }
  return null;
}

bool _isGeminiAgent(BaseAgent agent) {
  if (agent is! LlmAgent) {
    return false;
  }

  final Object model = agent.model;
  if (model is Gemini) {
    return true;
  }
  if (model is BaseLlm) {
    return isGeminiModel(model.model);
  }
  final String? modelName = _agentModelName(agent);
  return modelName != null && isGeminiModel(modelName);
}

bool _instrumentorHasStableMode() {
  final String? version = _genAiInstrumentorVersion?.trim();
  if (version == null || version.isEmpty) {
    return false;
  }
  final Match? majorMatch = RegExp(r'^(\d+)').firstMatch(version);
  if (majorMatch == null) {
    return false;
  }
  final int? major = int.tryParse(majorMatch.group(1)!);
  return major != null && major < 1;
}

/// Returns `true` when the external `opentelemetry-instrumentation-google-genai`
/// instrumentor records a Gemini inference under [telemetryConfig].
bool genaiInstrumentorRecordsInference(
  TelemetryConfig telemetryConfig, {
  Map<String, String>? environment,
}) {
  if (!_instrumentedWithOpenTelemetryInstrumentationGoogleGenai()) {
    return false;
  }
  final Map<String, String> env = environment ?? Platform.environment;
  final String ignoreRunConfig =
      (env['ADK_TELEMETRY_IGNORE_RUN_CONFIG'] ?? '').trim().toLowerCase();
  final bool ignorePerRequest =
      ignoreRunConfig == '1' || ignoreRunConfig == 'true';

  bool wantsExperimental;
  if (!ignorePerRequest &&
      telemetryConfig.genaiSemconvStabilityOptIn != null) {
    final Set<String> tokens = telemetryConfig.genaiSemconvStabilityOptIn!
        .split(',')
        .map((String s) => s.trim())
        .toSet();
    wantsExperimental =
        tokens.contains('experimental') ||
        tokens.contains('gen_ai_latest_experimental');
  } else if (!ignorePerRequest && telemetryConfig.useExperimentalSemconv) {
    wantsExperimental = true;
  } else if (experimental_semconv.isExperimentalSemconv(environment: env)) {
    wantsExperimental = true;
  } else {
    wantsExperimental =
        resolveTelemetrySchemaVersion(environment: env) >=
        schemaVersionSemconvAligned;
  }

  if (!wantsExperimental) {
    return false;
  }
  if (_instrumentorHasStableMode() &&
      !experimental_semconv.isExperimentalSemconv(environment: env)) {
    return false;
  }
  return true;
}

bool _shouldEmitNativeTelemetry(
  BaseAgent agent,
  TelemetryConfig telemetryConfig, {
  Map<String, String>? environment,
}) {
  if (!_isGeminiAgent(agent)) {
    return true;
  }
  return !genaiInstrumentorRecordsInference(
    telemetryConfig,
    environment: environment,
  );
}

String? _genAiSystemNameFromModel(
  String? model, {
  Map<String, String>? environment,
}) {
  if (model == null || model.isEmpty) {
    return null;
  }
  if (isGeminiModel(model)) {
    final Map<String, String> env = environment ?? Platform.environment;
    final String value = (env['GOOGLE_GENAI_USE_VERTEXAI'] ?? '').toLowerCase();
    if (value == 'true' || value == '1') {
      return 'gcp.vertex.agent';
    }
    return 'gcp.gemini';
  }
  final String normalized = extractModelName(model);
  if (normalized.startsWith('claude-')) {
    return 'anthropic';
  }
  return null;
}

String _resolveGenAiSystemName(
  String? model, {
  Map<String, String>? environment,
}) {
  return _genAiSystemNameFromModel(model, environment: environment) ?? '_other';
}

String? _responseModel(
  InvocationContext? invocationContext,
  LlmResponse llmResponse, [
  LlmRequest? llmRequest,
]) {
  final String? modelVersion = llmResponse.modelVersion;
  if (modelVersion != null && modelVersion.isNotEmpty) {
    return modelVersion;
  }
  final String? requestModel = llmRequest?.model;
  if (requestModel != null && requestModel.isNotEmpty) {
    return requestModel;
  }
  final BaseAgent? agent = invocationContext?.agent;
  if (agent != null) {
    return _agentModelName(agent);
  }
  return null;
}

String _inferenceSystemName(
  InvocationContext? invocationContext,
  LlmResponse llmResponse, {
  LlmRequest? llmRequest,
  Map<String, String>? environment,
}) {
  final String? fromResponse = _genAiSystemNameFromModel(
    llmResponse.modelVersion,
    environment: environment,
  );
  if (fromResponse != null) {
    return fromResponse;
  }
  String? model = llmRequest?.model;
  if ((model == null || model.isEmpty) && invocationContext != null) {
    model = _agentModelName(invocationContext.agent);
  }
  final String? fromFallback = _genAiSystemNameFromModel(
    model,
    environment: environment,
  );
  if (fromFallback != null) {
    return fromFallback;
  }
  return 'gcp.vertex.agent';
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

const String _internalTelemetryMetadataKey =
    '__adk_internal_telemetry_config';

final Expando<TelemetryConfig> _runConfigTelemetryExpando =
    Expando<TelemetryConfig>('RunConfig.telemetry');

/// Attaches per-run [TelemetryConfig] to [RunConfig].
extension RunConfigTelemetryExtension on RunConfig {
  /// Per-invocation telemetry configuration override, if set.
  TelemetryConfig? get telemetry {
    final TelemetryConfig? attached = _runConfigTelemetryExpando[this];
    if (attached != null) {
      return attached;
    }
    final Object? fromInternal = customMetadata?[_internalTelemetryMetadataKey];
    if (fromInternal is TelemetryConfig) {
      return fromInternal;
    }
    final Object? fromMeta = customMetadata?['telemetry'];
    if (fromMeta is TelemetryConfig) {
      return fromMeta;
    }
    return null;
  }

  set telemetry(TelemetryConfig? value) {
    _runConfigTelemetryExpando[this] = value;
    if (value != null) {
      final Map<String, dynamic> meta = customMetadata ?? <String, dynamic>{};
      meta[_internalTelemetryMetadataKey] = value;
      customMetadata = meta;
    } else if (customMetadata != null) {
      customMetadata!.remove(_internalTelemetryMetadataKey);
      if (customMetadata!.isEmpty) {
        customMetadata = null;
      }
    }
  }
}

/// Resolves [TelemetryConfig] from [invocationContext] if present.
TelemetryConfig telemetryConfigFromInvocationContext(
  InvocationContext? invocationContext,
) {
  if (invocationContext == null) {
    return const TelemetryConfig();
  }
  final RunConfig? runConfig = invocationContext.runConfig;
  if (runConfig == null) {
    return const TelemetryConfig();
  }
  return runConfig.telemetry ?? const TelemetryConfig();
}

/// Configuration for telemetry capture behavior.
class TelemetryConfig {
  /// Creates a [TelemetryConfig].
  const TelemetryConfig({
    this.captureMessageContent = true,
    this.useExperimentalSemconv = false,
    this.genaiSemconvStabilityOptIn,
  });

  /// Whether message and tool content payloads are captured on spans/logs.
  final bool captureMessageContent;

  /// Whether OpenTelemetry GenAI experimental semantic conventions are enabled.
  final bool useExperimentalSemconv;

  /// Optional per-request override for `OTEL_SEMCONV_STABILITY_OPT_IN`
  /// (for example `'stable'` or `'gen_ai_latest_experimental'`).
  final String? genaiSemconvStabilityOptIn;

  /// Resolves whether experimental GenAI semantic conventions apply for this
  /// configuration under [environment].
  bool shouldUseExperimentalGenAiSemconv({Map<String, String>? environment}) {
    final Map<String, String> env = environment ?? Platform.environment;
    final String ignoreRunConfig =
        (env['ADK_TELEMETRY_IGNORE_RUN_CONFIG'] ?? '').trim().toLowerCase();
    if (ignoreRunConfig != '1' && ignoreRunConfig != 'true') {
      if (genaiSemconvStabilityOptIn != null) {
        final Set<String> tokens = genaiSemconvStabilityOptIn!
            .split(',')
            .map((String token) => token.trim())
            .toSet();
        return tokens.contains('experimental') ||
            tokens.contains('gen_ai_latest_experimental');
      }
      if (useExperimentalSemconv) {
        return true;
      }
    }
    return experimental_semconv.isExperimentalSemconv(environment: env);
  }
}

/// Scoped telemetry context holder for node and agent execution.
class TelemetryContext {
  /// Creates a [TelemetryContext].
  TelemetryContext({
    this.config = const TelemetryConfig(),
    Map<String, Object?>? attributes,
  }) : attributes = Map<String, Object?>.from(
         attributes ?? const <String, Object?>{},
       );

  /// Active telemetry configuration.
  final TelemetryConfig config;

  /// Context-scoped attributes propagated to child spans.
  final Map<String, Object?> attributes;
}

/// Structured log entry exported for the ADK Web UI trace viewer.
class WebUiLog {
  /// Creates a [WebUiLog].
  WebUiLog({
    required this.eventName,
    required this.body,
    Map<String, Object?>? attributes,
    this.spanId,
    this.traceId,
  }) : attributes = Map<String, Object?>.unmodifiable(
         attributes ?? const <String, Object?>{},
       );

  /// Event name (for example `'gen_ai.user.message'`).
  final String eventName;

  /// Structured or scalar log body.
  final Object? body;

  /// Log record attributes.
  final Map<String, Object?> attributes;

  /// Associated span ID, if any.
  final String? spanId;

  /// Associated trace ID, if any.
  final String? traceId;

  /// Converts this log entry to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'event_name': eventName,
      'body': body,
      'attributes': attributes,
      if (spanId != null) 'span_id': spanId,
      if (traceId != null) 'trace_id': traceId,
    };
  }
}

/// Structured span snapshot exported for the ADK Web UI trace viewer.
class WebUiSpan {
  /// Creates a [WebUiSpan].
  WebUiSpan({
    required this.name,
    required this.spanId,
    required this.traceId,
    this.parentSpanId,
    this.startTimeUnixNano = 0,
    this.endTimeUnixNano = 0,
    Map<String, Object?>? attributes,
    List<WebUiLog>? logs,
  }) : attributes = Map<String, Object?>.unmodifiable(
         attributes ?? const <String, Object?>{},
       ),
       logs = List<WebUiLog>.unmodifiable(logs ?? const <WebUiLog>[]);

  /// Span name.
  final String name;

  /// Span identifier.
  final String spanId;

  /// Trace identifier.
  final String traceId;

  /// Optional parent span identifier.
  final String? parentSpanId;

  /// Start timestamp in Unix nanoseconds.
  final int startTimeUnixNano;

  /// End timestamp in Unix nanoseconds.
  final int endTimeUnixNano;

  /// Span attributes.
  final Map<String, Object?> attributes;

  /// Logs attached to this span.
  final List<WebUiLog> logs;

  /// Converts this span snapshot to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'span_id': spanId,
      'trace_id': traceId,
      'parent_span_id': parentSpanId,
      'start_time': startTimeUnixNano,
      'end_time': endTimeUnixNano,
      'attributes': attributes,
      'logs': logs.map((WebUiLog l) => l.toJson()).toList(growable: false),
    };
  }
}

/// In-memory log exporter used by the ADK Web UI to correlate logs with spans.
class WebUiLogExporter {
  /// Creates a [WebUiLogExporter].
  WebUiLogExporter();

  final Map<String, List<WebUiLog>> _logsBySpanId = <String, List<WebUiLog>>{};

  /// Exports a [log] and indexes it by `log.spanId`.
  void export(WebUiLog log) {
    final String key = log.spanId ?? '';
    _logsBySpanId.putIfAbsent(key, () => <WebUiLog>[]).add(log);
  }

  /// Returns all logs recorded for [spanId].
  List<WebUiLog> getLogsForSpan(String spanId) {
    return List<WebUiLog>.unmodifiable(
      _logsBySpanId[spanId] ?? const <WebUiLog>[],
    );
  }

  /// Clears all stored logs.
  void clear() {
    _logsBySpanId.clear();
  }
}
