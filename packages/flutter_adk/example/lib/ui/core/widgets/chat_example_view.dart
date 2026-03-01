import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_adk_example/data/services/agent_service.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/ui/examples/models/example_menu_item.dart';

class ChatExampleView extends StatefulWidget {
  const ChatExampleView({
    super.key,
    required this.exampleId,
    required this.exampleTitle,
    required this.summary,
    required this.initialAssistantMessage,
    required this.emptyStateMessage,
    required this.inputHint,
    required this.examplePromptsTitle,
    required this.examplePrompts,
    required this.apiKey,
    required this.mcpUrl,
    required this.mcpBearerToken,
    required this.language,
    required this.createAgent,
    required this.apiKeyMissingMessage,
    required this.genericErrorPrefix,
    required this.responseNotFoundMessage,
  });

  final String exampleId;
  final String exampleTitle;
  final String summary;
  final String initialAssistantMessage;
  final String emptyStateMessage;
  final String inputHint;
  final String examplePromptsTitle;
  final List<ExamplePromptViewData> examplePrompts;
  final String apiKey;
  final String mcpUrl;
  final String mcpBearerToken;
  final AppLanguage language;
  final AgentBuilder createAgent;
  final String apiKeyMissingMessage;
  final String genericErrorPrefix;
  final String responseNotFoundMessage;

  @override
  State<ChatExampleView> createState() => _ChatExampleViewState();
}

class _ChatExampleViewState extends State<ChatExampleView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final RunConfig _streamingRunConfig = RunConfig(
    streamingMode: StreamingMode.sse,
  );

  late final List<_ChatMessage> _messages;

  InMemoryRunner? _runner;
  String? _runnerApiKey;
  bool _isSending = false;

  static const String _userId = 'example_user';
  String _sessionId = 'session_init';

  @override
  void initState() {
    super.initState();
    _messages = <_ChatMessage>[
      _ChatMessage.assistant(widget.initialAssistantMessage),
    ];
  }

  @override
  void didUpdateWidget(covariant ChatExampleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.apiKey != widget.apiKey && _runnerApiKey != widget.apiKey) ||
        oldWidget.language != widget.language ||
        oldWidget.mcpUrl != widget.mcpUrl ||
        oldWidget.mcpBearerToken != widget.mcpBearerToken) {
      unawaited(_resetRunner());
    }
  }

  @override
  void dispose() {
    unawaited(_runner?.close());
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resetRunner() async {
    final InMemoryRunner? runner = _runner;
    _runner = null;
    _runnerApiKey = null;
    if (runner != null) {
      await runner.close();
    }
  }

  Future<void> _ensureRunner() async {
    final String apiKey = widget.apiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError(widget.apiKeyMissingMessage);
    }
    if (_runner != null && _runnerApiKey == apiKey) {
      return;
    }

    await _resetRunner();

    final BaseAgent agent = widget.createAgent(
      apiKey: apiKey,
      language: widget.language,
      mcpUrl: widget.mcpUrl,
      mcpBearerToken: widget.mcpBearerToken,
    );
    final InMemoryRunner runner = InMemoryRunner(
      agent: agent,
      appName: 'flutter_adk_${widget.exampleId}_example',
    );
    final String sessionId =
        '${widget.exampleId}_session_${DateTime.now().microsecondsSinceEpoch}';
    await runner.sessionService.createSession(
      appName: runner.appName,
      userId: _userId,
      sessionId: sessionId,
    );

    _runner = runner;
    _runnerApiKey = apiKey;
    _sessionId = sessionId;
  }

  Future<void> _sendMessage() async {
    if (_isSending) {
      return;
    }

    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _messages.add(_ChatMessage.user(text));
      _messageController.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      await _ensureRunner();
      final InMemoryRunner runner = _runner!;
      final Map<String, int> streamingIndexesByAuthor = <String, int>{};
      final Set<String> appendedFinalSignatures = <String>{};
      bool hasAssistantOutput = false;

      await for (final Event event in runner.runAsync(
        userId: _userId,
        sessionId: _sessionId,
        newMessage: Content.userText(text),
        runConfig: _streamingRunConfig,
      )) {
        final bool updated = _consumeAgentEvent(
          event: event,
          streamingIndexesByAuthor: streamingIndexesByAuthor,
          appendedFinalSignatures: appendedFinalSignatures,
        );
        if (updated) {
          hasAssistantOutput = true;
          _scrollToBottom();
        }
      }

      _finalizeStreamingMessages(streamingIndexesByAuthor);
      if (!mounted) {
        return;
      }
      if (!hasAssistantOutput) {
        setState(() {
          _messages.add(_ChatMessage.assistant(widget.responseNotFoundMessage));
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _ChatMessage.assistant('${widget.genericErrorPrefix}$error'),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
      _scrollToBottom();
    }
  }

  Future<void> _sendSuggestedPrompt(String prompt) async {
    if (_isSending) {
      return;
    }
    _messageController.text = prompt;
    await _sendMessage();
  }

  bool _consumeAgentEvent({
    required Event event,
    required Map<String, int> streamingIndexesByAuthor,
    required Set<String> appendedFinalSignatures,
  }) {
    if (event.author == 'user') {
      return false;
    }

    final String text = _extractText(event.content);
    if (text.isEmpty) {
      return false;
    }
    final String author = event.author.isEmpty ? 'model' : event.author;

    if (event.partial == true) {
      if (!mounted) {
        return false;
      }
      bool changed = false;
      setState(() {
        final int? index = streamingIndexesByAuthor[author];
        if (index == null) {
          _messages.add(
            _ChatMessage.assistant(text, author: author, isStreaming: true),
          );
          streamingIndexesByAuthor[author] = _messages.length - 1;
          changed = true;
          return;
        }
        final _ChatMessage current = _messages[index];
        if (current.text != text || !current.isStreaming) {
          _messages[index] = current.copyWith(text: text, isStreaming: true);
          changed = true;
        }
      });
      return changed;
    }

    if (!event.isFinalResponse()) {
      return false;
    }

    if (!mounted) {
      return false;
    }
    bool changed = false;
    setState(() {
      final int? index = streamingIndexesByAuthor.remove(author);
      final String signature = '$author::$text';
      if (appendedFinalSignatures.contains(signature)) {
        if (index != null && _messages[index].isStreaming) {
          _messages[index] = _messages[index].copyWith(isStreaming: false);
          changed = true;
        }
        return;
      }

      if (index != null) {
        final _ChatMessage current = _messages[index];
        _messages[index] = current.copyWith(text: text, isStreaming: false);
      } else {
        _messages.add(_ChatMessage.assistant(text, author: author));
      }
      appendedFinalSignatures.add(signature);
      changed = true;
    });
    return changed;
  }

  void _finalizeStreamingMessages(Map<String, int> streamingIndexesByAuthor) {
    if (!mounted || streamingIndexesByAuthor.isEmpty) {
      return;
    }
    setState(() {
      for (final int index in streamingIndexesByAuthor.values.toSet()) {
        if (index < 0 || index >= _messages.length) {
          continue;
        }
        _messages[index] = _messages[index].copyWith(isStreaming: false);
      }
    });
    streamingIndexesByAuthor.clear();
  }

  String _extractText(Content? content) {
    if (content == null) {
      return '';
    }

    final List<String> parts = <String>[];
    for (final Part part in content.parts) {
      final String? text = part.text?.trim();
      if (text != null && text.isNotEmpty) {
        parts.add(text);
      }
    }

    return parts.join('\n').trim();
  }

  String _streamingLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'streaming...';
      case AppLanguage.ko:
        return '스트리밍 중...';
      case AppLanguage.ja:
        return 'ストリーミング中...';
      case AppLanguage.zh:
        return '流式生成中...';
    }
  }

  String _invalidLinkMessage() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Invalid link.';
      case AppLanguage.ko:
        return '유효하지 않은 링크입니다.';
      case AppLanguage.ja:
        return '無効なリンクです。';
      case AppLanguage.zh:
        return '无效链接。';
    }
  }

  String _openLinkFailedMessage(String url) {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Failed to open link: $url';
      case AppLanguage.ko:
        return '링크를 열 수 없습니다: $url';
      case AppLanguage.ja:
        return 'リンクを開けませんでした: $url';
      case AppLanguage.zh:
        return '无法打开链接：$url';
    }
  }

  void _showMessageSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Uri? _normalizeLinkUri(String href) {
    final String raw = href.trim();
    if (raw.isEmpty) {
      return null;
    }

    final Uri? parsed = Uri.tryParse(raw);
    if (parsed == null) {
      return null;
    }
    if (parsed.hasScheme) {
      return parsed;
    }
    return Uri.tryParse('https://$raw');
  }

  Future<void> _onTapMarkdownLink(
    String? href, {
    String? text,
    String? title,
  }) async {
    if (href == null || href.trim().isEmpty) {
      _showMessageSnackBar(_invalidLinkMessage());
      return;
    }

    final Uri? uri = _normalizeLinkUri(href);
    if (uri == null) {
      _showMessageSnackBar(_invalidLinkMessage());
      return;
    }

    final bool opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!opened) {
      _showMessageSnackBar(_openLinkFailedMessage(uri.toString()));
    }
  }

  Widget _buildMessageBody(BuildContext context, _ChatMessage message) {
    if (message.isUser) {
      return SelectableText(message.text);
    }

    final MarkdownStyleSheet base = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    );
    final Color codeBlockColor = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;

    return MarkdownBody(
      data: message.text,
      selectable: true,
      shrinkWrap: true,
      softLineBreak: true,
      onTapLink: (String text, String? href, String title) {
        unawaited(_onTapMarkdownLink(href, text: text, title: title));
      },
      styleSheet: base.copyWith(
        p: Theme.of(context).textTheme.bodyMedium,
        code: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: codeBlockColor,
        ),
        codeblockDecoration: BoxDecoration(
          color: codeBlockColor,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(
                    widget.exampleTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(widget.summary),
                  if (widget.examplePrompts.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      widget.examplePromptsTitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.examplePrompts
                          .where(
                            (ExamplePromptViewData prompt) =>
                                prompt.text.trim().isNotEmpty,
                          )
                          .map((ExamplePromptViewData prompt) {
                            return ActionChip(
                              avatar: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: prompt.isAdvanced
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.secondaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  prompt.difficultyLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
                                child: Text(
                                  prompt.text,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              tooltip: prompt.text,
                              onPressed: _isSending
                                  ? null
                                  : () => _sendSuggestedPrompt(prompt.text),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _messages.length == 1
              ? Center(
                  child: SelectableText(
                    widget.emptyStateMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  itemCount: _messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    final _ChatMessage message = _messages[index];
                    return Align(
                      alignment: message.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: message.isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (!message.isUser &&
                                message.author != null &&
                                message.author!.isNotEmpty) ...<Widget>[
                              Text(
                                message.author!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (!message.isUser &&
                                message.isStreaming) ...<Widget>[
                              Text(
                                _streamingLabel(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            _buildMessageBody(context, message),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isSending,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: widget.inputHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isSending ? null : _sendMessage,
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatMessage {
  _ChatMessage({
    required this.isUser,
    required this.text,
    this.author,
    this.isStreaming = false,
  });

  factory _ChatMessage.user(String text) {
    return _ChatMessage(isUser: true, text: text);
  }

  factory _ChatMessage.assistant(
    String text, {
    String? author,
    bool isStreaming = false,
  }) {
    return _ChatMessage(
      isUser: false,
      text: text,
      author: author,
      isStreaming: isStreaming,
    );
  }

  _ChatMessage copyWith({String? text, String? author, bool? isStreaming}) {
    return _ChatMessage(
      isUser: isUser,
      text: text ?? this.text,
      author: author ?? this.author,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  final bool isUser;
  final String text;
  final String? author;
  final bool isStreaming;
}
