import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/adk_chat_message.dart';

/// Card widget that displays an agent's [AdkCodeExecution] snippet and its
/// standard output or error result.
///
/// ```dart
/// const AdkCodeExecutionCard(
///   execution: AdkCodeExecution(
///     language: 'PYTHON',
///     code: 'print(6 * 7)',
///     output: '42\n',
///     outcome: 'OUTCOME_OK',
///   ),
/// )
/// ```
class AdkCodeExecutionCard extends StatefulWidget {
  /// Creates an [AdkCodeExecutionCard].
  const AdkCodeExecutionCard({
    super.key,
    required this.execution,
    this.initiallyExpanded = true,
  });

  /// Code execution payload to render.
  final AdkCodeExecution execution;

  /// Whether the code and output panels start expanded.
  final bool initiallyExpanded;

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
    final AdkCodeExecution exec = widget.execution;
    final bool hasOutput = exec.output != null && exec.output!.trim().isNotEmpty;
    final bool isOk = exec.isSuccess;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10.0)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.terminal,
                    size: 16.0,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      exec.language.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      'Code Execution',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (exec.outcome != null && exec.outcome!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: SelectableText(
                  exec.code.trimRight(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            if (hasOutput)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: isOk
                      ? theme.colorScheme.surfaceContainer
                      : theme.colorScheme.errorContainer.withValues(alpha: 0.25),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(10.0),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                      style: theme.textTheme.bodySmall?.copyWith(
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
