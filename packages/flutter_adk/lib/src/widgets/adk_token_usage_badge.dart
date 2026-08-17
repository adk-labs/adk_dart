import 'package:flutter/material.dart';

/// A compact chip badge widget displaying token usage metrics (prompt, candidate, and total tokens).
class AdkTokenUsageBadge extends StatelessWidget {
  /// Creates an [AdkTokenUsageBadge].
  const AdkTokenUsageBadge({
    super.key,
    required this.promptTokens,
    required this.candidatesTokens,
    this.totalTokens,
    this.estimatedCost,
  });

  /// Number of input / prompt tokens consumed.
  final int promptTokens;

  /// Number of output / completion tokens generated.
  final int candidatesTokens;

  /// Total token count (computed as prompt + candidates if null).
  final int? totalTokens;

  /// Optional estimated cost in USD (e.g. `$0.002`).
  final String? estimatedCost;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int total = totalTokens ?? (promptTokens + candidatesTokens);

    return Tooltip(
      message: 'Prompt: $promptTokens tokens\nResponse: $candidatesTokens tokens'
          '${estimatedCost != null ? "\nEst. Cost: $estimatedCost" : ""}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.data_usage_rounded,
              size: 13.0,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4.0),
            Text(
              '$total tokens',
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
