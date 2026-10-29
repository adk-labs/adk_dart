import 'package:flutter/material.dart';

import '../models/adk_token_usage_model.dart';
import '../theme/adk_theme.dart';
import '../utils/adk_ui_utils.dart';

/// A compact chip badge widget displaying token usage metrics (prompt, candidate, thought, cached, and total tokens).
class AdkTokenUsageBadge extends StatelessWidget {
  /// Creates an [AdkTokenUsageBadge].
  const AdkTokenUsageBadge({
    super.key,
    required this.promptTokens,
    required this.candidatesTokens,
    this.totalTokens,
    this.thoughtTokens = 0,
    this.cachedTokens = 0,
    this.latencyMs,
    this.estimatedCost,
    this.compact = false,
    this.onTap,
    this.style,
    this.backgroundColor,
    this.borderColor,
    this.textStyle,
    this.costTextStyle,
    this.padding,
    this.borderRadius,
    this.icon,
    this.cachedIcon,
    this.contentBuilder,
  });

  /// Creates an [AdkTokenUsageBadge] directly from an [AdkTokenUsage] model.
  factory AdkTokenUsageBadge.fromUsage(
    AdkTokenUsage usage, {
    Key? key,
    String? estimatedCost,
    bool compact = false,
    VoidCallback? onTap,
    AdkCardStyle? style,
    Color? backgroundColor,
    Color? borderColor,
    TextStyle? textStyle,
    TextStyle? costTextStyle,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
    Widget? icon,
    Widget? cachedIcon,
    Widget Function(BuildContext context, int totalTokens, String formattedLabel)?
        contentBuilder,
  }) {
    return AdkTokenUsageBadge(
      key: key,
      promptTokens: usage.promptTokens,
      candidatesTokens: usage.completionTokens,
      totalTokens: usage.effectiveTotalTokens,
      thoughtTokens: usage.thoughtTokens,
      cachedTokens: usage.cachedTokens,
      latencyMs: usage.latencyMs,
      estimatedCost: estimatedCost,
      compact: compact,
      onTap: onTap,
      style: style,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      textStyle: textStyle,
      costTextStyle: costTextStyle,
      padding: padding,
      borderRadius: borderRadius,
      icon: icon,
      cachedIcon: cachedIcon,
      contentBuilder: contentBuilder,
    );
  }

  /// Number of input / prompt tokens consumed.
  final int promptTokens;

  /// Number of output / completion tokens generated.
  final int candidatesTokens;

  /// Total token count (computed as prompt + candidates + thoughts if null).
  final int? totalTokens;

  /// Number of reasoning / thought tokens consumed.
  final int thoughtTokens;

  /// Number of cached context tokens reused.
  final int cachedTokens;

  /// Optional generation latency in milliseconds.
  final int? latencyMs;

  /// Optional estimated cost in USD (for example `'$0.002'`).
  final String? estimatedCost;

  /// Whether to format numbers in compact `1.2k` style.
  final bool compact;

  /// Optional callback invoked when the badge is tapped.
  final VoidCallback? onTap;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Custom background color for the badge container.
  final Color? backgroundColor;

  /// Custom border color for the badge container.
  final Color? borderColor;

  /// Custom text style for the token count label.
  final TextStyle? textStyle;

  /// Custom text style for the estimated cost label.
  final TextStyle? costTextStyle;

  /// Custom padding inside the badge container.
  final EdgeInsetsGeometry? padding;

  /// Custom corner radius for the badge container.
  final BorderRadius? borderRadius;

  /// Optional custom leading icon widget replacing the default usage icon.
  final Widget? icon;

  /// Optional custom icon widget displayed when [cachedTokens] is greater than zero.
  final Widget? cachedIcon;

  /// Optional builder to override the badge content entirely.
  final Widget Function(
    BuildContext context,
    int totalTokens,
    String formattedLabel,
  )? contentBuilder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).usageBadgeStyle?.merge(style) ?? style;
    final int total =
        totalTokens ?? (promptTokens + candidatesTokens + thoughtTokens);

    final List<String> tooltipLines = <String>[
      'Prompt: $promptTokens tokens',
      'Response: $candidatesTokens tokens',
      if (thoughtTokens > 0) 'Thoughts: $thoughtTokens tokens',
      if (cachedTokens > 0) 'Cached: $cachedTokens tokens',
      'Total: $total tokens',
      if (latencyMs != null)
        'Latency: ${AdkFormatters.formatDuration(Duration(milliseconds: latencyMs!))}',
      if (estimatedCost != null) 'Est. Cost: $estimatedCost',
    ];

    final String label = compact
        ? '${AdkFormatters.formatTokens(total, compact: true)} tokens'
        : '$total tokens';

    final BorderRadius effectiveRadius =
        borderRadius ?? effectiveStyle?.borderRadius ?? BorderRadius.circular(12.0);
    final Color effectiveBg = backgroundColor ??
        effectiveStyle?.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final Color effectiveBorder = borderColor ??
        effectiveStyle?.borderColor ??
        theme.colorScheme.outlineVariant.withValues(alpha: 0.4);
    final Color fgColor =
        effectiveStyle?.textColor ?? theme.colorScheme.onSurfaceVariant;

    final Widget innerContent = contentBuilder != null
        ? contentBuilder!(context, total, label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              icon ??
                  Icon(
                    Icons.data_usage_rounded,
                    size: 13.0,
                    color: effectiveStyle?.accentColor ?? fgColor,
                  ),
              const SizedBox(width: 4.0),
              Text(
                label,
                style: textStyle ??
                    effectiveStyle?.titleStyle ??
                    theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: fgColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (cachedTokens > 0) ...<Widget>[
                const SizedBox(width: 4.0),
                cachedIcon ??
                    Icon(
                      Icons.bolt_rounded,
                      size: 12.0,
                      color: Colors.amber.shade700,
                    ),
              ],
              if (estimatedCost != null) ...<Widget>[
                const SizedBox(width: 6.0),
                Text(
                  estimatedCost!,
                  style: costTextStyle ??
                      effectiveStyle?.subtitleStyle ??
                      theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: effectiveStyle?.accentColor ??
                            theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          );

    final Widget chip = Container(
      margin: effectiveStyle?.margin,
      padding: padding ??
          effectiveStyle?.padding ??
          const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveBg,
            borderRadius: effectiveRadius,
            border: Border.all(color: effectiveBorder),
          ),
      child: innerContent,
    );

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: onTap != null
          ? InkWell(
              borderRadius: effectiveRadius,
              onTap: onTap,
              child: chip,
            )
          : chip,
    );
  }
}
