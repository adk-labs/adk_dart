/// Evaluator for tool call argument matching using [ToolArgsMatcher].
library;

import 'dart:async';
import 'dart:math' as math;

import '../features/_feature_registry.dart';
import '../tools/tool_args_matcher/tool_args_matcher.dart';
import '../utils/env_utils.dart';
import 'common.dart';
import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';

/// Maximum number of `(expectedCall, actualCall)` pairs scored concurrently.
const int maxConcurrentCallScores = 8;

const Object _cancelTokenZoneKey = Object();

/// Token notified if a sibling call-score task fails during concurrent scoring.
class CallScoreCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  /// Whether concurrent pair scoring has been cancelled due to an error.
  bool get isCancelled => _isCancelled;

  /// Registers [listener] to run immediately if cancelled (or right away if already cancelled).
  void onCancel(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void _cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final List<void Function()> listeners = List<void Function()>.from(
      _listeners,
    );
    _listeners.clear();
    for (final void Function() listener in listeners) {
      listener();
    }
  }
}

/// Active [CallScoreCancellationToken] in the current async zone, if any.
CallScoreCancellationToken? get currentCallScoreCancellationToken {
  final Object? token = Zone.current[_cancelTokenZoneKey];
  return token is CallScoreCancellationToken ? token : null;
}

/// Scores each invocation by how well actual tool call arguments match expected calls.
///
/// Expected and actual tool calls are paired using [MatchType.exact],
/// [MatchType.inOrder] (default), or [MatchType.anyOrder]. Each paired call is
/// scored with [ToolArgsMatcher.matchAsync], and the invocation score is the
/// mean across expected tool calls. Invocations without expected tool calls are
/// marked [EvalStatus.notEvaluated].
class ToolParameterMatchEvaluator extends Evaluator {
  /// Creates a [ToolParameterMatchEvaluator] from [evalMetric].
  ToolParameterMatchEvaluator(EvalMetricSpec evalMetric)
    : _evalMetric = evalMetric {
    _ensureToolArgsMatcherFeatureEnabled();
    final ToolParameterMatchCriterion? criterion = _parseCriterion(evalMetric);
    if (evalMetric.threshold != null) {
      _threshold = evalMetric.threshold!;
    } else if (criterion != null && criterion.hasExplicitThreshold) {
      _threshold = criterion.threshold;
    } else {
      throw ArgumentError(
        'Either evalMetric.threshold or evalMetric.criterion.threshold must be specified.',
      );
    }
    _argsMatcher = criterion?.argsMatcher ?? ToolArgsMatcher();
    _matchType = criterion?.matchType ?? MatchType.inOrder;
  }

  final EvalMetricSpec _evalMetric;
  late final double _threshold;
  late final ToolArgsMatcher _argsMatcher;
  late final MatchType _matchType;

  /// Exposed metric specification for this evaluator.
  EvalMetricSpec get evalMetric => _evalMetric;

  static void _ensureToolArgsMatcherFeatureEnabled() {
    final Map<FeatureName, bool> overrides = getFeatureOverrides();
    if (overrides[FeatureName.toolArgsMatcher] == false) {
      throw StateError('Feature TOOL_ARGS_MATCHER is not enabled.');
    }
    if (!overrides.containsKey(FeatureName.toolArgsMatcher)) {
      final bool explicitlyEnabled = isEnvEnabled('ADK_ENABLE_TOOL_ARGS_MATCHER');
      final bool explicitlyDisabled = isEnvEnabled(
        'ADK_DISABLE_TOOL_ARGS_MATCHER',
      );
      if (!explicitlyEnabled && explicitlyDisabled) {
        throw StateError('Feature TOOL_ARGS_MATCHER is not enabled.');
      }
      final FeatureConfig? config = getFeatureConfig(
        FeatureName.toolArgsMatcher,
      );
      if ((config?.defaultOn ?? false) &&
          !isFeatureEnabled(FeatureName.toolArgsMatcher)) {
        throw StateError('Feature TOOL_ARGS_MATCHER is not enabled.');
      }
    }
    warnFeatureUse(FeatureName.toolArgsMatcher);
  }

  static ToolParameterMatchCriterion? _parseCriterion(
    EvalMetricSpec evalMetric,
  ) {
    final BaseCriterion? rawCriterion = evalMetric.criterion;
    if (rawCriterion == null) {
      return null;
    }
    if (rawCriterion is ToolParameterMatchCriterion) {
      return rawCriterion;
    }
    if (rawCriterion.runtimeType != BaseCriterion) {
      throw ArgumentError(
        '`${evalMetric.metricName}` metric expects a criterion of type '
        '`ToolParameterMatchCriterion`.',
      );
    }
    try {
      return ToolParameterMatchCriterion.fromJson(rawCriterion.toJson());
    } on ArgumentError catch (error) {
      Error.throwWithStackTrace(
        ArgumentError(
          '`${evalMetric.metricName}` metric expects a criterion of type '
          '`ToolParameterMatchCriterion`: $error',
        ),
        StackTrace.current,
      );
    }
  }

  @override
  Type get criterionType => ToolParameterMatchCriterion;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (expectedInvocations == null) {
      throw ArgumentError('expected_invocations is needed by this metric.');
    }
    if (actualInvocations.length != expectedInvocations.length) {
      throw ArgumentError(
        'actual_invocations (${actualInvocations.length}) and '
        'expected_invocations (${expectedInvocations.length}) must have '
        'equal length.',
      );
    }

    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    for (int i = 0; i < actualInvocations.length; i += 1) {
      final Invocation actual = actualInvocations[i];
      final Invocation expected = expectedInvocations[i];
      final List<EvalJsonMap> expectedCalls = getAllToolCalls(
        expected.intermediateData,
      );
      if (expectedCalls.isEmpty) {
        perInvocationResults.add(
          PerInvocationResult(
            actualInvocation: actual,
            expectedInvocation: expected,
            score: null,
            evalStatus: EvalStatus.notEvaluated,
          ),
        );
        continue;
      }

      final List<EvalJsonMap> actualCalls = getAllToolCalls(
        actual.intermediateData,
      );
      final List<double> callScores = await _scoreCalls(
        actualCalls,
        expectedCalls,
      );
      final double score =
          callScores.fold<double>(0.0, (double a, double b) => a + b) /
          callScores.length;
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: actual,
          expectedInvocation: expected,
          score: score,
          evalStatus: _getEvalStatus(score),
        ),
      );
    }

    final List<double> scores = <double>[
      for (final PerInvocationResult result in perInvocationResults)
        if (result.score != null) result.score!,
    ];
    if (scores.isEmpty) {
      return EvaluationResult(perInvocationResults: perInvocationResults);
    }
    final double overallScore =
        scores.fold<double>(0.0, (double a, double b) => a + b) / scores.length;
    return EvaluationResult(
      overallScore: overallScore,
      overallEvalStatus: _getEvalStatus(overallScore),
      perInvocationResults: perInvocationResults,
    );
  }

  Future<List<double>> _scoreCalls(
    List<EvalJsonMap> actualCalls,
    List<EvalJsonMap> expectedCalls,
  ) async {
    switch (_matchType) {
      case MatchType.exact:
        return _scorePairs(
          expectedCalls,
          _pairCallsExactly(actualCalls, expectedCalls),
        );
      case MatchType.inOrder:
        return _scorePairs(
          expectedCalls,
          _pairCallsInOrder(actualCalls, expectedCalls),
        );
      case MatchType.anyOrder:
        return _scoreCallsInAnyOrder(actualCalls, expectedCalls);
    }
  }

  Future<List<double>> _scorePairs(
    List<EvalJsonMap> expectedCalls,
    List<EvalJsonMap?> pairedActualCalls,
  ) {
    final List<(EvalJsonMap, EvalJsonMap?)> pairs =
        <(EvalJsonMap, EvalJsonMap?)>[
          for (int i = 0; i < expectedCalls.length; i += 1)
            (expectedCalls[i], pairedActualCalls[i]),
        ];
    return _runBoundedPairs(pairs);
  }

  Future<List<double>> _runBoundedPairs(
    List<(EvalJsonMap, EvalJsonMap?)> pairs,
  ) {
    if (pairs.isEmpty) {
      return Future<List<double>>.value(const <double>[]);
    }
    final Completer<List<double>> completer = Completer<List<double>>();
    final List<double> results = List<double>.filled(pairs.length, 0.0);
    final CallScoreCancellationToken cancelToken = CallScoreCancellationToken();
    int nextIndex = 0;
    int completedCount = 0;

    Future<void> runWorker() async {
      while (!cancelToken.isCancelled) {
        final int index = nextIndex;
        if (index >= pairs.length) {
          return;
        }
        nextIndex += 1;
        final (EvalJsonMap expectedCall, EvalJsonMap? actualCall) =
            pairs[index];
        try {
          final double score = await runZoned(
            () => _scoreCall(expectedCall, actualCall),
            zoneValues: <Object?, Object?>{_cancelTokenZoneKey: cancelToken},
          );
          if (cancelToken.isCancelled) {
            return;
          }
          results[index] = score;
          completedCount += 1;
          if (completedCount == pairs.length && !completer.isCompleted) {
            completer.complete(results);
          }
        } catch (error, stackTrace) {
          cancelToken._cancel();
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          return;
        }
      }
    }

    final int workerCount = math.min(maxConcurrentCallScores, pairs.length);
    for (int w = 0; w < workerCount; w += 1) {
      unawaited(runWorker());
    }
    return completer.future;
  }

  Future<double> _scoreCall(
    EvalJsonMap expectedCall,
    EvalJsonMap? actualCall,
  ) async {
    if (actualCall == null || actualCall['name'] != expectedCall['name']) {
      return 0.0;
    }
    final ToolArgsMatchResult result = await _argsMatcher.matchAsync(
      toolName: '${expectedCall['name'] ?? ''}',
      expected: asEvalJson(expectedCall['args']),
      actual: asEvalJson(actualCall['args']),
    );
    return result.score;
  }

  Future<List<double>> _scoreCallsInAnyOrder(
    List<EvalJsonMap> actualCalls,
    List<EvalJsonMap> expectedCalls,
  ) async {
    final Map<String, List<int>> expectedIndicesByName = <String, List<int>>{};
    for (int i = 0; i < expectedCalls.length; i += 1) {
      final String name = '${expectedCalls[i]['name'] ?? ''}';
      expectedIndicesByName.putIfAbsent(name, () => <int>[]).add(i);
    }

    final Map<String, List<int>> actualIndicesByName = <String, List<int>>{};
    for (int j = 0; j < actualCalls.length; j += 1) {
      final String name = '${actualCalls[j]['name'] ?? ''}';
      if (expectedIndicesByName.containsKey(name)) {
        actualIndicesByName.putIfAbsent(name, () => <int>[]).add(j);
      }
    }

    final List<(EvalJsonMap, EvalJsonMap?)> candidatePairs =
        <(EvalJsonMap, EvalJsonMap?)>[];
    final List<(String, int, int)> candidateLocations = <(String, int, int)>[];
    for (final MapEntry<String, List<int>> entry
        in expectedIndicesByName.entries) {
      final String name = entry.key;
      final List<int> expectedIndices = entry.value;
      final List<int> actualIndices =
          actualIndicesByName[name] ?? const <int>[];
      for (int r = 0; r < expectedIndices.length; r += 1) {
        for (int c = 0; c < actualIndices.length; c += 1) {
          candidatePairs.add((
            expectedCalls[expectedIndices[r]],
            actualCalls[actualIndices[c]],
          ));
          candidateLocations.add((name, r, c));
        }
      }
    }

    final List<double> flatScores = await _runBoundedPairs(candidatePairs);

    final Map<String, List<List<double>>> matricesByName =
        <String, List<List<double>>>{};
    for (final MapEntry<String, List<int>> entry
        in expectedIndicesByName.entries) {
      final String name = entry.key;
      final int rowCount = entry.value.length;
      final int colCount = (actualIndicesByName[name] ?? const <int>[]).length;
      matricesByName[name] = List<List<double>>.generate(
        rowCount,
        (_) => List<double>.filled(colCount, 0.0),
      );
    }
    for (int k = 0; k < flatScores.length; k += 1) {
      final (String name, int r, int c) = candidateLocations[k];
      matricesByName[name]![r][c] = flatScores[k];
    }

    final List<double> callScores = List<double>.filled(
      expectedCalls.length,
      0.0,
    );
    for (final MapEntry<String, List<int>> entry
        in expectedIndicesByName.entries) {
      final String name = entry.key;
      final List<int> expectedIndices = entry.value;
      final List<double> assignedScores = _maxScoreAssignment(
        matricesByName[name]!,
      );
      for (int r = 0; r < expectedIndices.length; r += 1) {
        callScores[expectedIndices[r]] = assignedScores[r];
      }
    }
    return callScores;
  }

  EvalStatus _getEvalStatus(double score) {
    return score >= _threshold ? EvalStatus.passed : EvalStatus.failed;
  }
}

List<EvalJsonMap?> _pairCallsExactly(
  List<EvalJsonMap> actualCalls,
  List<EvalJsonMap> expectedCalls,
) {
  return <EvalJsonMap?>[
    for (int i = 0; i < expectedCalls.length; i += 1)
      i < actualCalls.length ? actualCalls[i] : null,
  ];
}

List<EvalJsonMap?> _pairCallsInOrder(
  List<EvalJsonMap> actualCalls,
  List<EvalJsonMap> expectedCalls,
) {
  final List<EvalJsonMap?> paired = <EvalJsonMap?>[];
  int actualIndex = 0;
  for (final EvalJsonMap expectedCall in expectedCalls) {
    final Object? expectedName = expectedCall['name'];
    int? matchedIndex;
    for (int j = actualIndex; j < actualCalls.length; j += 1) {
      if (actualCalls[j]['name'] == expectedName) {
        matchedIndex = j;
        break;
      }
    }
    if (matchedIndex == null) {
      paired.add(null);
    } else {
      paired.add(actualCalls[matchedIndex]);
      actualIndex = matchedIndex + 1;
    }
  }
  return paired;
}

/// Kuhn-Munkres maximum-weight assignment over [scores] (`rowCount x actualCount`).
///
/// Returns the assigned score for each row in `0 .. rowCount - 1`, with `0.0`
/// for any row left unassigned when `actualCount < rowCount`.
List<double> _maxScoreAssignment(List<List<double>> scores) {
  final int rowCount = scores.length;
  if (rowCount == 0) {
    return const <double>[];
  }
  final int actualCount = scores.first.length;
  if (actualCount == 0) {
    return List<double>.filled(rowCount, 0.0);
  }

  final int colCount = math.max(rowCount, actualCount);
  // Pad dummy columns with cost 1.0 (score 0.0) so rowCount <= colCount holds.
  final List<double> u = List<double>.filled(rowCount + 1, 0.0);
  final List<double> v = List<double>.filled(colCount + 1, 0.0);
  final List<int> matchedRowForCol = List<int>.filled(colCount + 1, 0);
  final List<int> prevCol = List<int>.filled(colCount + 1, 0);

  double costAt(int oneBasedRow, int oneBasedCol) {
    final int r = oneBasedRow - 1;
    final int c = oneBasedCol - 1;
    if (c >= actualCount) {
      return 1.0;
    }
    return 1.0 - scores[r][c];
  }

  for (int row = 1; row <= rowCount; row += 1) {
    matchedRowForCol[0] = row;
    int currentCol = 0;
    final List<double> minSlack = List<double>.filled(
      colCount + 1,
      double.infinity,
    );
    final List<bool> visitedCols = List<bool>.filled(colCount + 1, false);

    do {
      visitedCols[currentCol] = true;
      final int currentRow = matchedRowForCol[currentCol];
      double delta = double.infinity;
      int nextCol = 0;
      for (int col = 1; col <= colCount; col += 1) {
        if (visitedCols[col]) {
          continue;
        }
        final double slack =
            costAt(currentRow, col) - u[currentRow] - v[col];
        if (slack < minSlack[col]) {
          minSlack[col] = slack;
          prevCol[col] = currentCol;
        }
        if (minSlack[col] < delta) {
          delta = minSlack[col];
          nextCol = col;
        }
      }
      for (int col = 0; col <= colCount; col += 1) {
        if (visitedCols[col]) {
          u[matchedRowForCol[col]] += delta;
          v[col] -= delta;
        } else {
          minSlack[col] -= delta;
        }
      }
      currentCol = nextCol;
    } while (matchedRowForCol[currentCol] != 0);

    do {
      final int previous = prevCol[currentCol];
      matchedRowForCol[currentCol] = matchedRowForCol[previous];
      currentCol = previous;
    } while (currentCol != 0);
  }

  final List<double> assignedScores = List<double>.filled(rowCount, 0.0);
  for (int col = 1; col <= actualCount; col += 1) {
    final int row = matchedRowForCol[col];
    if (row > 0) {
      assignedScores[row - 1] = scores[row - 1][col - 1];
    }
  }
  return assignedScores;
}
