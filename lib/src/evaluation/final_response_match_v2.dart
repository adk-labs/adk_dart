import '../models/llm_response.dart';
import '../types/content.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';
import 'llm_as_judge.dart';
import 'llm_as_judge_utils.dart';

const String _finalResponseMatchV2Prompt = '''
You are an expert rater for an AI agent. The AI agent is going to call an API to answer the user query and generate API tool use code based for the choice of the API and API arguments. The ideal model response should be a function call that fulfills user query, or a natural language response hedges or asks users for further clarification if a function call does not apply.
The primary focus of this rating task is to check correctness of the model responses.

The data consists of:
- A user query.
- A model generated response for the prompt. The responses can consist of:
  - Natural language, when the model is asking for clarification, or tells the user it does not possess the requested functionality / option.
  - Code, in the form of one or multiple python function calls, and additional code as needed, for when the model is fulfilling the user request.
You can use the help from a reference response annotated by a human rater. This reference response is of high quality. You can compare the agent's response with the reference response and decide if the agent's response is valid.
Note sometimes the reference response only contains the key entities of the correct answer and you need to be flexible to allow the agent response to contain more information than the reference response, or to present the key entities in a different format or structure or in shorter or longer format.
When the agent response is provided in the form of tables/dataframes or should be best provided in the form of tables/dataframes: focus on the key entities and main components requested in the user query and check whether you can retrieve those from the agent response. Likewise, if you have the reference response, then find out the key entities and main components in them and check whether you can retrieve those from the agent response. If the prompt does not specify any format instructions and the main items/components are included in the response then tolerate the differences in the formatting of those tables/dataframes.

You should follow the constitutions below very carefully to rate the model response:
- Allow flexibility of format even when reference code only uses one of the possible format, unless API spec or user prompt has explicit format requirement
  - e.g. For state name, allow both abbreviation and full name unless API spec has explicit requirement. e.g. both 'tx' and 'Texas' should be allowed in the agent response even when reference code only uses one of them.
  - e.g. If a reference response list outputs in a list format, the agent response is allowed to use sentence format and vice versa unless user prompt explicitly asks for a specific format.
  - e.g. For numbers, allow flexibility of formatting, e.g. 1000000 vs 1,000,000.
- The model shouldn't assume that it doesn't have access to according data or incapable of answering the question if reference response is able to find a legit answer.
- If the model response contains the correct final answer, rate it as valid even when the model response contains more information than the reference response.
- If the user prompt has csv or other table format data, don't read it yourself. Trust the reference response final answer instead.
- When the validation needs maths, date calculations, do not use your own calculator. Trust the reference response final answer instead.
- Be mindful about unit of numbers. For example, if the reference response says 100 miles, but the model response says 100 km, it is invalid.
- When the agent response or the reference response is provided in the form of tables/dataframes: focus on the key entities and main components requested in the user query and check whether you can retrieve those from the agent response and whether those match the reference response. If the user query does not specify any format instructions and the main items/components are included in the response then tolerate the differences in the formatting of those tables/dataframes.
- When the answer is in numeric format, check whether there are any format requirements in the numeric format, rounding, precision, number of decimals, etc. specified in the user query and the prompt. If there are no such instructions, then tolerate different numerical formats.
- When the answer is in numeric format and there are rounding or precision differences between the agent response and the reference response, if no further instructions are provided evaluate if the rounding strategy or precision in the agent response follows the standards for that entity. For instance, model accuracy scores must be reported with at least two decimal places (e.g., 0.798 -> 0.80 is acceptable,  but 0.7 is not).

Below are the inputs:
{
  "User prompt": {prompt},
  "Agent response": {response},
  "Reference response": {golden_response},
}

The answer should be a json alone which follows the json structure below:
{
  "reasoning": [reasoning],
  "is_the_agent_response_valid": [valid or invalid],
}
Answer with assertiveness:
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
