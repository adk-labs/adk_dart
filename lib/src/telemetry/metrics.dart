/// OpenTelemetry-compatible ADK metric recording helpers.
library;

import 'dart:convert';

import '../events/event.dart';
import '../models/cache_metadata.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../types/content.dart';
import '../utils/system_environment/system_environment.dart';

/// Metric name for client token usage.
const String genAiClientTokenUsageMetric = 'gen_ai.client.token.usage';

/// Metric name for inference chunk durations.
const String genAiClientInferenceChunkDurationMetric =
    'gen_ai.client.inference.chunk.duration';

/// Metric name for time to first inference chunk.
const String genAiClientOperationTimeToFirstChunkMetric =
    'gen_ai.client.operation.time_to_first_chunk';

/// Metric name for agent invocation durations.
const String genAiAgentInvocationDurationMetric =
    'gen_ai.agent.invocation.duration';

/// Metric name for workflow invocation durations.
const String genAiWorkflowInvocationDurationMetric =
    'gen_ai.workflow.invocation.duration';

/// Metric name for tool execution durations.
const String genAiToolExecutionDurationMetric =
    'gen_ai.tool.execution.duration';

/// Metric name for client operation durations.
const String genAiClientOperationDurationMetric =
    'gen_ai.client.operation.duration';

/// Metric name for agent request sizes.
const String genAiAgentRequestSizeMetric = 'gen_ai.agent.request.size';

/// Metric name for agent response sizes.
const String genAiAgentResponseSizeMetric = 'gen_ai.agent.response.size';

/// Metric name for tool request sizes.
const String genAiToolRequestSizeMetric = 'gen_ai.tool.request.size';

/// Metric name for tool response sizes.
const String genAiToolResponseSizeMetric = 'gen_ai.tool.response.size';

/// Explicit histogram bucket boundaries for agent invocation durations (s).
const List<double> agentDurationBucketBounds = <double>[
  0.1,
  0.2,
  0.4,
  0.8,
  1.6,
  3.2,
  6.4,
  12.8,
  25.6,
  51.2,
  102.4,
  204.8,
  409.6,
];

/// Explicit histogram bucket boundaries for workflow invocation durations (s).
const List<int> workflowDurationBucketBounds = <int>[
  1,
  5,
  10,
  30,
  60,
  120,
  300,
  600,
  1800,
  3600,
  7200,
];

/// Explicit histogram bucket boundaries for tool and client operation durations (s).
const List<double> operationDurationBucketBounds = <double>[
  0.01,
  0.02,
  0.04,
  0.08,
  0.16,
  0.32,
  0.64,
  1.28,
  2.56,
  5.12,
  10.24,
  20.48,
  40.96,
  81.92,
];

/// Explicit histogram bucket boundaries for token usage counts.
const List<int> tokenUsageBucketBounds = <int>[
  1,
  4,
  16,
  64,
  256,
  1024,
  4096,
  16384,
  65536,
  262144,
  1048576,
  4194304,
  16777216,
  67108864,
];

/// One ADK metric sample.
class AdkMetricRecord {
  /// Creates a metric sample with [name], [value], [unit], and [attributes].
  AdkMetricRecord({
    required this.name,
    required this.value,
    required this.unit,
    required this.description,
    Map<String, Object?>? attributes,
    List<num>? explicitBucketBoundariesAdvisory,
  }) : attributes = Map<String, Object?>.unmodifiable(
         attributes ?? const <String, Object?>{},
       ),
       explicitBucketBoundariesAdvisory =
           explicitBucketBoundariesAdvisory == null
           ? null
           : List<num>.unmodifiable(explicitBucketBoundariesAdvisory);

  /// Canonical OpenTelemetry metric name.
  final String name;

  /// Recorded histogram value.
  final num value;

  /// OpenTelemetry unit, such as `ms`, `By`, or `1`.
  final String unit;

  /// Human-readable metric description.
  final String description;

  /// Attributes attached to this sample.
  final Map<String, Object?> attributes;

  /// Optional explicit histogram bucket boundaries advisory.
  final List<num>? explicitBucketBoundariesAdvisory;
}

/// Sink for ADK metric samples.
abstract class AdkMetricsRecorder {
  /// Records one [metric] sample.
  void record(AdkMetricRecord metric);
}

/// Metrics recorder that intentionally drops all samples.
class NoopAdkMetricsRecorder implements AdkMetricsRecorder {
  /// Creates a recorder that drops samples.
  const NoopAdkMetricsRecorder();

  @override
  void record(AdkMetricRecord metric) {}
}

/// Metrics recorder that stores samples in memory for tests and adapters.
class InMemoryAdkMetricsRecorder implements AdkMetricsRecorder {
  /// Creates an empty in-memory recorder.
  InMemoryAdkMetricsRecorder();

  final List<AdkMetricRecord> _records = <AdkMetricRecord>[];

  /// Recorded samples in insertion order.
  List<AdkMetricRecord> get records =>
      List<AdkMetricRecord>.unmodifiable(_records);

  /// Removes all recorded samples.
  void clear() {
    _records.clear();
  }

  @override
  void record(AdkMetricRecord metric) {
    _records.add(metric);
  }
}

AdkMetricsRecorder _globalAdkMetricsRecorder = const NoopAdkMetricsRecorder();

/// The process-wide metrics recorder used by ADK helpers.
AdkMetricsRecorder get adkMetricsRecorder => _globalAdkMetricsRecorder;

/// Sets the process-wide ADK metrics [recorder].
void setAdkMetricsRecorder(AdkMetricsRecorder recorder) {
  _globalAdkMetricsRecorder = recorder;
}

/// Restores the process-wide metrics recorder to a no-op recorder.
void resetAdkMetricsRecorderForTest() {
  _globalAdkMetricsRecorder = const NoopAdkMetricsRecorder();
}

/// Returns the UTF-8 and inline-data byte size of [content].
int contentSizeBytes(Content? content) {
  if (content == null) {
    return 0;
  }
  int size = 0;
  for (final Part part in content.parts) {
    final String? text = part.text;
    if (text != null) {
      size += utf8.encode(text).length;
    }
    final InlineData? inlineData = part.inlineData;
    if (inlineData != null) {
      size += inlineData.data.length;
    }
  }
  return size;
}

/// Returns the request byte size for string-valued tool arguments.
int toolRequestSizeBytes(Map<String, Object?> functionArgs) {
  int size = 0;
  for (final Object? value in functionArgs.values) {
    if (value is String) {
      size += utf8.encode(value).length;
    }
  }
  return size;
}

/// Records the duration of an agent invocation.
void recordAgentInvocationDuration(
  String agentName,
  Duration duration, {
  Object? error,
  AdkMetricsRecorder? recorder,
}) {
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiAgentInvocationDurationMetric,
      value: duration.inMilliseconds.toDouble(),
      unit: 'ms',
      description: 'Duration of agent invocations.',
      attributes: _agentAttributes(agentName, error: error),
      explicitBucketBoundariesAdvisory: agentDurationBucketBounds,
    ),
  );
}

/// Records the duration of a workflow invocation.
void recordWorkflowInvocationDuration(
  String workflowName,
  Duration duration, {
  Object? error,
  AdkMetricsRecorder? recorder,
}) {
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiWorkflowInvocationDurationMetric,
      value: duration.inMilliseconds.toDouble() / 1000.0,
      unit: 's',
      description: 'Total duration of a workflow execution.',
      attributes: _agentAttributes(workflowName, error: error),
      explicitBucketBoundariesAdvisory: workflowDurationBucketBounds,
    ),
  );
}

/// Records the duration of a client operation (e.g., `generate_content`).
void recordClientOperationDuration(
  String agentName,
  Duration duration, {
  String operationName = 'generate_content',
  String? requestModel,
  String? responseModel,
  String? system,
  String? serverAddress,
  int? serverPort,
  List<String>? finishReasons,
  Object? error,
  AdkMetricsRecorder? recorder,
}) {
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiClientOperationDurationMetric,
      value: duration.inMilliseconds.toDouble() / 1000.0,
      unit: 's',
      description: 'GenAI operation duration.',
      attributes: <String, Object?>{
        if (agentName.isNotEmpty) 'gen_ai.agent.name': agentName,
        'gen_ai.operation.name': operationName,
        if (requestModel != null && requestModel.isNotEmpty)
          'gen_ai.request.model': requestModel,
        if (responseModel != null && responseModel.isNotEmpty)
          'gen_ai.response.model': responseModel,
        if (system != null && system.isNotEmpty) 'gen_ai.system': system,
        if (serverAddress != null && serverAddress.isNotEmpty)
          'server.address': serverAddress,
        'server.port': ?serverPort,
        if (finishReasons != null && finishReasons.isNotEmpty)
          'gen_ai.response.finish_reasons': List<String>.unmodifiable(
            finishReasons,
          ),
        if (error != null)
          'error.type': error is String ? error : error.runtimeType.toString(),
      },
      explicitBucketBoundariesAdvisory: operationDurationBucketBounds,
    ),
  );
}

/// Records the latency of an inference chunk and, for the first chunk, the
/// time to first chunk.
void recordClientInferenceChunk(
  Duration duration, {
  required bool isFirstChunk,
  String? agentName,
  String operationName = 'generate_content',
  String? requestModel,
  String? responseModel,
  String? system,
  String? serverAddress,
  int? serverPort,
  AdkMetricsRecorder? recorder,
}) {
  final Map<String, Object?> attributes = <String, Object?>{
    if (agentName != null && agentName.isNotEmpty)
      'gen_ai.agent.name': agentName,
    'gen_ai.operation.name': operationName,
    if (requestModel != null && requestModel.isNotEmpty)
      'gen_ai.request.model': requestModel,
    if (responseModel != null && responseModel.isNotEmpty)
      'gen_ai.response.model': responseModel,
    if (system != null && system.isNotEmpty) 'gen_ai.system': system,
    if (serverAddress != null && serverAddress.isNotEmpty)
      'server.address': serverAddress,
    'server.port': ?serverPort,
  };
  final double durationSeconds =
      duration.inMicroseconds.toDouble() / 1000000.0;
  if (isFirstChunk) {
    _record(
      recorder,
      AdkMetricRecord(
        name: genAiClientOperationTimeToFirstChunkMetric,
        value: durationSeconds,
        unit: 's',
        description: 'Time to first chunk of a streaming GenAI operation.',
        attributes: attributes,
        explicitBucketBoundariesAdvisory: operationDurationBucketBounds,
      ),
    );
  }
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiClientInferenceChunkDurationMetric,
      value: durationSeconds,
      unit: 's',
      description: 'Duration between consecutive inference chunks.',
      attributes: attributes,
      explicitBucketBoundariesAdvisory: operationDurationBucketBounds,
    ),
  );
}

/// Records the byte size of the user content sent to an agent.
void recordAgentRequestSize(
  String agentName,
  Content? userContent, {
  AdkMetricsRecorder? recorder,
}) {
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiAgentRequestSizeMetric,
      value: contentSizeBytes(userContent),
      unit: 'By',
      description: 'Size of agent requests.',
      attributes: _agentAttributes(agentName),
    ),
  );
}

/// Records the byte size of the last response content authored by an agent.
void recordAgentResponseSize(
  String agentName,
  List<Event>? events, {
  AdkMetricsRecorder? recorder,
}) {
  Content? responseContent;
  if (events != null) {
    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      if (event.author == agentName && event.content != null) {
        responseContent = event.content;
        break;
      }
    }
  }
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiAgentResponseSizeMetric,
      value: contentSizeBytes(responseContent),
      unit: 'By',
      description: 'Size of agent responses.',
      attributes: _agentAttributes(agentName),
    ),
  );
}

/// Records the duration of a tool execution.
void recordToolExecutionDuration(
  String toolName,
  String agentName,
  Duration duration, {
  Object? error,
  AdkMetricsRecorder? recorder,
}) {
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiToolExecutionDurationMetric,
      value: duration.inMilliseconds.toDouble(),
      unit: 'ms',
      description: 'Duration of tool executions.',
      attributes: _toolAttributes(toolName, agentName, error: error),
      explicitBucketBoundariesAdvisory: operationDurationBucketBounds,
    ),
  );
}

/// Records the byte size of string-valued tool arguments.
void recordToolRequestSize(
  String toolName,
  String agentName,
  Map<String, Object?> functionArgs, {
  AdkMetricsRecorder? recorder,
}) {
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiToolRequestSizeMetric,
      value: toolRequestSizeBytes(functionArgs),
      unit: 'By',
      description: 'Size of tool requests.',
      attributes: _toolAttributes(toolName, agentName),
    ),
  );
}

/// Records the byte size of a tool response event.
void recordToolResponseSize(
  String toolName,
  String agentName,
  Event? responseEvent, {
  AdkMetricsRecorder? recorder,
}) {
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiToolResponseSizeMetric,
      value: contentSizeBytes(responseEvent?.content),
      unit: 'By',
      description: 'Size of tool responses.',
      attributes: _toolAttributes(toolName, agentName),
    ),
  );
}

/// Per-modality token count entry.
class ModalityTokenUsage {
  /// Creates a per-modality token count entry.
  const ModalityTokenUsage(this.modality, this.tokenCount);

  /// Normalized lowercase modality name (e.g., `text`, `image`, `audio`).
  final String modality;

  /// Token count for [modality].
  final int tokenCount;

  @override
  bool operator ==(Object other) =>
      other is ModalityTokenUsage &&
      other.modality == modality &&
      other.tokenCount == tokenCount;

  @override
  int get hashCode => Object.hash(modality, tokenCount);

  @override
  String toString() => 'ModalityTokenUsage($modality: $tokenCount)';
}

/// Aggregated token usage extracted from one or more LLM responses.
class TokenUsage {
  /// Creates a token usage summary.
  const TokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.cacheReadInputTokens,
    this.cacheWriteInputTokens,
    this.reasoningOutputTokens,
    this.toolInputTokens,
    this.promptInputTokens,
    this.candidateOutputTokens,
    this.inputTokensByModality = const <ModalityTokenUsage>[],
    this.cacheReadInputTokensByModality = const <ModalityTokenUsage>[],
    this.toolInputTokensByModality = const <ModalityTokenUsage>[],
    this.outputTokensByModality = const <ModalityTokenUsage>[],
  });

  /// Total input tokens (prompt + tool input tokens).
  final int? inputTokens;

  /// Total output tokens (candidate + reasoning output tokens).
  final int? outputTokens;

  /// Cached content input tokens.
  final int? cacheReadInputTokens;

  /// Cache creation/write input tokens.
  final int? cacheWriteInputTokens;

  /// Reasoning (thoughts) output tokens.
  final int? reasoningOutputTokens;

  /// Server-side tool use prompt input tokens.
  final int? toolInputTokens;

  /// Prompt input tokens.
  final int? promptInputTokens;

  /// Candidate output tokens.
  final int? candidateOutputTokens;

  /// Per-modality input tokens (prompt + tool input tokens).
  final List<ModalityTokenUsage> inputTokensByModality;

  /// Per-modality cache-read input tokens.
  final List<ModalityTokenUsage> cacheReadInputTokensByModality;

  /// Per-modality tool input tokens.
  final List<ModalityTokenUsage> toolInputTokensByModality;

  /// Per-modality output tokens.
  final List<ModalityTokenUsage> outputTokensByModality;

  /// Total derived tokens (`(inputTokens ?? 0) + (outputTokens ?? 0)`).
  int get totalTokens => (inputTokens ?? 0) + (outputTokens ?? 0);

  /// Extracts [TokenUsage] from a raw [usageMetadata] map or object.
  static TokenUsage fromUsageMetadata(
    Object? usageMetadata, {
    int? cacheWriteInputTokens,
  }) {
    if (usageMetadata == null) {
      return TokenUsage(cacheWriteInputTokens: cacheWriteInputTokens);
    }
    final int? promptTokens = _readIntField(
      usageMetadata,
      const <String>['prompt_token_count', 'promptTokenCount'],
    );
    final int? toolTokens = _readIntField(
      usageMetadata,
      const <String>[
        'tool_use_prompt_token_count',
        'toolUsePromptTokenCount',
      ],
    );
    final int? candidatesTokens = _readIntField(
      usageMetadata,
      const <String>['candidates_token_count', 'candidatesTokenCount'],
    );
    final int? thoughtsTokens = _readIntField(
      usageMetadata,
      const <String>[
        'thoughts_token_count',
        'thoughtsTokenCount',
        'reasoning_tokens',
        'reasoningTokens',
      ],
    );
    final int? cachedTokens = _readIntField(
      usageMetadata,
      const <String>['cached_content_token_count', 'cachedContentTokenCount'],
    );
    final int? metadataCacheWriteTokens = _readIntField(
      usageMetadata,
      const <String>[
        'cache_creation_input_tokens',
        'cacheCreationInputTokens',
      ],
    );

    final List<ModalityTokenUsage> promptByModality = _extractModalityTokens(
      _readObjectField(
        usageMetadata,
        const <String>['prompt_tokens_details', 'promptTokensDetails'],
      ),
    );
    final List<ModalityTokenUsage> cacheReadByModality = _extractModalityTokens(
      _readObjectField(
        usageMetadata,
        const <String>['cache_tokens_details', 'cacheTokensDetails'],
      ),
    );
    final List<ModalityTokenUsage> toolByModality = _extractModalityTokens(
      _readObjectField(
        usageMetadata,
        const <String>[
          'tool_use_prompt_tokens_details',
          'toolUsePromptTokensDetails',
        ],
      ),
    );
    final List<ModalityTokenUsage> outputByModality = _extractModalityTokens(
      _readObjectField(
        usageMetadata,
        const <String>['candidates_tokens_details', 'candidatesTokensDetails'],
      ),
    );

    final Map<String, int> inputTotals = <String, int>{
      for (final ModalityTokenUsage item in promptByModality)
        item.modality: item.tokenCount,
    };
    for (final ModalityTokenUsage item in toolByModality) {
      inputTotals[item.modality] =
          (inputTotals[item.modality] ?? 0) + item.tokenCount;
    }
    final List<ModalityTokenUsage> inputByModality = <ModalityTokenUsage>[
      for (final MapEntry<String, int> entry in inputTotals.entries)
        ModalityTokenUsage(entry.key, entry.value),
    ];

    return TokenUsage(
      inputTokens: promptTokens == null && toolTokens == null
          ? null
          : (promptTokens ?? 0) + (toolTokens ?? 0),
      outputTokens: candidatesTokens == null && thoughtsTokens == null
          ? null
          : (candidatesTokens ?? 0) + (thoughtsTokens ?? 0),
      cacheReadInputTokens: cachedTokens,
      cacheWriteInputTokens: cacheWriteInputTokens ?? metadataCacheWriteTokens,
      reasoningOutputTokens: thoughtsTokens,
      toolInputTokens: toolTokens,
      promptInputTokens: promptTokens,
      candidateOutputTokens: candidatesTokens,
      inputTokensByModality: List<ModalityTokenUsage>.unmodifiable(
        inputByModality,
      ),
      cacheReadInputTokensByModality: List<ModalityTokenUsage>.unmodifiable(
        cacheReadByModality,
      ),
      toolInputTokensByModality: List<ModalityTokenUsage>.unmodifiable(
        toolByModality,
      ),
      outputTokensByModality: List<ModalityTokenUsage>.unmodifiable(
        outputByModality,
      ),
    );
  }

  /// Extracts cumulative [TokenUsage] from [responses], preserving earlier
  /// usage when a trailing response has none.
  static TokenUsage? fromLlmResponses(List<LlmResponse> responses) {
    final List<Object> reported = <Object>[
      for (final LlmResponse response in responses)
        if (response.usageMetadata != null) response.usageMetadata!,
    ];
    final int? cacheWriteTokens = _extractCacheWriteInputTokens(responses);
    if (reported.isEmpty) {
      if (cacheWriteTokens != null) {
        return TokenUsage(cacheWriteInputTokens: cacheWriteTokens);
      }
      return null;
    }
    final TokenUsage usage = fromUsageMetadata(
      reported.last,
      cacheWriteInputTokens: cacheWriteTokens,
    );
    if (usage.inputTokens == null &&
        usage.outputTokens == null &&
        usage.cacheWriteInputTokens == null) {
      return null;
    }
    return usage;
  }
}

int? _extractCacheWriteInputTokens(List<LlmResponse> responses) {
  for (final LlmResponse response in responses) {
    final Object? cacheMeta = response.cacheMetadata;
    final Object? usageMeta = response.usageMetadata;
    if (cacheMeta is CacheMetadata &&
        cacheMeta.cacheName != null &&
        cacheMeta.invocationsUsed == 0 &&
        usageMeta != null) {
      final int? promptTokens = _readIntField(
        usageMeta,
        const <String>['prompt_token_count', 'promptTokenCount'],
      );
      if (promptTokens != null && promptTokens > 0) {
        return promptTokens;
      }
    }
  }
  return null;
}

List<ModalityTokenUsage> _extractModalityTokens(Object? details) {
  if (details is! Iterable) {
    return const <ModalityTokenUsage>[];
  }
  final Map<String, int> totals = <String, int>{};
  for (final Object? item in details) {
    if (item == null) {
      continue;
    }
    final String? modality = _normalizeModalityName(_readModalityField(item));
    final int? tokenCount = _readIntField(
      item,
      const <String>['token_count', 'tokenCount'],
    );
    if (modality == null || tokenCount == null || tokenCount <= 0) {
      continue;
    }
    totals[modality] = (totals[modality] ?? 0) + tokenCount;
  }
  return <ModalityTokenUsage>[
    for (final MapEntry<String, int> entry in totals.entries)
      ModalityTokenUsage(entry.key, entry.value),
  ];
}

String? _normalizeModalityName(Object? rawModality) {
  if (rawModality == null) {
    return null;
  }
  String value;
  if (rawModality is Enum) {
    value = rawModality.name;
  } else {
    value = '$rawModality';
    if (value.contains('.')) {
      value = value.split('.').last;
    }
  }
  value = value.trim().toLowerCase();
  if (value.isEmpty || value == 'modality_unspecified') {
    return null;
  }
  return value;
}

/// Last `opentelemetry-instrumentation-google-genai` version that did not emit
/// `gen_ai.client.token.usage` metrics on its own.
const String lastInstrumentorWithoutInferenceTokenMetrics = '0.7b2';

int _compareInstrumentorVersions(String a, String b) {
  final RegExp tokenRe = RegExp(r'(\d+|[a-zA-Z]+)');
  final List<String> partsA = tokenRe
      .allMatches(a.trim().toLowerCase())
      .map((RegExpMatch m) => m.group(0)!)
      .toList(growable: false);
  final List<String> partsB = tokenRe
      .allMatches(b.trim().toLowerCase())
      .map((RegExpMatch m) => m.group(0)!)
      .toList(growable: false);
  final int maxLen = partsA.length > partsB.length
      ? partsA.length
      : partsB.length;
  for (int i = 0; i < maxLen; i += 1) {
    final String? pa = i < partsA.length ? partsA[i] : null;
    final String? pb = i < partsB.length ? partsB[i] : null;
    if (pa == pb) {
      continue;
    }
    final int? na = pa == null ? null : int.tryParse(pa);
    final int? nb = pb == null ? null : int.tryParse(pb);
    if (na != null && nb != null) {
      return na.compareTo(nb);
    }
    if (pa == null) {
      // If `b` has a pre-release tag (e.g. `b`, `rc`, `a`) after identical numbers,
      // then `a` (final release) is greater than `b`.
      if (nb == null) {
        return 1;
      }
      return (0).compareTo(nb);
    }
    if (pb == null) {
      if (na == null) {
        return -1;
      }
      return na.compareTo(0);
    }
    if (na != null && nb == null) {
      return 1;
    }
    if (na == null && nb != null) {
      return -1;
    }
    final int cmp = pa.compareTo(pb);
    if (cmp != 0) {
      return cmp;
    }
  }
  return 0;
}

bool _instrumentorEmitsInferenceTokenMetrics({
  required bool hasGenAiInstrumentor,
  String? instrumentorVersion,
  required Map<String, String> env,
}) {
  if (!hasGenAiInstrumentor) {
    return false;
  }
  final String? version =
      (instrumentorVersion ??
              env['OTEL_INSTRUMENTATION_GOOGLE_GENAI_VERSION'] ??
              env['ADK_GOOGLE_GENAI_INSTRUMENTOR_VERSION'])
          ?.trim();
  if (version == null || version.isEmpty) {
    return true;
  }
  return _compareInstrumentorVersions(
        version,
        lastInstrumentorWithoutInferenceTokenMetrics,
      ) >
      0;
}

/// Whether ADK should emit `gen_ai.client.token.usage` metrics.
///
/// Under `ADK_GOOGLE_GENAI_INSTRUMENTOR_SCHEMA_VERSION=v1`, when an external
/// Google GenAI OpenTelemetry instrumentor (version > `0.7b2`) is active for
/// Gemini/Vertex AI, token metrics are skipped to avoid duplicate emission.
/// Under schema `v2` (the default), or when the instrumentor version is `<= 0.7b2`,
/// ADK emits inference token metrics.
bool shouldEmitInferenceTokenMetrics({
  String? system,
  bool? hasGenAiInstrumentor,
  String? instrumentorVersion,
  Map<String, String>? environment,
}) {
  final Map<String, String> env = environment ?? _safeMetricsEnvironment;
  final String schemaVersion =
      (env['ADK_GOOGLE_GENAI_INSTRUMENTOR_SCHEMA_VERSION'] ?? 'v2')
          .trim()
          .toLowerCase();
  final bool isGoogleGenAiSystem =
      system == 'gcp.gemini' ||
      system == 'gcp.vertex_ai' ||
      system == 'gcp.vertex.agent';
  if (isGoogleGenAiSystem &&
      _instrumentorEmitsInferenceTokenMetrics(
        hasGenAiInstrumentor: hasGenAiInstrumentor ?? false,
        instrumentorVersion: instrumentorVersion,
        env: env,
      ) &&
      schemaVersion == 'v1') {
    return false;
  }
  return true;
}

/// Records semconv-genai inference token usage samples from [tokenUsage],
/// including detail and modality breakdowns, and optional [error] attributes
/// for failed inference calls.
void recordInferenceTokenUsage({
  required TokenUsage? tokenUsage,
  String? agentName,
  String operationName = 'generate_content',
  String? requestModel,
  String? responseModel,
  String? system,
  String? serverAddress,
  int? serverPort,
  List<String>? finishReasons,
  Object? error,
  AdkMetricsRecorder? recorder,
}) {
  if (tokenUsage == null) {
    return;
  }
  final Map<String, Object?> baseAttributes = <String, Object?>{
    if (agentName != null && agentName.isNotEmpty)
      'gen_ai.agent.name': agentName,
    'gen_ai.operation.name': operationName,
    if (requestModel != null && requestModel.isNotEmpty)
      'gen_ai.request.model': requestModel,
    if (responseModel != null && responseModel.isNotEmpty)
      'gen_ai.response.model': responseModel,
    if (system != null && system.isNotEmpty) 'gen_ai.system': system,
    if (serverAddress != null && serverAddress.isNotEmpty)
      'server.address': serverAddress,
    'server.port': ?serverPort,
    if (finishReasons != null && finishReasons.isNotEmpty)
      'gen_ai.response.finish_reasons': List<String>.unmodifiable(
        finishReasons,
      ),
    if (error != null)
      'error.type': error is String ? error : error.runtimeType.toString(),
  };

  void emitTokenSample(
    int? count, {
    required String tokenType,
    String? detail,
    String? modality,
  }) {
    if (count == null || count <= 0) {
      return;
    }
    _record(
      recorder,
      AdkMetricRecord(
        name: genAiClientTokenUsageMetric,
        value: count,
        unit: '{token}',
        description: 'Number of input and output tokens used.',
        attributes: <String, Object?>{
          ...baseAttributes,
          'gen_ai.token.type': tokenType,
          'gen_ai.token.type.detail': ?detail,
          'gen_ai.Usage.experimental.modality': ?modality,
        },
        explicitBucketBoundariesAdvisory: tokenUsageBucketBounds,
      ),
    );
  }

  emitTokenSample(tokenUsage.inputTokens, tokenType: 'input');
  for (final ModalityTokenUsage item in tokenUsage.inputTokensByModality) {
    emitTokenSample(
      item.tokenCount,
      tokenType: 'input',
      modality: item.modality,
    );
  }

  emitTokenSample(
    tokenUsage.cacheReadInputTokens,
    tokenType: 'input',
    detail: 'cache_read',
  );
  for (final ModalityTokenUsage item
      in tokenUsage.cacheReadInputTokensByModality) {
    emitTokenSample(
      item.tokenCount,
      tokenType: 'input',
      detail: 'cache_read',
      modality: item.modality,
    );
  }

  emitTokenSample(
    tokenUsage.cacheWriteInputTokens,
    tokenType: 'input',
    detail: 'cache_write',
  );

  emitTokenSample(
    tokenUsage.toolInputTokens,
    tokenType: 'input',
    detail: 'tool',
  );
  for (final ModalityTokenUsage item in tokenUsage.toolInputTokensByModality) {
    emitTokenSample(
      item.tokenCount,
      tokenType: 'input',
      detail: 'tool',
      modality: item.modality,
    );
  }

  emitTokenSample(tokenUsage.outputTokens, tokenType: 'output');
  for (final ModalityTokenUsage item in tokenUsage.outputTokensByModality) {
    emitTokenSample(
      item.tokenCount,
      tokenType: 'output',
      modality: item.modality,
    );
  }

  emitTokenSample(
    tokenUsage.reasoningOutputTokens,
    tokenType: 'output',
    detail: 'reasoning',
  );
}

/// Records client token usage metrics from [responses], keeping usage from
/// earlier responses when the final response carries none.
void recordClientTokenUsage({
  required String agentName,
  required LlmRequest llmRequest,
  required List<LlmResponse> responses,
  String? system,
  String? serverAddress,
  int? serverPort,
  Object? error,
  AdkMetricsRecorder? recorder,
}) {
  if (responses.isEmpty) {
    return;
  }
  final TokenUsage? tokenUsage = TokenUsage.fromLlmResponses(responses);
  if (tokenUsage == null) {
    return;
  }

  String? responseModel;
  final List<String> finishReasons = <String>[];
  for (final LlmResponse response in responses) {
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

  recordInferenceTokenUsage(
    tokenUsage: tokenUsage,
    agentName: agentName,
    requestModel: llmRequest.model,
    responseModel: responseModel,
    system: system,
    serverAddress: serverAddress,
    serverPort: serverPort,
    finishReasons: finishReasons.isEmpty ? null : finishReasons,
    error: error,
    recorder: recorder,
  );
}

int? _readIntField(Object source, List<String> keys) {
  if (source is Map) {
    for (final String key in keys) {
      final Object? value = source[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
    }
    return null;
  }
  final dynamic dyn = source;
  for (final String key in keys) {
    try {
      Object? value;
      switch (key) {
        case 'prompt_token_count':
          value = dyn.prompt_token_count;
        case 'promptTokenCount':
          value = dyn.promptTokenCount;
        case 'tool_use_prompt_token_count':
          value = dyn.tool_use_prompt_token_count;
        case 'toolUsePromptTokenCount':
          value = dyn.toolUsePromptTokenCount;
        case 'candidates_token_count':
          value = dyn.candidates_token_count;
        case 'candidatesTokenCount':
          value = dyn.candidatesTokenCount;
        case 'thoughts_token_count':
          value = dyn.thoughts_token_count;
        case 'thoughtsTokenCount':
          value = dyn.thoughtsTokenCount;
        case 'reasoning_tokens':
          value = dyn.reasoning_tokens;
        case 'reasoningTokens':
          value = dyn.reasoningTokens;
        case 'cached_content_token_count':
          value = dyn.cached_content_token_count;
        case 'cachedContentTokenCount':
          value = dyn.cachedContentTokenCount;
        case 'cache_creation_input_tokens':
          value = dyn.cache_creation_input_tokens;
        case 'cacheCreationInputTokens':
          value = dyn.cacheCreationInputTokens;
        case 'token_count':
          value = dyn.token_count;
        case 'tokenCount':
          value = dyn.tokenCount;
      }
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
    } catch (_) {}
  }
  return null;
}

Object? _readObjectField(Object source, List<String> keys) {
  if (source is Map) {
    for (final String key in keys) {
      if (source.containsKey(key)) {
        return source[key];
      }
    }
    return null;
  }
  final dynamic dyn = source;
  for (final String key in keys) {
    try {
      switch (key) {
        case 'prompt_tokens_details':
          return dyn.prompt_tokens_details;
        case 'promptTokensDetails':
          return dyn.promptTokensDetails;
        case 'cache_tokens_details':
          return dyn.cache_tokens_details;
        case 'cacheTokensDetails':
          return dyn.cacheTokensDetails;
        case 'tool_use_prompt_tokens_details':
          return dyn.tool_use_prompt_tokens_details;
        case 'toolUsePromptTokensDetails':
          return dyn.toolUsePromptTokensDetails;
        case 'candidates_tokens_details':
          return dyn.candidates_tokens_details;
        case 'candidatesTokensDetails':
          return dyn.candidatesTokensDetails;
      }
    } catch (_) {}
  }
  return null;
}

Object? _readModalityField(Object source) {
  if (source is Map) {
    return source['modality'];
  }
  try {
    return (source as dynamic).modality;
  } catch (_) {
    return null;
  }
}

Map<String, String> get _safeMetricsEnvironment {
  try {
    return readSystemEnvironment();
  } catch (_) {
    return const <String, String>{};
  }
}

void _record(AdkMetricsRecorder? recorder, AdkMetricRecord metric) {
  (recorder ?? _globalAdkMetricsRecorder).record(metric);
}

Map<String, Object?> _agentAttributes(String agentName, {Object? error}) {
  return <String, Object?>{
    'gen_ai.agent.name': agentName,
    if (error != null) 'error.type': error.runtimeType.toString(),
  };
}

Map<String, Object?> _toolAttributes(
  String toolName,
  String agentName, {
  Object? error,
}) {
  return <String, Object?>{
    'gen_ai.agent.name': agentName,
    'gen_ai.tool.name': toolName,
    if (error != null) 'error.type': error.runtimeType.toString(),
  };
}
