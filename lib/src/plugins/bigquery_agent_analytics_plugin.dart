/// BigQuery analytics plugin and event-delivery support types.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../agents/base_agent.dart';
import '../agents/callback_context.dart';
import '../agents/invocation_context.dart';
import '../agents/llm/task/finish_task_tool.dart';
import '../agents/llm_agent.dart';
import '../agents/remote_a2a_agent.dart';
import '../events/event.dart';
import '../events/node_path_builder.dart';
import '../models/cache_metadata.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../platform/uuid.dart';
import '../tools/agent_tool.dart';
import '../tools/base_tool.dart';
import '../tools/function_tool.dart';
import '../tools/mcp_tool/mcp_tool.dart';
import '../tools/tool_context.dart';
import '../tools/transfer_to_agent_tool.dart';
import '../types/content.dart';
import '../utils/function_call_names.dart';
import '../version.dart';
import '_bigquery_agent_analytics_eval_sql.dart';
import 'base_plugin.dart';
import 'callback_helpers.dart';

export '_bigquery_agent_analytics_eval_sql.dart'
    show
        buildEvalSessionQuerySql,
        buildEvalSessionViewSql,
        buildEvalTurnQuerySql,
        buildEvalTurnViewSql,
        evalTableIdUnquotableRe,
        projectablePayloadColumns,
        validatePayloadColumnDenylist;
export 'callback_helpers.dart'
    show ToolResultClassification, ToolResultClassifier;


part 'bigquery_agent_analytics_models.dart';
part 'bigquery_agent_analytics_formatters.dart';
const String _schemaVersion = '1';
const String _schemaVersionLabelKey = 'adk_schema_version';
const String _cycleDetectedMessage = '[cycle detected]';

const Map<String, String> _hitlEventMap = <String, String>{
  requestEucFunctionCallName: 'HITL_CREDENTIAL_REQUEST',
  requestConfirmationFunctionCallName: 'HITL_CONFIRMATION_REQUEST',
  requestInputFunctionCallName: 'HITL_INPUT_REQUEST',
};

const List<String> _analyticsViewEventTypes = <String>[
  'INVOCATION_STARTING',
  'INVOCATION_COMPLETED',
  'INVOCATION_ERROR',
  'AGENT_STARTING',
  'AGENT_COMPLETED',
  'LLM_REQUEST',
  'LLM_RESPONSE',
  'LLM_ERROR',
  'TOOL_STARTING',
  'TOOL_COMPLETED',
  'TOOL_ERROR',
  'STATE_DELTA',
  'AGENT_RESPONSE',
  'USER_MESSAGE_RECEIVED',
  'HITL_CREDENTIAL_REQUEST',
  'HITL_CREDENTIAL_REQUEST_COMPLETED',
  'HITL_CONFIRMATION_REQUEST',
  'HITL_CONFIRMATION_REQUEST_COMPLETED',
  'HITL_INPUT_REQUEST',
  'HITL_INPUT_REQUEST_COMPLETED',
  'NODE_OUTPUT',
  'NODE_ERROR',
  'WORKFLOW_NODE_FIRST_OBSERVED',
  'WORKFLOW_NODE_OBSERVATION_SUMMARY',
];

const int _maxInFlightWorkflowSegments = 4096;
const int _maxObservedNodePathsPerSegment = 4096;
const int _reservedTerminalQueueSlots = 2;
const Set<String> _terminalQueueEventTypes = <String>{
  'INVOCATION_COMPLETED',
  'INVOCATION_ERROR',
};

/// Plugin that records ADK runtime events to BigQuery-compatible rows.
class BigQueryAgentAnalyticsPlugin extends BasePlugin {
  /// Creates a BigQuery analytics plugin.
  BigQueryAgentAnalyticsPlugin({
    required this.projectId,
    required this.datasetId,
    String? tableId,
    BigQueryLoggerConfig? config,
    this.location = 'US',
    this.configOverrides,
    BigQueryEventSink? sink,
    bool useBigQueryInsertAllSink = true,
    String? accessToken,
    String? apiKey,
    http.Client? httpClient,
    BigQueryAccessTokenProvider? accessTokenProvider,
    BigQueryAnalyticsViewExecutor? analyticsViewExecutor,
  }) : config = config ?? BigQueryLoggerConfig(),
       _sink =
           sink ??
           (useBigQueryInsertAllSink
               ? BigQueryInsertAllEventSink(
                   projectId: projectId,
                   datasetId: datasetId,
                   tableId: tableId ?? (config?.tableId ?? 'agent_events'),
                   apiKey: apiKey,
                   maxBatchSize: (config?.batchSize ?? 1) <= 0
                       ? 1
                       : (config?.batchSize ?? 1),
                   httpClient: httpClient,
                   accessTokenProvider: accessToken == null
                       ? accessTokenProvider
                       : () async => accessToken,
                 )
               : InMemoryBigQueryEventSink()),
       _analyticsViewExecutor = analyticsViewExecutor,
       super(name: 'bigquery_agent_analytics') {
    _applyConfigOverrides(configOverrides);
    this.tableId = tableId ?? this.config.tableId;
    _deniedColumns = validatePayloadColumnDenylist(
      this.config.payloadColumnDenylist,
    );
    for (final (String fieldName, String value) in <(String, String)>[
      ('project_id', projectId),
      ('dataset_id', datasetId),
      ('table_id', this.tableId),
      ('view_prefix', this.config.viewPrefix),
    ]) {
      if (value.isEmpty || evalTableIdUnquotableRe.hasMatch(value)) {
        throw ArgumentError.value(
          value,
          fieldName,
          '$fieldName must be a non-empty string without a backtick, '
          "backslash, control or line-break character; got '$value'.",
        );
      }
    }
    if (this.config.maxObservationSummariesPerSegment < 1) {
      throw ArgumentError.value(
        this.config.maxObservationSummariesPerSegment,
        'maxObservationSummariesPerSegment',
        'max_observation_summaries_per_segment must be an int >= 1.',
      );
    }
    if (this.config.createEvalViews) {
      _validateEvalViewConfig(prefix: 'Cannot enable createEvalViews=true');
    }
    _gcsUploadProvider = _resolveGcsUploadProvider(
      accessToken: accessToken,
      accessTokenProvider: accessTokenProvider,
      httpClient: httpClient,
    );
  }

  /// The Google Cloud project identifier.
  final String projectId;

  /// The destination BigQuery dataset identifier.
  final String datasetId;

  /// The target BigQuery region.
  final String location;

  /// Runtime logging configuration.
  final BigQueryLoggerConfig config;

  /// Optional config map used to override [config] fields.
  final Map<String, Object?>? configOverrides;

  /// The destination BigQuery table identifier.
  late final String tableId;

  late Set<String> _deniedColumns;
  bool _offloadDisabledWarned = false;
  bool _started = false;
  bool _isShuttingDown = false;
  bool _viewsCreated = false;
  int _queueFullCount = 0;
  int _writeFailedCount = 0;
  int _shutdownDroppedCount = 0;
  int _formatFailedCount = 0;
  int _gcsUploadFailedCount = 0;
  int _workflowObservationCapacityCount = 0;
  final Map<String, _WorkflowObservationSegment> _workflowSegments =
      <String, _WorkflowObservationSegment>{};

  /// Optional provider returning the current pending queue size for backpressure
  /// and terminal slot reservation checks.
  int Function()? queueSizeProvider;
  DateTime? _gcsCooldownUntil;
  final BigQueryEventSink _sink;
  final BigQueryAnalyticsViewExecutor? _analyticsViewExecutor;
  BigQueryGcsUploadProvider? _gcsUploadProvider;
  http.Client? _ownedGcsHttpClient;

  /// Number of queue slots reserved exclusively for `INVOCATION_COMPLETED` and
  /// `INVOCATION_ERROR` rows when `config.queueMaxSize > 1`.
  int get reservedTerminalQueueSlots {
    final int maxSize = config.queueMaxSize;
    if (maxSize <= 1) {
      return 0;
    }
    return min(max(_reservedTerminalQueueSlots, maxSize ~/ 100), maxSize - 1);
  }

  /// Current snapshot of dropped or degraded analytics event counts.
  BigQueryDropStats get dropStats => BigQueryDropStats(
    queueFull: _queueFullCount,
    writeFailed: _writeFailedCount,
    shutdownDropped: _shutdownDroppedCount,
    formatFailed: _formatFailedCount,
    gcsUploadFailed: _gcsUploadFailedCount,
    workflowObservationCapacity: _workflowObservationCapacityCount,
  );

  /// Returns per-reason drop counts as a map (matching Python `get_drop_stats()`).
  Map<String, int> getDropStats() => dropStats.toJson();

  /// The schema version stored in each event row.
  String get schemaVersion => _schemaVersion;

  /// The row field key used for schema version labels.
  String get schemaVersionLabelKey => _schemaVersionLabelKey;

  /// The configured event sink instance.
  BigQueryEventSink get sink => _sink;

  /// Captured rows when [sink] is [InMemoryBigQueryEventSink].
  List<Map<String, Object?>> get loggedRows {
    final BigQueryEventSink targetSink = _sink;
    if (targetSink is InMemoryBigQueryEventSink) {
      return targetSink.rows;
    }
    return const <Map<String, Object?>>[];
  }

  Future<void> _ensureStarted() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      if (config.createViews && !_viewsCreated) {
        await createAnalyticsViews();
      }
      if (config.onSchemaReady != null) {
        try {
          config.onSchemaReady!();
        } catch (cbError) {
          stderr.writeln('Error in onSchemaReady callback: $cbError');
        }
      }
    } catch (error, stackTrace) {
      if (config.onSchemaError != null) {
        try {
          config.onSchemaError!(error, stackTrace);
        } catch (cbError) {
          stderr.writeln('Error in onSchemaError callback: $cbError');
        }
      }
      rethrow;
    }
  }

  bool _contentPartsPersisted() {
    return config.logMultiModalContent &&
        !_deniedColumns.contains('content_parts');
  }

  void _maybeWarnOffloadDisabled() {
    if (_offloadDisabledWarned) {
      return;
    }
    final String? bucketName = config.gcsBucketName?.trim();
    if (bucketName == null || bucketName.isEmpty) {
      return;
    }
    final String reason = _deniedColumns.contains('content_parts')
        ? "payload_column_denylist drops 'content_parts', which holds the offloaded object reference"
        : "log_multi_modal_content is False, so 'content_parts' (which holds the offloaded object reference) is not persisted";
    stderr.writeln(
      'GCS offload disabled: $reason; large text is kept inline (truncated) '
      "in 'content' and binary parts are not stored instead of being uploaded "
      'to $bucketName.',
    );
    _offloadDisabledWarned = true;
  }

  BigQueryGcsUploadProvider? _resolveGcsUploadProvider({
    required String? accessToken,
    required BigQueryAccessTokenProvider? accessTokenProvider,
    required http.Client? httpClient,
  }) {
    final String? bucketName = config.gcsBucketName?.trim();
    if (bucketName == null || bucketName.isEmpty) {
      return null;
    }
    if (!_contentPartsPersisted()) {
      _maybeWarnOffloadDisabled();
      return null;
    }
    final BigQueryGcsUploadProvider? configured = config.gcsUploadProvider;
    final BigQueryGcsUploadProvider rawProvider =
        configured ??
        _GcsJsonUploadProvider(
          bucketName: bucketName,
          httpClient:
              httpClient ?? (_ownedGcsHttpClient = http.Client()),
          accessTokenProvider: accessToken == null
              ? accessTokenProvider ?? _defaultBigQueryAccessTokenProvider
              : () async => accessToken,
        ).uploadContent;
    return ({
      required List<int> data,
      required String contentType,
      required String path,
    }) async {
      final DateTime now = DateTime.now();
      if (_gcsCooldownUntil != null && now.isBefore(_gcsCooldownUntil!)) {
        _gcsUploadFailedCount += 1;
        throw TimeoutException(
          'GCS upload paused during cooldown window',
          config.gcsUploadTimeout,
        );
      }
      final Duration timeout = config.gcsUploadTimeout;
      try {
        if (timeout > Duration.zero) {
          return await rawProvider(
            data: data,
            contentType: contentType,
            path: path,
          ).timeout(timeout);
        }
        return await rawProvider(
          data: data,
          contentType: contentType,
          path: path,
        );
      } on TimeoutException {
        _gcsUploadFailedCount += 1;
        if (timeout > Duration.zero) {
          _gcsCooldownUntil = DateTime.now().add(timeout);
        }
        rethrow;
      } catch (_) {
        _gcsUploadFailedCount += 1;
        rethrow;
      }
    };
  }

  /// Flushes and closes the sink.
  ///
  /// The optional [timeout] parameter is accepted for parity with Python ADK.
  Future<void> shutdown({double? timeout}) async {
    if (_isShuttingDown) {
      return;
    }
    _isShuttingDown = true;
    await _sink.flush();
    await _sink.close();
    _ownedGcsHttpClient?.close();
    _ownedGcsHttpClient = null;
    _workflowSegments.clear();
    _isShuttingDown = false;
    _started = false;
  }

  /// Flushes buffered events to the sink.
  Future<void> flush() async {
    await _sink.flush();
  }

  /// Creates or refreshes analytics views for the configured event types.
  Future<void> createAnalyticsViews() async {
    final BigQueryAnalyticsViewExecutor? executor = _analyticsViewExecutor;
    if (executor == null) {
      return;
    }
    try {
      await executor(_buildAnalyticsViewStatements());
    } on Object catch (error) {
      if (_isConcurrentViewConflict(error)) {
        stderr.writeln(
          'BigQuery analytics views were updated concurrently; skipping duplicate refresh.',
        );
        _viewsCreated = true;
        return;
      }
      rethrow;
    }
    _viewsCreated = true;
  }

  static const Set<String> _evalViewFullRequiredEvents = <String>{
    'USER_MESSAGE_RECEIVED',
    'AGENT_STARTING',
    'LLM_REQUEST',
    'TOOL_STARTING',
    'TOOL_COMPLETED',
    'TOOL_ERROR',
    'TOOL_PAUSED',
    'AGENT_TRANSFER',
    'AGENT_RESPONSE',
    'INVOCATION_COMPLETED',
    'HITL_CREDENTIAL_REQUEST',
    'HITL_CREDENTIAL_REQUEST_COMPLETED',
    'HITL_CONFIRMATION_REQUEST',
    'HITL_CONFIRMATION_REQUEST_COMPLETED',
    'HITL_INPUT_REQUEST',
    'HITL_INPUT_REQUEST_COMPLETED',
  };

  static const Set<String> _evalViewConversationOnlyRequiredEvents = <String>{
    'USER_MESSAGE_RECEIVED',
    'AGENT_RESPONSE',
    'INVOCATION_COMPLETED',
  };

  static const Map<String, Set<String>> _evalViewEventsByMode =
      <String, Set<String>>{
        'full': _evalViewFullRequiredEvents,
        'conversation_only': _evalViewConversationOnlyRequiredEvents,
      };

  void _validateEvalViewConfig({String prefix = 'Cannot create eval views'}) {
    if (_deniedColumns.contains('content')) {
      throw ArgumentError(
        "$prefix when 'content' is in payloadColumnDenylist.",
      );
    }
    final Set<String>? requiredEvents =
        _evalViewEventsByMode[config.evalViewMode];
    if (requiredEvents == null) {
      throw ArgumentError(
        '$prefix with unknown evalViewMode=${config.evalViewMode}; '
        'expected one of [conversation_only, full].',
      );
    }
    final List<String> denied = (config.eventDenylist ?? const <String>[])
        .where(requiredEvents.contains)
        .toList()
      ..sort();
    if (denied.isNotEmpty) {
      throw ArgumentError(
        '$prefix when required events are in eventDenylist: $denied.',
      );
    }
    final List<String>? allowlist = config.eventAllowlist;
    if (allowlist != null && allowlist.isNotEmpty) {
      final Set<String> allowed = allowlist.toSet();
      final List<String> missing = requiredEvents
          .where((String event) => !allowed.contains(event))
          .toList()
        ..sort();
      if (missing.isNotEmpty) {
        final String hint = config.evalViewMode == 'full'
            ? " Set evalViewMode='conversation_only' if tool, model-request, "
                  'agent-handoff, or HITL events are intentionally omitted.'
            : '';
        throw ArgumentError(
          '$prefix unless eventAllowlist includes all required events; '
          'missing: $missing.$hint',
        );
      }
    }
  }

  /// Validates [config] and creates or refreshes the evaluation views.
  Future<void> createEvalViews() async {
    _validateEvalViewConfig();
    final String fullTableId = '$projectId.$datasetId.$tableId';
    final List<String> statements = <String>[
      buildEvalSessionViewSql(
        fullTableId,
        viewPrefix: config.viewPrefix,
        deniedColumns: _deniedColumns,
      ),
      buildEvalTurnViewSql(
        fullTableId,
        viewPrefix: config.viewPrefix,
        deniedColumns: _deniedColumns,
      ),
    ];
    final BigQueryAnalyticsViewExecutor? executor = _analyticsViewExecutor;
    if (executor == null) {
      return;
    }
    await executor(statements);
  }

  @override
  Future<void> close() async {
    await shutdown();
  }

  /// Logs incoming user messages before invocation processing.
  @override
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    return _safeCallback<Content?>('onUserMessageCallback', () async {
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );
      await _logEvent(
        'USER_MESSAGE_RECEIVED',
        callbackContext,
        rawContent: userMessage,
      );

      for (final Part part in userMessage.parts) {
        final FunctionResponse? response = part.functionResponse;
        if (response == null) {
          continue;
        }
        final String? hitlEvent = _hitlEventMap[response.name];
        if (hitlEvent == null) {
          continue;
        }
        final _TruncateResult truncated = _recursiveSmartTruncate(
          response.response,
          config.maxContentLength,
        );
        await _logEvent(
          '${hitlEvent}_COMPLETED',
          callbackContext,
          rawContent: <String, Object?>{
            'tool': response.name,
            'result': truncated.value,
          },
          isTruncated: truncated.isTruncated,
        );
      }

      return null;
    });
  }

  /// Logs runtime events emitted during invocation.
  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    return _safeCallback<Event?>('onEventCallback', () async {
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );

      if (_workflowObservationsEnabled) {
        try {
          final (_WorkflowObservationSegment, bool, double?)?
          workflowObservation = _recordWorkflowNodeObservation(
            event,
            invocationContext,
          );
          if (workflowObservation != null) {
            final (
              _WorkflowObservationSegment segment,
              bool isFirst,
              double? eventTs,
            ) = workflowObservation;
            if (isFirst) {
              await _logEvent(
                'WORKFLOW_NODE_FIRST_OBSERVED',
                callbackContext,
                eventData: EventData(
                  sourceEvent: event,
                  adkExtras: <String, Object?>{
                    'workflow_segment_id': segment.segmentId,
                    'boundary_basis': 'event_observation',
                    'source_event_timestamp': eventTs,
                  },
                ),
              );
            }
          }
        } catch (error) {
          stderr.writeln(
            'Could not record workflow-node observation; continuing. $error',
          );
        }
      }

      if (event.actions.stateDelta.isNotEmpty) {
        await _logEvent(
          'STATE_DELTA',
          callbackContext,
          eventData: EventData(
            sourceEvent: event,
            extraAttributes: <String, Object?>{
              'state_delta': Map<String, Object?>.from(
                event.actions.stateDelta,
              ),
            },
          ),
        );
      }

      final NodeInfo nodeInfo = event.nodeInfo;
      if (nodeInfo.path.isNotEmpty && event.partial != true) {
        if (event.output != null && nodeInfo.messageAsOutput != true) {
          final _TruncateResult outputTruncated = _recursiveSmartTruncate(
            event.output,
            config.maxContentLength,
          );
          await _logEvent(
            'NODE_OUTPUT',
            callbackContext,
            rawContent: <String, Object?>{'output': outputTruncated.value},
            isTruncated: outputTruncated.isTruncated,
            eventData: EventData(
              sourceEvent: event,
              extraAttributes: <String, Object?>{'node_path': nodeInfo.path},
            ),
          );
        }
        if ((event.errorCode?.isNotEmpty ?? false) &&
            isDurableNodeError(event)) {
          await _logEvent(
            'NODE_ERROR',
            callbackContext,
            rawContent: <String, Object?>{'error_code': event.errorCode},
            eventData: EventData(
              sourceEvent: event,
              status: 'ERROR',
              errorMessage: event.errorMessage ?? event.errorCode,
              extraAttributes: <String, Object?>{
                'node_path': nodeInfo.path,
                'error_code': event.errorCode,
              },
            ),
          );
        }
      }

      final Content? content = event.content;
      if (content == null) {
        return null;
      }

      for (final Part part in content.parts) {
        final FunctionCall? functionCall = part.functionCall;
        if (functionCall != null) {
          final String? hitlEvent = _hitlEventMap[functionCall.name];
          if (hitlEvent != null) {
            final _TruncateResult args = _recursiveSmartTruncate(
              functionCall.args,
              config.maxContentLength,
            );
            await _logEvent(
              hitlEvent,
              callbackContext,
              rawContent: <String, Object?>{
                'tool': functionCall.name,
                'args': args.value,
              },
              isTruncated: args.isTruncated,
            );
          }
        }

        final FunctionResponse? functionResponse = part.functionResponse;
        if (functionResponse != null) {
          if (functionResponse.name == finishTaskToolName &&
              isFinishTaskTerminalFr(event)) {
            _TraceManager.popTaskAgentSpan(callbackContext, event.author);
          }
          final String? hitlEvent = _hitlEventMap[functionResponse.name];
          if (hitlEvent != null) {
            final _TruncateResult result = _recursiveSmartTruncate(
              functionResponse.response,
              config.maxContentLength,
            );
            await _logEvent(
              '${hitlEvent}_COMPLETED',
              callbackContext,
              rawContent: <String, Object?>{
                'tool': functionResponse.name,
                'result': result.value,
              },
              isTruncated: result.isTruncated,
            );
          }
        }
      }

      final bool isAgentResponse =
          event.isFinalResponse() &&
          event.partial != true &&
          event.getFunctionCalls().isEmpty &&
          event.getFunctionResponses().isEmpty &&
          (event.longRunningToolIds == null ||
              event.longRunningToolIds!.isEmpty);
      if (isAgentResponse) {
        final List<Part> visibleTextParts = content.parts
            .where(
              (Part part) =>
                  part.text != null && part.text!.isNotEmpty && !part.thought,
            )
            .map((Part part) => part.copyWith())
            .toList(growable: false);
        if (visibleTextParts.isNotEmpty) {
          final _FormatResult formatted = _formatContent(
            Content(role: content.role, parts: visibleTextParts),
            maxLen: config.maxContentLength,
          );
          await _logEvent(
            'AGENT_RESPONSE',
            callbackContext,
            rawContent: <String, Object?>{'response': formatted.text},
            isTruncated: formatted.isTruncated,
            eventData: EventData(
              extraAttributes: <String, Object?>{
                'source_event_id': event.id,
                'source_event_author': event.author,
                'source_event_branch': event.branch,
              },
            ),
          );
        }
      }

      return null;
    });
  }

  /// Logs invocation start and initializes sink startup state.
  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    return _safeCallback<Content?>('beforeRunCallback', () async {
      await _ensureStarted();
      if (_workflowObservationsEnabled) {
        _openWorkflowSegment(invocationContext.invocationId);
      }
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );
      await _logEvent('INVOCATION_STARTING', callbackContext);
      return null;
    });
  }

  /// Logs invocation completion and clears trace state.
  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    await _safeCallback<void>('afterRunCallback', () async {
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );
      try {
        await _drainWorkflowNodeObservations(
          callbackContext,
          drainCallback: 'after_run',
        );
        await _logEvent('INVOCATION_COMPLETED', callbackContext);
      } finally {
        _workflowSegments.remove(invocationContext.invocationId);
        await flush();
        _TraceManager.clear(callbackContext);
      }
    });
  }

  /// Logs runner failure, drains workflow node observations, and clears trace state.
  @override
  Future<void> onRunErrorCallback({
    required InvocationContext invocationContext,
    required Object error,
  }) async {
    await _safeCallback<void>('onRunErrorCallback', () async {
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );
      try {
        await _drainWorkflowNodeObservations(
          callbackContext,
          drainCallback: 'on_run_error',
        );
        await _logEvent(
          'INVOCATION_ERROR',
          callbackContext,
          rawContent: <String, Object?>{'error_traceback': '$error'},
          eventData: EventData(
            status: 'ERROR',
            errorMessage: '$error',
          ),
        );
      } finally {
        _workflowSegments.remove(invocationContext.invocationId);
        await flush();
        _TraceManager.clear(callbackContext);
      }
    });
  }

  /// Logs agent start and pushes an agent span.
  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return _safeCallback<Content?>('beforeAgentCallback', () async {
      _TraceManager.initTrace(callbackContext);
      _TraceManager.pushSpan(callbackContext, 'agent', agent: agent);
      await _logEvent(
        'AGENT_STARTING',
        callbackContext,
        rawContent: _agentInstruction(agent),
      );
      return null;
    });
  }

  /// Logs agent completion and pops the agent span.
  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return _safeCallback<Content?>('afterAgentCallback', () async {
      final _PopResult popResult = _TraceManager.popSpan(callbackContext);
      await _logEvent(
        'AGENT_COMPLETED',
        callbackContext,
        eventData: EventData(
          latencyMs: popResult.durationMs,
          spanIdOverride: popResult.spanId,
          parentSpanIdOverride: popResult.parentSpanId,
        ),
      );
      return null;
    });
  }

  /// Logs model request metadata and pushes an LLM span.
  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    return _safeCallback<LlmResponse?>('beforeModelCallback', () async {
      final Map<String, Object?> attributes = <String, Object?>{};

      final GenerateContentConfig llmConfig = llmRequest.config;
      final Map<String, Object?> configData = <String, Object?>{};
      _putIfNotNull(configData, 'temperature', llmConfig.temperature);
      _putIfNotNull(configData, 'top_p', llmConfig.topP);
      _putIfNotNull(configData, 'max_output_tokens', llmConfig.maxOutputTokens);
      _putIfNotNull(configData, 'candidate_count', llmConfig.candidateCount);
      _putIfNotNull(
        configData,
        'response_mime_type',
        llmConfig.responseMimeType,
      );
      _putIfNotNull(configData, 'response_schema', llmConfig.responseSchema);
      _putIfNotNull(configData, 'seed', llmConfig.seed);
      _putIfNotNull(
        configData,
        'response_logprobs',
        llmConfig.responseLogprobs,
      );
      _putIfNotNull(configData, 'logprobs', llmConfig.logprobs);
      if (configData.isNotEmpty) {
        attributes['llm_config'] = configData;
      }

      if (llmConfig.labels.isNotEmpty) {
        attributes['labels'] = Map<String, String>.from(llmConfig.labels);
      }
      bool toolsTruncated = false;
      if (llmRequest.toolsDict.isNotEmpty) {
        // Route tool declarations through the shared safety pipeline so
        // unbounded descriptions / parameter schemas are size-capped and
        // sensitive keys are redacted, consistent with every other attribute.
        final _TruncateResult truncatedTools = _recursiveSmartTruncate(
          _extractToolDeclarations(llmRequest.toolsDict),
          config.maxContentLength,
        );
        attributes['tools'] = truncatedTools.value;
        toolsTruncated = truncatedTools.isTruncated;
      }

      _TraceManager.pushSpan(callbackContext, 'llm_request');
      await _logEvent(
        'LLM_REQUEST',
        callbackContext,
        rawContent: llmRequest,
        isTruncated: toolsTruncated,
        eventData: EventData(
          model: llmRequest.model,
          extraAttributes: attributes,
        ),
      );
      return null;
    });
  }

  /// Logs model responses and captures latency metrics.
  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    return _safeCallback<LlmResponse?>('afterModelCallback', () async {
      final Map<String, Object?> content = <String, Object?>{};
      bool isTruncated = false;

      final Content? responseContent = llmResponse.content;
      if (responseContent != null) {
        final _FormatResult formatted = _formatContent(
          responseContent,
          maxLen: config.maxContentLength,
        );
        if (formatted.text.isNotEmpty) {
          content['response'] = formatted.text;
        }
        isTruncated = isTruncated || formatted.isTruncated;
      }

      if (llmResponse.usageMetadata != null) {
        content['usage'] = _recursiveSmartTruncate(
          llmResponse.usageMetadata,
          config.maxContentLength,
        ).value;
      }
      if (llmResponse.cacheMetadata != null) {
        content['cache'] = _recursiveSmartTruncate(
          llmResponse.cacheMetadata,
          config.maxContentLength,
        ).value;
      }

      String? spanId = _TraceManager.getCurrentSpanId(callbackContext);
      String? parentSpanId = _TraceManager.getCurrentSpanAndParent(
        callbackContext,
      ).parentSpanId;

      bool popped = false;
      int? durationMs;
      int? tfftMs;

      if (llmResponse.partial == true) {
        if (spanId != null) {
          _TraceManager.recordFirstToken(callbackContext, spanId);
          durationMs = _TraceManager.elapsedMs(callbackContext, spanId);
          tfftMs = _TraceManager.timeToFirstTokenMs(callbackContext, spanId);
        }
      } else {
        if (spanId != null) {
          _TraceManager.recordFirstToken(callbackContext, spanId);
          tfftMs = _TraceManager.timeToFirstTokenMs(callbackContext, spanId);
        }
        final _PopResult popResult = _TraceManager.popSpan(callbackContext);
        popped = true;
        durationMs = popResult.durationMs;
        spanId = popResult.spanId ?? spanId;
        parentSpanId = popResult.parentSpanId ?? parentSpanId;
      }

      await _logEvent(
        'LLM_RESPONSE',
        callbackContext,
        rawContent: content.isEmpty ? null : content,
        isTruncated: isTruncated,
        eventData: EventData(
          latencyMs: durationMs,
          timeToFirstTokenMs: tfftMs,
          modelVersion: llmResponse.modelVersion,
          usageMetadata: llmResponse.usageMetadata,
          cacheMetadata: llmResponse.cacheMetadata,
          spanIdOverride: popped ? spanId : null,
          parentSpanIdOverride: popped ? parentSpanId : null,
        ),
      );
      return null;
    });
  }

  /// Logs model invocation errors.
  @override
  Future<LlmResponse?> onModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    return _safeCallback<LlmResponse?>('onModelErrorCallback', () async {
      final _PopResult popResult = _TraceManager.popSpan(callbackContext);
      await _logEvent(
        'LLM_ERROR',
        callbackContext,
        eventData: EventData(
          errorMessage: '$error',
          latencyMs: popResult.durationMs,
          spanIdOverride: popResult.spanId,
          parentSpanIdOverride: popResult.parentSpanId,
        ),
      );
      return null;
    });
  }

  /// Logs tool start events and pushes a tool span.
  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    return _safeCallback<Map<String, dynamic>?>('beforeToolCallback', () async {
      final _TruncateResult args = _recursiveSmartTruncate(
        toolArgs,
        config.maxContentLength,
      );
      _TraceManager.pushSpan(toolContext, 'tool');
      await _logEvent(
        'TOOL_STARTING',
        toolContext,
        rawContent: <String, Object?>{
          'tool': tool.name,
          'args': args.value,
          'tool_origin': _getToolOrigin(tool),
        },
        isTruncated: args.isTruncated,
      );
      return null;
    });
  }

  /// Logs successful tool completion (or result-reported failure) and span timing.
  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return _safeCallback<Map<String, dynamic>?>('afterToolCallback', () async {
      if (popToolErrorRecorded(this, toolContext)) {
        return null;
      }

      final String toolOrigin = _getToolOrigin(tool);
      final _PopResult popResult = _TraceManager.popSpan(toolContext);
      final String? errorMessage = classifyToolResultError(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
        result: result,
        toolResultClassifier: config.toolResultClassifier,
        onWarning: (String warning) => stderr.writeln(warning),
      );
      if (errorMessage != null) {
        final _TruncateResult argsTruncated = _recursiveSmartTruncate(
          toolArgs,
          config.maxContentLength,
        );
        await _logEvent(
          'TOOL_ERROR',
          toolContext,
          rawContent: <String, Object?>{
            'tool': tool.name,
            'args': argsTruncated.value,
            'tool_origin': toolOrigin,
          },
          isTruncated: argsTruncated.isTruncated,
          eventData: EventData(
            status: 'ERROR',
            errorMessage: errorMessage,
            latencyMs: popResult.durationMs,
            spanIdOverride: popResult.spanId,
            parentSpanIdOverride: popResult.parentSpanId,
          ),
        );
        return null;
      }

      final _TruncateResult truncatedResult = _recursiveSmartTruncate(
        result,
        config.maxContentLength,
      );

      await _logEvent(
        'TOOL_COMPLETED',
        toolContext,
        rawContent: <String, Object?>{
          'tool': tool.name,
          'result': truncatedResult.value,
          'tool_origin': toolOrigin,
        },
        isTruncated: truncatedResult.isTruncated,
        eventData: EventData(
          latencyMs: popResult.durationMs,
          spanIdOverride: popResult.spanId,
          parentSpanIdOverride: popResult.parentSpanId,
        ),
      );

      if (config.finalResponseToolNames.contains(tool.name)) {
        final _TruncateResult argsTruncated = _recursiveSmartTruncate(
          toolArgs,
          config.maxContentLength,
        );
        await _logEvent(
          'AGENT_RESPONSE',
          toolContext,
          rawContent: <String, Object?>{'response': argsTruncated.value},
          isTruncated: argsTruncated.isTruncated,
          eventData: EventData(
            extraAttributes: <String, Object?>{'source_tool': tool.name},
          ),
        );
      }
      return null;
    });
  }

  /// Logs tool execution failures and span timing.
  @override
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    return _safeCallback<Map<String, dynamic>?>(
      'onToolErrorCallback',
      () async {
        final _TruncateResult args = _recursiveSmartTruncate(
          toolArgs,
          config.maxContentLength,
        );
        final _PopResult popResult = _TraceManager.popSpan(toolContext);
        String errorMessage;
        try {
          final String rendered = '$error';
          errorMessage = rendered.isNotEmpty
              ? rendered
              : error.runtimeType.toString();
        } catch (_) {
          errorMessage = error.runtimeType.toString();
        }
        markToolErrorRecorded(this, toolContext);

        await _logEvent(
          'TOOL_ERROR',
          toolContext,
          rawContent: <String, Object?>{
            'tool': tool.name,
            'args': args.value,
            'tool_origin': _getToolOrigin(tool),
          },
          isTruncated: args.isTruncated,
          eventData: EventData(
            status: 'ERROR',
            errorMessage: errorMessage,
            latencyMs: popResult.durationMs,
            spanIdOverride: popResult.spanId,
            parentSpanIdOverride: popResult.parentSpanId,
          ),
        );
        return null;
      },
    );
  }

  Future<T?> _safeCallback<T>(
    String callbackName,
    Future<T?> Function() run,
  ) async {
    try {
      return await run();
    } catch (error) {
      stderr.writeln(
        'BigQuery analytics plugin error in $callbackName; skipping. $error',
      );
      return null;
    }
  }

  bool get _workflowObservationsEnabled => config.enabled && !_isShuttingDown;

  bool _eventTypeFiltered(String eventType) {
    if (config.eventDenylist?.contains(eventType) == true) {
      return true;
    }
    final List<String>? allowlist = config.eventAllowlist;
    return allowlist != null && !allowlist.contains(eventType);
  }

  void _openWorkflowSegment(String invocationId) {
    _workflowSegments.remove(invocationId);
    while (_workflowSegments.length >= _maxInFlightWorkflowSegments) {
      _workflowSegments.remove(_workflowSegments.keys.first);
    }
    _workflowSegments[invocationId] = _WorkflowObservationSegment(
      segmentId: newUuid(),
    );
  }

  (_WorkflowObservationSegment, bool, double?)? _recordWorkflowNodeObservation(
    Event event,
    InvocationContext invocationContext,
  ) {
    final NodeInfo nodeInfo = event.nodeInfo;
    final String nodePath = nodeInfo.path;
    if (nodePath.isEmpty) {
      return null;
    }

    final String eventId = event.id;
    final double? eventTs = event.timestamp.isFinite ? event.timestamp : null;
    final int summaryCap = config.maxObservationSummariesPerSegment;
    final int maxTrackedPaths = max(
      summaryCap,
      _maxObservedNodePathsPerSegment,
    );

    final _WorkflowObservationSegment? segment =
        _workflowSegments[invocationContext.invocationId];
    if (segment == null) {
      return null;
    }

    _WorkflowNodeObservation? observation = segment.nodes[nodePath];
    bool isFirst = false;
    if (observation == null) {
      if (segment.nodes.length >= summaryCap) {
        if (event.longRunningToolIds != null &&
            event.longRunningToolIds!.isNotEmpty) {
          for (final String ancestorPath in _strictAncestorNodePaths(nodePath)) {
            final _WorkflowNodeObservation? ancestor =
                segment.nodes[ancestorPath];
            if (ancestor != null) {
              ancestor.descendantInterruptObserved = true;
            }
          }
        }
        if (segment.overflowNodePaths.contains(nodePath)) {
          return (segment, false, eventTs);
        }
        if (segment.nodes.length + segment.overflowNodePaths.length <
            maxTrackedPaths) {
          segment.overflowNodePaths.add(nodePath);
          return (segment, true, eventTs);
        }
        segment.untrackedPathEvents += 1;
        return (segment, false, eventTs);
      }
      isFirst = true;
      final String? runId = NodePathBuilder.fromString(nodePath).runId;
      observation = _WorkflowNodeObservation(
        nodePath: nodePath,
        nodeRunId: (runId == null || runId.isEmpty) ? null : runId,
        nodeParentRunId: nodeInfo.parentRunId,
        firstSourceEventId: eventId,
        lastSourceEventId: eventId,
        firstSourceEventTimestamp: eventTs,
        lastSourceEventTimestamp: eventTs,
      );
      segment.nodes[nodePath] = observation;
    } else {
      observation.lastSourceEventId = eventId;
      if (eventTs != null) {
        observation.firstSourceEventTimestamp ??= eventTs;
        observation.lastSourceEventTimestamp = eventTs;
      }
      observation.observedEventCount += 1;
    }

    if (event.longRunningToolIds != null &&
        event.longRunningToolIds!.isNotEmpty) {
      observation.nodeInterruptObserved = true;
      final List<String> ancestorPaths = _strictAncestorNodePaths(nodePath);
      segment.interruptedAncestorPaths.addAll(ancestorPaths);
      for (final String ancestorPath in ancestorPaths) {
        final _WorkflowNodeObservation? ancestor = segment.nodes[ancestorPath];
        if (ancestor != null) {
          ancestor.descendantInterruptObserved = true;
        }
      }
    }

    if (segment.interruptedAncestorPaths.contains(nodePath)) {
      observation.descendantInterruptObserved = true;
    }

    if ((event.errorCode?.isNotEmpty ?? false) && isDurableNodeError(event)) {
      observation.nodeErrorObservedCount += 1;
    }

    return (segment, isFirst, eventTs);
  }

  Future<void> _drainWorkflowNodeObservations(
    CallbackContext callbackContext, {
    required String drainCallback,
  }) async {
    if (!_workflowObservationsEnabled) {
      return;
    }
    final _WorkflowObservationSegment? segment =
        _workflowSegments[callbackContext.invocationId];
    if (segment == null) {
      return;
    }
    final List<_WorkflowNodeObservation> observations = segment.nodes.values
        .toList(growable: false);
    final int overflowPathCount = segment.overflowNodePaths.length;
    final int untrackedEventCount = segment.untrackedPathEvents;
    if (_eventTypeFiltered('WORKFLOW_NODE_OBSERVATION_SUMMARY')) {
      return;
    }

    final int cap = config.maxObservationSummariesPerSegment;
    final List<_WorkflowNodeObservation> kept = observations.length > cap
        ? observations.sublist(0, cap)
        : observations;
    final int truncatedNodeCount =
        (observations.length - kept.length) + overflowPathCount;
    for (int index = 1; index <= kept.length; index += 1) {
      final _WorkflowNodeObservation observation = kept[index - 1];
      try {
        final double? spanMs =
            observation.firstSourceEventTimestamp != null &&
                observation.lastSourceEventTimestamp != null
            ? (observation.lastSourceEventTimestamp! -
                      observation.firstSourceEventTimestamp!) *
                  1000.0
            : null;
        final Map<String, Object?> adkExtras = <String, Object?>{
          'workflow_segment_id': segment.segmentId,
          'node': <String, Object?>{
            'path': observation.nodePath,
            'run_id': observation.nodeRunId,
            'parent_run_id': observation.nodeParentRunId,
          },
          'first_source_event_id': observation.firstSourceEventId,
          'last_source_event_id': observation.lastSourceEventId,
          'first_source_event_timestamp': observation.firstSourceEventTimestamp,
          'last_source_event_timestamp': observation.lastSourceEventTimestamp,
          'source_event_span_ms': spanMs,
          'observed_event_count': observation.observedEventCount,
          'node_interrupt_observed': observation.nodeInterruptObserved,
          'descendant_interrupt_observed':
              observation.descendantInterruptObserved,
          'node_error_observed_count': observation.nodeErrorObservedCount,
          'drain_callback': drainCallback,
          'boundary_basis': 'event_observation',
        };
        if (truncatedNodeCount > 0 && index == kept.length) {
          adkExtras['truncated_node_count'] = truncatedNodeCount;
        }
        if (untrackedEventCount > 0 && index == kept.length) {
          adkExtras['untracked_overflow_event_count'] = untrackedEventCount;
        }
        await _logEvent(
          'WORKFLOW_NODE_OBSERVATION_SUMMARY',
          callbackContext,
          eventData: EventData(adkExtras: adkExtras),
        );
      } catch (error) {
        stderr.writeln(
          'Could not emit workflow-node observation summary; continuing. $error',
        );
      }
    }

    if (truncatedNodeCount > 0) {
      _workflowObservationCapacityCount += truncatedNodeCount;
    }
  }

  Future<void> _logEvent(
    String eventType,
    CallbackContext callbackContext, {
    Object? rawContent,
    bool isTruncated = false,
    EventData? eventData,
  }) async {
    if (!config.enabled) {
      return;
    }
    if (_isShuttingDown) {
      _shutdownDroppedCount += 1;
      return;
    }
    if (_eventTypeFiltered(eventType)) {
      return;
    }

    if (!_started) {
      await _ensureStarted();
    }

    final int maxQueueSize = config.queueMaxSize;
    final int Function()? sizeFn = queueSizeProvider;
    if (maxQueueSize > 0 && sizeFn != null) {
      final int currentSize = sizeFn();
      final int reserved = reservedTerminalQueueSlots;
      final bool isTerminal = _terminalQueueEventTypes.contains(eventType);
      final int effectiveLimit = isTerminal
          ? maxQueueSize
          : maxQueueSize - reserved;
      if (currentSize >= effectiveLimit) {
        _queueFullCount += 1;
        return;
      }
    }

    final EventData resolvedEventData = eventData ?? EventData();
    String? effectiveErrorMessage = resolvedEventData.errorMessage;
    Object? normalizedContent = rawContent;
    final BigQueryContentFormatter? formatter = config.contentFormatter;
    if (formatter != null) {
      try {
        normalizedContent = formatter(normalizedContent, eventType);
      } catch (error) {
        _formatFailedCount += 1;
        stderr.writeln('Content formatter failed: $error');
        String formatterError;
        try {
          final String detail = '$error';
          formatterError = detail.isNotEmpty
              ? '${error.runtimeType}: $detail'
              : '${error.runtimeType}';
        } catch (_) {
          formatterError = '${error.runtimeType}';
        }
        // Fail closed so a masking/formatting error cannot leak raw content.
        normalizedContent = null;
        if (config.logContentFormatterErrorDetails) {
          final _TruncateResult truncatedFormatterError =
              _recursiveSmartTruncate(formatterError, config.maxContentLength);
          isTruncated = isTruncated || truncatedFormatterError.isTruncated;
          resolvedEventData.adkExtras['content_formatter_error'] =
              truncatedFormatterError.value;
          if (effectiveErrorMessage == null || effectiveErrorMessage.isEmpty) {
            effectiveErrorMessage = '${truncatedFormatterError.value ?? ''}';
          }
        }
      }
    }

    final _TracePair pair = _TraceManager.getCurrentSpanAndParent(
      callbackContext,
    );
    final String traceId =
        resolvedEventData.traceIdOverride ??
        _TraceManager.getTraceId(callbackContext);
    final String? spanId = resolvedEventData.spanIdOverride ?? pair.spanId;
    final String? parentSpanId =
        resolvedEventData.parentSpanIdOverride ?? pair.parentSpanId;

    final bool contentPartsPersisted = _contentPartsPersisted();
    if (!contentPartsPersisted) {
      _maybeWarnOffloadDisabled();
    }
    Object? contentValue;
    List<Object?> contentParts;
    if (_deniedColumns.contains('content') && !contentPartsPersisted) {
      contentValue = null;
      contentParts = const <Object?>[];
    } else {
      final _TruncateResult contentResult = _serializeContentPayload(
        normalizedContent,
        maxLength: config.maxContentLength,
      );
      isTruncated = isTruncated || contentResult.isTruncated;
      contentValue = _deniedColumns.contains('content')
          ? null
          : contentResult.value;
      contentParts = contentPartsPersisted
          ? await _extractContentPartsForLogging(
              normalizedContent,
              maxLength: config.maxContentLength,
              gcsUploadProvider: _gcsUploadProvider,
              traceId: traceId,
              spanId: spanId,
              connectionId: config.connectionId,
            )
          : const <Object?>[];
    }

    String? attributesJson;
    if (!_deniedColumns.contains('attributes')) {
      final Map<String, Object?> attributes = _enrichAttributes(
        callbackContext: callbackContext,
        eventData: resolvedEventData,
      );
      try {
        attributesJson = jsonEncode(attributes);
      } on Object {
        attributesJson = jsonEncode(
          attributes,
          toEncodable: (Object? value) => '$value',
        );
      }
    }

    final Map<String, Object?> row = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'event_type': eventType,
      'agent': callbackContext.agentName,
      'session_id': callbackContext.session.id,
      'invocation_id': callbackContext.invocationId,
      'user_id': callbackContext.userId,
      'trace_id': traceId,
      'span_id': spanId,
      'parent_span_id': parentSpanId,
      if (!_deniedColumns.contains('content')) 'content': contentValue,
      if (!_deniedColumns.contains('content_parts'))
        'content_parts': contentParts,
      if (!_deniedColumns.contains('attributes')) 'attributes': attributesJson,
      if (!_deniedColumns.contains('latency_ms'))
        'latency_ms': _extractLatency(resolvedEventData),
      'status': resolvedEventData.status,
      'error_message': effectiveErrorMessage,
      'is_truncated': isTruncated,
      'sdk_version': adkVersion,
      _schemaVersionLabelKey: _schemaVersion,
      'project_id': projectId,
      'dataset_id': datasetId,
      'table_id': tableId,
      'location': location,
    };

    try {
      await _sink.append(row);
    } catch (_) {
      _writeFailedCount += 1;
      rethrow;
    }
  }

  List<String> _buildAnalyticsViewStatements() {
    return _analyticsViewEventTypes
        .map(_buildAnalyticsViewStatement)
        .toList(growable: false);
  }

  String _buildAnalyticsViewStatement(String eventType) {
    final String viewName = 'v_${eventType.toLowerCase()}';
    final String escapedEventType = eventType.replaceAll("'", "\\'");
    final List<String> extraColumns = switch (eventType) {
      'NODE_OUTPUT' => const <String>[
        "JSON_VALUE(attributes, '\$.adk.node.path') AS node_path",
        "JSON_VALUE(attributes, '\$.adk.node.run_id') AS node_run_id",
        "JSON_VALUE(attributes, '\$.adk.node.parent_run_id') AS node_parent_run_id",
        'content AS output',
      ],
      'NODE_ERROR' => const <String>[
        "JSON_VALUE(attributes, '\$.adk.node.path') AS node_path",
        "JSON_VALUE(attributes, '\$.adk.node.run_id') AS node_run_id",
        "JSON_VALUE(attributes, '\$.adk.node.parent_run_id') AS node_parent_run_id",
        "JSON_VALUE(content, '\$.error_code') AS error_code",
      ],
      'WORKFLOW_NODE_FIRST_OBSERVED' => const <String>[
        "JSON_VALUE(attributes, '\$.adk.app_name') AS app_name",
        "JSON_VALUE(attributes, '\$.adk.workflow_segment_id') AS workflow_segment_id",
        "JSON_VALUE(attributes, '\$.adk.node.path') AS node_path",
        "JSON_VALUE(attributes, '\$.adk.node.run_id') AS node_run_id",
        "JSON_VALUE(attributes, '\$.adk.node.parent_run_id') AS node_parent_run_id",
        "JSON_VALUE(attributes, '\$.adk.source_event_id') AS source_event_id",
        "SAFE.TIMESTAMP_MICROS(SAFE_CAST(SAFE_CAST(JSON_VALUE(attributes, '\$.adk.source_event_timestamp') AS FLOAT64) * 1000000 AS INT64)) AS source_event_timestamp",
        "JSON_VALUE(attributes, '\$.adk.boundary_basis') AS boundary_basis",
      ],
      'WORKFLOW_NODE_OBSERVATION_SUMMARY' => const <String>[
        "JSON_VALUE(attributes, '\$.adk.app_name') AS app_name",
        "JSON_VALUE(attributes, '\$.adk.workflow_segment_id') AS workflow_segment_id",
        "JSON_VALUE(attributes, '\$.adk.node.path') AS node_path",
        "JSON_VALUE(attributes, '\$.adk.node.run_id') AS node_run_id",
        "JSON_VALUE(attributes, '\$.adk.node.parent_run_id') AS node_parent_run_id",
        "JSON_VALUE(attributes, '\$.adk.first_source_event_id') AS first_source_event_id",
        "JSON_VALUE(attributes, '\$.adk.last_source_event_id') AS last_source_event_id",
        "SAFE.TIMESTAMP_MICROS(SAFE_CAST(SAFE_CAST(JSON_VALUE(attributes, '\$.adk.first_source_event_timestamp') AS FLOAT64) * 1000000 AS INT64)) AS first_source_event_timestamp",
        "SAFE.TIMESTAMP_MICROS(SAFE_CAST(SAFE_CAST(JSON_VALUE(attributes, '\$.adk.last_source_event_timestamp') AS FLOAT64) * 1000000 AS INT64)) AS last_source_event_timestamp",
        "SAFE_CAST(JSON_VALUE(attributes, '\$.adk.source_event_span_ms') AS FLOAT64) AS source_event_span_ms",
        "SAFE_CAST(JSON_VALUE(attributes, '\$.adk.observed_event_count') AS INT64) AS observed_event_count",
        "SAFE_CAST(JSON_VALUE(attributes, '\$.adk.node_interrupt_observed') AS BOOL) AS node_interrupt_observed",
        "SAFE_CAST(JSON_VALUE(attributes, '\$.adk.descendant_interrupt_observed') AS BOOL) AS descendant_interrupt_observed",
        "SAFE_CAST(JSON_VALUE(attributes, '\$.adk.node_error_observed_count') AS INT64) AS node_error_observed_count",
        "JSON_VALUE(attributes, '\$.adk.drain_callback') AS drain_callback",
        "JSON_VALUE(attributes, '\$.adk.boundary_basis') AS boundary_basis",
        "SAFE_CAST(JSON_VALUE(attributes, '\$.adk.truncated_node_count') AS INT64) AS truncated_node_count",
      ],
      _ => const <String>[],
    };
    final String extraSelect = extraColumns.isEmpty
        ? ''
        : ',\n  ${extraColumns.join(',\n  ')}';
    return '''
CREATE OR REPLACE VIEW `$projectId.$datasetId.$viewName` AS
SELECT
  timestamp,
  event_type,
  agent,
  session_id,
  invocation_id,
  user_id,
  trace_id,
  span_id,
  parent_span_id,
  content,
  content_parts,
  attributes,
  latency_ms,
  status,
  error_message,
  is_truncated,
  sdk_version,
  project_id,
  dataset_id,
  table_id,
  location$extraSelect
FROM `$projectId.$datasetId.$tableId`
WHERE event_type = '$escapedEventType'
'''
        .trim();
  }

  Map<String, Object?> _buildAdkEnvelope(
    CallbackContext callbackContext,
    Event? sourceEvent,
  ) {
    final Map<String, Object?> adk = <String, Object?>{
      'schema_version': _schemaVersion,
      'app_name': callbackContext.session.appName,
    };
    if (sourceEvent == null) {
      return adk;
    }
    if (sourceEvent.id.isNotEmpty) {
      adk['source_event_id'] = sourceEvent.id;
    }
    final NodeInfo nodeInfo = sourceEvent.nodeInfo;
    final String path = nodeInfo.path;
    final String? runId = NodePathBuilder.fromString(path).runId;
    adk['node'] = <String, Object?>{
      'path': path,
      'run_id': (runId == null || runId.isEmpty) ? null : runId,
      'parent_run_id': nodeInfo.parentRunId,
    };
    adk['branch'] = sourceEvent.branch;
    return adk;
  }

  Map<String, Object?> _enrichAttributes({
    required CallbackContext callbackContext,
    required EventData eventData,
  }) {
    final Map<String, Object?> attrs = <String, Object?>{
      ...eventData.extraAttributes,
    };

    final Map<String, Object?> adkEnvelope = _buildAdkEnvelope(
      callbackContext,
      eventData.sourceEvent,
    );
    eventData.adkExtras.forEach((String key, Object? value) {
      adkEnvelope.putIfAbsent(key, () => value);
    });
    if (attrs['adk'] is Map) {
      final Map<String, Object?> existingAdk = _toStringObjectMap(attrs['adk']);
      existingAdk.forEach((String key, Object? value) {
        adkEnvelope.putIfAbsent(key, () => value);
      });
    }
    attrs['adk'] = adkEnvelope;

    attrs['root_agent_name'] =
        _TraceManager.getRootAgentName(callbackContext) ??
        callbackContext.invocationContext.agent.rootAgent.name;

    if (eventData.model != null) {
      attrs['model'] = eventData.model;
    }
    if (eventData.modelVersion != null) {
      attrs['model_version'] = eventData.modelVersion;
    }
    if (eventData.usageMetadata != null) {
      attrs['usage_metadata'] = _recursiveSmartTruncate(
        eventData.usageMetadata,
        config.maxContentLength,
      ).value;
    }
    if (eventData.cacheMetadata != null) {
      attrs['cache_metadata'] = _recursiveSmartTruncate(
        eventData.cacheMetadata,
        config.maxContentLength,
      ).value;
    }

    if (config.logSessionMetadata) {
      final Map<String, Object?> sessionMeta = <String, Object?>{
        'session_id': callbackContext.session.id,
        'app_name': callbackContext.session.appName,
        'user_id': callbackContext.session.userId,
      };
      if (callbackContext.session.state.isNotEmpty) {
        sessionMeta['state'] = Map<String, Object?>.from(
          callbackContext.session.state,
        );
      }
      attrs['session_metadata'] = sessionMeta;
    }

    if (config.customTags.isNotEmpty) {
      attrs['custom_tags'] = Map<String, Object?>.from(config.customTags);
    }

    return attrs;
  }

  Map<String, Object?>? _extractLatency(EventData eventData) {
    final Map<String, Object?> latency = <String, Object?>{};
    if (eventData.latencyMs != null) {
      latency['total_ms'] = eventData.latencyMs;
    }
    if (eventData.timeToFirstTokenMs != null) {
      latency['time_to_first_token_ms'] = eventData.timeToFirstTokenMs;
    }
    if (latency.isEmpty) {
      return null;
    }
    return latency;
  }

  bool _isConcurrentViewConflict(Object error) {
    final String message = '$error'.toLowerCase();
    return message.contains('conflict') ||
        message.contains('already exists') ||
        message.contains('status code 409') ||
        message.contains('http 409');
  }

  void _applyConfigOverrides(Map<String, Object?>? overrides) {
    if (overrides == null) {
      return;
    }
    for (final MapEntry<String, Object?> entry in overrides.entries) {
      switch (entry.key) {
        case 'enabled':
          if (entry.value is bool) {
            config.enabled = entry.value as bool;
          }
        case 'event_allowlist':
          if (entry.value is List) {
            config.eventAllowlist = (entry.value as List)
                .map((Object? value) => '$value')
                .toList(growable: false);
          }
        case 'event_denylist':
          if (entry.value is List) {
            config.eventDenylist = (entry.value as List)
                .map((Object? value) => '$value')
                .toList(growable: false);
          }
        case 'max_content_length':
          if (entry.value is num) {
            config.maxContentLength = (entry.value as num).toInt();
          }
        case 'table_id':
          if (entry.value is String) {
            config.tableId = entry.value as String;
          }
        case 'batch_size':
          if (entry.value is num) {
            config.batchSize = (entry.value as num).toInt();
          }
        case 'batch_flush_interval':
          if (entry.value is num) {
            config.batchFlushInterval = (entry.value as num).toDouble();
          }
        case 'shutdown_timeout':
          if (entry.value is num) {
            config.shutdownTimeout = (entry.value as num).toDouble();
          }
        case 'queue_max_size':
          if (entry.value is num) {
            config.queueMaxSize = (entry.value as num).toInt();
          }
        case 'log_multi_modal_content':
          if (entry.value is bool) {
            config.logMultiModalContent = entry.value as bool;
          }
        case 'log_content_formatter_error_details':
          if (entry.value is bool) {
            config.logContentFormatterErrorDetails = entry.value as bool;
          }
        case 'gcs_bucket_name':
          if (entry.value is String) {
            config.gcsBucketName = entry.value as String;
          }
        case 'connection_id':
          if (entry.value is String) {
            config.connectionId = entry.value as String;
          }
        case 'log_session_metadata':
          if (entry.value is bool) {
            config.logSessionMetadata = entry.value as bool;
          }
        case 'create_views':
          if (entry.value is bool) {
            config.createViews = entry.value as bool;
          }
        case 'view_prefix':
          if (entry.value is String) {
            config.viewPrefix = entry.value as String;
          }
        case 'payload_column_denylist':
          if (entry.value is Iterable) {
            final List<String> list = (entry.value as Iterable)
                .map((Object? value) => '$value')
                .toList(growable: false);
            validatePayloadColumnDenylist(list);
            config.payloadColumnDenylist = list;
          }
        case 'exactly_once_delivery':
          if (entry.value is bool) {
            config.exactlyOnceDelivery = entry.value as bool;
          }
        case 'gcs_upload_timeout':
          if (entry.value is Duration) {
            config.gcsUploadTimeout = entry.value as Duration;
          } else if (entry.value is num) {
            config.gcsUploadTimeout = Duration(
              milliseconds: ((entry.value as num).toDouble() * 1000).round(),
            );
          }
        case 'create_eval_views':
          if (entry.value is bool) {
            config.createEvalViews = entry.value as bool;
          }
        case 'eval_view_mode':
          if (entry.value is String) {
            config.evalViewMode = entry.value as String;
          }
        case 'max_observation_summaries_per_segment':
          if (entry.value is num) {
            config.maxObservationSummariesPerSegment =
                (entry.value as num).toInt();
          }
        case 'tool_result_classifier':
          if (entry.value is ToolResultClassifier) {
            config.toolResultClassifier = entry.value as ToolResultClassifier;
          }
      }
    }
  }

  Object? _agentInstruction(BaseAgent agent) {
    try {
      final Object? value = (agent as dynamic).instruction;
      return value;
    } catch (_) {
      return '';
    }
  }
}

const Set<String> _skillToolTypeNames = <String>{
  'ListSkillsTool',
  'LoadSkillResourceTool',
  'LoadSkillTool',
  'RunSkillScriptTool',
  'SearchSkillsTool',
  'UnloadSkillTool',
};

