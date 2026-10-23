/// Configuration models for evaluation and user-simulator execution.
library;

import 'dart:convert';
import 'dart:io';

import '../agents/common_configs.dart';
import 'eval_metrics.dart';
import 'multi_run_aggregation_methods.dart';

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

/// An aggregation method paired with a pass/fail threshold across runs.
class MultiRunCriterion {
  /// Creates a multi-run pass/fail criterion.
  MultiRunCriterion({required this.method, required this.threshold}) {
    if (!threshold.isFinite || threshold < 0.0 || threshold > 1.0) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'Must be between 0.0 and 1.0',
      );
    }
  }

  /// Name of the aggregation method (for example `'pass_rate'`).
  final String method;

  /// Minimum aggregated value in `[0.0, 1.0]` required to pass.
  final double threshold;

  /// Decodes a [MultiRunCriterion] from JSON.
  factory MultiRunCriterion.fromJson(Map<String, Object?> json) {
    const Set<String> allowedKeys = <String>{'method', 'threshold'};
    for (final String key in json.keys) {
      if (!allowedKeys.contains(key)) {
        throw ArgumentError(
          'Extra inputs are not permitted in MultiRunCriterion: $key',
        );
      }
    }
    final Object? rawMethod = json['method'];
    if (rawMethod is! String || rawMethod.isEmpty) {
      throw ArgumentError('MultiRunCriterion.method must be a non-empty String.');
    }
    final Object? rawThreshold = json['threshold'];
    if (rawThreshold is bool || rawThreshold is! num) {
      throw ArgumentError('MultiRunCriterion.threshold must be a number.');
    }
    return MultiRunCriterion(
      method: rawMethod,
      threshold: rawThreshold.toDouble(),
    );
  }

  /// Encodes this criterion to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'method': method,
      'threshold': threshold,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is MultiRunCriterion &&
        other.method == method &&
        other.threshold == threshold;
  }

  @override
  int get hashCode => Object.hash(method, threshold);

  @override
  String toString() =>
      'MultiRunCriterion(method: $method, threshold: $threshold)';
}

/// Configuration for a custom cross-run aggregation method.
class CustomCrossRunMethodConfig {
  /// Creates a custom cross-run aggregation method configuration.
  CustomCrossRunMethodConfig({
    required this.codeConfig,
    this.usesScores = true,
  }) {
    if (codeConfig.args.isNotEmpty) {
      throw ArgumentError(
        'args field in CodeConfig for custom method is not supported.',
      );
    }
  }

  /// Location of the user-defined aggregation function (`List<RunResult> -> double?`).
  final CodeConfig codeConfig;

  /// `true` if the function combines numeric scores; `false` if it counts pass/fail outcomes.
  final bool usesScores;

  /// Decodes a [CustomCrossRunMethodConfig] from JSON.
  factory CustomCrossRunMethodConfig.fromJson(Map<String, Object?> json) {
    const Set<String> allowedKeys = <String>{
      'code_config',
      'codeConfig',
      'uses_scores',
      'usesScores',
    };
    for (final String key in json.keys) {
      if (!allowedKeys.contains(key)) {
        throw ArgumentError(
          'Extra inputs are not permitted in CustomCrossRunMethodConfig: $key',
        );
      }
    }
    final Object? rawCodeConfig = json['codeConfig'] ?? json['code_config'];
    if (rawCodeConfig is! Map) {
      throw ArgumentError(
        'CustomCrossRunMethodConfig requires a code_config map.',
      );
    }
    final Object? rawUsesScores = json.containsKey('usesScores')
        ? json['usesScores']
        : json['uses_scores'];
    if (rawUsesScores != null && rawUsesScores is! bool) {
      throw ArgumentError(
        'CustomCrossRunMethodConfig.uses_scores must be a bool.',
      );
    }
    return CustomCrossRunMethodConfig(
      codeConfig: CodeConfig.fromJson(_castJsonMap(rawCodeConfig)),
      usesScores: (rawUsesScores as bool?) ?? true,
    );
  }

  /// Encodes this configuration to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code_config': codeConfig.toJson(),
      'uses_scores': usesScores,
    };
  }
}

/// Configuration for running each eval case multiple times and aggregating across runs.
class MultiRunConfig {
  /// Creates a multi-run evaluation configuration.
  MultiRunConfig({
    this.numRuns,
    this.maxCrashedRuns = 0,
    Object? crossRunScoring,
    this.crossRunScoringByMetric,
    this.crossRunCriteria,
    this.customMethods,
  }) : crossRunScoring = crossRunScoring ?? defaultAggregationMethod.name {
    if (numRuns != null && numRuns! < 1) {
      throw ArgumentError.value(
        numRuns,
        'numRuns',
        'Input should be greater than or equal to 1',
      );
    }
    if (maxCrashedRuns < 0) {
      throw ArgumentError.value(
        maxCrashedRuns,
        'maxCrashedRuns',
        'Input should be greater than or equal to 0',
      );
    }
    _validateMethodReferences();
  }

  /// Default number of repetitions per eval case when `--num_runs` is not passed on the CLI.
  final int? numRuns;

  /// Maximum number of runs allowed to crash before an eval case is marked as failed.
  final int maxCrashedRuns;

  /// Default rule for judging each metric across runs (`String` method name or [MultiRunCriterion]).
  final Object crossRunScoring;

  /// Optional per-metric overrides for [crossRunScoring], keyed by metric name.
  final Map<String, Object>? crossRunScoringByMetric;

  /// Optional pass-count criteria applied across whole runs of an eval case.
  final List<MultiRunCriterion>? crossRunCriteria;

  /// User-defined cross-run aggregation methods keyed by method name.
  final Map<String, CustomCrossRunMethodConfig>? customMethods;

  void _validateMethodReferences() {
    final Map<String, bool> usesScoresByName = <String, bool>{
      for (final MapEntry<String, AggregationMethod> entry
          in getBuiltInAggregationMethods().entries)
        entry.key: entry.value.usesScores,
    };
    if (customMethods != null) {
      for (final MapEntry<String, CustomCrossRunMethodConfig> entry
          in customMethods!.entries) {
        if (usesScoresByName.containsKey(entry.key)) {
          throw ArgumentError(
            'custom_methods cannot override built-in method "${entry.key}".',
          );
        }
        usesScoresByName[entry.key] = entry.value.usesScores;
      }
    }

    void checkRule(Object rule, String where) {
      if (rule is! String && rule is! MultiRunCriterion) {
        throw ArgumentError(
          'Invalid rule in $where: expected String or MultiRunCriterion, got ${rule.runtimeType}.',
        );
      }
      final String name =
          rule is MultiRunCriterion ? rule.method : rule as String;
      final bool? usesScores = usesScoresByName[name];
      if (usesScores == null) {
        final List<String> known = usesScoresByName.keys.toList()..sort();
        throw ArgumentError(
          'Unknown aggregation method "$name" in $where. '
          'Known methods: $known',
        );
      }
      if (usesScores && rule is MultiRunCriterion) {
        throw ArgumentError(
          'Score-combining method "$name" in $where compares '
          "against the metric's threshold in criteria; specify it as "
          '"$name", not with a separate threshold.',
        );
      }
      if (!usesScores && rule is String) {
        throw ArgumentError(
          'Pass-count method "$name" in $where requires a '
          'threshold: {"method": "$name", "threshold": <0..1>}.',
        );
      }
    }

    checkRule(crossRunScoring, 'cross_run_scoring');
    if (crossRunScoringByMetric != null) {
      for (final MapEntry<String, Object> entry
          in crossRunScoringByMetric!.entries) {
        checkRule(entry.value, 'cross_run_scoring_by_metric[${entry.key}]');
      }
    }
    if (crossRunCriteria != null) {
      for (final MultiRunCriterion criterion in crossRunCriteria!) {
        final bool? usesScores = usesScoresByName[criterion.method];
        if (usesScores == null) {
          final List<String> known = usesScoresByName.keys.toList()..sort();
          throw ArgumentError(
            'Unknown aggregation method "${criterion.method}" in '
            'cross_run_criteria. Known methods: $known',
          );
        }
        if (usesScores) {
          throw ArgumentError(
            'Score-combining method "${criterion.method}" in '
            'cross_run_criteria cannot be used across the whole eval case '
            '(cases have no single score); use it in cross_run_scoring or '
            'cross_run_scoring_by_metric.',
          );
        }
      }
    }
  }

  static Object _parseScoringRule(Object? raw, String fieldName) {
    if (raw is String) {
      return raw;
    }
    if (raw is MultiRunCriterion) {
      return raw;
    }
    if (raw is Map) {
      return MultiRunCriterion.fromJson(_castJsonMap(raw));
    }
    throw ArgumentError(
      'Invalid $fieldName: expected String or MultiRunCriterion map, got ${raw.runtimeType}.',
    );
  }

  /// Decodes a [MultiRunConfig] from JSON.
  factory MultiRunConfig.fromJson(Map<String, Object?> json) {
    const Set<String> allowedKeys = <String>{
      'num_runs',
      'numRuns',
      'max_crashed_runs',
      'maxCrashedRuns',
      'cross_run_scoring',
      'crossRunScoring',
      'cross_run_scoring_by_metric',
      'crossRunScoringByMetric',
      'cross_run_criteria',
      'crossRunCriteria',
      'custom_methods',
      'customMethods',
    };
    for (final String key in json.keys) {
      if (!allowedKeys.contains(key)) {
        throw ArgumentError(
          'Extra inputs are not permitted in MultiRunConfig: $key',
        );
      }
    }

    final Object? rawNumRuns = json['numRuns'] ?? json['num_runs'];
    int? numRuns;
    if (rawNumRuns != null) {
      if (rawNumRuns is bool || rawNumRuns is! int) {
        throw ArgumentError('MultiRunConfig.num_runs must be an int.');
      }
      numRuns = rawNumRuns;
    }

    final Object? rawMaxCrashed =
        json['maxCrashedRuns'] ?? json['max_crashed_runs'];
    int maxCrashedRuns = 0;
    if (rawMaxCrashed != null) {
      if (rawMaxCrashed is bool || rawMaxCrashed is! int) {
        throw ArgumentError('MultiRunConfig.max_crashed_runs must be an int.');
      }
      maxCrashedRuns = rawMaxCrashed;
    }

    final Object? rawCrossRunScoring =
        json['crossRunScoring'] ?? json['cross_run_scoring'];
    final Object crossRunScoring = rawCrossRunScoring == null
        ? defaultAggregationMethod.name
        : _parseScoringRule(rawCrossRunScoring, 'cross_run_scoring');

    final Object? rawByMetric =
        json['crossRunScoringByMetric'] ?? json['cross_run_scoring_by_metric'];
    Map<String, Object>? crossRunScoringByMetric;
    if (rawByMetric != null) {
      if (rawByMetric is! Map) {
        throw ArgumentError(
          'MultiRunConfig.cross_run_scoring_by_metric must be a map.',
        );
      }
      crossRunScoringByMetric = <String, Object>{};
      rawByMetric.forEach((Object? k, Object? v) {
        final String key = '$k';
        crossRunScoringByMetric![key] = _parseScoringRule(
          v,
          'cross_run_scoring_by_metric[$key]',
        );
      });
    }

    final Object? rawCriteria =
        json['crossRunCriteria'] ?? json['cross_run_criteria'];
    List<MultiRunCriterion>? crossRunCriteria;
    if (rawCriteria != null) {
      if (rawCriteria is! List) {
        throw ArgumentError(
          'MultiRunConfig.cross_run_criteria must be a list.',
        );
      }
      crossRunCriteria = <MultiRunCriterion>[
        for (final Object? item in rawCriteria)
          if (item is MultiRunCriterion)
            item
          else if (item is Map)
            MultiRunCriterion.fromJson(_castJsonMap(item))
          else
            throw ArgumentError(
              'cross_run_criteria items must be MultiRunCriterion maps.',
            ),
      ];
    }

    final Object? rawCustomMethods =
        json['customMethods'] ?? json['custom_methods'];
    Map<String, CustomCrossRunMethodConfig>? customMethods;
    if (rawCustomMethods != null) {
      if (rawCustomMethods is! Map) {
        throw ArgumentError('MultiRunConfig.custom_methods must be a map.');
      }
      customMethods = <String, CustomCrossRunMethodConfig>{};
      rawCustomMethods.forEach((Object? k, Object? v) {
        if (v is CustomCrossRunMethodConfig) {
          customMethods!['$k'] = v;
        } else if (v is Map) {
          customMethods!['$k'] = CustomCrossRunMethodConfig.fromJson(
            _castJsonMap(v),
          );
        } else {
          throw ArgumentError(
            'custom_methods[$k] must be a CustomCrossRunMethodConfig map.',
          );
        }
      });
    }

    return MultiRunConfig(
      numRuns: numRuns,
      maxCrashedRuns: maxCrashedRuns,
      crossRunScoring: crossRunScoring,
      crossRunScoringByMetric: crossRunScoringByMetric,
      crossRunCriteria: crossRunCriteria,
      customMethods: customMethods,
    );
  }

  /// Encodes this configuration to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (numRuns != null) 'num_runs': numRuns,
      'max_crashed_runs': maxCrashedRuns,
      'cross_run_scoring': crossRunScoring is MultiRunCriterion
          ? (crossRunScoring as MultiRunCriterion).toJson()
          : crossRunScoring,
      if (crossRunScoringByMetric != null)
        'cross_run_scoring_by_metric': crossRunScoringByMetric!.map(
          (String k, Object v) => MapEntry(
            k,
            v is MultiRunCriterion ? v.toJson() : v,
          ),
        ),
      if (crossRunCriteria != null)
        'cross_run_criteria': crossRunCriteria!
            .map((MultiRunCriterion c) => c.toJson())
            .toList(),
      if (customMethods != null)
        'custom_methods': customMethods!.map(
          (String k, CustomCrossRunMethodConfig v) => MapEntry(k, v.toJson()),
        ),
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
    this.liveModelConfig,
    this.multiRunConfig,
  }) : criteria = criteria ?? <String, Object?>{} {
    _checkCrossRunMetricNames();
  }

  /// Criterion config keyed by metric name.
  final Map<String, Object?> criteria;

  /// Optional custom metric definitions keyed by metric name.
  final Map<String, CustomMetricConfig>? customMetrics;

  /// Optional user simulator configuration.
  final BaseUserSimulatorConfig? userSimulatorConfig;

  /// Optional live/bidirectional model configuration.
  final LiveModelConfig? liveModelConfig;

  /// Optional configuration for running each eval case multiple times and aggregating across runs.
  final MultiRunConfig? multiRunConfig;

  void _checkCrossRunMetricNames() {
    final Map<String, Object>? byMetric =
        multiRunConfig?.crossRunScoringByMetric;
    if (byMetric == null || byMetric.isEmpty) {
      return;
    }
    final List<String> unknown =
        byMetric.keys.where((String key) => !criteria.containsKey(key)).toList()
          ..sort();
    if (unknown.isNotEmpty) {
      throw ArgumentError(
        'multi_run_config.cross_run_scoring_by_metric has rules for '
        'metrics that are not in criteria: $unknown',
      );
    }
  }

  /// Creates a copy of this configuration with the specified fields replaced.
  EvalConfig copyWith({
    Map<String, Object?>? criteria,
    Map<String, CustomMetricConfig>? customMetrics,
    BaseUserSimulatorConfig? userSimulatorConfig,
    LiveModelConfig? liveModelConfig,
    MultiRunConfig? multiRunConfig,
  }) {
    return EvalConfig(
      criteria: criteria ?? Map<String, Object?>.from(this.criteria),
      customMetrics: customMetrics ?? this.customMetrics,
      userSimulatorConfig: userSimulatorConfig ?? this.userSimulatorConfig,
      liveModelConfig: liveModelConfig ?? this.liveModelConfig,
      multiRunConfig: multiRunConfig ?? this.multiRunConfig,
    );
  }

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
    final Object? rawLiveModelConfig =
        json['liveModelConfig'] ?? json['live_model_config'];
    final Object? rawMultiRunConfig =
        json['multiRunConfig'] ?? json['multi_run_config'];
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
      liveModelConfig: rawLiveModelConfig is Map
          ? LiveModelConfig.fromJson(_castJsonMap(rawLiveModelConfig))
          : null,
      multiRunConfig: rawMultiRunConfig is MultiRunConfig
          ? rawMultiRunConfig
          : (rawMultiRunConfig is Map
                ? MultiRunConfig.fromJson(_castJsonMap(rawMultiRunConfig))
                : null),
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
      if (liveModelConfig != null)
        'live_model_config': liveModelConfig!.toJson(),
      if (multiRunConfig != null)
        'multi_run_config': multiRunConfig!.toJson(),
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

/// Configuration for running an agent in live/bidirectional mode during evaluation.
class LiveModelConfig {
  /// Creates a [LiveModelConfig].
  const LiveModelConfig({
    this.responseModalities = const <String>['AUDIO'],
    this.speechConfig,
    this.enableInputAudioTranscription = true,
    this.enableOutputAudioTranscription = true,
  });

  /// Parses a [LiveModelConfig] from JSON.
  factory LiveModelConfig.fromJson(Map<String, Object?> json) {
    final Object? rawModalities =
        json['responseModalities'] ?? json['response_modalities'];
    return LiveModelConfig(
      responseModalities: rawModalities is Iterable
          ? rawModalities.map((Object? e) => '$e').toList(growable: false)
          : const <String>['AUDIO'],
      speechConfig: json['speechConfig'] is Map || json['speech_config'] is Map
          ? _castJsonMap(json['speechConfig'] ?? json['speech_config'])
          : null,
      enableInputAudioTranscription:
          (json['enableInputAudioTranscription'] ??
                  json['enable_input_audio_transcription'])
              as bool? ??
          true,
      enableOutputAudioTranscription:
          (json['enableOutputAudioTranscription'] ??
                  json['enable_output_audio_transcription'])
              as bool? ??
          true,
    );
  }

  /// Requested response modalities (defaults to `['AUDIO']`).
  final List<String> responseModalities;

  /// Optional speech synthesis configuration dictionary.
  final Map<String, Object?>? speechConfig;

  /// Whether input audio transcription is enabled.
  final bool enableInputAudioTranscription;

  /// Whether output audio transcription is enabled.
  final bool enableOutputAudioTranscription;

  /// Serializes this configuration to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'response_modalities': responseModalities,
      if (speechConfig != null) 'speech_config': speechConfig,
      'enable_input_audio_transcription': enableInputAudioTranscription,
      'enable_output_audio_transcription': enableOutputAudioTranscription,
    };
  }
}
