/// LLM flow pipeline components and processors.
library;

import 'dart:convert';

import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../events/node_path_builder.dart';
import '../../events/rewind_events.dart';
import '../../models/anthropic_llm.dart';
import '../../models/llm_request.dart';
import '../../types/content.dart';
import '../../utils/content_utils.dart';
import '_fencing.dart';
import 'base_llm_flow.dart';
import 'functions.dart';

List<Event> _filterSingleTurnNodeEvents(
  String? currentBranch,
  List<Event> events, {
  bool isSingleTurn = false,
  String? nodePath,
  bool allowAncestorNodePaths = false,
}) {
  if (!isSingleTurn) {
    return events;
  }
  final List<Event> filtered = events
      .where((Event e) => isEventBelongsToBranch(currentBranch, e))
      .toList(growable: false);
  if (nodePath == null || nodePath.isEmpty) {
    return filtered;
  }
  final NodePathBuilder selfPath = NodePathBuilder.fromString(nodePath);
  if (allowAncestorNodePaths) {
    return filtered
        .where(
          (Event e) =>
              selfPath.includesNodePath(e.nodeInfo.path) ||
              selfPath.isDescendantOf(
                NodePathBuilder.fromString(e.nodeInfo.path),
              ),
        )
        .toList(growable: false);
  }
  return filtered
      .where((Event e) => selfPath.includesNodePath(e.nodeInfo.path))
      .toList(growable: false);
}

Set<String> _collectFunctionCallIds(List<Event> events) {
  final Set<String> ids = <String>{};
  for (final Event event in events) {
    for (final FunctionCall call in event.getFunctionCalls()) {
      if (call.id != null && call.id!.isNotEmpty) {
        ids.add(call.id!);
      }
    }
  }
  return ids;
}

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
        nodePath: invocationContext.nodePath,
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
        nodePath: invocationContext.nodePath,
      );
    }

    final List<Content>? modelInputContext =
        invocationContext.runConfig?.modelInputContext;
    if (modelInputContext != null && modelInputContext.isNotEmpty) {
      _addModelInputContextToUserContent(
        invocationContext,
        llmRequest,
        modelInputContext.map((Content content) => content.copyWith()).toList(),
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
  String? nodePath,
}) {
  final List<Event> rewindFiltered = _filterSingleTurnNodeEvents(
    currentBranch,
    _filterRewoundEvents(events),
    isSingleTurn: isSingleTurn,
    nodePath: nodePath,
    allowAncestorNodePaths: true,
  );
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
  eventsToProcess = _dropOrphanedFunctionCalls(eventsToProcess);

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
    content.parts.removeWhere(isAdkLiveArtifactPart);
    if (content.parts.isEmpty) {
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
  String? nodePath,
}) {
  final List<Event> scopedEvents = _filterSingleTurnNodeEvents(
    currentBranch,
    events,
    isSingleTurn: isSingleTurn,
    nodePath: nodePath,
  );
  final Set<String> toolCallIds = _collectFunctionCallIds(scopedEvents);
  final Set<String> unmatchedResponseIds = <String>{};

  for (int i = scopedEvents.length - 1; i >= 0; i -= 1) {
    final Event event = scopedEvents[i];
    for (final FunctionCall call in event.getFunctionCalls()) {
      if (call.id != null) {
        unmatchedResponseIds.remove(call.id);
      }
    }
    if (event.author == 'user') {
      for (final FunctionResponse response in event.getFunctionResponses()) {
        if (response.id != null && toolCallIds.contains(response.id)) {
          unmatchedResponseIds.add(response.id!);
        }
      }
    }

    if (unmatchedResponseIds.isEmpty &&
        shouldIncludeEventInContext(
          currentBranch,
          event,
          isolationScope: isolationScope,
        ) &&
        (event.author == 'user' || _isOtherAgentReply(agentName, event)) &&
        !_isDirectTransfer(event)) {
      return getContents(
        currentBranch: currentBranch,
        events: scopedEvents.sublist(i),
        agentName: agentName,
        preserveFunctionCallIds: preserveFunctionCallIds,
        isolationScope: isolationScope,
        isSingleTurn: isSingleTurn,
        userContent: userContent,
        nodePath: nodePath,
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
      !isAuthEvent(event) &&
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
  final String? eventBranch = event.branch;
  if (eventBranch == null || eventBranch.isEmpty) {
    return true;
  }
  if (invocationBranch == null || invocationBranch.isEmpty) {
    return !eventBranch.contains('@');
  }
  if (invocationBranch == eventBranch) {
    return true;
  }
  if (invocationBranch.startsWith('$eventBranch.')) {
    return true;
  }
  return false;
}

bool _isPartInvisible(Part part) {
  if (isAdkLiveArtifactPart(part)) {
    return true;
  }
  if (part.functionCall != null || part.functionResponse != null) {
    return false;
  }
  if (part.thoughtSignature != null && part.thoughtSignature!.isNotEmpty) {
    return false;
  }
  return part.thought ||
      !(part.hasText ||
          part.inlineData != null ||
          part.fileData != null ||
          part.executableCode != null ||
          part.codeExecutionResult != null);
}

bool _hasCompactionEvents(List<Event> events) {
  return events.any((Event event) => event.actions.compaction != null);
}

/// Applies non-subsumed compaction events to [events].
List<Event> processCompactionEvents(List<Event> events) =>
    _processCompactionEvents(events);

List<(int, double, double)> _getCompactionRangesForIndexedEvents(
  List<(int, Event)> indexedEvents,
) {
  final List<(int, double, double)> ranges = <(int, double, double)>[];
  final List<(int, double, double)> comparable = <(int, double, double)>[];
  final Set<int> retained = <int>{};
  for (final (int index, Event event) in indexedEvents) {
    final EventCompaction? compaction = event.actions.compaction;
    if (compaction == null) {
      continue;
    }
    final double start = compaction.startTimestamp;
    final double end = compaction.endTimestamp;
    final (int, double, double) item = (index, start, end);
    ranges.add(item);
    if (start.isNaN || end.isNaN) {
      retained.add(index);
    } else {
      comparable.add(item);
    }
  }

  comparable.sort(((int, double, double) a, (int, double, double) b) {
    final int startCmp = a.$2.compareTo(b.$2);
    if (startCmp != 0) {
      return startCmp;
    }
    final int endCmp = b.$3.compareTo(a.$3);
    if (endCmp != 0) {
      return endCmp;
    }
    return b.$1.compareTo(a.$1);
  });

  double? maxEnd;
  for (final (int index, double _, double end) in comparable) {
    if (maxEnd == null || end > maxEnd) {
      retained.add(index);
      maxEnd = end;
    }
  }
  return <(int, double, double)>[
    for (final (int, double, double) item in ranges)
      if (retained.contains(item.$1)) item,
  ];
}

int _bisectRight(List<double> sortedStarts, double value) {
  int lo = 0;
  int hi = sortedStarts.length;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (value < sortedStarts[mid]) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}

List<(double, int, Event)> _processSingleScopeCompactionEvents(
  List<(int, Event)> indexedEvents,
) {
  final List<(int, double, double)> compactionInfos =
      _getCompactionRangesForIndexedEvents(indexedEvents);
  final Set<int> retainedIndexes = <int>{
    for (final (int index, double _, double _) in compactionInfos) index,
  };

  final List<(double, double)> validRanges = <(double, double)>[
    for (final (int _, double start, double end) in compactionInfos)
      if (start <= end) (start, end),
  ]..sort(((double, double) a, (double, double) b) {
    final int startCmp = a.$1.compareTo(b.$1);
    return startCmp != 0 ? startCmp : a.$2.compareTo(b.$2);
  });

  final List<(double, double)> coverage = <(double, double)>[];
  for (final (double start, double end) in validRanges) {
    if (coverage.isNotEmpty && start <= coverage.last.$2) {
      final (double lastStart, double lastEnd) = coverage.last;
      coverage[coverage.length - 1] = (
        lastStart,
        end > lastEnd ? end : lastEnd,
      );
    } else {
      coverage.add((start, end));
    }
  }
  final List<double> coverageStarts = <double>[
    for (final (double start, double _) in coverage) start,
  ];

  bool isTimestampCompacted(double ts) {
    if (ts.isNaN || coverageStarts.isEmpty) {
      return false;
    }
    final int index = _bisectRight(coverageStarts, ts) - 1;
    return index >= 0 && ts <= coverage[index].$2;
  }

  final List<(double, int, Event)> processed = <(double, int, Event)>[];
  for (final (int index, Event event) in indexedEvents) {
    final EventCompaction? compaction = event.actions.compaction;
    if (compaction != null) {
      if (!retainedIndexes.contains(index)) {
        continue;
      }
      final double end = compaction.endTimestamp;
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
    } else if (!isTimestampCompacted(event.timestamp)) {
      processed.add((event.timestamp, index, event));
    }
  }

  return processed;
}

List<Event> _processCompactionEvents(List<Event> events) {
  if (events.isEmpty) {
    return events;
  }
  final String? firstScope = events.first.isolationScope;
  final bool singleScope = events.every(
    (Event e) => e.isolationScope == firstScope,
  );
  final List<(double, int, Event)> processed;
  if (singleScope) {
    processed = _processSingleScopeCompactionEvents(<(int, Event)>[
      for (int i = 0; i < events.length; i += 1) (i, events[i]),
    ]);
  } else {
    final Map<String?, List<(int, Event)>> partitions =
        <String?, List<(int, Event)>>{};
    for (int i = 0; i < events.length; i += 1) {
      final Event event = events[i];
      (partitions[event.isolationScope] ??= <(int, Event)>[]).add((i, event));
    }
    processed = <(double, int, Event)>[
      for (final List<(int, Event)> partition in partitions.values)
        ..._processSingleScopeCompactionEvents(partition),
    ];
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
/// Call ids can be reused. Ownership is resolved in source order before any
/// events are restored: a response belongs to the latest preceding call with
/// its id, even when another call with that id survived compaction.
///
/// [events] is the post-compaction events being assembled into request
/// contents; [sourceEvents] is the pre-compaction events to recover missing
/// calls from. Returns [events] unchanged when nothing needs recovery.
List<Event> _recoverCompactedFunctionCalls(
  List<Event> events,
  List<Event> sourceEvents,
) {
  if (!events.any((Event event) => event.getFunctionResponses().isNotEmpty)) {
    return events;
  }

  final Set<Event> presentEvents = Set<Event>.identity()..addAll(events);
  final Map<String, Event> latestCallById = <String, Event>{};
  final Map<Event, Map<String, Event>> callByResponse =
      Map<Event, Map<String, Event>>.identity();
  final Map<Event, Map<String, Event>> responseByCall =
      Map<Event, Map<String, Event>>.identity();
  final Map<Event, Set<String>> survivingResponses =
      Map<Event, Set<String>>.identity();

  for (final Event event in sourceEvents) {
    for (final FunctionCall functionCall in event.getFunctionCalls()) {
      final String? id = functionCall.id;
      if (id != null && id.isNotEmpty) {
        latestCallById[id] = event;
      }
    }
    for (final FunctionResponse functionResponse
        in event.getFunctionResponses()) {
      final String? responseId = functionResponse.id;
      if (responseId == null || responseId.isEmpty) {
        continue;
      }
      final Event? callEvent = latestCallById[responseId];
      if (callEvent == null) {
        continue;
      }
      (callByResponse[event] ??= <String, Event>{})[responseId] = callEvent;
      if (presentEvents.contains(event)) {
        (survivingResponses[callEvent] ??= <String>{}).add(responseId);
      }
      // Keep the latest update for this occurrence, not a later call that
      // happens to reuse the id. Equal timestamps retain source order.
      final Map<String, Event> callResponses =
          responseByCall[callEvent] ??= <String, Event>{};
      final Event? existing = callResponses[responseId];
      if (existing == null || event.timestamp >= existing.timestamp) {
        callResponses[responseId] = event;
      }
    }
  }

  final List<Event> result = <Event>[];
  final Set<Event> reinjectedCalls = Set<Event>.identity();
  final Set<Event> reinjectedResponses = Set<Event>.identity();
  for (final Event event in events) {
    for (final FunctionResponse functionResponse
        in event.getFunctionResponses()) {
      final String? functionResponseId = functionResponse.id;
      if (functionResponseId == null || functionResponseId.isEmpty) {
        continue;
      }
      final Event? callEvent = callByResponse[event]?[functionResponseId];
      if (callEvent == null ||
          presentEvents.contains(callEvent) ||
          reinjectedCalls.contains(callEvent)) {
        continue;
      }
      result.add(callEvent);
      reinjectedCalls.add(callEvent);
      // Recover sibling responses that compaction removed so a parallel sibling
      // is not left looking like a pending call.
      final Set<String>? survivingForCall = survivingResponses[callEvent];
      final Map<String, Event>? responsesForCall = responseByCall[callEvent];
      for (final FunctionCall siblingCall in callEvent.getFunctionCalls()) {
        final String? siblingId = siblingCall.id;
        if (siblingId == null || siblingId.isEmpty) {
          continue;
        }
        if (survivingForCall == null || !survivingForCall.contains(siblingId)) {
          final Event? siblingResponse = responsesForCall?[siblingId];
          if (siblingResponse != null &&
              !reinjectedResponses.contains(siblingResponse)) {
            result.add(siblingResponse);
            reinjectedResponses.add(siblingResponse);
          }
        }
      }
    }
    result.add(event);
  }
  return reinjectedCalls.isNotEmpty ? result : events;
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

List<Event> _dropOrphanedFunctionCalls(List<Event> events) {
  final Set<String> responseIds = <String>{};
  final Set<String> longRunningIds = <String>{};
  for (final Event event in events) {
    for (final FunctionResponse response in event.getFunctionResponses()) {
      if (response.id != null && response.id!.isNotEmpty) {
        responseIds.add(response.id!);
      }
    }
    if (event.longRunningToolIds != null) {
      longRunningIds.addAll(event.longRunningToolIds!);
    }
  }

  final List<Event> resultEvents = <Event>[];
  for (final Event event in events) {
    final Content? content = event.content;
    final List<Part>? parts = content?.parts;
    if (parts == null || event.getFunctionCalls().isEmpty) {
      resultEvents.add(event);
      continue;
    }

    final List<Part> keptParts = <Part>[];
    for (final Part part in parts) {
      final FunctionCall? call = part.functionCall;
      if (call != null &&
          call.id != null &&
          call.id!.isNotEmpty &&
          !responseIds.contains(call.id) &&
          !longRunningIds.contains(call.id)) {
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
          Part.text(
            '[${event.author}] thought:\n${quoteUntrusted(part.text!)}',
          ),
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
      if (isAdkLiveArtifactPart(part)) {
        continue;
      }
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

/// Whether [event] is an end-user credential exchange event (adk_request_euc).
bool isAuthEvent(Event event) {
  return _isFunctionCallEvent(event, requestEucFunctionCallName);
}

bool _isRequestConfirmationEvent(Event event) {
  return _isFunctionCallEvent(event, requestConfirmationFunctionCallName);
}

bool _isAdkFrameworkEvent(Event event) {
  return _isFunctionCallEvent(event, 'adk_framework');
}
