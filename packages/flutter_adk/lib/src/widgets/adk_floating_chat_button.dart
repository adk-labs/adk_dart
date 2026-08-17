import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

import '../controllers/adk_chat_controller.dart';
import 'adk_chat_view.dart';

/// A floating action button (FAB) that opens an [AdkChatView] in a modal bottom sheet.
class AdkFloatingChatButton extends StatelessWidget {
  /// Creates an [AdkFloatingChatButton].
  const AdkFloatingChatButton({
    super.key,
    this.controller,
    this.agent,
    this.runner,
    this.title = 'AI Assistant',
    this.icon = Icons.auto_awesome,
    this.tooltip = 'Chat with AI',
    this.bottomSheetHeightFactor = 0.85,
  }) : assert(
          controller != null || agent != null || runner != null,
          'AdkFloatingChatButton requires either a controller, an agent, or a runner.',
        );

  /// Controller managing the chat session.
  final AdkChatController? controller;

  /// Agent to invoke.
  final adk.BaseAgent? agent;

  /// Runner to execute.
  final adk.Runner? runner;

  /// Assistant title shown in the bottom sheet header.
  final String title;

  /// Icon displayed on the floating button.
  final IconData icon;

  /// Tooltip message.
  final String tooltip;

  /// Height ratio of the bottom sheet (0.0 - 1.0).
  final double bottomSheetHeightFactor;

  /// Opens the chat bottom sheet programmatically.
  static Future<void> showChatBottomSheet(
    BuildContext context, {
    AdkChatController? controller,
    adk.BaseAgent? agent,
    adk.Runner? runner,
    String title = 'AI Assistant',
    double heightFactor = 0.85,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return FractionallySizedBox(
          heightFactor: heightFactor,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
            ),
            child: Column(
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                  width: 36.0,
                  height: 4.0,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
                Expanded(
                  child: AdkChatView(
                    controller: controller,
                    agent: agent,
                    runner: runner,
                    title: title,
                    showAppBar: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      tooltip: tooltip,
      onPressed: () => showChatBottomSheet(
        context,
        controller: controller,
        agent: agent,
        runner: runner,
        title: title,
        heightFactor: bottomSheetHeightFactor,
      ),
      child: Icon(icon),
    );
  }
}
