import 'package:flutter/material.dart';

/// A Human-in-the-Loop (HITL) confirmation banner displayed inline when an agent
/// requests user permission before executing an action.
class AdkConfirmationBanner extends StatelessWidget {
  /// Creates an [AdkConfirmationBanner].
  const AdkConfirmationBanner({
    super.key,
    required this.title,
    required this.description,
    required this.onConfirm,
    required this.onDeny,
    this.confirmLabel = 'Allow',
    this.denyLabel = 'Deny',
    this.toolName,
  });

  /// Title of the confirmation prompt.
  final String title;

  /// Description or reason for the requested action.
  final String description;

  /// Callback when the user confirms/allows the action.
  final VoidCallback onConfirm;

  /// Callback when the user denies/rejects the action.
  final VoidCallback onDeny;

  /// Label for the confirmation button.
  final String confirmLabel;

  /// Label for the denial button.
  final String denyLabel;

  /// Name of the sensitive tool requesting permission, if any.
  final String? toolName;

  /// Shows an alert dialog version of the confirmation prompt.
  static Future<bool?> showAsDialog(
    BuildContext context, {
    required String title,
    required String description,
    String? toolName,
    String confirmLabel = 'Allow',
    String denyLabel = 'Deny',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return AlertDialog(
          icon: Icon(
            Icons.shield_outlined,
            size: 36.0,
            color: theme.colorScheme.primary,
          ),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (toolName != null) ...<Widget>[
                Chip(
                  avatar: const Icon(Icons.build, size: 14.0),
                  label: Text(
                    'Tool: $toolName',
                    style: const TextStyle(fontSize: 12.0, fontFamily: 'monospace'),
                  ),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                const SizedBox(height: 8.0),
              ],
              Text(description),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(denyLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.security_rounded,
                size: 20.0,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (toolName != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                  child: Text(
                    toolName!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8.0),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 12.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              OutlinedButton(
                onPressed: onDeny,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(denyLabel),
              ),
              const SizedBox(width: 8.0),
              FilledButton(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
