import 'dart:convert';
import 'package:flutter/material.dart';

/// A notification banner indicating that an ADK agent or workflow execution
/// is paused on a long-running tool interrupt waiting for user resolution.
class AdkInterruptBanner extends StatelessWidget {
  /// Creates an [AdkInterruptBanner].
  const AdkInterruptBanner({
    super.key,
    required this.toolName,
    this.reason,
    this.interruptId,
    this.onResume,
    this.onDismiss,
    this.actionLabel = 'Review & Resume',
  });

  /// Name of the tool or node that triggered the interrupt.
  final String toolName;

  /// High-level reason or prompt for the pause.
  final String? reason;

  /// Optional unique identifier of the interrupt.
  final String? interruptId;

  /// Callback when user clicks the resume action button.
  final VoidCallback? onResume;

  /// Callback when user dismisses the banner.
  final VoidCallback? onDismiss;

  /// Label for the action button.
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.pause_circle_filled_rounded,
            color: colorScheme.onErrorContainer,
            size: 24.0,
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Action Required: $toolName',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                if (reason != null && reason!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2.0),
                  Text(
                    reason!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer.withValues(alpha: 0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onResume != null) ...<Widget>[
            const SizedBox(width: 8.0),
            FilledButton.tonal(
              onPressed: onResume,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
              ),
              child: Text(actionLabel),
            ),
          ],
          if (onDismiss != null) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.close, size: 18.0),
              color: colorScheme.onErrorContainer,
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              tooltip: 'Dismiss banner',
            ),
          ],
        ],
      ),
    );
  }
}

/// An interactive card widget detailing a paused interrupt with argument previews
/// and resumption actions.
class AdkInterruptCard extends StatefulWidget {
  /// Creates an [AdkInterruptCard].
  const AdkInterruptCard({
    super.key,
    required this.toolName,
    this.interruptId,
    this.arguments,
    this.reason,
    this.requiresInput = false,
    this.inputPlaceholder = 'Enter required input...',
    this.isProcessing = false,
    this.onResume,
    this.onCancel,
  });

  /// The name of the tool causing the pause.
  final String toolName;

  /// Identifier of this interrupt.
  final String? interruptId;

  /// Parameter arguments passed to the tool call.
  final Map<String, dynamic>? arguments;

  /// Description or prompt explaining why the interrupt occurred.
  final String? reason;

  /// Whether user must provide text input before resuming.
  final bool requiresInput;

  /// Placeholder hint for the input field.
  final String inputPlaceholder;

  /// Whether resumption is actively processing.
  final bool isProcessing;

  /// Callback when user confirms or submits input to resume execution.
  final void Function(String? inputValue)? onResume;

  /// Callback when user cancels the paused operation.
  final VoidCallback? onCancel;

  @override
  State<AdkInterruptCard> createState() => _AdkInterruptCardState();
}

class _AdkInterruptCardState extends State<AdkInterruptCard> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  String _formatArguments(Map<String, dynamic> args) {
    try {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(args);
    } catch (_) {
      return args.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Card(
      elevation: 2.0,
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.0),
        side: BorderSide(
          color: colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 16.0,
                  backgroundColor: colorScheme.errorContainer,
                  child: Icon(
                    Icons.security_update_warning_rounded,
                    color: colorScheme.error,
                    size: 18.0,
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Tool Interrupted: ${widget.toolName}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.interruptId != null)
                        Text(
                          'ID: ${widget.interruptId}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    'Paused',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.reason != null && widget.reason!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12.0),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  widget.reason!,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
            if (widget.arguments != null && widget.arguments!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12.0),
              Text(
                'Parameters:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4.0),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: SelectableText(
                  _formatArguments(widget.arguments!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            if (widget.requiresInput) ...<Widget>[
              const SizedBox(height: 14.0),
              TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: widget.inputPlaceholder,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 10.0,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (widget.onCancel != null) ...<Widget>[
                  OutlinedButton(
                    onPressed: widget.isProcessing ? null : widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8.0),
                ],
                FilledButton.icon(
                  onPressed: widget.isProcessing
                      ? null
                      : () {
                          widget.onResume?.call(
                            widget.requiresInput ? _inputController.text.trim() : null,
                          );
                        },
                  icon: widget.isProcessing
                      ? const SizedBox(
                          width: 14.0,
                          height: 14.0,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18.0),
                  label: Text(widget.isProcessing ? 'Resuming...' : 'Resume'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
