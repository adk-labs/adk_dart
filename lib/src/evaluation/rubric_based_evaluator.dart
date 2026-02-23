import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_rubrics.dart';
import 'evaluator.dart';
import 'llm_as_judge_utils.dart';

abstract class RubricBasedEvaluator extends Evaluator {
  RubricBasedEvaluator({
    required EvalMetricSpec evalMetric,
    required this.rubricType,
  }) {
    if (evalMetric.criterion == null) {
      throw ArgumentError(
        '`${evalMetric.metricName}` metric expects a rubric-based criterion.',
      );
    }
    _criterion = evalMetric.criterion is RubricsBasedCriterion
        ? evalMetric.criterion! as RubricsBasedCriterion
        : RubricsBasedCriterion.fromJson(evalMetric.criterion!.toJson());
  }

  final String rubricType;
  late final RubricsBasedCriterion _criterion;

  @override
  Type get criterionType => RubricsBasedCriterion;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (actualInvocations.isEmpty) {
      return EvaluationResult();
    }
    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    final List<RubricScore> overallRubricScores = <RubricScore>[];
    double total = 0.0;
    final double threshold = _criterion.threshold;

    for (final Invocation invocation in actualInvocations) {
      final List<Rubric> rubrics = _effectiveRubrics(invocation.rubrics);
      final List<RubricScore> rubricScores = _scoreRubrics(
        rubrics: rubrics,
        candidateText: candidateText(invocation),
      );
      final double? score = getAverageRubricScore(rubricScores);
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: invocation,
          score: score,
          evalStatus: getEvalStatus(score, threshold),
          rubricScores: rubricScores,
        ),
      );
      overallRubricScores.addAll(rubricScores);
      total += score ?? 0.0;
    }

    final double overallScore = total / actualInvocations.length;
    return EvaluationResult(
      overallScore: overallScore,
      overallEvalStatus: getEvalStatus(overallScore, threshold),
      perInvocationResults: perInvocationResults,
      overallRubricScores: overallRubricScores,
    );
  }

  String candidateText(Invocation invocation);

  List<Rubric> _effectiveRubrics(List<EvalJsonMap> invocationRubrics) {
    final List<Rubric> fromInvocation = invocationRubrics
        .map((EvalJsonMap rubric) => Rubric.fromJson(rubric))
        .where((Rubric rubric) {
          if (rubricType.isEmpty || rubric.type == null) {
            return true;
          }
          return rubric.type == rubricType;
        })
        .toList();
    if (fromInvocation.isNotEmpty) {
      return fromInvocation;
    }

    return _criterion.rubrics.where((Rubric rubric) {
      if (rubricType.isEmpty || rubric.type == null) {
        return true;
      }
      return rubric.type == rubricType;
    }).toList();
  }

  List<RubricScore> _scoreRubrics({
    required List<Rubric> rubrics,
    required String candidateText,
  }) {
    final String normalizedCandidate = _normalize(candidateText);
    return rubrics.map((Rubric rubric) {
      final String property = rubric.rubricContent.textProperty ?? '';
      final double score =
          _propertyMatches(
            property: property,
            normalizedCandidate: normalizedCandidate,
          )
          ? 1.0
          : 0.0;
      return RubricScore(
        rubricId: rubric.rubricId,
        rationale: score == 1.0
            ? 'Candidate satisfied rubric text match.'
            : 'Candidate did not satisfy rubric text match.',
        score: score,
      );
    }).toList();
  }

  bool _propertyMatches({
    required String property,
    required String normalizedCandidate,
  }) {
    final List<String> tokens = _normalize(property)
        .split(RegExp(r'\\s+'))
        .where((String token) => token.length >= 4)
        .toList();
    if (tokens.isEmpty) {
      return normalizedCandidate.isNotEmpty;
    }
    int matched = 0;
    for (final String token in tokens) {
      if (normalizedCandidate.contains(token)) {
        matched += 1;
      }
    }
    return matched >= (tokens.length / 2).ceil();
  }
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();
}
