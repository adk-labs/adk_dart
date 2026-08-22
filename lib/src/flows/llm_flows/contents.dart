/// LLM flow pipeline components and processors.
library;

import 'dart:convert';

import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../events/rewind_events.dart';
import '../../models/anthropic_llm.dart';
import '../../models/llm_request.dart';
import '../../types/content.dart';
import '_fencing.dart';
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
    final bool preserveFunctionCallIds = agent.canonicalModel is AnthropicLlm;
    final bool includeThoughtsFromOtherAgents =
        invocationContext.runConfig?.includeThoughtsFromOtherAgents ?? false;

    if (agent.includeContents == 'default') {
      llmRequest.contents = getContents(
        currentBranch: invocationContext.branch,
        events: invocationContext.session.events,
        agentName: agent.name,
        preserveFunctionCallIds: preserveFunctionCallIds,
        isolationScope: invocationContext.isolationScope,
        isSingleTurn: agent.mode == 'single_turn',
        userContent: invocationContext.userContent,
        includeThoughtsFromOtherAgents: includeThoughtsFromOtherAgents,
      );
    } else if (agent.includeContents == 'none' ||
        agent.includeContents == 'current_turn') {
      llmRequest.contents = getCurrentTurnContents(
        currentBranch: invocationContext.branch,
        events: invocationContext.session.events,
        agentName: agent.name,
        preserveFunctionCallIds: preserveFunctionCallIds,
        isolationScope: invocationContext.isolationScope,
        isSingleTurn: agent.mode == 'single_turn',
        userContent: invocationContext.userContent,
      );
    }

    final List<Content>? modelInputContext =
        invocationContext.runConfig?.modelInputContext;
    if (modelInputContext != null && modelInputContext.isNotEmpty) {
      _addModelInputContextToUserContent(
        invocationContext,
        llmRequest,
        modelInputContext
            .map((Content content) => content.copyWith())
            .toList(),
      );
    }

    addInstructionsToUserContent(llmRequest, instructionContents);
  }
}

/// Builds context contents from [events] with compaction and branch handling.
List<Content> getContents({
  required String? currentBranch,
  required List<Event> events,
  String agentName = '',
  bool preserveFunctionCallIds = false,
  String? isolationScope,
  bool isSingleTurn = false,
  Content? userContent,
  bool includeThoughtsFromOtherAgents = false,
}) {
  final List<Event> rewindFiltered = _filterRewoundEvents(events);
  final List<Event> rawFiltered = rewindFiltered
      .where(
        (Event event) => shouldIncludeEventInContext(
          currentBranch,
          event,
          isolationScope: isolationScope,
        ),
      )
      .toList(growable: false);

  List<Event> eventsToProcess;
  if (_hasCompactionEvents(rawFiltered)) {
    eventsToProcess = _processCompactionEvents(rawFiltered);
    // Compaction may have removed a function_call whose response survives
    // (e.g. a long-running call resumed after it was compacted); restore it so
    // the call/response pairing is intact.
    eventsToProcess = _recoverCompactedFunctionCalls(
      eventsToProcess,
      rawFiltered,
    );
  } else {
    eventsToProcess = rawFiltered;
  }

  eventsToProcess = _dropOrphanedFunctionResponses(eventsToProcess);

  final List<Event> filtered = <Event>[];
  for (final Event event in eventsToProcess) {
    if (_isOtherAgentReply(agentName, event)) {
      final Event? converted = _presentOtherAgentMessage(
        event,
        includeThoughts: includeThoughtsFromOtherAgents,
      );
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

  final Content? leading = buildTaskInputUserContent(
    events: events,
    isolationScope: isolationScope,
    isSingleTurn: isSingleTurn,
    userContent: userContent,
  );
  if (leading != null) {
    contents.insert(0, leading);
  }
  return contents;
}

/// Returns the current-turn subset of contents for [events].
List<Content> getCurrentTurnContents({
  required String? currentBranch,
  required List<Event> events,
  String agentName = '',
  bool preserveFunctionCallIds = false,
  String? isolationScope,
  bool isSingleTurn = false,
  Content? userContent,
}) {
  for (int i = events.length - 1; i >= 0; i -= 1) {
    final Event event = events[i];
    if (shouldIncludeEventInContext(
          currentBranch,
          event,
          isolationScope: isolationScope,
        ) &&
        (event.author == 'user' || _isOtherAgentReply(agentName, event)) &&
        !_isDirectTransfer(event)) {
      return getContents(
        currentBranch: currentBranch,
        events: events.sublist(i),
        agentName: agentName,
        preserveFunctionCallIds: preserveFunctionCallIds,
        isolationScope: isolationScope,
        isSingleTurn: isSingleTurn,
        userContent: userContent,
      );
    }
  }
  return const <Content>[];
}

/// Inserts instruction contents before trailing user messages.
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

/// Inserts transient model input context before the invocation user content.
///
/// When the invocation has no user content anchor in the request (e.g. live
/// mode or a re-run over existing history), the transient context falls back
/// to the front of the request, before all prior history.
void _addModelInputContextToUserContent(
  InvocationContext invocationContext,
  LlmRequest llmRequest,
  List<Content> modelInputContext,
) {
  if (modelInputContext.isEmpty) {
    return;
  }

  int insertIndex = 0;
  final Content? userContent = invocationContext.userContent;
  if (userContent != null) {
    for (int i = llmRequest.contents.length - 1; i >= 0; i -= 1) {
      if (_contentEquals(llmRequest.contents[i], userContent)) {
        insertIndex = i;
        break;
      }
    }
  }

  llmRequest.contents.insertAll(insertIndex, modelInputContext);
}

/// Structural equality between two contents, mirroring Python's pydantic
/// model comparison for the user-content anchor lookup.
bool _contentEquals(Content a, Content b) {
  if (a.role != b.role || a.parts.length != b.parts.length) {
    return false;
  }
  for (int i = 0; i < a.parts.length; i += 1) {
    final Part left = a.parts[i];
    final Part right = b.parts[i];
    if (left.text != right.text ||
        left.functionCall?.name != right.functionCall?.name ||
        left.functionCall?.id != right.functionCall?.id ||
        left.functionResponse?.name != right.functionResponse?.name ||
        left.functionResponse?.id != right.functionResponse?.id) {
      return false;
    }
  }
  return true;
}

/// Whether [event] should be included in model context.
bool shouldIncludeEventInContext(
  String? currentBranch,
  Event event, {
  String? isolationScope,
}) {
  return event.isolationScope == isolationScope &&
      !containsEmptyContent(event) &&
      isEventBelongsToBranch(currentBranch, event) &&
      !_isAdkFrameworkEvent(event) &&
      !_isAuthEvent(event) &&
      !_isRequestConfirmationEvent(event);
}

/// Rebuilds a scoped task's originating function-call arguments as user text.
Content? buildTaskInputUserContent({
  required List<Event> events,
  required String? isolationScope,
  bool isSingleTurn = false,
  Content? userContent,
}) {
  if (isolationScope == null) {
    return null;
  }

  for (final Event event in events) {
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      continue;
    }
    for (final Part part in content.parts) {
      final FunctionCall? call = part.functionCall;
      if (call == null || call.id != isolationScope || call.args.isEmpty) {
        continue;
      }
      final List<Part> parts = <Part>[Part.text(_taskArgsText(call.args))];
      if (isSingleTurn) {
        parts.add(Part.text(_singleTurnNudge));
      }
      return Content(role: 'user', parts: parts);
    }
  }

  if (userContent != null && userContent.parts.isNotEmpty) {
    final List<Part> parts = userContent.parts
        .map((Part part) => part.copyWith())
        .toList();
    if (isSingleTurn) {
      parts.add(Part.text(_singleTurnNudge));
    }
    return Content(role: 'user', parts: parts);
  }
  return null;
}

const String _singleTurnNudge =
    'Important: You will not receive any user replies or clarifications. '
    'Complete the task using only the information provided above.';

String _taskArgsText(Map<String, dynamic> args) {
  try {
    return jsonEncode(args);
  } catch (_) {
    return '$args';
  }
}

/// Whether [event] contains no visible content for model context.
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

/// Whether [event] belongs to [invocationBranch] context.
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
        isolationScope: event.isolationScope,
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

/// Re-injects function-call events that compaction removed.
///
/// Compaction can summarize away a function_call while a matching
/// function_response survives outside the compacted range. The clearest case
/// is a long-running tool call: the call is compacted along with its
/// intermediate placeholder response, then the real result arrives on resume
/// (a later event not covered by the summary). That surviving response would
/// be orphaned, which breaks call/response pairing during prompt assembly.
///
/// For each response whose call is no longer present, this restores the
/// original call event from [sourceEvents] (the pre-compaction list),
/// inserting it immediately before the first surviving response that
/// references it. The whole call event is re-injected verbatim (rather than
/// trimmed to the resumed call) so parallel-call thought signatures, which only
/// the first part carries, are preserved. Any sibling responses that compaction
/// removed are re-injected too, so a sibling is not surfaced as a phantom
/// pending call.
///
/// [events] is the post-compaction events being assembled into request
/// contents; [sourceEvents] is the pre-compaction events to recover missing
/// calls from. Returns [events] unchanged when nothing needs recovery.
List<Event> _recoverCompactedFunctionCalls(
  List<Event> events,
  List<Event> sourceEvents,
) {
  final Set<String> callIdsPresent = <String>{};
  final Set<String> responseIdsPresent = <String>{};
  for (final Event event in events) {
    for (final FunctionCall functionCall in event.getFunctionCalls()) {
      final String? id = functionCall.id;
      if (id != null && id.isNotEmpty) {
        callIdsPresent.add(id);
      }
    }
    for (final FunctionResponse functionResponse
        in event.getFunctionResponses()) {
      final String? id = functionResponse.id;
      if (id != null && id.isNotEmpty) {
        responseIdsPresent.add(id);
      }
    }
  }

  final Set<String> orphanedIds = responseIdsPresent
      .where((String responseId) => !callIdsPresent.contains(responseId))
      .toSet();
  if (orphanedIds.isEmpty) {
    return events;
  }

  final Map<String, Event> callEventById = <String, Event>{};
  for (final Event event in sourceEvents) {
    for (final FunctionCall functionCall in event.getFunctionCalls()) {
      final String? id = functionCall.id;
      if (id != null && orphanedIds.contains(id)) {
        callEventById.putIfAbsent(id, () => event);
      }
    }
  }

  if (callEventById.isEmpty) {
    return events;
  }

  final Map<String, Event> responseEventById = <String, Event>{};
  for (final Event event in sourceEvents) {
    for (final FunctionResponse functionResponse
        in event.getFunctionResponses()) {
      final String? id = functionResponse.id;
      if (id != null && id.isNotEmpty) {
        responseEventById.putIfAbsent(id, () => event);
      }
    }
  }

  final List<Event> result = <Event>[];
  final Set<String> reinjectedIds = <String>{};
  for (final Event event in events) {
    for (final FunctionResponse functionResponse
        in event.getFunctionResponses()) {
      final String? responseId = functionResponse.id;
      if (responseId == null) {
        continue;
      }
      final Event? callEvent = callEventById[responseId];
      if (callEvent == null || reinjectedIds.contains(responseId)) {
        continue;
      }
      result.add(callEvent);
      final List<String> siblingIds = <String>[
        for (final FunctionCall functionCall in callEvent.getFunctionCalls())
          if (functionCall.id != null && functionCall.id!.isNotEmpty)
            functionCall.id!,
      ];
      reinjectedIds.addAll(siblingIds);
      // Recover sibling responses that compaction removed so a parallel sibling
      // is not left looking like a pending call.
      for (final String siblingId in siblingIds) {
        if (!responseIdsPresent.contains(siblingId)) {
          final Event? siblingResponse = responseEventById[siblingId];
          if (siblingResponse != null) {
            result.add(siblingResponse);
          }
        }
      }
    }
    result.add(event);
  }
  return result;
}

List<Event> _dropOrphanedFunctionResponses(List<Event> events) {
  final Set<String> callIds = <String>{};
  for (final Event event in events) {
    for (final FunctionCall functionCall in event.getFunctionCalls()) {
      if (functionCall.id != null && functionCall.id!.isNotEmpty) {
        callIds.add(functionCall.id!);
      }
    }
  }

  final List<Event> resultEvents = <Event>[];
  for (final Event event in events) {
    final Content? content = event.content;
    final List<Part>? parts = content?.parts;
    if (parts == null || event.getFunctionResponses().isEmpty) {
      resultEvents.add(event);
      continue;
    }

    final List<Part> keptParts = <Part>[];
    for (final Part part in parts) {
      final FunctionResponse? response = part.functionResponse;
      if (response != null &&
          response.id != null &&
          response.id!.isNotEmpty &&
          !callIds.contains(response.id)) {
        continue;
      }
      keptParts.add(part);
    }

    if (keptParts.isEmpty) {
      continue;
    }
    if (keptParts.length != parts.length) {
      final Event updatedEvent = event.copyWith(
        content: content?.copyWith(parts: keptParts),
      );
      resultEvents.add(updatedEvent);
    } else {
      resultEvents.add(event);
    }
  }
  return resultEvents;
}

List<Event> _filterRewoundEvents(List<Event> events) {
  return applyRewinds(events);
}

bool _isOtherAgentReply(String currentAgentName, Event event) {
  if (event.liveSessionId != null && event.liveSessionId!.isNotEmpty) {
    return event.author != 'user';
  }
  return currentAgentName.isNotEmpty &&
      event.author != currentAgentName &&
      event.author != 'user';
}

/// Whether the event is a direct `transfer_to_agent` event.
///
/// When `includeContents='none'` and control is handed to a sub-agent via
/// `transfer_to_agent`, the trailing transfer events (the function call and
/// its response) must not be treated as the start of the current turn.
/// Otherwise the sub-agent's turn would anchor on the parent's transfer event
/// and drop the latest user input. Skipping these events lets the turn anchor
/// on the real user input (or a non-transfer model request) instead, while the
/// transfer events are still included as context.
bool _isDirectTransfer(Event event) {
  if (event.actions.transferToAgent != null) {
    return true;
  }
  final Content? content = event.content;
  if (content == null || content.parts.isEmpty) {
    return false;
  }
  return content.parts.any(
    (Part part) =>
        part.functionCall != null &&
        part.functionCall!.name == 'transfer_to_agent',
  );
}

Event? _presentOtherAgentMessage(Event event, {bool includeThoughts = false}) {
  final Content? original = event.content;
  if (original == null || original.parts.isEmpty) {
    return event;
  }

  final Content content = Content(
    role: 'user',
    parts: <Part>[Part.text(otherAgentContextPreamble)],
  );
  for (final Part part in original.parts) {
    if (part.thought) {
      if (includeThoughts &&
          part.text != null &&
          part.text!.trim().isNotEmpty) {
        content.parts.add(
          Part.text('[${event.author}] thought:\n${quoteUntrusted(part.text!)}'),
        );
      }
      continue;
    }
    if (part.text != null && part.text!.trim().isNotEmpty) {
      content.parts.add(
        Part.text('[${event.author}] said:\n${quoteUntrusted(part.text!)}'),
      );
      continue;
    }
    if (part.functionCall != null) {
      final Map<String, dynamic> rawArgs = part.functionCall!.args;
      final List<String> sortedKeys = rawArgs.keys.toList()..sort();
      final Map<String, dynamic> sortedArgs = <String, dynamic>{
        for (final String k in sortedKeys) k: rawArgs[k],
      };
      content.parts.add(
        Part.text(
          '[${event.author}] called tool `${elideQuoteMarkers(part.functionCall!.name)}` with parameters:\n'
          '${quoteUntrusted(sortedArgs.toString())}',
        ),
      );
      continue;
    }
    if (part.functionResponse != null) {
      content.parts.add(
        Part.text(
          '[${event.author}] `${elideQuoteMarkers(part.functionResponse!.name)}` tool returned result:\n'
          '${quoteUntrusted(part.functionResponse!.response.toString())}',
        ),
      );
      continue;
    }
    if (part.codeExecutionResult != null ||
        part.inlineData != null ||
        part.fileData != null ||
        part.executableCode != null) {
      content.parts.add(part.copyWith());
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
    isolationScope: event.isolationScope,
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

bool _isAdkFrameworkEvent(Event event) {
  return _isFunctionCallEvent(event, 'adk_framework');
}
