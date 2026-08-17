import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

/// A horizontal scrollable bar of suggestion chips that users can tap to quickly send prompts.
class AdkPromptSuggestionsBar extends StatelessWidget {
  /// Creates an [AdkPromptSuggestionsBar].
  const AdkPromptSuggestionsBar({
    super.key,
    required this.suggestions,
    required this.onSelected,
    this.theme,
    this.padding = const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
    this.chipColor,
    this.textColor,
    this.borderRadius,
    this.icon,
    this.chipBuilder,
  });

  /// The list of suggestion prompt strings.
  final List<String> suggestions;

  /// Callback invoked when a suggestion chip is tapped.
  final ValueChanged<String> onSelected;

  /// Optional theme styling configuration.
  final AdkChatThemeData? theme;

  /// Padding around the suggestions bar.
  final EdgeInsetsGeometry padding;

  /// Custom background color for the chips.
  final Color? chipColor;

  /// Custom text color for the chip labels.
  final Color? textColor;

  /// Custom corner radius for chips.
  final BorderRadius? borderRadius;

  /// Optional leading icon displayed on each chip.
  final IconData? icon;

  /// Custom builder for individual chips.
  final Widget Function(BuildContext context, String suggestion, VoidCallback onSelect)?
      chipBuilder;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData flutterTheme = Theme.of(context);
    final AdkChatThemeData adkTheme = theme ?? AdkTheme.of(context);

    final Color effectiveChipColor = chipColor ??
        adkTheme.suggestionBackgroundColor ??
        flutterTheme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);

    final Color effectiveTextColor = textColor ??
        adkTheme.suggestionTextColor ??
        flutterTheme.colorScheme.onSurfaceVariant;

    final BorderRadius effectiveRadius = borderRadius ??
        adkTheme.suggestionBorderRadius ??
        BorderRadius.circular(18.0);

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

          if (chipBuilder != null) {
            return chipBuilder!(context, prompt, () => onSelected(prompt));
          }

          return ActionChip(
            avatar: icon != null
                ? Icon(
                    icon,
                    size: 16.0,
                    color: effectiveTextColor,
                  )
                : null,
            label: Text(
              prompt,
              style: flutterTheme.textTheme.bodySmall?.copyWith(
                color: effectiveTextColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: effectiveChipColor,
            shape: RoundedRectangleBorder(
              borderRadius: effectiveRadius,
              side: BorderSide(
                color: flutterTheme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            onPressed: () => onSelected(prompt),
          );
        },
      ),
    );
  }
}
