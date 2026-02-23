import 'common.dart';
import 'eval_case.dart';
import 'eval_result.dart';
import 'eval_rubrics.dart';

typedef Threshold = double;

class PrebuiltMetricNames {
  static const String toolTrajectoryAvgScore = 'tool_trajectory_avg_score';
  static const String responseEvaluationScore = 'response_evaluation_score';
  static const String responseMatchScore = 'response_match_score';
  static const String safetyV1 = 'safety_v1';
  static const String finalResponseMatchV2 = 'final_response_match_v2';
  static const String rubricBasedFinalResponseQualityV1 =
      'rubric_based_final_response_quality_v1';
  static const String hallucinationsV1 = 'hallucinations_v1';
  static const String rubricBasedToolUseQualityV1 =
      'rubric_based_tool_use_quality_v1';
  static const String perTurnUserSimulatorQualityV1 =
      'per_turn_user_simulator_quality_v1';
}

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
  );

  const PrebuiltMetrics(this.value);
  final String value;
}

class JudgeModelOptions {
  JudgeModelOptions({
    this.judgeModel = 'gemini-2.5-flash',
    this.judgeModelConfig,
    this.numSamples = 5,
  });

  final String judgeModel;
  final Object? judgeModelConfig;
  final int numSamples;

  factory JudgeModelOptions.fromJson(Map<String, Object?> json) {
    return JudgeModelOptions(
      judgeModel:
          (json['judgeModel'] ?? json['judge_model'] ?? 'gemini-2.5-flash')
              as String,
      judgeModelConfig: json['judgeModelConfig'] ?? json['judge_model_config'],
      numSamples: (json['numSamples'] ?? json['num_samples'] ?? 5) as int,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'judge_model': judgeModel,
      if (judgeModelConfig != null) 'judge_model_config': judgeModelConfig,
      'num_samples': numSamples,
    };
  }
}

class BaseCriterion {
  BaseCriterion({required this.threshold, Map<String, Object?>? extra})
    : extra = extra ?? <String, Object?>{};

  final double threshold;
  final Map<String, Object?> extra;

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

  Map<String, Object?> toJson() {
    return <String, Object?>{'threshold': threshold, ...extra};
  }
}

class LlmAsAJudgeCriterion extends BaseCriterion {
  LlmAsAJudgeCriterion({
    required super.threshold,
    JudgeModelOptions? judgeModelOptions,
    super.extra,
  }) : judgeModelOptions = judgeModelOptions ?? JudgeModelOptions();

  final JudgeModelOptions judgeModelOptions;

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

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'judge_model_options': judgeModelOptions.toJson(),
    };
  }
}

class RubricsBasedCriterion extends BaseCriterion {
  RubricsBasedCriterion({
    required super.threshold,
    JudgeModelOptions? judgeModelOptions,
    List<Rubric>? rubrics,
    super.extra,
  }) : judgeModelOptions = judgeModelOptions ?? JudgeModelOptions(),
       rubrics = rubrics ?? <Rubric>[];

  final JudgeModelOptions judgeModelOptions;
  final List<Rubric> rubrics;

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

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'judge_model_options': judgeModelOptions.toJson(),
      'rubrics': rubrics.map((Rubric value) => value.toJson()).toList(),
    };
  }
}

class HallucinationsCriterion extends BaseCriterion {
  HallucinationsCriterion({
    required super.threshold,
    JudgeModelOptions? judgeModelOptions,
    this.evaluateIntermediateNlResponses = false,
    super.extra,
  }) : judgeModelOptions = judgeModelOptions ?? JudgeModelOptions();

  final JudgeModelOptions judgeModelOptions;
  final bool evaluateIntermediateNlResponses;

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

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'judge_model_options': judgeModelOptions.toJson(),
      'evaluate_intermediate_nl_responses': evaluateIntermediateNlResponses,
    };
  }
}

class ToolTrajectoryCriterion extends BaseCriterion {
  ToolTrajectoryCriterion({
    required super.threshold,
    this.matchType = MatchType.exact,
    super.extra,
  });

  final MatchType matchType;

  factory ToolTrajectoryCriterion.fromJson(Object? value) {
    final BaseCriterion base = BaseCriterion.fromJson(value);
    final Map<String, Object?> map = asEvalJson(value);
    return ToolTrajectoryCriterion(
      threshold: base.threshold,
      matchType: MatchTypeX.fromObject(map['matchType'] ?? map['match_type']),
      extra: base.extra,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'match_type': matchType.wireName,
    };
  }
}

enum MatchType { exact, inOrder, anyOrder }

extension MatchTypeX on MatchType {
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

class LlmBackedUserSimulatorCriterion extends LlmAsAJudgeCriterion {
  LlmBackedUserSimulatorCriterion({
    required super.threshold,
    super.judgeModelOptions,
    this.stopSignal = '</finished>',
    super.extra,
  });

  final String stopSignal;

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

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{...super.toJson(), 'stop_signal': stopSignal};
  }
}

class EvalMetricSpec {
  EvalMetricSpec({
    required this.metricName,
    this.threshold,
    this.criterion,
    this.customFunctionPath,
  });

  final String metricName;
  final double? threshold;
  final BaseCriterion? criterion;
  final String? customFunctionPath;

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

class EvalMetricResultDetails {
  EvalMetricResultDetails({List<RubricScore>? rubricScores})
    : rubricScores = rubricScores ?? <RubricScore>[];

  final List<RubricScore> rubricScores;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rubric_scores': rubricScores
          .map((RubricScore value) => value.toJson())
          .toList(),
    };
  }
}

class EvalMetricResultSpec extends EvalMetricSpec {
  EvalMetricResultSpec({
    required super.metricName,
    super.threshold,
    super.criterion,
    super.customFunctionPath,
    this.score,
    this.evalStatus = EvalStatus.notEvaluated,
    EvalMetricResultDetails? details,
  }) : details = details ?? EvalMetricResultDetails();

  final double? score;
  final EvalStatus evalStatus;
  final EvalMetricResultDetails details;

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

class EvalMetricResultPerInvocation {
  EvalMetricResultPerInvocation({
    required this.actualInvocation,
    this.expectedInvocation,
    List<EvalMetricResultSpec>? evalMetricResults,
  }) : evalMetricResults = evalMetricResults ?? <EvalMetricResultSpec>[];

  final Invocation actualInvocation;
  final Invocation? expectedInvocation;
  final List<EvalMetricResultSpec> evalMetricResults;
}

class Interval {
  Interval({
    required this.minValue,
    this.openAtMin = false,
    required this.maxValue,
    this.openAtMax = false,
  });

  final double minValue;
  final bool openAtMin;
  final double maxValue;
  final bool openAtMax;

  factory Interval.fromJson(Map<String, Object?> json) {
    return Interval(
      minValue: asDoubleOr(json['minValue'] ?? json['min_value']),
      openAtMin: (json['openAtMin'] ?? json['open_at_min'] ?? false) as bool,
      maxValue: asDoubleOr(json['maxValue'] ?? json['max_value']),
      openAtMax: (json['openAtMax'] ?? json['open_at_max'] ?? false) as bool,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'min_value': minValue,
      'open_at_min': openAtMin,
      'max_value': maxValue,
      'open_at_max': openAtMax,
    };
  }
}

class MetricValueInfo {
  MetricValueInfo({Interval? interval, double? minValue, double? maxValue})
    : interval =
          interval ??
          ((minValue != null || maxValue != null)
              ? Interval(minValue: minValue ?? 0.0, maxValue: maxValue ?? 1.0)
              : null);

  final Interval? interval;

  double? get minValue => interval?.minValue;
  double? get maxValue => interval?.maxValue;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (interval != null) 'interval': interval!.toJson(),
      if (interval != null) 'min_value': interval!.minValue,
      if (interval != null) 'max_value': interval!.maxValue,
    };
  }

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

class MetricInfo {
  MetricInfo({
    required this.metricName,
    this.description = '',
    MetricValueInfo? metricValueInfo,
  }) : metricValueInfo = metricValueInfo ?? MetricValueInfo();

  final String metricName;
  final String description;
  final MetricValueInfo metricValueInfo;

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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'metric_name': metricName,
      'description': description,
      'metric_value_info': metricValueInfo.toJson(),
    };
  }
}

abstract class MetricInfoProvider {
  MetricInfo getMetricInfo();
}
