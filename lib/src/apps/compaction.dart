import '../events/event.dart';
import '../events/event_actions.dart';
import '../flows/llm_flows/contents.dart' as contents_flow;
import '../sessions/base_session_service.dart';
import '../sessions/session.dart';
import '../types/content.dart';
import 'app.dart';

bool hasTokenThresholdConfig(EventsCompactionConfig? config) {
  return config != null &&
      config.tokenThreshold != null &&
      config.eventRetentionSize != null;
}

bool hasSlidingWindowConfig(EventsCompactionConfig? config) {
  return config != null &&
      config.compactionInterval > 0 &&
      config.overlapSize >= 0;
}

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

  final int splitIndex = candidates.length - config.eventRetentionSize!;
  if (splitIndex <= 0) {
    return false;
  }

  final List<Event> eventsToCompact = candidates
      .take(splitIndex)
      .map((Event event) => event.copyWith())
      .toList(growable: false);
  if (eventsToCompact.isEmpty) {
    return false;
  }

  final Content compacted = await summarizeEvents(
    eventsToCompact,
    summarizer: config.summarizer,
  );

  final Event compactionEvent = Event(
    invocationId: 'compaction_${DateTime.now().microsecondsSinceEpoch}',
    author: agentName,
    branch: currentBranch,
    actions: EventActions(
      skipSummarization: true,
      compaction: EventCompaction(
        startTimestamp: eventsToCompact.first.timestamp,
        endTimestamp: eventsToCompact.last.timestamp,
        compactedContent: compacted,
      ),
    ),
  );
  await sessionService.appendEvent(session: session, event: compactionEvent);
  return true;
}

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
  final List<Event> eventsToCompact = candidates
      .where(
        (Event event) => invocationIdsToCompact.contains(event.invocationId),
      )
      .toList(growable: false);

  if (eventsToCompact.isEmpty) {
    return false;
  }

  final Content compacted = await summarizeEvents(
    eventsToCompact,
    summarizer: config.summarizer,
  );

  final Event compactionEvent = Event(
    invocationId: 'compaction_${DateTime.now().microsecondsSinceEpoch}',
    author: app.rootAgent.name,
    actions: EventActions(
      skipSummarization: true,
      compaction: EventCompaction(
        startTimestamp: eventsToCompact.first.timestamp,
        endTimestamp: eventsToCompact.last.timestamp,
        compactedContent: compacted,
      ),
    ),
  );
  await sessionService.appendEvent(session: session, event: compactionEvent);
  return true;
}

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
