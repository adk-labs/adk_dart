import '../agents/llm_agent.dart';

class BaseSamplingResult {
  BaseSamplingResult({required Map<String, double> scores})
    : scores = Map<String, double>.unmodifiable(scores);

  final Map<String, double> scores;
}

class UnstructuredSamplingResult extends BaseSamplingResult {
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

  final Map<String, Map<String, Object?>>? data;
}

class BaseAgentWithScores {
  BaseAgentWithScores({required this.optimizedAgent, this.overallScore});

  final Agent optimizedAgent;
  final double? overallScore;
}

class OptimizerResult<T extends BaseAgentWithScores> {
  OptimizerResult({required List<T> optimizedAgents})
    : optimizedAgents = List<T>.unmodifiable(optimizedAgents);

  final List<T> optimizedAgents;
}
