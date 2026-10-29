import 'package:flutter/material.dart';

import '../models/adk_token_usage_model.dart';
import '../theme/adk_theme.dart';
import '../utils/adk_ui_utils.dart';

/// A dashboard card widget that visualizes token consumption breakdown, cache efficiency, and estimated cost.
class AdkUsageMonitorCard extends StatelessWidget {
  /// Creates an [AdkUsageMonitorCard].
  const AdkUsageMonitorCard({
    super.key,
    required this.usage,
    this.title = 'Token Usage & Cost',
    this.modelName,
    this.turnCount,
    this.inputPricePerMillion = 0.15,
    this.outputPricePerMillion = 0.60,
    this.cachedInputPricePerMillion = 0.0375,
    this.showCostEstimate = true,
    this.onReset,
    this.style,
    this.promptColor,
    this.cachedColor,
    this.completionColor,
    this.thoughtColor,
    this.leadingIcon,
    this.trailingWidget,
    this.headerBuilder,
    this.kpiBuilder,
    this.barBuilder,
    this.legendBuilder,
  });

  /// Token usage metrics to display.
  final AdkTokenUsage usage;

  /// Header title of the monitor card.
  final String title;

  /// Optional model identifier displayed as a subtitle badge.
  final String? modelName;

  /// Optional number of model turns included in [usage].
  final int? turnCount;

  /// Price in USD per 1M uncached input tokens.
  final double inputPricePerMillion;

  /// Price in USD per 1M output and thought tokens.
  final double outputPricePerMillion;

  /// Price in USD per 1M cached input tokens.
  final double cachedInputPricePerMillion;

  /// Whether to compute and display the estimated USD cost.
  final bool showCostEstimate;

  /// Optional callback invoked when the reset button is pressed.
  final VoidCallback? onReset;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Custom color for uncached prompt tokens in the stacked bar and legend.
  final Color? promptColor;

  /// Custom color for cached tokens in the stacked bar and legend.
  final Color? cachedColor;

  /// Custom color for output completion tokens in the stacked bar and legend.
  final Color? completionColor;

  /// Custom color for reasoning thought tokens in the stacked bar and legend.
  final Color? thoughtColor;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder to replace the header row.
  final Widget Function(BuildContext context, AdkTokenUsage usage)?
      headerBuilder;

  /// Optional custom builder to replace the KPI summary row.
  final Widget Function(
    BuildContext context,
    AdkTokenUsage usage,
    double estimatedCostUsd,
  )? kpiBuilder;

  /// Optional custom builder to replace the proportional stacked bar.
  final Widget Function(BuildContext context, AdkTokenUsage usage)? barBuilder;

  /// Optional custom builder to replace the legend wrap row.
  final Widget Function(BuildContext context, AdkTokenUsage usage)?
      legendBuilder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).usageBadgeStyle?.merge(style) ??
        AdkTheme.of(context).cardStyle?.merge(style) ??
        style;
    final int total = usage.effectiveTotalTokens;
    final int uncachedPrompt =
        (usage.promptTokens - usage.cachedTokens).clamp(0, usage.promptTokens);
    final double costUsd = usage.estimateCostUsd(
      inputPricePerMillion: inputPricePerMillion,
      outputPricePerMillion: outputPricePerMillion,
      cachedInputPricePerMillion: cachedInputPricePerMillion,
    );

    final Color effectivePromptColor =
        promptColor ?? effectiveStyle?.accentColor ?? theme.colorScheme.primary;
    final Color effectiveCachedColor = cachedColor ?? Colors.amber.shade700;
    final Color effectiveCompletionColor =
        completionColor ?? Colors.teal.shade600;
    final Color effectiveThoughtColor =
        thoughtColor ?? Colors.deepPurple.shade400;
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
            headerBuilder!(context, usage)
          else
            Row(
              children: <Widget>[
                leadingIcon ??
                    Icon(
                      Icons.analytics_outlined,
                      size: 18.0,
                      color: effectiveStyle?.accentColor ??
                          theme.colorScheme.primary,
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
                if (modelName != null && modelName!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 2.0,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Text(
                      modelName!,
                      style: effectiveStyle?.subtitleStyle ??
                          theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                    ),
                  ),
                if (trailingWidget != null) ...<Widget>[
                  const SizedBox(width: 4.0),
                  trailingWidget!,
                ],
                if (onReset != null) ...<Widget>[
                  const SizedBox(width: 4.0),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16.0),
                    tooltip: 'Reset usage counters',
                    visualDensity: VisualDensity.compact,
                    onPressed: onReset,
                  ),
                ],
              ],
            ),
          const SizedBox(height: 12.0),
          if (kpiBuilder != null)
            kpiBuilder!(context, usage, costUsd)
          else
            Row(
              children: <Widget>[
                _buildSummaryKpi(
                  theme,
                  effectiveStyle,
                  label: 'Total Tokens',
                  value: AdkFormatters.formatTokens(total, compact: true),
                  subvalue: '$total tok',
                ),
                if (showCostEstimate)
                  _buildSummaryKpi(
                    theme,
                    effectiveStyle,
                    label: 'Est. Cost',
                    value: _formatUsd(costUsd),
                    subvalue: turnCount != null && turnCount! > 0
                        ? '$turnCount turns'
                        : 'Session',
                  ),
                if (usage.cachedTokens > 0)
                  _buildSummaryKpi(
                    theme,
                    effectiveStyle,
                    label: 'Cache Hit',
                    value:
                        '${(usage.cacheHitRatio * 100).toStringAsFixed(0)}%',
                    subvalue:
                        '${AdkFormatters.formatTokens(usage.cachedTokens, compact: true)} cached',
                  ),
                if (usage.latencyMs != null)
                  _buildSummaryKpi(
                    theme,
                    effectiveStyle,
                    label: 'Latency',
                    value: AdkFormatters.formatDuration(
                      Duration(milliseconds: usage.latencyMs!),
                    ),
                    subvalue: usage.trafficType ?? 'Cumulative',
                  ),
              ],
            ),
          const SizedBox(height: 12.0),
          if (barBuilder != null)
            barBuilder!(context, usage)
          else
            _buildStackedBar(
              theme,
              total: total,
              uncachedPrompt: uncachedPrompt,
              cached: usage.cachedTokens,
              completion: usage.completionTokens,
              thought: usage.thoughtTokens,
              promptColor: effectivePromptColor,
              cachedColor: effectiveCachedColor,
              completionColor: effectiveCompletionColor,
              thoughtColor: effectiveThoughtColor,
            ),
          const SizedBox(height: 10.0),
          if (legendBuilder != null)
            legendBuilder!(context, usage)
          else
            Wrap(
              spacing: 12.0,
              runSpacing: 6.0,
              children: <Widget>[
                _buildLegendDot(
                  theme,
                  effectiveStyle,
                  color: effectivePromptColor,
                  label: 'Prompt',
                  tokens: uncachedPrompt,
                ),
                if (usage.cachedTokens > 0)
                  _buildLegendDot(
                    theme,
                    effectiveStyle,
                    color: effectiveCachedColor,
                    label: 'Cached',
                    tokens: usage.cachedTokens,
                  ),
                _buildLegendDot(
                  theme,
                  effectiveStyle,
                  color: effectiveCompletionColor,
                  label: 'Output',
                  tokens: usage.completionTokens,
                ),
                if (usage.thoughtTokens > 0)
                  _buildLegendDot(
                    theme,
                    effectiveStyle,
                    color: effectiveThoughtColor,
                    label: 'Thoughts',
                    tokens: usage.thoughtTokens,
                  ),
                if (usage.toolUsePromptTokens > 0)
                  _buildLegendDot(
                    theme,
                    effectiveStyle,
                    color: theme.colorScheme.tertiary,
                    label: 'Tool Prompt',
                    tokens: usage.toolUsePromptTokens,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryKpi(
    ThemeData theme,
    AdkCardStyle? effectiveStyle, {
    required String label,
    required String value,
    required String subvalue,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: effectiveStyle?.subtitleStyle ??
                theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2.0),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: effectiveStyle?.textColor,
            ),
          ),
          Text(
            subvalue,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.0,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedBar(
    ThemeData theme, {
    required int total,
    required int uncachedPrompt,
    required int cached,
    required int completion,
    required int thought,
    required Color promptColor,
    required Color cachedColor,
    required Color completionColor,
    required Color thoughtColor,
  }) {
    if (total <= 0) {
      return Container(
        height: 8.0,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4.0),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4.0),
      child: SizedBox(
        height: 8.0,
        child: Row(
          children: <Widget>[
            if (uncachedPrompt > 0)
              Expanded(
                flex: uncachedPrompt,
                child: ColoredBox(color: promptColor),
              ),
            if (cached > 0)
              Expanded(
                flex: cached,
                child: ColoredBox(color: cachedColor),
              ),
            if (completion > 0)
              Expanded(
                flex: completion,
                child: ColoredBox(color: completionColor),
              ),
            if (thought > 0)
              Expanded(
                flex: thought,
                child: ColoredBox(color: thoughtColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendDot(
    ThemeData theme,
    AdkCardStyle? effectiveStyle, {
    required Color color,
    required String label,
    required int tokens,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8.0,
          height: 8.0,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4.0),
        Text(
          '$label: ${AdkFormatters.formatTokens(tokens, compact: true)}',
          style: effectiveStyle?.codeStyle ??
              theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: effectiveStyle?.textColor ??
                    theme.colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  String _formatUsd(double cost) {
    if (cost <= 0) {
      return r'$0.0000';
    }
    if (cost < 0.01) {
      return '\$${cost.toStringAsFixed(4)}';
    }
    return '\$${cost.toStringAsFixed(3)}';
  }
}
