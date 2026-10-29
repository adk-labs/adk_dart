import 'package:adk_dart/adk_dart.dart' as core;
import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

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
    this.note,
  });

  /// Name of the evaluated metric.
  final String metricName;

  /// Aggregation method name (for example `'mean_over_invocations'`, `'mean_of_runs'`, `'min_over_runs'`).
  final String methodName;

  /// Aggregated score value, if evaluated.
  final double? value;

  /// Configured pass threshold, if any.
  final double? threshold;

  /// Whether this aggregated metric passed its threshold.
  final bool passed;

  /// Optional human-readable breakdown note.
  final String? note;
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
    this.metrics = const <AdkMultiRunMetricSummary>[],
  });

  /// Converts an ADK [core.MultiRunCaseResult] into an [AdkMultiRunCaseSummary].
  factory AdkMultiRunCaseSummary.fromCore(core.MultiRunCaseResult result) {
    final int total = result.runs.length;
    final int passedCount = result.runs
        .where(
          (core.EvalCaseResult r) =>
              core.getRunStatus(r) == core.EvalStatus.passed,
        )
        .length;
    return AdkMultiRunCaseSummary(
      evalId: result.evalId,
      totalRuns: total,
      passedRuns: passedCount,
      passed: result.finalEvalStatus == core.EvalStatus.passed,
      metrics: result.metricMethods.entries.map((
        MapEntry<String, core.MethodResult> e,
      ) {
        return AdkMultiRunMetricSummary(
          metricName: e.key,
          methodName: e.value.name,
          value: e.value.value,
          threshold: e.value.threshold,
          passed: e.value.status == core.EvalStatus.passed,
          note: e.value.note,
        );
      }).toList(),
    );
  }

  /// Evaluation case identifier.
  final String evalId;

  /// Total number of repetition runs executed for this case.
  final int totalRuns;

  /// Number of repetition runs that passed all metrics.
  final int passedRuns;

  /// Whether the case passed overall cross-run evaluation criteria.
  final bool passed;

  /// Per-metric aggregated results for this case.
  final List<AdkMultiRunMetricSummary> metrics;

  /// Pass rate across runs in the range `0.0` to `1.0`.
  double get passRate => totalRuns > 0 ? passedRuns / totalRuns : 0.0;
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
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6.0,
                    vertical: 2.0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  child: Text(
                    '${m.metricName} (${m.methodName}): $valStr',
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
}
