import 'dart:math';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _NoopRuntimeModel extends BaseLlm {
  _NoopRuntimeModel() : super(model: 'noop-runtime');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}

class _ConstantPromptModel extends BaseLlm {
  _ConstantPromptModel(this.output) : super(model: 'optimizer-model');

  final String output;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[Part.text('analysis', thought: true), Part.text(output)],
      ),
    );
  }
}

class _PromptScoreSampler extends Sampler<UnstructuredSamplingResult> {
  _PromptScoreSampler({required this.trainIds, required this.validationIds});

  final List<String> trainIds;
  final List<String> validationIds;

  @override
  List<String> getTrainExampleIds() => List<String>.from(trainIds);

  @override
  List<String> getValidationExampleIds() => List<String>.from(validationIds);

  @override
  Future<UnstructuredSamplingResult> sampleAndScore(
    Agent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  }) async {
    final List<String> ids =
        batch ?? (exampleSet == ExampleSet.train ? trainIds : validationIds);

    final bool improved = '${candidate.instruction}'.contains('Improved');
    final double baseScore = exampleSet == ExampleSet.train
        ? (improved ? 0.85 : 0.35)
        : (improved ? 0.95 : 0.45);

    final Map<String, double> scores = <String, double>{
      for (final String id in ids) id: baseScore,
    };
    return UnstructuredSamplingResult(scores: scores);
  }
}

void main() {
  test('data_types hold optimizer structures', () {
    final Agent agent = Agent(
      name: 'a',
      model: _NoopRuntimeModel(),
      instruction: 'x',
      disallowTransferToParent: true,
      disallowTransferToPeers: true,
    );
    final BaseAgentWithScores item = BaseAgentWithScores(
      optimizedAgent: agent,
      overallScore: 0.9,
    );
    final OptimizerResult<BaseAgentWithScores> result =
        OptimizerResult<BaseAgentWithScores>(
          optimizedAgents: <BaseAgentWithScores>[item],
        );

    expect(result.optimizedAgents, hasLength(1));
    expect(result.optimizedAgents.single.overallScore, 0.9);
    expect(
      UnstructuredSamplingResult(
        scores: <String, double>{'e1': 0.7},
      ).scores['e1'],
      0.7,
    );
  });

  test(
    'simple optimizer improves instruction and reports validation score',
    () async {
      final Agent initial = Agent(
        name: 'root_agent',
        model: _NoopRuntimeModel(),
        instruction: 'Initial instruction',
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final _PromptScoreSampler sampler = _PromptScoreSampler(
        trainIds: <String>['t1', 't2', 't3'],
        validationIds: <String>['v1', 'v2'],
      );
      final SimplePromptOptimizer optimizer = SimplePromptOptimizer(
        SimplePromptOptimizerConfig(
          optimizerModel: _ConstantPromptModel('Improved instruction'),
          numIterations: 2,
          batchSize: 2,
        ),
        random: Random(7),
      );

      final OptimizerResult<BaseAgentWithScores> result = await optimizer
          .optimize(initial, sampler);

      expect(result.optimizedAgents, hasLength(1));
      final BaseAgentWithScores best = result.optimizedAgents.single;
      expect(
        '${best.optimizedAgent.instruction}',
        contains('Improved instruction'),
      );
      expect(best.overallScore, closeTo(0.95, 1e-9));
    },
  );

  test(
    'simple optimizer keeps initial instruction when candidate is empty',
    () async {
      final Agent initial = Agent(
        name: 'root_agent',
        model: _NoopRuntimeModel(),
        instruction: 'Initial instruction',
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
      );
      final _PromptScoreSampler sampler = _PromptScoreSampler(
        trainIds: <String>['t1'],
        validationIds: <String>['v1'],
      );
      final SimplePromptOptimizer optimizer = SimplePromptOptimizer(
        SimplePromptOptimizerConfig(
          optimizerModel: _ConstantPromptModel('   '),
          numIterations: 1,
          batchSize: 5,
        ),
        random: Random(3),
      );

      final OptimizerResult<BaseAgentWithScores> result = await optimizer
          .optimize(initial, sampler);

      expect(
        result.optimizedAgents.single.optimizedAgent.instruction,
        'Initial instruction',
      );
      expect(result.optimizedAgents.single.overallScore, closeTo(0.45, 1e-9));
    },
  );
}
