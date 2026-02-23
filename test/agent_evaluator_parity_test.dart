import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _EchoAgent extends BaseAgent {
  _EchoAgent() : super(name: 'echo_agent');

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final String input =
        context.userContent?.parts
            .map((Part p) => p.text ?? '')
            .where((String t) => t.isNotEmpty)
            .join(' ') ??
        '';
    yield Event(
      invocationId: context.invocationId,
      author: name,
      content: Content.modelText('Echo: $input'),
    );
  }
}

class _BinaryJudgeEvaluator extends LlmAsJudge {
  _BinaryJudgeEvaluator({
    required EvalMetricSpec evalMetric,
    required AutoRaterInvoker autoRaterInvoker,
  }) : super(
         evalMetric: evalMetric,
         expectedInvocationsRequired: true,
         autoRaterInvoker: autoRaterInvoker,
       );

  @override
  String formatAutoRaterPrompt(
    Invocation actualInvocation,
    Invocation? expectedInvocation,
  ) {
    return getTextFromContent(actualInvocation.finalResponse) ?? '';
  }

  @override
  AutoRaterScore convertAutoRaterResponseToScore(
    LlmResponse autoRaterResponse,
  ) {
    final String text =
        autoRaterResponse.content?.parts
            .map((Part p) => p.text ?? '')
            .join(' ') ??
        '';
    return AutoRaterScore(score: text.contains('valid') ? 1.0 : 0.0);
  }

  @override
  PerInvocationResult aggregatePerInvocationSamples(
    List<PerInvocationResult> perInvocationSamples,
  ) {
    final double total = perInvocationSamples.fold<double>(
      0,
      (double acc, PerInvocationResult value) => acc + (value.score ?? 0.0),
    );
    final double mean = total / perInvocationSamples.length;
    final PerInvocationResult first = perInvocationSamples.first;
    return PerInvocationResult(
      actualInvocation: first.actualInvocation,
      expectedInvocation: first.expectedInvocation,
      score: mean >= 0.5 ? 1.0 : 0.0,
      evalStatus: mean >= 0.5 ? EvalStatus.passed : EvalStatus.failed,
    );
  }

  @override
  EvaluationResult aggregateInvocationResults(
    List<PerInvocationResult> perInvocationResults,
  ) {
    final double total = perInvocationResults.fold<double>(
      0,
      (double acc, PerInvocationResult value) => acc + (value.score ?? 0.0),
    );
    final double score = total / perInvocationResults.length;
    return EvaluationResult(
      overallScore: score,
      overallEvalStatus: score >= 0.5 ? EvalStatus.passed : EvalStatus.failed,
      perInvocationResults: perInvocationResults,
    );
  }
}

EvalSet _singleTurnEvalSet() {
  return EvalSet(
    evalSetId: 'set1',
    evalCases: <EvalCase>[
      EvalCase(evalId: 'case1', input: 'hello', expectedOutput: 'Echo: hello'),
    ],
  );
}

void main() {
  group('evaluation generator', () {
    test('generates invocation responses from eval set', () async {
      final List<EvalCaseResponses> responses =
          await EvaluationGenerator.generateResponses(
            evalSet: _singleTurnEvalSet(),
            rootAgent: _EchoAgent(),
            repeatNum: 1,
          );

      expect(responses, hasLength(1));
      expect(responses.first.responses, hasLength(1));
      final List<Invocation> run = responses.first.responses.first;
      expect(run, isNotEmpty);
      final String? responseText = getTextFromContent(run.first.finalResponse);
      expect(responseText, contains('Echo: hello'));
    });
  });

  group('agent evaluator', () {
    test('evaluates metric scores across generated runs', () async {
      final List<AgentEvalCaseSummary> summary =
          await AgentEvaluator.evaluateEvalSet(
            rootAgent: _EchoAgent(),
            evalSet: _singleTurnEvalSet(),
            evalConfig: EvalConfig(
              criteria: <String, Object?>{
                PrebuiltMetricNames.responseMatchScore: 0.9,
              },
            ),
            repeatNum: 1,
          );

      expect(summary, hasLength(1));
      expect(summary.first.metrics, isNotEmpty);
      expect(
        summary.first.metrics.first.metricName,
        PrebuiltMetricNames.responseMatchScore,
      );
      expect(summary.first.passed, isTrue);
    });
  });

  group('llm as judge base', () {
    test('runs multi-sample auto-rater path and aggregates results', () async {
      final EvalMetricSpec metric = EvalMetricSpec(
        metricName: PrebuiltMetricNames.finalResponseMatchV2,
        criterion: LlmAsAJudgeCriterion(
          threshold: 0.5,
          judgeModelOptions: JudgeModelOptions(numSamples: 2),
        ),
      );

      final _BinaryJudgeEvaluator evaluator = _BinaryJudgeEvaluator(
        evalMetric: metric,
        autoRaterInvoker:
            ({
              required String prompt,
              required JudgeModelOptions judgeModelOptions,
            }) async {
              return LlmResponse(
                content: Content.modelText(
                  '{"is_the_agent_response_valid":"valid"}',
                ),
              );
            },
      );

      final Invocation invocation = Invocation(
        userContent: <String, Object?>{
          'role': 'user',
          'parts': <Object?>[
            <String, Object?>{'text': 'hello'},
          ],
        },
        finalResponse: <String, Object?>{
          'role': 'model',
          'parts': <Object?>[
            <String, Object?>{'text': 'Echo: hello'},
          ],
        },
      );

      final EvaluationResult result = await evaluator.evaluateInvocations(
        actualInvocations: <Invocation>[invocation],
        expectedInvocations: <Invocation>[invocation],
      );
      expect(result.overallScore, 1.0);
      expect(result.overallEvalStatus, EvalStatus.passed);
    });
  });
}
