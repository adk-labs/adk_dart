/// OpenTelemetry-compatible ADK metric recording helpers.
library;

import 'dart:convert';

import '../events/event.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../types/content.dart';

/// Metric name for client token usage.
const String genAiClientTokenUsageMetric = 'gen_ai.client.token.usage';

/// Metric name for agent invocation durations.
const String genAiAgentInvocationDurationMetric =
    'gen_ai.agent.invocation.duration';

/// Metric name for tool execution durations.
const String genAiToolExecutionDurationMetric =
    'gen_ai.tool.execution.duration';

/// Metric name for agent request sizes.
const String genAiAgentRequestSizeMetric = 'gen_ai.agent.request.size';

/// Metric name for agent response sizes.
const String genAiAgentResponseSizeMetric = 'gen_ai.agent.response.size';

/// Metric name for tool request sizes.
const String genAiToolRequestSizeMetric = 'gen_ai.tool.request.size';

/// Metric name for tool response sizes.
const String genAiToolResponseSizeMetric = 'gen_ai.tool.response.size';

/// One ADK metric sample.
class AdkMetricRecord {
  /// Creates a metric sample with [name], [value], [unit], and [attributes].
  AdkMetricRecord({
    required this.name,
    required this.value,
    required this.unit,
    required this.description,
    Map<String, Object?>? attributes,
  }) : attributes = Map<String, Object?>.unmodifiable(
         attributes ?? const <String, Object?>{},
       );

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

/// Aggregated token usage extracted from one or more LLM responses.
class TokenUsage {
  /// Creates a token usage summary.
  const TokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.cacheReadInputTokens,
    this.reasoningOutputTokens,
    this.toolInputTokens,
    this.promptInputTokens,
    this.candidateOutputTokens,
  });

  /// Total input tokens (prompt + tool input tokens).
  final int? inputTokens;

  /// Total output tokens (candidate + reasoning output tokens).
  final int? outputTokens;

  /// Cached content input tokens.
  final int? cacheReadInputTokens;

  /// Reasoning (thoughts) output tokens.
  final int? reasoningOutputTokens;

  /// Server-side tool use prompt input tokens.
  final int? toolInputTokens;

  /// Prompt input tokens.
  final int? promptInputTokens;

  /// Candidate output tokens.
  final int? candidateOutputTokens;

  /// Total derived tokens (`(inputTokens ?? 0) + (outputTokens ?? 0)`).
  int get totalTokens => (inputTokens ?? 0) + (outputTokens ?? 0);

  /// Extracts [TokenUsage] from a raw [usageMetadata] map or object.
  static TokenUsage fromUsageMetadata(Object? usageMetadata) {
    if (usageMetadata == null) {
      return const TokenUsage();
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

    return TokenUsage(
      inputTokens: promptTokens == null && toolTokens == null
          ? null
          : (promptTokens ?? 0) + (toolTokens ?? 0),
      outputTokens: candidatesTokens == null && thoughtsTokens == null
          ? null
          : (candidatesTokens ?? 0) + (thoughtsTokens ?? 0),
      cacheReadInputTokens: cachedTokens,
      reasoningOutputTokens: thoughtsTokens,
      toolInputTokens: toolTokens,
      promptInputTokens: promptTokens,
      candidateOutputTokens: candidatesTokens,
    );
  }

  /// Extracts cumulative [TokenUsage] from [responses], preserving earlier
  /// usage when a trailing response has none.
  static TokenUsage? fromLlmResponses(List<LlmResponse> responses) {
    final List<Object> reported = <Object>[
      for (final LlmResponse response in responses)
        if (response.usageMetadata != null) response.usageMetadata!,
    ];
    if (reported.isEmpty) {
      return null;
    }
    final TokenUsage usage = fromUsageMetadata(reported.last);
    if (usage.inputTokens == null && usage.outputTokens == null) {
      return null;
    }
    return usage;
  }
}

/// Records client token usage metrics from [responses], keeping usage from
/// earlier responses when the final response carries none.
void recordClientTokenUsage({
  required String agentName,
  required LlmRequest llmRequest,
  required List<LlmResponse> responses,
  AdkMetricsRecorder? recorder,
}) {
  if (responses.isEmpty) {
    return;
  }
  final TokenUsage? tokenUsage = TokenUsage.fromLlmResponses(responses);
  if (tokenUsage == null) {
    return;
  }

  final int inputTokenCount = tokenUsage.inputTokens ?? 0;
  final int outputTokenCount = tokenUsage.outputTokens ?? 0;
  final String? responseModel =
      responses.last.modelVersion ?? llmRequest.model;
  final Map<String, Object?> baseAttributes = <String, Object?>{
    'gen_ai.agent.name': agentName,
    'gen_ai.operation.name': 'generate_content',
    if (llmRequest.model != null && llmRequest.model!.isNotEmpty)
      'gen_ai.request.model': llmRequest.model,
    if (responseModel != null && responseModel.isNotEmpty)
      'gen_ai.response.model': responseModel,
  };

  if (inputTokenCount > 0) {
    _record(
      recorder,
      AdkMetricRecord(
        name: genAiClientTokenUsageMetric,
        value: inputTokenCount,
        unit: '{token}',
        description: 'Number of input and output tokens used.',
        attributes: <String, Object?>{
          ...baseAttributes,
          'gen_ai.token.type': 'input',
        },
      ),
    );
  }

  if (outputTokenCount > 0) {
    _record(
      recorder,
      AdkMetricRecord(
        name: genAiClientTokenUsageMetric,
        value: outputTokenCount,
        unit: '{token}',
        description: 'Number of input and output tokens used.',
        attributes: <String, Object?>{
          ...baseAttributes,
          'gen_ai.token.type': 'output',
        },
      ),
    );
  }
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
