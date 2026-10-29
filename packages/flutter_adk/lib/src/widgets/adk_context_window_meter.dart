import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';
import '../utils/adk_ui_utils.dart';

/// A progress bar meter widget that displays context window token utilization and compaction thresholds.
class AdkContextWindowMeter extends StatelessWidget {
  /// Creates an [AdkContextWindowMeter].
  const AdkContextWindowMeter({
    super.key,
    required this.usedTokens,
    this.maxContextTokens = 128000,
    this.compactionThresholdTokens,
    this.compact = false,
    this.onCompactPressed,
    this.label = 'Context Window',
    this.style,
    this.normalColor,
    this.warningColor,
    this.criticalColor,
    this.thresholdMarkerColor,
    this.barHeight,
    this.leadingIcon,
    this.trailingWidget,
    this.progressBuilder,
  });

  /// Current number of tokens occupying the context window.
  final int usedTokens;

  /// Maximum token capacity of the active model's context window.
  final int maxContextTokens;

  /// Optional token threshold at which `EventsCompactionConfig` triggers automatic context compaction.
  final int? compactionThresholdTokens;

  /// Whether to render a single-line compact bar suitable for app bar headers.
  final bool compact;

  /// Optional callback invoked when the user taps the manual compact button.
  final VoidCallback? onCompactPressed;

  /// Label displayed on the meter header when [compact] is false.
  final String label;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Color used when utilization is below 75%.
  final Color? normalColor;

  /// Color used when utilization is between 75% and 89%.
  final Color? warningColor;

  /// Color used when utilization is 90% or above.
  final Color? criticalColor;

  /// Color of the compaction threshold vertical marker line.
  final Color? thresholdMarkerColor;

  /// Height of the progress bar indicator.
  final double? barHeight;

  /// Optional custom leading icon widget replacing the memory icon.
  final Widget? leadingIcon;

  /// Optional custom trailing widget displayed on the header row.
  final Widget? trailingWidget;

  /// Optional custom builder to override the progress bar widget.
  final Widget Function(
    BuildContext context,
    double utilization,
    Color activeColor,
  )? progressBuilder;

  /// Ratio of [usedTokens] to [maxContextTokens] clamped between `0.0` and `1.0`.
  double get utilization => maxContextTokens > 0
      ? (usedTokens / maxContextTokens).clamp(0.0, 1.0)
      : 0.0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).contextMeterStyle?.merge(style) ??
        AdkTheme.of(context).cardStyle?.merge(style) ??
        style;
    final double ratio = utilization;
    final int percent = (ratio * 100).round();

    final Color barColor;
    if (ratio >= 0.9) {
      barColor = criticalColor ?? theme.colorScheme.error;
    } else if (ratio >= 0.75) {
      barColor = warningColor ?? Colors.orange.shade700;
    } else {
      barColor =
          normalColor ?? effectiveStyle?.accentColor ?? theme.colorScheme.primary;
    }

    final String summaryText =
        '${AdkFormatters.formatTokens(usedTokens, compact: true)} / ${AdkFormatters.formatTokens(maxContextTokens, compact: true)} ($percent%)';

    if (compact) {
      final BorderRadius compactRadius =
          effectiveStyle?.borderRadius ?? BorderRadius.circular(12.0);
      return Tooltip(
        message: '$label: $summaryText'
            '${compactionThresholdTokens != null ? '\nCompaction threshold: ${AdkFormatters.formatTokens(compactionThresholdTokens!, compact: true)}' : ''}',
        child: Container(
          margin: effectiveStyle?.margin,
          padding: effectiveStyle?.padding ??
              const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
          decoration: effectiveStyle?.decoration ??
              BoxDecoration(
                color: effectiveStyle?.backgroundColor ??
                    theme.colorScheme.surfaceContainerLow,
                borderRadius: compactRadius,
                border: Border.all(
                  color: effectiveStyle?.borderColor ??
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              leadingIcon ??
                  Icon(Icons.memory_rounded, size: 13.0, color: barColor),
              const SizedBox(width: 6.0),
              SizedBox(
                width: 56.0,
                child: progressBuilder != null
                    ? progressBuilder!(context, ratio, barColor)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(3.0),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: barHeight ?? 5.0,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
              ),
              const SizedBox(width: 6.0),
              Text(
                '$percent%',
                style: effectiveStyle?.subtitleStyle ??
                    theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: barColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (trailingWidget != null) ...<Widget>[
                const SizedBox(width: 4.0),
                trailingWidget!,
              ],
            ],
          ),
        ),
      );
    }

    final BorderRadius fullRadius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      padding: effectiveStyle?.padding ??
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ??
                theme.colorScheme.surfaceContainerLow,
            borderRadius: fullRadius,
            border: Border.all(
              color: effectiveStyle?.borderColor ??
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              leadingIcon ??
                  Icon(Icons.memory_rounded, size: 15.0, color: barColor),
              const SizedBox(width: 6.0),
              Text(
                label,
                style: effectiveStyle?.titleStyle ??
                    theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: effectiveStyle?.textColor,
                    ),
              ),
              const Spacer(),
              Text(
                summaryText,
                style: effectiveStyle?.subtitleStyle ??
                    theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: barColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (trailingWidget != null) ...<Widget>[
                const SizedBox(width: 6.0),
                trailingWidget!,
              ],
              if (onCompactPressed != null) ...<Widget>[
                const SizedBox(width: 8.0),
                InkWell(
                  onTap: onCompactPressed,
                  borderRadius: BorderRadius.circular(6.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6.0,
                      vertical: 2.0,
                    ),
                    child: Text(
                      'Compact',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6.0),
          if (progressBuilder != null)
            progressBuilder!(context, ratio, barColor)
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double? thresholdRatio =
                    compactionThresholdTokens != null && maxContextTokens > 0
                        ? (compactionThresholdTokens! / maxContextTokens)
                            .clamp(0.0, 1.0)
                        : null;
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.0),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: barHeight ?? 6.0,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                    if (thresholdRatio != null && constraints.maxWidth.isFinite)
                      Positioned(
                        left: (constraints.maxWidth * thresholdRatio)
                            .clamp(0.0, constraints.maxWidth - 2.0),
                        top: -2.0,
                        bottom: -2.0,
                        child: Tooltip(
                          message:
                              'Compaction threshold: ${AdkFormatters.formatTokens(compactionThresholdTokens!)}',
                          child: Container(
                            width: 2.0,
                            color: thresholdMarkerColor ??
                                theme.colorScheme.tertiary,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
