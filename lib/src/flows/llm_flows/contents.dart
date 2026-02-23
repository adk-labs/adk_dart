import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../models/llm_request.dart';
import '../../types/content.dart';
import 'base_llm_flow.dart';
import 'functions.dart';

/// Builds request contents from session events with ADK-level filtering.
class ContentsLlmRequestProcessor extends BaseLlmRequestProcessor {
  @override
  Stream<Event> runAsync(
    InvocationContext invocationContext,
    LlmRequest llmRequest,
  ) async* {
    final LlmAgent agent = invocationContext.agent as LlmAgent;
    final List<Content> instructionContents = llmRequest.contents
        .map((Content content) => content.copyWith())
        .toList(growable: false);

    if (agent.includeContents == 'default') {
      llmRequest.contents = getContents(
        currentBranch: invocationContext.branch,
        events: invocationContext.session.events,
        agentName: agent.name,
      );
    } else if (agent.includeContents == 'none' ||
        agent.includeContents == 'current_turn') {
      llmRequest.contents = getCurrentTurnContents(
        currentBranch: invocationContext.branch,
        events: invocationContext.session.events,
        agentName: agent.name,
      );
    }

    addInstructionsToUserContent(llmRequest, instructionContents);
  }
}

List<Content> getContents({
  required String? currentBranch,
  required List<Event> events,
  String agentName = '',
  bool preserveFunctionCallIds = false,
}) {
  final List<Event> rewindFiltered = _filterRewoundEvents(events);
  final List<Event> rawFiltered = rewindFiltered
      .where((Event event) => shouldIncludeEventInContext(currentBranch, event))
      .toList(growable: false);

  final List<Event> eventsToProcess = _hasCompactionEvents(rawFiltered)
      ? _processCompactionEvents(rawFiltered)
      : rawFiltered;

  final List<Event> filtered = <Event>[];
  for (final Event event in eventsToProcess) {
    if (_isOtherAgentReply(agentName, event)) {
      final Event? converted = _presentOtherAgentMessage(event);
      if (converted != null) {
        filtered.add(converted);
      }
      continue;
    }
    filtered.add(event);
  }

  final List<Content> contents = <Content>[];
  for (final Event event in filtered) {
    final Content? content = event.content?.copyWith();
    if (content == null) {
      continue;
    }
    if (!preserveFunctionCallIds) {
      removeClientFunctionCallId(content);
    }
    contents.add(content);
  }
  return contents;
}

List<Content> getCurrentTurnContents({
  required String? currentBranch,
  required List<Event> events,
  String agentName = '',
  bool preserveFunctionCallIds = false,
}) {
  for (int i = events.length - 1; i >= 0; i -= 1) {
    final Event event = events[i];
    if (shouldIncludeEventInContext(currentBranch, event) &&
        (event.author == 'user' || _isOtherAgentReply(agentName, event))) {
      return getContents(
        currentBranch: currentBranch,
        events: events.sublist(i),
        agentName: agentName,
        preserveFunctionCallIds: preserveFunctionCallIds,
      );
    }
  }
  return const <Content>[];
}

void addInstructionsToUserContent(
  LlmRequest llmRequest,
  List<Content> instructionContents,
) {
  if (instructionContents.isEmpty) {
    return;
  }

  int insertIndex = llmRequest.contents.length;
  for (int i = llmRequest.contents.length - 1; i >= 0; i -= 1) {
    final Content content = llmRequest.contents[i];
    if (content.role != 'user') {
      insertIndex = i + 1;
      break;
    }
    if (_contentContainsFunctionResponse(content)) {
      insertIndex = i + 1;
      break;
    }
    insertIndex = i;
  }

  llmRequest.contents.insertAll(
    insertIndex,
    instructionContents.map((Content content) => content.copyWith()),
  );
}

bool shouldIncludeEventInContext(String? currentBranch, Event event) {
  return !containsEmptyContent(event) &&
      isEventBelongsToBranch(currentBranch, event) &&
      !_isAdkFrameworkEvent(event) &&
      !_isAuthEvent(event) &&
      !_isRequestConfirmationEvent(event) &&
      !_isRequestInputEvent(event);
}

bool containsEmptyContent(Event event) {
  if (event.actions.compaction != null) {
    return false;
  }

  final Content? content = event.content;
  if (content == null || content.role == null || content.parts.isEmpty) {
    return true;
  }
  return content.parts.every(_isPartInvisible);
}

bool isEventBelongsToBranch(String? invocationBranch, Event event) {
  if (invocationBranch == null || invocationBranch.isEmpty) {
    return true;
  }
  if (event.branch == null || event.branch!.isEmpty) {
    return true;
  }
  return invocationBranch == event.branch ||
      invocationBranch.startsWith('${event.branch}.');
}

bool _isPartInvisible(Part part) {
  if (part.functionCall != null || part.functionResponse != null) {
    return false;
  }
  return part.thought || !(part.hasText || part.codeExecutionResult != null);
}

bool _hasCompactionEvents(List<Event> events) {
  return events.any((Event event) => event.actions.compaction != null);
}

List<Event> _processCompactionEvents(List<Event> events) {
  final List<(int, double, double, Event)> compactions =
      <(int, double, double, Event)>[];
  for (int i = 0; i < events.length; i += 1) {
    final Event event = events[i];
    final EventCompaction? compaction = event.actions.compaction;
    if (compaction == null) {
      continue;
    }
    compactions.add((
      i,
      compaction.startTimestamp,
      compaction.endTimestamp,
      event,
    ));
  }

  final Set<int> subsumed = <int>{};
  for (final (int eventIndex, double start, double end, Event _)
      in compactions) {
    for (final (int otherIndex, double otherStart, double otherEnd, Event _)
        in compactions) {
      if (otherIndex == eventIndex) {
        continue;
      }
      if (otherStart <= start &&
          otherEnd >= end &&
          (otherStart < start || otherEnd > end || otherIndex > eventIndex)) {
        subsumed.add(eventIndex);
        break;
      }
    }
  }

  final List<(double, int, Event)> processed = <(double, int, Event)>[];
  final List<(double, double)> ranges = <(double, double)>[];
  for (final (int index, double start, double end, Event event)
      in compactions) {
    if (subsumed.contains(index)) {
      continue;
    }
    final EventCompaction compaction = event.actions.compaction!;
    ranges.add((start, end));
    processed.add((
      end,
      index,
      Event(
        timestamp: end,
        invocationId: event.invocationId,
        author: 'model',
        branch: event.branch,
        content: compaction.compactedContent.copyWith(),
        actions: event.actions.copyWith(),
      ),
    ));
  }

  bool isCompacted(double ts) {
    for (final (double start, double end) in ranges) {
      if (start <= ts && ts <= end) {
        return true;
      }
    }
    return false;
  }

  for (int i = 0; i < events.length; i += 1) {
    final Event event = events[i];
    if (event.actions.compaction != null || isCompacted(event.timestamp)) {
      continue;
    }
    processed.add((event.timestamp, i, event));
  }

  processed.sort((a, b) {
    final int tsCompare = a.$1.compareTo(b.$1);
    if (tsCompare != 0) {
      return tsCompare;
    }
    return a.$2.compareTo(b.$2);
  });
  return processed.map((record) => record.$3).toList(growable: false);
}

List<Event> _filterRewoundEvents(List<Event> events) {
  final List<Event> rewindFiltered = <Event>[];
  int i = events.length - 1;
  while (i >= 0) {
    final Event event = events[i];
    final String? rewindBefore = event.actions.rewindBeforeInvocationId;
    if (rewindBefore != null && rewindBefore.isNotEmpty) {
      int target = -1;
      for (int j = 0; j < i; j += 1) {
        if (events[j].invocationId == rewindBefore) {
          target = j;
          break;
        }
      }
      if (target != -1) {
        i = target - 1;
        continue;
      }
    }
    rewindFiltered.add(event);
    i -= 1;
  }
  return rewindFiltered.reversed.toList(growable: false);
}

bool _isOtherAgentReply(String currentAgentName, Event event) {
  return currentAgentName.isNotEmpty &&
      event.author != currentAgentName &&
      event.author != 'user';
}

Event? _presentOtherAgentMessage(Event event) {
  final Content? original = event.content;
  if (original == null || original.parts.isEmpty) {
    return event;
  }

  final Content content = Content(
    role: 'user',
    parts: <Part>[Part.text('For context:')],
  );
  for (final Part part in original.parts) {
    if (part.thought) {
      continue;
    }
    if (part.text != null && part.text!.trim().isNotEmpty) {
      content.parts.add(Part.text('[${event.author}] said: ${part.text}'));
      continue;
    }
    if (part.functionCall != null) {
      content.parts.add(
        Part.text(
          '[${event.author}] called tool `${part.functionCall!.name}` with '
          'parameters: ${part.functionCall!.args}',
        ),
      );
      continue;
    }
    if (part.functionResponse != null) {
      content.parts.add(
        Part.text(
          '[${event.author}] `${part.functionResponse!.name}` tool returned '
          'result: ${part.functionResponse!.response}',
        ),
      );
      continue;
    }
    if (part.codeExecutionResult != null) {
      content.parts.add(
        Part.text('[${event.author}] code execution result was provided.'),
      );
      continue;
    }
  }

  if (content.parts.length == 1) {
    return null;
  }

  return Event(
    timestamp: event.timestamp,
    invocationId: event.invocationId,
    author: 'user',
    branch: event.branch,
    content: content,
  );
}

bool _contentContainsFunctionResponse(Content content) {
  return content.parts.any((Part part) => part.functionResponse != null);
}

bool _isFunctionCallEvent(Event event, String functionName) {
  final Content? content = event.content;
  if (content == null || content.parts.isEmpty) {
    return false;
  }
  for (final Part part in content.parts) {
    if (part.functionCall?.name == functionName ||
        part.functionResponse?.name == functionName) {
      return true;
    }
  }
  return false;
}

bool _isAuthEvent(Event event) {
  return _isFunctionCallEvent(event, requestEucFunctionCallName);
}

bool _isRequestConfirmationEvent(Event event) {
  return _isFunctionCallEvent(event, requestConfirmationFunctionCallName);
}

bool _isRequestInputEvent(Event event) {
  return _isFunctionCallEvent(event, requestInputFunctionCallName);
}

bool _isAdkFrameworkEvent(Event event) {
  return _isFunctionCallEvent(event, 'adk_framework');
}
