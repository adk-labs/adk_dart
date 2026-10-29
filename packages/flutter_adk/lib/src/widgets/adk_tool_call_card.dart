import 'dart:convert';
import 'package:flutter/material.dart';

import '../theme/adk_theme.dart';

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
    this.style,
    this.leadingIcon,
    this.trailingWidget,
    this.headerBuilder,
    this.argsBuilder,
    this.resultBuilder,
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

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom trailing widget in the header.
  final Widget? trailingWidget;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    String toolName,
    bool isRunning,
    bool hasError,
    bool isExpanded,
    VoidCallback onToggle,
  )? headerBuilder;

  /// Optional custom builder to render [toolArgs].
  final Widget Function(BuildContext context, Map<String, dynamic> args)?
      argsBuilder;

  /// Optional custom builder to render [toolResult].
  final Widget Function(BuildContext context, dynamic result)? resultBuilder;

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

  void _toggle() => setState(() => _expanded = !_expanded);

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
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).cardStyle?.merge(widget.style) ?? widget.style;
    final bool hasError = widget.errorMessage != null;

    final Color statusColor = widget.isRunning
        ? (effectiveStyle?.accentColor ?? theme.colorScheme.primary)
        : (hasError
            ? theme.colorScheme.error
            : (effectiveStyle?.accentColor ?? theme.colorScheme.tertiary));
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(12.0);

    return Card(
      elevation: effectiveStyle?.elevation ?? 0,
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      color: effectiveStyle?.backgroundColor ??
          theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: hasError
              ? theme.colorScheme.error.withValues(alpha: 0.4)
              : (effectiveStyle?.borderColor ??
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.headerBuilder != null)
            widget.headerBuilder!(
              context,
              widget.toolName,
              widget.isRunning,
              hasError,
              _expanded,
              _toggle,
            )
          else
            InkWell(
              borderRadius: radius,
              onTap: _toggle,
              child: Container(
                color: effectiveStyle?.headerBackgroundColor,
                padding: effectiveStyle?.padding ??
                    const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 10.0,
                    ),
                child: Row(
                  children: <Widget>[
                    if (widget.leadingIcon != null)
                      widget.leadingIcon!
                    else if (widget.isRunning)
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
                        hasError
                            ? Icons.error_outline
                            : Icons.build_circle_outlined,
                        size: 18.0,
                        color: statusColor,
                      ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        'Tool: ${widget.toolName}',
                        style: effectiveStyle?.titleStyle ??
                            theme.textTheme.titleSmall?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: effectiveStyle?.textColor ??
                                  theme.colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (widget.trailingWidget != null) ...<Widget>[
                      widget.trailingWidget!,
                      const SizedBox(width: 4.0),
                    ],
                    Text(
                      widget.isRunning
                          ? 'Running...'
                          : (hasError ? 'Failed' : 'Success'),
                      style: effectiveStyle?.subtitleStyle ??
                          theme.textTheme.labelSmall?.copyWith(
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
              padding: effectiveStyle?.padding ?? const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.toolArgs != null &&
                      widget.toolArgs!.isNotEmpty) ...<Widget>[
                    if (widget.argsBuilder != null)
                      widget.argsBuilder!(context, widget.toolArgs!)
                    else ...<Widget>[
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
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: SelectableText(
                          _formatJson(widget.toolArgs),
                          style: effectiveStyle?.codeStyle ??
                              theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 11.0,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8.0),
                  ],
                  if (widget.toolResult != null) ...<Widget>[
                    if (widget.resultBuilder != null)
                      widget.resultBuilder!(context, widget.toolResult)
                    else ...<Widget>[
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
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: SelectableText(
                          _formatJson(widget.toolResult),
                          style: effectiveStyle?.codeStyle ??
                              theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 11.0,
                              ),
                        ),
                      ),
                    ],
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
