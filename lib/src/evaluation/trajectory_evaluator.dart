import 'dart:convert';

import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';

class TrajectoryEvaluator extends Evaluator {
  TrajectoryEvaluator({double? threshold, EvalMetricSpec? evalMetric}) {
    if (threshold != null && evalMetric != null) {
      throw ArgumentError(
        'Either evalMetric should be specified or threshold should be specified.',
      );
    }

    if (evalMetric?.criterion != null) {
      final BaseCriterion criterion = evalMetric!.criterion!;
      if (criterion is ToolTrajectoryCriterion) {
        _threshold = criterion.threshold;
        _matchType = criterion.matchType;
      } else {
        final ToolTrajectoryCriterion parsed = ToolTrajectoryCriterion.fromJson(
          criterion.toJson(),
        );
        _threshold = parsed.threshold;
        _matchType = parsed.matchType;
      }
    } else if (evalMetric != null) {
      _threshold = evalMetric.threshold ?? 1.0;
      _matchType = MatchType.exact;
    } else {
      _threshold = threshold ?? 1.0;
      _matchType = MatchType.exact;
    }
  }

  late final double _threshold;
  late final MatchType _matchType;

  @override
  Type get criterionType => ToolTrajectoryCriterion;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (expectedInvocations == null) {
      throw ArgumentError('expectedInvocations is needed by this metric.');
    }
    final int count = _min(
      actualInvocations.length,
      expectedInvocations.length,
    );
    if (count == 0) {
      return EvaluationResult();
    }

    double totalToolUseAccuracy = 0.0;
    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    for (int i = 0; i < count; i += 1) {
      final Invocation actual = actualInvocations[i];
      final Invocation expected = expectedInvocations[i];
      final double toolUseAccuracy = _calculateToolUseAccuracy(
        actual,
        expected,
      );
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: actual,
          expectedInvocation: expected,
          score: toolUseAccuracy,
          evalStatus: _getEvalStatus(toolUseAccuracy),
        ),
      );
      totalToolUseAccuracy += toolUseAccuracy;
    }

    final double overallScore = totalToolUseAccuracy / count;
    return EvaluationResult(
      overallScore: overallScore,
      overallEvalStatus: _getEvalStatus(overallScore),
      perInvocationResults: perInvocationResults,
    );
  }

  double _calculateToolUseAccuracy(
    Invocation actualInvocation,
    Invocation expectedInvocation,
  ) {
    final List<EvalJsonMap> actualToolUses = getAllToolCalls(
      actualInvocation.intermediateData,
    );
    final List<EvalJsonMap> expectedToolUses = getAllToolCalls(
      expectedInvocation.intermediateData,
    );

    bool toolUseMatchStatus;
    switch (_matchType) {
      case MatchType.exact:
        toolUseMatchStatus = _areToolCallsExactMatch(
          actualToolUses,
          expectedToolUses,
        );
        break;
      case MatchType.inOrder:
        toolUseMatchStatus = _areToolCallsInOrderMatch(
          actualToolUses,
          expectedToolUses,
        );
        break;
      case MatchType.anyOrder:
        toolUseMatchStatus = _areToolCallsAnyOrderMatch(
          actualToolUses,
          expectedToolUses,
        );
        break;
    }
    return toolUseMatchStatus ? 1.0 : 0.0;
  }

  bool _areToolCallsInOrderMatch(
    List<EvalJsonMap> actualToolCalls,
    List<EvalJsonMap> expectedToolCalls,
  ) {
    if (expectedToolCalls.isEmpty) {
      return true;
    }
    if (actualToolCalls.isEmpty && expectedToolCalls.isNotEmpty) {
      return false;
    }

    int expectedIndex = 0;
    for (final EvalJsonMap actual in actualToolCalls) {
      if (_isSameToolCall(actual, expectedToolCalls[expectedIndex])) {
        expectedIndex += 1;
        if (expectedIndex == expectedToolCalls.length) {
          return true;
        }
      }
    }
    return false;
  }

  bool _areToolCallsAnyOrderMatch(
    List<EvalJsonMap> actualToolCalls,
    List<EvalJsonMap> expectedToolCalls,
  ) {
    if (expectedToolCalls.isEmpty) {
      return true;
    }
    if (actualToolCalls.isEmpty && expectedToolCalls.isNotEmpty) {
      return false;
    }

    final List<EvalJsonMap> actualCopy = List<EvalJsonMap>.from(
      actualToolCalls,
    );
    for (final EvalJsonMap expected in expectedToolCalls) {
      bool found = false;
      for (int i = 0; i < actualCopy.length; i += 1) {
        if (_isSameToolCall(actualCopy[i], expected)) {
          actualCopy.removeAt(i);
          found = true;
          break;
        }
      }
      if (!found) {
        return false;
      }
    }
    return true;
  }

  bool _areToolCallsExactMatch(
    List<EvalJsonMap> actualToolCalls,
    List<EvalJsonMap> expectedToolCalls,
  ) {
    if (actualToolCalls.length != expectedToolCalls.length) {
      return false;
    }
    for (int i = 0; i < actualToolCalls.length; i += 1) {
      if (!_isSameToolCall(actualToolCalls[i], expectedToolCalls[i])) {
        return false;
      }
    }
    return true;
  }

  bool _isSameToolCall(EvalJsonMap lhs, EvalJsonMap rhs) {
    final String lhsName = (lhs['name'] ?? '').toString();
    final String rhsName = (rhs['name'] ?? '').toString();
    if (lhsName != rhsName) {
      return false;
    }
    return _jsonDeepEqual(lhs['args'], rhs['args']);
  }

  bool _jsonDeepEqual(Object? lhs, Object? rhs) {
    return jsonEncode(_normalizeJson(lhs)) == jsonEncode(_normalizeJson(rhs));
  }

  Object? _normalizeJson(Object? value) {
    if (value is Map) {
      final List<String> keys = value.keys
          .map((dynamic key) => key.toString())
          .toList();
      keys.sort();
      final Map<String, Object?> normalized = <String, Object?>{};
      for (final String key in keys) {
        normalized[key] = _normalizeJson(value[key]);
      }
      return normalized;
    }
    if (value is List) {
      return value.map(_normalizeJson).toList();
    }
    return value;
  }

  EvalStatus _getEvalStatus(double score) {
    return score >= _threshold ? EvalStatus.passed : EvalStatus.failed;
  }
}

int _min(int lhs, int rhs) => lhs < rhs ? lhs : rhs;
