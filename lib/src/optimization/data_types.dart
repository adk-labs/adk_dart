/// Data models used by optimizer sampling and ranking workflows.
library;

import '../agents/llm_agent.dart';

/// Holds metric scores produced by one optimizer sampling pass.
class BaseSamplingResult {
  /// Creates a sampling result with immutable [scores].
  BaseSamplingResult({required Map<String, double> scores})
    : scores = Map<String, double>.unmodifiable(scores);

  /// Parses one sampling result payload from JSON.
  ///
  /// Throws a [FormatException] when required fields (`scores`) are missing or
  /// malformed.
  factory BaseSamplingResult.fromJson(Map<String, Object?> json) {
    if (!json.containsKey('scores') || json['scores'] == null) {
      throw const FormatException('Missing required field: scores');
    }
    final Object? rawScores = json['scores'];
    if (rawScores is! Map) {
      throw const FormatException('Field "scores" must be a JSON object.');
    }
    final Map<String, double> parsedScores = <String, double>{};
    rawScores.forEach((Object? key, Object? value) {
      if (value is! num) {
        throw FormatException('Score for "$key" must be numeric.');
      }
      parsedScores['$key'] = value.toDouble();
    });
    return BaseSamplingResult(scores: parsedScores);
  }

  /// Metric scores keyed by metric name.
  final Map<String, double> scores;

  /// Serializes this sampling result to JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'scores': Map<String, double>.from(scores),
  };

  /// Standard JSON Schema for [BaseSamplingResult] / [SamplingResult].
  static Map<String, Object?> jsonSchema() {
    return <String, Object?>{
      'title': 'SamplingResult',
      'type': 'object',
      'properties': <String, Object?>{
        'scores': <String, Object?>{
          'title': 'Scores',
          'description':
              "A map from example UID to the agent's overall score on that example."
              ' (higher is better).',
          'type': 'object',
          'additionalProperties': <String, Object?>{'type': 'number'},
        },
      },
      'required': <String>['scores'],
    };
  }
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

  /// Parses one unstructured sampling result payload from JSON.
  factory UnstructuredSamplingResult.fromJson(Map<String, Object?> json) {
    final BaseSamplingResult base = BaseSamplingResult.fromJson(json);
    final Object? rawData = json['data'];
    Map<String, Map<String, Object?>>? parsedData;
    if (rawData != null) {
      if (rawData is! Map) {
        throw const FormatException('Field "data" must be a JSON object.');
      }
      parsedData = <String, Map<String, Object?>>{};
      rawData.forEach((Object? key, Object? value) {
        if (value is! Map) {
          throw FormatException('Data entry for "$key" must be a JSON object.');
        }
        parsedData!['$key'] = value.map(
          (Object? innerKey, Object? innerVal) =>
              MapEntry('$innerKey', innerVal),
        );
      });
    }
    return UnstructuredSamplingResult(scores: base.scores, data: parsedData);
  }

  /// Optional raw evaluator payloads keyed by metric name.
  final Map<String, Map<String, Object?>>? data;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...super.toJson(),
    if (data != null) 'data': data,
  };

  /// Standard JSON Schema for [UnstructuredSamplingResult].
  static Map<String, Object?> jsonSchema() {
    return <String, Object?>{
      'title': 'UnstructuredSamplingResult',
      'type': 'object',
      'properties': <String, Object?>{
        'scores': <String, Object?>{
          'title': 'Scores',
          'description':
              "A map from example UID to the agent's overall score on that example."
              ' (higher is better).',
          'type': 'object',
          'additionalProperties': <String, Object?>{'type': 'number'},
        },
        'data': <String, Object?>{
          'title': 'Data',
          'description':
              'A map from example UID to arbitrary additional information about'
              ' the agent execution on that example.',
          'anyOf': <Object?>[
            <String, Object?>{
              'type': 'object',
              'additionalProperties': <String, Object?>{'type': 'object'},
            },
            <String, Object?>{'type': 'null'},
          ],
          'default': null,
        },
      },
      'required': <String>['scores'],
    };
  }
}

/// Represents one optimized agent candidate with aggregate scoring.
class BaseAgentWithScores {
  /// Creates a scored optimized agent container.
  BaseAgentWithScores({required this.optimizedAgent, this.overallScore});

  /// Parses one scored agent payload from JSON.
  ///
  /// Throws a [FormatException] when required fields (`optimized_agent`) are
  /// missing or invalid.
  factory BaseAgentWithScores.fromJson(Map<String, Object?> json) {
    final Object? rawAgent =
        json.containsKey('optimized_agent') ? json['optimized_agent'] : json['optimizedAgent'];
    if (rawAgent == null) {
      throw const FormatException('Missing required field: optimized_agent');
    }
    if (rawAgent is! Agent) {
      throw const FormatException(
        'Field "optimized_agent" must be an Agent instance.',
      );
    }
    final Object? rawOverallScore = json.containsKey('overall_score')
        ? json['overall_score']
        : json['overallScore'];
    if (rawOverallScore != null && rawOverallScore is! num) {
      throw const FormatException('Field "overall_score" must be numeric.');
    }
    return BaseAgentWithScores(
      optimizedAgent: rawAgent,
      overallScore: (rawOverallScore as num?)?.toDouble(),
    );
  }

  /// Optimized agent candidate.
  final Agent optimizedAgent;

  /// Optional aggregate score across validation metrics.
  final double? overallScore;

  /// Standard JSON Schema for [BaseAgentWithScores] / [AgentWithScores].
  static Map<String, Object?> jsonSchema() {
    return <String, Object?>{
      'title': 'AgentWithScores',
      'type': 'object',
      'properties': <String, Object?>{
        'optimized_agent': <String, Object?>{
          'title': 'Optimized Agent',
          'description': 'The optimized agent.',
          'type': 'object',
        },
        'overall_score': <String, Object?>{
          'title': 'Overall Score',
          'description':
              'The overall score of the optimized agent on the full validation'
              ' set, if scored.',
          'anyOf': <Object?>[
            <String, Object?>{'type': 'number'},
            <String, Object?>{'type': 'null'},
          ],
          'default': null,
        },
      },
      'required': <String>['optimized_agent'],
    };
  }
}

/// Alias for [BaseAgentWithScores] matching the ADK Python `AgentWithScores` type.
typedef AgentWithScores = BaseAgentWithScores;

/// Wraps optimizer output candidates.
class OptimizerResult<T extends BaseAgentWithScores> {
  /// Creates an immutable optimizer result.
  OptimizerResult({required List<T> optimizedAgents})
    : optimizedAgents = List<T>.unmodifiable(optimizedAgents);

  /// Parses one optimizer result payload from JSON.
  ///
  /// Throws a [FormatException] when required fields (`optimized_agents`) are
  /// missing or invalid.
  factory OptimizerResult.fromJson(
    Map<String, Object?> json, {
    T Function(Map<String, Object?>)? itemFromJson,
  }) {
    final Object? rawAgents = json.containsKey('optimized_agents')
        ? json['optimized_agents']
        : json['optimizedAgents'];
    if (rawAgents == null) {
      throw const FormatException('Missing required field: optimized_agents');
    }
    if (rawAgents is! List) {
      throw const FormatException('Field "optimized_agents" must be a list.');
    }
    final List<T> parsed = <T>[];
    for (final Object? entry in rawAgents) {
      if (entry is T) {
        parsed.add(entry);
      } else if (entry is Map) {
        final Map<String, Object?> map = entry.map(
          (Object? k, Object? v) => MapEntry('$k', v),
        );
        if (itemFromJson != null) {
          parsed.add(itemFromJson(map));
        } else {
          parsed.add(BaseAgentWithScores.fromJson(map) as T);
        }
      } else {
        throw const FormatException(
          'Each entry in "optimized_agents" must be an AgentWithScores.',
        );
      }
    }
    return OptimizerResult<T>(optimizedAgents: parsed);
  }

  /// Optimized candidates in ranking order determined by the optimizer.
  final List<T> optimizedAgents;

  /// Standard JSON Schema for [OptimizerResult].
  static Map<String, Object?> jsonSchema() {
    return <String, Object?>{
      'title': 'OptimizerResult',
      'type': 'object',
      'properties': <String, Object?>{
        'optimized_agents': <String, Object?>{
          'title': 'Optimized Agents',
          'description':
              'A list of optimized agents which cannot be considered strictly'
              ' better than one another.',
          'type': 'array',
          'items': BaseAgentWithScores.jsonSchema(),
        },
      },
      'required': <String>['optimized_agents'],
    };
  }
}
