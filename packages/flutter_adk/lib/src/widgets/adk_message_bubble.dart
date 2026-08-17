import 'package:flutter/material.dart';

import '../models/adk_attachment_model.dart';
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
    final bool isUser = message.role == .user;
    final bool isTool = message.role == .tool;
    final bool isSystem = message.role == .system;

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
            if (message.attachments.isNotEmpty) ...<Widget>[
              _buildAttachmentsList(theme, isUser),
              if (message.text.isNotEmpty) const SizedBox(height: 6.0),
            ],
            if (message.text.isNotEmpty)
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

  Widget _buildAttachmentsList(ThemeData theme, bool isUser) {
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: message.attachments.map((AdkAttachment att) {
        if (att.isImage && att.bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.memory(
              att.bytes!,
              width: 140.0,
              height: 140.0,
              fit: BoxFit.cover,
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: isUser
                ? Colors.white.withValues(alpha: 0.2)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                att.isPdf
                    ? Icons.picture_as_pdf
                    : (att.isAudio ? Icons.audiotrack : Icons.attach_file),
                size: 16.0,
                color: isUser ? Colors.white : theme.colorScheme.primary,
              ),
              const SizedBox(width: 4.0),
              Flexible(
                child: Text(
                  att.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.0,
                    color: isUser ? Colors.white : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
              Icons.construction,
              size: 16.0,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8.0),
            Flexible(
              child: Text(
                message.toolName != null
                    ? 'Tool Execution: ${message.toolName}'
                    : message.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemCard(ThemeData theme) {
    final bool isErr = message.errorMessage != null;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isErr
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.7)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isErr ? Icons.error_outline : Icons.info_outline,
              size: 14.0,
              color: isErr
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6.0),
            Flexible(
              child: Text(
                message.errorMessage ?? message.text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isErr
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
