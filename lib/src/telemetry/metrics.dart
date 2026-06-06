/// OpenTelemetry-compatible ADK metric recording helpers.
library;

import 'dart:convert';

import '../events/event.dart';
import '../types/content.dart';

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

/// Metric name for agent workflow step counts.
const String genAiAgentWorkflowStepsMetric = 'gen_ai.agent.workflow.steps';

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

/// Records the number of events authored by an agent.
void recordAgentWorkflowSteps(
  String agentName,
  List<Event> events, {
  AdkMetricsRecorder? recorder,
}) {
  final int count = events.where((Event event) {
    return event.author == agentName;
  }).length;
  _record(
    recorder,
    AdkMetricRecord(
      name: genAiAgentWorkflowStepsMetric,
      value: count,
      unit: '1',
      description: 'Length of agentic workflow (# of events).',
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
