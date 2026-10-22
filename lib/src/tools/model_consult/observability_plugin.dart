/// Observability plugin for tracking model consultation usage, escalations, and cost.
library;

import '../../agents/callback_context.dart';
import '../../agents/invocation_context.dart';
import '../../models/llm_response.dart';
import '../../plugins/base_plugin.dart';
import '../base_tool.dart';
import '../tool_context.dart';
import 'force_escalation_plugin.dart';
import 'model_consult_tool.dart';

/// Default estimated input cost in USD per 1M tokens for the primary model.
const double defaultPrimaryInputCostPerMillion = 0.50;

/// Default estimated output cost in USD per 1M tokens for the primary model.
const double defaultPrimaryOutputCostPerMillion = 3.00;

/// Default estimated input cost in USD per 1M tokens for the advisor model.
const double defaultAdvisorInputCostPerMillion = 2.00;

/// Default estimated output cost in USD per 1M tokens for the advisor model.
const double defaultAdvisorOutputCostPerMillion = 12.00;

/// Aggregated token and call usage for a single model.
class ModelConsultUsage {
  /// Creates a [ModelConsultUsage] counter set.
  ModelConsultUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.thoughtTokens = 0,
    this.cachedTokens = 0,
    this.calls = 0,
  });

  /// Total input/prompt tokens consumed.
  int inputTokens;

  /// Total generated output/candidate tokens consumed.
  int outputTokens;

  /// Total reasoning/thought tokens consumed.
  int thoughtTokens;

  /// Total cached prompt tokens served.
  int cachedTokens;

  /// Total number of model invocations recorded.
  int calls;

  /// Adds usage statistics from a single call's [usageMetadata].
  void addFromUsageMetadata(Object? usageMetadata) {
    calls += 1;
    if (usageMetadata == null) {
      return;
    }
    if (usageMetadata is AdvisorUsage) {
      inputTokens += usageMetadata.promptTokenCount ?? 0;
      outputTokens += usageMetadata.candidatesTokenCount ?? 0;
      thoughtTokens += usageMetadata.thoughtsTokenCount ?? 0;
      return;
    }
    if (usageMetadata is ModelConsultUsage) {
      inputTokens += usageMetadata.inputTokens;
      outputTokens += usageMetadata.outputTokens;
      thoughtTokens += usageMetadata.thoughtTokens;
      cachedTokens += usageMetadata.cachedTokens;
      return;
    }
    if (usageMetadata is Map) {
      inputTokens +=
          _readNonNegativeInt(
            usageMetadata['prompt_token_count'] ??
                usageMetadata['promptTokenCount'] ??
                usageMetadata['input_tokens'] ??
                usageMetadata['inputTokens'] ??
                usageMetadata['prompt_tokens'],
          ) ??
          0;
      outputTokens +=
          _readNonNegativeInt(
            usageMetadata['candidates_token_count'] ??
                usageMetadata['candidatesTokenCount'] ??
                usageMetadata['output_tokens'] ??
                usageMetadata['outputTokens'],
          ) ??
          0;
      thoughtTokens +=
          _readNonNegativeInt(
            usageMetadata['thoughts_token_count'] ??
                usageMetadata['thoughtsTokenCount'] ??
                usageMetadata['thought_tokens'] ??
                usageMetadata['thoughtTokens'] ??
                usageMetadata['thoughts_tokens'],
          ) ??
          0;
      cachedTokens +=
          _readNonNegativeInt(
            usageMetadata['cached_content_token_count'] ??
                usageMetadata['cachedContentTokenCount'] ??
                usageMetadata['cached_tokens'] ??
                usageMetadata['cachedTokens'],
          ) ??
          0;
      return;
    }

    try {
      final dynamic dyn = usageMetadata;
      inputTokens += _readNonNegativeInt(dyn.promptTokenCount) ?? 0;
      outputTokens += _readNonNegativeInt(dyn.candidatesTokenCount) ?? 0;
      thoughtTokens += _readNonNegativeInt(dyn.thoughtsTokenCount) ?? 0;
      cachedTokens += _readNonNegativeInt(dyn.cachedContentTokenCount) ?? 0;
    } catch (_) {
      // Ignore unrecognized usage metadata structures.
    }
  }

  /// Creates a copy of this usage record.
  ModelConsultUsage copy() {
    return ModelConsultUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      thoughtTokens: thoughtTokens,
      cachedTokens: cachedTokens,
      calls: calls,
    );
  }

  /// Serializes this usage record to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'thought_tokens': thoughtTokens,
      'cached_tokens': cachedTokens,
      'calls': calls,
    };
  }
}

/// Token usage and cost statistics for a single [model].
class ModelConsultStats {
  /// Creates stats for [model] with optional initial [usage].
  ModelConsultStats({
    required this.model,
    ModelConsultUsage? usage,
  }) : usage = usage ?? ModelConsultUsage();

  /// Model identifier.
  final String model;

  /// Accumulated token and call usage for [model].
  final ModelConsultUsage usage;

  /// Computes the estimated USD cost for [usage] using per-million token rates.
  double estimatedCostUsd({
    required double inputCostPerMillion,
    required double outputCostPerMillion,
  }) {
    final double inputCost =
        (usage.inputTokens / 1000000.0) * inputCostPerMillion;
    final double outputCost =
        ((usage.outputTokens + usage.thoughtTokens) / 1000000.0) *
        outputCostPerMillion;
    return inputCost + outputCost;
  }

  /// Creates a deep copy of these stats.
  ModelConsultStats copy() {
    return ModelConsultStats(
      model: model,
      usage: usage.copy(),
    );
  }
}

/// Immutable snapshot of model consultation observability metrics and costs.
class ModelConsultReport {
  /// Creates a [ModelConsultReport] snapshot.
  ModelConsultReport({
    required this.invocations,
    required this.escalatedInvocations,
    required this.totalAdvisorCalls,
    Map<String, int>? advisorCallsByFocus,
    Map<String, ModelConsultStats>? primaryByModel,
    Map<String, ModelConsultStats>? advisorByModel,
    this.primaryInputCostPerMillion = defaultPrimaryInputCostPerMillion,
    this.primaryOutputCostPerMillion = defaultPrimaryOutputCostPerMillion,
    this.advisorInputCostPerMillion = defaultAdvisorInputCostPerMillion,
    this.advisorOutputCostPerMillion = defaultAdvisorOutputCostPerMillion,
  }) : advisorCallsByFocus = Map<String, int>.unmodifiable(
         advisorCallsByFocus ?? const <String, int>{},
       ),
       primaryByModel = Map<String, ModelConsultStats>.unmodifiable(
         primaryByModel ?? const <String, ModelConsultStats>{},
       ),
       advisorByModel = Map<String, ModelConsultStats>.unmodifiable(
         advisorByModel ?? const <String, ModelConsultStats>{},
       );

  /// Total completed runner invocations observed.
  final int invocations;

  /// Number of invocations that made at least one advisor consultation.
  final int escalatedInvocations;

  /// Total number of advisor consultations across all invocations.
  final int totalAdvisorCalls;

  /// Advisor consultation counts grouped by consultation focus.
  final Map<String, int> advisorCallsByFocus;

  /// Primary (executor) model statistics keyed by model name.
  final Map<String, ModelConsultStats> primaryByModel;

  /// Advisor model statistics keyed by model name.
  final Map<String, ModelConsultStats> advisorByModel;

  /// Input token cost per 1M tokens for primary models.
  final double primaryInputCostPerMillion;

  /// Output token cost per 1M tokens for primary models.
  final double primaryOutputCostPerMillion;

  /// Input token cost per 1M tokens for advisor models.
  final double advisorInputCostPerMillion;

  /// Output token cost per 1M tokens for advisor models.
  final double advisorOutputCostPerMillion;

  /// Fraction of invocations that escalated to the advisor (`0.0` to `1.0`).
  double get escalationRate =>
      invocations == 0 ? 0.0 : escalatedInvocations / invocations;

  /// Mean number of advisor consultations per invocation.
  double get avgEscalationsPerInvocation =>
      invocations == 0 ? 0.0 : totalAdvisorCalls / invocations;

  /// Total input tokens consumed by primary models.
  int get totalPrimaryInputTokens => primaryByModel.values.fold(
    0,
    (int sum, ModelConsultStats stat) => sum + stat.usage.inputTokens,
  );

  /// Total output tokens consumed by primary models.
  int get totalPrimaryOutputTokens => primaryByModel.values.fold(
    0,
    (int sum, ModelConsultStats stat) => sum + stat.usage.outputTokens,
  );

  /// Total input tokens consumed by advisor models.
  int get totalAdvisorInputTokens => advisorByModel.values.fold(
    0,
    (int sum, ModelConsultStats stat) => sum + stat.usage.inputTokens,
  );

  /// Total output tokens consumed by advisor models.
  int get totalAdvisorOutputTokens => advisorByModel.values.fold(
    0,
    (int sum, ModelConsultStats stat) => sum + stat.usage.outputTokens,
  );

  /// Estimated USD cost of all primary model calls.
  double get estimatedPrimaryCostUsd => primaryByModel.values.fold(
    0.0,
    (double sum, ModelConsultStats stat) =>
        sum +
        stat.estimatedCostUsd(
          inputCostPerMillion: primaryInputCostPerMillion,
          outputCostPerMillion: primaryOutputCostPerMillion,
        ),
  );

  /// Estimated USD cost of all advisor model calls.
  double get estimatedAdvisorCostUsd => advisorByModel.values.fold(
    0.0,
    (double sum, ModelConsultStats stat) =>
        sum +
        stat.estimatedCostUsd(
          inputCostPerMillion: advisorInputCostPerMillion,
          outputCostPerMillion: advisorOutputCostPerMillion,
        ),
  );

  /// Combined estimated USD cost across primary and advisor models.
  double get estimatedTotalCostUsd =>
      estimatedPrimaryCostUsd + estimatedAdvisorCostUsd;

  /// Converts this report into a JSON-serializable summary map.
  Map<String, Object?> toSummaryMap() {
    return <String, Object?>{
      'invocations': invocations,
      'escalated_invocations': escalatedInvocations,
      'escalation_rate': escalationRate,
      'total_advisor_calls': totalAdvisorCalls,
      'avg_escalations_per_invocation': avgEscalationsPerInvocation,
      'advisor_calls_by_focus': Map<String, int>.from(advisorCallsByFocus),
      'total_primary_input_tokens': totalPrimaryInputTokens,
      'total_primary_output_tokens': totalPrimaryOutputTokens,
      'total_advisor_input_tokens': totalAdvisorInputTokens,
      'total_advisor_output_tokens': totalAdvisorOutputTokens,
      'estimated_primary_cost_usd': estimatedPrimaryCostUsd,
      'estimated_advisor_cost_usd': estimatedAdvisorCostUsd,
      'estimated_total_cost_usd': estimatedTotalCostUsd,
      'primary_by_model': <String, Object?>{
        for (final MapEntry<String, ModelConsultStats> entry
            in primaryByModel.entries)
          entry.key: entry.value.usage.toJson(),
      },
      'advisor_by_model': <String, Object?>{
        for (final MapEntry<String, ModelConsultStats> entry
            in advisorByModel.entries)
          entry.key: entry.value.usage.toJson(),
      },
    };
  }

  /// Formats a human-readable multi-line summary of this report.
  String formatSummary() {
    final String ratePct = (escalationRate * 100).toStringAsFixed(1);
    final StringBuffer buffer = StringBuffer()
      ..writeln('Model Consult Observability Summary')
      ..writeln(
        '  Invocations: $invocations '
        '(escalated: $escalatedInvocations, rate: $ratePct%)',
      )
      ..writeln(
        '  Advisor calls: $totalAdvisorCalls '
        '(avg/invocation: ${avgEscalationsPerInvocation.toStringAsFixed(2)})',
      )
      ..writeln(
        '  Primary tokens: in=$totalPrimaryInputTokens, '
        'out=$totalPrimaryOutputTokens',
      )
      ..writeln(
        '  Advisor tokens: in=$totalAdvisorInputTokens, '
        'out=$totalAdvisorOutputTokens',
      )
      ..write(
        '  Estimated cost (USD): '
        'primary=\$${estimatedPrimaryCostUsd.toStringAsFixed(6)}, '
        'advisor=\$${estimatedAdvisorCostUsd.toStringAsFixed(6)}, '
        'total=\$${estimatedTotalCostUsd.toStringAsFixed(6)}',
      );
    return buffer.toString();
  }
}

class _InvocationScratch {
  int advisorCalls = 0;
}

/// Plugin that records primary model usage, [ConsultModelTool] escalations, and
/// estimated token costs across invocations.
///
/// ```dart
/// final observability = ModelConsultObservabilityPlugin();
/// final runner = InMemoryRunner(
///   agent: agent,
///   plugins: <BasePlugin>[observability],
/// );
///
/// // After running invocations:
/// final report = observability.getReport();
/// print(report.formatSummary());
/// ```
class ModelConsultObservabilityPlugin extends BasePlugin {
  /// Creates a [ModelConsultObservabilityPlugin] with optional cost rates.
  ModelConsultObservabilityPlugin({
    super.name = 'model_consult_observability',
    this.primaryInputCostPerMillion = defaultPrimaryInputCostPerMillion,
    this.primaryOutputCostPerMillion = defaultPrimaryOutputCostPerMillion,
    this.advisorInputCostPerMillion = defaultAdvisorInputCostPerMillion,
    this.advisorOutputCostPerMillion = defaultAdvisorOutputCostPerMillion,
  });

  /// Input token cost per 1M tokens for primary models.
  final double primaryInputCostPerMillion;

  /// Output token cost per 1M tokens for primary models.
  final double primaryOutputCostPerMillion;

  /// Input token cost per 1M tokens for advisor models.
  final double advisorInputCostPerMillion;

  /// Output token cost per 1M tokens for advisor models.
  final double advisorOutputCostPerMillion;

  int _invocations = 0;
  int _escalatedInvocations = 0;
  int _totalAdvisorCalls = 0;
  final Map<String, int> _advisorCallsByFocus = <String, int>{};
  final Map<String, ModelConsultStats> _primaryByModel =
      <String, ModelConsultStats>{};
  final Map<String, ModelConsultStats> _advisorByModel =
      <String, ModelConsultStats>{};
  final Map<String, _InvocationScratch> _scratchByInvocation =
      <String, _InvocationScratch>{};

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    if (llmResponse.partial == true) {
      return null;
    }
    _scratchByInvocation.putIfAbsent(
      callbackContext.invocationId,
      _InvocationScratch.new,
    );
    final String modelName =
        (llmResponse.modelVersion != null &&
            llmResponse.modelVersion!.trim().isNotEmpty)
        ? llmResponse.modelVersion!.trim()
        : 'unknown';
    final ModelConsultStats stats = _primaryByModel.putIfAbsent(
      modelName,
      () => ModelConsultStats(model: modelName),
    );
    stats.usage.addFromUsageMetadata(llmResponse.usageMetadata);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    if (tool is! ModelConsultTool) {
      return null;
    }
    final Object? status = result['status'];
    if (status == 'error' ||
        status == 'limit_reached' ||
        status == 'invalid_request' ||
        status == consultRequiredStatus ||
        result['error'] != null) {
      return null;
    }

    final _InvocationScratch scratch = _scratchByInvocation.putIfAbsent(
      toolContext.invocationId,
      _InvocationScratch.new,
    );
    scratch.advisorCalls += 1;
    _totalAdvisorCalls += 1;

    final Object? rawFocus = toolArgs['focus'] ?? result['focus'];
    final String focus = (rawFocus is String && rawFocus.trim().isNotEmpty)
        ? rawFocus.trim()
        : 'general';
    _advisorCallsByFocus[focus] = (_advisorCallsByFocus[focus] ?? 0) + 1;

    final Object? rawModel = result['model'] ?? result['advisor_model'];
    String advisorModel;
    if (rawModel is String && rawModel.trim().isNotEmpty) {
      advisorModel = rawModel.trim();
    } else if (tool.model is String && (tool.model as String).trim().isNotEmpty) {
      advisorModel = (tool.model as String).trim();
    } else {
      try {
        advisorModel = tool.resolvedModel.model;
      } catch (_) {
        advisorModel = 'unknown';
      }
    }

    final ModelConsultStats stats = _advisorByModel.putIfAbsent(
      advisorModel,
      () => ModelConsultStats(model: advisorModel),
    );
    stats.usage.addFromUsageMetadata(result['usage']);
    return null;
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    final _InvocationScratch? scratch = _scratchByInvocation.remove(
      invocationContext.invocationId,
    );
    _invocations += 1;
    if (scratch != null && scratch.advisorCalls > 0) {
      _escalatedInvocations += 1;
    }
  }

  /// Returns an immutable [ModelConsultReport] snapshot of recorded metrics.
  ModelConsultReport getReport() {
    return ModelConsultReport(
      invocations: _invocations,
      escalatedInvocations: _escalatedInvocations,
      totalAdvisorCalls: _totalAdvisorCalls,
      advisorCallsByFocus: Map<String, int>.from(_advisorCallsByFocus),
      primaryByModel: <String, ModelConsultStats>{
        for (final MapEntry<String, ModelConsultStats> entry
            in _primaryByModel.entries)
          entry.key: entry.value.copy(),
      },
      advisorByModel: <String, ModelConsultStats>{
        for (final MapEntry<String, ModelConsultStats> entry
            in _advisorByModel.entries)
          entry.key: entry.value.copy(),
      },
      primaryInputCostPerMillion: primaryInputCostPerMillion,
      primaryOutputCostPerMillion: primaryOutputCostPerMillion,
      advisorInputCostPerMillion: advisorInputCostPerMillion,
      advisorOutputCostPerMillion: advisorOutputCostPerMillion,
    );
  }

  /// Resets all accumulated counters and per-invocation scratch state.
  void reset() {
    _invocations = 0;
    _escalatedInvocations = 0;
    _totalAdvisorCalls = 0;
    _advisorCallsByFocus.clear();
    _primaryByModel.clear();
    _advisorByModel.clear();
    _scratchByInvocation.clear();
  }
}

int? _readNonNegativeInt(Object? value) {
  if (value is bool || value == null) {
    return null;
  }
  if (value is int) {
    return value >= 0 ? value : 0;
  }
  if (value is num) {
    final int asInt = value.toInt();
    return asInt >= 0 ? asInt : 0;
  }
  if (value is String) {
    final int? parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed >= 0 ? parsed : 0;
    }
  }
  return null;
}
