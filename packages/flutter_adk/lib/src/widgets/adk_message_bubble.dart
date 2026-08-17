import 'package:flutter/material.dart';

import '../models/adk_chat_message.dart';
import 'adk_typing_indicator.dart';

/// A customizable message bubble widget representing user, model, tool, or system messages.
class AdkMessageBubble extends StatelessWidget {
  /// Creates an [AdkMessageBubble].
  const AdkMessageBubble({
    super.key,
    required this.message,
    this.userBubbleColor,
    this.modelBubbleColor,
    this.toolBubbleColor,
    this.userTextColor,
    this.modelTextColor,
    this.borderRadius,
  });

  /// The chat message to render.
  final AdkChatMessage message;

  /// Custom background color for user bubbles.
  final Color? userBubbleColor;

  /// Custom background color for model bubbles.
  final Color? modelBubbleColor;

  /// Custom background color for tool execution bubbles.
  final Color? toolBubbleColor;

  /// Custom text color for user bubbles.
  final Color? userTextColor;

  /// Custom text color for model bubbles.
  final Color? modelTextColor;

  /// Custom corner radius for the bubble container.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isUser = message.role == AdkMessageRole.user;
    final bool isTool = message.role == AdkMessageRole.tool;
    final bool isSystem = message.role == AdkMessageRole.system;

    if (isSystem) {
      return _buildSystemCard(theme);
    }

    if (isTool) {
      return _buildToolCard(theme);
    }

    final Color bgColor = isUser
        ? (userBubbleColor ?? theme.colorScheme.primary)
        : (modelBubbleColor ?? theme.colorScheme.surfaceContainerHighest);

    final Color fgColor = isUser
        ? (userTextColor ?? theme.colorScheme.onPrimary)
        : (modelTextColor ?? theme.colorScheme.onSurface);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius ??
              BorderRadius.only(
                topLeft: const Radius.circular(16.0),
                topRight: const Radius.circular(16.0),
                bottomLeft: Radius.circular(isUser ? 16.0 : 4.0),
                bottomRight: Radius.circular(isUser ? 4.0 : 16.0),
              ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4.0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (message.author.isNotEmpty && !isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  message.author,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: fgColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
            SelectableText(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fgColor,
                height: 1.4,
              ),
            ),
            if (message.isPartial)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: AdkTypingIndicator(
                  dotColor: fgColor.withValues(alpha: 0.6),
                  dotSize: 5.0,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: toolBubbleColor ?? theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.build_circle_outlined,
              size: 16.0,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 8.0),
            Flexible(
              child: Text(
                message.text.isNotEmpty
                    ? message.text
                    : 'Tool: ${message.toolName ?? "unknown"}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemCard(ThemeData theme) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: message.errorMessage != null
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (message.errorMessage != null)
              Icon(
                Icons.error_outline,
                size: 16.0,
                color: theme.colorScheme.error,
              ),
            if (message.errorMessage != null) const SizedBox(width: 6.0),
            Flexible(
              child: Text(
                message.errorMessage ?? message.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: message.errorMessage != null
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
