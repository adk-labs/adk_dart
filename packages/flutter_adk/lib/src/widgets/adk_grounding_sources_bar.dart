import 'package:flutter/material.dart';

import '../models/adk_chat_message.dart';

/// Displays search grounding queries and cited web/document sources for a
/// grounded model response.
///
/// ```dart
/// const AdkGroundingSourcesBar(
///   grounding: AdkGroundingInfo(
///     searchQueries: ['google adk dart'],
///     sources: [
///       AdkGroundingSource(
///         title: 'ADK Documentation',
///         uri: 'https://google.github.io/adk-docs/',
///       ),
///     ],
///   ),
/// )
/// ```
class AdkGroundingSourcesBar extends StatelessWidget {
  /// Creates an [AdkGroundingSourcesBar].
  const AdkGroundingSourcesBar({
    super.key,
    required this.grounding,
    this.onSourceTap,
  });

  /// Grounding queries and citation sources to render.
  final AdkGroundingInfo grounding;

  /// Optional callback invoked when a user taps a citation source chip.
  final void Function(AdkGroundingSource source)? onSourceTap;

  @override
  Widget build(BuildContext context) {
    if (grounding.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
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
                  Icon(
                    Icons.manage_search,
                    size: 14.0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  for (final String query in grounding.searchQueries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 2.0,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Text(
                        query,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
                  _buildSourceChip(context, theme, i + 1, grounding.sources[i]),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(
    BuildContext context,
    ThemeData theme,
    int index,
    AdkGroundingSource source,
  ) {
    final String label = source.title.trim().isNotEmpty
        ? source.title.trim()
        : source.uri;
    return InkWell(
      onTap: onSourceTap != null ? () => onSourceTap!(source) : null,
      borderRadius: BorderRadius.circular(14.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14.0),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Text(
                '$index',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10.0,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4.0),
            Icon(
              Icons.open_in_new,
              size: 11.0,
              color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
