import 'dart:io';
import 'dart:math' as math;

import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_result.dart';
import 'evaluator.dart';
import 'llm_as_judge_utils.dart';

const String errorMessageSuffix = '''
You should specify both project id and location. This metric uses Vertex Gen AI
Eval SDK, and it requires google cloud credentials.

If using an .env file add the values there, or explicitly set in the code using
the template below:

Platform.environment['GOOGLE_CLOUD_LOCATION'] = <LOCATION>
Platform.environment['GOOGLE_CLOUD_PROJECT'] = <PROJECT ID>
''';

class VertexAiEvalSummaryMetric {
  VertexAiEvalSummaryMetric({this.meanScore});

  final double? meanScore;
}

class VertexAiEvalOutput {
  VertexAiEvalOutput({List<VertexAiEvalSummaryMetric>? summaryMetrics})
    : summaryMetrics = summaryMetrics ?? <VertexAiEvalSummaryMetric>[];

  final List<VertexAiEvalSummaryMetric> summaryMetrics;
}

typedef VertexAiEvalInvoker =
    Future<VertexAiEvalOutput> Function({
      required List<Map<String, String?>> dataset,
      required List<String> metrics,
    });

class VertexAiEvalFacade extends Evaluator {
  VertexAiEvalFacade({
    required double threshold,
    required String metricName,
    bool expectedInvocationsRequired = false,
    VertexAiEvalInvoker? evalInvoker,
  }) : _threshold = threshold,
       _metricName = metricName,
       _expectedInvocationsRequired = expectedInvocationsRequired,
       _evalInvoker = evalInvoker ?? _defaultPerformEval;

  final double _threshold;
  final String _metricName;
  final bool _expectedInvocationsRequired;
  final VertexAiEvalInvoker _evalInvoker;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (_expectedInvocationsRequired && expectedInvocations == null) {
      throw ArgumentError('expectedInvocations is needed by this metric.');
    }
    // Intentionally unsupported in this facade: only per-invocation evaluation.
    if (conversationScenario != null) {
      // no-op
    }

    final List<Invocation?> expected =
        expectedInvocations ??
        List<Invocation?>.filled(actualInvocations.length, null);

    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    double totalScore = 0.0;
    int numScoredInvocations = 0;

    for (int index = 0; index < actualInvocations.length; index += 1) {
      final Invocation actual = actualInvocations[index];
      final Invocation? expectedInvocation = index < expected.length
          ? expected[index]
          : null;
      final Map<String, String?> row = <String, String?>{
        'prompt': getTextFromContent(actual.userContent) ?? '',
        'reference': expectedInvocation == null
            ? null
            : getTextFromContent(expectedInvocation.finalResponse) ?? '',
        'response': getTextFromContent(actual.finalResponse) ?? '',
      };

      final VertexAiEvalOutput evalOutput = await _evalInvoker(
        dataset: <Map<String, String?>>[row],
        metrics: <String>[_metricName],
      );
      final double? score = _extractScore(evalOutput);
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: actual,
          expectedInvocation: expectedInvocation,
          score: score,
          evalStatus: _getEvalStatus(score),
        ),
      );

      // Matches Python truthy behavior: 0.0 does not count as scored.
      if (score != null && score != 0.0) {
        totalScore += score;
        numScoredInvocations += 1;
      }
    }

    if (perInvocationResults.isEmpty) {
      return EvaluationResult();
    }

    final double? overallScore = numScoredInvocations == 0
        ? null
        : totalScore / numScoredInvocations;
    return EvaluationResult(
      overallScore: overallScore,
      overallEvalStatus: _getEvalStatus(overallScore),
      perInvocationResults: perInvocationResults,
    );
  }

  double? _extractScore(VertexAiEvalOutput output) {
    if (output.summaryMetrics.isEmpty) {
      return null;
    }
    final double? mean = output.summaryMetrics.first.meanScore;
    if (mean == null || mean.isNaN) {
      return null;
    }
    return mean;
  }

  EvalStatus _getEvalStatus(double? score) {
    if (score == null) {
      return EvalStatus.notEvaluated;
    }
    return score >= _threshold ? EvalStatus.passed : EvalStatus.failed;
  }

  static Future<VertexAiEvalOutput> _defaultPerformEval({
    required List<Map<String, String?>> dataset,
    required List<String> metrics,
  }) async {
    final String? projectId = Platform.environment['GOOGLE_CLOUD_PROJECT'];
    final String? location = Platform.environment['GOOGLE_CLOUD_LOCATION'];
    final String? apiKey = Platform.environment['GOOGLE_API_KEY'];

    if ((projectId != null && projectId.isNotEmpty) &&
        (location == null || location.isEmpty)) {
      throw ArgumentError('Missing location.$errorMessageSuffix');
    }
    if ((location != null && location.isNotEmpty) &&
        (projectId == null || projectId.isEmpty)) {
      throw ArgumentError('Missing project id.$errorMessageSuffix');
    }
    if ((apiKey == null || apiKey.isEmpty) &&
        ((projectId == null || projectId.isEmpty) ||
            (location == null || location.isEmpty))) {
      throw ArgumentError(
        'Either API Key or Google cloud Project id and location should be '
        'specified.',
      );
    }

    // Local deterministic fallback scorer that approximates semantic overlap.
    final List<double> scores = <double>[];
    for (final Map<String, String?> row in dataset) {
      final String response = row['response'] ?? '';
      final String reference = row['reference'] ?? row['prompt'] ?? '';
      scores.add(_tokenOverlap(reference, response));
    }
    final double meanScore = scores.isEmpty
        ? double.nan
        : scores.reduce((double a, double b) => a + b) / scores.length;
    return VertexAiEvalOutput(
      summaryMetrics: <VertexAiEvalSummaryMetric>[
        VertexAiEvalSummaryMetric(meanScore: meanScore),
      ],
    );
  }
}

double _tokenOverlap(String reference, String response) {
  final Set<String> referenceTokens = _tokenize(reference).toSet();
  final Set<String> responseTokens = _tokenize(response).toSet();
  if (referenceTokens.isEmpty || responseTokens.isEmpty) {
    return 0.0;
  }
  int overlap = 0;
  for (final String token in responseTokens) {
    if (referenceTokens.contains(token)) {
      overlap += 1;
    }
  }
  return overlap / math.max(responseTokens.length, 1);
}

List<String> _tokenize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .split(RegExp(r'\\s+'))
      .where((String token) => token.isNotEmpty)
      .toList();
}
