import 'dart:async';

import '../events/event.dart';
import '../types/content.dart';
import 'base_agent.dart';
import 'invocation_context.dart';

enum LangGraphMessageRole { system, user, assistant }

class LangGraphMessage {
  LangGraphMessage({required this.role, required this.content});

  factory LangGraphMessage.system(String content) {
    return LangGraphMessage(
      role: LangGraphMessageRole.system,
      content: content,
    );
  }

  factory LangGraphMessage.user(String content) {
    return LangGraphMessage(role: LangGraphMessageRole.user, content: content);
  }

  factory LangGraphMessage.assistant(String content) {
    return LangGraphMessage(
      role: LangGraphMessageRole.assistant,
      content: content,
    );
  }

  final LangGraphMessageRole role;
  final String content;
}

typedef LangGraphInvoker =
    FutureOr<String> Function({
      required List<LangGraphMessage> messages,
      required String threadId,
    });

typedef LangGraphStateChecker = FutureOr<bool> Function(String threadId);

class LangGraphAgent extends BaseAgent {
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

  final LangGraphInvoker invokeGraph;
  final String instruction;
  final bool hasCheckpointer;
  final LangGraphStateChecker? hasExistingGraphState;

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

  List<LangGraphMessage> getMessages(List<Event> events) {
    if (hasCheckpointer) {
      return getLastHumanMessages(events);
    }
    return getConversationWithAgent(events);
  }

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
