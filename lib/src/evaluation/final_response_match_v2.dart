import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';
import 'llm_as_judge_utils.dart';

Label parseCritique(String response) {
  final RegExp labelValidExp = RegExp(
    r'"is_the_agent_response_valid"\s*:\s*\[*\s*"?([^"\\]\\s]+)"?',
    caseSensitive: false,
    multiLine: true,
  );
  final RegExp labelInvalidExp = RegExp(
    r'"is_the_agent_response_invalid"\s*:\s*\[*\s*"?([^"\\]\\s]+)"?',
    caseSensitive: false,
    multiLine: true,
  );

  final RegExpMatch? validMatch = labelValidExp.firstMatch(response);
  if (validMatch != null) {
    final String label = (validMatch.group(1) ?? '').trim().toLowerCase();
    if (label == 'valid' || label == 'true') {
      return Label.valid;
    }
    if (label == 'invalid' ||
        label == 'false' ||
        label == 'almost' ||
        label == 'partially' ||
        label == 'partially_valid') {
      return Label.invalid;
    }
    return Label.notFound;
  }

  final RegExpMatch? invalidMatch = labelInvalidExp.firstMatch(response);
  if (invalidMatch != null) {
    final String label = (invalidMatch.group(1) ?? '').trim().toLowerCase();
    return (label == 'true' || label == 'invalid')
        ? Label.invalid
        : Label.valid;
  }

  return Label.notFound;
}

class FinalResponseMatchV2Evaluator extends Evaluator {
  FinalResponseMatchV2Evaluator(this._evalMetric);

  final EvalMetricSpec _evalMetric;

  @override
  Type get criterionType => LlmAsAJudgeCriterion;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (expectedInvocations == null) {
      throw ArgumentError('expectedInvocations is required for this metric.');
    }
    final int count = actualInvocations.length < expectedInvocations.length
        ? actualInvocations.length
        : expectedInvocations.length;
    if (count == 0) {
      return EvaluationResult();
    }

    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    double evaluated = 0.0;
    double valid = 0.0;
    final double threshold = _evalMetric.threshold ?? 0.5;

    for (int i = 0; i < count; i += 1) {
      final Invocation actual = actualInvocations[i];
      final Invocation expected = expectedInvocations[i];
      final double score = _scoreSingle(actual: actual, expected: expected);
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: actual,
          expectedInvocation: expected,
          score: score,
          evalStatus: getEvalStatus(score, threshold),
        ),
      );
      evaluated += 1;
      valid += score;
    }

    final double overall = valid / evaluated;
    return EvaluationResult(
      overallScore: overall,
      overallEvalStatus: getEvalStatus(overall, threshold),
      perInvocationResults: perInvocationResults,
    );
  }
}

double _scoreSingle({
  required Invocation actual,
  required Invocation expected,
}) {
  final String response = (getTextFromContent(actual.finalResponse) ?? '')
      .trim();
  final String reference = (getTextFromContent(expected.finalResponse) ?? '')
      .trim();
  if (response.isEmpty || reference.isEmpty) {
    return 0.0;
  }

  if (_normalize(response) == _normalize(reference)) {
    return 1.0;
  }

  final Set<String> responseTokens = _normalize(
    response,
  ).split(RegExp(r'\s+')).where((String token) => token.isNotEmpty).toSet();
  final List<String> referenceTokens = _normalize(
    reference,
  ).split(RegExp(r'\s+')).where((String token) => token.isNotEmpty).toList();
  if (referenceTokens.isEmpty) {
    return 0.0;
  }
  int overlap = 0;
  for (final String token in referenceTokens) {
    if (responseTokens.contains(token)) {
      overlap += 1;
    }
  }
  final double ratio = overlap / referenceTokens.length;
  return ratio >= 0.75 ? 1.0 : 0.0;
}

String _normalize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();
}
