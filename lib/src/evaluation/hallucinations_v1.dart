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
4. When encountering tables, you should include the whole table in ONE sentence output.
5. Each sentence should be meaningful to further analyze on. DO NOT ONLY put symbols themselves into a sentence.
6. You should ONLY output segmented sentences in the provided response. DO NOT make up any new sentences.

**Input Format:**
The input will be the model-generated response.

**Output Format:**
For each decomposed sentence, wrap them with <sentence> and </sentence>.

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
1. For each sentence, assign one label: supported, unsupported, contradictory, disputed, or not_applicable.
2. Provide a short rationale for each sentence.
3. Use supported/contradictory/disputed only when clear evidence exists in context.
4. If sentence is based on tool_outputs, ensure corresponding tool_calls are supported.

**Output Format:**
sentence: <sentence>
label: <supported|unsupported|contradictory|disputed|not_applicable>
rationale: <brief explanation>
supporting_excerpt: <text or null>
contradicting_excerpt: <text or null>

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
