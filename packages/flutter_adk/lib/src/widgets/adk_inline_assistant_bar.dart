import 'dart:async';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Data model representing a quick inline action in [AdkInlineAssistantBar].
@immutable
class AdkInlineAction {
  /// Creates an [AdkInlineAction].
  const AdkInlineAction({
    required this.label,
    required this.promptPrefix,
    this.icon = Icons.auto_awesome,
  });

  /// Label shown on the action button/chip.
  final String label;

  /// Prompt sent to the agent before the input text (e.g. 'Rewrite more formally:').
  final String promptPrefix;

  /// Icon for this action.
  final IconData icon;

  /// Preset action to fix grammar and spelling.
  static const AdkInlineAction fixGrammar = AdkInlineAction(
    label: 'Fix Grammar',
    promptPrefix: 'Fix any grammar and spelling mistakes in the following text without changing its meaning:',
    icon: Icons.spellcheck,
  );

  /// Preset action to make text more polite and formal.
  static const AdkInlineAction makeFormal = AdkInlineAction(
    label: 'Make Formal',
    promptPrefix: 'Rewrite the following text in a professional, polite, and formal tone:',
    icon: Icons.business_center_outlined,
  );

  /// Preset action to summarize into 3 bullet points.
  static const AdkInlineAction summarize = AdkInlineAction(
    label: 'Summarize',
    promptPrefix: 'Summarize the following text into concise bullet points:',
    icon: Icons.short_text,
  );

  /// Preset action to translate to English.
  static const AdkInlineAction translateEn = AdkInlineAction(
    label: 'Translate to English',
    promptPrefix: 'Translate the following text to fluent English:',
    icon: Icons.translate,
  );
}

/// An inline Copilot toolbar placed above or below text inputs to run one-click AI refinements.
class AdkInlineAssistantBar extends StatefulWidget {
  /// Creates an [AdkInlineAssistantBar].
  const AdkInlineAssistantBar({
    super.key,
    required this.agent,
    this.targetController,
    this.currentText,
    this.onResultApplied,
    this.actions = const <AdkInlineAction>[
      AdkInlineAction.fixGrammar,
      AdkInlineAction.makeFormal,
      AdkInlineAction.summarize,
      AdkInlineAction.translateEn,
    ],
    this.showPreview = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
    this.actionBuilder,
  });

  /// Agent to perform refinements.
  final adk.BaseAgent agent;

  /// Target [TextEditingController] whose text will be analyzed and updated.
  final TextEditingController? targetController;

  /// Alternatively, explicit current text string.
  final String? currentText;

  /// Callback when the user accepts and applies the generated text.
  final ValueChanged<String>? onResultApplied;

  /// List of inline actions.
  final List<AdkInlineAction> actions;

  /// Whether to show an interactive preview card before replacing text.
  final bool showPreview;

  /// Padding around the action bar.
  final EdgeInsetsGeometry padding;

  /// Custom builder for action chips/buttons.
  final Widget Function(BuildContext context, AdkInlineAction action, bool isRunning, VoidCallback onTrigger)?
      actionBuilder;

  @override
  State<AdkInlineAssistantBar> createState() => _AdkInlineAssistantBarState();
}

class _AdkInlineAssistantBarState extends State<AdkInlineAssistantBar> {
  bool _isLoading = false;
  String? _generatedResult;
  String? _activeActionLabel;
  StreamSubscription<adk.Event>? _subscription;

  String _getTextToProcess() {
    if (widget.targetController != null) {
      return widget.targetController!.text.trim();
    }
    return widget.currentText?.trim() ?? '';
  }

  Future<void> _runAction(AdkInlineAction action) async {
    final String text = _getTextToProcess();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
      _activeActionLabel = action.label;
      _generatedResult = '';
    });

    final adk.Runner runner = adk.InMemoryRunner(agent: widget.agent);
    final String fullPrompt = '${action.promptPrefix}\n\n$text';

    try {
      final Stream<adk.Event> stream = runner.runAsync(
        userId: 'inline_user',
        sessionId: 'inline_session_${DateTime.now().millisecondsSinceEpoch}',
        newMessage: adk.Content.userText(fullPrompt),
      );

      final StringBuffer buffer = StringBuffer();
      await for (final adk.Event event in stream) {
        final content = event.content;
        if (content != null) {
          for (final part in content.parts) {
            if (part.text != null) {
              buffer.write(part.text);
              if (mounted) {
                setState(() {
                  _generatedResult = buffer.toString();
                });
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generatedResult = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyResult() {
    if (_generatedResult == null || _generatedResult!.isEmpty) return;

    if (widget.targetController != null) {
      widget.targetController!.text = _generatedResult!;
    }
    widget.onResultApplied?.call(_generatedResult!);

    setState(() {
      _generatedResult = null;
      _activeActionLabel = null;
    });
  }

  void _dismissPreview() {
    setState(() {
      _generatedResult = null;
      _activeActionLabel = null;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Action Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          child: Row(
            children: widget.actions.map((AdkInlineAction act) {
              final bool isRunningThis = _isLoading && _activeActionLabel == act.label;
              if (widget.actionBuilder != null) {
                return widget.actionBuilder!(
                  context,
                  act,
                  isRunningThis,
                  () => _runAction(act),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: ActionChip(
                  avatar: isRunningThis
                      ? SizedBox(
                          width: 14.0,
                          height: 14.0,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(act.icon, size: 16.0, color: theme.colorScheme.primary),
                  label: Text(act.label, style: const TextStyle(fontSize: 12.0)),
                  onPressed: _isLoading ? null : () => _runAction(act),
                ),
              );
            }).toList(),
          ),
        ),
        // Result Preview Card
        if (widget.showPreview && _generatedResult != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.auto_awesome, size: 16.0, color: theme.colorScheme.primary),
                    const SizedBox(width: 6.0),
                    Text(
                      'AI Suggestion (${_activeActionLabel ?? "Refined"})',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16.0),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _dismissPreview,
                    ),
                  ],
                ),
                const SizedBox(height: 6.0),
                SelectableText(
                  _generatedResult!,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                ),
                const SizedBox(height: 8.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 14.0),
                      label: const Text('Copy'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _generatedResult!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      },
                    ),
                    const SizedBox(width: 8.0),
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 14.0),
                      label: const Text('Apply'),
                      onPressed: _applyResult,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
