import 'dart:convert';
import 'package:flutter/material.dart';

/// A card widget displayed in the chat stream when an agent requests user
/// authorization or confirmation for an action (Human-in-the-Loop checkpoint).
class AdkHumanInTheLoopCard extends StatelessWidget {
  /// Creates an [AdkHumanInTheLoopCard].
  const AdkHumanInTheLoopCard({
    super.key,
    required this.toolName,
    this.actionDescription,
    this.arguments,
    this.onApprove,
    this.onReject,
    this.onModify,
    this.isProcessing = false,
    this.decision,
    this.approveLabel = 'Approve',
    this.rejectLabel = 'Reject',
    this.modifyLabel = 'Modify',
    this.warningMessage,
  });

  /// The name of the tool or action being confirmed.
  final String toolName;

  /// High-level description of what the tool will do.
  final String? actionDescription;

  /// Map of parameters / arguments to be passed to the tool.
  final Map<String, dynamic>? arguments;

  /// Callback when user approves the action.
  final VoidCallback? onApprove;

  /// Callback when user rejects the action.
  final VoidCallback? onReject;

  /// Callback when user wants to modify arguments before proceeding.
  final VoidCallback? onModify;

  /// Whether the approval or rejection is currently being processed.
  final bool isProcessing;

  /// Already finalized decision if resolved ('approved', 'rejected', etc.).
  final String? decision;

  /// Custom label for the approve button.
  final String approveLabel;

  /// Custom label for the reject button.
  final String rejectLabel;

  /// Custom label for the modify button.
  final String modifyLabel;

  /// Optional security or risk warning (e.g. 'Irreversible operation').
  final String? warningMessage;

  String _formatJson(Map<String, dynamic> data) {
    try {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isResolved = decision != null;
    final bool isApproved = decision?.toLowerCase() == 'approved';

    final Color headerColor = isResolved
        ? (isApproved ? theme.colorScheme.primary : theme.colorScheme.error)
        : theme.colorScheme.error;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.0),
        side: BorderSide(
          color: headerColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Header Row
            Row(
              children: <Widget>[
                Icon(
                  isResolved
                      ? (isApproved ? Icons.check_circle_outline : Icons.cancel_outlined)
                      : Icons.gavel_rounded,
                  color: headerColor,
                  size: 20.0,
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    isResolved
                        ? 'Action ${isApproved ? "Approved" : "Rejected"}'
                        : 'Approval Required: $toolName',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isResolved)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: headerColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      decision!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: headerColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8.0),

            // Action Description or Warning
            if (actionDescription != null && actionDescription!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Text(
                  actionDescription!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            if (warningMessage != null && warningMessage!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8.0),
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16.0,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        warningMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Arguments preview
            if (arguments != null && arguments!.isNotEmpty) ...<Widget>[
              Text(
                'Parameters:',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4.0),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: SelectableText(
                  _formatJson(arguments!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(height: 12.0),
            ],

            // Action Buttons
            if (!isResolved)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (onModify != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: TextButton.icon(
                        icon: const Icon(Icons.edit_outlined, size: 16.0),
                        label: Text(modifyLabel),
                        onPressed: isProcessing ? null : onModify,
                      ),
                    ),
                  if (onReject != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 16.0),
                        label: Text(rejectLabel),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                          side: BorderSide(color: theme.colorScheme.error),
                        ),
                        onPressed: isProcessing ? null : onReject,
                      ),
                    ),
                  if (onApprove != null)
                    FilledButton.icon(
                      icon: isProcessing
                          ? SizedBox(
                              width: 14.0,
                              height: 14.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.check, size: 16.0),
                      label: Text(approveLabel),
                      onPressed: isProcessing ? null : onApprove,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
