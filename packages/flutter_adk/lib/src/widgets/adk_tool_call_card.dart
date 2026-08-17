import 'dart:convert';
import 'package:flutter/material.dart';

/// An expandable card widget displaying tool execution arguments, progress, and results.
class AdkToolCallCard extends StatefulWidget {
  /// Creates an [AdkToolCallCard].
  const AdkToolCallCard({
    super.key,
    required this.toolName,
    this.toolArgs,
    this.toolResult,
    this.isRunning = false,
    this.errorMessage,
    this.initiallyExpanded = false,
  });

  /// The name of the tool called.
  final String toolName;

  /// The arguments map passed to the tool.
  final Map<String, dynamic>? toolArgs;

  /// The result returned by the tool, if completed.
  final dynamic toolResult;

  /// Whether the tool is currently executing.
  final bool isRunning;

  /// Optional error message if the tool failed.
  final String? errorMessage;

  /// Whether the card is initially expanded.
  final bool initiallyExpanded;

  @override
  State<AdkToolCallCard> createState() => _AdkToolCallCardState();
}

class _AdkToolCallCardState extends State<AdkToolCallCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  String _formatJson(dynamic value) {
    if (value == null) return 'null';
    try {
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasError = widget.errorMessage != null;

    final Color statusColor = widget.isRunning
        ? theme.colorScheme.primary
        : (hasError ? theme.colorScheme.error : theme.colorScheme.tertiary);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(
          color: hasError
              ? theme.colorScheme.error.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(12.0),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Row(
                children: <Widget>[
                  if (widget.isRunning)
                    SizedBox(
                      width: 16.0,
                      height: 16.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        color: statusColor,
                      ),
                    )
                  else
                    Icon(
                      hasError ? Icons.error_outline : Icons.build_circle_outlined,
                      size: 18.0,
                      color: statusColor,
                    ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      'Tool: ${widget.toolName}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    widget.isRunning
                        ? 'Running...'
                        : (hasError ? 'Failed' : 'Success'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4.0),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20.0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...<Widget>[
            const Divider(height: 1.0),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.toolArgs != null && widget.toolArgs!.isNotEmpty) ...<Widget>[
                    Text(
                      'Arguments:',
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
                        _formatJson(widget.toolArgs),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8.0),
                  ],
                  if (widget.toolResult != null) ...<Widget>[
                    Text(
                      'Result:',
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
                        _formatJson(widget.toolResult),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11.0,
                        ),
                      ),
                    ),
                  ],
                  if (hasError) ...<Widget>[
                    Text(
                      'Error: ${widget.errorMessage}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
