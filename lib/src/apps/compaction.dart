/// Event compaction helpers for app-level history management.
library;

import '../events/event.dart';
import '../events/event_actions.dart';
import '../flows/llm_flows/contents.dart' as contents_flow;
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../telemetry/tracing.dart' as tracing;
import '../types/content.dart';
import 'app.dart';

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

List<Event> _longestSelfContainedPrefix(List<Event> events) {
  final Set<String> openIds = <String>{};
  int safeLength = 0;
  for (int index = 0; index < events.length; index += 1) {
    final Event event = events[index];
    openIds.removeAll(_eventFunctionResponseIds(event));
    openIds.addAll(_eventFunctionCallIds(event));
    openIds.addAll(event.actions.requestedToolConfirmations.keys);
    openIds.addAll(event.actions.requestedAuthConfigs.keys);
    if (openIds.isEmpty) {
      safeLength = index + 1;
    }
  }
  return events.take(safeLength).toList(growable: false);
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

  final int? promptTokenCount = latestPromptTokenCount(
    events: session.events,
    currentBranch: currentBranch,
    agentName: agentName,
  );
  if (promptTokenCount == null || promptTokenCount < config.tokenThreshold!) {
    return false;
  }

  final double lastCompactedEnd = latestCompactionEndTimestamp(session.events);
  final List<Event> candidates = session.events
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
  eventsToCompact = _longestSelfContainedPrefix(eventsToCompact);
  if (eventsToCompact.isEmpty) {
    return false;
  }

  final Event compactionEvent = await _createCompactionEventWithTrace(
    session: session,
    config: config,
    eventsToCompact: eventsToCompact,
    trigger: 'token_threshold',
    author: agentName,
    branch: currentBranch,
  );
  await sessionService.appendEvent(session: session, event: compactionEvent);
  return true;
}

/// Runs sliding-window compaction for [app] and [session].
Future<bool> runCompactionForSlidingWindow({
  required App app,
  required Session session,
  required BaseSessionService sessionService,
  bool skipTokenCompaction = false,
}) async {
  final EventsCompactionConfig? config = app.eventsCompactionConfig;
  if (config == null) {
    return false;
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
      return true;
    }
  }

  if (!hasSlidingWindowConfig(config)) {
    return false;
  }

  final double lastCompactedEnd = latestCompactionEndTimestamp(session.events);
  final List<Event> candidates = session.events
      .where(
        (Event event) =>
            event.actions.compaction == null &&
            event.timestamp > lastCompactedEnd,
      )
      .toList(growable: false);
  if (candidates.isEmpty) {
    return false;
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
    return false;
  }

  final int keep = config.overlapSize.clamp(0, userInvocations.length);
  final int compactCount = userInvocations.length - keep;
  if (compactCount <= 0) {
    return false;
  }

  final Set<String> invocationIdsToCompact = userInvocations
      .take(compactCount)
      .toSet();
  List<Event> eventsToCompact = candidates
      .where(
        (Event event) => invocationIdsToCompact.contains(event.invocationId),
      )
      .toList(growable: false);
  eventsToCompact = _longestSelfContainedPrefix(eventsToCompact);

  if (eventsToCompact.isEmpty) {
    return false;
  }

  final Event compactionEvent = await _createCompactionEventWithTrace(
    session: session,
    config: config,
    eventsToCompact: eventsToCompact,
    trigger: 'sliding_window',
    author: app.rootAgent.name,
  );
  await sessionService.appendEvent(session: session, event: compactionEvent);
  return true;
}

Future<Event> _createCompactionEventWithTrace({
  required Session session,
  required EventsCompactionConfig config,
  required List<Event> eventsToCompact,
  required String trigger,
  required String author,
  String? branch,
}) {
  return tracing.tracer.inSpanAsync<Event>(
    'compact_events $trigger',
    (tracing.TraceSpanRecord span) async {
      final Content compacted = await summarizeEvents(
        eventsToCompact,
        summarizer: config.summarizer,
      );
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
      span.setAttributes(_buildCompactionResultAttributes(compactionEvent));
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
    for (final Part part in content.parts) {
      final String? text = part.text;
      if (text != null && text.isNotEmpty) {
        totalChars += text.length;
      }
    }
  }
  if (totalChars <= 0) {
    return null;
  }
  return totalChars ~/ 4;
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
