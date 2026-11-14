/// Evaluation metric definitions and evaluation runtime options.
library;

import 'eval_config.dart';
import 'eval_metrics.dart';

/// Built-in evaluation metrics supported by the evaluator.
enum EvalMetric {
  /// Checks whether the final response exactly matches the expected response.
  finalResponseExactMatch,

  /// Checks whether the final response contains the expected response substring.
  finalResponseContains,
}

/// Runtime configuration for evaluation execution.
class EvaluateConfig {
  /// Creates evaluate configuration.
  EvaluateConfig({
    List<EvalMetric>? evalMetrics,
    List<EvalMetricSpec>? evalMetricSpecs,
    this.multiRunConfig,
    this.parallelism = 4,
  }) : evalMetrics =
           evalMetrics ??
           (evalMetricSpecs != null && evalMetricSpecs.isNotEmpty
               ? <EvalMetric>[]
               : <EvalMetric>[EvalMetric.finalResponseExactMatch]),
       evalMetricSpecs = evalMetricSpecs ?? const <EvalMetricSpec>[];

  /// Built-in metrics to evaluate for each eval case.
  final List<EvalMetric> evalMetrics;

  /// Registry-backed [EvalMetricSpec] entries to evaluate for each eval case.
  final List<EvalMetricSpec> evalMetricSpecs;

  /// Optional configuration for aggregating results across multiple runs of each eval case.
  final MultiRunConfig? multiRunConfig;

  /// Maximum evaluation parallelism.
  final int parallelism;
}
