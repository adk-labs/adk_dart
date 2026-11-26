/// Multi-objective grid search over agent settings.
library;

import 'dart:developer' as developer;
import 'dart:math' as math;

import '../agents/base_agent.dart';
import '../agents/llm_agent.dart';
import '../evaluation/efficiency_evaluators.dart';
import '../evaluation/eval_metrics.dart';
import '../features/_feature_decorator.dart';
import '../features/_feature_registry.dart';
import 'agent_optimizer.dart';
import 'agent_tree_cloner.dart';
import 'data_types.dart';
import 'sampler.dart';

// Must match evaluation.eval_metrics and evaluation.efficiency_evaluators.
const String _tokenMetric = 'token_usage_v1';
const String _durationMetric = 'invocation_duration_v1';
const Set<String> _efficiencyMetrics = <String>{
  _durationMetric,
  _tokenMetric,
  'tool_call_count_v1',
  'inference_call_count_v1',
};

// Field names follow ADK's TokenUsageDetails: input_tokens includes
// cached_tokens, output_tokens includes reasoning_tokens, and total_tokens is
// input_tokens + output_tokens.
const List<String> _tokenFields = <String>[
  'total_tokens',
  'input_tokens',
  'output_tokens',
  'cached_tokens',
  'reasoning_tokens',
];
const Set<String> _optionalTokenFields = <String>{
  'cached_tokens',
  'reasoning_tokens',
};
const int _maxLoggedParamsChars = 120;

/// Callback computing an example quality score from per-example metric scores.
typedef QualityMetricFn = num Function(Map<String, double> scores);

/// Warning emitter used by [GridSearchAgentOptimizer].
typedef GridSearchWarningEmitter = void Function(String message);

class _TokenCounts {
  const _TokenCounts({
    this.totalTokens,
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.reasoningTokens,
  });

  final double? totalTokens;
  final double? inputTokens;
  final double? outputTokens;
  final double? cachedTokens;
  final double? reasoningTokens;

  double? operator [](String field) {
    switch (field) {
      case 'total_tokens':
        return totalTokens;
      case 'input_tokens':
        return inputTokens;
      case 'output_tokens':
        return outputTokens;
      case 'cached_tokens':
        return cachedTokens;
      case 'reasoning_tokens':
        return reasoningTokens;
      default:
        return null;
    }
  }

  Map<String, double> toMap() {
    return <String, double>{
      'total_tokens': ?totalTokens,
      'input_tokens': ?inputTokens,
      'output_tokens': ?outputTokens,
      'cached_tokens': ?cachedTokens,
      'reasoning_tokens': ?reasoningTokens,
    };
  }
}

class _ExampleTelemetry {
  const _ExampleTelemetry({
    required this.metricScores,
    required this.metricNames,
    required this.latencySec,
    required this.tokens,
    this.hasInvocations = true,
  });

  final Map<String, double> metricScores;
  final Set<String> metricNames;
  final double? latencySec;
  final _TokenCounts? tokens;
  final bool hasInvocations;
}

/// A Pareto-optimal candidate agent with its quality and efficiency.
class GridSearchAgentWithScores implements ScoredAgentWithScores {
  /// Creates a scored Pareto-optimal candidate entry.
  GridSearchAgentWithScores({
    required this.optimizedAgent,
    this.overallScore = 0.0,
    Map<String, double>? evalCaseScores,
    Map<String, double>? tokenUsage,
    this.latencySec,
    Map<String, Object?>? metadata,
  }) : evalCaseScores = Map<String, double>.unmodifiable(
         evalCaseScores ?? const <String, double>{},
       ),
       tokenUsage = Map<String, double>.unmodifiable(
         tokenUsage ?? const <String, double>{},
       ),
       metadata = Map<String, Object?>.unmodifiable(
         metadata ?? const <String, Object?>{},
       );

  /// The optimized agent hierarchy.
  @override
  final BaseAgent optimizedAgent;

  /// Mean quality score over all evaluated examples.
  ///
  /// An example that could not be scored, for example because inference failed,
  /// counts as `0.0`.
  @override
  final double overallScore;

  /// Per-example quality scores keyed by example UID.
  final Map<String, double> evalCaseScores;

  /// Mean token counts per example when every example reported token usage,
  /// keyed by `TokenUsageDetails` field names (`total_tokens`, `input_tokens`,
  /// `output_tokens`, `cached_tokens`, `reasoning_tokens`).
  ///
  /// Empty when any example did not report token usage.
  final Map<String, double> tokenUsage;

  /// Mean turn duration in seconds, or `null` if not reported.
  final double? latencySec;

  /// Candidate hyperparameters and evaluation metadata.
  final Map<String, Object?> metadata;
}

/// Configuration for [GridSearchAgentOptimizer].
class GridSearchAgentOptimizerConfig {
  /// Creates a grid search optimizer configuration.
  ///
  /// [paramGrid] may be a `Map<String, Iterable<Object?>>` or a
  /// `List<Map<String, Iterable<Object?>>>` (conditional sub-grids).
  /// [qualityMetric] may be `null`, a `String` metric name, a
  /// `Map<String, num>` of metric weights, or a [QualityMetricFn].
  GridSearchAgentOptimizerConfig({
    required Object paramGrid,
    this.minQualityScore,
    this.maxLatencySec,
    this.maxTotalTokens,
    this.qualityMetric,
    this.exampleSet = ExampleSet.train,
    this.maxConcurrentCandidates = 4,
  }) : paramGrid = _validateAndNormalizeParamGrid(paramGrid) {
    if (minQualityScore != null && !minQualityScore!.isFinite) {
      throw ArgumentError.value(
        minQualityScore,
        'minQualityScore',
        'min_quality_score must be finite.',
      );
    }
    if (maxLatencySec != null &&
        (!maxLatencySec!.isFinite || maxLatencySec! < 0.0)) {
      throw ArgumentError.value(
        maxLatencySec,
        'maxLatencySec',
        'max_latency_sec must be finite and >= 0.0.',
      );
    }
    if (maxTotalTokens != null && maxTotalTokens! < 0) {
      throw ArgumentError.value(
        maxTotalTokens,
        'maxTotalTokens',
        'max_total_tokens must be >= 0.',
      );
    }
    if (maxConcurrentCandidates < 1) {
      throw ArgumentError.value(
        maxConcurrentCandidates,
        'maxConcurrentCandidates',
        'max_concurrent_candidates must be >= 1.',
      );
    }
    _validateQualityMetric(qualityMetric);
  }

  /// Normalized sequence of conditional parameter sub-grids.
  final List<Map<String, List<Object?>>> paramGrid;

  /// Optional minimum mean quality score for feasibility.
  final double? minQualityScore;

  /// Optional maximum latency for feasibility, in seconds per turn, averaged
  /// over turns and examples.
  final double? maxLatencySec;

  /// Optional maximum total tokens for feasibility, per example (summed over
  /// the conversation's turns), averaged over examples.
  final int? maxTotalTokens;

  /// How each example's quality score is computed.
  final Object? qualityMetric;

  /// Example split (`train` or `validation`) used for scoring.
  ///
  /// Falls back to the other split with a warning if the requested split has
  /// no examples.
  final ExampleSet exampleSet;

  /// Maximum number of candidates evaluated concurrently.
  final int maxConcurrentCandidates;

  static List<Map<String, List<Object?>>> _validateAndNormalizeParamGrid(
    Object paramGrid,
  ) {
    final List<Object?> rawSubGrids;
    if (paramGrid is Map) {
      rawSubGrids = <Object?>[paramGrid];
    } else if (paramGrid is Iterable) {
      rawSubGrids = paramGrid.toList(growable: false);
    } else {
      throw ArgumentError.value(
        paramGrid,
        'paramGrid',
        'param_grid must be a Map or a List of Maps.',
      );
    }

    if (rawSubGrids.isEmpty) {
      throw ArgumentError('param_grid has no sub-grids.');
    }

    final List<Map<String, List<Object?>>> normalized =
        <Map<String, List<Object?>>>[];
    for (final Object? rawGrid in rawSubGrids) {
      if (rawGrid is! Map) {
        throw ArgumentError.value(
          rawGrid,
          'paramGrid',
          'Each sub-grid in param_grid must be a Map.',
        );
      }
      if (rawGrid.isEmpty) {
        throw ArgumentError('param_grid contains an empty grid.');
      }
      final Map<String, List<Object?>> grid = <String, List<Object?>>{};
      for (final MapEntry<Object?, Object?> entry in rawGrid.entries) {
        final String path = '${entry.key}';
        final Object? values = entry.value;
        if (values is String) {
          throw ArgumentError(
            "param_grid['$path'] must be a list of values, not the string "
            "'$values'. Write ['$values'].",
          );
        }
        if (values is! Iterable) {
          throw ArgumentError(
            "param_grid['$path'] must be a list of values, got "
            '${values.runtimeType}.',
          );
        }
        final List<Object?> valueList = values.toList(growable: false);
        if (valueList.isEmpty) {
          throw ArgumentError("param_grid['$path'] has no values.");
        }
        grid[path] = valueList;
      }
      normalized.add(Map<String, List<Object?>>.unmodifiable(grid));
    }
    return List<Map<String, List<Object?>>>.unmodifiable(normalized);
  }

  static void _validateQualityMetric(Object? qualityMetric) {
    if (qualityMetric == null || qualityMetric is Function) {
      if (qualityMetric is Function && qualityMetric is! QualityMetricFn) {
        throw ArgumentError.value(
          qualityMetric,
          'qualityMetric',
          'quality_metric callable must accept Map<String, double> and return num.',
        );
      }
      return;
    }

    final Set<String> names;
    if (qualityMetric is String) {
      names = <String>{qualityMetric};
    } else if (qualityMetric is Map) {
      names = <String>{};
      final List<String> invalid = <String>[];
      for (final MapEntry<Object?, Object?> entry in qualityMetric.entries) {
        final String name = '${entry.key}';
        names.add(name);
        final Object? rawWeight = entry.value;
        if (rawWeight is! num ||
            !rawWeight.isFinite ||
            rawWeight.toDouble() < 0.0) {
          invalid.add(name);
        }
      }
      invalid.sort();
      if (invalid.isNotEmpty) {
        throw ArgumentError(
          'quality_metric gives $invalid invalid weights. Weights must be '
          'finite and non-negative so that 0, the score of an example that '
          'could not be scored, stays the lowest quality.',
        );
      }
    } else {
      throw ArgumentError(
        'Unsupported quality_metric type: ${qualityMetric.runtimeType}',
      );
    }

    final List<String> efficiency = names.intersection(_efficiencyMetrics).toList()
      ..sort();
    if (efficiency.isNotEmpty) {
      throw ArgumentError(
        'quality_metric names efficiency metrics $efficiency, which measure '
        'cost rather than quality. Token usage and latency are already Pareto '
        'objectives; limit them with max_total_tokens or max_latency_sec.',
      );
    }
  }
}

class _TrialResult {
  _TrialResult({
    required this.params,
    required this.agent,
    this.qualityScore = 0.0,
    Map<String, double>? evalCaseScores,
    this.latencySec,
    this.tokens,
    this.numCasesEvaluated = 0,
  }) : evalCaseScores = evalCaseScores ?? <String, double>{};

  final Map<String, Object?> params;
  final BaseAgent agent;
  final double qualityScore;
  final Map<String, double> evalCaseScores;
  final double? latencySec;
  final _TokenCounts? tokens;
  final int numCasesEvaluated;
  bool isFeasible = false;
}

List<Map<String, Object?>> _expandParamGrid(
  List<Map<String, List<Object?>>> subGrids,
) {
  final List<Map<String, Object?>> candidates = <Map<String, Object?>>[];
  for (final Map<String, List<Object?>> grid in subGrids) {
    final List<String> keys = grid.keys.toList(growable: false);
    final List<List<Object?>> valueLists = <List<Object?>>[
      for (final String key in keys) grid[key]!,
    ];
    void buildProduct(int depth, List<Object?> current) {
      if (depth == keys.length) {
        candidates.add(<String, Object?>{
          for (int i = 0; i < keys.length; i += 1) keys[i]: current[i],
        });
        return;
      }
      for (final Object? value in valueLists[depth]) {
        current.add(value);
        buildProduct(depth + 1, current);
        current.removeLast();
      }
    }

    buildProduct(0, <Object?>[]);
  }
  return candidates;
}

double? _finite(Object? value) {
  if (value is num) {
    final double number = value.toDouble();
    return number.isFinite ? number : null;
  }
  if (value is String) {
    final double? parsed = double.tryParse(value);
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

double _fsum(Iterable<double> values) {
  double sum = 0.0;
  for (final double v in values) {
    sum += v;
  }
  return sum;
}

double _fmean(List<double> values) {
  return _fsum(values) / values.length;
}

_TokenCounts? _parseTokenCounts(Object? details, Object? score) {
  Map<Object?, Object?>? detailsMap;
  if (details is Map) {
    detailsMap = details;
  } else if (details is TokenUsageDetails) {
    detailsMap = <String, Object?>{
      'total_tokens': ?details.totalTokens,
      'input_tokens': ?details.inputTokens,
      'output_tokens': ?details.outputTokens,
      'cached_tokens': ?details.cachedTokens,
      'reasoning_tokens': ?details.reasoningTokens,
    };
  }

  final Map<String, double> counts = <String, double>{};
  if (detailsMap != null) {
    for (final String name in _tokenFields) {
      final double? value = _finite(detailsMap[name]);
      if (value != null) {
        counts[name] = math.max(0.0, value);
      }
    }
  }
  if (!counts.containsKey('total_tokens')) {
    final double? total = _finite(score);
    if (counts.containsKey('input_tokens') &&
        counts.containsKey('output_tokens')) {
      counts['total_tokens'] =
          counts['input_tokens']! + counts['output_tokens']!;
    } else if (total != null) {
      counts['total_tokens'] = math.max(0.0, total);
    }
  }
  if (counts.isEmpty) {
    return null;
  }
  return _TokenCounts(
    totalTokens: counts['total_tokens'],
    inputTokens: counts['input_tokens'],
    outputTokens: counts['output_tokens'],
    cachedTokens: counts['cached_tokens'],
    reasoningTokens: counts['reasoning_tokens'],
  );
}

_TokenCounts? _combineTokenCounts(
  List<_TokenCounts> items, {
  required double Function(List<double>) combine,
}) {
  final Map<String, double> combined = <String, double>{};
  for (final String name in _tokenFields) {
    final List<double?> values = <double?>[
      for (final _TokenCounts item in items) item[name],
    ];
    final List<double> known = <double>[
      for (final double? v in values) ?v,
    ];
    if (known.isEmpty) {
      continue;
    }
    if (known.length == values.length) {
      combined[name] = combine(known);
    } else if (_optionalTokenFields.contains(name)) {
      combined[name] = combine(<double>[
        for (final double? v in values) v ?? 0.0,
      ]);
    }
  }
  if (combined.isEmpty) {
    return null;
  }
  return _TokenCounts(
    totalTokens: combined['total_tokens'],
    inputTokens: combined['input_tokens'],
    outputTokens: combined['output_tokens'],
    cachedTokens: combined['cached_tokens'],
    reasoningTokens: combined['reasoning_tokens'],
  );
}

_ExampleTelemetry _extractExampleTelemetry(Map<String, Object?>? exampleData) {
  final Map<String, List<double>> metricValues = <String, List<double>>{};
  final Set<String> metricNames = <String>{};
  final List<double> durations = <double>[];
  final List<_TokenCounts> turnTokens = <_TokenCounts>[];
  bool tokensComplete = true;

  final bool hasInvocationsKey =
      exampleData != null && exampleData.containsKey('invocations');
  final Object? rawInvocations = exampleData?['invocations'];
  final List<Object?> invocations = rawInvocations is List
      ? rawInvocations
      : const <Object?>[];
  final bool hasInvocations = hasInvocationsKey
      ? invocations.isNotEmpty
      : true;

  for (final Object? invocation in invocations) {
    if (invocation is! Map) {
      continue;
    }
    _TokenCounts? turnCount;
    final Object? rawResults = invocation['eval_metric_results'];
    final List<Object?> results = rawResults is List
        ? rawResults
        : const <Object?>[];
    for (final Object? metricResult in results) {
      if (metricResult is! Map) {
        continue;
      }
      final Object? rawName = metricResult['metric_name'];
      final String name = rawName == null ? '' : '$rawName';
      if (name.isNotEmpty) {
        metricNames.add(name);
      }
      final double? score = _finite(metricResult['score']);
      if (name == _tokenMetric) {
        final Object? details = metricResult['details'];
        final Object? breakdown = details is Map
            ? details['token_usage_details']
            : null;
        turnCount = _parseTokenCounts(breakdown, metricResult['score']);
      } else if (score == null) {
        continue;
      } else if (name == _durationMetric) {
        durations.add(score);
      } else if (name.isNotEmpty) {
        (metricValues[name] ??= <double>[]).add(score);
      }
    }
    if (turnCount == null) {
      tokensComplete = false;
    } else {
      turnTokens.add(turnCount);
    }
  }

  _TokenCounts? tokens;
  if (tokensComplete && turnTokens.isNotEmpty) {
    tokens = _combineTokenCounts(turnTokens, combine: _fsum);
  }
  return _ExampleTelemetry(
    metricScores: <String, double>{
      for (final MapEntry<String, List<double>> entry in metricValues.entries)
        entry.key: _fmean(entry.value),
    },
    metricNames: Set<String>.unmodifiable(metricNames),
    latencySec: durations.isNotEmpty ? _fmean(durations) : null,
    tokens: tokens,
    hasInvocations: hasInvocations,
  );
}

double? _totalTokens(_TrialResult trial) => trial.tokens?.totalTokens;

String _describe(List<_TrialResult> trials, {int limit = 3}) {
  final List<String> shown = <String>[];
  for (final _TrialResult trial in trials.take(limit)) {
    String params = '${trial.params}';
    if (params.length > _maxLoggedParamsChars) {
      params = '${params.substring(0, _maxLoggedParamsChars - 3)}...';
    }
    shown.add(params);
  }
  return shown.join('; ') + (trials.length > limit ? '; ...' : '');
}

(double, double, double) _objectives(_TrialResult trial) {
  final double? tokens = _totalTokens(trial);
  return (
    -trial.qualityScore,
    tokens ?? double.infinity,
    trial.latencySec ?? double.infinity,
  );
}

bool _dominates(_TrialResult a, _TrialResult b) {
  final (double aq, double at, double al) = _objectives(a);
  final (double bq, double bt, double bl) = _objectives(b);
  if (aq == bq && at == bt && al == bl) {
    return false;
  }
  return aq <= bq && at <= bt && al <= bl;
}

int _compareObjectives(
  (double, double, double) a,
  (double, double, double) b,
) {
  final int q = a.$1.compareTo(b.$1);
  if (q != 0) {
    return q;
  }
  final int t = a.$2.compareTo(b.$2);
  if (t != 0) {
    return t;
  }
  return a.$3.compareTo(b.$3);
}

/// Evaluates every candidate in a parameter grid and returns the Pareto front.
///
/// Every candidate is scored on the same examples, so the front compares like
/// with like across quality, total tokens, and latency.
class GridSearchAgentOptimizer
    extends
        AgentOptimizer<UnstructuredSamplingResult, GridSearchAgentWithScores> {
  /// Creates a [GridSearchAgentOptimizer] for [_config].
  GridSearchAgentOptimizer(
    this._config, {
    GridSearchWarningEmitter? onWarning,
  }) : _onWarning = onWarning {
    experimental(FeatureName.gridSearchAgentOptimizer).checkEnabled();
  }

  final GridSearchAgentOptimizerConfig _config;
  final GridSearchWarningEmitter? _onWarning;

  /// The optimizer configuration.
  GridSearchAgentOptimizerConfig get config => _config;

  void _emitWarning(String message) {
    developer.log(message, level: 900, name: 'adk_dart.optimization');
    _onWarning?.call(message);
  }

  double? _calculateExampleQuality({
    required double? overallScore,
    required Map<String, double> metricScores,
    Set<String> metricNames = const <String>{},
  }) {
    final Object? qualityMetric = _config.qualityMetric;
    final Map<String, double> qualityScores = <String, double>{
      for (final MapEntry<String, double> entry in metricScores.entries)
        if (!_efficiencyMetrics.contains(entry.key)) entry.key: entry.value,
    };
    final bool hasQualityMetrics = metricNames
        .difference(_efficiencyMetrics)
        .isNotEmpty;

    if (qualityMetric == null ||
        (qualityMetric is Map && qualityMetric.isEmpty)) {
      if (qualityScores.isNotEmpty) {
        return _fmean(qualityScores.values.toList(growable: false));
      }
      if (hasQualityMetrics || overallScore == null) {
        return null;
      }
      return overallScore;
    }

    if (qualityMetric is String) {
      return metricScores[qualityMetric];
    }

    if (qualityMetric is QualityMetricFn) {
      if (qualityScores.isEmpty && overallScore == null) {
        return null;
      }
      final Map<String, double> combined = Map<String, double>.from(
        qualityScores,
      );
      if (overallScore != null) {
        combined.putIfAbsent('overall_score', () => overallScore);
      }
      return qualityMetric(combined).toDouble();
    }

    if (qualityMetric is Map) {
      for (final Object? rawName in qualityMetric.keys) {
        final String name = '$rawName';
        if (!metricScores.containsKey(name)) {
          return null;
        }
      }
      double weighted = 0.0;
      for (final MapEntry<Object?, Object?> entry in qualityMetric.entries) {
        final String name = '${entry.key}';
        final double weight = (entry.value as num).toDouble();
        weighted += metricScores[name]! * weight;
      }
      return weighted;
    }

    throw ArgumentError(
      'Unsupported quality_metric type: ${qualityMetric.runtimeType}',
    );
  }

  void _checkQualityMetricReported(Set<String> reported) {
    final Object? qualityMetric = _config.qualityMetric;
    final Set<String> wanted;
    if (qualityMetric is String) {
      wanted = <String>{qualityMetric};
    } else if (qualityMetric is Map) {
      wanted = <String>{for (final Object? key in qualityMetric.keys) '$key'};
    } else {
      return;
    }
    final List<String> missing = wanted.difference(reported).toList()..sort();
    if (reported.isNotEmpty && missing.isNotEmpty) {
      final List<String> reportedList = reported.toList()..sort();
      throw ArgumentError(
        'quality_metric names $missing, which the sampler did not report. '
        'Reported metrics: $reportedList.',
      );
    }
  }

  _TrialResult _scoreCandidate({
    required Map<String, Object?> params,
    required BaseAgent agent,
    required List<String> exampleIds,
    required UnstructuredSamplingResult samplingResult,
  }) {
    final Map<String, double> scoresMap = samplingResult.scores;
    final Map<String, Map<String, Object?>> dataMap =
        samplingResult.data ?? const <String, Map<String, Object?>>{};
    final Map<String, double> caseScores = <String, double>{};
    final List<double> latencies = <double>[];
    final List<_TokenCounts> exampleTokens = <_TokenCounts>[];
    final Set<String> reportedMetrics = <String>{};

    for (final String exampleId in exampleIds) {
      final _ExampleTelemetry telemetry = _extractExampleTelemetry(
        dataMap[exampleId],
      );
      reportedMetrics.addAll(telemetry.metricNames);
      if (telemetry.latencySec != null) {
        latencies.add(telemetry.latencySec!);
      }
      if (telemetry.tokens != null) {
        exampleTokens.add(telemetry.tokens!);
      }
      final double? overallScore = telemetry.hasInvocations
          ? _finite(scoresMap[exampleId])
          : null;
      final double? quality = _finite(
        _calculateExampleQuality(
          overallScore: overallScore,
          metricScores: telemetry.metricScores,
          metricNames: telemetry.metricNames,
        ),
      );
      if (quality != null) {
        caseScores[exampleId] = quality;
      }
    }
    _checkQualityMetricReported(reportedMetrics);

    final bool allTimed =
        latencies.length == exampleIds.length && latencies.isNotEmpty;
    final bool allCounted =
        exampleTokens.length == exampleIds.length && exampleTokens.isNotEmpty;

    final _TrialResult trial = _TrialResult(
      params: params,
      agent: agent,
      // Unscored examples count as 0 so every candidate is averaged over the
      // full example set.
      qualityScore: _fsum(caseScores.values) / exampleIds.length,
      evalCaseScores: caseScores,
      latencySec: allTimed ? _fmean(latencies) : null,
      tokens: allCounted
          ? _combineTokenCounts(exampleTokens, combine: _fmean)
          : null,
      numCasesEvaluated: caseScores.length,
    );
    trial.isFeasible = _isTrialFeasible(trial);
    return trial;
  }

  bool _isTrialFeasible(_TrialResult trial) {
    final double? minQuality = _config.minQualityScore;
    final double? maxLatency = _config.maxLatencySec;
    final int? maxTokens = _config.maxTotalTokens;
    final double? totalTokens = _totalTokens(trial);
    if (trial.numCasesEvaluated == 0) {
      return false;
    }
    if (minQuality != null && trial.qualityScore < minQuality) {
      return false;
    }
    if (maxLatency != null &&
        (trial.latencySec == null || trial.latencySec! > maxLatency)) {
      return false;
    }
    if (maxTokens != null &&
        (totalTokens == null || totalTokens > maxTokens)) {
      return false;
    }
    return true;
  }

  OptimizerResult<GridSearchAgentWithScores> _buildParetoResult(
    List<_TrialResult> trials,
  ) {
    final List<_TrialResult> feasible = < _TrialResult>[
      for (final _TrialResult trial in trials)
        if (trial.isFeasible) trial,
    ];
    final List<_TrialResult> front = <_TrialResult>[
      for (final _TrialResult trial in feasible)
        if (!feasible.any(
          (_TrialResult other) =>
              !identical(other, trial) && _dominates(other, trial),
        ))
          trial,
    ];
    front.sort(
      (_TrialResult a, _TrialResult b) =>
          _compareObjectives(_objectives(a), _objectives(b)),
    );
    return OptimizerResult<GridSearchAgentWithScores>(
      optimizedAgents: <GridSearchAgentWithScores>[
        for (final _TrialResult trial in front)
          GridSearchAgentWithScores(
            optimizedAgent: trial.agent,
            overallScore: trial.qualityScore,
            evalCaseScores: trial.evalCaseScores,
            tokenUsage: trial.tokens?.toMap() ?? const <String, double>{},
            latencySec: trial.latencySec,
            metadata: <String, Object?>{
              'params': Map<String, Object?>.unmodifiable(trial.params),
              'num_cases_evaluated': trial.numCasesEvaluated,
            },
          ),
      ],
    );
  }

  Future<UnstructuredSamplingResult> _sampleCandidate(
    Sampler<UnstructuredSamplingResult> sampler,
    BaseAgent agent,
    ExampleSet exampleSet,
    List<String> exampleIds,
  ) {
    if (agent is Agent) {
      return sampler.sampleAndScore(
        agent,
        exampleSet: exampleSet,
        batch: List<String>.from(exampleIds),
        captureFullEvalData: true,
      );
    }
    return (sampler as dynamic).sampleAndScore(
          agent,
          exampleSet: exampleSet,
          batch: List<String>.from(exampleIds),
          captureFullEvalData: true,
        )
        as Future<UnstructuredSamplingResult>;
  }

  /// Evaluates every grid candidate on the same examples and returns the
  /// Pareto front across quality, total tokens, and latency.
  @override
  Future<OptimizerResult<GridSearchAgentWithScores>> optimize(
    BaseAgent initialAgent,
    Sampler<UnstructuredSamplingResult> sampler,
  ) async {
    final ExampleSet requestedSet = _config.exampleSet;
    ExampleSet exampleSet = requestedSet;
    List<String> rawIds;
    if (requestedSet == ExampleSet.train) {
      rawIds = sampler.getTrainExampleIds();
      if (rawIds.isEmpty) {
        exampleSet = ExampleSet.validation;
        rawIds = sampler.getValidationExampleIds();
      }
    } else {
      rawIds = sampler.getValidationExampleIds();
      if (rawIds.isEmpty) {
        exampleSet = ExampleSet.train;
        rawIds = sampler.getTrainExampleIds();
      }
    }

    final Set<String> seenIds = <String>{};
    final List<String> exampleIds = <String>[
      for (final String id in rawIds)
        if (seenIds.add(id)) id,
    ];
    if (exampleIds.isEmpty) {
      _emitWarning('Grid search: the sampler has no examples to score.');
      return OptimizerResult<GridSearchAgentWithScores>(
        optimizedAgents: const <GridSearchAgentWithScores>[],
      );
    }
    if (exampleSet != requestedSet) {
      _emitWarning(
        'Grid search: sampler has no ${requestedSet.name} examples; falling '
        'back to ${exampleIds.length} ${exampleSet.name} examples.',
      );
    }

    final List<Map<String, Object?>> candidates = _expandParamGrid(
      _config.paramGrid,
    );
    final List<BaseAgent> agents = <BaseAgent>[
      for (final Map<String, Object?> params in candidates)
        cloneAgentWithParams(initialAgent, params),
    ];

    developer.log(
      'Grid search: evaluating ${candidates.length} candidates on '
      '${exampleIds.length} ${exampleSet.name} examples each.',
      name: 'adk_dart.optimization',
    );

    final List<_TrialResult?> trialSlots = List<_TrialResult?>.filled(
      candidates.length,
      null,
    );
    final int workerCount = math.min(
      _config.maxConcurrentCandidates,
      candidates.length,
    );
    int nextIndex = 0;
    bool aborted = false;

    Future<void> runWorker() async {
      while (!aborted) {
        final int index = nextIndex;
        if (index >= candidates.length) {
          return;
        }
        nextIndex += 1;
        try {
          final UnstructuredSamplingResult samplingResult =
              await _sampleCandidate(
                sampler,
                agents[index],
                exampleSet,
                exampleIds,
              );
          trialSlots[index] = _scoreCandidate(
            params: candidates[index],
            agent: agents[index],
            exampleIds: exampleIds,
            samplingResult: samplingResult,
          );
        } catch (_) {
          aborted = true;
          rethrow;
        }
      }
    }

    await Future.wait<void>(
      <Future<void>>[for (int i = 0; i < workerCount; i += 1) runWorker()],
      eagerError: true,
    );

    final List<_TrialResult> trials = <_TrialResult>[
      for (final _TrialResult? trial in trialSlots) trial!,
    ];
    _warnAboutMissingData(trials, numExamples: exampleIds.length);
    return _buildParetoResult(trials);
  }

  void _warnAboutMissingData(
    List<_TrialResult> trials, {
    required int numExamples,
  }) {
    final List<_TrialResult> unscored = <_TrialResult>[
      for (final _TrialResult trial in trials)
        if (trial.numCasesEvaluated == 0) trial,
    ];
    if (unscored.isNotEmpty) {
      _emitWarning(
        'Grid search: ${unscored.length} of ${trials.length} candidates '
        'produced no scored examples and are excluded: ${_describe(unscored)}',
      );
    }

    final List<_TrialResult> scored = <_TrialResult>[
      for (final _TrialResult trial in trials)
        if (trial.numCasesEvaluated > 0) trial,
    ];
    if (scored.isNotEmpty &&
        !scored.any((_TrialResult trial) => trial.isFeasible)) {
      final double bestQuality = scored
          .map((_TrialResult t) => t.qualityScore)
          .reduce(math.max);
      _emitWarning(
        'Grid search: all ${scored.length} scored candidates failed feasibility '
        'thresholds (best quality=${bestQuality.toStringAsFixed(4)}); returning '
        'an empty result.',
      );
    }

    final List<_TrialResult> partial = <_TrialResult>[
      for (final _TrialResult trial in scored)
        if (trial.numCasesEvaluated < numExamples) trial,
    ];
    if (partial.isNotEmpty) {
      _emitWarning(
        'Grid search: ${partial.length} of ${trials.length} candidates could '
        'not be scored on every example (unscored examples count as 0 quality): '
        '${_describe(partial)}',
      );
    }

    final List<_TrialResult> missingTokens = <_TrialResult>[
      for (final _TrialResult trial in scored)
        if (_totalTokens(trial) == null) trial,
    ];
    if (missingTokens.isNotEmpty) {
      _emitWarning(
        'Grid search: ${missingTokens.length} of ${scored.length} scored '
        'candidates reported no token usage (ranked worst on tokens; fails '
        'max_total_tokens if set): ${_describe(missingTokens)}',
      );
    }

    final List<_TrialResult> missingLatency = <_TrialResult>[
      for (final _TrialResult trial in scored)
        if (trial.latencySec == null) trial,
    ];
    if (missingLatency.isNotEmpty) {
      _emitWarning(
        'Grid search: ${missingLatency.length} of ${scored.length} scored '
        'candidates reported no latency (ranked worst on latency; fails '
        'max_latency_sec if set): ${_describe(missingLatency)}',
      );
    }
  }
}
