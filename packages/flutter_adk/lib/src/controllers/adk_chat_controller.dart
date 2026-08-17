import 'dart:async';
import 'dart:convert';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

import '../models/adk_chat_message.dart';
import '../storage/adk_storage.dart';
import '../storage/adk_storage_session_service.dart';

/// State controller that manages conversation events, streaming responses,
/// and message history for ADK agents in Flutter.
class AdkChatController extends ChangeNotifier {
  /// Creates an [AdkChatController] bound to an agent or runner.
  AdkChatController({
    adk.BaseAgent? agent,
    adk.Runner? runner,
    String? userId,
    String? appName,
    String? sessionId,
    adk.BaseSessionService? sessionService,
  })  : userId = userId ?? 'default_user',
        appName = appName ?? 'default_app',
        sessionId = sessionId ?? 'default_session',
        sessionService = sessionService ?? (runner?.sessionService ?? adk.InMemorySessionService()),
        _runner = runner ??
            (agent != null
                ? adk.Runner(
                    appName: appName ?? 'default_app',
                    agent: agent,
                    sessionService:
                        sessionService ?? adk.InMemorySessionService(),
                    autoCreateSession: true,
                  )
                : null);

  /// Creates an [AdkChatController] persisted by [AdkKeyValueStorage].
  factory AdkChatController.fromStorage({
    required adk.BaseAgent agent,
    required AdkKeyValueStorage storage,
    String? userId,
    String? appName,
    String? sessionId,
  }) {
    final sessionService = AdkStorageSessionService(storage: storage);
    return AdkChatController(
      agent: agent,
      userId: userId,
      appName: appName,
      sessionId: sessionId,
      sessionService: sessionService,
    );
  }

  /// The active runner instance.
  final adk.Runner? _runner;

  /// Active user identifier.
  final String userId;

  /// Active application name.
  final String appName;

  /// Active session identifier.
  final String sessionId;

  /// Active session persistence service.
  final adk.BaseSessionService sessionService;

  final List<AdkChatMessage> _messages = <AdkChatMessage>[];
  bool _isLoading = false;
  bool _isStreaming = false;
  String? _currentError;
  StreamSubscription<adk.Event>? _subscription;

  /// Unmodifiable list of current chat messages in chronological order.
  List<AdkChatMessage> get messages =>
      List<AdkChatMessage>.unmodifiable(_messages);

  /// Whether a model or tool turn is currently executing.
  bool get isLoading => _isLoading;

  /// Whether the controller is actively receiving streaming chunks.
  bool get isStreaming => _isStreaming;

  /// The latest error message, if any.
  String? get currentError => _currentError;

  /// Sends a user prompt and streams the agent's response events into [messages].
  Future<void> sendMessage(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) {
      return;
    }

    _currentError = null;
    _isLoading = true;
    notifyListeners();

    final String userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    _messages.add(
      AdkChatMessage.user(
        id: userMsgId,
        text: trimmed,
        author: 'User',
      ),
    );
    notifyListeners();

    try {
      if (_runner == null) {
        throw StateError(
          'AdkChatController requires either an agent or a runner.',
        );
      }

      final Stream<adk.Event> eventStream = _runner.runAsync(
        userId: userId,
        sessionId: sessionId,
        newMessage: adk.Content.userText(trimmed),
      );

      await _consumeEventStream(eventStream);
    } catch (e) {
      _currentError = e.toString();
      _messages.add(
        AdkChatMessage.system(
          id: 'error_${DateTime.now().millisecondsSinceEpoch}',
          text: 'Error occurred during generation.',
          errorMessage: _currentError,
        ),
      );
    } finally {
      _isLoading = false;
      _isStreaming = false;
      notifyListeners();
    }
  }

  Future<void> _consumeEventStream(Stream<adk.Event> eventStream) async {
    String? currentModelMsgId;
    final StringBuffer textAccumulator = StringBuffer();

    _subscription = eventStream.listen(
      (adk.Event event) {
        final adk.Content? content = event.content;
        if (content == null) {
          _maybeHandleToolActions(event);
          return;
        }

        // Handle function calls inside content
        for (final adk.Part part in content.parts) {
          final adk.FunctionCall? fc = part.functionCall;
          if (fc != null) {
            _messages.add(
              AdkChatMessage.tool(
                id: 'tool_call_${DateTime.now().microsecondsSinceEpoch}',
                toolName: fc.name,
                toolArgs: fc.args,
                text: 'Calling tool: ${fc.name}',
                author: event.author.isNotEmpty ? event.author : 'Tool',
              ),
            );
            notifyListeners();
          }

          final adk.FunctionResponse? fr = part.functionResponse;
          if (fr != null) {
            _messages.add(
              AdkChatMessage.tool(
                id: 'tool_resp_${DateTime.now().microsecondsSinceEpoch}',
                toolName: fr.name,
                toolResult: fr.response,
                text: 'Tool result: ${fr.name}',
                author: 'Tool Result',
              ),
            );
            notifyListeners();
          }
        }

        // Extract text chunks for model responses
        final String chunkText = content.parts
            .map((adk.Part p) => p.text ?? '')
            .join('');

        if (chunkText.isNotEmpty) {
          _isStreaming = true;
          textAccumulator.write(chunkText);

          if (currentModelMsgId == null) {
            currentModelMsgId = 'model_${DateTime.now().millisecondsSinceEpoch}';
            _messages.add(
              AdkChatMessage.model(
                id: currentModelMsgId!,
                text: textAccumulator.toString(),
                author: event.author.isNotEmpty ? event.author : 'Agent',
                isPartial: true,
              ),
            );
          } else {
            final int index =
                _messages.indexWhere((AdkChatMessage m) => m.id == currentModelMsgId);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                text: textAccumulator.toString(),
                isPartial: true,
              );
            }
          }
          notifyListeners();
        }
      },
      onError: (Object error) {
        _currentError = error.toString();
        _messages.add(
          AdkChatMessage.system(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            text: 'Stream error',
            errorMessage: _currentError,
          ),
        );
        notifyListeners();
      },
    );

    await _subscription?.asFuture<void>();

    // Finalize the last model message as complete
    if (currentModelMsgId != null) {
      final int index =
          _messages.indexWhere((AdkChatMessage m) => m.id == currentModelMsgId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(isPartial: false);
      }
    }
  }

  void _maybeHandleToolActions(adk.Event event) {
    final adk.EventActions actions = event.actions;
    final Map<String, Object?>? state = actions.agentState;
    if (state != null && state.isNotEmpty) {
      notifyListeners();
    }
  }

  /// Loads previous messages and state from the underlying [sessionService].
  Future<void> loadSession({String? targetSessionId}) async {
    final id = targetSessionId ?? sessionId;
    final session = await sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: id,
    );

    if (session == null) return;

    _messages.clear();
    for (final event in session.events) {
      final content = event.content;
      if (content == null) continue;

      for (final part in content.parts) {
        if (part.text != null && part.text!.isNotEmpty) {
          final isUser = content.role == 'user' || event.author == 'user';
          _messages.add(
            AdkChatMessage(
              id: 'hist_${event.id ?? DateTime.now().microsecondsSinceEpoch}',
              role: isUser ? AdkMessageRole.user : AdkMessageRole.model,
              text: part.text!,
              author: event.author,
              timestamp: event.timestamp != null
                  ? DateTime.fromMillisecondsSinceEpoch((event.timestamp! * 1000).toInt())
                  : null,
            ),
          );
        } else if (part.functionCall != null) {
          _messages.add(
            AdkChatMessage.tool(
              id: 'hist_call_${part.functionCall!.name}',
              toolName: part.functionCall!.name,
              toolArgs: part.functionCall!.args,
              text: 'Called tool: ${part.functionCall!.name}',
              author: event.author,
            ),
          );
        } else if (part.functionResponse != null) {
          _messages.add(
            AdkChatMessage.tool(
              id: 'hist_resp_${part.functionResponse!.name}',
              toolName: part.functionResponse!.name,
              toolResult: part.functionResponse!.response,
              text: 'Tool result: ${part.functionResponse!.name}',
              author: 'Tool',
            ),
          );
        }
      }
    }
    notifyListeners();
  }

  /// Exports current chat messages as a formatted JSON string.
  String exportTranscriptJson({bool pretty = true}) {
    final list = _messages.map((m) => {
      'id': m.id,
      'role': m.role.name,
      'text': m.text,
      'author': m.author,
      'timestamp': m.timestamp.toIso8601String(),
      if (m.toolName != null) 'tool_name': m.toolName,
      if (m.toolArgs != null) 'tool_args': m.toolArgs,
      if (m.toolResult != null) 'tool_result': m.toolResult,
      if (m.errorMessage != null) 'error_message': m.errorMessage,
    }).toList();

    return pretty ? const JsonEncoder.withIndent('  ').convert(list) : jsonEncode(list);
  }

  /// Clears the message history and resets error state.
  void clearMessages() {
    _messages.clear();
    _currentError = null;
    notifyListeners();
  }

  /// Cancels any active streaming generation.
  void stopGeneration() {
    _subscription?.cancel();
    _subscription = null;
    _isLoading = false;
    _isStreaming = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
