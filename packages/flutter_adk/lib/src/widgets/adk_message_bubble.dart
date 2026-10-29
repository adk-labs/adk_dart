import 'package:flutter/material.dart';

import '../models/adk_attachment_model.dart';
import '../models/adk_chat_message.dart';
import '../models/adk_token_usage_model.dart';
import '../theme/adk_theme.dart';
import 'adk_code_execution_card.dart';
import 'adk_compaction_summary_card.dart';
import 'adk_computer_action_card.dart';
import 'adk_file_edit_card.dart';
import 'adk_grounding_sources_bar.dart';
import 'adk_reasoning_expander.dart';
import 'adk_shell_command_card.dart';
import 'adk_skill_tool_card.dart';
import 'adk_token_usage_badge.dart';
import 'adk_tool_call_card.dart';
import 'adk_typing_indicator.dart';
import 'adk_web_page_card.dart';

/// A customizable message bubble widget representing user, model, tool, or system messages.
class AdkMessageBubble extends StatelessWidget {
  /// Creates an [AdkMessageBubble].
  const AdkMessageBubble({
    super.key,
    required this.message,
    this.theme,
    this.userBubbleColor,
    this.modelBubbleColor,
    this.toolBubbleColor,
    this.userTextColor,
    this.modelTextColor,
    this.userTextStyle,
    this.modelTextStyle,
    this.borderRadius,
    this.avatar,
    this.avatarBuilder,
    this.showAvatar,
    this.showTimestamp,
    this.timestampFormatter,
    this.onTap,
    this.onLongPress,
    this.onGroundingSourceTap,
    this.customContentBuilder,
    this.toolCardBuilder,
    this.systemCardBuilder,
    this.compactionCardBuilder,
    this.tokenUsageBuilder,
    this.thoughtBuilder,
    this.codeExecutionBuilder,
    this.groundingBuilder,
    this.attachmentBuilder,
    this.toolCardStyle,
    this.terminalCardStyle,
    this.usageBadgeStyle,
    this.compactionCardStyle,
    this.useToolCallCard = true,
    this.useSpecializedToolCards = true,
    this.showTokenUsage = true,
  });

  /// The chat message to render.
  final AdkChatMessage message;

  /// Optional theme override for this bubble.
  final AdkChatThemeData? theme;

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

  /// Custom text style for user bubbles.
  final TextStyle? userTextStyle;

  /// Custom text style for model bubbles.
  final TextStyle? modelTextStyle;

  /// Custom corner radius for the bubble container.
  final BorderRadius? borderRadius;

  /// Static avatar widget displayed beside the message.
  final Widget? avatar;

  /// Custom avatar builder for dynamic avatars per message.
  final Widget Function(BuildContext context, AdkChatMessage message)? avatarBuilder;

  /// Whether to render an avatar beside this message.
  final bool? showAvatar;

  /// Whether to display a timestamp below the bubble text.
  final bool? showTimestamp;

  /// Formatter function for timestamps.
  final String Function(DateTime timestamp)? timestampFormatter;

  /// Callback when the message bubble is tapped.
  final VoidCallback? onTap;

  /// Callback when the message bubble is long-pressed.
  final VoidCallback? onLongPress;

  /// Callback invoked when a grounding citation source chip is tapped.
  final void Function(AdkGroundingSource source)? onGroundingSourceTap;

  /// Optional builder to override internal message body content.
  final Widget Function(BuildContext context, AdkChatMessage message)? customContentBuilder;

  /// Optional builder to override tool call and tool response cards.
  final Widget Function(BuildContext context, AdkChatMessage message)?
      toolCardBuilder;

  /// Optional builder to override system and error notification cards.
  final Widget Function(BuildContext context, AdkChatMessage message)?
      systemCardBuilder;

  /// Optional builder to override compacted conversation summary cards.
  final Widget Function(BuildContext context, AdkChatMessage message)?
      compactionCardBuilder;

  /// Optional builder to override the per-message token usage badge.
  final Widget Function(
    BuildContext context,
    AdkTokenUsage usage,
    AdkChatMessage message,
  )? tokenUsageBuilder;

  /// Optional builder to override the reasoning / thought expander inside model bubbles.
  final Widget Function(
    BuildContext context,
    String thought,
    AdkChatMessage message,
  )? thoughtBuilder;

  /// Optional builder to override the code execution card inside model bubbles.
  final Widget Function(
    BuildContext context,
    AdkCodeExecution execution,
    AdkChatMessage message,
  )? codeExecutionBuilder;

  /// Optional builder to override the grounding citation bar inside model bubbles.
  final Widget Function(
    BuildContext context,
    AdkGroundingInfo grounding,
    AdkChatMessage message,
  )? groundingBuilder;

  /// Optional builder to override individual attachment items inside bubbles.
  final Widget Function(
    BuildContext context,
    AdkAttachment attachment,
    bool isUser,
  )? attachmentBuilder;

  /// Optional style override applied to tool, skill, file, web, and computer cards.
  final AdkCardStyle? toolCardStyle;

  /// Optional style override applied to shell command and code execution terminal cards.
  final AdkCardStyle? terminalCardStyle;

  /// Optional style override applied to the token usage badge.
  final AdkCardStyle? usageBadgeStyle;

  /// Optional style override applied to the compaction summary card.
  final AdkCardStyle? compactionCardStyle;

  /// Whether to render tool messages using [AdkToolCallCard] with expandable args and results.
  final bool useToolCallCard;

  /// Whether to route built-in tool names (`SkillToolset`, `FileEdit`, `ShellCommand`, `WebPage`, `ComputerAction`) to their dedicated cards.
  final bool useSpecializedToolCards;

  /// Whether to display an [AdkTokenUsageBadge] beneath model responses when token metrics are present.
  final bool showTokenUsage;

  @override
  Widget build(BuildContext context) {
    final ThemeData flutterTheme = Theme.of(context);
    final AdkChatThemeData adkTheme = theme ?? AdkTheme.of(context);

    final bool isUser = message.role == .user;
    final bool isTool = message.role == .tool;
    final bool isSystem = message.role == .system;

    if (isSystem) {
      return _buildSystemCard(context, flutterTheme, adkTheme);
    }

    if (isTool) {
      return _buildToolCard(context, flutterTheme, adkTheme);
    }

    final Color bgColor = isUser
        ? (userBubbleColor ?? adkTheme.userBubbleColor ?? flutterTheme.colorScheme.primary)
        : (modelBubbleColor ?? adkTheme.modelBubbleColor ?? flutterTheme.colorScheme.surfaceContainerHighest);

    final Color fgColor = isUser
        ? (userTextColor ?? adkTheme.userTextColor ?? flutterTheme.colorScheme.onPrimary)
        : (modelTextColor ?? adkTheme.modelTextColor ?? flutterTheme.colorScheme.onSurface);

    final TextStyle defaultTextStyle = isUser
        ? (userTextStyle ?? adkTheme.userTextStyle ?? flutterTheme.textTheme.bodyMedium!.copyWith(color: fgColor, height: 1.4))
        : (modelTextStyle ?? adkTheme.modelTextStyle ?? flutterTheme.textTheme.bodyMedium!.copyWith(color: fgColor, height: 1.4));

    final BorderRadius bubbleRadius = borderRadius ??
        (isUser ? adkTheme.userBorderRadius : adkTheme.modelBorderRadius) ??
        adkTheme.borderRadius ??
        BorderRadius.only(
          topLeft: const Radius.circular(16.0),
          topRight: const Radius.circular(16.0),
          bottomLeft: Radius.circular(isUser ? 16.0 : 4.0),
          bottomRight: Radius.circular(isUser ? 4.0 : 16.0),
        );

    final bool displayAvatar = showAvatar ?? adkTheme.showAvatars || avatarBuilder != null || avatar != null;
    final Widget? avatarWidget = displayAvatar
        ? (avatarBuilder != null
            ? avatarBuilder!(context, message)
            : avatar ?? _buildDefaultAvatar(flutterTheme, isUser))
        : null;

    final Widget bubbleContent = Container(
      margin: adkTheme.bubbleMargin ?? const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * adkTheme.maxWidthFactor,
      ),
      padding: adkTheme.bubblePadding ?? const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: bubbleRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (message.author.isNotEmpty && !isUser)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                message.author,
                style: adkTheme.authorTextStyle ??
                    flutterTheme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: fgColor.withValues(alpha: 0.7),
                    ),
              ),
            ),
          if (message.thought != null && message.thought!.isNotEmpty) ...<Widget>[
            if (thoughtBuilder != null)
              thoughtBuilder!(context, message.thought!, message)
            else
              AdkReasoningExpander(thought: message.thought!),
            const SizedBox(height: 4.0),
          ],
          if (message.codeExecution != null) ...<Widget>[
            if (codeExecutionBuilder != null)
              codeExecutionBuilder!(context, message.codeExecution!, message)
            else
              AdkCodeExecutionCard(
                execution: message.codeExecution!,
                style: terminalCardStyle ?? adkTheme.terminalCardStyle,
              ),
            if (message.text.isNotEmpty) const SizedBox(height: 6.0),
          ],
          if (message.attachments.isNotEmpty) ...<Widget>[
            _buildAttachmentsList(context, flutterTheme, isUser),
            if (message.text.isNotEmpty) const SizedBox(height: 6.0),
          ],
          if (customContentBuilder != null)
            customContentBuilder!(context, message)
          else if (message.text.isNotEmpty)
            SelectableText(
              message.text,
              style: defaultTextStyle,
            ),
          if (message.grounding != null && message.grounding!.isNotEmpty)
            if (groundingBuilder != null)
              groundingBuilder!(context, message.grounding!, message)
            else
              AdkGroundingSourcesBar(
                grounding: message.grounding!,
                onSourceTap: onGroundingSourceTap,
                style: toolCardStyle ?? adkTheme.cardStyle,
              ),
          if (!isUser &&
              showTokenUsage &&
              message.tokenUsage != null &&
              message.tokenUsage!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: tokenUsageBuilder != null
                  ? tokenUsageBuilder!(context, message.tokenUsage!, message)
                  : AdkTokenUsageBadge.fromUsage(
                      message.tokenUsage!,
                      compact: true,
                      style: usageBadgeStyle ?? adkTheme.usageBadgeStyle,
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
          if ((showTimestamp ?? adkTheme.showTimestamp))
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                timestampFormatter != null
                    ? timestampFormatter!(message.timestamp)
                    : _formatTime(message.timestamp),
                style: adkTheme.timestampTextStyle ??
                    TextStyle(
                      fontSize: 10.0,
                      color: fgColor.withValues(alpha: 0.6),
                    ),
              ),
            ),
        ],
      ),
    );

    final Widget interactiveBubble = (onTap != null || onLongPress != null)
        ? InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: bubbleRadius,
            child: bubbleContent,
          )
        : bubbleContent;

    if (!displayAvatar || avatarWidget == null) {
      return Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: interactiveBubble,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (!isUser) ...<Widget>[
            avatarWidget,
            const SizedBox(width: 4.0),
          ],
          Flexible(child: interactiveBubble),
          if (isUser) ...<Widget>[
            const SizedBox(width: 4.0),
            avatarWidget,
          ],
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(ThemeData theme, bool isUser) {
    return CircleAvatar(
      radius: 14.0,
      backgroundColor: isUser ? theme.colorScheme.primaryContainer : theme.colorScheme.secondaryContainer,
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        size: 16.0,
        color: isUser ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSecondaryContainer,
      ),
    );
  }

  Widget _buildAttachmentsList(
    BuildContext context,
    ThemeData theme,
    bool isUser,
  ) {
    return Wrap(
      spacing: 6.0,
      runSpacing: 6.0,
      children: message.attachments.map((AdkAttachment att) {
        if (attachmentBuilder != null) {
          return attachmentBuilder!(context, att, isUser);
        }
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

  Widget _buildToolCard(
    BuildContext context,
    ThemeData theme,
    AdkChatThemeData adkTheme,
  ) {
    if (toolCardBuilder != null) {
      return toolCardBuilder!(context, message);
    }
    final AdkCardStyle? effectiveToolStyle =
        adkTheme.cardStyle?.merge(toolCardStyle) ?? toolCardStyle;
    final AdkCardStyle? effectiveTerminalStyle =
        adkTheme.terminalCardStyle?.merge(terminalCardStyle) ??
        terminalCardStyle;
    final String? name = message.toolName;
    if (useSpecializedToolCards && name != null) {
      if (AdkSkillToolCard.isSkillTool(name)) {
        return AdkSkillToolCard(
          toolName: name,
          toolArgs: message.toolArgs,
          toolResult: message.toolResult,
          isRunning: message.isPartial,
          style: effectiveToolStyle,
        );
      }
      if (AdkFileEditCard.isFileTool(name)) {
        return AdkFileEditCard(
          toolName: name,
          toolArgs: message.toolArgs,
          toolResult: message.toolResult,
          isRunning: message.isPartial,
          style: effectiveToolStyle,
        );
      }
      if (AdkShellCommandCard.isShellTool(name)) {
        return AdkShellCommandCard(
          toolName: name,
          toolArgs: message.toolArgs,
          toolResult: message.toolResult,
          isRunning: message.isPartial,
          style: effectiveTerminalStyle,
        );
      }
      if (AdkWebPageCard.isWebPageTool(name)) {
        return AdkWebPageCard(
          toolName: name,
          toolArgs: message.toolArgs,
          toolResult: message.toolResult,
          isRunning: message.isPartial,
          style: effectiveToolStyle,
        );
      }
      if (AdkComputerActionCard.isComputerActionTool(name)) {
        return AdkComputerActionCard(
          toolName: name,
          toolArgs: message.toolArgs,
          toolResult: message.toolResult,
          isRunning: message.isPartial,
          style: effectiveToolStyle,
        );
      }
    }

    if (useToolCallCard && (message.toolName != null || message.toolArgs != null || message.toolResult != null)) {
      return AdkToolCallCard(
        toolName: message.toolName ?? 'Unnamed Tool',
        toolArgs: message.toolArgs,
        toolResult: message.toolResult,
        errorMessage: message.errorMessage,
        isRunning: message.isPartial,
        style: effectiveToolStyle,
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 12.0),
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: toolBubbleColor ?? adkTheme.toolBubbleColor ?? theme.colorScheme.surfaceContainerLow,
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
                style: adkTheme.toolTextStyle ??
                    theme.textTheme.bodySmall?.copyWith(
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

  Widget _buildSystemCard(
    BuildContext context,
    ThemeData theme,
    AdkChatThemeData adkTheme,
  ) {
    if (message.isCompaction) {
      if (compactionCardBuilder != null) {
        return compactionCardBuilder!(context, message);
      }
      return AdkCompactionSummaryCard(
        summaryText: message.text,
        style: adkTheme.compactionCardStyle?.merge(compactionCardStyle) ??
            compactionCardStyle,
      );
    }
    if (systemCardBuilder != null) {
      return systemCardBuilder!(context, message);
    }
    final bool isErr = message.errorMessage != null;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: isErr
              ? (adkTheme.errorBubbleColor ?? theme.colorScheme.errorContainer.withValues(alpha: 0.7))
              : (adkTheme.systemBubbleColor ?? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
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

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}
