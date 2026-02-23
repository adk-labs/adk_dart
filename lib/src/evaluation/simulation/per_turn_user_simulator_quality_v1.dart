import '../conversation_scenarios.dart';
import '../eval_case.dart';
import '../eval_metrics.dart';
import '../evaluator.dart';
import '../llm_as_judge_utils.dart';

class PerTurnUserSimulatorQualityV1 extends Evaluator {
  PerTurnUserSimulatorQualityV1(EvalMetricSpec evalMetric)
    : _evalMetric = evalMetric {
    if (evalMetric.criterion == null) {
      _criterion = LlmBackedUserSimulatorCriterion(threshold: 0.5);
      return;
    }
    _criterion = evalMetric.criterion is LlmBackedUserSimulatorCriterion
        ? evalMetric.criterion! as LlmBackedUserSimulatorCriterion
        : LlmBackedUserSimulatorCriterion.fromJson(
            evalMetric.criterion!.toJson(),
          );
  }

  final EvalMetricSpec _evalMetric;
  late final LlmBackedUserSimulatorCriterion _criterion;

  @override
  Type get criterionType => LlmBackedUserSimulatorCriterion;

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
    double total = 0.0;
    final double threshold = _evalMetric.threshold ?? _criterion.threshold;
    for (final Invocation invocation in actualInvocations) {
      final String userText = getTextFromContent(invocation.userContent) ?? '';
      final double score = _scoreUserMessage(
        message: userText,
        scenario: conversationScenario,
      );
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: invocation,
          score: score,
          evalStatus: getEvalStatus(score, threshold),
        ),
      );
      total += score;
    }

    final double overall = total / actualInvocations.length;
    return EvaluationResult(
      overallScore: overall,
      overallEvalStatus: getEvalStatus(overall, threshold),
      perInvocationResults: perInvocationResults,
    );
  }

  double _scoreUserMessage({
    required String message,
    required ConversationScenario? scenario,
  }) {
    final String normalizedMessage = _normalize(message);
    if (normalizedMessage.isEmpty) {
      return 0.0;
    }

    if (normalizedMessage.contains(_normalize(_criterion.stopSignal))) {
      return 1.0;
    }

    if (scenario == null) {
      return 1.0;
    }

    final Set<String> messageTokens = _tokenize(normalizedMessage).toSet();
    final Set<String> planTokens = _tokenize(
      '${scenario.startingPrompt} ${scenario.conversationPlan}',
    ).toSet();

    if (planTokens.isEmpty) {
      return 1.0;
    }

    int overlap = 0;
    for (final String token in messageTokens) {
      if (planTokens.contains(token)) {
        overlap += 1;
      }
    }

    if (messageTokens.isEmpty) {
      return 0.0;
    }
    return overlap / messageTokens.length;
  }
}

String _normalize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s</>]'), ' ')
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();
}

List<String> _tokenize(String text) {
  return _normalize(
    text,
  ).split(RegExp(r'\\s+')).where((String token) => token.length >= 3).toList();
}
