import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_adk_example/data/services/agent_service.dart';
import 'package:flutter_adk_example/data/services/chat_debug_logger.dart';
import 'package:flutter_adk_example/data/services/chat_history_store.dart';
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
    required this.enableDebugLogs,
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
  final bool enableDebugLogs;
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
  final ChatHistoryStore _chatHistoryStore =
      SharedPreferencesChatHistoryStore();
  List<PersistedChatSession> _savedSessions = <PersistedChatSession>[];
  bool _historyLoaded = false;

  InMemoryRunner? _runner;
  String? _runnerApiKey;
  bool _isSending = false;
  String? _loadingStatus;

  static const String _userId = 'example_user';
  String _sessionId = 'session_init';

  ChatDebugLogger _logger({String? sessionId}) {
    return ChatDebugLogger(
      enabled: widget.enableDebugLogs,
      exampleId: widget.exampleId,
      sessionId: sessionId ?? _sessionId,
    );
  }

  @override
  void initState() {
    super.initState();
    _messages = <_ChatMessage>[
      _ChatMessage.assistant(widget.initialAssistantMessage),
    ];
    unawaited(_loadPersistedSessions());
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
    _logger().logInfo('Reset runner requested.');
    final InMemoryRunner? runner = _runner;
    _runner = null;
    _runnerApiKey = null;
    if (runner != null) {
      await runner.close();
      _logger().logInfo('Runner closed.');
    }
  }

  Future<void> _loadPersistedSessions() async {
    final List<PersistedChatSession> sessions = await _chatHistoryStore
        .loadSessions(exampleId: widget.exampleId);
    if (!mounted) {
      return;
    }

    final List<_ChatMessage> initialMessages;
    String nextSessionId;
    if (sessions.isEmpty) {
      nextSessionId = _newSessionId();
      initialMessages = <_ChatMessage>[
        _ChatMessage.assistant(widget.initialAssistantMessage),
      ];
    } else {
      final PersistedChatSession active = sessions.first;
      nextSessionId = active.sessionId;
      initialMessages = _restoreMessages(active);
    }

    setState(() {
      _savedSessions = sessions;
      _sessionId = nextSessionId;
      _replaceMessages(initialMessages);
      _historyLoaded = true;
    });
    _logger(
      sessionId: nextSessionId,
    ).logInfo('Loaded ${sessions.length} persisted sessions.');

    if (sessions.isEmpty) {
      await _persistActiveSession();
    }
  }

  void _replaceMessages(List<_ChatMessage> nextMessages) {
    _messages
      ..clear()
      ..addAll(nextMessages);
  }

  List<_ChatMessage> _restoreMessages(PersistedChatSession session) {
    final List<_ChatMessage> restored = session.messages
        .where((PersistedChatMessage item) => item.text.trim().isNotEmpty)
        .map(
          (PersistedChatMessage item) => item.isUser
              ? _ChatMessage.user(item.text)
              : _ChatMessage.assistant(
                  item.text,
                  author: item.author,
                  isStreaming: false,
                ),
        )
        .toList(growable: false);
    if (restored.isEmpty) {
      return <_ChatMessage>[
        _ChatMessage.assistant(widget.initialAssistantMessage),
      ];
    }
    return restored;
  }

  String _newSessionId() {
    return '${widget.exampleId}_session_${DateTime.now().microsecondsSinceEpoch}';
  }

  PersistedChatSession? _activeSavedSession() {
    for (final PersistedChatSession session in _savedSessions) {
      if (session.sessionId == _sessionId) {
        return session;
      }
    }
    return null;
  }

  Future<void> _persistActiveSession() async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final PersistedChatSession? existing = _activeSavedSession();
    final List<PersistedChatMessage> persistedMessages = _messages
        .where(
          (_ChatMessage item) =>
              !item.isStreaming &&
              item.text.trim().isNotEmpty &&
              (item.isUser || (item.author != null && item.author!.isNotEmpty)),
        )
        .map(
          (_ChatMessage item) => PersistedChatMessage(
            isUser: item.isUser,
            text: item.text,
            author: item.author,
            timestampMs: now,
          ),
        )
        .toList(growable: false);

    final PersistedChatSession session = PersistedChatSession(
      sessionId: _sessionId,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
      messages: persistedMessages,
    );
    await _chatHistoryStore.upsertSession(
      exampleId: widget.exampleId,
      session: session,
    );
    if (!mounted) {
      return;
    }
    final List<PersistedChatSession> refreshed = await _chatHistoryStore
        .loadSessions(exampleId: widget.exampleId);
    if (!mounted) {
      return;
    }
    setState(() {
      _savedSessions = refreshed;
    });
  }

  Future<void> _rehydrateSessionEvents({
    required InMemoryRunner runner,
    required String sessionId,
  }) async {
    final PersistedChatSession? sessionRecord = _activeSavedSession();
    if (sessionRecord == null || sessionRecord.messages.isEmpty) {
      return;
    }
    final Session? session = await runner.sessionService.getSession(
      appName: runner.appName,
      userId: _userId,
      sessionId: sessionId,
    );
    if (session == null) {
      return;
    }

    for (int i = 0; i < sessionRecord.messages.length; i += 1) {
      final PersistedChatMessage message = sessionRecord.messages[i];
      final bool isUser = message.isUser;
      final Event event = Event(
        invocationId: 'rehydrate_$i',
        author: isUser ? 'user' : (message.author ?? 'model'),
        content: isUser
            ? Content.userText(message.text)
            : Content.modelText(message.text),
        partial: false,
        turnComplete: true,
      );
      await runner.sessionService.appendEvent(session: session, event: event);
    }

    _logger(sessionId: sessionId).logInfo(
      'Rehydrated ${sessionRecord.messages.length} messages into session.',
    );
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
    final String sessionId = _sessionId == 'session_init'
        ? _newSessionId()
        : _sessionId;
    await runner.sessionService.createSession(
      appName: runner.appName,
      userId: _userId,
      sessionId: sessionId,
    );
    await _rehydrateSessionEvents(runner: runner, sessionId: sessionId);

    _runner = runner;
    _runnerApiKey = apiKey;
    _sessionId = sessionId;
    _logger(sessionId: sessionId).logInfo(
      'Runner ready. appName=${runner.appName}, language=${widget.language.code}, mcpConfigured=${widget.mcpUrl.trim().isNotEmpty}',
    );
  }

  Future<void> _sendMessage() async {
    if (_isSending || !_historyLoaded) {
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
      _loadingStatus = null;
    });
    _scrollToBottom();
    _logger().logUserMessage(text);
    _setLoadingStatus(_statusPreparingSession(), phase: 'prepare_session');

    try {
      await _ensureRunner();
      _setLoadingStatus(_statusAnalyzingRequest(), phase: 'analyze_request');
      final InMemoryRunner runner = _runner!;
      final ChatDebugLogger logger = _logger();
      final Map<String, int> streamingIndexesByAuthor = <String, int>{};
      final Set<String> appendedFinalSignatures = <String>{};
      bool hasAssistantOutput = false;

      await for (final Event event in runner.runAsync(
        userId: _userId,
        sessionId: _sessionId,
        newMessage: Content.userText(text),
        runConfig: _streamingRunConfig,
      )) {
        logger.logEvent(event);
        _updateLoadingStatusFromEvent(event);
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
        logger.logInfo('No assistant output text found for this turn.');
        setState(() {
          _messages.add(_ChatMessage.assistant(widget.responseNotFoundMessage));
        });
      }
    } catch (error, stackTrace) {
      _setLoadingStatus(_statusError(), phase: 'error');
      _logger().logError(error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _ChatMessage.assistant('${widget.genericErrorPrefix}$error'),
        );
      });
    } finally {
      await _persistActiveSession();
      if (mounted) {
        _logger().logUiStatus(
          status: 'idle',
          phase: 'completed',
          author: null,
          targetAgent: null,
        );
        setState(() {
          _isSending = false;
          _loadingStatus = null;
        });
      }
      _scrollToBottom();
    }
  }

  void _setLoadingStatus(
    String nextStatus, {
    required String phase,
    String? author,
    String? targetAgent,
  }) {
    if (!mounted || _loadingStatus == nextStatus) {
      return;
    }
    setState(() {
      _loadingStatus = nextStatus;
    });
    _logger().logUiStatus(
      status: nextStatus,
      phase: phase,
      author: author,
      targetAgent: targetAgent,
    );
  }

  void _updateLoadingStatusFromEvent(Event event) {
    if (!_isSending) {
      return;
    }

    final String? transferredAgent = event.actions.transferToAgent?.trim();
    if (transferredAgent != null && transferredAgent.isNotEmpty) {
      _setLoadingStatus(
        _statusTransferredTo(transferredAgent),
        phase: 'transferred',
        targetAgent: transferredAgent,
      );
      return;
    }

    final String? transferTarget = _extractTransferTarget(event);
    if (transferTarget != null) {
      _setLoadingStatus(
        _statusRoutingTo(transferTarget),
        phase: 'routing',
        targetAgent: transferTarget,
      );
      return;
    }

    final String author = event.author.trim();
    if (author.isNotEmpty && author != 'user') {
      if (event.isFinalResponse()) {
        _setLoadingStatus(
          _statusFinalizing(author),
          phase: 'finalizing',
          author: author,
        );
      } else if (event.partial == true) {
        _setLoadingStatus(
          _statusStreaming(author),
          phase: 'streaming',
          author: author,
        );
      } else {
        _setLoadingStatus(
          _statusProcessing(author),
          phase: 'processing',
          author: author,
        );
      }
    }
  }

  String? _extractTransferTarget(Event event) {
    for (final FunctionCall functionCall in event.getFunctionCalls()) {
      if (functionCall.name != 'transfer_to_agent') {
        continue;
      }
      final Object? raw =
          functionCall.args['agent_name'] ?? functionCall.args['agentName'];
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
    }
    return null;
  }

  Future<void> _sendSuggestedPrompt(String prompt) async {
    if (_isSending || !_historyLoaded) {
      return;
    }
    _messageController.text = prompt;
    await _sendMessage();
  }

  Future<void> _startNewSession() async {
    if (_isSending || !_historyLoaded) {
      return;
    }
    await _resetRunner();
    final String nextSessionId = _newSessionId();
    if (!mounted) {
      return;
    }
    setState(() {
      _sessionId = nextSessionId;
      _replaceMessages(<_ChatMessage>[
        _ChatMessage.assistant(widget.initialAssistantMessage),
      ]);
    });
    await _persistActiveSession();
    _logger(sessionId: nextSessionId).logInfo('Started new session.');
  }

  Future<void> _switchToSession(PersistedChatSession session) async {
    if (_isSending || !_historyLoaded || session.sessionId == _sessionId) {
      return;
    }
    await _resetRunner();
    if (!mounted) {
      return;
    }
    setState(() {
      _sessionId = session.sessionId;
      _replaceMessages(_restoreMessages(session));
    });
    _logger(sessionId: session.sessionId).logInfo('Switched to saved session.');
  }

  Future<void> _showSessionPicker() async {
    if (_isSending || !_historyLoaded) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        final List<PersistedChatSession> sessions = _savedSessions;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _sessionsLabel(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_noSavedSessionsLabel()),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      itemBuilder: (BuildContext context, int index) {
                        final PersistedChatSession session = sessions[index];
                        final bool isActive = session.sessionId == _sessionId;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isActive
                                ? Icons.radio_button_checked
                                : Icons.history,
                            size: 18,
                          ),
                          title: Text(
                            _sessionTitle(session.updatedAtMs),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            session.preview.isEmpty
                                ? _emptySessionPreview()
                                : session.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () async {
                            Navigator.of(context).pop();
                            await _switchToSession(session);
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _startNewSession();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(_newSessionLabel()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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

  String _statusPreparingSession() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Preparing agent session...';
      case AppLanguage.ko:
        return '에이전트 세션 준비 중...';
      case AppLanguage.ja:
        return 'エージェント セッションを準備中...';
      case AppLanguage.zh:
        return '正在准备智能体会话...';
    }
  }

  String _statusAnalyzingRequest() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Analyzing request...';
      case AppLanguage.ko:
        return '요청 분석 중...';
      case AppLanguage.ja:
        return 'リクエストを分析中...';
      case AppLanguage.zh:
        return '正在分析请求...';
    }
  }

  String _statusRoutingTo(String agent) {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Routing to $agent...';
      case AppLanguage.ko:
        return '$agent(으)로 라우팅 중...';
      case AppLanguage.ja:
        return '$agent にルーティング中...';
      case AppLanguage.zh:
        return '正在路由到 $agent...';
    }
  }

  String _statusTransferredTo(String agent) {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Transferred to $agent. Waiting for response...';
      case AppLanguage.ko:
        return '$agent(으)로 전달됨. 응답 대기 중...';
      case AppLanguage.ja:
        return '$agent に引き継ぎました。応答待機中...';
      case AppLanguage.zh:
        return '已转交给 $agent，等待响应中...';
    }
  }

  String _statusProcessing(String agent) {
    switch (widget.language) {
      case AppLanguage.en:
        return '$agent is processing...';
      case AppLanguage.ko:
        return '$agent 처리 중...';
      case AppLanguage.ja:
        return '$agent が処理中...';
      case AppLanguage.zh:
        return '$agent 正在处理中...';
    }
  }

  String _statusStreaming(String agent) {
    switch (widget.language) {
      case AppLanguage.en:
        return '$agent is drafting a response...';
      case AppLanguage.ko:
        return '$agent 응답 작성 중...';
      case AppLanguage.ja:
        return '$agent が応答を生成中...';
      case AppLanguage.zh:
        return '$agent 正在生成回复...';
    }
  }

  String _statusFinalizing(String agent) {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Finalizing response from $agent...';
      case AppLanguage.ko:
        return '$agent 응답 마무리 중...';
      case AppLanguage.ja:
        return '$agent の応答を仕上げ中...';
      case AppLanguage.zh:
        return '正在完成 $agent 的回复...';
    }
  }

  String _statusError() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Failed while generating response.';
      case AppLanguage.ko:
        return '응답 생성 중 오류가 발생했습니다.';
      case AppLanguage.ja:
        return '応答生成中にエラーが発生しました。';
      case AppLanguage.zh:
        return '生成回复时发生错误。';
    }
  }

  String _sessionsLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Sessions';
      case AppLanguage.ko:
        return '세션';
      case AppLanguage.ja:
        return 'セッション';
      case AppLanguage.zh:
        return '会话';
    }
  }

  String _newSessionLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'New session';
      case AppLanguage.ko:
        return '새 세션';
      case AppLanguage.ja:
        return '新規セッション';
      case AppLanguage.zh:
        return '新建会话';
    }
  }

  String _resumeSessionLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'Resume';
      case AppLanguage.ko:
        return '불러오기';
      case AppLanguage.ja:
        return '再開';
      case AppLanguage.zh:
        return '继续';
    }
  }

  String _noSavedSessionsLabel() {
    switch (widget.language) {
      case AppLanguage.en:
        return 'No saved sessions yet.';
      case AppLanguage.ko:
        return '저장된 세션이 없습니다.';
      case AppLanguage.ja:
        return '保存されたセッションがありません。';
      case AppLanguage.zh:
        return '暂无已保存会话。';
    }
  }

  String _emptySessionPreview() {
    switch (widget.language) {
      case AppLanguage.en:
        return '(No messages)';
      case AppLanguage.ko:
        return '(메시지 없음)';
      case AppLanguage.ja:
        return '(メッセージなし)';
      case AppLanguage.zh:
        return '(暂无消息)';
    }
  }

  String _sessionTitle(int timestampMs) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(
      timestampMs,
    ).toLocal();
    final String yyyy = dt.year.toString().padLeft(4, '0');
    final String mm = dt.month.toString().padLeft(2, '0');
    final String dd = dt.day.toString().padLeft(2, '0');
    final String hh = dt.hour.toString().padLeft(2, '0');
    final String min = dt.minute.toString().padLeft(2, '0');
    switch (widget.language) {
      case AppLanguage.en:
        return '$yyyy-$mm-$dd $hh:$min';
      case AppLanguage.ko:
        return '$yyyy-$mm-$dd $hh:$min';
      case AppLanguage.ja:
        return '$yyyy-$mm-$dd $hh:$min';
      case AppLanguage.zh:
        return '$yyyy-$mm-$dd $hh:$min';
    }
  }

  String _currentSessionLabel() {
    final PersistedChatSession? current = _activeSavedSession();
    if (current == null) {
      return _sessionsLabel();
    }
    return '${_sessionsLabel()}: ${_sessionTitle(current.updatedAtMs)}';
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

  Widget _buildLoadingStatusBanner(BuildContext context) {
    final String status = _loadingStatus ?? _statusAnalyzingRequest();
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ),
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

  bool _isConversationEmpty() {
    for (final _ChatMessage message in _messages) {
      if (message.isUser ||
          (message.author != null && message.author!.trim().isNotEmpty)) {
        return false;
      }
    }
    return true;
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
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Chip(
                        avatar: const Icon(Icons.history, size: 16),
                        label: Text(
                          _historyLoaded
                              ? _currentSessionLabel()
                              : _statusPreparingSession(),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: (_isSending || !_historyLoaded)
                            ? null
                            : _showSessionPicker,
                        icon: const Icon(Icons.playlist_play),
                        label: Text(_resumeSessionLabel()),
                      ),
                      OutlinedButton.icon(
                        onPressed: (_isSending || !_historyLoaded)
                            ? null
                            : _startNewSession,
                        icon: const Icon(Icons.add),
                        label: Text(_newSessionLabel()),
                      ),
                    ],
                  ),
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
        if (_isSending) _buildLoadingStatusBanner(context),
        Expanded(
          child: _isConversationEmpty()
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
                    enabled: !_isSending && _historyLoaded,
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
                    onPressed: (_isSending || !_historyLoaded)
                        ? null
                        : _sendMessage,
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
