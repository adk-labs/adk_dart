import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';
import 'llm_as_judge_utils.dart';

class HallucinationsV1Evaluator extends Evaluator {
  HallucinationsV1Evaluator(EvalMetricSpec evalMetric) {
    if (evalMetric.criterion == null) {
      throw ArgumentError(
        '`${evalMetric.metricName}` metric expects a criterion of type `${HallucinationsCriterion}`.',
      );
    }
    _criterion = evalMetric.criterion is HallucinationsCriterion
        ? evalMetric.criterion! as HallucinationsCriterion
        : HallucinationsCriterion.fromJson(evalMetric.criterion!.toJson());
  }

  late final HallucinationsCriterion _criterion;

  @override
  Type get criterionType => HallucinationsCriterion;

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
    for (final Invocation invocation in actualInvocations) {
      final String response =
          getTextFromContent(invocation.finalResponse) ?? '';
      final String context = _buildContext(invocation);
      final double score = _groundingScore(
        response: response,
        context: context,
      );
      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: invocation,
          score: score,
          evalStatus: getEvalStatus(score, _criterion.threshold),
        ),
      );
      total += score;
    }

    final double overall = total / actualInvocations.length;
    return EvaluationResult(
      overallScore: overall,
      overallEvalStatus: getEvalStatus(overall, _criterion.threshold),
      perInvocationResults: perInvocationResults,
    );
  }

  String _buildContext(Invocation invocation) {
    final StringBuffer buffer = StringBuffer();
    final String userPrompt = getTextFromContent(invocation.userContent) ?? '';
    if (userPrompt.isNotEmpty) {
      buffer.writeln(userPrompt);
    }
    for (final (EvalJsonMap call, EvalJsonMap? response)
        in getAllToolCallsWithResponses(invocation.intermediateData)) {
      final String name = (call['name'] ?? '').toString();
      if (name.isNotEmpty) {
        buffer.writeln(name);
      }
      if (response != null) {
        buffer.writeln(response.toString());
      }
    }

    if (_criterion.evaluateIntermediateNlResponses &&
        invocation.intermediateData is IntermediateData) {
      final IntermediateData data =
          invocation.intermediateData! as IntermediateData;
      for (final InvocationResponse response in data.intermediateResponses) {
        for (final EvalJsonMap part in response.parts) {
          final String text = (part['text'] ?? '').toString();
          if (text.isNotEmpty) {
            buffer.writeln(text);
          }
        }
      }
    }
    return buffer.toString();
  }
}

double _groundingScore({required String response, required String context}) {
  final List<String> responseTokens = _tokenize(response);
  final Set<String> contextTokens = _tokenize(context).toSet();
  if (responseTokens.isEmpty) {
    return 0.0;
  }
  int grounded = 0;
  for (final String token in responseTokens) {
    if (_isAllowedGenericToken(token) || contextTokens.contains(token)) {
      grounded += 1;
    }
  }
  return grounded / responseTokens.length;
}

bool _isAllowedGenericToken(String token) {
  const Set<String> generic = <String>{
    'the',
    'a',
    'an',
    'and',
    'or',
    'is',
    'are',
    'to',
    'for',
    'of',
    'in',
    'on',
    'it',
    'this',
    'that',
    'you',
    'i',
    'we',
    'can',
    'could',
    'would',
    'should',
  };
  return generic.contains(token);
}

List<String> _tokenize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
      .split(RegExp(r'\\s+'))
      .where((String token) => token.isNotEmpty)
      .toList();
}
