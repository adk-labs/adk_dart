/// Sampling contracts used by optimizers for train and validation scoring.
library;

import '../agents/llm_agent.dart';
import 'data_types.dart';

/// Selects which example split to evaluate.
enum ExampleSet {
  /// Training split used to guide candidate search.
  train,

  /// Validation split used for final quality checks.
  validation,
}

/// Provides train/validation sampling and scoring for optimizers.
abstract class Sampler<T extends BaseSamplingResult> {
  /// Returns available training example identifiers.
  List<String> getTrainExampleIds();

  /// Returns available validation example identifiers.
  List<String> getValidationExampleIds();

  /// Scores [candidate] on the selected [exampleSet].
  ///
  /// When [batch] is provided, implementations should evaluate only that
  /// subset. When [captureFullEvalData] is true, implementations may attach
  /// richer metric payloads in the returned result.
  Future<T> sampleAndScore(
    Agent candidate, {
    ExampleSet exampleSet = ExampleSet.validation,
    List<String>? batch,
    bool captureFullEvalData = false,
  });
}
