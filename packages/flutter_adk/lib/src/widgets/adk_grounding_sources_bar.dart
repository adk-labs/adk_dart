import 'package:flutter/material.dart';

import '../models/adk_chat_message.dart';
import '../theme/adk_theme.dart';

/// Displays search grounding queries and cited web/document sources for a
/// grounded model response.
class AdkGroundingSourcesBar extends StatelessWidget {
  /// Creates an [AdkGroundingSourcesBar].
  const AdkGroundingSourcesBar({
    super.key,
    required this.grounding,
    this.onSourceTap,
    this.style,
    this.searchIcon,
    this.queryChipBuilder,
    this.sourceChipBuilder,
  });

  /// Grounding queries and citation sources to render.
  final AdkGroundingInfo grounding;

  /// Optional callback invoked when a user taps a citation source chip.
  final void Function(AdkGroundingSource source)? onSourceTap;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Optional custom search icon widget displayed next to search queries.
  final Widget? searchIcon;

  /// Optional custom builder for individual search query chips.
  final Widget Function(BuildContext context, String query)? queryChipBuilder;

  /// Optional custom builder for individual [AdkGroundingSource] citation chips.
  final Widget Function(
    BuildContext context,
    int index,
    AdkGroundingSource source,
  )? sourceChipBuilder;

  @override
  Widget build(BuildContext context) {
    if (grounding.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(style) ?? style;
    return Padding(
      padding: effectiveStyle?.padding ?? const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (grounding.searchQueries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Wrap(
                spacing: 6.0,
                runSpacing: 4.0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  searchIcon ??
                      Icon(
                        Icons.manage_search,
                        size: 14.0,
                        color: effectiveStyle?.accentColor ??
                            theme.colorScheme.onSurfaceVariant,
                      ),
                  for (final String query in grounding.searchQueries)
                    if (queryChipBuilder != null)
                      queryChipBuilder!(context, query)
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: effectiveStyle?.backgroundColor ??
                              theme.colorScheme.surfaceContainerHigh,
                          borderRadius: effectiveStyle?.borderRadius ??
                              BorderRadius.circular(12.0),
                        ),
                        child: Text(
                          query,
                          style: effectiveStyle?.subtitleStyle ??
                              theme.textTheme.labelSmall?.copyWith(
                                color: effectiveStyle?.textColor ??
                                    theme.colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                ],
              ),
            ),
          if (grounding.sources.isNotEmpty)
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0,
              children: <Widget>[
                for (int i = 0; i < grounding.sources.length; i += 1)
                  if (sourceChipBuilder != null)
                    sourceChipBuilder!(context, i + 1, grounding.sources[i])
                  else
                    _buildSourceChip(
                      context,
                      theme,
                      effectiveStyle,
                      i + 1,
                      grounding.sources[i],
                    ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(
    BuildContext context,
    ThemeData theme,
    AdkCardStyle? effectiveStyle,
    int index,
    AdkGroundingSource source,
  ) {
    final String label = source.title.trim().isNotEmpty
        ? source.title.trim()
        : source.uri;
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(14.0);
    return InkWell(
      onTap: onSourceTap != null ? () => onSourceTap!(source) : null,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: effectiveStyle?.backgroundColor ??
              theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: radius,
          border: Border.all(
            color: effectiveStyle?.borderColor ??
                theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.0),
              decoration: BoxDecoration(
                color: (effectiveStyle?.accentColor ??
                        theme.colorScheme.primary)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                '$index',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10.0,
                  fontWeight: FontWeight.bold,
                  color: effectiveStyle?.accentColor ??
                      theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 5.0),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180.0),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: effectiveStyle?.titleStyle ??
                    theme.textTheme.labelSmall?.copyWith(
                      color: effectiveStyle?.textColor ??
                          theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            const SizedBox(width: 4.0),
            Icon(
              Icons.open_in_new,
              size: 11.0,
              color: theme.colorScheme.onSecondaryContainer
                  .withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
