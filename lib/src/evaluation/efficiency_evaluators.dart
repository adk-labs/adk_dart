/// Informational efficiency metrics for agent evaluation.
///
/// These metrics quantify how expensive an agent was in producing its responses
/// rather than response quality:
/// - `tool_call_count_v1`: tool (function) calls made per invocation.
/// - `inference_call_count_v1`: model inference calls made per invocation.
/// - `invocation_duration_v1`: wall-clock seconds per invocation with model,
///   tool, and framework breakdown.
/// - `token_usage_v1`: tokens consumed per invocation with per-type breakdown.
///
/// All four are reference-free, informational metrics whose status is always
/// [EvalStatus.informational]. Configuring a threshold on any of them throws an
/// [ArgumentError].
library;

import 'dart:math' as math;

import '../telemetry/metrics.dart';
import 'common.dart';
import 'conversation_scenarios.dart';
import 'eval_case.dart';
import 'eval_metrics.dart';
import 'eval_result.dart';
import 'evaluator.dart';

class _InvocationTiming {
  double? duration;
  double? modelDuration;
  double? toolDuration;
}

final Expando<_InvocationTiming> _invocationTimingExpando =
    Expando<_InvocationTiming>('efficiency_invocation_timing');

class _PerInvocationEfficiencyDetails {
  TokenUsageDetails? tokenUsageDetails;
  DurationDetails? durationDetails;
}

final Expando<_PerInvocationEfficiencyDetails> _perInvocationDetailsExpando =
    Expando<_PerInvocationEfficiencyDetails>('per_invocation_efficiency_details');

class _OverallEfficiencyDetails {
  TokenUsageDetails? overallTokenUsageDetails;
  DurationDetails? overallDurationDetails;
}

final Expando<_OverallEfficiencyDetails> _overallDetailsExpando =
    Expando<_OverallEfficiencyDetails>('overall_efficiency_details');

/// An [Invocation] carrying wall-clock duration measurements for efficiency
/// evaluation.
class TimedInvocation extends Invocation {
  /// Creates an [Invocation] with optional wall-clock timing splits in seconds.
  TimedInvocation({
    super.invocationId,
    required super.userContent,
    super.finalResponse,
    super.intermediateData,
    super.creationTimestamp,
    super.rubrics,
    super.appDetails,
    double? duration,
    double? modelDuration,
    double? toolDuration,
  }) : _duration = duration,
       _modelDuration = modelDuration,
       _toolDuration = toolDuration;

  double? _duration;
  double? _modelDuration;
  double? _toolDuration;
}

/// Timing accessors on [Invocation] used by [InvocationDurationV1Evaluator].
extension EfficiencyInvocationTimingX on Invocation {
  /// Total wall-clock seconds this invocation took, or `null` if untimed.
  double? get duration {
    if (this is TimedInvocation) {
      return (this as TimedInvocation)._duration;
    }
    final _InvocationTiming? timing = _invocationTimingExpando[this];
    if (timing != null && timing.duration != null) {
      return timing.duration;
    }
    if (intermediateData is Map) {
      return asNullableDouble((intermediateData as Map)['duration']);
    }
    return null;
  }

  /// Sets total wall-clock seconds this invocation took.
  set duration(double? value) {
    if (this is TimedInvocation) {
      (this as TimedInvocation)._duration = value;
      return;
    }
    (_invocationTimingExpando[this] ??= _InvocationTiming()).duration = value;
  }

  /// Seconds spent with at least one model call in flight, or `null` if unsplit.
  double? get modelDuration {
    if (this is TimedInvocation) {
      return (this as TimedInvocation)._modelDuration;
    }
    final _InvocationTiming? timing = _invocationTimingExpando[this];
    if (timing != null && timing.modelDuration != null) {
      return timing.modelDuration;
    }
    if (intermediateData is Map) {
      final Map<Object?, Object?> map = intermediateData as Map<Object?, Object?>;
      return asNullableDouble(map['model_duration'] ?? map['modelDuration']);
    }
    return null;
  }

  /// Sets seconds spent awaiting model inference.
  set modelDuration(double? value) {
    if (this is TimedInvocation) {
      (this as TimedInvocation)._modelDuration = value;
      return;
    }
    (_invocationTimingExpando[this] ??= _InvocationTiming()).modelDuration =
        value;
  }

  /// Seconds spent inside tools excluding model calls, or `null` if unsplit.
  double? get toolDuration {
    if (this is TimedInvocation) {
      return (this as TimedInvocation)._toolDuration;
    }
    final _InvocationTiming? timing = _invocationTimingExpando[this];
    if (timing != null && timing.toolDuration != null) {
      return timing.toolDuration;
    }
    if (intermediateData is Map) {
      final Map<Object?, Object?> map = intermediateData as Map<Object?, Object?>;
      return asNullableDouble(map['tool_duration'] ?? map['toolDuration']);
    }
    return null;
  }

  /// Sets seconds spent executing tools.
  set toolDuration(double? value) {
    if (this is TimedInvocation) {
      (this as TimedInvocation)._toolDuration = value;
      return;
    }
    (_invocationTimingExpando[this] ??= _InvocationTiming()).toolDuration =
        value;
  }

  /// Returns a [TimedInvocation] copy carrying the specified timing values.
  TimedInvocation withTiming({
    double? duration,
    double? modelDuration,
    double? toolDuration,
  }) {
    return TimedInvocation(
      invocationId: invocationId,
      userContent: userContent,
      finalResponse: finalResponse,
      intermediateData: intermediateData,
      creationTimestamp: creationTimestamp,
      rubrics: rubrics,
      appDetails: appDetails,
      duration: duration ?? this.duration,
      modelDuration: modelDuration ?? this.modelDuration,
      toolDuration: toolDuration ?? this.toolDuration,
    );
  }
}

class _EfficiencyTokenUsageDetails extends TokenUsageDetails {
  const _EfficiencyTokenUsageDetails({
    this.totalTokens,
    this.inputTokens,
    this.promptTokens,
    this.cachedTokens,
    this.toolUseTokens,
    this.outputTokens,
    this.candidatesTokens,
    this.reasoningTokens,
  }) : super(
         promptTokenCount: promptTokens == null ? 0 : (promptTokens ~/ 1),
         candidatesTokenCount: candidatesTokens == null
             ? 0
             : (candidatesTokens ~/ 1),
         thoughtsTokenCount: reasoningTokens == null
             ? 0
             : (reasoningTokens ~/ 1),
         cachedContentTokenCount: cachedTokens == null
             ? 0
             : (cachedTokens ~/ 1),
         toolUsePromptTokenCount: toolUseTokens == null
             ? 0
             : (toolUseTokens ~/ 1),
         totalTokenCount: totalTokens == null ? 0 : (totalTokens ~/ 1),
       );

  final double? totalTokens;
  final double? inputTokens;
  final double? promptTokens;
  final double? cachedTokens;
  final double? toolUseTokens;
  final double? outputTokens;
  final double? candidatesTokens;
  final double? reasoningTokens;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'total_tokens': totalTokens,
      'input_tokens': inputTokens,
      'prompt_tokens': promptTokens,
      'cached_tokens': cachedTokens,
      'tool_use_tokens': toolUseTokens,
      'output_tokens': outputTokens,
      'candidates_tokens': candidatesTokens,
      'reasoning_tokens': reasoningTokens,
    };
  }
}

/// Nullable per-type token breakdown accessors matching ADK Python's
/// `TokenUsageDetails` model.
extension EfficiencyTokenUsageDetailsX on TokenUsageDetails {
  /// Derived total tokens (`inputTokens + outputTokens`), or `null` when n/a.
  double? get totalTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).totalTokens
      : totalTokenCount.toDouble();

  /// Total input tokens (`promptTokens + toolUseTokens`), or `null` when n/a.
  double? get inputTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).inputTokens
      : (promptTokenCount + toolUsePromptTokenCount).toDouble();

  /// Prompt input tokens, or `null` when n/a.
  double? get promptTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).promptTokens
      : promptTokenCount.toDouble();

  /// Cached input tokens, or `null` when n/a.
  double? get cachedTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).cachedTokens
      : cachedContentTokenCount.toDouble();

  /// Server-side tool-use input tokens, or `null` when n/a.
  double? get toolUseTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).toolUseTokens
      : toolUsePromptTokenCount.toDouble();

  /// Total output tokens (`candidatesTokens + reasoningTokens`), or `null` when n/a.
  double? get outputTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).outputTokens
      : (candidatesTokenCount + thoughtsTokenCount).toDouble();

  /// Candidate output tokens, or `null` when n/a.
  double? get candidatesTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).candidatesTokens
      : candidatesTokenCount.toDouble();

  /// Reasoning/thoughts output tokens, or `null` when n/a.
  double? get reasoningTokens => this is _EfficiencyTokenUsageDetails
      ? (this as _EfficiencyTokenUsageDetails).reasoningTokens
      : thoughtsTokenCount.toDouble();
}

/// Constructs a [TokenUsageDetails] with nullable floating-point token buckets
/// matching Python `TokenUsageDetails`.
TokenUsageDetails createTokenUsageDetails({
  double? totalTokens,
  double? inputTokens,
  double? promptTokens,
  double? cachedTokens,
  double? toolUseTokens,
  double? outputTokens,
  double? candidatesTokens,
  double? reasoningTokens,
}) {
  return _EfficiencyTokenUsageDetails(
    totalTokens: totalTokens,
    inputTokens: inputTokens,
    promptTokens: promptTokens,
    cachedTokens: cachedTokens,
    toolUseTokens: toolUseTokens,
    outputTokens: outputTokens,
    candidatesTokens: candidatesTokens,
    reasoningTokens: reasoningTokens,
  );
}

class _EfficiencyDurationDetails extends DurationDetails {
  const _EfficiencyDurationDetails({
    this.totalSeconds,
    this.modelSeconds,
    this.toolSeconds,
    this.frameworkSeconds,
  }) : super(
         totalDurationSeconds: totalSeconds ?? 0.0,
         modelDurationSeconds: modelSeconds ?? 0.0,
         toolDurationSeconds: toolSeconds ?? 0.0,
         frameworkDurationSeconds: frameworkSeconds ?? 0.0,
       );

  final double? totalSeconds;
  final double? modelSeconds;
  final double? toolSeconds;
  final double? frameworkSeconds;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...super.toJson(),
      'total_seconds': totalSeconds,
      'model_seconds': modelSeconds,
      'tool_seconds': toolSeconds,
      'framework_seconds': frameworkSeconds,
    };
  }
}

/// Nullable duration breakdown accessors matching ADK Python's
/// `DurationDetails` model.
extension EfficiencyDurationDetailsX on DurationDetails {
  /// Wall-clock seconds the whole invocation took, or `null` when untimed.
  double? get totalSeconds => this is _EfficiencyDurationDetails
      ? (this as _EfficiencyDurationDetails).totalSeconds
      : totalDurationSeconds;

  /// Seconds with at least one model call in flight, or `null` when unsplit.
  double? get modelSeconds => this is _EfficiencyDurationDetails
      ? (this as _EfficiencyDurationDetails).modelSeconds
      : modelDurationSeconds;

  /// Seconds spent inside tools excluding model calls, or `null` when unsplit.
  double? get toolSeconds => this is _EfficiencyDurationDetails
      ? (this as _EfficiencyDurationDetails).toolSeconds
      : toolDurationSeconds;

  /// Seconds spent in ADK orchestration, derived from the other three, or `null`.
  double? get frameworkSeconds => this is _EfficiencyDurationDetails
      ? (this as _EfficiencyDurationDetails).frameworkSeconds
      : frameworkDurationSeconds;
}

/// Constructs a [DurationDetails] with nullable timing buckets matching Python
/// `DurationDetails`.
DurationDetails createDurationDetails({
  double? totalSeconds,
  double? modelSeconds,
  double? toolSeconds,
  double? frameworkSeconds,
}) {
  return _EfficiencyDurationDetails(
    totalSeconds: totalSeconds,
    modelSeconds: modelSeconds,
    toolSeconds: toolSeconds,
    frameworkSeconds: frameworkSeconds,
  );
}

/// Efficiency breakdown accessors on [PerInvocationResult].
extension EfficiencyPerInvocationResultX on PerInvocationResult {
  /// Per-type token counts reported by [TokenUsageV1Evaluator].
  TokenUsageDetails? get tokenUsageDetails =>
      _perInvocationDetailsExpando[this]?.tokenUsageDetails;

  /// Sets per-type token counts on this invocation result.
  set tokenUsageDetails(TokenUsageDetails? value) {
    (_perInvocationDetailsExpando[this] ??= _PerInvocationEfficiencyDetails())
        .tokenUsageDetails = value;
  }

  /// Duration breakdown reported by [InvocationDurationV1Evaluator].
  DurationDetails? get durationDetails =>
      _perInvocationDetailsExpando[this]?.durationDetails;

  /// Sets duration breakdown on this invocation result.
  set durationDetails(DurationDetails? value) {
    (_perInvocationDetailsExpando[this] ??= _PerInvocationEfficiencyDetails())
        .durationDetails = value;
  }
}

/// Efficiency breakdown accessors on [EvaluationResult].
extension EfficiencyEvaluationResultX on EvaluationResult {
  /// Per-type token counts averaged across invocations by [TokenUsageV1Evaluator].
  TokenUsageDetails? get overallTokenUsageDetails =>
      _overallDetailsExpando[this]?.overallTokenUsageDetails;

  /// Sets overall averaged token counts on this evaluation result.
  set overallTokenUsageDetails(TokenUsageDetails? value) {
    (_overallDetailsExpando[this] ??= _OverallEfficiencyDetails())
        .overallTokenUsageDetails = value;
  }

  /// Duration breakdown averaged across invocations by [InvocationDurationV1Evaluator].
  DurationDetails? get overallDurationDetails =>
      _overallDetailsExpando[this]?.overallDurationDetails;

  /// Sets overall averaged duration breakdown on this evaluation result.
  set overallDurationDetails(DurationDetails? value) {
    (_overallDetailsExpando[this] ??= _OverallEfficiencyDetails())
        .overallDurationDetails = value;
  }
}

/// Returns the usage metadata map for every invocation event in [invocation]
/// that reported it.
List<EvalJsonMap> getAllUsageMetadata(Invocation invocation) {
  final InvocationEvents? events = _asInvocationEvents(
    invocation.intermediateData,
  );
  if (events == null) {
    return <EvalJsonMap>[];
  }
  return <EvalJsonMap>[
    for (final InvocationEvent event in events.invocationEvents)
      if (event.usageMetadata != null) event.usageMetadata!,
  ];
}

InvocationEvents? _asInvocationEvents(Object? intermediateData) {
  if (intermediateData is InvocationEvents) {
    return intermediateData;
  }
  if (intermediateData is Map) {
    final EvalJsonMap map = asEvalJson(intermediateData);
    if (map.containsKey('invocation_events') ||
        map.containsKey('invocationEvents')) {
      return InvocationEvents.fromJson(map);
    }
  }
  return null;
}

void _rejectThreshold(EvalMetricSpec? evalMetric) {
  if (evalMetric == null) {
    return;
  }
  if (evalMetric.threshold == null && evalMetric.criterion == null) {
    return;
  }
  throw ArgumentError(
    '`${evalMetric.metricName}` does not support a threshold: it reports a '
    'value and never passes or fails. Remove it from `criteria` entirely; '
    'it is reported automatically on every eval.',
  );
}

bool _isModelCallEvent(InvocationEvent event) {
  return event.usageMetadata != null || event.modelVersion != null;
}

double _round3(double value) {
  return (value * 1000.0).round() / 1000.0;
}

EvaluationResult _evaluateEfficiencyMetric(
  List<Invocation> actualInvocations,
  double? Function(Invocation invocation) computeValueFn,
) {
  final List<PerInvocationResult> perInvocationResults =
      <PerInvocationResult>[];
  final List<double> values = <double>[];
  for (final Invocation actual in actualInvocations) {
    final double? value = computeValueFn(actual);
    perInvocationResults.add(
      PerInvocationResult(
        actualInvocation: actual,
        score: value,
        evalStatus: EvalStatus.informational,
      ),
    );
    if (value != null) {
      values.add(value);
    }
  }

  if (perInvocationResults.isEmpty) {
    return EvaluationResult(overallEvalStatus: EvalStatus.informational);
  }

  final double? overallScore = values.isEmpty
      ? null
      : values.fold<double>(0.0, (double acc, double v) => acc + v) /
            values.length;
  return EvaluationResult(
    overallScore: overallScore,
    overallEvalStatus: EvalStatus.informational,
    perInvocationResults: perInvocationResults,
  );
}

/// Counts the number of tool (function) calls made in an invocation.
///
/// Informational only: reports the count, never passes or fails.
class ToolCallCountV1Evaluator extends Evaluator {
  /// Creates a [ToolCallCountV1Evaluator], rejecting any configured threshold.
  ToolCallCountV1Evaluator({EvalMetricSpec? evalMetric}) {
    _rejectThreshold(evalMetric);
  }

  double _computeValue(Invocation invocation) {
    return getAllToolCalls(invocation.intermediateData).length.toDouble();
  }

  @override
  EvaluationResult evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) {
    return _evaluateEfficiencyMetric(actualInvocations, _computeValue);
  }
}

/// Counts the number of inference (model) calls made in an invocation.
///
/// Informational only: returns `null` when model-call event data was not
/// captured for the invocation.
class InferenceCallCountV1Evaluator extends Evaluator {
  /// Creates an [InferenceCallCountV1Evaluator], rejecting any configured threshold.
  InferenceCallCountV1Evaluator({EvalMetricSpec? evalMetric}) {
    _rejectThreshold(evalMetric);
  }

  double? _computeValue(Invocation invocation) {
    final InvocationEvents? events = _asInvocationEvents(
      invocation.intermediateData,
    );
    if (events == null) {
      return null;
    }
    int count = 0;
    for (final InvocationEvent event in events.invocationEvents) {
      if (_isModelCallEvent(event)) {
        count += 1;
      }
    }
    return count.toDouble();
  }

  @override
  EvaluationResult evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) {
    return _evaluateEfficiencyMetric(actualInvocations, _computeValue);
  }
}

/// Reports how long an invocation took in seconds, and where the time went
/// across model, tool, and framework buckets.
class InvocationDurationV1Evaluator extends Evaluator {
  /// Creates an [InvocationDurationV1Evaluator], rejecting any configured threshold.
  InvocationDurationV1Evaluator({EvalMetricSpec? evalMetric}) {
    _rejectThreshold(evalMetric);
  }

  DurationDetails _durationDetails(Invocation invocation) {
    final double? total = invocation.duration;
    if (total == null) {
      return const _EfficiencyDurationDetails();
    }
    final double? modelSeconds = invocation.modelDuration;
    final double? toolSeconds = invocation.toolDuration;
    return _EfficiencyDurationDetails(
      totalSeconds: total,
      modelSeconds: modelSeconds,
      toolSeconds: toolSeconds,
      frameworkSeconds: _frameworkSeconds(total, modelSeconds, toolSeconds),
    );
  }

  static double? _frameworkSeconds(
    double total,
    double? modelSeconds,
    double? toolSeconds,
  ) {
    if (modelSeconds == null || toolSeconds == null) {
      return null;
    }
    return _round3(math.max(total - modelSeconds - toolSeconds, 0.0));
  }

  DurationDetails _average(List<DurationDetails> allDetails) {
    double? averageField(double? Function(DurationDetails d) selector) {
      final List<double> present = <double>[
        for (final DurationDetails details in allDetails)
          if (selector(details) != null) selector(details)!,
      ];
      if (present.isEmpty) {
        return null;
      }
      final double sum = present.fold<double>(
        0.0,
        (double acc, double v) => acc + v,
      );
      return _round3(sum / present.length);
    }

    return _EfficiencyDurationDetails(
      totalSeconds: averageField((DurationDetails d) => d.totalSeconds),
      modelSeconds: averageField((DurationDetails d) => d.modelSeconds),
      toolSeconds: averageField((DurationDetails d) => d.toolSeconds),
      frameworkSeconds: averageField((DurationDetails d) => d.frameworkSeconds),
    );
  }

  @override
  EvaluationResult evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) {
    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    final List<DurationDetails> allDetails = <DurationDetails>[];
    for (final Invocation actual in actualInvocations) {
      final DurationDetails details = _durationDetails(actual);
      allDetails.add(details);
      final PerInvocationResult invResult = PerInvocationResult(
        actualInvocation: actual,
        score: details.totalSeconds,
        evalStatus: EvalStatus.informational,
      )..durationDetails = details;
      perInvocationResults.add(invResult);
    }

    if (perInvocationResults.isEmpty) {
      return EvaluationResult(overallEvalStatus: EvalStatus.informational);
    }

    final DurationDetails overallDetails = _average(allDetails);
    return EvaluationResult(
      overallScore: overallDetails.totalSeconds,
      overallEvalStatus: EvalStatus.informational,
      perInvocationResults: perInvocationResults,
    )..overallDurationDetails = overallDetails;
  }
}

/// Sums the token usage reported across all model calls in an invocation.
///
/// Informational only: reports `null` (n/a) rather than `0` when no model call
/// reported a bucket.
class TokenUsageV1Evaluator extends Evaluator {
  /// Creates a [TokenUsageV1Evaluator], rejecting any configured threshold.
  TokenUsageV1Evaluator({EvalMetricSpec? evalMetric}) {
    _rejectThreshold(evalMetric);
  }

  static double? _add(double? total, int? count) {
    if (count == null) {
      return total;
    }
    return (total ?? 0.0) + count;
  }

  TokenUsageDetails _tokenUsageDetails(Invocation invocation) {
    double? inputTokens;
    double? promptTokens;
    double? cachedTokens;
    double? toolUseTokens;
    double? outputTokens;
    double? candidatesTokens;
    double? reasoningTokens;

    for (final EvalJsonMap usageMetadata in getAllUsageMetadata(invocation)) {
      final TokenUsage usage = TokenUsage.fromUsageMetadata(usageMetadata);
      inputTokens = _add(inputTokens, usage.inputTokens);
      promptTokens = _add(promptTokens, usage.promptInputTokens);
      cachedTokens = _add(cachedTokens, usage.cacheReadInputTokens);
      toolUseTokens = _add(toolUseTokens, usage.toolInputTokens);
      outputTokens = _add(outputTokens, usage.outputTokens);
      candidatesTokens = _add(candidatesTokens, usage.candidateOutputTokens);
      reasoningTokens = _add(reasoningTokens, usage.reasoningOutputTokens);
    }

    double? totalTokens;
    if (inputTokens != null || outputTokens != null) {
      totalTokens = (inputTokens ?? 0.0) + (outputTokens ?? 0.0);
    }

    return _EfficiencyTokenUsageDetails(
      totalTokens: totalTokens,
      inputTokens: inputTokens,
      promptTokens: promptTokens,
      cachedTokens: cachedTokens,
      toolUseTokens: toolUseTokens,
      outputTokens: outputTokens,
      candidatesTokens: candidatesTokens,
      reasoningTokens: reasoningTokens,
    );
  }

  TokenUsageDetails _average(List<TokenUsageDetails> allDetails) {
    final List<TokenUsageDetails> reported = <TokenUsageDetails>[
      for (final TokenUsageDetails details in allDetails)
        if (details.totalTokens != null) details,
    ];

    double? averageField(double? Function(TokenUsageDetails d) selector) {
      final List<double?> values = <double?>[
        for (final TokenUsageDetails details in reported) selector(details),
      ];
      final List<double> present = <double>[
        for (final double? value in values) ?value,
      ];
      if (present.isEmpty) {
        return null;
      }
      final double sum = present.fold<double>(
        0.0,
        (double acc, double v) => acc + v,
      );
      return sum / values.length;
    }

    return _EfficiencyTokenUsageDetails(
      totalTokens: averageField((TokenUsageDetails d) => d.totalTokens),
      inputTokens: averageField((TokenUsageDetails d) => d.inputTokens),
      promptTokens: averageField((TokenUsageDetails d) => d.promptTokens),
      cachedTokens: averageField((TokenUsageDetails d) => d.cachedTokens),
      toolUseTokens: averageField((TokenUsageDetails d) => d.toolUseTokens),
      outputTokens: averageField((TokenUsageDetails d) => d.outputTokens),
      candidatesTokens: averageField(
        (TokenUsageDetails d) => d.candidatesTokens,
      ),
      reasoningTokens: averageField((TokenUsageDetails d) => d.reasoningTokens),
    );
  }

  @override
  EvaluationResult evaluateInvocations({
    required List<Invocation> actualInvocations,
    List<Invocation>? expectedInvocations,
    ConversationScenario? conversationScenario,
  }) {
    final List<PerInvocationResult> perInvocationResults =
        <PerInvocationResult>[];
    final List<TokenUsageDetails> allDetails = <TokenUsageDetails>[];
    for (final Invocation actual in actualInvocations) {
      final TokenUsageDetails details = _tokenUsageDetails(actual);
      allDetails.add(details);
      final PerInvocationResult invResult = PerInvocationResult(
        actualInvocation: actual,
        score: details.totalTokens,
        evalStatus: EvalStatus.informational,
      )..tokenUsageDetails = details;
      perInvocationResults.add(invResult);
    }

    if (perInvocationResults.isEmpty) {
      return EvaluationResult(overallEvalStatus: EvalStatus.informational);
    }

    final TokenUsageDetails overallDetails = _average(allDetails);
    return EvaluationResult(
      overallScore: overallDetails.totalTokens,
      overallEvalStatus: EvalStatus.informational,
      perInvocationResults: perInvocationResults,
    )..overallTokenUsageDetails = overallDetails;
  }
}
