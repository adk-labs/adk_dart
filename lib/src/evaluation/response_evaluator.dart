import 'conversation_scenarios.dart';
import 'common.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';
import 'final_response_match_v1.dart';

class ResponseEvaluator extends Evaluator {
  ResponseEvaluator({
    double? threshold,
    String? metricName,
    EvalMetricSpec? evalMetric,
  }) {
    if ((threshold != null && evalMetric != null) ||
        (metricName != null && evalMetric != null)) {
      throw ArgumentError(
        'Either evalMetric should be specified or both threshold and metricName should be specified.',
      );
    }

    if (evalMetric != null) {
      _threshold = evalMetric.threshold;
      _metricName = evalMetric.metricName;
    } else {
      _threshold = threshold;
      _metricName = metricName ?? PrebuiltMetricNames.responseMatchScore;
    }

    if (_metricName != PrebuiltMetricNames.responseEvaluationScore &&
        _metricName != PrebuiltMetricNames.responseMatchScore) {
      throw ArgumentError('`$_metricName` is not supported.');
    }
  }

  late final String _metricName;
  late final double? _threshold;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (_metricName == PrebuiltMetricNames.responseMatchScore) {
      return RougeEvaluator(
        EvalMetricSpec(metricName: _metricName, threshold: _threshold),
      ).evaluateInvocations(
        actualInvocations: actualInvocations,
        expectedInvocations: expectedInvocations,
        conversationScenario: conversationScenario,
      );
    }

    final List<Invocation> expected = expectedInvocations ?? <Invocation>[];
    final int count = actualInvocations.length < expected.length
        ? actualInvocations.length
        : expected.isEmpty
        ? actualInvocations.length
        : expected.length;
    if (count == 0) {
      return EvaluationResult();
    }

    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    double total = 0.0;
    for (int i = 0; i < count; i += 1) {
      final Invocation actual = actualInvocations[i];
      final Invocation? expectedInvocation = expected.isEmpty
          ? null
          : expected[i];
      final String response = _textFromContent(actual.finalResponse);
      final String reference = expectedInvocation == null
          ? ''
          : _textFromContent(expectedInvocation.finalResponse);

      final double score = _coherenceScore(
        response: response,
        reference: reference,
      );
      final double threshold = _threshold ?? 3.0;
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: actual,
          expectedInvocation: expectedInvocation,
          score: score,
          evalStatus: score >= threshold
              ? EvalStatus.passed
              : EvalStatus.failed,
        ),
      );
      total += score;
    }

    final double overallScore = total / count;
    return EvaluationResult(
      overallScore: overallScore,
      overallEvalStatus: overallScore >= (_threshold ?? 3.0)
          ? EvalStatus.passed
          : EvalStatus.failed,
      perInvocationResults: perInvocationResults,
    );
  }
}

String _textFromContent(EvalJsonMap? content) {
  if (content == null) {
    return '';
  }
  return asObjectList(content['parts'])
      .map((Object? value) => asNullableString(asEvalJson(value)['text']) ?? '')
      .where((String text) => text.isNotEmpty)
      .join('\n');
}

double _coherenceScore({required String response, required String reference}) {
  if (response.trim().isEmpty) {
    return 1.0;
  }
  if (reference.trim().isEmpty) {
    final int tokens = response
        .split(RegExp(r'\s+'))
        .where((String t) => t.isNotEmpty)
        .length;
    if (tokens >= 20) {
      return 5.0;
    }
    if (tokens >= 10) {
      return 4.0;
    }
    if (tokens >= 4) {
      return 3.0;
    }
    return 2.0;
  }

  final List<String> responseTokens = _tokenize(response);
  final List<String> referenceTokens = _tokenize(reference);
  if (responseTokens.isEmpty || referenceTokens.isEmpty) {
    return 1.0;
  }
  final Set<String> referenceSet = referenceTokens.toSet();
  int overlap = 0;
  for (final String token in responseTokens) {
    if (referenceSet.contains(token)) {
      overlap += 1;
    }
  }
  final double ratio = overlap / referenceTokens.length;
  if (ratio >= 0.85) {
    return 5.0;
  }
  if (ratio >= 0.6) {
    return 4.0;
  }
  if (ratio >= 0.35) {
    return 3.0;
  }
  if (ratio >= 0.1) {
    return 2.0;
  }
  return 1.0;
}

List<String> _tokenize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .split(RegExp(r'\\s+'))
      .where((String token) => token.isNotEmpty)
      .toList();
}
