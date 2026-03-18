/// Metric specifications and canonical metric identifiers.
library;

import 'common.dart';
import 'eval_case.dart';
import 'eval_result.dart';
import 'eval_rubrics.dart';

/// Minimum passing score threshold for a metric.
typedef Threshold = double;

/// Canonical names for built-in evaluation metrics.
class PrebuiltMetricNames {
  /// Average score for tool trajectory quality.
  static const String toolTrajectoryAvgScore = 'tool_trajectory_avg_score';

  /// LLM-judge score for response quality.
  static const String responseEvaluationScore = 'response_evaluation_score';

  /// Deterministic response matching score.
  static const String responseMatchScore = 'response_match_score';

  /// Safety evaluation metric version 1.
  static const String safetyV1 = 'safety_v1';

  /// Final response matching metric version 2.
  static const String finalResponseMatchV2 = 'final_response_match_v2';

  /// Rubric-based final response quality metric version 1.
  static const String rubricBasedFinalResponseQualityV1 =
      'rubric_based_final_response_quality_v1';

  /// Hallucination detection metric version 1.
  static const String hallucinationsV1 = 'hallucinations_v1';

  /// Rubric-based tool usage quality metric version 1.
  static const String rubricBasedToolUseQualityV1 =
      'rubric_based_tool_use_quality_v1';

  /// Per-turn user simulator quality metric version 1.
  static const String perTurnUserSimulatorQualityV1 =
      'per_turn_user_simulator_quality_v1';

  /// Multi-turn task success metric version 1.
  static const String multiTurnTaskSuccessV1 = 'multi_turn_task_success_v1';

  /// Multi-turn trajectory quality metric version 1.
  static const String multiTurnTrajectoryQualityV1 =
      'multi_turn_trajectory_quality_v1';

  /// Multi-turn tool use quality metric version 1.
  static const String multiTurnToolUseQualityV1 =
      'multi_turn_tool_use_quality_v1';
}

/// Enum wrapper for built-in metric identifiers.
enum PrebuiltMetrics {
  toolTrajectoryAvgScore(PrebuiltMetricNames.toolTrajectoryAvgScore),
  responseEvaluationScore(PrebuiltMetricNames.responseEvaluationScore),
  responseMatchScore(PrebuiltMetricNames.responseMatchScore),
  safetyV1(PrebuiltMetricNames.safetyV1),
  finalResponseMatchV2(PrebuiltMetricNames.finalResponseMatchV2),
  rubricBasedFinalResponseQualityV1(
    PrebuiltMetricNames.rubricBasedFinalResponseQualityV1,
  ),
  hallucinationsV1(PrebuiltMetricNames.hallucinationsV1),
  rubricBasedToolUseQualityV1(PrebuiltMetricNames.rubricBasedToolUseQualityV1),
  perTurnUserSimulatorQualityV1(
    PrebuiltMetricNames.perTurnUserSimulatorQualityV1,
  ),
  multiTurnTaskSuccessV1(PrebuiltMetricNames.multiTurnTaskSuccessV1),
  multiTurnTrajectoryQualityV1(
    PrebuiltMetricNames.multiTurnTrajectoryQualityV1,
  ),
  multiTurnToolUseQualityV1(PrebuiltMetricNames.multiTurnToolUseQualityV1);

  /// Creates a built-in metric enum value.
  const PrebuiltMetrics(this.value);

  /// Wire value used in serialized configurations.
  final String value;
}

/// Options for judge-model-based metric evaluation.
class JudgeModelOptions {
  /// Creates judge model options.
  JudgeModelOptions({
    this.judgeModel = 'gemini-2.5-flash',
    this.judgeModelConfig,
    this.numSamples = 5,
  });

  /// Judge model identifier.
  final String judgeModel;

  /// Optional model configuration payload.
  final Object? judgeModelConfig;

  /// Number of samples used when scoring.
  final int numSamples;

  /// Creates options from JSON.
  factory JudgeModelOptions.fromJson(Map<String, Object?> json) {
    return JudgeModelOptions(
      judgeModel:
          (json['judgeModel'] ?? json['judge_model'] ?? 'gemini-2.5-flash')
              as String,
      judgeModelConfig: json['judgeModelConfig'] ?? json['judge_model_config'],
      numSamples: (json['numSamples'] ?? json['num_samples'] ?? 5) as int,
    );
  }

  /// Converts these options to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'judge_model': judgeModel,
      if (judgeModelConfig != null) 'judge_model_config': judgeModelConfig,
      'num_samples': numSamples,
    };
  }
}

/// Base criterion definition for evaluation thresholds and metadata.
class BaseCriterion {
  /// Creates a base criterion.
  BaseCriterion({required this.threshold, Map<String, Object?>? extra})
    : extra = extra ?? <String, Object?>{};

  /// Minimum passing score.
  final double threshold;

  /// Additional criterion metadata.
  final Map<String, Object?> extra;

  /// Creates a criterion from JSON or a numeric threshold.
  factory BaseCriterion.fromJson(Object? value) {
    if (value is num) {
      return BaseCriterion(threshold: value.toDouble());
    }
    final Map<String, Object?> map = asEvalJson(value);
    return BaseCriterion(
      threshold: asDoubleOr(map['threshold']),
      extra: map..remove('threshold'),
    );
  }

  /// Converts this criterion to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{'threshold': threshold, ...extra};
  }
}

/// Criterion scored by an LLM judge model.
class LlmAsAJudgeCriterion extends BaseCriterion {
  /// Creates an LLM-as-a-judge criterion.
  LlmAsAJudgeCriterion({
    required super.threshold,
    JudgeModelOptions? judgeModelOptions,
    super.extra,
  }) : judgeModelOptions = judgeModelOptions ?? JudgeModelOptions();

  /// Judge model options.
  final JudgeModelOptions judgeModelOptions;

  /// Creates a criterion from JSON.
  factory LlmAsAJudgeCriterion.fromJson(Object? value) {
    final BaseCriterion base = BaseCriterion.fromJson(value);
    final Map<String, Object?> map = asEvalJson(value);
    return LlmAsAJudgeCriterion(
      threshold: base.threshold,
      judgeModelOptions:
          map['judgeModelOptions'] == null && map['judge_model_options'] == null
          ? JudgeModelOptions()
          : JudgeModelOptions.fromJson(
              asEvalJson(
                map['judgeModelOptions'] ?? map['judge_model_options'],
              ),
            ),
      extra: base.extra,
    );
  }

  /// Converts this criterion to JSON.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'judge_model_options': judgeModelOptions.toJson(),
    };
  }
}

/// Criterion scored against explicit rubrics.
class RubricsBasedCriterion extends BaseCriterion {
  /// Creates a rubrics-based criterion.
  RubricsBasedCriterion({
    required super.threshold,
    JudgeModelOptions? judgeModelOptions,
    List<Rubric>? rubrics,
    super.extra,
  }) : judgeModelOptions = judgeModelOptions ?? JudgeModelOptions(),
       rubrics = rubrics ?? <Rubric>[];

  /// Judge model options.
  final JudgeModelOptions judgeModelOptions;

  /// Rubrics used for scoring.
  final List<Rubric> rubrics;

  /// Creates a criterion from JSON.
  factory RubricsBasedCriterion.fromJson(Object? value) {
    final BaseCriterion base = BaseCriterion.fromJson(value);
    final Map<String, Object?> map = asEvalJson(value);
    return RubricsBasedCriterion(
      threshold: base.threshold,
      judgeModelOptions:
          map['judgeModelOptions'] == null && map['judge_model_options'] == null
          ? JudgeModelOptions()
          : JudgeModelOptions.fromJson(
              asEvalJson(
                map['judgeModelOptions'] ?? map['judge_model_options'],
              ),
            ),
      rubrics: asObjectList(map['rubrics']).map((Object? item) {
        return Rubric.fromJson(asEvalJson(item));
      }).toList(),
      extra: base.extra,
    );
  }

  /// Converts this criterion to JSON.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'judge_model_options': judgeModelOptions.toJson(),
      'rubrics': rubrics.map((Rubric value) => value.toJson()).toList(),
    };
  }
}

/// Criterion for hallucination evaluation.
class HallucinationsCriterion extends BaseCriterion {
  /// Creates a hallucinations criterion.
  HallucinationsCriterion({
    required super.threshold,
    JudgeModelOptions? judgeModelOptions,
    this.evaluateIntermediateNlResponses = false,
    super.extra,
  }) : judgeModelOptions = judgeModelOptions ?? JudgeModelOptions();

  /// Judge model options.
  final JudgeModelOptions judgeModelOptions;

  /// Whether intermediate natural-language responses are evaluated.
  final bool evaluateIntermediateNlResponses;

  /// Creates a criterion from JSON.
  factory HallucinationsCriterion.fromJson(Object? value) {
    final BaseCriterion base = BaseCriterion.fromJson(value);
    final Map<String, Object?> map = asEvalJson(value);
    return HallucinationsCriterion(
      threshold: base.threshold,
      judgeModelOptions:
          map['judgeModelOptions'] == null && map['judge_model_options'] == null
          ? JudgeModelOptions()
          : JudgeModelOptions.fromJson(
              asEvalJson(
                map['judgeModelOptions'] ?? map['judge_model_options'],
              ),
            ),
      evaluateIntermediateNlResponses:
          (map['evaluateIntermediateNlResponses'] ??
                  map['evaluate_intermediate_nl_responses'] ??
                  false)
              as bool,
      extra: base.extra,
    );
  }

  /// Converts this criterion to JSON.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'judge_model_options': judgeModelOptions.toJson(),
      'evaluate_intermediate_nl_responses': evaluateIntermediateNlResponses,
    };
  }
}

/// Criterion for tool trajectory matching.
class ToolTrajectoryCriterion extends BaseCriterion {
  /// Creates a tool trajectory criterion.
  ToolTrajectoryCriterion({
    required super.threshold,
    this.matchType = MatchType.exact,
    super.extra,
  });

  /// Matching mode used for expected versus actual tool paths.
  final MatchType matchType;

  /// Creates a criterion from JSON.
  factory ToolTrajectoryCriterion.fromJson(Object? value) {
    final BaseCriterion base = BaseCriterion.fromJson(value);
    final Map<String, Object?> map = asEvalJson(value);
    return ToolTrajectoryCriterion(
      threshold: base.threshold,
      matchType: MatchTypeX.fromObject(map['matchType'] ?? map['match_type']),
      extra: base.extra,
    );
  }

  /// Converts this criterion to JSON.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'match_type': matchType.wireName,
    };
  }
}

/// Matching strategies for tool trajectories.
enum MatchType { exact, inOrder, anyOrder }

/// Utility methods for [MatchType].
extension MatchTypeX on MatchType {
  /// Serialized wire name.
  String get wireName {
    switch (this) {
      case MatchType.exact:
        return 'EXACT';
      case MatchType.inOrder:
        return 'IN_ORDER';
      case MatchType.anyOrder:
        return 'ANY_ORDER';
    }
  }

  /// Parses [value] into a [MatchType].
  static MatchType fromObject(Object? value) {
    if (value is MatchType) {
      return value;
    }
    if (value is String) {
      final String normalized = value
          .trim()
          .toUpperCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      switch (normalized) {
        case 'IN_ORDER':
          return MatchType.inOrder;
        case 'ANY_ORDER':
          return MatchType.anyOrder;
        case 'EXACT':
        default:
          return MatchType.exact;
      }
    }
    return MatchType.exact;
  }
}

/// Criterion configuration for LLM-backed user simulator metrics.
class LlmBackedUserSimulatorCriterion extends LlmAsAJudgeCriterion {
  /// Creates an LLM-backed user simulator criterion.
  LlmBackedUserSimulatorCriterion({
    required super.threshold,
    super.judgeModelOptions,
    this.stopSignal = '</finished>',
    super.extra,
  });

  /// Stop token used by the user simulator.
  final String stopSignal;

  /// Creates a criterion from JSON.
  factory LlmBackedUserSimulatorCriterion.fromJson(Object? value) {
    final LlmAsAJudgeCriterion base = LlmAsAJudgeCriterion.fromJson(value);
    final Map<String, Object?> map = asEvalJson(value);
    return LlmBackedUserSimulatorCriterion(
      threshold: base.threshold,
      judgeModelOptions: base.judgeModelOptions,
      stopSignal:
          asNullableString(map['stopSignal']) ??
          asNullableString(map['stop_signal']) ??
          '</finished>',
      extra: base.extra,
    );
  }

  /// Converts this criterion to JSON.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{...super.toJson(), 'stop_signal': stopSignal};
  }
}

/// Evaluation metric specification used in test configuration.
class EvalMetricSpec {
  /// Creates an evaluation metric specification.
  EvalMetricSpec({
    required this.metricName,
    this.threshold,
    this.criterion,
    this.customFunctionPath,
  });

  /// Metric name.
  final String metricName;

  /// Optional score threshold.
  final double? threshold;

  /// Optional metric-specific criterion.
  final BaseCriterion? criterion;

  /// Optional path to a custom evaluation function.
  final String? customFunctionPath;

  /// Creates a metric spec from JSON.
  factory EvalMetricSpec.fromJson(Map<String, Object?> json) {
    final Object? rawCriterion = json['criterion'];
    return EvalMetricSpec(
      metricName: (json['metricName'] ?? json['metric_name'] ?? '') as String,
      threshold: asNullableDouble(json['threshold']),
      criterion: rawCriterion == null
          ? null
          : BaseCriterion.fromJson(rawCriterion),
      customFunctionPath:
          (json['customFunctionPath'] ?? json['custom_function_path'])
              as String?,
    );
  }

  /// Converts this metric spec to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metric_name': metricName,
      if (threshold != null) 'threshold': threshold,
      if (criterion != null) 'criterion': criterion!.toJson(),
      if (customFunctionPath != null)
        'custom_function_path': customFunctionPath,
    };
  }
}

/// Detailed per-metric evaluation outputs.
class EvalMetricResultDetails {
  /// Creates result details.
  EvalMetricResultDetails({List<RubricScore>? rubricScores})
    : rubricScores = rubricScores ?? <RubricScore>[];

  /// Rubric scores emitted by evaluators.
  final List<RubricScore> rubricScores;

  /// Converts details to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rubric_scores': rubricScores
          .map((RubricScore value) => value.toJson())
          .toList(),
    };
  }
}

/// Metric specification enriched with score and status.
class EvalMetricResultSpec extends EvalMetricSpec {
  /// Creates an evaluated metric result spec.
  EvalMetricResultSpec({
    required super.metricName,
    super.threshold,
    super.criterion,
    super.customFunctionPath,
    this.score,
    this.evalStatus = EvalStatus.notEvaluated,
    EvalMetricResultDetails? details,
  }) : details = details ?? EvalMetricResultDetails();

  /// Final metric score.
  final double? score;

  /// Evaluation status.
  final EvalStatus evalStatus;

  /// Additional detailed outputs.
  final EvalMetricResultDetails details;

  /// Converts this evaluated spec to JSON.
  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      if (score != null) 'score': score,
      'eval_status': evalStatus.name,
      'details': details.toJson(),
    };
  }
}

/// Metric results grouped by invocation pair.
class EvalMetricResultPerInvocation {
  /// Creates per-invocation metric results.
  EvalMetricResultPerInvocation({
    required this.actualInvocation,
    this.expectedInvocation,
    List<EvalMetricResultSpec>? evalMetricResults,
  }) : evalMetricResults = evalMetricResults ?? <EvalMetricResultSpec>[];

  /// Actual invocation trace.
  final Invocation actualInvocation;

  /// Optional expected invocation trace.
  final Invocation? expectedInvocation;

  /// Evaluated metrics for this invocation pair.
  final List<EvalMetricResultSpec> evalMetricResults;
}

/// Closed or open numeric interval.
class Interval {
  /// Creates an interval.
  Interval({
    required this.minValue,
    this.openAtMin = false,
    required this.maxValue,
    this.openAtMax = false,
  });

  /// Lower bound.
  final double minValue;

  /// Whether the lower bound is open.
  final bool openAtMin;

  /// Upper bound.
  final double maxValue;

  /// Whether the upper bound is open.
  final bool openAtMax;

  /// Creates an interval from JSON.
  factory Interval.fromJson(Map<String, Object?> json) {
    return Interval(
      minValue: asDoubleOr(json['minValue'] ?? json['min_value']),
      openAtMin: (json['openAtMin'] ?? json['open_at_min'] ?? false) as bool,
      maxValue: asDoubleOr(json['maxValue'] ?? json['max_value']),
      openAtMax: (json['openAtMax'] ?? json['open_at_max'] ?? false) as bool,
    );
  }

  /// Converts this interval to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'min_value': minValue,
      'open_at_min': openAtMin,
      'max_value': maxValue,
      'open_at_max': openAtMax,
    };
  }
}

/// Range information for metric values.
class MetricValueInfo {
  /// Creates metric value range information.
  MetricValueInfo({Interval? interval, double? minValue, double? maxValue})
    : interval =
          interval ??
          ((minValue != null || maxValue != null)
              ? Interval(minValue: minValue ?? 0.0, maxValue: maxValue ?? 1.0)
              : null);

  /// Explicit interval definition.
  final Interval? interval;

  /// Minimum value derived from [interval].
  double? get minValue => interval?.minValue;

  /// Maximum value derived from [interval].
  double? get maxValue => interval?.maxValue;

  /// Converts this value info to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (interval != null) 'interval': interval!.toJson(),
      if (interval != null) 'min_value': interval!.minValue,
      if (interval != null) 'max_value': interval!.maxValue,
    };
  }

  /// Creates metric value info from JSON.
  factory MetricValueInfo.fromJson(Map<String, Object?> json) {
    if (json['interval'] != null) {
      return MetricValueInfo(
        interval: Interval.fromJson(asEvalJson(json['interval'])),
      );
    }
    return MetricValueInfo(
      minValue: asNullableDouble(json['min_value']),
      maxValue: asNullableDouble(json['max_value']),
    );
  }
}

/// Human-readable information for one metric.
class MetricInfo {
  /// Creates metric information.
  MetricInfo({
    required this.metricName,
    this.description = '',
    MetricValueInfo? metricValueInfo,
  }) : metricValueInfo = metricValueInfo ?? MetricValueInfo();

  /// Metric name.
  final String metricName;

  /// Metric description.
  final String description;

  /// Valid value range information.
  final MetricValueInfo metricValueInfo;

  /// Creates metric information from JSON.
  factory MetricInfo.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> metricValueMap = asEvalJson(
      json['metricValueInfo'] ?? json['metric_value_info'],
    );
    return MetricInfo(
      metricName: (json['metricName'] ?? json['metric_name'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      metricValueInfo: MetricValueInfo.fromJson(metricValueMap),
    );
  }

  /// Converts this metric information to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metric_name': metricName,
      'description': description,
      'metric_value_info': metricValueInfo.toJson(),
    };
  }
}

/// Provider interface for metric metadata.
abstract class MetricInfoProvider {
  /// Returns metric metadata.
  MetricInfo getMetricInfo();
}
