import 'eval_metrics.dart';

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

class ResponseEvaluatorMetricInfoProvider extends MetricInfoProvider {
  ResponseEvaluatorMetricInfoProvider(this.metricName);

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
