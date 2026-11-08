part of 'bigquery_agent_analytics_plugin.dart';

List<String> _strictAncestorNodePaths(String nodePath) {
  final List<String> segments = nodePath.split('/');
  final List<String> ancestors = <String>[];
  for (int end = 1; end < segments.length; end += 1) {
    ancestors.add(segments.sublist(0, end).join('/'));
  }
  return ancestors;
}

class _WorkflowNodeObservation {
  _WorkflowNodeObservation({
    required this.nodePath,
    required this.nodeRunId,
    required this.nodeParentRunId,
    required this.firstSourceEventId,
    required this.lastSourceEventId,
    this.firstSourceEventTimestamp,
    this.lastSourceEventTimestamp,
  });

  final String nodePath;
  final String? nodeRunId;
  final String? nodeParentRunId;
  final String firstSourceEventId;
  String lastSourceEventId;
  double? firstSourceEventTimestamp;
  double? lastSourceEventTimestamp;
  int observedEventCount = 1;
  bool nodeInterruptObserved = false;
  bool descendantInterruptObserved = false;
  int nodeErrorObservedCount = 0;
}

class _WorkflowObservationSegment {
  _WorkflowObservationSegment({required this.segmentId});

  final String segmentId;
  final Map<String, _WorkflowNodeObservation> nodes =
      <String, _WorkflowNodeObservation>{};
  final Set<String> overflowNodePaths = <String>{};
  int untrackedPathEvents = 0;
  final Set<String> interruptedAncestorPaths = <String>{};
}

/// Retry policy used by BigQuery event delivery.
class RetryConfig {
  /// Creates a retry policy.
  RetryConfig({
    this.maxRetries = 3,
    this.initialDelay = 1.0,
    this.multiplier = 2.0,
    this.maxDelay = 10.0,
  });

  /// The maximum number of retry attempts.
  final int maxRetries;

  /// The initial retry delay in seconds.
  final double initialDelay;

  /// The exponential backoff multiplier applied after each retry.
  final double multiplier;

  /// The maximum retry delay in seconds.
  final double maxDelay;
}

/// Formats raw event content before it is serialized for BigQuery.
typedef BigQueryContentFormatter =
    Object? Function(Object? content, String eventType);

/// Uploads analytics content to Cloud Storage and returns a `gs://` URI.
typedef BigQueryGcsUploadProvider =
    Future<String> Function({
      required List<int> data,
      required String contentType,
      required String path,
    });

/// Executes generated analytics view SQL statements.
typedef BigQueryAnalyticsViewExecutor =
    Future<void> Function(List<String> statements);

/// Snapshot of dropped or degraded analytics event counts.
class BigQueryDropStats {
  /// Creates a drop statistics snapshot.
  const BigQueryDropStats({
    this.queueFull = 0,
    this.writeFailed = 0,
    this.shutdownDropped = 0,
    this.formatFailed = 0,
    this.gcsUploadFailed = 0,
    this.workflowObservationCapacity = 0,
  });

  /// Events dropped because the internal queue was at capacity.
  final int queueFull;

  /// Events dropped because writing to the BigQuery sink failed.
  final int writeFailed;

  /// Events dropped because the plugin was shutting down.
  final int shutdownDropped;

  /// Events whose content formatting failed and fell back to `null`.
  final int formatFailed;

  /// Multimodal or oversized text parts whose GCS offload failed.
  final int gcsUploadFailed;

  /// Workflow observation summaries not written because observed node paths
  /// exceeded [BigQueryLoggerConfig.maxObservationSummariesPerSegment].
  final int workflowObservationCapacity;

  /// Total events dropped from BigQuery delivery.
  int get total =>
      queueFull + writeFailed + shutdownDropped + workflowObservationCapacity;

  /// Serializes this snapshot as a JSON-compatible map.
  Map<String, int> toJson() => <String, int>{
    'queue_full': queueFull,
    'write_failed': writeFailed,
    'shutdown_dropped': shutdownDropped,
    'format_failed': formatFailed,
    'gcs_upload_failed': gcsUploadFailed,
    'workflow_observation_capacity': workflowObservationCapacity,
    'total': total,
  };
}

/// Configuration for [BigQueryAgentAnalyticsPlugin].
class BigQueryLoggerConfig {
  /// Creates a BigQuery logging configuration.
  BigQueryLoggerConfig({
    this.enabled = true,
    this.eventAllowlist,
    this.eventDenylist,
    this.maxContentLength = 500 * 1024,
    this.tableId = 'agent_events',
    List<String>? clusteringFields,
    this.logMultiModalContent = true,
    RetryConfig? retryConfig,
    this.batchSize = 1,
    this.batchFlushInterval = 1,
    this.shutdownTimeout = 10,
    this.queueMaxSize = 10000,
    this.contentFormatter,
    this.logContentFormatterErrorDetails = false,
    this.gcsBucketName,
    this.gcsUploadProvider,
    this.gcsUploadTimeout = const Duration(seconds: 10),
    this.connectionId,
    this.logSessionMetadata = true,
    Map<String, Object?>? customTags,
    this.autoSchemaUpgrade = true,
    this.createViews = true,
    this.viewPrefix = 'v',
    this.exactlyOnceDelivery = false,
    Set<String>? finalResponseToolNames,
    this.createEvalViews = false,
    this.evalViewMode = 'full',
    this.payloadColumnDenylist,
    this.maxObservationSummariesPerSegment = 200,
    this.toolResultClassifier,
    this.onSchemaError,
    this.onSchemaReady,
  }) : clusteringFields =
           clusteringFields ?? <String>['event_type', 'agent', 'user_id'],
       retryConfig = retryConfig ?? RetryConfig(),
       customTags = customTags ?? <String, Object?>{},
       finalResponseToolNames = finalResponseToolNames ?? <String>{} {
    validatePayloadColumnDenylist(payloadColumnDenylist);
  }

  /// Whether event logging is enabled.
  bool enabled;

  /// Optional event names to include.
  ///
  /// When provided, only listed events are logged.
  List<String>? eventAllowlist;

  /// Optional event names to exclude.
  List<String>? eventDenylist;

  /// The maximum serialized payload length per field.
  int maxContentLength;

  /// The destination table identifier.
  String tableId;

  /// BigQuery clustering fields for table creation workflows.
  List<String> clusteringFields;

  /// Whether multimodal parts are logged separately in `content_parts`.
  bool logMultiModalContent;

  /// Retry settings used by transport layers.
  RetryConfig retryConfig;

  /// The number of rows to buffer before flushing.
  int batchSize;

  /// The periodic flush interval in seconds.
  double batchFlushInterval;

  /// The shutdown flush timeout in seconds.
  double shutdownTimeout;

  /// The maximum number of queued events.
  int queueMaxSize;

  /// Optional payload formatter applied before truncation.
  BigQueryContentFormatter? contentFormatter;

  /// Whether to record `contentFormatter` exception details in BigQuery rows
  /// (`error_message` and `attributes.adk.content_formatter_error`).
  ///
  /// Defaults to `false` so exception messages that may contain raw payload
  /// fragments are not written to BigQuery unless explicitly opted in.
  bool logContentFormatterErrorDetails;

  /// Optional Cloud Storage bucket for overflow or archival integrations.
  String? gcsBucketName;

  /// Optional uploader used when [gcsBucketName] is configured.
  BigQueryGcsUploadProvider? gcsUploadProvider;

  /// Timeout applied to each GCS offload upload before pausing uploads for one
  /// cooldown window.
  Duration gcsUploadTimeout;

  /// Optional BigQuery connection identifier for external integrations.
  String? connectionId;

  /// Whether to include session metadata in event attributes.
  bool logSessionMetadata;

  /// Static key-value tags added to each event row.
  Map<String, Object?> customTags;

  /// Whether schema compatibility upgrades are allowed automatically.
  bool autoSchemaUpgrade;

  /// Whether per-event analytics views should be created.
  bool createViews;

  /// Prefix used for created BigQuery analytics and evaluation views.
  String viewPrefix;

  /// Whether deterministic row `insertId` values are used for deduplication.
  bool exactlyOnceDelivery;

  /// Tool names whose successful completion carries the agent's final answer.
  /// When a completed tool's name is in this set, its call args are logged as
  /// an `AGENT_RESPONSE` event.
  Set<String> finalResponseToolNames;

  /// Whether agent evaluation views (`v_eval_session`, `v_eval_turn`) should
  /// be created automatically.
  bool createEvalViews;

  /// Evaluation view event requirement mode: `'full'` (default) or
  /// `'conversation_only'`.
  String evalViewMode;

  /// Optional list of projectable payload columns (`'content'`,
  /// `'content_parts'`, `'attributes'`, `'latency_ms'`) to omit from logged rows.
  List<String>? payloadColumnDenylist;

  /// Maximum number of `WORKFLOW_NODE_OBSERVATION_SUMMARY` rows written when
  /// a runner call ends. Must be an integer >= 1.
  int maxObservationSummariesPerSegment;

  /// Optional classifier for tool results that report errors without throwing.
  ToolResultClassifier? toolResultClassifier;

  /// Optional callback invoked when schema or view setup fails.
  void Function(Object error, StackTrace stackTrace)? onSchemaError;

  /// Optional callback invoked when schema and view setup succeeds.
  void Function()? onSchemaReady;
}

/// Per-event metadata captured in BigQuery rows.
class EventData {
  /// Creates event metadata.
  EventData({
    this.traceIdOverride,
    this.spanIdOverride,
    this.parentSpanIdOverride,
    this.latencyMs,
    this.timeToFirstTokenMs,
    this.model,
    this.modelVersion,
    this.usageMetadata,
    this.cacheMetadata,
    this.status = 'OK',
    this.errorMessage,
    this.sourceEvent,
    Map<String, Object?>? adkExtras,
    Map<String, Object?>? extraAttributes,
  }) : adkExtras = adkExtras ?? <String, Object?>{},
       extraAttributes = extraAttributes ?? <String, Object?>{};

  /// Explicit trace identifier to use for this event.
  final String? traceIdOverride;

  /// Explicit span identifier to use for this event.
  final String? spanIdOverride;

  /// Explicit parent span identifier to use for this event.
  final String? parentSpanIdOverride;

  /// End-to-end latency in milliseconds.
  final int? latencyMs;

  /// Time-to-first-token latency in milliseconds.
  final int? timeToFirstTokenMs;

  /// The logical model name associated with this event.
  final String? model;

  /// The provider model version associated with this event.
  final String? modelVersion;

  /// Raw usage metadata emitted by model providers.
  final Object? usageMetadata;

  /// Context cache metadata emitted by model providers.
  final Object? cacheMetadata;

  /// Event status string stored in the `status` column.
  final String status;

  /// Optional error message for failed operations.
  final String? errorMessage;

  /// Optional source [Event] used to populate the `attributes.adk` envelope.
  final Event? sourceEvent;

  /// Producer-supplied extras merged into `attributes.adk`.
  final Map<String, Object?> adkExtras;

  /// Additional attributes merged into the row metadata.
  final Map<String, Object?> extraAttributes;
}

/// Event sink abstraction used by [BigQueryAgentAnalyticsPlugin].
abstract class BigQueryEventSink {
  /// Appends one event row.
  Future<void> append(Map<String, Object?> row);

  /// Flushes buffered rows to the destination.
  Future<void> flush();

  /// Closes the sink and releases resources.
  Future<void> close();
}

/// Async token provider used for BigQuery HTTP authentication.
typedef BigQueryAccessTokenProvider = Future<String?> Function();

/// [BigQueryEventSink] implementation that writes rows using `insertAll`.
class BigQueryInsertAllEventSink implements BigQueryEventSink {
  /// Creates an `insertAll` sink.
  BigQueryInsertAllEventSink({
    required this.projectId,
    required this.datasetId,
    required this.tableId,
    this.apiKey,
    this.maxBatchSize = 100,
    http.Client? httpClient,
    BigQueryAccessTokenProvider? accessTokenProvider,
  }) : _httpClient = httpClient ?? http.Client(),
       _accessTokenProvider =
           accessTokenProvider ?? _defaultBigQueryAccessTokenProvider,
       _ownsHttpClient = httpClient == null;

  /// The Google Cloud project identifier.
  final String projectId;

  /// The BigQuery dataset identifier.
  final String datasetId;

  /// The BigQuery table identifier.
  final String tableId;

  /// Optional API key used when OAuth access token is unavailable.
  final String? apiKey;

  /// The maximum rows sent in a single request.
  final int maxBatchSize;
  final http.Client _httpClient;
  final BigQueryAccessTokenProvider _accessTokenProvider;
  final bool _ownsHttpClient;
  final List<Map<String, Object?>> _pendingRows = <Map<String, Object?>>[];
  bool _closed = false;

  @override
  Future<void> append(Map<String, Object?> row) async {
    if (_closed) {
      throw StateError('Cannot append rows after BigQuery sink is closed.');
    }
    _pendingRows.add(Map<String, Object?>.from(row));
    if (_pendingRows.length >= maxBatchSize) {
      await _flushBatch();
    }
  }

  @override
  Future<void> flush() async {
    while (_pendingRows.isNotEmpty) {
      await _flushBatch();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    await flush();
    _closed = true;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<void> _flushBatch() async {
    if (_pendingRows.isEmpty) {
      return;
    }
    final int batchLimit = maxBatchSize <= 0 ? 1 : maxBatchSize;
    final int takeCount = _pendingRows.length < batchLimit
        ? _pendingRows.length
        : batchLimit;
    final List<Map<String, Object?>> batch = _pendingRows
        .sublist(0, takeCount)
        .map((Map<String, Object?> row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    _pendingRows.removeRange(0, takeCount);

    final Uri uri = _buildInsertAllUri();
    final String? accessToken = await _accessTokenProvider();
    final Map<String, String> headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $accessToken';
    }

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (final Map<String, Object?> row in batch) {
      rows.add(<String, Object?>{
        'insertId': _newInsertId(),
        'json': _toJsonSafeMap(row),
      });
    }
    final Map<String, Object?> payload = <String, Object?>{
      'kind': 'bigquery#tableDataInsertAllRequest',
      'skipInvalidRows': false,
      'ignoreUnknownValues': false,
      'rows': rows,
    };

    final http.Response response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 400) {
      throw HttpException(
        'BigQuery insertAll failed (${response.statusCode}): ${response.body}',
      );
    }

    final String body = response.body.trim();
    if (body.isEmpty) {
      return;
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) {
      return;
    }
    final Map<String, Object?> map = decoded.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    final Object? insertErrors = map['insertErrors'];
    if (insertErrors is List && insertErrors.isNotEmpty) {
      throw StateError(
        'BigQuery insertAll returned insert errors: $insertErrors',
      );
    }
  }

  Uri _buildInsertAllUri() {
    final Uri base = Uri.parse(
      'https://bigquery.googleapis.com/bigquery/v2/projects/'
      '$projectId/datasets/$datasetId/tables/$tableId/insertAll',
    );
    final String? resolvedApiKey = apiKey?.trim();
    if (resolvedApiKey == null || resolvedApiKey.isEmpty) {
      return base;
    }
    return base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        'key': resolvedApiKey,
      },
    );
  }
}

/// In-memory [BigQueryEventSink] for tests and local inspection.
class InMemoryBigQueryEventSink implements BigQueryEventSink {
  final List<Map<String, Object?>> _rows = <Map<String, Object?>>[];

  /// Logged rows captured by this sink.
  List<Map<String, Object?>> get rows =>
      List<Map<String, Object?>>.unmodifiable(_rows);

  @override
  Future<void> append(Map<String, Object?> row) async {
    _rows.add(Map<String, Object?>.from(row));
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> flush() async {}
}

class _GcsJsonUploadProvider {
  _GcsJsonUploadProvider({
    required this.bucketName,
    required http.Client httpClient,
    required BigQueryAccessTokenProvider accessTokenProvider,
  }) : _httpClient = httpClient,
       _accessTokenProvider = accessTokenProvider;

  final String bucketName;
  final http.Client _httpClient;
  final BigQueryAccessTokenProvider _accessTokenProvider;

  Future<String> uploadContent({
    required List<int> data,
    required String contentType,
    required String path,
  }) async {
    final String? accessToken = await _accessTokenProvider();
    final Map<String, String> headers = <String, String>{
      'content-type': contentType,
      'accept': 'application/json',
    };
    if (accessToken != null && accessToken.isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $accessToken';
    }

    final Uri uri = Uri(
      scheme: 'https',
      host: 'storage.googleapis.com',
      pathSegments: <String>['upload', 'storage', 'v1', 'b', bucketName, 'o'],
      queryParameters: <String, String>{'uploadType': 'media', 'name': path},
    );

    final http.Response response = await _httpClient.post(
      uri,
      headers: headers,
      body: data,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'GCS analytics offload failed (${response.statusCode}): '
        '${response.body}',
      );
    }
    return 'gs://$bucketName/$path';
  }
}

class _SpanRecord {
  _SpanRecord({
    required this.spanId,
    required this.startMicros,
    this.name = '',
    this.agentName,
    this.isLlmAgent = false,
    List<String>? childAgentNames,
  }) : childAgentNames = childAgentNames ?? const <String>[];

  final String spanId;
  final int startMicros;
  final String name;
  final String? agentName;
  final bool isLlmAgent;
  final List<String> childAgentNames;
  int? firstTokenMicros;
  bool taskDelegated = false;
}

class _CompletedInvocationTrace {
  _CompletedInvocationTrace({
    required this.traceId,
    required this.rootSpanId,
    required this.rootAgentName,
  });

  final String traceId;
  final String? rootSpanId;
  final String? rootAgentName;
}

class _TracePair {
  _TracePair({this.spanId, this.parentSpanId});

  final String? spanId;
  final String? parentSpanId;
}

class _PopResult {
  _PopResult({this.spanId, this.parentSpanId, this.durationMs});

  final String? spanId;
  final String? parentSpanId;
  final int? durationMs;
}

/// Tracks trace and span state across callback boundaries.
class _TraceManager {
  static const int maxCompletedInvocations = 1024;
  static final Map<String, List<_SpanRecord>> _spanRecordsByInvocation =
      <String, List<_SpanRecord>>{};
  static final Map<String, String> _rootAgentNameByInvocation =
      <String, String>{};
  static final Map<String, String> _rootSpanIdByInvocation = <String, String>{};
  static final Map<String, _CompletedInvocationTrace> _completedInvocations =
      <String, _CompletedInvocationTrace>{};
  static final Random _random = Random();

  /// Initializes trace state for an invocation if missing.
  static void initTrace(CallbackContext callbackContext) {
    final String invocationId = callbackContext.invocationId;
    _completedInvocations.remove(invocationId);
    _spanRecordsByInvocation.putIfAbsent(
      invocationId,
      () => <_SpanRecord>[],
    );
    _rootAgentNameByInvocation.putIfAbsent(
      invocationId,
      () => callbackContext.invocationContext.agent.rootAgent.name,
    );
    _rootSpanIdByInvocation.putIfAbsent(invocationId, _newSpanId);
  }

  /// The trace identifier for the current invocation.
  static String getTraceId(CallbackContext callbackContext) {
    return callbackContext.invocationId;
  }

  /// Pushes a new span and returns its identifier.
  static String pushSpan(
    CallbackContext callbackContext,
    String spanName, {
    BaseAgent? agent,
  }) {
    final String invocationId = callbackContext.invocationId;
    final _CompletedInvocationTrace? completed =
        _completedInvocations[invocationId];
    if (completed != null) {
      // Late callback after afterRunCallback: do not resurrect active tracking,
      // but push onto the transient stack seeded with the completed root span.
      final List<_SpanRecord> stack = _spanRecordsByInvocation.putIfAbsent(
        invocationId,
        () => <_SpanRecord>[
          if (completed.rootSpanId != null)
            _SpanRecord(
              spanId: completed.rootSpanId!,
              startMicros: DateTime.now().microsecondsSinceEpoch,
              name: 'invocation',
            ),
        ],
      );
      final String spanId = _newSpanId();
      stack.add(
        _SpanRecord(
          spanId: spanId,
          startMicros: DateTime.now().microsecondsSinceEpoch,
          name: spanName,
          agentName: agent?.name,
          isLlmAgent: agent is LlmAgent,
          childAgentNames: agent == null
              ? const <String>[]
              : agent.subAgents
                    .map((BaseAgent sub) => sub.name)
                    .toList(growable: false),
        ),
      );
      return spanId;
    }

    initTrace(callbackContext);

    final List<_SpanRecord> stack = _spanRecordsByInvocation.putIfAbsent(
      invocationId,
      () => <_SpanRecord>[],
    );
    if (spanName == 'agent' && agent != null && stack.isNotEmpty) {
      // Retire a prior activation of the same LLM agent that was interrupted
      // by task delegation when control returns after finish_task.
      for (int i = stack.length - 1; i >= 0; i -= 1) {
        final _SpanRecord record = stack[i];
        if (record.name == 'agent' &&
            record.agentName == agent.name &&
            record.taskDelegated) {
          stack.removeRange(i, stack.length);
          break;
        }
      }
    }

    final String spanId = _newSpanId();
    stack.add(
      _SpanRecord(
        spanId: spanId,
        startMicros: DateTime.now().microsecondsSinceEpoch,
        name: spanName,
        agentName: agent?.name,
        isLlmAgent: agent is LlmAgent,
        childAgentNames: agent == null
            ? const <String>[]
            : agent.subAgents
                  .map((BaseAgent sub) => sub.name)
                  .toList(growable: false),
      ),
    );
    _rootSpanIdByInvocation[invocationId] ??= spanId;
    return spanId;
  }

  /// Pops a task-mode agent span when `finish_task` completes and marks only a
  /// direct LLM parent that configured the task sub-agent as `taskDelegated`.
  static _PopResult popTaskAgentSpan(
    CallbackContext callbackContext,
    String taskAgentName,
  ) {
    final List<_SpanRecord>? stack =
        _spanRecordsByInvocation[callbackContext.invocationId];
    if (stack == null || stack.isEmpty) {
      return _PopResult();
    }
    int taskIndex = -1;
    for (int i = stack.length - 1; i >= 0; i -= 1) {
      if (stack[i].name == 'agent' && stack[i].agentName == taskAgentName) {
        taskIndex = i;
        break;
      }
    }
    if (taskIndex < 0) {
      return _PopResult();
    }
    final _SpanRecord record = stack.removeAt(taskIndex);
    final String? parentSpanId = taskIndex > 0
        ? stack[taskIndex - 1].spanId
        : null;
    if (parentSpanId != null) {
      for (int j = 0; j < stack.length; j += 1) {
        final _SpanRecord candidate = stack[j];
        if (candidate.spanId == parentSpanId &&
            candidate.name == 'agent' &&
            candidate.isLlmAgent &&
            candidate.childAgentNames.contains(taskAgentName)) {
          candidate.taskDelegated = true;
          break;
        }
      }
    }
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int durationMs = ((nowMicros - record.startMicros) / 1000).round();
    return _PopResult(
      spanId: record.spanId,
      parentSpanId: parentSpanId,
      durationMs: durationMs,
    );
  }

  /// Pops the current span and returns timing information.
  static _PopResult popSpan(CallbackContext callbackContext) {
    final String invocationId = callbackContext.invocationId;
    final List<_SpanRecord>? stack = _spanRecordsByInvocation[invocationId];
    if (stack == null || stack.isEmpty) {
      final _CompletedInvocationTrace? completed =
          _completedInvocations[invocationId];
      if (completed != null) {
        return _PopResult(
          spanId: completed.rootSpanId,
          parentSpanId: null,
        );
      }
      return _PopResult();
    }

    final _SpanRecord record = stack.removeLast();
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int durationMs = ((nowMicros - record.startMicros) / 1000).round();
    final String? parentSpanId = stack.isEmpty
        ? _completedInvocations[invocationId]?.rootSpanId
        : stack.last.spanId;
    return _PopResult(
      spanId: record.spanId,
      parentSpanId: parentSpanId,
      durationMs: durationMs,
    );
  }

  /// The current span and parent span identifiers.
  static _TracePair getCurrentSpanAndParent(CallbackContext callbackContext) {
    final String invocationId = callbackContext.invocationId;
    final List<_SpanRecord>? stack = _spanRecordsByInvocation[invocationId];
    if (stack == null || stack.isEmpty) {
      final _CompletedInvocationTrace? completed =
          _completedInvocations[invocationId];
      if (completed != null) {
        return _TracePair(spanId: completed.rootSpanId, parentSpanId: null);
      }
      return _TracePair();
    }
    final String spanId = stack.last.spanId;
    final String? parentSpanId = stack.length > 1
        ? stack[stack.length - 2].spanId
        : _completedInvocations[invocationId]?.rootSpanId;
    return _TracePair(
      spanId: spanId,
      parentSpanId: parentSpanId == spanId ? null : parentSpanId,
    );
  }

  /// The current span identifier, if present.
  static String? getCurrentSpanId(CallbackContext callbackContext) {
    final String invocationId = callbackContext.invocationId;
    final List<_SpanRecord>? stack = _spanRecordsByInvocation[invocationId];
    if (stack == null || stack.isEmpty) {
      return _completedInvocations[invocationId]?.rootSpanId;
    }
    return stack.last.spanId;
  }

  /// Records the first token timestamp for [spanId].
  ///
  /// Returns `true` when the timestamp is recorded for the first time.
  static bool recordFirstToken(CallbackContext callbackContext, String spanId) {
    final _SpanRecord? record = _findRecord(callbackContext, spanId);
    if (record == null || record.firstTokenMicros != null) {
      return false;
    }
    record.firstTokenMicros = DateTime.now().microsecondsSinceEpoch;
    return true;
  }

  /// Elapsed time in milliseconds for [spanId], if available.
  static int? elapsedMs(CallbackContext callbackContext, String spanId) {
    final _SpanRecord? record = _findRecord(callbackContext, spanId);
    if (record == null) {
      return null;
    }
    return ((DateTime.now().microsecondsSinceEpoch - record.startMicros) / 1000)
        .round();
  }

  /// Time-to-first-token in milliseconds for [spanId], if available.
  static int? timeToFirstTokenMs(
    CallbackContext callbackContext,
    String spanId,
  ) {
    final _SpanRecord? record = _findRecord(callbackContext, spanId);
    final int? firstTokenMicros = record?.firstTokenMicros;
    if (record == null || firstTokenMicros == null) {
      return null;
    }
    return ((firstTokenMicros - record.startMicros) / 1000).round();
  }

  /// The root agent name associated with the current invocation.
  static String? getRootAgentName(CallbackContext callbackContext) {
    final String invocationId = callbackContext.invocationId;
    return _rootAgentNameByInvocation[invocationId] ??
        _completedInvocations[invocationId]?.rootAgentName;
  }

  /// Archives and clears active trace state for a completed invocation.
  static void clear(CallbackContext callbackContext) {
    final String invocationId = callbackContext.invocationId;
    final List<_SpanRecord>? stack = _spanRecordsByInvocation.remove(
      invocationId,
    );
    final String rootAgentName =
        _rootAgentNameByInvocation.remove(invocationId) ??
        callbackContext.invocationContext.agent.rootAgent.name;
    final String? rootSpanId =
        _rootSpanIdByInvocation.remove(invocationId) ??
        (stack != null && stack.isNotEmpty ? stack.first.spanId : null);
    if (invocationId.isNotEmpty) {
      _completedInvocations.remove(invocationId);
      _completedInvocations[invocationId] = _CompletedInvocationTrace(
        traceId: invocationId,
        rootSpanId: rootSpanId,
        rootAgentName: rootAgentName,
      );
      while (_completedInvocations.length > maxCompletedInvocations) {
        _completedInvocations.remove(_completedInvocations.keys.first);
      }
    }
  }

  static _SpanRecord? _findRecord(
    CallbackContext callbackContext,
    String spanId,
  ) {
    final List<_SpanRecord>? stack =
        _spanRecordsByInvocation[callbackContext.invocationId];
    if (stack == null) {
      return null;
    }
    for (int i = stack.length - 1; i >= 0; i -= 1) {
      final _SpanRecord record = stack[i];
      if (record.spanId == spanId) {
        return record;
      }
    }
    return null;
  }

  static String _newSpanId() {
    final int value =
        DateTime.now().microsecondsSinceEpoch ^ _random.nextInt(1 << 31);
    final String hex = value.toUnsigned(64).toRadixString(16);
    return hex.padLeft(16, '0').substring(0, 16);
  }
}

class _TruncateResult {
  _TruncateResult({required this.value, required this.isTruncated});

  final Object? value;
  final bool isTruncated;
}
