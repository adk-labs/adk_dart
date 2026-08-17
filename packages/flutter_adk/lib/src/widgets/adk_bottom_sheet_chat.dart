import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

import '../controllers/adk_chat_controller.dart';
import '../models/adk_chat_message.dart';
import '../theme/adk_theme.dart';
import 'adk_chat_view.dart';

/// Opens a turnkey ADK AI Assistant in a modal draggable bottom sheet.
Future<T?> showAdkChatBottomSheet<T>({
  required BuildContext context,
  adk.BaseAgent? agent,
  adk.Runner? runner,
  AdkChatController? controller,
  AdkChatThemeData? theme,
  String title = 'AI Assistant',
  String? subtitle,
  String inputPlaceholder = 'Ask something...',
  List<String>? suggestions,
  double initialChildSize = 0.85,
  double minChildSize = 0.5,
  double maxChildSize = 0.95,
  bool isDismissible = true,
  bool enableDrag = true,
  Widget? header,
  Widget Function(BuildContext context, AdkChatMessage message)? avatarBuilder,
  Widget Function(BuildContext context, AdkChatMessage message)? messageBubbleBuilder,
  Widget Function(BuildContext context, TextEditingController controller, VoidCallback onSend, bool isLoading)? inputBarBuilder,
  Widget Function(BuildContext context)? emptyStateBuilder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      return AdkBottomSheetChat(
        agent: agent,
        runner: runner,
        controller: controller,
        theme: theme,
        title: title,
        subtitle: subtitle,
        inputPlaceholder: inputPlaceholder,
        suggestions: suggestions,
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        header: header,
        avatarBuilder: avatarBuilder,
        messageBubbleBuilder: messageBubbleBuilder,
        inputBarBuilder: inputBarBuilder,
        emptyStateBuilder: emptyStateBuilder,
      );
    },
  );
}

/// A modal bottom sheet widget hosting an interactive ADK chat interface.
class AdkBottomSheetChat extends StatelessWidget {
  /// Creates an [AdkBottomSheetChat].
  const AdkBottomSheetChat({
    super.key,
    this.agent,
    this.runner,
    this.controller,
    this.theme,
    this.title = 'AI Assistant',
    this.subtitle,
    this.inputPlaceholder = 'Ask something...',
    this.suggestions,
    this.initialChildSize = 0.85,
    this.minChildSize = 0.5,
    this.maxChildSize = 0.95,
    this.header,
    this.avatarBuilder,
    this.messageBubbleBuilder,
    this.inputBarBuilder,
    this.emptyStateBuilder,
  });

  /// Agent to run.
  final adk.BaseAgent? agent;

  /// Runner to run.
  final adk.Runner? runner;

  /// Preconfigured chat controller.
  final AdkChatController? controller;

  /// Optional theme styling configuration.
  final AdkChatThemeData? theme;

  /// Header title label.
  final String title;

  /// Optional subtitle underneath title.
  final String? subtitle;

  /// Input placeholder text.
  final String inputPlaceholder;

  /// Quick prompt suggestions.
  final List<String>? suggestions;

  /// Initial sheet height ratio (0.0 to 1.0).
  final double initialChildSize;

  /// Minimum sheet height ratio.
  final double minChildSize;

  /// Maximum sheet height ratio.
  final double maxChildSize;

  /// Optional custom top header widget.
  final Widget? header;

  /// Custom avatar builder.
  final Widget Function(BuildContext context, AdkChatMessage message)? avatarBuilder;

  /// Custom message bubble builder.
  final Widget Function(BuildContext context, AdkChatMessage message)? messageBubbleBuilder;

  /// Custom input bar builder.
  final Widget Function(BuildContext context, TextEditingController controller, VoidCallback onSend, bool isLoading)? inputBarBuilder;

  /// Custom empty state builder.
  final Widget Function(BuildContext context)? emptyStateBuilder;

  @override
  Widget build(BuildContext context) {
    final ThemeData flutterTheme = Theme.of(context);
    final AdkChatThemeData adkTheme = theme ?? AdkTheme.of(context);

    final Color sheetBg = adkTheme.backgroundColor ?? flutterTheme.colorScheme.surface;

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10.0,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                  width: 36.0,
                  height: 4.0,
                  decoration: BoxDecoration(
                    color: flutterTheme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
              ),
              // Top Bar / Header
              if (header != null)
                header!
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                  child: Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 16.0,
                        backgroundColor: flutterTheme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.smart_toy_outlined,
                          size: 18.0,
                          color: flutterTheme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              title,
                              style: flutterTheme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: flutterTheme.textTheme.bodySmall?.copyWith(
                                  color: flutterTheme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1.0),
              // Main Chat Area
              Expanded(
                child: AdkChatView(
                  agent: agent,
                  runner: runner,
                  controller: controller,
                  theme: adkTheme,
                  inputPlaceholder: inputPlaceholder,
                  suggestions: suggestions,
                  avatarBuilder: avatarBuilder,
                  messageBubbleBuilder: messageBubbleBuilder,
                  inputBarBuilder: inputBarBuilder,
                  emptyStateBuilder: emptyStateBuilder,
                  showAppBar: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
