import 'package:adk_dart/adk_dart.dart';

class MockLlm extends BaseLlm {
  MockLlm() : super(model: 'mock_helper');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content.modelText('The capital of France is Paris.'),
    );
  }
}

Future<void> main() async {
  print('=== ADK Agent Evaluation Suite ===');

  // 1. Define agent under evaluation
  final Agent targetAgent = Agent(
    name: 'geography_agent',
    model: MockLlm(),
    instruction: 'Answer geography questions accurately.',
  );

  // 2. Setup LocalEvalService
  final LocalEvalService evalService = LocalEvalService(
    rootAgent: targetAgent,
    appName: 'geo_eval_app',
  );

  // 3. Define test evaluation cases
  final List<EvalCase> evalCases = <EvalCase>[
    EvalCase(
      evalId: 'case_1',
      input: 'What is the capital of France?',
      expectedOutput: 'Paris',
    ),
    EvalCase(
      evalId: 'case_2',
      input: 'Tell me about Paris capital status.',
      expectedOutput: 'Paris',
    ),
  ];

  final InferenceRequest inferenceRequest = InferenceRequest(
    appName: 'geo_eval_app',
    userId: 'eval_user',
    evalCases: evalCases,
  );

  print('Running inference across ${evalCases.length} evaluation cases...');
  await for (final InferenceResult result in evalService.performInference(inferenceRequest)) {
    print('----------------------------------------');
    print('Case ID: ${result.evalCaseId}');
    print('User Input: ${result.userInput}');
    print('Agent Response: ${result.responseText}');
    print('Status: ${result.status.name}');
  }

  print('\nEvaluation run completed successfully!');
}
