import 'dart:io';
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

class _SequencePromptModel extends BaseLlm {
  _SequencePromptModel(this.outputs) : super(model: 'optimizer-model');

  final List<String> outputs;
  final List<LlmRequest> requests = <LlmRequest>[];
  int _index = 0;

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    requests.add(request);
    final String output = outputs[_index < outputs.length ? _index++ : 0];
    yield LlmResponse(
      content: Content(
        role: 'model',
        parts: <Part>[Part.text('analysis', thought: true), Part.text(output)],
      ),
    );
  }
}

class _RecordedSampleCall {
  _RecordedSampleCall({
    required this.instruction,
    required this.exampleSet,
    required this.batch,
    required this.captureFullEvalData,
  });

  final String instruction;
  final ExampleSet exampleSet;
  final List<String>? batch;
  final bool captureFullEvalData;
}

class _RecordingSampler extends Sampler<UnstructuredSamplingResult> {
  _RecordingSampler({
    required this.trainIds,
    required this.validationIds,
  });

  final List<String> trainIds;
  final List<String> validationIds;
  final List<_RecordedSampleCall> calls = <_RecordedSampleCall>[];

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
    final String instruction = '${candidate.instruction}';
    calls.add(
      _RecordedSampleCall(
        instruction: instruction,
        exampleSet: exampleSet,
        batch: batch == null ? null : List<String>.from(batch),
        captureFullEvalData: captureFullEvalData,
      ),
    );

    final List<String> ids =
        batch ?? (exampleSet == ExampleSet.train ? trainIds : validationIds);
    final double baseScore;
    if (instruction.contains('Improved prompt v2')) {
      baseScore = exampleSet == ExampleSet.train ? 0.92 : 0.97;
    } else if (instruction.contains('Improved prompt v1')) {
      baseScore = exampleSet == ExampleSet.train ? 0.71 : 0.81;
    } else {
      baseScore = exampleSet == ExampleSet.train ? 0.35 : 0.45;
    }

    final Map<String, double> scores = <String, double>{
      for (final String id in ids) id: baseScore,
    };
    final Map<String, Map<String, Object?>> data = <String, Map<String, Object?>>{
      for (final String id in ids)
        id: <String, Object?>{
          'instruction': instruction,
          'example_id': id,
          'example_set': exampleSet.name,
        },
    };
    return UnstructuredSamplingResult(scores: scores, data: data);
  }
}

void main() {
  group('gepa root agent prompt optimizer parity', () {
    test('optimizes root prompt and returns GEPA-style raw result', () async {
      final Agent initial = Agent(
        name: 'root_agent',
        model: _NoopRuntimeModel(),
        instruction: 'Initial instruction',
      );
      final _RecordingSampler sampler = _RecordingSampler(
        trainIds: <String>['t1', 't2', 't3'],
        validationIds: <String>['v1', 'v2'],
      );
      final _SequencePromptModel optimizerModel = _SequencePromptModel(
        <String>['Improved prompt v1', 'Improved prompt v2'],
      );
      final GepaRootAgentPromptOptimizer optimizer =
          GepaRootAgentPromptOptimizer(
            GepaRootAgentPromptOptimizerConfig(
              optimizerModel: optimizerModel,
              maxMetricCalls: 2,
              reflectionMinibatchSize: 2,
            ),
            random: Random(7),
          );

      final GepaRootAgentPromptOptimizerResult result = await optimizer
          .optimize(initial, sampler);

      expect(result.optimizedAgents, hasLength(2));
      expect(
        result.optimizedAgents.first.optimizedAgent.instruction,
        'Improved prompt v2',
      );
      expect(result.optimizedAgents.first.overallScore, closeTo(0.97, 1e-9));
      expect(
        result.optimizedAgents.last.optimizedAgent.instruction,
        'Improved prompt v1',
      );

      final Map<String, Object?> raw =
          result.gepaResult ?? <String, Object?>{};
      expect((raw['seed_candidate'] as Map<String, Object?>)['agent_prompt'], (
        'Initial instruction'
      ));
      expect(raw['trainset'], <String>['t1', 't2', 't3']);
      expect(raw['valset'], <String>['v1', 'v2']);
      expect(
        raw['val_aggregate_scores'],
        allOf(
          isA<List<Object?>>(),
          hasLength(2),
          predicate<Object?>((Object? value) {
            final List<Object?> scores = value! as List<Object?>;
            return (scores[0] as num).toDouble() > (scores[1] as num).toDouble();
          }),
        ),
      );

      final Iterable<_RecordedSampleCall> trainCalls = sampler.calls.where(
        (_RecordedSampleCall call) => call.exampleSet == ExampleSet.train,
      );
      expect(trainCalls, isNotEmpty);
      expect(trainCalls.first.captureFullEvalData, isTrue);
      expect(trainCalls.first.batch, hasLength(2));
      expect(optimizerModel.requests, hasLength(2));
    });

    test('writes GEPA artifacts when runDir is configured', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'gepa_optimizer_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final Agent initial = Agent(
        name: 'root_agent',
        model: _NoopRuntimeModel(),
        instruction: 'Initial instruction',
      );
      final _RecordingSampler sampler = _RecordingSampler(
        trainIds: <String>['t1'],
        validationIds: <String>['v1'],
      );
      final GepaRootAgentPromptOptimizer optimizer =
          GepaRootAgentPromptOptimizer(
            GepaRootAgentPromptOptimizerConfig(
              optimizerModel: _SequencePromptModel(<String>['Improved prompt']),
              maxMetricCalls: 1,
              reflectionMinibatchSize: 1,
              runDir: tempDir.path,
            ),
            random: Random(3),
          );

      await optimizer.optimize(initial, sampler);

      final File resultFile = File('${tempDir.path}/gepa_result.json');
      expect(await resultFile.exists(), isTrue);
      final String body = await resultFile.readAsString();
      expect(body, contains('Improved prompt'));
      expect(body, contains('seed_candidate'));
    });
  });
}
