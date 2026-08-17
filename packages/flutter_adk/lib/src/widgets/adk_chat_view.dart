import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

import '../controllers/adk_chat_controller.dart';
import '../models/adk_chat_message.dart';
import '../theme/adk_theme.dart';
import 'adk_message_bubble.dart';
import 'adk_prompt_suggestions_bar.dart';
import 'adk_typing_indicator.dart';

/// A complete, turnkey and highly customizable Chat UI widget for interacting with ADK agents.
class AdkChatView extends StatefulWidget {
  /// Creates an [AdkChatView].
  const AdkChatView({
    super.key,
    this.controller,
    this.agent,
    this.runner,
    this.theme,
    this.title = 'AI Assistant',
    this.inputPlaceholder = 'Ask something...',
    this.suggestions,
    this.emptyStateWidget,
    this.emptyStateBuilder,
    this.messageBubbleBuilder,
    this.avatarBuilder,
    this.inputBarBuilder,
    this.suggestionBuilder,
    this.typingIndicatorBuilder,
    this.headerBuilder,
    this.footerBuilder,
    this.onVoicePressed,
    this.onTapMessage,
    this.onLongPressMessage,
    this.showAppBar = false,
    this.showAvatars,
  }) : assert(
          controller != null || agent != null || runner != null,
          'AdkChatView requires either a controller, an agent, or a runner.',
        );

  /// Optional pre-configured controller. If omitted, one is created automatically.
  final AdkChatController? controller;

  /// Agent to interact with if [controller] is not provided.
  final adk.BaseAgent? agent;

  /// Runner to execute with if [controller] is not provided.
  final adk.Runner? runner;

  /// Optional theme styling configuration. If omitted, inherits from [AdkTheme.of].
  final AdkChatThemeData? theme;

  /// Header title if [showAppBar] is true.
  final String title;

  /// Placeholder hint in the text input box.
  final String inputPlaceholder;

  /// Optional prompt suggestion chips displayed above the input bar.
  final List<String>? suggestions;

  /// Custom static widget displayed when no messages have been sent yet.
  final Widget? emptyStateWidget;

  /// Custom builder for empty state screen.
  final Widget Function(BuildContext context)? emptyStateBuilder;

  /// Optional builder to override message bubble rendering entirely.
  final Widget Function(BuildContext context, AdkChatMessage message)?
      messageBubbleBuilder;

  /// Custom avatar builder for messages.
  final Widget Function(BuildContext context, AdkChatMessage message)?
      avatarBuilder;

  /// Custom input bar builder replacing the default text input and send button.
  final Widget Function(
    BuildContext context,
    TextEditingController controller,
    VoidCallback onSend,
    bool isLoading,
  )? inputBarBuilder;

  /// Custom builder for individual suggestion chips.
  final Widget Function(
    BuildContext context,
    String suggestion,
    VoidCallback onSelect,
  )? suggestionBuilder;

  /// Custom typing indicator builder.
  final Widget Function(BuildContext context)? typingIndicatorBuilder;

  /// Optional custom header builder placed above the messages list.
  final Widget Function(BuildContext context)? headerBuilder;

  /// Optional custom footer builder placed between messages and input bar.
  final Widget Function(BuildContext context)? footerBuilder;

  /// Optional callback for triggering voice input.
  final VoidCallback? onVoicePressed;

  /// Callback when a message bubble is tapped.
  final void Function(AdkChatMessage message)? onTapMessage;

  /// Callback when a message bubble is long-pressed.
  final void Function(AdkChatMessage message)? onLongPressMessage;

  /// Whether to include an internal AppBar.
  final bool showAppBar;

  /// Whether to display avatars next to messages.
  final bool? showAvatars;

  @override
  State<AdkChatView> createState() => _AdkChatViewState();
}

class _AdkChatViewState extends State<AdkChatView> {
  late final AdkChatController _controller;
  late final bool _ownsController;
  final TextEditingController _textEditingController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = AdkChatController(
        agent: widget.agent,
        runner: widget.runner,
      );
      _ownsController = true;
    }
    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final String text = _textEditingController.text.trim();
    if (text.isEmpty || _controller.isLoading) {
      return;
    }
    _textEditingController.clear();
    _controller.sendMessage(text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    if (_ownsController) {
      _controller.dispose();
    }
    _textEditingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData flutterTheme = Theme.of(context);
    final AdkChatThemeData adkTheme = widget.theme ?? AdkTheme.of(context);

    final Widget content = Scaffold(
      backgroundColor: adkTheme.backgroundColor ?? flutterTheme.colorScheme.surface,
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(widget.title, style: adkTheme.appBarTextStyle),
              backgroundColor: adkTheme.appBarBackgroundColor ?? flutterTheme.colorScheme.surface,
            )
          : null,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (widget.headerBuilder != null) widget.headerBuilder!(context),
            Expanded(
              child: _controller.messages.isEmpty
                  ? _buildEmptyState(flutterTheme)
                  : _buildMessagesList(flutterTheme, adkTheme),
            ),
            if (widget.footerBuilder != null) widget.footerBuilder!(context),
            if (widget.suggestions != null && widget.suggestions!.isNotEmpty)
              _buildSuggestionsBar(adkTheme),
            if (widget.inputBarBuilder != null)
              widget.inputBarBuilder!(
                context,
                _textEditingController,
                _sendMessage,
                _controller.isLoading,
              )
            else
              _buildDefaultInputBar(flutterTheme, adkTheme),
          ],
        ),
      ),
    );

    if (widget.theme != null) {
      return AdkTheme(data: widget.theme!, child: content);
    }
    return content;
  }

  Widget _buildEmptyState(ThemeData theme) {
    if (widget.emptyStateBuilder != null) {
      return widget.emptyStateBuilder!(context);
    }
    if (widget.emptyStateWidget != null) {
      return widget.emptyStateWidget!;
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.chat_bubble_outline,
            size: 48.0,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12.0),
          Text(
            widget.showAppBar ? 'How can I help you today?' : widget.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4.0),
          Text(
            widget.inputPlaceholder,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(ThemeData theme, AdkChatThemeData adkTheme) {
    final bool showAvatars = widget.showAvatars ?? adkTheme.showAvatars || widget.avatarBuilder != null;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: _controller.messages.length + (_controller.isLoading && !_controller.isStreaming ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index == _controller.messages.length) {
          if (widget.typingIndicatorBuilder != null) {
            return widget.typingIndicatorBuilder!(context);
          }
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AdkTypingIndicator(),
            ),
          );
        }

        final AdkChatMessage message = _controller.messages[index];

        if (widget.messageBubbleBuilder != null) {
          return widget.messageBubbleBuilder!(context, message);
        }

        return AdkMessageBubble(
          message: message,
          theme: adkTheme,
          avatarBuilder: widget.avatarBuilder,
          showAvatar: showAvatars,
          onTap: widget.onTapMessage != null ? () => widget.onTapMessage!(message) : null,
          onLongPress: widget.onLongPressMessage != null ? () => widget.onLongPressMessage!(message) : null,
        );
      },
    );
  }

  Widget _buildSuggestionsBar(AdkChatThemeData adkTheme) {
    if (widget.suggestionBuilder != null) {
      return SizedBox(
        height: 44.0,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          itemCount: widget.suggestions!.length,
          separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 8.0),
          itemBuilder: (BuildContext context, int index) {
            final String suggestion = widget.suggestions![index];
            return widget.suggestionBuilder!(
              context,
              suggestion,
              () => _controller.sendMessage(suggestion),
            );
          },
        ),
      );
    }

    return AdkPromptSuggestionsBar(
      suggestions: widget.suggestions!,
      onSelected: (String suggestion) {
        _controller.sendMessage(suggestion);
      },
    );
  }

  Widget _buildDefaultInputBar(ThemeData theme, AdkChatThemeData adkTheme) {
    final BorderRadius inputRadius = adkTheme.inputBorderRadius ?? BorderRadius.circular(24.0);
    final Color inputBg = adkTheme.inputBackgroundColor ?? theme.colorScheme.surfaceContainerHigh;
    final Color sendBtnBg = adkTheme.sendButtonColor ?? theme.colorScheme.primary;
    final Color sendBtnIconColor = adkTheme.sendButtonIconColor ?? theme.colorScheme.onPrimary;

    return Container(
      padding: adkTheme.inputPadding ?? const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Row(
        children: <Widget>[
          if (widget.onVoicePressed != null)
            IconButton(
              icon: const Icon(Icons.mic_outlined),
              onPressed: widget.onVoicePressed,
              tooltip: 'Voice Input',
            ),
          Expanded(
            child: TextField(
              controller: _textEditingController,
              decoration: InputDecoration(
                hintText: widget.inputPlaceholder,
                hintStyle: adkTheme.inputHintStyle,
                filled: true,
                fillColor: inputBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 10.0,
                ),
                border: OutlineInputBorder(
                  borderRadius: inputRadius,
                  borderSide: BorderSide.none,
                ),
              ),
              style: adkTheme.inputTextStyle,
              onSubmitted: (_) => _sendMessage(),
              enabled: !_controller.isLoading,
            ),
          ),
          const SizedBox(width: 8.0),
          IconButton.filled(
            icon: Icon(
              adkTheme.sendButtonIcon ?? Icons.arrow_upward,
              color: sendBtnIconColor,
            ),
            style: IconButton.styleFrom(backgroundColor: sendBtnBg),
            onPressed: _controller.isLoading ? null : _sendMessage,
          ),
        ],
      ),
    );
  }
}
