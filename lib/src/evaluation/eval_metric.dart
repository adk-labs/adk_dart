/// Evaluation metric definitions and evaluation runtime options.
library;

/// Built-in evaluation metrics supported by the evaluator.
enum EvalMetric { finalResponseExactMatch, finalResponseContains }

/// Runtime configuration for evaluation execution.
class EvaluateConfig {
  /// Creates evaluate configuration.
  EvaluateConfig({List<EvalMetric>? evalMetrics, this.parallelism = 4})
    : evalMetrics =
          evalMetrics ?? <EvalMetric>[EvalMetric.finalResponseExactMatch];

  /// Metrics to evaluate for each eval case.
  final List<EvalMetric> evalMetrics;

  /// Maximum evaluation parallelism.
  final int parallelism;
}
