import 'dart:convert';
import 'dart:io';

import '../agents/common_configs.dart';
import 'eval_metrics.dart';

/// Base configuration payload for user simulator implementations.
class BaseUserSimulatorConfig {
  /// Creates a user simulator config.
  BaseUserSimulatorConfig({Map<String, Object?>? values})
    : values = values ?? <String, Object?>{};

  /// Raw configuration values.
  final Map<String, Object?> values;

  /// Decodes config values from JSON.
  factory BaseUserSimulatorConfig.fromJson(Map<String, Object?> json) {
    return BaseUserSimulatorConfig(values: json);
  }

  /// Encodes this config for persistence.
  Map<String, Object?> toJson() => Map<String, Object?>.from(values);
}

/// Declares one custom metric implementation used during evaluation.
class CustomMetricConfig {
  /// Creates a custom metric configuration.
  CustomMetricConfig({
    required this.codeConfig,
    this.metricInfo,
    this.description = '',
  }) {
    if (codeConfig.args.isNotEmpty) {
      throw ArgumentError(
        'args field in CodeConfig for custom metric is not supported.',
      );
    }
  }

  /// Code loading configuration for the custom metric function.
  final CodeConfig codeConfig;

  /// Optional metric metadata exposed to tooling and reports.
  final MetricInfo? metricInfo;

  /// Optional human-readable description.
  final String description;

  /// Decodes a custom metric configuration from JSON.
  factory CustomMetricConfig.fromJson(Map<String, Object?> json) {
    return CustomMetricConfig(
      codeConfig: CodeConfig.fromJson(
        _castJsonMap(json['codeConfig'] ?? json['code_config']),
      ),
      metricInfo: json['metricInfo'] == null && json['metric_info'] == null
          ? null
          : MetricInfo.fromJson(
              _castJsonMap(json['metricInfo'] ?? json['metric_info']),
            ),
      description: (json['description'] ?? '') as String,
    );
  }

  /// Encodes this configuration for persistence.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code_config': codeConfig.toJson(),
      if (metricInfo != null) 'metric_info': metricInfo!.toJson(),
      if (description.isNotEmpty) 'description': description,
    };
  }
}

/// Top-level evaluation configuration loaded from disk or defaults.
class EvalConfig {
  /// Creates an evaluation configuration.
  EvalConfig({
    Map<String, Object?>? criteria,
    this.customMetrics,
    this.userSimulatorConfig,
  }) : criteria = criteria ?? <String, Object?>{};

  /// Criterion config keyed by metric name.
  final Map<String, Object?> criteria;

  /// Optional custom metric definitions keyed by metric name.
  final Map<String, CustomMetricConfig>? customMetrics;

  /// Optional user simulator configuration.
  final BaseUserSimulatorConfig? userSimulatorConfig;

  /// Decodes an evaluation configuration from JSON.
  factory EvalConfig.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> rawCriteria = _castJsonMap(json['criteria']);
    final Map<String, Object?> rawCustomMetrics = _castJsonMap(
      json['customMetrics'] ?? json['custom_metrics'],
    );
    final Map<String, CustomMetricConfig>? customMetrics =
        rawCustomMetrics.isEmpty
        ? null
        : rawCustomMetrics.map(
            (String key, Object? value) =>
                MapEntry(key, CustomMetricConfig.fromJson(_castJsonMap(value))),
          );
    return EvalConfig(
      criteria: rawCriteria,
      customMetrics: customMetrics,
      userSimulatorConfig:
          json['userSimulatorConfig'] == null &&
              json['user_simulator_config'] == null
          ? null
          : BaseUserSimulatorConfig.fromJson(
              _castJsonMap(
                json['userSimulatorConfig'] ?? json['user_simulator_config'],
              ),
            ),
    );
  }

  /// Encodes this configuration for persistence.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'criteria': criteria,
      if (customMetrics != null)
        'custom_metrics': customMetrics!.map(
          (String key, CustomMetricConfig value) =>
              MapEntry(key, value.toJson()),
        ),
      if (userSimulatorConfig != null)
        'user_simulator_config': userSimulatorConfig!.toJson(),
    };
  }
}

final EvalConfig _defaultEvalConfig = EvalConfig(
  criteria: <String, Object?>{
    'tool_trajectory_avg_score': 1.0,
    'response_match_score': 0.8,
  },
);

/// Loads evaluation config from [evalConfigFilePath] or returns defaults.
EvalConfig getEvaluationCriteriaOrDefault(String? evalConfigFilePath) {
  if (evalConfigFilePath != null && evalConfigFilePath.isNotEmpty) {
    final File file = File(evalConfigFilePath);
    if (file.existsSync()) {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return EvalConfig.fromJson(_castJsonMap(decoded));
      }
    }
  }
  return _defaultEvalConfig;
}

/// Converts [evalConfig] criteria into normalized metric specs.
List<EvalMetricSpec> getEvalMetricsFromConfig(EvalConfig evalConfig) {
  final List<EvalMetricSpec> results = <EvalMetricSpec>[];
  evalConfig.criteria.forEach((String metricName, Object? criterionValue) {
    String? customFunctionPath;
    if (evalConfig.customMetrics != null &&
        evalConfig.customMetrics!.containsKey(metricName)) {
      customFunctionPath =
          evalConfig.customMetrics![metricName]!.codeConfig.name;
    }

    if (criterionValue is num) {
      final double threshold = criterionValue.toDouble();
      results.add(
        EvalMetricSpec(
          metricName: metricName,
          threshold: threshold,
          criterion: BaseCriterion(threshold: threshold),
          customFunctionPath: customFunctionPath,
        ),
      );
      return;
    }

    if (criterionValue is Map) {
      final BaseCriterion criterion = BaseCriterion.fromJson(criterionValue);
      results.add(
        EvalMetricSpec(
          metricName: metricName,
          threshold: criterion.threshold,
          criterion: criterion,
          customFunctionPath: customFunctionPath,
        ),
      );
      return;
    }

    throw ArgumentError(
      'Unexpected criterion type `${criterionValue.runtimeType}` for metric `$metricName`.',
    );
  });
  return results;
}

Map<String, Object?> _castJsonMap(Object? value) {
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}
