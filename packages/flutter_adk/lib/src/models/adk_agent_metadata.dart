import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

/// Operational lifecycle status of a managed agent.
enum AdkAgentStatus {
  /// Agent is ready and awaiting instructions.
  idle,

  /// Agent is actively processing or generating a turn.
  busy,

  /// Agent is temporarily disabled.
  disabled,

  /// Agent encountered an unhandled execution error.
  error,
}

/// Execution telemetry and performance metrics for a managed agent.
@immutable
class AdkAgentMetrics {
  /// Creates an [AdkAgentMetrics].
  const AdkAgentMetrics({
    this.totalInvocations = 0,
    this.totalTokens = 0,
    this.errorCount = 0,
    this.totalLatencyMs = 0.0,
    this.lastActiveAt,
  });

  /// Total number of turns / runs executed by this agent.
  final int totalInvocations;

  /// Total cumulative tokens consumed.
  final int totalTokens;

  /// Total number of failed execution turns.
  final int errorCount;

  /// Cumulative execution latency in milliseconds.
  final double totalLatencyMs;

  /// Timestamp of the latest execution turn.
  final DateTime? lastActiveAt;

  /// Average latency per turn in milliseconds.
  double get avgLatencyMs =>
      totalInvocations == 0 ? 0.0 : totalLatencyMs / totalInvocations;

  /// Copies this [AdkAgentMetrics] with updated metrics.
  AdkAgentMetrics copyWith({
    int? totalInvocations,
    int? totalTokens,
    int? errorCount,
    double? totalLatencyMs,
    DateTime? lastActiveAt,
  }) {
    return AdkAgentMetrics(
      totalInvocations: totalInvocations ?? this.totalInvocations,
      totalTokens: totalTokens ?? this.totalTokens,
      errorCount: errorCount ?? this.errorCount,
      totalLatencyMs: totalLatencyMs ?? this.totalLatencyMs,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }
}

/// Rich metadata, configuration, and state descriptor for an ADK agent in the management registry.
@immutable
class AdkAgentMetadata {
  /// Creates an [AdkAgentMetadata].
  const AdkAgentMetadata({
    required this.id,
    required this.name,
    required this.agent,
    this.description = '',
    this.model = 'gemini-3.7-flash',
    this.instruction = '',
    this.status = .idle,
    this.isEnabled = true,
    this.toolsCount = 0,
    this.subAgentsCount = 0,
    this.metrics = const AdkAgentMetrics(),
    this.tags = const <String>[],
  });

  /// Unique agent identifier.
  final String id;

  /// Human-readable display name.
  final String name;

  /// The underlying ADK runtime agent instance.
  final adk.BaseAgent agent;

  /// Description of the agent's role and capabilities.
  final String description;

  /// Primary LLM model configured for this agent.
  final String model;

  /// System instructions / prompt.
  final String instruction;

  /// Current lifecycle status.
  final AdkAgentStatus status;

  /// Whether this agent is enabled for execution and delegation.
  final bool isEnabled;

  /// Number of tools registered to this agent.
  final int toolsCount;

  /// Number of sub-agents orchestrated by this agent.
  final int subAgentsCount;

  /// Telemetry and invocation metrics.
  final AdkAgentMetrics metrics;

  /// Categorical tags (e.g. `coding`, `research`, `customer_support`).
  final List<String> tags;

  /// Copies this [AdkAgentMetadata] with updated properties.
  AdkAgentMetadata copyWith({
    String? id,
    String? name,
    adk.BaseAgent? agent,
    String? description,
    String? model,
    String? instruction,
    AdkAgentStatus? status,
    bool? isEnabled,
    int? toolsCount,
    int? subAgentsCount,
    AdkAgentMetrics? metrics,
    List<String>? tags,
  }) {
    return AdkAgentMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      agent: agent ?? this.agent,
      description: description ?? this.description,
      model: model ?? this.model,
      instruction: instruction ?? this.instruction,
      status: status ?? this.status,
      isEnabled: isEnabled ?? this.isEnabled,
      toolsCount: toolsCount ?? this.toolsCount,
      subAgentsCount: subAgentsCount ?? this.subAgentsCount,
      metrics: metrics ?? this.metrics,
      tags: tags ?? this.tags,
    );
  }
}
