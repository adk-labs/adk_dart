import '../agents/llm_agent.dart';
import 'data_types.dart';

enum ExampleSet { train, validation }

abstract class Sampler<T extends BaseSamplingResult> {
  List<String> getTrainExampleIds();

  List<String> getValidationExampleIds();

  Future<T> sampleAndScore(
    Agent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  });
}
