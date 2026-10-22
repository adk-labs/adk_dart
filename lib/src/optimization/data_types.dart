/// Data models used by optimizer sampling and ranking workflows.
library;

import '../agents/llm_agent.dart';

/// Holds metric scores produced by one optimizer sampling pass.
class BaseSamplingResult {
  /// Creates a sampling result with immutable [scores].
  BaseSamplingResult({required Map<String, double> scores})
    : scores = Map<String, double>.unmodifiable(scores);

  /// Metric scores keyed by metric name.
  final Map<String, double> scores;
}

/// Alias for [BaseSamplingResult] matching the ADK Python `SamplingResult` type.
typedef SamplingResult = BaseSamplingResult;

/// Sampling result that also carries optional per-metric structured payloads.
class UnstructuredSamplingResult extends BaseSamplingResult {
  /// Creates an unstructured sampling result.
  UnstructuredSamplingResult({
    required super.scores,
    Map<String, Map<String, Object?>>? data,
  }) : data = data == null
           ? null
           : Map<String, Map<String, Object?>>.unmodifiable(
               data.map(
                 (String key, Map<String, Object?> value) =>
                     MapEntry(key, Map<String, Object?>.unmodifiable(value)),
               ),
             );

  /// Optional raw evaluator payloads keyed by metric name.
  final Map<String, Map<String, Object?>>? data;
}

/// Represents one optimized agent candidate with aggregate scoring.
class BaseAgentWithScores {
  /// Creates a scored optimized agent container.
  BaseAgentWithScores({required this.optimizedAgent, this.overallScore});

  /// Optimized agent candidate.
  final Agent optimizedAgent;

  /// Optional aggregate score across validation metrics.
  final double? overallScore;
}

/// Alias for [BaseAgentWithScores] matching the ADK Python `AgentWithScores` type.
typedef AgentWithScores = BaseAgentWithScores;

/// Wraps optimizer output candidates.
class OptimizerResult<T extends BaseAgentWithScores> {
  /// Creates an immutable optimizer result.
  OptimizerResult({required List<T> optimizedAgents})
    : optimizedAgents = List<T>.unmodifiable(optimizedAgents);

  /// Optimized candidates in ranking order determined by the optimizer.
  final List<T> optimizedAgents;
}
