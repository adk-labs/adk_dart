/// Shared evaluation models and utility helpers.
library;

import 'eval_metrics.dart';

/// Metric metadata provider for tool trajectory evaluation.
class TrajectoryEvaluatorMetricInfoProvider extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.toolTrajectoryAvgScore,
      description:
          'This metric compares two tool call trajectories (expected vs actual) '
          'for the same user interaction.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for response evaluation and response matching.
class ResponseEvaluatorMetricInfoProvider extends MetricInfoProvider {
  /// Creates a response metric info provider for [metricName].
  ResponseEvaluatorMetricInfoProvider(this.metricName);

  /// Target metric name.
  final String metricName;

  @override
  MetricInfo getMetricInfo() {
    if (metricName == PrebuiltMetricNames.responseEvaluationScore) {
      return MetricInfo(
        metricName: metricName,
        description:
            'This metric evaluates how coherent agent response was. '
            'Value range is [1,5], where higher is better.',
        metricValueInfo: MetricValueInfo(
          interval: Interval(minValue: 1.0, maxValue: 5.0),
        ),
      );
    }
    if (metricName == PrebuiltMetricNames.responseMatchScore) {
      return MetricInfo(
        metricName: metricName,
        description:
            'This metric evaluates whether final response matches the '
            'expected response.',
        metricValueInfo: MetricValueInfo(
          interval: Interval(minValue: 0.0, maxValue: 1.0),
        ),
      );
    }
    throw ArgumentError('`$metricName` is not supported.');
  }
}

/// Metric metadata provider for safety v1 evaluation.
class SafetyEvaluatorV1MetricInfoProvider extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.safetyV1,
      description:
          'This metric evaluates safety (harmlessness) of an agent response.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for multi-turn task success v1.
class MultiTurnTaskSuccessV1MetricInfoProvider extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.multiTurnTaskSuccessV1,
      description:
          'Evaluates whether the agent achieves the overall goal of a '
          'multi-turn conversation.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for multi-turn trajectory quality v1.
class MultiTurnTrajectoryQualityV1MetricInfoProvider
    extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.multiTurnTrajectoryQualityV1,
      description:
          'Evaluates the overall conversation trajectory in a multi-turn run.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for multi-turn tool use quality v1.
class MultiTurnToolUseQualityV1MetricInfoProvider extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.multiTurnToolUseQualityV1,
      description:
          'Evaluates tool usage quality across a full multi-turn conversation.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for final response match v2 evaluation.
class FinalResponseMatchV2EvaluatorMetricInfoProvider
    extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.finalResponseMatchV2,
      description:
          'This metric evaluates final response match using LLM-as-a-judge '
          'style grading.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for rubric-based final response quality v1.
class RubricBasedFinalResponseQualityV1EvaluatorMetricInfoProvider
    extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.rubricBasedFinalResponseQualityV1,
      description:
          'This metric assesses final response quality against provided rubrics.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for hallucinations v1 evaluation.
class HallucinationsV1EvaluatorMetricInfoProvider extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.hallucinationsV1,
      description:
          'This metric assesses whether response contains unsupported claims.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for rubric-based tool-use quality v1.
class RubricBasedToolUseV1EvaluatorMetricInfoProvider
    extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.rubricBasedToolUseQualityV1,
      description:
          'This metric assesses tool-usage quality against provided rubrics.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}

/// Metric metadata provider for per-turn user simulator quality v1.
class PerTurnUserSimulatorQualityV1MetricInfoProvider
    extends MetricInfoProvider {
  @override
  MetricInfo getMetricInfo() {
    return MetricInfo(
      metricName: PrebuiltMetricNames.perTurnUserSimulatorQualityV1,
      description:
          'This metric evaluates whether user simulator messages follow '
          'the conversation scenario.',
      metricValueInfo: MetricValueInfo(
        interval: Interval(minValue: 0.0, maxValue: 1.0),
      ),
    );
  }
}
