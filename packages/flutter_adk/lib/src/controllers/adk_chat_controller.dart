import 'dart:async';
import 'dart:convert';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/foundation.dart';

import '../models/adk_chat_message.dart';
import '../storage/adk_storage.dart';
import '../storage/adk_storage_session_service.dart';

/// State controller that manages conversation events, streaming responses,
/// and message history for ADK agents in Flutter.
///
/// ```dart
/// final controller = AdkChatController(
///   agent: myAgent,
///   userId: 'user_1',
///   sessionId: 'session_1',
/// );
/// await controller.sendMessage('Hello!');
/// controller.dispose();
/// ```
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
    final StringBuffer thoughtAccumulator = StringBuffer();
    AdkCodeExecution? pendingCodeExecution;
    AdkGroundingInfo? latestGrounding;

    _subscription = eventStream.listen(
      (adk.Event event) {
        final adk.EventCompaction? compaction = event.actions.compaction;
        if (compaction != null) {
          final String summaryText = compaction.compactedContent.parts
              .map((adk.Part p) => p.text ?? '')
              .join('')
              .trim();
          if (summaryText.isNotEmpty) {
            _messages.add(
              AdkChatMessage.system(
                id: 'compaction_${event.id}',
                text: 'Session compacted: $summaryText',
                isCompaction: true,
              ),
            );
            notifyListeners();
          }
        }

        final AdkGroundingInfo? eventGrounding = _extractGroundingInfo(
          event.groundingMetadata,
        );
        if (eventGrounding != null) {
          latestGrounding = eventGrounding;
        }

        final adk.Content? content = event.content;
        if (content == null) {
          _maybeHandleToolActions(event);
          return;
        }

        // Handle function calls, responses, and code execution inside content
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

          final Object? execCode = part.executableCode;
          if (execCode != null) {
            final (String language, String code) = _parseExecutableCode(
              execCode,
            );
            pendingCodeExecution = (pendingCodeExecution ?? const AdkCodeExecution())
                .copyWith(language: language, code: code);
          }

          final Object? execResult = part.codeExecutionResult;
          if (execResult != null) {
            final (String? outcome, String? output) =
                _parseCodeExecutionResult(execResult);
            pendingCodeExecution = (pendingCodeExecution ?? const AdkCodeExecution())
                .copyWith(outcome: outcome, output: output);
          }
        }

        // Extract thought and regular text chunks for model responses
        final String thoughtChunk = content.parts
            .where((adk.Part p) => p.thought && p.text != null)
            .map((adk.Part p) => p.text!)
            .join('');
        if (thoughtChunk.isNotEmpty) {
          thoughtAccumulator.write(thoughtChunk);
        }

        final String chunkText = content.parts
            .where((adk.Part p) => !p.thought)
            .map((adk.Part p) => p.text ?? '')
            .join('');

        final bool hasModelUpdate =
            chunkText.isNotEmpty ||
            thoughtChunk.isNotEmpty ||
            pendingCodeExecution != null ||
            eventGrounding != null;

        if (hasModelUpdate) {
          _isStreaming = true;
          if (chunkText.isNotEmpty) {
            textAccumulator.write(chunkText);
          }
          final String? currentThought = thoughtAccumulator.isEmpty
              ? null
              : thoughtAccumulator.toString();

          if (currentModelMsgId == null) {
            currentModelMsgId = 'model_${DateTime.now().millisecondsSinceEpoch}';
            _messages.add(
              AdkChatMessage.model(
                id: currentModelMsgId!,
                text: textAccumulator.toString(),
                author: event.author.isNotEmpty ? event.author : 'Agent',
                isPartial: true,
                thought: currentThought,
                codeExecution: pendingCodeExecution,
                grounding: latestGrounding,
              ),
            );
          } else {
            final int index =
                _messages.indexWhere((AdkChatMessage m) => m.id == currentModelMsgId);
            if (index != -1) {
              _messages[index] = _messages[index].copyWith(
                text: textAccumulator.toString(),
                isPartial: true,
                thought: currentThought,
                codeExecution: pendingCodeExecution,
                grounding: latestGrounding,
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
      final compaction = event.actions.compaction;
      if (compaction != null) {
        final summaryText = compaction.compactedContent.parts
            .map((p) => p.text ?? '')
            .join('')
            .trim();
        if (summaryText.isNotEmpty) {
          _messages.add(
            AdkChatMessage.system(
              id: 'hist_compaction_${event.id}',
              text: 'Session compacted: $summaryText',
              isCompaction: true,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                (event.timestamp * 1000).toInt(),
              ),
            ),
          );
        }
      }

      final content = event.content;
      if (content == null) continue;

      final AdkGroundingInfo? grounding = _extractGroundingInfo(
        event.groundingMetadata,
      );
      AdkCodeExecution? codeExec;
      for (final part in content.parts) {
        if (part.executableCode != null) {
          final (String lang, String code) = _parseExecutableCode(
            part.executableCode!,
          );
          codeExec = (codeExec ?? const AdkCodeExecution()).copyWith(
            language: lang,
            code: code,
          );
        }
        if (part.codeExecutionResult != null) {
          final (String? outcome, String? output) = _parseCodeExecutionResult(
            part.codeExecutionResult!,
          );
          codeExec = (codeExec ?? const AdkCodeExecution()).copyWith(
            outcome: outcome,
            output: output,
          );
        }
      }

      bool attachedExtrasToModelMessage = false;
      for (final part in content.parts) {
        if (part.text != null && part.text!.isNotEmpty && !part.thought) {
          final isUser = content.role == 'user' || event.author == 'user';
          _messages.add(
            AdkChatMessage(
              id: 'hist_${event.id}',
              role: isUser ? .user : .model,
              text: part.text!,
              author: event.author,
              codeExecution: !isUser && !attachedExtrasToModelMessage
                  ? codeExec
                  : null,
              grounding: !isUser && !attachedExtrasToModelMessage
                  ? grounding
                  : null,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                (event.timestamp * 1000).toInt(),
              ),
            ),
          );
          if (!isUser) {
            attachedExtrasToModelMessage = true;
          }
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
      if (!attachedExtrasToModelMessage &&
          (codeExec != null || grounding != null)) {
        _messages.add(
          AdkChatMessage.model(
            id: 'hist_exec_${event.id}',
            text: '',
            author: event.author.isNotEmpty ? event.author : 'Agent',
            codeExecution: codeExec,
            grounding: grounding,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (event.timestamp * 1000).toInt(),
            ),
          ),
        );
      }
    }
    notifyListeners();
  }

  (String, String) _parseExecutableCode(Object raw) {
    if (raw is Map) {
      final String language = '${raw['language'] ?? 'PYTHON'}'.trim();
      final String code = '${raw['code'] ?? ''}'.trim();
      return (language.isEmpty ? 'PYTHON' : language, code);
    }
    return ('PYTHON', '$raw');
  }

  (String?, String?) _parseCodeExecutionResult(Object raw) {
    if (raw is Map) {
      final String? outcome = raw['outcome']?.toString();
      final String? output = raw['output']?.toString();
      return (outcome, output);
    }
    return ('OUTCOME_OK', '$raw');
  }

  AdkGroundingInfo? _extractGroundingInfo(Object? rawGrounding) {
    if (rawGrounding is! Map) {
      return null;
    }
    final List<String> queries = <String>[];
    final Object? rawQueries =
        rawGrounding['webSearchQueries'] ?? rawGrounding['web_search_queries'];
    if (rawQueries is List) {
      for (final Object? item in rawQueries) {
        final String text = '${item ?? ''}'.trim();
        if (text.isNotEmpty) {
          queries.add(text);
        }
      }
    }

    final List<AdkGroundingSource> sources = <AdkGroundingSource>[];
    final Object? rawChunks =
        rawGrounding['groundingChunks'] ?? rawGrounding['grounding_chunks'];
    if (rawChunks is List) {
      for (final Object? chunk in rawChunks) {
        if (chunk is! Map) continue;
        final Object? web = chunk['web'] ?? chunk['retrievedContext'] ?? chunk['retrieved_context'];
        if (web is Map) {
          final String uri = '${web['uri'] ?? ''}'.trim();
          final String title = '${web['title'] ?? uri}'.trim();
          if (uri.isNotEmpty) {
            sources.add(AdkGroundingSource(title: title, uri: uri));
          }
        }
      }
    }

    if (queries.isEmpty && sources.isEmpty) {
      return null;
    }
    return AdkGroundingInfo(searchQueries: queries, sources: sources);
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
      if (m.codeExecution != null)
        'code_execution': {
          'language': m.codeExecution!.language,
          'code': m.codeExecution!.code,
          if (m.codeExecution!.output != null)
            'output': m.codeExecution!.output,
          if (m.codeExecution!.outcome != null)
            'outcome': m.codeExecution!.outcome,
        },
      if (m.grounding != null && m.grounding!.isNotEmpty)
        'grounding': {
          'search_queries': m.grounding!.searchQueries,
          'sources': m.grounding!.sources
              .map((s) => {'title': s.title, 'uri': s.uri})
              .toList(),
        },
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
