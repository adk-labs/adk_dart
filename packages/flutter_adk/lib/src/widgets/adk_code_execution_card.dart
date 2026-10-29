import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/adk_chat_message.dart';
import '../theme/adk_theme.dart';

/// Card widget that displays an agent's [AdkCodeExecution] snippet and its
/// standard output or error result.
class AdkCodeExecutionCard extends StatefulWidget {
  /// Creates an [AdkCodeExecutionCard].
  const AdkCodeExecutionCard({
    super.key,
    required this.execution,
    this.initiallyExpanded = true,
    this.title = 'Code Execution',
    this.style,
    this.leadingIcon,
    this.headerBuilder,
    this.codeBuilder,
    this.outputBuilder,
  });

  /// Code execution payload to render.
  final AdkCodeExecution execution;

  /// Whether the code and output panels start expanded.
  final bool initiallyExpanded;

  /// Header title label.
  final String title;

  /// Optional style configuration overriding theme defaults.
  final AdkCardStyle? style;

  /// Optional custom leading icon widget in the header.
  final Widget? leadingIcon;

  /// Optional custom builder to replace the header row.
  final Widget Function(
    BuildContext context,
    AdkCodeExecution execution,
    bool isExpanded,
    VoidCallback onToggle,
  )? headerBuilder;

  /// Optional custom builder to render the source code panel.
  final Widget Function(BuildContext context, String language, String code)?
      codeBuilder;

  /// Optional custom builder to render the execution output panel.
  final Widget Function(
    BuildContext context,
    String output,
    bool isSuccess,
  )? outputBuilder;

  @override
  State<AdkCodeExecutionCard> createState() => _AdkCodeExecutionCardState();
}

class _AdkCodeExecutionCardState extends State<AdkCodeExecutionCard> {
  late bool _isExpanded;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _toggle() => setState(() => _isExpanded = !_isExpanded);

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.execution.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AdkCardStyle? effectiveStyle =
        AdkTheme.of(context).terminalCardStyle?.merge(widget.style) ??
        AdkTheme.of(context).cardStyle?.merge(widget.style) ??
        widget.style;
    final AdkCodeExecution exec = widget.execution;
    final bool hasOutput =
        exec.output != null && exec.output!.trim().isNotEmpty;
    final bool isOk = exec.isSuccess;
    final BorderRadius radius =
        effectiveStyle?.borderRadius ?? BorderRadius.circular(10.0);

    return Container(
      margin: effectiveStyle?.margin ??
          const EdgeInsets.symmetric(vertical: 4.0),
      decoration: effectiveStyle?.decoration ??
          BoxDecoration(
            color: effectiveStyle?.backgroundColor ??
                theme.colorScheme.surfaceContainerLow,
            borderRadius: radius,
            border: Border.all(
              color: effectiveStyle?.borderColor ??
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.headerBuilder != null)
            widget.headerBuilder!(context, exec, _isExpanded, _toggle)
          else
            InkWell(
              onTap: _toggle,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10.0),
              ),
              child: Container(
                color: effectiveStyle?.headerBackgroundColor,
                padding: effectiveStyle?.padding ??
                    const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: 8.0,
                    ),
                child: Row(
                  children: <Widget>[
                    widget.leadingIcon ??
                        Icon(
                          Icons.terminal,
                          size: 16.0,
                          color: effectiveStyle?.accentColor ??
                              theme.colorScheme.primary,
                        ),
                    const SizedBox(width: 6.0),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6.0,
                        vertical: 2.0,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        exec.language.toUpperCase(),
                        style: effectiveStyle?.subtitleStyle ??
                            theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: effectiveStyle?.titleStyle ??
                            theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: effectiveStyle?.textColor,
                            ),
                      ),
                    ),
                    if (exec.outcome != null && exec.outcome!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: isOk
                              ? Colors.green.withValues(alpha: 0.15)
                              : theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          isOk ? 'OK' : exec.outcome!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10.0,
                            fontWeight: FontWeight.bold,
                            color: isOk
                                ? Colors.green.shade700
                                : theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    if (exec.code.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 15.0,
                        ),
                        tooltip: _copied ? 'Copied' : 'Copy code',
                        visualDensity: VisualDensity.compact,
                        onPressed: _copyCode,
                      ),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18.0,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          if (_isExpanded) ...<Widget>[
            if (exec.code.isNotEmpty)
              if (widget.codeBuilder != null)
                widget.codeBuilder!(context, exec.language, exec.code)
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: SelectableText(
                    exec.code.trimRight(),
                    style: effectiveStyle?.codeStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                  ),
                ),
            if (hasOutput)
              if (widget.outputBuilder != null)
                widget.outputBuilder!(context, exec.output!, isOk)
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: isOk
                        ? theme.colorScheme.surfaceContainer
                        : theme.colorScheme.errorContainer
                            .withValues(alpha: 0.25),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(10.0),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Output',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      SelectableText(
                        exec.output!.trimRight(),
                        style: effectiveStyle?.codeStyle ??
                            theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
