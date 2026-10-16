import 'package:flutter/material.dart';

/// A card widget displaying the decision, confidence score, and probability
/// distribution breakdown produced by an ADK `ClassifierNode`.
class AdkClassifierCard extends StatelessWidget {
  /// Creates an [AdkClassifierCard].
  const AdkClassifierCard({
    super.key,
    required this.selectedRoute,
    this.question,
    this.confidence,
    this.probabilities = const <String, double>{},
    this.title = 'Workflow Classification',
    this.onRouteSelected,
  });

  /// The route selected by the classifier (e.g. `'technical_support'`).
  final String selectedRoute;

  /// The classification prompt or instructions.
  final String? question;

  /// Overall confidence score in `[0.0, 1.0]`.
  final double? confidence;

  /// Probabilities assigned to each candidate route option.
  final Map<String, double> probabilities;

  /// Header title for the card.
  final String title;

  /// Optional callback when a route option is tapped.
  final void Function(String route)? onRouteSelected;

  Color _confidenceColor(ThemeData theme, double? score) {
    if (score == null) return theme.colorScheme.primary;
    if (score >= 0.8) return Colors.green.shade600;
    if (score >= 0.5) return Colors.orange.shade700;
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final String confidenceText = confidence != null
        ? '${(confidence! * 100).toStringAsFixed(1)}%'
        : 'N/A';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.0),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14.0,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.alt_route_rounded,
                    size: 16.0,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (confidence != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: _confidenceColor(theme, confidence).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Text(
                      'Confidence: $confidenceText',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _confidenceColor(theme, confidence),
                      ),
                    ),
                  ),
              ],
            ),
            if (question != null && question!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8.0),
              Text(
                question!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
            const SizedBox(height: 12.0),
            Row(
              children: <Widget>[
                Text(
                  'Selected Route: ',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: Text(selectedRoute),
                  avatar: const Icon(Icons.check_circle_rounded, size: 16.0),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            if (probabilities.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12.0),
              Text(
                'Candidate Probabilities:',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6.0),
              ...probabilities.entries.map((MapEntry<String, double> entry) {
                final bool isSelected = entry.key == selectedRoute;
                final double prob = entry.value.clamp(0.0, 1.0);
                final String percentLabel = '${(prob * 100).toStringAsFixed(1)}%';

                return InkWell(
                  onTap: () => onRouteSelected?.call(entry.key),
                  borderRadius: BorderRadius.circular(6.0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              entry.key,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight:
                                    isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected
                                    ? colorScheme.primary
                                    : theme.textTheme.bodySmall?.color,
                              ),
                            ),
                            Text(
                              percentLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? colorScheme.primary
                                    : theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2.0),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3.0),
                          child: LinearProgressIndicator(
                            value: prob,
                            minHeight: 6.0,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isSelected ? colorScheme.primary : colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
