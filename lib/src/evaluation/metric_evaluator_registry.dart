/// Registry wiring for prebuilt metric evaluators.
library;

import '../errors/not_found_error.dart';
import 'custom_metric_evaluator.dart';
import 'efficiency_evaluators.dart';
import 'eval_config.dart';
import 'eval_metrics.dart';
import 'evaluator.dart';
import 'final_response_match_v2.dart';
import 'hallucinations_v1.dart';
import 'metric_info_providers.dart';
import 'multi_turn_task_success_evaluator.dart';
import 'multi_turn_tool_use_quality_evaluator.dart';
import 'multi_turn_trajectory_quality_evaluator.dart';
import 'response_evaluator.dart';
import 'rubric_based_final_response_quality_v1.dart';
import 'rubric_based_multi_turn_trajectory_evaluator.dart';
import 'rubric_based_tool_use_quality_v1.dart';
import 'safety_evaluator.dart';
import 'simulation/per_turn_user_simulator_quality_v1.dart';
import 'tool_parameter_match_evaluator.dart';
import 'trajectory_evaluator.dart';

/// Creates an [Evaluator] instance for one metric specification.
typedef EvaluatorFactory = Evaluator Function(EvalMetricSpec evalMetric);

class _RegistryEntry {
  _RegistryEntry({required this.factory, required this.metricInfo});

  final EvaluatorFactory factory;
  final MetricInfo metricInfo;
}

/// Registry mapping metric names to evaluator factories and metadata.
class MetricEvaluatorRegistry {
  final Map<String, _RegistryEntry> _registry = <String, _RegistryEntry>{};
  final Map<String, String> _customFunctionPaths = <String, String>{};

  /// Returns an evaluator for [evalMetric].
  ///
  /// When a custom function path was registered from an [EvalConfig] via
  /// [registerCustomMetricsFromConfig], that path takes precedence over
  /// [EvalMetricSpec.customFunctionPath].
  Evaluator getEvaluator(EvalMetricSpec evalMetric) {
    final _RegistryEntry? entry = _registry[evalMetric.metricName];
    if (entry == null) {
      throw NotFoundError('${evalMetric.metricName} not found in registry.');
    }

    final String? registeredCustomPath =
        _customFunctionPaths[evalMetric.metricName];
    if (registeredCustomPath != null && registeredCustomPath.isNotEmpty) {
      return CustomMetricEvaluator(
        evalMetric: evalMetric,
        customFunctionPath: registeredCustomPath,
      );
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

  /// Registers an evaluator factory for one metric.
  void registerEvaluator({
    required MetricInfo metricInfo,
    required EvaluatorFactory evaluatorFactory,
  }) {
    _register(
      metricInfo: metricInfo,
      evaluatorFactory: evaluatorFactory,
      customFunctionPath: null,
    );
  }

  void _register({
    required MetricInfo metricInfo,
    required EvaluatorFactory evaluatorFactory,
    required String? customFunctionPath,
  }) {
    _registry[metricInfo.metricName] = _RegistryEntry(
      factory: evaluatorFactory,
      metricInfo: metricInfo,
    );
    if (customFunctionPath != null) {
      _customFunctionPaths[metricInfo.metricName] = customFunctionPath;
    }
  }

  /// Returns metadata for all registered metrics.
  List<MetricInfo> getRegisteredMetrics() {
    return _registry.values.map((_RegistryEntry entry) {
      return MetricInfo.fromJson(entry.metricInfo.toJson());
    }).toList();
  }

  /// Creates an isolated copy of this registry with the same registered metrics.
  MetricEvaluatorRegistry fork() {
    final MetricEvaluatorRegistry copy = MetricEvaluatorRegistry();
    _registry.forEach((String name, _RegistryEntry entry) {
      copy._registry[name] = _RegistryEntry(
        factory: entry.factory,
        metricInfo: MetricInfo.fromJson(entry.metricInfo.toJson()),
      );
    });
    copy._customFunctionPaths.addAll(_customFunctionPaths);
    return copy;
  }
}

/// Builds the default evaluator registry with all prebuilt metrics.
MetricEvaluatorRegistry getDefaultMetricEvaluatorRegistry() {
  final MetricEvaluatorRegistry registry = MetricEvaluatorRegistry();

  registry.registerEvaluator(
    metricInfo: TrajectoryEvaluatorMetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        TrajectoryEvaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: ToolParameterMatchEvaluatorMetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        ToolParameterMatchEvaluator(evalMetric),
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
    metricInfo: MultiTurnTaskSuccessV1MetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        MultiTurnTaskSuccessV1Evaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: MultiTurnTrajectoryQualityV1MetricInfoProvider()
        .getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        MultiTurnTrajectoryQualityV1Evaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: MultiTurnToolUseQualityV1MetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        MultiTurnToolUseQualityV1Evaluator(evalMetric: evalMetric),
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
    metricInfo: RubricBasedMultiTurnTrajectoryMetricInfoProvider()
        .getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        RubricBasedMultiTurnTrajectoryEvaluator(evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: PerTurnUserSimulatorQualityV1MetricInfoProvider()
        .getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        PerTurnUserSimulatorQualityV1(evalMetric),
  );

  // Efficiency metrics.
  registry.registerEvaluator(
    metricInfo: ToolCallCountV1MetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        ToolCallCountV1Evaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: InferenceCallCountV1MetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        InferenceCallCountV1Evaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: TokenUsageV1MetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        TokenUsageV1Evaluator(evalMetric: evalMetric),
  );
  registry.registerEvaluator(
    metricInfo: InvocationDurationV1MetricInfoProvider().getMetricInfo(),
    evaluatorFactory: (EvalMetricSpec evalMetric) =>
        InvocationDurationV1Evaluator(evalMetric: evalMetric),
  );

  return registry;
}

/// Shared default evaluator registry instance.
final MetricEvaluatorRegistry defaultMetricEvaluatorRegistry =
    getDefaultMetricEvaluatorRegistry();

MetricInfo _getDefaultMetricInfo(String metricName, {String description = ''}) {
  return MetricInfo(
    metricName: metricName,
    description: description,
    metricValueInfo: MetricValueInfo(
      interval: Interval(minValue: 0.0, maxValue: 1.0),
    ),
  );
}

/// Registers custom metrics declared in [evalConfig] into
/// [metricEvaluatorRegistry] (or [defaultMetricEvaluatorRegistry] when omitted).
///
/// Entries without a `metricInfo` receive a default [MetricInfo] with a
/// `[0.0, 1.0]` value interval. Returns the registry in which the metrics were
/// registered.
MetricEvaluatorRegistry registerCustomMetricsFromConfig(
  EvalConfig evalConfig, [
  MetricEvaluatorRegistry? metricEvaluatorRegistry,
]) {
  final MetricEvaluatorRegistry targetRegistry =
      metricEvaluatorRegistry ?? defaultMetricEvaluatorRegistry;
  final Map<String, CustomMetricConfig>? customMetrics =
      evalConfig.customMetrics;
  if (customMetrics == null || customMetrics.isEmpty) {
    return targetRegistry;
  }

  customMetrics.forEach((String metricName, CustomMetricConfig config) {
    final MetricInfo metricInfo;
    if (config.metricInfo != null) {
      final Map<String, Object?> copiedJson = config.metricInfo!.toJson();
      copiedJson['metric_name'] = metricName;
      copiedJson.remove('metricName');
      metricInfo = MetricInfo.fromJson(copiedJson);
    } else {
      metricInfo = _getDefaultMetricInfo(
        metricName,
        description: config.description,
      );
    }

    final String functionPath = config.codeConfig.name;
    targetRegistry._register(
      metricInfo: metricInfo,
      evaluatorFactory: (EvalMetricSpec evalMetric) => CustomMetricEvaluator(
        evalMetric: evalMetric,
        customFunctionPath: functionPath,
      ),
      customFunctionPath: functionPath,
    );
  });

  return targetRegistry;
}
