import 'package:flutter/material.dart';

/// A horizontal scrollable bar of suggestion chips that users can tap to quickly send prompts.
class AdkPromptSuggestionsBar extends StatelessWidget {
  /// Creates an [AdkPromptSuggestionsBar].
  const AdkPromptSuggestionsBar({
    super.key,
    required this.suggestions,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
    this.chipColor,
    this.textColor,
    this.icon,
  });

  /// The list of suggestion prompt strings.
  final List<String> suggestions;

  /// Callback invoked when a suggestion chip is tapped.
  final ValueChanged<String> onSelected;

  /// Padding around the suggestions bar.
  final EdgeInsetsGeometry padding;

  /// Custom background color for the chips.
  final Color? chipColor;

  /// Custom text color for the chip labels.
  final Color? textColor;

  /// Optional leading icon displayed on each chip.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);

    return Container(
      padding: padding,
      height: 48.0,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8.0),
        itemBuilder: (BuildContext context, int index) {
          final String prompt = suggestions[index];
          return ActionChip(
            avatar: icon != null
                ? Icon(
                    icon,
                    size: 16.0,
                    color: textColor ?? theme.colorScheme.primary,
                  )
                : null,
            label: Text(
              prompt,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor ?? theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: chipColor ??
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18.0),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            onPressed: () => onSelected(prompt),
          );
        },
      ),
    );
  }
}
