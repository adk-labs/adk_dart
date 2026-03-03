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
import '../agents/remote_a2a_agent.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/agent_tool.dart';
import '../tools/base_tool.dart';
import '../tools/function_tool.dart';
import '../tools/mcp_tool/mcp_tool.dart';
import '../tools/tool_context.dart';
import '../tools/transfer_to_agent_tool.dart';
import '../types/content.dart';
import '../version.dart';
import 'base_plugin.dart';

const String _schemaVersion = '1';
const String _schemaVersionLabelKey = 'adk_schema_version';

const Map<String, String> _hitlEventMap = <String, String>{
  'adk_request_credential': 'HITL_CREDENTIAL_REQUEST',
  'adk_request_confirmation': 'HITL_CONFIRMATION_REQUEST',
  'adk_request_input': 'HITL_INPUT_REQUEST',
};

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
    this.gcsBucketName,
    this.connectionId,
    this.logSessionMetadata = true,
    Map<String, Object?>? customTags,
    this.autoSchemaUpgrade = true,
  }) : clusteringFields =
           clusteringFields ?? <String>['event_type', 'agent', 'user_id'],
       retryConfig = retryConfig ?? RetryConfig(),
       customTags = customTags ?? <String, Object?>{};

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

  /// Optional Cloud Storage bucket for overflow or archival integrations.
  String? gcsBucketName;

  /// Optional BigQuery connection identifier for external integrations.
  String? connectionId;

  /// Whether to include session metadata in event attributes.
  bool logSessionMetadata;

  /// Static key-value tags added to each event row.
  Map<String, Object?> customTags;

  /// Whether schema compatibility upgrades are allowed automatically.
  bool autoSchemaUpgrade;
}

/// Per-event metadata captured in BigQuery rows.
class EventData {
  /// Creates event metadata.
  EventData({
    this.spanIdOverride,
    this.parentSpanIdOverride,
    this.latencyMs,
    this.timeToFirstTokenMs,
    this.model,
    this.modelVersion,
    this.usageMetadata,
    this.status = 'OK',
    this.errorMessage,
    Map<String, Object?>? extraAttributes,
  }) : extraAttributes = extraAttributes ?? <String, Object?>{};

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

  /// Event status string stored in the `status` column.
  final String status;

  /// Optional error message for failed operations.
  final String? errorMessage;

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

class _SpanRecord {
  _SpanRecord({required this.spanId, required this.startMicros});

  final String spanId;
  final int startMicros;
  int? firstTokenMicros;
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
  static final Map<String, List<_SpanRecord>> _spanRecordsByInvocation =
      <String, List<_SpanRecord>>{};
  static final Map<String, String> _rootAgentNameByInvocation =
      <String, String>{};
  static final Random _random = Random();

  /// Initializes trace state for an invocation if missing.
  static void initTrace(CallbackContext callbackContext) {
    _spanRecordsByInvocation.putIfAbsent(
      callbackContext.invocationId,
      () => <_SpanRecord>[],
    );
    _rootAgentNameByInvocation.putIfAbsent(
      callbackContext.invocationId,
      () => callbackContext.invocationContext.agent.rootAgent.name,
    );
  }

  /// The trace identifier for the current invocation.
  static String getTraceId(CallbackContext callbackContext) {
    return callbackContext.invocationId;
  }

  /// Pushes a new span and returns its identifier.
  static String pushSpan(CallbackContext callbackContext, String spanName) {
    initTrace(callbackContext);

    final String spanId = _newSpanId();
    final List<_SpanRecord> stack = _spanRecordsByInvocation.putIfAbsent(
      callbackContext.invocationId,
      () => <_SpanRecord>[],
    );
    stack.add(
      _SpanRecord(
        spanId: spanId,
        startMicros: DateTime.now().microsecondsSinceEpoch,
      ),
    );
    return spanId;
  }

  /// Pops the current span and returns timing information.
  static _PopResult popSpan(CallbackContext callbackContext) {
    final List<_SpanRecord>? stack =
        _spanRecordsByInvocation[callbackContext.invocationId];
    if (stack == null || stack.isEmpty) {
      return _PopResult();
    }

    final _SpanRecord record = stack.removeLast();
    final int nowMicros = DateTime.now().microsecondsSinceEpoch;
    final int durationMs = ((nowMicros - record.startMicros) / 1000).round();
    final String? parentSpanId = stack.isEmpty ? null : stack.last.spanId;
    return _PopResult(
      spanId: record.spanId,
      parentSpanId: parentSpanId,
      durationMs: durationMs,
    );
  }

  /// The current span and parent span identifiers.
  static _TracePair getCurrentSpanAndParent(CallbackContext callbackContext) {
    final List<_SpanRecord>? stack =
        _spanRecordsByInvocation[callbackContext.invocationId];
    if (stack == null || stack.isEmpty) {
      return _TracePair();
    }
    final String spanId = stack.last.spanId;
    final String? parentSpanId = stack.length > 1
        ? stack[stack.length - 2].spanId
        : null;
    return _TracePair(spanId: spanId, parentSpanId: parentSpanId);
  }

  /// The current span identifier, if present.
  static String? getCurrentSpanId(CallbackContext callbackContext) {
    final List<_SpanRecord>? stack =
        _spanRecordsByInvocation[callbackContext.invocationId];
    if (stack == null || stack.isEmpty) {
      return null;
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
    return _rootAgentNameByInvocation[callbackContext.invocationId];
  }

  /// Clears trace state for an invocation.
  static void clear(CallbackContext callbackContext) {
    _spanRecordsByInvocation.remove(callbackContext.invocationId);
    _rootAgentNameByInvocation.remove(callbackContext.invocationId);
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
       super(name: 'bigquery_agent_analytics') {
    this.tableId = tableId ?? this.config.tableId;
    _applyConfigOverrides(configOverrides);
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

  bool _started = false;
  bool _isShuttingDown = false;
  final BigQueryEventSink _sink;

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
    _isShuttingDown = false;
    _started = false;
  }

  /// Flushes buffered events to the sink.
  Future<void> flush() async {
    await _sink.flush();
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

      if (event.actions.stateDelta.isNotEmpty) {
        await _logEvent(
          'STATE_DELTA',
          callbackContext,
          eventData: EventData(
            extraAttributes: <String, Object?>{
              'state_delta': Map<String, Object?>.from(
                event.actions.stateDelta,
              ),
            },
          ),
        );
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

      return null;
    });
  }

  /// Logs invocation start and initializes sink startup state.
  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    return _safeCallback<Content?>('beforeRunCallback', () async {
      final CallbackContext callbackContext = CallbackContext(
        invocationContext,
      );
      await _ensureStarted();
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
      await _logEvent('INVOCATION_COMPLETED', callbackContext);
      await flush();
      _TraceManager.clear(callbackContext);
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
      _TraceManager.pushSpan(callbackContext, 'agent');
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
      if (llmRequest.toolsDict.isNotEmpty) {
        attributes['tools'] = llmRequest.toolsDict.keys.toList(growable: false);
      }

      _TraceManager.pushSpan(callbackContext, 'llm_request');
      await _logEvent(
        'LLM_REQUEST',
        callbackContext,
        rawContent: llmRequest,
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

  /// Logs successful tool completion and span timing.
  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return _safeCallback<Map<String, dynamic>?>('afterToolCallback', () async {
      final _TruncateResult truncatedResult = _recursiveSmartTruncate(
        result,
        config.maxContentLength,
      );
      final _PopResult popResult = _TraceManager.popSpan(toolContext);

      await _logEvent(
        'TOOL_COMPLETED',
        toolContext,
        rawContent: <String, Object?>{
          'tool': tool.name,
          'result': truncatedResult.value,
          'tool_origin': _getToolOrigin(tool),
        },
        isTruncated: truncatedResult.isTruncated,
        eventData: EventData(
          latencyMs: popResult.durationMs,
          spanIdOverride: popResult.spanId,
          parentSpanIdOverride: popResult.parentSpanId,
        ),
      );
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
            errorMessage: '$error',
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

  Future<void> _logEvent(
    String eventType,
    CallbackContext callbackContext, {
    Object? rawContent,
    bool isTruncated = false,
    EventData? eventData,
  }) async {
    if (!config.enabled || _isShuttingDown) {
      return;
    }
    if (config.eventDenylist?.contains(eventType) == true) {
      return;
    }
    final List<String>? allowlist = config.eventAllowlist;
    if (allowlist != null && !allowlist.contains(eventType)) {
      return;
    }

    if (!_started) {
      await _ensureStarted();
    }

    final EventData resolvedEventData = eventData ?? EventData();
    Object? normalizedContent = rawContent;
    final BigQueryContentFormatter? formatter = config.contentFormatter;
    if (formatter != null) {
      try {
        normalizedContent = formatter(normalizedContent, eventType);
      } catch (error) {
        stderr.writeln('Content formatter failed: $error');
      }
    }

    final _TruncateResult contentResult = _serializeContentPayload(
      normalizedContent,
      maxLength: config.maxContentLength,
    );
    isTruncated = isTruncated || contentResult.isTruncated;
    final List<Object?> contentParts = config.logMultiModalContent
        ? _extractContentPartsForLogging(
            normalizedContent,
            maxLength: config.maxContentLength,
          )
        : const <Object?>[];

    final _TracePair pair = _TraceManager.getCurrentSpanAndParent(
      callbackContext,
    );
    final String traceId = _TraceManager.getTraceId(callbackContext);
    final String? spanId = resolvedEventData.spanIdOverride ?? pair.spanId;
    final String? parentSpanId =
        resolvedEventData.parentSpanIdOverride ?? pair.parentSpanId;

    final Map<String, Object?> attributes = _enrichAttributes(
      callbackContext: callbackContext,
      eventData: resolvedEventData,
    );
    String attributesJson;
    try {
      attributesJson = jsonEncode(attributes);
    } on Object {
      attributesJson = jsonEncode(
        attributes,
        toEncodable: (Object? value) => '$value',
      );
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
      'content': contentResult.value,
      'content_parts': contentParts,
      'attributes': attributesJson,
      'latency_ms': _extractLatency(resolvedEventData),
      'status': resolvedEventData.status,
      'error_message': resolvedEventData.errorMessage,
      'is_truncated': isTruncated,
      'sdk_version': adkVersion,
      _schemaVersionLabelKey: _schemaVersion,
      'project_id': projectId,
      'dataset_id': datasetId,
      'table_id': tableId,
      'location': location,
    };

    await _sink.append(row);
  }

  Map<String, Object?> _enrichAttributes({
    required CallbackContext callbackContext,
    required EventData eventData,
  }) {
    final Map<String, Object?> attrs = <String, Object?>{
      ...eventData.extraAttributes,
    };

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
        case 'log_session_metadata':
          if (entry.value is bool) {
            config.logSessionMetadata = entry.value as bool;
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

String _getToolOrigin(BaseTool tool) {
  if (tool is McpTool) {
    return 'MCP';
  }
  if (tool is TransferToAgentTool) {
    return 'TRANSFER_AGENT';
  }
  if (tool is AgentTool) {
    if (tool.agent is RemoteA2aAgent) {
      return 'A2A';
    }
    return 'SUB_AGENT';
  }
  if (tool is FunctionTool) {
    return 'LOCAL';
  }
  return 'UNKNOWN';
}

class _FormatResult {
  _FormatResult({required this.text, required this.isTruncated});

  final String text;
  final bool isTruncated;
}

_FormatResult _formatContent(Content? content, {int maxLen = 5000}) {
  if (content == null || content.parts.isEmpty) {
    return _FormatResult(text: 'None', isTruncated: false);
  }

  final List<String> parts = <String>[];
  bool truncated = false;
  for (final Part part in content.parts) {
    if (part.text != null) {
      String value = part.text!;
      if (maxLen != -1 && value.length > maxLen) {
        value = '${value.substring(0, maxLen)}...';
        truncated = true;
      }
      parts.add("text: '$value'");
    } else if (part.functionCall != null) {
      parts.add('call: ${part.functionCall!.name}');
    } else if (part.functionResponse != null) {
      parts.add('resp: ${part.functionResponse!.name}');
    } else {
      parts.add('other');
    }
  }
  return _FormatResult(text: parts.join(' | '), isTruncated: truncated);
}

_TruncateResult _serializeContentPayload(
  Object? value, {
  required int maxLength,
}) {
  if (value is LlmRequest) {
    final List<Object?> prompt = value.contents
        .map((Content content) => _contentToJson(content))
        .toList(growable: false);
    return _recursiveSmartTruncate(<String, Object?>{
      'prompt': prompt,
      if (value.config.systemInstruction != null)
        'system_prompt': value.config.systemInstruction,
    }, maxLength);
  }

  if (value is LlmResponse) {
    return _recursiveSmartTruncate(<String, Object?>{
      'content': _contentToJson(value.content),
      'partial': value.partial,
      'turn_complete': value.turnComplete,
      'error_code': value.errorCode,
      'error_message': value.errorMessage,
    }, maxLength);
  }

  if (value is Content) {
    return _recursiveSmartTruncate(_contentToJson(value), maxLength);
  }

  if (value is Part) {
    return _recursiveSmartTruncate(_partToJson(value), maxLength);
  }

  return _recursiveSmartTruncate(value, maxLength);
}

List<Object?> _extractContentPartsForLogging(
  Object? value, {
  required int maxLength,
}) {
  if (value is Content) {
    return value.parts
        .map(
          (Part part) => _recursiveSmartTruncate(_partToJson(part), maxLength),
        )
        .map((_TruncateResult result) => result.value)
        .toList(growable: false);
  }

  if (value is Part) {
    return <Object?>[
      _recursiveSmartTruncate(_partToJson(value), maxLength).value,
    ];
  }

  if (value is LlmResponse) {
    return _extractContentPartsForLogging(value.content, maxLength: maxLength);
  }

  if (value is LlmRequest) {
    final List<Object?> parts = <Object?>[];
    for (final Content content in value.contents) {
      parts.addAll(
        _extractContentPartsForLogging(content, maxLength: maxLength),
      );
    }
    return parts;
  }

  if (value is Map) {
    final Map<String, Object?> map = _toStringObjectMap(value);
    final Object? explicitParts = map['content_parts'];
    if (explicitParts is List) {
      return explicitParts
          .map((Object? part) => _recursiveSmartTruncate(part, maxLength).value)
          .toList(growable: false);
    }

    final Map<String, Object?> content = _toStringObjectMap(map['content']);
    final Object? partsRaw = content['parts'];
    if (partsRaw is List) {
      return partsRaw
          .map((Object? part) => _recursiveSmartTruncate(part, maxLength).value)
          .toList(growable: false);
    }
  }

  return const <Object?>[];
}

Map<String, Object?> _toStringObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, Object?>? _contentToJson(Content? content) {
  if (content == null) {
    return null;
  }

  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map(_partToJson).toList(growable: false),
  };
}

Map<String, Object?> _partToJson(Part part) {
  return <String, Object?>{
    if (part.text != null) 'text': part.text,
    if (part.thought) 'thought': true,
    if (part.thoughtSignature != null)
      'thought_signature': List<int>.from(part.thoughtSignature!),
    if (part.functionCall != null)
      'function_call': <String, Object?>{
        if (part.functionCall!.id != null) 'id': part.functionCall!.id,
        'name': part.functionCall!.name,
        'args': Map<String, dynamic>.from(part.functionCall!.args),
        if (part.functionCall!.partialArgs != null)
          'partial_args': part.functionCall!.partialArgs
              ?.map(
                (Map<String, Object?> value) =>
                    Map<String, Object?>.from(value),
              )
              .toList(growable: false),
        if (part.functionCall!.willContinue != null)
          'will_continue': part.functionCall!.willContinue,
      },
    if (part.functionResponse != null)
      'function_response': <String, Object?>{
        if (part.functionResponse!.id != null) 'id': part.functionResponse!.id,
        'name': part.functionResponse!.name,
        'response': Map<String, dynamic>.from(part.functionResponse!.response),
      },
    if (part.inlineData != null)
      'inline_data': <String, Object?>{
        'mime_type': part.inlineData!.mimeType,
        if (part.inlineData!.displayName != null)
          'display_name': part.inlineData!.displayName,
      },
    if (part.fileData != null)
      'file_data': <String, Object?>{
        'file_uri': part.fileData!.fileUri,
        if (part.fileData!.mimeType != null)
          'mime_type': part.fileData!.mimeType,
        if (part.fileData!.displayName != null)
          'display_name': part.fileData!.displayName,
      },
  };
}

_TruncateResult _recursiveSmartTruncate(
  Object? value,
  int maxLength, [
  Set<int>? seen,
]) {
  final Set<int> visited = seen ?? <int>{};

  if (value == null || value is num || value is bool) {
    return _TruncateResult(value: value, isTruncated: false);
  }

  if (value is String) {
    if (maxLength != -1 && value.length > maxLength) {
      return _TruncateResult(
        value: '${value.substring(0, maxLength)}...[TRUNCATED]',
        isTruncated: true,
      );
    }
    return _TruncateResult(value: value, isTruncated: false);
  }

  final int identity = identityHashCode(value);
  if (visited.contains(identity)) {
    return _TruncateResult(value: '[CIRCULAR_REFERENCE]', isTruncated: false);
  }

  final bool isCompound = value is Map || value is List || value is Set;
  if (isCompound) {
    visited.add(identity);
  }

  try {
    if (value is List) {
      bool truncated = false;
      final List<Object?> converted = <Object?>[];
      for (final Object? item in value) {
        final _TruncateResult child = _recursiveSmartTruncate(
          item,
          maxLength,
          visited,
        );
        converted.add(child.value);
        truncated = truncated || child.isTruncated;
      }
      return _TruncateResult(value: converted, isTruncated: truncated);
    }

    if (value is Set) {
      bool truncated = false;
      final List<Object?> converted = <Object?>[];
      for (final Object? item in value) {
        final _TruncateResult child = _recursiveSmartTruncate(
          item,
          maxLength,
          visited,
        );
        converted.add(child.value);
        truncated = truncated || child.isTruncated;
      }
      return _TruncateResult(value: converted, isTruncated: truncated);
    }

    if (value is Map) {
      bool truncated = false;
      final Map<String, Object?> converted = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final _TruncateResult child = _recursiveSmartTruncate(
          entry.value,
          maxLength,
          visited,
        );
        converted['${entry.key}'] = child.value;
        truncated = truncated || child.isTruncated;
      }
      return _TruncateResult(value: converted, isTruncated: truncated);
    }

    final String fallback = '$value';
    if (maxLength != -1 && fallback.length > maxLength) {
      return _TruncateResult(
        value: '${fallback.substring(0, maxLength)}...[TRUNCATED]',
        isTruncated: true,
      );
    }
    return _TruncateResult(value: fallback, isTruncated: false);
  } finally {
    if (isCompound) {
      visited.remove(identity);
    }
  }
}

void _putIfNotNull(Map<String, Object?> map, String key, Object? value) {
  if (value != null) {
    map[key] = value;
  }
}

Future<String?> _defaultBigQueryAccessTokenProvider() async {
  final Map<String, String> environment = Platform.environment;
  return environment['GOOGLE_OAUTH_ACCESS_TOKEN'] ??
      environment['GOOGLE_ACCESS_TOKEN'] ??
      environment['ACCESS_TOKEN'];
}

String _newInsertId() {
  final int micros = DateTime.now().microsecondsSinceEpoch;
  final int randomBits = Random().nextInt(1 << 20);
  return '${micros.toRadixString(16)}${randomBits.toRadixString(16)}';
}

Map<String, Object?> _toJsonSafeMap(Map<String, Object?> source) {
  final Map<String, Object?> converted = <String, Object?>{};
  source.forEach((String key, Object? value) {
    converted[key] = _toJsonSafeValue(value);
  });
  return converted;
}

Object? _toJsonSafeValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is List) {
    return value.map(_toJsonSafeValue).toList(growable: false);
  }
  if (value is Set) {
    return value.map(_toJsonSafeValue).toList(growable: false);
  }
  if (value is Map) {
    final Map<String, Object?> nested = <String, Object?>{};
    value.forEach((Object? nestedKey, Object? nestedValue) {
      nested['$nestedKey'] = _toJsonSafeValue(nestedValue);
    });
    return nested;
  }
  return '$value';
}
