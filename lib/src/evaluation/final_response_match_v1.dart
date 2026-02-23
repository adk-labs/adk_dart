import 'conversation_scenarios.dart';
import 'common.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';

class RougeEvaluator extends Evaluator {
  RougeEvaluator(this._evalMetric);

  final EvalMetricSpec _evalMetric;

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
    double totalScore = 0.0;
    for (int i = 0; i < count; i += 1) {
      final Invocation actual = actualInvocations[i];
      final Invocation expected = expectedInvocations[i];
      final String reference = _getTextFromContent(expected.finalResponse);
      final String response = _getTextFromContent(actual.finalResponse);
      final double score = _calculateRouge1FMeasure(
        candidate: response,
        reference: reference,
      );
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: actual,
          expectedInvocation: expected,
          score: score,
          evalStatus: _getEvalStatus(score, _evalMetric.threshold ?? 0.0),
        ),
      );
      totalScore += score;
    }

    final double overallScore = totalScore / count;
    return EvaluationResult(
      overallScore: overallScore,
      overallEvalStatus: _getEvalStatus(
        overallScore,
        _evalMetric.threshold ?? 0.0,
      ),
      perInvocationResults: perInvocationResults,
    );
  }
}

String _getTextFromContent(EvalJsonMap? content) {
  if (content == null) {
    return '';
  }
  final List<Object?> parts = asObjectList(content['parts']);
  final List<String> texts = <String>[];
  for (final Object? part in parts) {
    final String? text = asNullableString(asEvalJson(part)['text']);
    if (text != null) {
      texts.add(text);
    }
  }
  return texts.join('\n');
}

EvalStatus _getEvalStatus(double score, double threshold) {
  return score >= threshold ? EvalStatus.passed : EvalStatus.failed;
}

double _calculateRouge1FMeasure({
  required String candidate,
  required String reference,
}) {
  final List<String> candidateTokens = _tokenize(candidate);
  final List<String> referenceTokens = _tokenize(reference);
  if (candidateTokens.isEmpty || referenceTokens.isEmpty) {
    return 0.0;
  }

  final Map<String, int> candidateCounts = _countTokens(candidateTokens);
  final Map<String, int> referenceCounts = _countTokens(referenceTokens);

  int overlap = 0;
  referenceCounts.forEach((String token, int refCount) {
    final int candCount = candidateCounts[token] ?? 0;
    overlap += candCount < refCount ? candCount : refCount;
  });

  final double precision = overlap / candidateTokens.length;
  final double recall = overlap / referenceTokens.length;
  if (precision + recall == 0) {
    return 0.0;
  }
  return 2 * precision * recall / (precision + recall);
}

List<String> _tokenize(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .split(RegExp(r'\\s+'))
      .where((String token) => token.isNotEmpty)
      .toList();
}

Map<String, int> _countTokens(List<String> tokens) {
  final Map<String, int> counts = <String, int>{};
  for (final String token in tokens) {
    counts[token] = (counts[token] ?? 0) + 1;
  }
  return counts;
}
