import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A collapsible/expandable accordion widget designed for displaying AI reasoning / thinking steps.
class AdkReasoningExpander extends StatefulWidget {
  /// Creates an [AdkReasoningExpander].
  const AdkReasoningExpander({
    super.key,
    required this.thought,
    this.title = 'Thinking Process',
    this.durationMs,
    this.initialExpanded = false,
    this.icon = Icons.psychology_outlined,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.customHeaderBuilder,
    this.customBodyBuilder,
  });

  /// The raw thought / reasoning text to display.
  final String thought;

  /// Header title label.
  final String title;

  /// Optional duration in milliseconds taken for reasoning.
  final int? durationMs;

  /// Whether the accordion is expanded initially.
  final bool initialExpanded;

  /// Leading icon for the reasoning card.
  final IconData icon;

  /// Custom background color.
  final Color? backgroundColor;

  /// Custom border color.
  final Color? borderColor;

  /// Custom text color.
  final Color? textColor;

  /// Optional builder to override the header row entirely.
  final Widget Function(BuildContext context, bool isExpanded, VoidCallback onToggle)?
      customHeaderBuilder;

  /// Optional builder to override the expanded reasoning body.
  final Widget Function(BuildContext context, String thought)? customBodyBuilder;

  @override
  State<AdkReasoningExpander> createState() => _AdkReasoningExpanderState();
}

class _AdkReasoningExpanderState extends State<AdkReasoningExpander> {
  late bool _isExpanded;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _copyThought() async {
    await Clipboard.setData(ClipboardData(text: widget.thought));
    if (mounted) {
      setState(() => _copied = true);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.thought.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData flutterTheme = Theme.of(context);

    final Color bgColor = widget.backgroundColor ??
        flutterTheme.colorScheme.surfaceContainerLow.withValues(alpha: 0.8);
    final Color lineBorderColor = widget.borderColor ??
        flutterTheme.colorScheme.outlineVariant.withValues(alpha: 0.4);
    final Color fgColor = widget.textColor ?? flutterTheme.colorScheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: lineBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.customHeaderBuilder != null)
            widget.customHeaderBuilder!(context, _isExpanded, _toggle)
          else
            InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(12.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                child: Row(
                  children: <Widget>[
                    Icon(widget.icon, size: 18.0, color: flutterTheme.colorScheme.primary),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          Text(
                            widget.title,
                            style: flutterTheme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: fgColor,
                            ),
                          ),
                          if (widget.durationMs != null) ...<Widget>[
                            const SizedBox(width: 6.0),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                              decoration: BoxDecoration(
                                color: flutterTheme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: Text(
                                '${(widget.durationMs! / 1000).toStringAsFixed(1)}s',
                                style: flutterTheme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10.0,
                                  color: fgColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 14.0,
                        color: _copied ? Colors.green : fgColor.withValues(alpha: 0.7),
                      ),
                      tooltip: 'Copy thought',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _copyThought,
                    ),
                    const SizedBox(width: 8.0),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 18.0,
                      color: fgColor,
                    ),
                  ],
                ),
              ),
            ),
          if (_isExpanded) ...<Widget>[
            Divider(height: 1.0, color: lineBorderColor),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: widget.customBodyBuilder != null
                  ? widget.customBodyBuilder!(context, widget.thought)
                  : SelectableText(
                      widget.thought,
                      style: flutterTheme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: fgColor.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
