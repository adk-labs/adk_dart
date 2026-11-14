import 'package:adk_dart/adk_dart.dart' as core;
import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

String _formatRunSymbol(core.EvalCaseResult run) {
  if (core.countRunsFailedWithoutMetricResults(<core.EvalCaseResult>[run]) >
      0) {
    return 'C';
  }
  final core.EvalStatus status = core.getRunStatus(run);
  if (status == core.EvalStatus.passed) {
    return 'P';
  }
  if (status == core.EvalStatus.failed) {
    return 'F';
  }
  return '-';
}

double? _extractRunMetricScore(core.EvalCaseResult run, String metricName) {
  for (final core.EvalMetricResultSpec metricResult
      in run.overallEvalMetricResults) {
    if (metricResult.metricName == metricName && metricResult.score != null) {
      return metricResult.score;
    }
  }
  final List<double> invocationScores = <double>[
    for (final core.EvalMetricResultPerInvocation inv
        in run.evalMetricResultPerInvocation)
      for (final core.EvalMetricResultSpec metricResult
          in inv.evalMetricResults)
        if (metricResult.metricName == metricName && metricResult.score != null)
          metricResult.score!,
  ];
  if (invocationScores.isNotEmpty) {
    final double sum = invocationScores.fold<double>(
      0.0,
      (double acc, double val) => acc + val,
    );
    return sum / invocationScores.length;
  }
  return null;
}

String _statusUpperLabel(core.EvalStatus status) {
  switch (status) {
    case core.EvalStatus.passed:
      return 'PASSED';
    case core.EvalStatus.failed:
      return 'FAILED';
    case core.EvalStatus.notEvaluated:
      return 'NOT_EVALUATED';
    case core.EvalStatus.informational:
      return 'INFORMATIONAL';
  }
}

/// Cross-run criterion summary (such as `pass@3` or `pass^3`) for one eval case.
@immutable
class AdkMultiRunCriterionSummary {
  /// Creates an [AdkMultiRunCriterionSummary].
  const AdkMultiRunCriterionSummary({
    required this.name,
    this.value,
    this.threshold,
    this.passed = true,
    this.isInformational = false,
    this.statusLabel = 'PASSED',
    this.note,
  });

  /// Converts a persisted [core.MethodResult] into an [AdkMultiRunCriterionSummary].
  factory AdkMultiRunCriterionSummary.fromMethodResult(core.MethodResult res) {
    final bool isInfo =
        res.status == core.EvalStatus.informational ||
        res.status == core.EvalStatus.notEvaluated;
    return AdkMultiRunCriterionSummary(
      name: res.name,
      value: res.value,
      threshold: res.threshold,
      passed: res.status == core.EvalStatus.passed || isInfo,
      isInformational: isInfo,
      statusLabel: _statusUpperLabel(res.status),
      note: res.note,
    );
  }

  /// Criterion name (e.g. `'pass_at_3'`, `'pass@3'`, `'pass^3'`).
  final String name;

  /// Computed cross-run criterion value, if evaluated.
  final double? value;

  /// Optional gating threshold.
  final double? threshold;

  /// Whether the criterion passed (or was informational).
  final bool passed;

  /// Whether the criterion is report-only (`INFORMATIONAL` or `NOT_EVALUATED`).
  final bool isInformational;

  /// Uppercase status label (`PASSED`, `FAILED`, `INFORMATIONAL`, `NOT_EVALUATED`).
  final String statusLabel;

  /// Optional breakdown note.
  final String? note;

  /// Formatted summary matching CLI output (`name=0.67` or `name=0.67 (PASSED)`).
  String get formattedSummary {
    final String valStr = value != null ? value!.toStringAsFixed(2) : 'n/a';
    if (isInformational) {
      return '$name=$valStr';
    }
    return '$name=$valStr ($statusLabel)';
  }
}

/// Per-metric aggregated score summary across multiple evaluation runs.
@immutable
class AdkMultiRunMetricSummary {
  /// Creates an [AdkMultiRunMetricSummary].
  const AdkMultiRunMetricSummary({
    required this.metricName,
    required this.methodName,
    this.value,
    this.threshold,
    this.passed = true,
    this.isInformational = false,
    this.note,
    this.perRunScores = const <double?>[],
  });

  /// Name of the evaluated metric.
  final String metricName;

  /// Aggregation method name (for example `'mean_over_invocations'`, `'mean_of_runs'`, `'min_over_runs'`, `'pass_at_k'`, `'pass_hat_k'`).
  final String methodName;

  /// Aggregated score value, if evaluated.
  final double? value;

  /// Configured pass threshold, if any.
  final double? threshold;

  /// Whether this aggregated metric passed its threshold.
  final bool passed;

  /// Whether this metric was evaluated in report-only / informational mode (no threshold).
  final bool isInformational;

  /// Optional human-readable breakdown note.
  final String? note;

  /// Optional per-run score list in repetition order (`null` when a run produced no score).
  final List<double?> perRunScores;

  /// Formatted per-run score strip (`runs: [1.00, 0.50, -]`), or `null` when [perRunScores] is empty.
  String? get formattedRunScoresStrip {
    if (perRunScores.isEmpty) {
      return null;
    }
    final List<String> formatted = <String>[
      for (final double? s in perRunScores)
        s != null ? s.toStringAsFixed(2) : '-',
    ];
    return 'runs: [${formatted.join(', ')}]';
  }

  /// The human-friendly label for [methodName], formatting `'pass_at_k'` as `'pass@k'` and `'pass_hat_k'` as `'pass^k'`.
  String get displayMethodName {
    if (methodName == 'pass_at_k') {
      return 'pass@k';
    }
    if (methodName == 'pass_hat_k') {
      return 'pass^k';
    }
    return methodName;
  }
}

/// Summary of a single evaluation case executed across multiple repetitions.
@immutable
class AdkMultiRunCaseSummary {
  /// Creates an [AdkMultiRunCaseSummary].
  const AdkMultiRunCaseSummary({
    required this.evalId,
    required this.totalRuns,
    required this.passedRuns,
    required this.passed,
    this.failedRuns = 0,
    this.crashedRuns = 0,
    this.notEvaluatedRuns = 0,
    this.runStatusStrip,
    double? passRateOverride,
    this.metrics = const <AdkMultiRunMetricSummary>[],
    this.crossRunCriteria = const <AdkMultiRunCriterionSummary>[],
  }) : _passRateOverride = passRateOverride;

  /// Converts an ADK [core.MultiRunCaseResult] into an [AdkMultiRunCaseSummary].
  factory AdkMultiRunCaseSummary.fromCore(core.MultiRunCaseResult result) {
    final core.MultiRunCaseSummary persisted =
        core.summarizeMultiRunCaseResult(result);
    return AdkMultiRunCaseSummary.fromCoreSummary(
      persisted,
      runs: result.runs,
    );
  }

  /// Converts a persisted ADK [core.MultiRunCaseSummary] (with optional per-repetition
  /// [runs] from [core.EvalSetResult.evalCaseResults]) into an [AdkMultiRunCaseSummary].
  factory AdkMultiRunCaseSummary.fromCoreSummary(
    core.MultiRunCaseSummary summary, {
    List<core.EvalCaseResult>? runs,
  }) {
    final List<core.EvalCaseResult>? matchingRuns = runs
        ?.where((core.EvalCaseResult r) => r.evalId == summary.evalId)
        .toList(growable: false);

    final String statusStrip;
    if (matchingRuns != null && matchingRuns.isNotEmpty) {
      statusStrip = matchingRuns.map(_formatRunSymbol).join();
    } else {
      statusStrip =
          '${'P' * summary.passedRuns}'
          '${'F' * summary.failedRuns}'
          '${'C' * summary.crashedRuns}'
          '${'-' * summary.notEvaluatedRuns}';
    }

    final List<AdkMultiRunMetricSummary> uiMetrics =
        <AdkMultiRunMetricSummary>[];
    if (summary.metricMethods.isNotEmpty) {
      final Map<String, core.EvalMetricResultSpec> specsByName =
          <String, core.EvalMetricResultSpec>{
            for (final core.EvalMetricResultSpec s
                in summary.overallEvalMetricResults)
              s.metricName: s,
          };
      for (final MapEntry<String, core.MethodResult> entry
          in summary.metricMethods.entries) {
        final String metricName = entry.key;
        final core.MethodResult methodResult = entry.value;
        final core.EvalMetricResultSpec? spec = specsByName[metricName];
        final bool isInfo =
            methodResult.status == core.EvalStatus.informational &&
            (spec == null || spec.evalStatus == core.EvalStatus.informational);
        final bool metricPassed = spec != null
            ? (spec.evalStatus == core.EvalStatus.passed ||
                  spec.evalStatus == core.EvalStatus.informational)
            : (methodResult.status == core.EvalStatus.passed || isInfo);
        final List<double?> perRunScores =
            matchingRuns != null && matchingRuns.isNotEmpty
            ? <double?>[
                for (final core.EvalCaseResult r in matchingRuns)
                  _extractRunMetricScore(r, metricName),
              ]
            : const <double?>[];
        uiMetrics.add(
          AdkMultiRunMetricSummary(
            metricName: metricName,
            methodName: methodResult.name,
            value: spec?.score ?? methodResult.value,
            threshold:
                methodResult.threshold ??
                spec?.threshold ??
                spec?.criterion?.threshold,
            passed: metricPassed,
            isInformational: isInfo,
            note: methodResult.note,
            perRunScores: perRunScores,
          ),
        );
      }
    } else {
      for (final core.EvalMetricResultSpec spec
          in summary.overallEvalMetricResults) {
        final bool isInfo = spec.evalStatus == core.EvalStatus.informational;
        final List<double?> perRunScores =
            matchingRuns != null && matchingRuns.isNotEmpty
            ? <double?>[
                for (final core.EvalCaseResult r in matchingRuns)
                  _extractRunMetricScore(r, spec.metricName),
              ]
            : const <double?>[];
        uiMetrics.add(
          AdkMultiRunMetricSummary(
            metricName: spec.metricName,
            methodName: 'mean_over_invocations',
            value: spec.score,
            threshold: spec.threshold ?? spec.criterion?.threshold,
            passed: spec.evalStatus == core.EvalStatus.passed || isInfo,
            isInformational: isInfo,
            perRunScores: perRunScores,
          ),
        );
      }
    }

    return AdkMultiRunCaseSummary(
      evalId: summary.evalId,
      totalRuns: summary.numRuns,
      passedRuns: summary.passedRuns,
      failedRuns: summary.failedRuns,
      crashedRuns: summary.crashedRuns,
      notEvaluatedRuns: summary.notEvaluatedRuns,
      runStatusStrip: statusStrip,
      passRateOverride: summary.passRate,
      passed: summary.finalEvalStatus == core.EvalStatus.passed ||
          summary.finalEvalStatus == core.EvalStatus.informational,
      metrics: uiMetrics,
      crossRunCriteria: summary.crossRunResults
          .map(AdkMultiRunCriterionSummary.fromMethodResult)
          .toList(growable: false),
    );
  }

  /// Evaluation case identifier.
  final String evalId;

  /// Total number of repetition runs executed for this case.
  final int totalRuns;

  /// Number of repetition runs that passed all metrics.
  final int passedRuns;

  /// Number of repetition runs that failed metrics.
  final int failedRuns;

  /// Number of repetition runs that crashed without metric results.
  final int crashedRuns;

  /// Number of non-crashed repetition runs that were not evaluated.
  final int notEvaluatedRuns;

  /// Compact per-run status strip (`P` passed, `F` failed, `C` crashed, `-` not evaluated).
  final String? runStatusStrip;

  final double? _passRateOverride;

  /// Whether the case passed overall cross-run evaluation criteria.
  final bool passed;

  /// Per-metric aggregated results for this case.
  final List<AdkMultiRunMetricSummary> metrics;

  /// Configured case-level cross-run criteria results.
  final List<AdkMultiRunCriterionSummary> crossRunCriteria;

  /// Number of decided runs (`passedRuns + failedRuns`), falling back to non-crashed/non-unevaluated runs.
  int get decidedRuns {
    if (passedRuns + failedRuns > 0) {
      return passedRuns + failedRuns;
    }
    final int remaining = totalRuns - crashedRuns - notEvaluatedRuns;
    return remaining > 0 ? remaining : 0;
  }

  /// Fraction of decided runs that passed (`0.0` to `1.0`), or `null` when no run was decided.
  double? get decidedPassRate {
    if (_passRateOverride != null) {
      return _passRateOverride;
    }
    final int decided = decidedRuns;
    return decided > 0 ? passedRuns / decided : null;
  }

  /// Pass rate across runs in the range `0.0` to `1.0`.
  double get passRate =>
      decidedPassRate ?? (totalRuns > 0 ? passedRuns / totalRuns : 0.0);

  /// Formatted pass rate label (for example `'Pass Rate: 67%'` or `'Pass Rate: n/a'`).
  String get formattedPassRateLabel {
    final double? rate = decidedPassRate;
    if (rate == null) {
      return 'Pass Rate: n/a';
    }
    return 'Pass Rate: ${(rate * 100).round()}%';
  }
}

/// A summary card widget that displays aggregated statistics across multi-run evaluation cases.
class AdkMultiRunEvalCard extends StatelessWidget {
  /// Creates an [AdkMultiRunEvalCard].
  const AdkMultiRunEvalCard({
    super.key,
    required this.caseSummaries,
    this.title = 'Multi-Run Evaluation Summary',
    this.style,
    this.passColor,
    this.warnColor,
    this.failColor,
    this.leadingIcon,
    this.trailingWidget,
    this.headerBuilder,
    this.caseRowBuilder,
    this.metricChipBuilder,
  });

  /// Creates an [AdkMultiRunEvalCard] directly from [core.MultiRunCaseResult] instances.
  factory AdkMultiRunEvalCard.fromCoreResults({
    Key? key,
    required List<core.MultiRunCaseResult> results,
    String title = 'Multi-Run Evaluation Summary',
    AdkCardStyle? style,
    Color? passColor,
    Color? warnColor,
    Color? failColor,
    Widget? leadingIcon,
    Widget? trailingWidget,
    Widget Function(
      BuildContext context,
      int passedCases,
      int totalCases,
      double passRate,
    )? headerBuilder,
    Widget Function(BuildContext context, AdkMultiRunCaseSummary summary)?
        caseRowBuilder,
    Widget Function(BuildContext context, AdkMultiRunMetricSummary metric)?
        metricChipBuilder,
  }) {
    return AdkMultiRunEvalCard(
      key: key,
      title: title,
      caseSummaries: results.map(AdkMultiRunCaseSummary.fromCore).toList(),
      style: style,
      passColor: passColor,
      warnColor: warnColor,
      failColor: failColor,
      leadingIcon: leadingIcon,
      trailingWidget: trailingWidget,
      headerBuilder: headerBuilder,
      caseRowBuilder: caseRowBuilder,
      metricChipBuilder: metricChipBuilder,
    );
  }

  /// Creates an [AdkMultiRunEvalCard] from persisted [core.MultiRunCaseSummary] models.
  factory AdkMultiRunEvalCard.fromCoreSummaries({
    Key? key,
    required List<core.MultiRunCaseSummary> summaries,
    List<core.EvalCaseResult>? evalCaseResults,
    String title = 'Multi-Run Evaluation Summary',
    AdkCardStyle? style,
    Color? passColor,
    Color? warnColor,
    Color? failColor,
    Widget? leadingIcon,
    Widget? trailingWidget,
    Widget Function(
      BuildContext context,
      int passedCases,
      int totalCases,
      double passRate,
    )? headerBuilder,
    Widget Function(BuildContext context, AdkMultiRunCaseSummary summary)?
        caseRowBuilder,
    Widget Function(BuildContext context, AdkMultiRunMetricSummary metric)?
        metricChipBuilder,
  }) {
    return AdkMultiRunEvalCard(
      key: key,
      title: title,
      caseSummaries: summaries
          .map(
            (core.MultiRunCaseSummary s) => AdkMultiRunCaseSummary.fromCoreSummary(
              s,
              runs: evalCaseResults,
            ),
          )
          .toList(growable: false),
      style: style,
      passColor: passColor,
      warnColor: warnColor,
      failColor: failColor,
      leadingIcon: leadingIcon,
      trailingWidget: trailingWidget,
      headerBuilder: headerBuilder,
      caseRowBuilder: caseRowBuilder,
      metricChipBuilder: metricChipBuilder,
    );
  }

  /// Creates an [AdkMultiRunEvalCard] from a stored [core.EvalSetResult], using
  /// persisted [core.EvalSetResult.multiRunCaseSummaries] when available and
  /// falling back to aggregating [core.EvalSetResult.evalCaseResults].
  factory AdkMultiRunEvalCard.fromEvalSetResult({
    Key? key,
    required core.EvalSetResult evalSetResult,
    core.MultiRunConfig? multiRunConfig,
    String title = 'Multi-Run Evaluation Summary',
    AdkCardStyle? style,
    Color? passColor,
    Color? warnColor,
    Color? failColor,
    Widget? leadingIcon,
    Widget? trailingWidget,
    Widget Function(
      BuildContext context,
      int passedCases,
      int totalCases,
      double passRate,
    )? headerBuilder,
    Widget Function(BuildContext context, AdkMultiRunCaseSummary summary)?
        caseRowBuilder,
    Widget Function(BuildContext context, AdkMultiRunMetricSummary metric)?
        metricChipBuilder,
  }) {
    final List<core.MultiRunCaseSummary>? persisted =
        evalSetResult.multiRunCaseSummaries;
    if (persisted != null && persisted.isNotEmpty) {
      return AdkMultiRunEvalCard.fromCoreSummaries(
        key: key,
        summaries: persisted,
        evalCaseResults: evalSetResult.evalCaseResults,
        title: title,
        style: style,
        passColor: passColor,
        warnColor: warnColor,
        failColor: failColor,
        leadingIcon: leadingIcon,
        trailingWidget: trailingWidget,
        headerBuilder: headerBuilder,
        caseRowBuilder: caseRowBuilder,
        metricChipBuilder: metricChipBuilder,
      );
    }
    return AdkMultiRunEvalCard.fromCoreResults(
      key: key,
      results: core.aggregateEvalCaseResults(
        evalSetResult.evalCaseResults,
        multiRunConfig: multiRunConfig,
      ),
      title: title,
      style: style,
      passColor: passColor,
      warnColor: warnColor,
      failColor: failColor,
      leadingIcon: leadingIcon,
      trailingWidget: trailingWidget,
      headerBuilder: headerBuilder,
      caseRowBuilder: caseRowBuilder,
      metricChipBuilder: metricChipBuilder,
    );
  }

  /// Multi-run case summaries to visualize.
  final List<AdkMultiRunCaseSummary> caseSummaries;

  /// Title displayed in the card header.
  final String title;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Color used when pass rate is 80% or above.
  final Color? passColor;

  /// Color used when pass rate is between 50% and 79%.
  final Color? warnColor;

  /// Color used when pass rate is below 50%.
  final Color? failColor;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    int passedCases,
    int totalCases,
    double passRate,
  )? headerBuilder;

  /// Optional custom builder for each [AdkMultiRunCaseSummary] row.
  final Widget Function(BuildContext context, AdkMultiRunCaseSummary summary)?
      caseRowBuilder;

  /// Optional custom builder for each [AdkMultiRunMetricSummary] chip.
  final Widget Function(BuildContext context, AdkMultiRunMetricSummary metric)?
      metricChipBuilder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(style) ?? style;
    final int totalCases = caseSummaries.length;
    final int passedCases =
        caseSummaries.where((AdkMultiRunCaseSummary c) => c.passed).length;
    final double passRate = totalCases > 0 ? passedCases / totalCases : 0.0;
    final int passPercent = (passRate * 100).round();
    final Color statusColor = passRate >= 0.8
        ? (passColor ?? Colors.green.shade600)
        : (passRate >= 0.5
            ? (warnColor ?? Colors.orange.shade700)
            : (failColor ?? theme.colorScheme.error));
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(12.0);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
      padding: effectiveStyle?.padding ?? const EdgeInsets.all(14.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ?? theme.colorScheme.surface,
            borderRadius: radius,
            border: Border.all(
              color: effectiveStyle?.borderColor ??
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (headerBuilder != null)
            headerBuilder!(context, passedCases, totalCases, passRate)
          else
            Row(
              children: <Widget>[
                leadingIcon ??
                    Icon(
                      Icons.fact_check_outlined,
                      size: 18.0,
                      color: statusColor,
                    ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    title,
                    style: effectiveStyle?.titleStyle ??
                        theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: effectiveStyle?.textColor,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 3.0,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    '$passedCases/$totalCases cases ($passPercent%)',
                    style: effectiveStyle?.subtitleStyle ??
                        theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                  ),
                ),
                if (trailingWidget != null) ...<Widget>[
                  const SizedBox(width: 6.0),
                  trailingWidget!,
                ],
              ],
            ),
          if (caseSummaries.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12.0),
            ...caseSummaries.map(
              (AdkMultiRunCaseSummary item) => caseRowBuilder != null
                  ? caseRowBuilder!(context, item)
                  : _buildCaseRow(context, theme, effectiveStyle, item),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCaseRow(
    BuildContext context,
    ThemeData theme,
    AdkCardStyle? effectiveStyle,
    AdkMultiRunCaseSummary item,
  ) {
    final bool hasStrip =
        item.runStatusStrip != null && item.runStatusStrip!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                item.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
                size: 14.0,
                color: item.passed
                    ? (passColor ?? Colors.green.shade600)
                    : (failColor ?? theme.colorScheme.error),
              ),
              const SizedBox(width: 6.0),
              Expanded(
                child: Text(
                  item.evalId,
                  style: effectiveStyle?.titleStyle ??
                      theme.textTheme.labelMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: effectiveStyle?.textColor,
                      ),
                ),
              ),
              Text(
                '${item.passedRuns}/${item.totalRuns} runs passed',
                style: effectiveStyle?.subtitleStyle ??
                    theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 3.0),
          Wrap(
            spacing: 6.0,
            runSpacing: 4.0,
            children: <Widget>[
              if (hasStrip)
                _buildInfoBadge(
                  theme: theme,
                  label: 'Runs: ${item.runStatusStrip}',
                ),
              _buildInfoBadge(
                theme: theme,
                label: item.formattedPassRateLabel,
              ),
              if (item.crashedRuns > 0)
                _buildInfoBadge(
                  theme: theme,
                  label: '${item.crashedRuns} crashed',
                  isWarning: true,
                ),
              if (item.notEvaluatedRuns > 0)
                _buildInfoBadge(
                  theme: theme,
                  label: '${item.notEvaluatedRuns} not evaluated',
                ),
              for (final AdkMultiRunCriterionSummary criterion
                  in item.crossRunCriteria)
                _buildInfoBadge(
                  theme: theme,
                  label: criterion.formattedSummary,
                  isWarning: !criterion.passed,
                ),
            ],
          ),
          if (item.metrics.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: item.metrics.map((AdkMultiRunMetricSummary m) {
                if (metricChipBuilder != null) {
                  return metricChipBuilder!(context, m);
                }
                final String valStr = m.value != null
                    ? m.value!.toStringAsFixed(2)
                    : 'N/A';
                final String statusSuffix = m.isInformational ? ' [INFO]' : '';
                final String? runsStrip = m.formattedRunScoresStrip;
                final String runsSuffix =
                    runsStrip != null ? ' ($runsStrip)' : '';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: m.isInformational
                        ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.6)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  child: Text(
                    '${m.metricName} (${m.displayMethodName}): $valStr$statusSuffix$runsSuffix',
                    style: effectiveStyle?.codeStyle ??
                        theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                        ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoBadge({
    required ThemeData theme,
    required String label,
    bool isWarning = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: isWarning
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.7)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(5.0),
        border: Border.all(
          color: isWarning
              ? theme.colorScheme.error.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 10.0,
          color: isWarning
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
