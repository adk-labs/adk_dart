import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _FixedModel extends BaseLlm {
  _FixedModel(this.reply) : super(model: 'fixed');

  final String reply;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(content: Content.modelText(reply));
  }
}

void main() {
  group('LocalEvalService', () {
    test('performs inference and evaluates final response metric', () async {
      final Agent agent = Agent(
        name: 'root_agent',
        model: _FixedModel('hello'),
      );
      final LocalEvalService service = LocalEvalService(rootAgent: agent);

      final EvalCase evalCase = EvalCase(
        evalId: 'case_1',
        input: 'say hello',
        expectedOutput: 'hello',
      );

      final List<InferenceResult> inferences = await service
          .performInference(
            InferenceRequest(
              appName: 'eval_app',
              evalCases: <EvalCase>[evalCase],
            ),
          )
          .toList();

      expect(inferences, hasLength(1));
      expect(inferences.first.status, InferenceStatus.success);
      expect(inferences.first.responseText, 'hello');

      final List<EvalCaseResult> results = await service
          .evaluate(
            EvaluateRequest(
              inferenceResults: inferences,
              evalCasesById: <String, EvalCase>{evalCase.evalId: evalCase},
              evaluateConfig: EvaluateConfig(
                evalMetrics: <EvalMetric>[EvalMetric.finalResponseExactMatch],
              ),
            ),
          )
          .toList();

      expect(results, hasLength(1));
      expect(results.first.metrics, hasLength(1));
      expect(results.first.metrics.first.passed, isTrue);
      expect(results.first.overallScore, 1);
    });
  });
}
