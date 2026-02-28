import 'dart:convert';

import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../types/content.dart';
import '_retry_options_utils.dart';
import 'app_details.dart';
import 'conversation_scenarios.dart';
import 'common.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';
import 'llm_as_judge_utils.dart';

const String _hallucinationsV1SegmenterPrompt = '''
You are a helpful and harmless AI assistant. You will be provided with a model-generated response.
Your task is to segment the provided response sentence by sentence so that we could analyze each sentence in the future.

**Instructions:**
1. Overall, you should decompose the whole provided response into individual sentences. You should make sure the output covers ALL the sentences in the provided response block.
2. You should COPY each sentence as it is, WORD BY WORD. DO NOT modify the sentence or the surrounding punctuation.
3. If there are bullet points in the response, you should segment each bullet point into DIFFERENT sentences. If one bullet point has sub bullet points, you should further decompose sub bullet points into DIFFERENT sentences.
For example, if there are responses like "it has three criteria: * aaa. * bbb. * ccc", you should segment them into FOUR sentences: "it has three criteria", "aaa", "bbb", "ccc". Bullet points could start with numbers (1/2/3/etc) or symbols like "*", "-" etc.
4. When encountering tables, you should include the whole table in ONE sentence output.
5. Each sentence should be meaningful to further analyze on. DO NOT ONLY put symbols themselves into a sentence.
6. You should ONLY output segmented sentences in the provided response. DO NOT make up any new sentences.

**Input Format:**

The input will be the model-generated response:
* **Response:** The model-generated response to be analyzed.

**Output Format:**
For each decomposed sentence, wrap them with <sentence> and </sentence> like the following:
<sentence>...</sentence>
<sentence>...</sentence>

**Example:**

**Input:**

**Response Begin**
There are three kinds of fruits:
1. Apples are red.
2. Bananas are green.
3. Pears are purple.

For prices:
* Bananas are cheaper than apples.

Enjoy your fruit!
**Response End**

**Output:**
<sentence>There are three kinds of fruits:</sentence>
<sentence>1. Apples are red.</sentence>
<sentence>2. Bananas are green.</sentence>
<sentence>3. Pears are purple.</sentence>
<sentence>For prices:</sentence>
<sentence>* Bananas are cheaper than apples.</sentence>
<sentence>Enjoy your fruit!</sentence>

**Now, given the following response, please segment the response into sentences:**

**Input:**
**Response Begin**
{response}
**Response End**

**Your Sentence Segmentation Output:**
''';

const String _hallucinationsV1ValidatorPrompt = '''
You are a helpful and harmless AI assistant. You will be provided with a textual context and sentences from a model-generated response.
Your task is to analyze sentence by sentence and classify each sentence according to its relationship with the provided context.

**Instructions:**

1. **Read the textual context carefully.**
2. **For each sentence, assign one of the following labels:**
    * **`supported`**: The sentence is entailed by the given context. Provide a supporting excerpt from the context. The supporting except must *fully* entail the sentence.
    * **`unsupported`**: The sentence is not entailed by the given context. No excerpt is needed for this label.
    * **`contradictory`**: The sentence is falsified by the given context. Provide a contradicting excerpt from the context.
    * **`disputed`**: The given context contains both supporting and contradicting information. Provide both supporting and contradicting excerpt from the context.
    * **`not_applicable`**: The sentence does not require factual attribution (e.g., opinions, planning steps, greetings, questions, disclaimers, mathematical calculation).
3. **For each label, provide a short rationale explaining your decision.** The rationale should be separate from the excerpt.
4. **Be very strict with your `supported`, `contradictory` and `disputed` decisions.** Unless you can find straightforward, indisputable evidence excepts *in the context* that a sentence is `supported`, `contradictory` or `disputed`, consider it `unsupported`.  You should not employ world knowledge unless it is truly trivial.
5. "tool_outputs" blocks contain code execution results of the "tool_code" blocks immediately above them. If any sentence is based on "tool_outputs" results, first analyze if the corresponding "tool_code" is supported and if the results are error-free. Only if the "tool_code" block is supported, you can treat code execution results as correct.
6. If you need to cite multiple supporting excerpts, simply concatenate them. Excerpt could be summary from the context if it is too long.

**Input Format:**

The input will consist of two parts, clearly separated:

* **Context:**  The textual context used to generate the response.
* **Sentences:** The sentences from the model-generated response to be analyzed. Each sentence will be wrapped in <sentence>...</sentence>.

**Output Format:**

For each sentence, output a block of text with the following fields:

* sentence: The sentence being analyzed. Please directly copy the sentence which is provided.
* label: One of `supported`, `unsupported`, `contradictory`, `disputed` or `not_applicable`.
* rationale: A brief explanation for the assessment
* supporting_excerpt: A relevant excerpt from the context that supports the sentence. Only required for `supported` and `disputed` labels.
* contradicting_excerpt: A relevant excerpt from the context that contradicts with the sentence. Only required for `contradictory` and `disputed` labels.

**Example:**

**Input:**

**Context Begin**
Apples are red fruits. Bananas are yellow fruits. Pears are purple fruits. Pears are blue fruits.
**Context End**

**Sentences Begin**
<sentence>Apples are red.</sentence>
<sentence>Bananas are green.</sentence>
<sentence>Pears are purple.</sentence>
<sentence>Bananas are cheaper than apples.</sentence>
<sentence>Enjoy your fruit!</sentence>
**Sentences End**

**Output:**
sentence: Apples are red.
label: supported
rationale: The context explicitly states that apples are red.
supporting_excerpt: Apples are red fruits.
contradicting_excerpt: null

sentence: Bananas are green.
label: contradictory
rationale: The context states that bananas are yellow, not green.
supporting_excerpt: null
contradicting_excerpt: Bananas are yellow fruits.

sentence: Pears are purple.
label: disputed
rationale: The context states that pears are purple but it also states that pears are blue.
supporting_excerpt: Pears are purple fruits
contradicting_excerpt: Pears are blue fruits

sentence: Bananas are cheaper than apples.
label: unsupported
rationale: The context does not mention the price of bananas or apples.
supporting_excerpt: null
contradicting_excerpt: null

sentence: Enjoy your fruit!
label: not_applicable
rationale: This is a general expression and does not require factual attribution.
supporting_excerpt: null
contradicting_excerpt: null

**Now, please analyze the following context and sentences:**

**Input:**
**Context Begin**
{context}
**Context End**

**Sentences Begin**
{sentences}
**Sentences End**

**Output:**
''';

const Set<String> _positiveLabels = <String>{'supported', 'not_applicable'};
const Set<String> _negativeLabels = <String>{
  'unsupported',
  'contradictory',
  'disputed',
};

class _EvaluationStep {
  _EvaluationStep({required this.context, required this.nlResponse});

  final String context;
  final String nlResponse;
}

class HallucinationsV1Evaluator extends Evaluator {
  HallucinationsV1Evaluator(
    EvalMetricSpec evalMetric, {
    BaseLlm Function(String model)? llmFactory,
  }) : _evalMetric = evalMetric,
       _llmFactory = llmFactory ?? LLMRegistry.newLlm {
    if (_evalMetric.criterion == null) {
      throw ArgumentError(
        '`${_evalMetric.metricName}` metric expects a criterion of type '
        '`$HallucinationsCriterion`.',
      );
    }

    _criterion = _evalMetric.criterion is HallucinationsCriterion
        ? _evalMetric.criterion! as HallucinationsCriterion
        : HallucinationsCriterion.fromJson(_evalMetric.criterion!.toJson());

    _judgeModelOptions = _criterion.judgeModelOptions;
    _judgeModel = _llmFactory(_judgeModelOptions.judgeModel);
  }

  final EvalMetricSpec _evalMetric;
  final BaseLlm Function(String model) _llmFactory;

  late final HallucinationsCriterion _criterion;
  late final JudgeModelOptions _judgeModelOptions;
  late final BaseLlm _judgeModel;

  String segmenterPrompt = _hallucinationsV1SegmenterPrompt;
  String sentenceValidatorPrompt = _hallucinationsV1ValidatorPrompt;

  @override
  Type get criterionType => HallucinationsCriterion;

  @override
  Future<EvaluationResult> evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) async {
    if (conversationScenario != null) {
      // This metric ignores conversation scenario input.
    }

    if (actualInvocations.isEmpty) {
      return EvaluationResult();
    }

    final List<Invocation?> expected = expectedInvocations == null
        ? List<Invocation?>.filled(actualInvocations.length, null)
        : expectedInvocations;

    final int count = expectedInvocations == null
        ? actualInvocations.length
        : actualInvocations.length < expected.length
        ? actualInvocations.length
        : expected.length;

    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];

    for (int i = 0; i < count; i += 1) {
      final Invocation actual = actualInvocations[i];
      final Invocation? expectedInvocation = expected[i];

      final List<_EvaluationStep> stepEvaluations = _getStepsToEvaluate(actual);
      if (stepEvaluations.isEmpty) {
        perInvocationResults.add(
          PerInvocationResult(
            actualInvocation: actual,
            expectedInvocation: expectedInvocation,
            score: null,
            evalStatus: EvalStatus.notEvaluated,
          ),
        );
        continue;
      }

      final List<double> scoresPerStep = <double>[];
      for (final _EvaluationStep step in stepEvaluations) {
        final double? score = await _evaluateNlResponse(
          nlResponse: step.nlResponse,
          context: step.context,
        );
        if (score != null) {
          scoresPerStep.add(score);
        }
      }

      final double? invocationScore = scoresPerStep.isEmpty
          ? null
          : scoresPerStep.reduce((double a, double b) => a + b) /
                scoresPerStep.length;

      perInvocationResults.add(
        PerInvocationResult(
          actualInvocation: actual,
          expectedInvocation: expectedInvocation,
          score: invocationScore,
          evalStatus: getEvalStatus(
            invocationScore,
            _evalMetric.threshold ?? _criterion.threshold,
          ),
        ),
      );
    }

    return _aggregateInvocationResults(perInvocationResults);
  }

  Future<double?> _evaluateNlResponse({
    required String nlResponse,
    required String context,
  }) async {
    final LlmResponse? segmenterResponse = await _invokeJudge(
      segmenterPrompt.replaceAll('{response}', nlResponse),
    );
    if (segmenterResponse == null) {
      return null;
    }

    final String segmenterText =
        getTextFromContent(_contentToEvalJson(segmenterResponse.content)) ?? '';
    final List<String> sentences = _parseSentences(segmenterText);
    if (sentences.isEmpty) {
      return null;
    }

    final String sentencesBlock = sentences
        .map((String sentence) => '<sentence>$sentence</sentence>')
        .join('\n');
    final String validatorPrompt = sentenceValidatorPrompt
        .replaceAll('{context}', context)
        .replaceAll('{sentences}', sentencesBlock);

    final LlmResponse? validatorResponse = await _invokeJudge(validatorPrompt);
    if (validatorResponse == null) {
      return null;
    }

    final String validatorText =
        getTextFromContent(_contentToEvalJson(validatorResponse.content)) ?? '';
    final List<Map<String, Object?>> validationResults =
        _parseValidationResults(validatorText);

    final List<double> scores = <double>[];
    for (final Map<String, Object?> result in validationResults) {
      final String label = (result['label'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (_positiveLabels.contains(label)) {
        scores.add(1.0);
      } else if (_negativeLabels.contains(label)) {
        scores.add(0.0);
      }
    }

    if (scores.isEmpty) {
      return null;
    }
    return scores.reduce((double a, double b) => a + b) / scores.length;
  }

  Future<LlmResponse?> _invokeJudge(String prompt) async {
    final Object? rawModelConfig = _judgeModelOptions.judgeModelConfig;
    final GenerateContentConfig modelConfig =
        rawModelConfig is GenerateContentConfig
        ? rawModelConfig.copyWith()
        : GenerateContentConfig();

    final LlmRequest llmRequest = LlmRequest(
      model: _judgeModelOptions.judgeModel,
      contents: <Content>[Content.userText(prompt)],
      config: modelConfig,
    );
    addDefaultRetryOptionsIfNotPresent(llmRequest);

    await for (final LlmResponse response in _judgeModel.generateContent(
      llmRequest,
      stream: false,
    )) {
      return response;
    }
    return null;
  }

  String _createContextForStep(
    AppDetails? appDetails,
    Invocation invocation,
    List<InvocationEvent> events,
  ) {
    String developerInstructions = '';
    String toolDeclarations = 'Agent has no tools.';

    if (appDetails != null) {
      final List<String> instructionBlocks = <String>[];
      appDetails.agentDetails.forEach((String agentName, AgentDetails _) {
        final String instructions = appDetails.getDeveloperInstructions(
          agentName,
        );
        if (instructions.isNotEmpty) {
          instructionBlocks.add('$agentName:\n$instructions');
        }
      });
      developerInstructions = instructionBlocks.join('\n\n');
      toolDeclarations = getToolDeclarationsAsJsonStr(appDetails);
    }

    final List<String> contextParts = <String>[];
    contextParts.add('Developer instructions:\n$developerInstructions\n');
    contextParts.add(
      'User prompt:\n${getTextFromContent(invocation.userContent)}\n',
    );
    contextParts.add('Tool definitions:');
    contextParts.add('$toolDeclarations\n');

    for (final InvocationEvent event in events) {
      final EvalJsonMap? content = event.content;
      if (content == null) {
        continue;
      }

      final List<EvalJsonMap> toolCalls = <EvalJsonMap>[];
      final List<EvalJsonMap> toolResponses = <EvalJsonMap>[];
      final List<String> nlResponses = <String>[];

      for (final Object? rawPart in asObjectList(content['parts'])) {
        final EvalJsonMap part = asEvalJson(rawPart);

        final EvalJsonMap? functionCall =
            part['function_call'] == null && part['functionCall'] == null
            ? null
            : asEvalJson(part['function_call'] ?? part['functionCall']);
        if (functionCall != null && functionCall.isNotEmpty) {
          toolCalls.add(functionCall);
        }

        final EvalJsonMap? functionResponse =
            part['function_response'] == null &&
                part['functionResponse'] == null
            ? null
            : asEvalJson(part['function_response'] ?? part['functionResponse']);
        if (functionResponse != null && functionResponse.isNotEmpty) {
          toolResponses.add(functionResponse);
        }

        final String? text = asNullableString(part['text']);
        if (text != null && text.isNotEmpty) {
          nlResponses.add(text);
        }
      }

      if (nlResponses.isNotEmpty) {
        contextParts.add('${nlResponses.join('\n')}\n');
      }
      if (toolCalls.isNotEmpty) {
        contextParts.add('tool_calls:');
        contextParts.add(
          '${const JsonEncoder.withIndent('  ').convert(toolCalls)}\n',
        );
      }
      if (toolResponses.isNotEmpty) {
        contextParts.add('tool_outputs:');
        contextParts.add(
          '${const JsonEncoder.withIndent('  ').convert(toolResponses)}\n',
        );
      }
    }

    return contextParts.join('\n');
  }

  List<_EvaluationStep> _getStepsToEvaluate(Invocation actual) {
    final List<_EvaluationStep> stepEvaluations = <_EvaluationStep>[];
    final List<InvocationEvent> eventsForContext = <InvocationEvent>[];

    final List<InvocationEvent> allEvents =
        actual.intermediateData is InvocationEvents
        ? (actual.intermediateData! as InvocationEvents).invocationEvents
        : <InvocationEvent>[];

    if (_criterion.evaluateIntermediateNlResponses) {
      for (final InvocationEvent event in allEvents) {
        final List<String> nlParts = <String>[];
        final EvalJsonMap? content = event.content;
        if (content != null) {
          for (final Object? rawPart in asObjectList(content['parts'])) {
            final String? text = asNullableString(asEvalJson(rawPart)['text']);
            if (text != null && text.isNotEmpty) {
              nlParts.add(text);
            }
          }
        }

        if (nlParts.isNotEmpty) {
          final String context = _createContextForStep(
            actual.appDetails,
            actual,
            eventsForContext,
          );
          for (final String nlResponse in nlParts) {
            stepEvaluations.add(
              _EvaluationStep(nlResponse: nlResponse, context: context),
            );
          }
        }
        eventsForContext.add(event);
      }
    } else {
      eventsForContext.addAll(allEvents);
    }

    final String? finalResponseText = getTextFromContent(actual.finalResponse);
    if (finalResponseText != null && finalResponseText.isNotEmpty) {
      final String context = _createContextForStep(
        actual.appDetails,
        actual,
        eventsForContext,
      );
      stepEvaluations.add(
        _EvaluationStep(nlResponse: finalResponseText, context: context),
      );
    }

    return stepEvaluations;
  }

  EvaluationResult _aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    final List<PerInvocationResult> validResults = perInvocationResults
        .where((PerInvocationResult result) => result.score != null)
        .toList();
    if (validResults.isEmpty) {
      return EvaluationResult(
        overallScore: null,
        overallEvalStatus: EvalStatus.notEvaluated,
        perInvocationResults: perInvocationResults,
      );
    }

    final double overallScore =
        validResults
            .map((PerInvocationResult value) => value.score!)
            .reduce((double a, double b) => a + b) /
        validResults.length;

    return EvaluationResult(
      overallScore: overallScore,
      overallEvalStatus: getEvalStatus(
        overallScore,
        _evalMetric.threshold ?? _criterion.threshold,
      ),
      perInvocationResults: perInvocationResults,
    );
  }
}

List<String> _parseSentences(String responseText) {
  final RegExp sentencePattern = RegExp(
    r'<sentence>(.*?)</sentence>',
    caseSensitive: false,
    dotAll: true,
  );
  return sentencePattern
      .allMatches(responseText)
      .map((RegExpMatch match) => (match.group(1) ?? '').trim())
      .where((String sentence) => sentence.isNotEmpty)
      .toList();
}

List<Map<String, Object?>> _parseValidationResults(String responseText) {
  final RegExp pattern = RegExp(
    r'sentence:(.*?)\nlabel:(.*?)\nrationale:(.*?)\nsupporting_excerpt:(.*?)\ncontradicting_excerpt:(.*?)(?=\nsentence:|$)',
    caseSensitive: false,
    dotAll: true,
  );

  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  for (final RegExpMatch match in pattern.allMatches(responseText.trim())) {
    final String sentence = (match.group(1) ?? '').trim();
    final String label = (match.group(2) ?? '').trim();
    final String rationale = (match.group(3) ?? '').trim();
    final String supportingExcerptRaw = (match.group(4) ?? '').trim();
    final String contradictingExcerptRaw = (match.group(5) ?? '').trim();

    results.add(<String, Object?>{
      'sentence': sentence,
      'label': label,
      'rationale': rationale,
      'supporting_excerpt': supportingExcerptRaw.toLowerCase() == 'null'
          ? null
          : supportingExcerptRaw,
      'contradicting_excerpt': contradictingExcerptRaw.toLowerCase() == 'null'
          ? null
          : contradictingExcerptRaw,
    });
  }
  return results;
}

EvalJsonMap? _contentToEvalJson(Content? content) {
  if (content == null) {
    return null;
  }
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts.map((Part part) {
      if (part.functionCall != null) {
        return <String, Object?>{
          'function_call': <String, Object?>{
            'name': part.functionCall!.name,
            'args': part.functionCall!.args,
            if (part.functionCall!.id != null) 'id': part.functionCall!.id,
          },
        };
      }
      if (part.functionResponse != null) {
        return <String, Object?>{
          'function_response': <String, Object?>{
            'name': part.functionResponse!.name,
            'response': part.functionResponse!.response,
            if (part.functionResponse!.id != null)
              'id': part.functionResponse!.id,
          },
        };
      }
      return <String, Object?>{'text': part.text ?? ''};
    }).toList(),
  };
}
