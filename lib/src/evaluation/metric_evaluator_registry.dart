import '../errors/not_found_error.dart';
import 'custom_metric_evaluator.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';
import 'final_response_match_v2.dart';
import 'hallucinations_v1.dart';
import 'metric_info_providers.dart';
import 'response_evaluator.dart';
import 'rubric_based_final_response_quality_v1.dart';
import 'rubric_based_tool_use_quality_v1.dart';
import 'safety_evaluator.dart';
import 'simulation/per_turn_user_simulator_quality_v1.dart';
import 'trajectory_evaluator.dart';

typedef EvaluatorFactory = Evaluator Function(EvalMetricSpec evalMetric);

class _RegistryEntry {
  _RegistryEntry({required this.factory, required this.metricInfo});

  final EvaluatorFactory factory;
  final MetricInfo metricInfo;
}

class MetricEvaluatorRegistry {
  final Map<String, _RegistryEntry> _registry = <String, _RegistryEntry>{};

  Evaluator getEvaluator(EvalMetricSpec evalMetric) {
    final _RegistryEntry? entry = _registry[evalMetric.metricName];
    if (entry == null) {
      throw NotFoundError('${evalMetric.metricName} not found in registry.');
    }

    if (evalMetric.customFunctionPath != null &&
        evalMetric.customFunctionPath!.isNotEmpty) {
      return CustomMetricEvaluator(
        evalMetric: evalMetric,
        customFunctionPath: evalMetric.customFunctionPath!,
      );
    }
    return entry.factory(evalMetric);
  }

  void registerEvaluator({
    required MetricInfo metricInfo,
    required EvaluatorFactory evaluatorFactory,
  }) {
    _registry[metricInfo.metricName] = _RegistryEntry(
      factory: evaluatorFactory,
      metricInfo: metricInfo,
    );
  }

  List<MetricInfo> getRegisteredMetrics() {
    return _registry.values.map((_RegistryEntry entry) {
      return MetricInfo.fromJson(entry.metricInfo.toJson());
    }).toList();
  }
}

MetricEvaluatorRegistry getDefaultMetricEvaluatorRegistry() {
  final MetricEvaluatorRegistry registry = MetricEvaluatorRegistry();

  registry.registerEvaluator(
    metricInfo: TrajectoryEvaluatorMetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        TrajectoryEvaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: ResponseEvaluatorMetricInfoProvider(
      PrebuiltMetricNames.responseEvaluationScore,
    ).getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        ResponseEvaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: ResponseEvaluatorMetricInfoProvider(
      PrebuiltMetricNames.responseMatchScore,
    ).getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        ResponseEvaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: SafetyEvaluatorV1MetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        SafetyEvaluatorV1(evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: FinalResponseMatchV2EvaluatorMetricInfoProvider()
        .getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        FinalResponseMatchV2Evaluator(evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: RubricBasedFinalResponseQualityV1EvaluatorMetricInfoProvider()
        .getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        RubricBasedFinalResponseQualityV1Evaluator(evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: HallucinationsV1EvaluatorMetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        HallucinationsV1Evaluator(evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: RubricBasedToolUseV1EvaluatorMetricInfoProvider()
        .getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        RubricBasedToolUseV1Evaluator(evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: PerTurnUserSimulatorQualityV1MetricInfoProvider()
        .getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        PerTurnUserSimulatorQualityV1(evalMetric),
  );

  return registry;
}

final MetricEvaluatorRegistry defaultMetricEvaluatorRegistry =
    getDefaultMetricEvaluatorRegistry();
