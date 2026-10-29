import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

/// A status banner widget that surfaces self-healing reflection and retry attempts from `ReflectAndRetryToolPlugin` or `ReflectAndRetryModelPlugin`.
class AdkReflectRetryBanner extends StatelessWidget {
  /// Creates an [AdkReflectRetryBanner].
  const AdkReflectRetryBanner({
    super.key,
    required this.attempt,
    this.maxRetries = 3,
    this.targetName,
    this.errorSummary,
    this.isModelRetry = false,
    this.style,
    this.leadingIcon,
    this.attemptBadgeBuilder,
    this.contentBuilder,
  });

  /// Current 1-based retry attempt number.
  final int attempt;

  /// Maximum configured retry attempts.
  final int maxRetries;

  /// Optional tool or model name that triggered the reflection retry.
  final String? targetName;

  /// Optional error message or reflection guidance summary.
  final String? errorSummary;

  /// Whether this retry originated from `ReflectAndRetryModelPlugin` rather than a tool call.
  final bool isModelRetry;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Optional custom leading icon widget.
  final Widget? leadingIcon;

  /// Optional custom builder for the `Attempt N/M` badge.
  final Widget Function(BuildContext context, int attempt, int maxRetries)?
      attemptBadgeBuilder;

  /// Optional custom builder to replace the entire banner content.
  final Widget Function(
    BuildContext context,
    int attempt,
    int maxRetries,
    String? targetName,
    String? errorSummary,
  )? contentBuilder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(style) ?? style;
    final Color accent = effectiveStyle?.accentColor ?? Colors.amber.shade800;
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
      padding: effectiveStyle?.padding ??
          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ??
                Colors.amber.withValues(alpha: 0.12),
            borderRadius: radius,
            border: Border.all(
              color:
                  effectiveStyle?.borderColor ?? accent.withValues(alpha: 0.45),
            ),
          ),
      child: contentBuilder != null
          ? contentBuilder!(
              context,
              attempt,
              maxRetries,
              targetName,
              errorSummary,
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                leadingIcon ??
                    Icon(
                      Icons.autorenew_rounded,
                      size: 16.0,
                      color: accent,
                    ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              isModelRetry
                                  ? 'Model Self-Reflection Retry${targetName != null ? ' ($targetName)' : ''}'
                                  : 'Tool Self-Healing Retry${targetName != null ? ': $targetName' : ''}',
                              style: effectiveStyle?.titleStyle ??
                                  theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: effectiveStyle?.textColor ?? accent,
                                  ),
                            ),
                          ),
                          if (attemptBadgeBuilder != null)
                            attemptBadgeBuilder!(context, attempt, maxRetries)
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: Text(
                                'Attempt $attempt/$maxRetries',
                                style: effectiveStyle?.subtitleStyle ??
                                    theme.textTheme.labelSmall?.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                              ),
                            ),
                        ],
                      ),
                      if (errorSummary != null &&
                          errorSummary!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4.0),
                        Text(
                          errorSummary!,
                          style: effectiveStyle?.codeStyle ??
                              theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: effectiveStyle?.textColor ??
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
