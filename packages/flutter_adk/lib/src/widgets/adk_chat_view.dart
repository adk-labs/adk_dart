import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

import '../controllers/adk_chat_controller.dart';
import '../models/adk_chat_message.dart';
import 'adk_message_bubble.dart';
import 'adk_typing_indicator.dart';

/// A complete, turnkey Chat UI widget for interacting with ADK agents and workflows.
class AdkChatView extends StatefulWidget {
  /// Creates an [AdkChatView].
  const AdkChatView({
    super.key,
    this.controller,
    this.agent,
    this.runner,
    this.title = 'AI Assistant',
    this.inputPlaceholder = 'Ask something...',
    this.emptyStateWidget,
    this.messageBubbleBuilder,
    this.showAppBar = false,
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

  /// Header title if [showAppBar] is true.
  final String title;

  /// Placeholder hint in the text input box.
  final String inputPlaceholder;

  /// Custom widget displayed when no messages have been sent yet.
  final Widget? emptyStateWidget;

  /// Optional builder to override message bubble rendering.
  final Widget Function(BuildContext context, AdkChatMessage message)?
      messageBubbleBuilder;

  /// Whether to include an internal AppBar.
  final bool showAppBar;

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

  void _handleSend() {
    final String text = _textEditingController.text;
    if (text.trim().isEmpty) return;

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
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(widget.title),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Clear chat',
                  onPressed: () => _controller.clearMessages(),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _controller.messages.isEmpty
                  ? _buildEmptyState(theme)
                  : _buildMessageList(),
            ),
            if (_controller.isLoading && !_controller.isStreaming)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: <Widget>[
                    const AdkTypingIndicator(dotSize: 6.0),
                    const SizedBox(width: 8.0),
                    Text(
                      'Thinking...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
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
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12.0),
          Text(
            'Start a conversation with ${widget.title}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      itemCount: _controller.messages.length,
      itemBuilder: (BuildContext context, int index) {
        final AdkChatMessage message = _controller.messages[index];
        if (widget.messageBubbleBuilder != null) {
          return widget.messageBubbleBuilder!(context, message);
        }
        return AdkMessageBubble(message: message);
      },
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _textEditingController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              enabled: !_controller.isLoading,
              decoration: InputDecoration(
                hintText: widget.inputPlaceholder,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 10.0,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24.0),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                  ),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          IconButton.filled(
            icon: _controller.isLoading
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 20.0),
            onPressed: _controller.isLoading ? null : _handleSend,
          ),
        ],
      ),
    );
  }
}
