/// LangGraph-backed agent integration APIs.
library;

import 'dart:async';

import '../events/event.dart';
import '../types/content.dart';
import 'base_agent.dart';
import 'invocation_context.dart';

/// Supported LangGraph chat message roles.
enum LangGraphMessageRole { system, user, assistant }

/// A single message sent to or received from LangGraph.
class LangGraphMessage {
  /// Creates a LangGraph message.
  LangGraphMessage({required this.role, required this.content});

  /// Creates a system-role message.
  factory LangGraphMessage.system(String content) {
    return LangGraphMessage(
      role: LangGraphMessageRole.system,
      content: content,
    );
  }

  /// Creates a user-role message.
  factory LangGraphMessage.user(String content) {
    return LangGraphMessage(role: LangGraphMessageRole.user, content: content);
  }

  /// Creates an assistant-role message.
  factory LangGraphMessage.assistant(String content) {
    return LangGraphMessage(
      role: LangGraphMessageRole.assistant,
      content: content,
    );
  }

  /// Message role.
  final LangGraphMessageRole role;

  /// Message text content.
  final String content;
}

/// Callback that invokes a LangGraph workflow.
typedef LangGraphInvoker =
    FutureOr<String> Function({
      required List<LangGraphMessage> messages,
      required String threadId,
    });

/// Callback that reports whether a LangGraph thread already has state.
typedef LangGraphStateChecker = FutureOr<bool> Function(String threadId);

/// Agent that delegates response generation to LangGraph.
class LangGraphAgent extends BaseAgent {
  /// Creates a LangGraph agent.
  LangGraphAgent({
    required super.name,
    required this.invokeGraph,
    this.instruction = '',
    this.hasCheckpointer = false,
    this.hasExistingGraphState,
    super.description = '',
    super.subAgents,
    super.beforeAgentCallback,
    super.afterAgentCallback,
  });

  /// LangGraph invocation callback.
  final LangGraphInvoker invokeGraph;

  /// Optional system instruction injected on fresh graph threads.
  final String instruction;

  /// Whether LangGraph persists conversation state internally.
  final bool hasCheckpointer;

  /// Optional callback to detect existing graph thread state.
  final LangGraphStateChecker? hasExistingGraphState;

  /// Returns a cloned LangGraph agent with optional field overrides.
  @override
  LangGraphAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> cloneUpdate = normalizeCloneUpdate(update);
    validateCloneUpdateFields(
      update: cloneUpdate,
      allowedFields: <String>{
        ...BaseAgent.baseCloneUpdateFields,
        'invokeGraph',
        'instruction',
        'hasCheckpointer',
        'hasExistingGraphState',
      },
    );

    final List<BaseAgent> clonedSubAgents = cloneSubAgentsField(cloneUpdate);
    final LangGraphAgent clonedAgent = LangGraphAgent(
      name: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'name',
        currentValue: name,
      ),
      invokeGraph: cloneFieldValue<LangGraphInvoker>(
        update: cloneUpdate,
        fieldName: 'invokeGraph',
        currentValue: invokeGraph,
      ),
      instruction: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'instruction',
        currentValue: instruction,
      ),
      hasCheckpointer: cloneFieldValue<bool>(
        update: cloneUpdate,
        fieldName: 'hasCheckpointer',
        currentValue: hasCheckpointer,
      ),
      hasExistingGraphState: cloneFieldValue<LangGraphStateChecker?>(
        update: cloneUpdate,
        fieldName: 'hasExistingGraphState',
        currentValue: hasExistingGraphState,
      ),
      description: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'description',
        currentValue: description,
      ),
      subAgents: <BaseAgent>[],
      beforeAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'beforeAgentCallback',
        currentValue: beforeAgentCallback,
      ),
      afterAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'afterAgentCallback',
        currentValue: afterAgentCallback,
      ),
    );
    clonedAgent.subAgents = clonedSubAgents;
    relinkClonedSubAgents(clonedAgent);
    return clonedAgent;
  }

  /// Executes one LangGraph invocation and yields a single model event.
  @override
  Stream<Event> runAsyncImpl(InvocationContext ctx) async* {
    final String threadId = ctx.session.id;
    final bool graphHasState = hasExistingGraphState == null
        ? false
        : await Future<bool>.value(hasExistingGraphState!(threadId));

    final List<LangGraphMessage> messages = <LangGraphMessage>[
      if (instruction.isNotEmpty && !graphHasState)
        LangGraphMessage.system(instruction),
      ...getMessages(ctx.session.events),
    ];

    final String result = await Future<String>.value(
      invokeGraph(messages: messages, threadId: threadId),
    );

    yield Event(
      invocationId: ctx.invocationId,
      author: name,
      branch: ctx.branch,
      content: Content.modelText(result),
    );
  }

  /// Returns LangGraph messages derived from [events].
  List<LangGraphMessage> getMessages(List<Event> events) {
    if (hasCheckpointer) {
      return getLastHumanMessages(events);
    }
    return getConversationWithAgent(events);
  }

  /// Returns trailing user messages for checkpointer-enabled graphs.
  List<LangGraphMessage> getLastHumanMessages(List<Event> events) {
    final List<LangGraphMessage> messages = <LangGraphMessage>[];
    for (final Event event in events.reversed) {
      if (messages.isNotEmpty && event.author != 'user') {
        break;
      }
      if (event.author != 'user') {
        continue;
      }
      final String? text = _extractPrimaryText(event);
      if (text != null && text.isNotEmpty) {
        messages.add(LangGraphMessage.user(text));
      }
    }
    return messages.reversed.toList(growable: false);
  }

  /// Returns conversation messages involving the user and this agent.
  List<LangGraphMessage> getConversationWithAgent(List<Event> events) {
    final List<LangGraphMessage> messages = <LangGraphMessage>[];
    for (final Event event in events) {
      final String? text = _extractPrimaryText(event);
      if (text == null || text.isEmpty) {
        continue;
      }
      if (event.author == 'user') {
        messages.add(LangGraphMessage.user(text));
      } else if (event.author == name) {
        messages.add(LangGraphMessage.assistant(text));
      }
    }
    return messages;
  }

  String? _extractPrimaryText(Event event) {
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      return null;
    }
    return content.parts.first.text;
  }
}
