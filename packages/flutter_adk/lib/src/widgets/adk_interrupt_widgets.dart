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
    this.backgroundColor,
    this.foregroundColor,
    this.icon,
    this.borderRadius,
    this.padding,
    this.margin,
    this.actionBuilder,
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

  /// Custom background color for the banner container.
  final Color? backgroundColor;

  /// Custom text and icon foreground color.
  final Color? foregroundColor;

  /// Custom leading icon.
  final IconData? icon;

  /// Custom border radius for the banner container.
  final BorderRadius? borderRadius;

  /// Custom padding inside the banner container.
  final EdgeInsetsGeometry? padding;

  /// Custom margin around the banner container.
  final EdgeInsetsGeometry? margin;

  /// Custom builder for the action area.
  final Widget Function(BuildContext context, VoidCallback? onResume)? actionBuilder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final Color effectiveBg = backgroundColor ?? colorScheme.errorContainer.withValues(alpha: 0.85);
    final Color effectiveFg = foregroundColor ?? colorScheme.onErrorContainer;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: borderRadius ?? BorderRadius.circular(12.0),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            icon ?? Icons.pause_circle_filled_rounded,
            color: effectiveFg,
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
                    color: effectiveFg,
                  ),
                ),
                if (reason != null && reason!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2.0),
                  Text(
                    reason!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: effectiveFg.withValues(alpha: 0.9),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actionBuilder != null)
            actionBuilder!(context, onResume)
          else if (onResume != null) ...<Widget>[
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
              color: effectiveFg,
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
    this.cardElevation = 2.0,
    this.borderRadius,
    this.accentColor,
    this.headerBuilder,
    this.actionsBuilder,
    this.inputDecoration,
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

  /// Elevation of the card.
  final double cardElevation;

  /// Corner border radius.
  final BorderRadius? borderRadius;

  /// Accent highlight color.
  final Color? accentColor;

  /// Custom builder for the header section.
  final Widget Function(BuildContext context)? headerBuilder;

  /// Custom builder for action buttons.
  final Widget Function(
    BuildContext context,
    void Function(String? val)? onResume,
    VoidCallback? onCancel,
    bool isProcessing,
  )? actionsBuilder;

  /// Custom decoration for the input field.
  final InputDecoration? inputDecoration;

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
      elevation: widget.cardElevation,
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(14.0),
        side: BorderSide(
          color: (widget.accentColor ?? colorScheme.error).withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.headerBuilder != null)
              widget.headerBuilder!(context)
            else
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 16.0,
                    backgroundColor: (widget.accentColor ?? colorScheme.error).withValues(alpha: 0.15),
                    child: Icon(
                      Icons.security_update_warning_rounded,
                      color: widget.accentColor ?? colorScheme.error,
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
                decoration: widget.inputDecoration ??
                    InputDecoration(
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
            if (widget.actionsBuilder != null)
              widget.actionsBuilder!(
                context,
                widget.onResume != null
                    ? (String? val) {
                        widget.onResume?.call(
                          widget.requiresInput ? (val ?? _inputController.text.trim()) : null,
                        );
                      }
                    : null,
                widget.onCancel,
                widget.isProcessing,
              )
            else
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
