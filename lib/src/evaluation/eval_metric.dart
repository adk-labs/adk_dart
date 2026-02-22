enum EvalMetric { finalResponseExactMatch, finalResponseContains }

class EvaluateConfig {
  EvaluateConfig({List<EvalMetric>? evalMetrics, this.parallelism = 4})
    : evalMetrics =
          evalMetrics ?? <EvalMetric>[EvalMetric.finalResponseExactMatch];

  final List<EvalMetric> evalMetrics;
  final int parallelism;
}
