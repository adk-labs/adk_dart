import '../models/llm_response.dart';
import '../types/content.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';
import 'llm_as_judge.dart';
import 'llm_as_judge_utils.dart';

const String _finalResponseMatchV2Prompt = '''
You are an expert rater for an AI agent response.
Compare the agent response against the reference response for the same user prompt.

User prompt:
{prompt}

Agent response:
{response}

Reference response:
{golden_response}

Return strict JSON only:
{
  "reasoning": "...",
  "is_the_agent_response_valid": "valid|invalid"
}
''';

Label parseCritique(String response) {
  final RegExp labelValidExp = RegExp(
    r'"is_the_agent_response_valid"\s*:\s*\[*\s*"?([^"\]\s,\}]+)"?\s*\]*',
    caseSensitive: false,
    multiLine: true,
  );
  final RegExp labelInvalidExp = RegExp(
    r'"is_the_agent_response_invalid"\s*:\s*\[*\s*"?([^"\]\s,\}]+)"?\s*\]*',
    caseSensitive: false,
    multiLine: true,
  );

  final RegExpMatch? validMatch = labelValidExp.firstMatch(response);
  if (validMatch != null) {
    final String label = (validMatch.group(1) ?? '').trim().toLowerCase();
    if (label == Label.valid.value || label == Label.trueLabel.value) {
      return Label.valid;
    }
    if (label == Label.invalid.value ||
        label == Label.falseLabel.value ||
        label == Label.almost.value ||
        label == 'partially' ||
        label == 'partially_valid') {
      return Label.invalid;
    }
    return Label.notFound;
  }

  final RegExpMatch? invalidMatch = labelInvalidExp.firstMatch(response);
  if (invalidMatch != null) {
    final String label = (invalidMatch.group(1) ?? '').trim().toLowerCase();
    return (label == Label.trueLabel.value || label == Label.invalid.value)
        ? Label.invalid
        : Label.valid;
  }

  return Label.notFound;
}

class FinalResponseMatchV2Evaluator extends LlmAsJudge {
  FinalResponseMatchV2Evaluator(
    this._evalMetric, {
    AutoRaterInvoker? autoRaterInvoker,
    String? autoRaterPromptTemplate,
  }) : _autoRaterPromptTemplate =
           autoRaterPromptTemplate ?? _finalResponseMatchV2Prompt,
       super(
         evalMetric: _evalMetric,
         expectedInvocationsRequired: true,
         autoRaterInvoker: autoRaterInvoker,
       ) {
    if (_evalMetric.criterion == null) {
      throw ArgumentError(
        '`${_evalMetric.metricName}` metric expects a criterion of type '
        '`$LlmAsAJudgeCriterion`.',
      );
    }
    _criterion = _evalMetric.criterion is LlmAsAJudgeCriterion
        ? _evalMetric.criterion! as LlmAsAJudgeCriterion
        : LlmAsAJudgeCriterion.fromJson(_evalMetric.criterion!.toJson());
  }

  final EvalMetricSpec _evalMetric;
  final String _autoRaterPromptTemplate;
  late final LlmAsAJudgeCriterion _criterion;

  @override
  Type get criterionType => LlmAsAJudgeCriterion;

  @override
  String formatAutoRaterPrompt(
    Invocation actualInvocation,
    Invocation? expectedInvocation,
  ) {
    if (expectedInvocation == null) {
      throw ArgumentError('expectedInvocation is required for this metric.');
    }

    final String reference =
        getTextFromContent(expectedInvocation.finalResponse) ?? '';
    final String response =
        getTextFromContent(actualInvocation.finalResponse) ?? '';
    final String userPrompt =
        getTextFromContent(expectedInvocation.userContent) ?? '';

    return _autoRaterPromptTemplate
        .replaceAll('{prompt}', userPrompt)
        .replaceAll('{response}', response)
        .replaceAll('{golden_response}', reference);
  }

  @override
  AutoRaterScore convertAutoRaterResponseToScore(
    LlmResponse autoRaterResponse,
  ) {
    final String? responseText = getTextFromContent(
      _contentToEvalJson(autoRaterResponse.content),
    );
    if (responseText == null || responseText.isEmpty) {
      return AutoRaterScore();
    }
    final Label label = parseCritique(responseText);
    if (label == Label.valid) {
      return AutoRaterScore(score: 1.0);
    }
    if (label == Label.invalid) {
      return AutoRaterScore(score: 0.0);
    }
    return AutoRaterScore();
  }

  @override
  PerInvocationResult aggregatePerInvocationSamples(
    List<PerInvocationResult> perInvocationSamples,
  ) {
    final List<PerInvocationResult> positive = <PerInvocationResult>[];
    final List<PerInvocationResult> negative = <PerInvocationResult>[];
    for (final PerInvocationResult result in perInvocationSamples) {
      if (result.score == 1.0) {
        positive.add(result);
      } else if (result.score == 0.0) {
        negative.add(result);
      }
    }
    if (positive.isEmpty && negative.isEmpty) {
      return perInvocationSamples.first;
    }
    if (positive.length > negative.length) {
      return positive.first;
    }
    return negative.first;
  }

  @override
  EvaluationResult aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    double numValid = 0.0;
    int numEvaluated = 0;
    for (final PerInvocationResult result in perInvocationResults) {
      if (result.score == null ||
          result.evalStatus == EvalStatus.notEvaluated) {
        continue;
      }
      numEvaluated += 1;
      numValid += result.score!;
    }

    if (numEvaluated == 0) {
      return EvaluationResult(perInvocationResults: perInvocationResults);
    }

    final double overall = numValid / numEvaluated;
    return EvaluationResult(
      overallScore: overall,
      overallEvalStatus: getEvalStatus(overall, _criterion.threshold),
      perInvocationResults: perInvocationResults,
    );
  }
}

EvalJsonMap? _contentToEvalJson(Content? content) {
  if (content == null) {
    return null;
  }
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts
        .map((Part part) => <String, Object?>{'text': part.text ?? ''})
        .toList(),
  };
}
