import 'dart:convert';
import 'dart:developer' as developer;

import '../events/event.dart';
import '../events/event_actions.dart';
import '../events/rewind_events.dart';
import '../flows/llm_flows/contents.dart' as contents_flow;
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../telemetry/tracing.dart' as tracing;
import '../types/content.dart';
import 'app.dart';
import 'base_events_summarizer.dart';

/// Whether [config] has token-threshold compaction parameters configured.
bool hasTokenThresholdConfig(EventsCompactionConfig? config) {
  return config != null &&
      config.tokenThreshold != null &&
      config.eventRetentionSize != null;
}

/// Whether [config] has sliding-window compaction parameters configured.
bool hasSlidingWindowConfig(EventsCompactionConfig? config) {
  return config != null &&
      config.compactionInterval > 0 &&
      config.overlapSize >= 0;
}

Set<String> _eventFunctionCallIds(Event event) {
  return event
      .getFunctionCalls()
      .map((FunctionCall call) => call.id)
      .whereType<String>()
      .toSet();
}

Set<String> _eventFunctionResponseIds(Event event) {
  return event
      .getFunctionResponses()
      .map((FunctionResponse response) => response.id)
      .whereType<String>()
      .toSet();
}

Set<String> _eventResolvedResponseIds(Event event) {
  final Set<String> pendingInEvent = <String>{
    ...event.actions.requestedToolConfirmations.keys,
    ...event.actions.requestedAuthConfigs.keys,
  };
  return _eventFunctionResponseIds(event).difference(pendingInEvent);
}

const Set<String> _syntheticHitlToolNames = <String>{
  'adk_request_confirmation',
  'adk_request_credential',
  'adk_request_input',
};

/// Returns function-call IDs opened in [events] that can never be answered.
Set<String> _provablyDeadCallIds(
  List<Event> events, {
  required List<Event> allEvents,
  required String? newestInvocationId,
}) {
  final Set<String> protectedIds = <String>{};
  final Set<String> answeredIds = <String>{};

  for (final Event event in allEvents) {
    final bool isNewestOrUnscoped =
        event.invocationId.isEmpty || event.invocationId == newestInvocationId;
    final Set<String>? longRunningIds = event.longRunningToolIds;
    if (longRunningIds != null && longRunningIds.isNotEmpty) {
      if (isNewestOrUnscoped) {
        protectedIds.addAll(longRunningIds);
      } else {
        final Set<String> syntheticHitlIds = event
            .getFunctionCalls()
            .where(
              (FunctionCall fc) =>
                  fc.id != null &&
                  fc.id!.isNotEmpty &&
                  _syntheticHitlToolNames.contains(fc.name),
            )
            .map((FunctionCall fc) => fc.id!)
            .toSet();
        protectedIds.addAll(longRunningIds.difference(syntheticHitlIds));
      }
    }
    if (isNewestOrUnscoped) {
      protectedIds.addAll(event.actions.requestedToolConfirmations.keys);
      protectedIds.addAll(event.actions.requestedAuthConfigs.keys);
    }
    answeredIds.addAll(_eventResolvedResponseIds(event));
  }

  final Set<String> deadIds = <String>{};
  for (final Event event in events) {
    if (newestInvocationId != null &&
        newestInvocationId.isNotEmpty &&
        event.invocationId == newestInvocationId) {
      continue;
    }
    for (final String callId in _eventFunctionCallIds(event)) {
      if (!protectedIds.contains(callId) && !answeredIds.contains(callId)) {
        deadIds.add(callId);
      }
    }
  }
  return deadIds;
}

List<Event> _longestSelfContainedPrefix(
  List<Event> events, {
  List<Event>? allEvents,
}) {
  int runPass(Set<String> deadIds) {
    final Set<String> openIds = <String>{};
    int safeLength = 0;
    for (int index = 0; index < events.length; index += 1) {
      final Event event = events[index];
      openIds.removeAll(_eventFunctionResponseIds(event));
      openIds.addAll(_eventFunctionCallIds(event).difference(deadIds));
      openIds.addAll(
        event.actions.requestedToolConfirmations.keys.toSet().difference(
          deadIds,
        ),
      );
      openIds.addAll(
        event.actions.requestedAuthConfigs.keys.toSet().difference(deadIds),
      );
      if (openIds.isEmpty) {
        safeLength = index + 1;
      }
    }
    return safeLength;
  }

  final int safeLength = runPass(const <String>{});
  if (safeLength == events.length) {
    return events;
  }
  if (allEvents == null) {
    return events.take(safeLength).toList(growable: false);
  }
  if (safeLength > 0 &&
      events[safeLength - 1].invocationId != events[safeLength].invocationId) {
    return events.take(safeLength).toList(growable: false);
  }

  String? newestInvocationId;
  for (int i = allEvents.length - 1; i >= 0; i -= 1) {
    final Event event = allEvents[i];
    if (event.invocationId.isNotEmpty && event.actions.compaction == null) {
      newestInvocationId = event.invocationId;
      break;
    }
  }

  final Set<String> deadIds = _provablyDeadCallIds(
    events,
    allEvents: allEvents,
    newestInvocationId: newestInvocationId,
  );
  if (deadIds.isEmpty) {
    return events.take(safeLength).toList(growable: false);
  }

  final int secondPassLength = runPass(deadIds);
  final int finalLength =
      secondPassLength > safeLength ? secondPassLength : safeLength;
  return events.take(finalLength).toList(growable: false);
}

int _safeTokenCompactionSplitIndex({
  required List<Event> candidateEvents,
  required int eventRetentionSize,
}) {
  final int initialSplit = candidateEvents.length - eventRetentionSize;
  if (initialSplit <= 0) {
    return 0;
  }

  final Set<String> unmatchedResponseIds = <String>{};
  int bestSplit = 0;

  for (int i = candidateEvents.length - 1; i >= 0; i -= 1) {
    unmatchedResponseIds.addAll(_eventFunctionResponseIds(candidateEvents[i]));
    unmatchedResponseIds.removeAll(_eventFunctionCallIds(candidateEvents[i]));

    if (unmatchedResponseIds.isEmpty && i <= initialSplit) {
      bestSplit = i;
      break;
    }
  }

  return bestSplit;
}

/// Runs token-threshold compaction when the configured threshold is exceeded.
Future<bool> runCompactionForTokenThresholdConfig({
  required EventsCompactionConfig? config,
  required Session session,
  required BaseSessionService sessionService,
  required String agentName,
  required String? currentBranch,
}) async {
  if (!hasTokenThresholdConfig(config) || config == null) {
    return false;
  }

  final List<Event> events = applyRewinds(session.events);
  final int? promptTokenCount = latestPromptTokenCount(
    events: events,
    currentBranch: currentBranch,
    agentName: agentName,
  );
  if (promptTokenCount == null || promptTokenCount < config.tokenThreshold!) {
    return false;
  }

  final double lastCompactedEnd = latestCompactionEndTimestamp(events);
  final List<Event> candidates = events
      .where(
        (Event event) =>
            event.actions.compaction == null &&
            event.timestamp > lastCompactedEnd,
      )
      .toList(growable: false);

  if (candidates.length <= config.eventRetentionSize!) {
    return false;
  }

  final int splitIndex = config.eventRetentionSize == 0
      ? candidates.length
      : _safeTokenCompactionSplitIndex(
          candidateEvents: candidates,
          eventRetentionSize: config.eventRetentionSize!,
        );
  if (splitIndex <= 0) {
    return false;
  }

  List<Event> eventsToCompact = candidates
      .take(splitIndex)
      .map((Event event) => event.copyWith())
      .toList(growable: false);
  eventsToCompact = _longestSelfContainedPrefix(
    eventsToCompact,
    allEvents: events,
  );
  if (eventsToCompact.isEmpty ||
      !_isRangeWorthCompacting(
        events: events,
        eventsToCompact: eventsToCompact,
      )) {
    return false;
  }

  final Event? compactionEvent = await _createCompactionEventWithTrace(
    session: session,
    config: config,
    events: events,
    eventsToCompact: eventsToCompact,
    trigger: 'token_threshold',
    author: agentName,
    branch: currentBranch,
  );
  if (compactionEvent == null) {
    return false;
  }
  await sessionService.appendEvent(session: session, event: compactionEvent);
  return true;
}

/// Runs sliding-window compaction for [app] and [session].
///
/// Yields the sliding-window compaction event, if one is produced. The caller
/// (the runner loop) is responsible for appending it to the session, so that
/// persistence of this event stays at the runtime's synchronization point.
/// The token-threshold fallback still appends internally via [sessionService].
Stream<Event> runCompactionForSlidingWindow({
  required App app,
  required Session session,
  required BaseSessionService sessionService,
  bool skipTokenCompaction = false,
}) async* {
  final EventsCompactionConfig? config = app.eventsCompactionConfig;
  if (config == null) {
    return;
  }

  if (!skipTokenCompaction) {
    final bool tokenCompacted = await runCompactionForTokenThresholdConfig(
      config: config,
      session: session,
      sessionService: sessionService,
      agentName: app.rootAgent.name,
      currentBranch: null,
    );
    if (tokenCompacted) {
      return;
    }
  }

  if (!hasSlidingWindowConfig(config)) {
    return;
  }

  final List<Event> events = applyRewinds(session.events);
  final double lastCompactedEnd = latestCompactionEndTimestamp(events);
  final List<Event> candidates = events
      .where(
        (Event event) =>
            event.actions.compaction == null &&
            event.timestamp > lastCompactedEnd,
      )
      .toList(growable: false);
  if (candidates.isEmpty) {
    return;
  }

  final List<String> userInvocations = <String>[];
  for (final Event event in candidates) {
    if (event.author != 'user') {
      continue;
    }
    if (userInvocations.contains(event.invocationId)) {
      continue;
    }
    userInvocations.add(event.invocationId);
  }

  if (userInvocations.length < config.compactionInterval) {
    return;
  }

  final int keep = config.overlapSize.clamp(0, userInvocations.length);
  final int compactCount = userInvocations.length - keep;
  if (compactCount <= 0) {
    return;
  }

  final Set<String> invocationIdsToCompact = userInvocations
      .take(compactCount)
      .toSet();
  List<Event> eventsToCompact = candidates
      .where(
        (Event event) => invocationIdsToCompact.contains(event.invocationId),
      )
      .toList(growable: false);
  eventsToCompact = _longestSelfContainedPrefix(
    eventsToCompact,
    allEvents: events,
  );

  if (eventsToCompact.isEmpty ||
      !_isRangeWorthCompacting(
        events: events,
        eventsToCompact: eventsToCompact,
      )) {
    return;
  }

  final Event? compactionEvent = await _createCompactionEventWithTrace(
    session: session,
    config: config,
    events: events,
    eventsToCompact: eventsToCompact,
    trigger: 'sliding_window',
    author: app.rootAgent.name,
  );
  if (compactionEvent != null) {
    yield compactionEvent;
  }
}

Content? _requestContent(Event event) {
  final EventCompaction? compaction = event.actions.compaction;
  if (compaction != null) {
    return compaction.compactedContent;
  }
  return event.content;
}

int _serializedSize(List<Event> events) {
  int total = 0;
  for (final Event event in events) {
    total += _countCharsInContent(_requestContent(event));
  }
  return total;
}

int _promptCharsSaved({
  required List<Event> events,
  required Event compactionEvent,
}) {
  final List<Event> before = contents_flow.processCompactionEvents(events);
  final List<Event> after = contents_flow.processCompactionEvents(<Event>[
    ...events,
    compactionEvent,
  ]);
  return _serializedSize(before) - _serializedSize(after);
}

int _removablePromptChars({
  required List<Event> events,
  required List<Event> eventsToCompact,
}) {
  if (eventsToCompact.isEmpty) {
    return 0;
  }
  double startTs = eventsToCompact.first.timestamp;
  double endTs = eventsToCompact.first.timestamp;
  for (final Event event in eventsToCompact) {
    if (event.timestamp < startTs) {
      startTs = event.timestamp;
    }
    if (event.timestamp > endTs) {
      endTs = event.timestamp;
    }
  }
  final Event weightlessSummary = Event(
    invocationId: '',
    author: 'agent',
    actions: EventActions(
      compaction: EventCompaction(
        startTimestamp: startTs,
        endTimestamp: endTs,
        compactedContent: Content(role: 'model', parts: <Part>[]),
      ),
    ),
  );
  return _promptCharsSaved(events: events, compactionEvent: weightlessSummary);
}

Event? _latestCompactionEvent(List<Event> events) {
  double latestEnd = 0.0;
  int latestIndex = -1;
  Event? latest;
  for (int i = 0; i < events.length; i += 1) {
    final EventCompaction? compaction = events[i].actions.compaction;
    if (compaction == null) {
      continue;
    }
    if (i >= latestIndex && compaction.endTimestamp > latestEnd) {
      latestIndex = i;
      latestEnd = compaction.endTimestamp;
      latest = events[i];
    }
  }
  return latest;
}

int _previousSummaryChars(List<Event> events) {
  final Event? latest = _latestCompactionEvent(events);
  if (latest == null) {
    return 0;
  }
  return _serializedSize(<Event>[latest]);
}

bool _isRangeWorthCompacting({
  required List<Event> events,
  required List<Event> eventsToCompact,
}) {
  return _removablePromptChars(
        events: events,
        eventsToCompact: eventsToCompact,
      ) >
      _previousSummaryChars(events);
}

Future<Event?> _createCompactionEventWithTrace({
  required Session session,
  required EventsCompactionConfig config,
  required List<Event> events,
  required List<Event> eventsToCompact,
  required String trigger,
  required String author,
  String? branch,
}) {
  return tracing.tracer.inSpanAsync<Event?>(
    'compact_events $trigger',
    (tracing.TraceSpanRecord span) async {
      final Object? rawSummarizer = config.summarizer;
      if (rawSummarizer is BaseEventsSummarizer) {
        try {
          final Event? summarizedEvent = await rawSummarizer
              .maybeSummarizeEvents(events: eventsToCompact);
          if (summarizedEvent != null) {
            final int charsSaved = _promptCharsSaved(
              events: events,
              compactionEvent: summarizedEvent,
            );
            span.setAttributes(<String, Object?>{
              ..._buildCompactionResultAttributes(summarizedEvent),
              'gen_ai.compaction.prompt_chars_saved': charsSaved,
            });
          }
          return summarizedEvent;
        } catch (error, stackTrace) {
          developer.log(
            'Failed to compact events ($trigger); skipping compaction: $error',
            name: 'adk_dart.compaction',
            error: error,
            stackTrace: stackTrace,
          );
          return null;
        }
      }

      final Content? compacted = await _summarizeEventsOrNull(
        eventsToCompact,
        summarizer: rawSummarizer,
      );
      if (compacted == null) {
        return null;
      }
      final Event compactionEvent = Event(
        invocationId: 'compaction_${DateTime.now().microsecondsSinceEpoch}',
        author: author,
        branch: branch,
        actions: EventActions(
          skipSummarization: true,
          compaction: EventCompaction(
            startTimestamp: eventsToCompact.first.timestamp,
            endTimestamp: eventsToCompact.last.timestamp,
            compactedContent: compacted,
          ),
        ),
      );
      final int charsSaved = _promptCharsSaved(
        events: events,
        compactionEvent: compactionEvent,
      );
      span.setAttributes(<String, Object?>{
        ..._buildCompactionResultAttributes(compactionEvent),
        'gen_ai.compaction.prompt_chars_saved': charsSaved,
      });
      return compactionEvent;
    },
    attributes: _buildCompactionAttributes(
      sessionId: session.id,
      trigger: trigger,
      summarizerType: _summarizerType(config.summarizer),
      eventCount: eventsToCompact.length,
      tokenThreshold: config.tokenThreshold,
      eventRetentionSize: config.eventRetentionSize,
      compactionInterval: config.compactionInterval,
      overlapSize: config.overlapSize,
    ),
  );
}

Map<String, Object?> _buildCompactionAttributes({
  required String sessionId,
  required String trigger,
  required String summarizerType,
  required int eventCount,
  int? tokenThreshold,
  int? eventRetentionSize,
  int? compactionInterval,
  int? overlapSize,
}) {
  final Map<String, Object?> attributes = <String, Object?>{
    'gen_ai.operation.name': 'compact_events',
    'gen_ai.conversation.id': sessionId,
    'gen_ai.compaction.trigger': trigger,
    'gen_ai.compaction.summarizer_type': summarizerType,
    'gen_ai.compaction.event_count': eventCount,
    'gen_ai.compaction.compaction_interval': compactionInterval,
    'gen_ai.compaction.overlap_size': overlapSize,
  };
  if (tokenThreshold != null) {
    attributes['gen_ai.compaction.token_threshold'] = tokenThreshold;
  }
  if (eventRetentionSize != null) {
    attributes['gen_ai.compaction.event_retention_size'] = eventRetentionSize;
  }
  return attributes;
}

Map<String, Object?> _buildCompactionResultAttributes(Event event) {
  final EventCompaction? compaction = event.actions.compaction;
  if (compaction == null) {
    return const <String, Object?>{};
  }
  return <String, Object?>{
    'gen_ai.compaction.result_event_id': event.id,
    'gen_ai.compaction.start_timestamp': compaction.startTimestamp,
    'gen_ai.compaction.end_timestamp': compaction.endTimestamp,
  };
}

String _summarizerType(Object? summarizer) {
  if (summarizer == null) {
    return 'default';
  }
  return summarizer.runtimeType.toString();
}

/// Returns the latest prompt token count estimate from [events].
int? latestPromptTokenCount({
  required List<Event> events,
  required String? currentBranch,
  required String agentName,
}) {
  for (int i = events.length - 1; i >= 0; i -= 1) {
    final int? found = _extractPromptTokenCount(events[i].usageMetadata);
    if (found != null) {
      return found;
    }
  }

  final List<Content> effectiveContents = contents_flow.getContents(
    currentBranch: currentBranch,
    events: events,
    agentName: agentName,
  );
  int totalChars = 0;
  for (final Content content in effectiveContents) {
    totalChars += _countCharsInContent(content);
  }
  if (totalChars <= 0) {
    return null;
  }
  return totalChars ~/ 4;
}

int _countCharsInContent(Content? content) {
  if (content == null || content.parts.isEmpty) {
    return 0;
  }
  int totalChars = 0;
  for (final Part part in content.parts) {
    final String? text = part.text;
    if (text != null && text.isNotEmpty) {
      totalChars += text.length;
    }
    final FunctionCall? call = part.functionCall;
    if (call != null) {
      totalChars += call.name.length;
      if (call.args.isNotEmpty) {
        try {
          totalChars += jsonEncode(call.args).length;
        } catch (_) {
          totalChars += call.args.toString().length;
        }
      }
    }
    final FunctionResponse? resp = part.functionResponse;
    if (resp != null) {
      totalChars += resp.name.length;
      if (resp.response.isNotEmpty) {
        try {
          totalChars += jsonEncode(resp.response).length;
        } catch (_) {
          totalChars += resp.response.toString().length;
        }
      }
    }
  }
  return totalChars;
}

/// Returns the latest end timestamp among compaction events.
double latestCompactionEndTimestamp(List<Event> events) {
  double latestEnd = 0.0;
  int latestIndex = -1;
  for (int i = 0; i < events.length; i += 1) {
    final EventCompaction? compaction = events[i].actions.compaction;
    if (compaction == null) {
      continue;
    }
    if (i >= latestIndex && compaction.endTimestamp > latestEnd) {
      latestIndex = i;
      latestEnd = compaction.endTimestamp;
    }
  }
  return latestEnd;
}

Future<Content?> _summarizeEventsOrNull(
  List<Event> events, {
  Object? summarizer,
}) async {
  if (summarizer is Function) {
    try {
      final Object? result = Function.apply(summarizer, <Object>[events]);
      final Object? resolved = result is Future ? await result : result;
      if (resolved == null) {
        return null;
      }
      final Content? content = _toContent(resolved);
      if (content != null) {
        return content;
      }
    } catch (error, stackTrace) {
      developer.log(
        'Summarizer failed during event compaction; skipping compaction: $error',
        name: 'adk_dart.compaction',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
  return summarizeEvents(events, summarizer: summarizer);
}

/// Summarizes [events] using [summarizer] or fallback default summarization.
Future<Content> summarizeEvents(
  List<Event> events, {
  Object? summarizer,
}) async {
  if (summarizer is Function) {
    try {
      final Object? result = Function.apply(summarizer, <Object>[events]);
      final Object? resolved = result is Future ? await result : result;
      final Content? content = _toContent(resolved);
      if (content != null) {
        return content;
      }
    } catch (_) {
      // Fall back to default summarization.
    }
  }
  return _defaultSummary(events);
}

Content _defaultSummary(List<Event> events) {
  final List<String> lines = <String>[];
  for (final Event event in events) {
    final Content? content = event.content;
    if (content == null) {
      continue;
    }
    for (final Part part in content.parts) {
      if (part.text != null && part.text!.trim().isNotEmpty) {
        lines.add('[${event.author}] ${part.text!.trim()}');
      } else if (part.functionCall != null) {
        lines.add('[${event.author}] called ${part.functionCall!.name}');
      } else if (part.functionResponse != null) {
        lines.add('[${event.author}] ${part.functionResponse!.name} responded');
      }
      if (lines.length >= 12) {
        break;
      }
    }
    if (lines.length >= 12) {
      break;
    }
  }

  final String summaryText = lines.isEmpty
      ? 'Compacted ${events.length} events.'
      : 'Compacted ${events.length} events:\n${lines.join('\n')}';
  return Content.modelText(summaryText);
}

Content? _toContent(Object? value) {
  if (value is Content) {
    return value.copyWith();
  }
  if (value is String) {
    return Content.modelText(value);
  }
  return null;
}

int? _extractPromptTokenCount(Object? usageMetadata) {
  if (usageMetadata is Map) {
    final Object? raw =
        usageMetadata['promptTokenCount'] ??
        usageMetadata['prompt_token_count'];
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
  }
  return null;
}
