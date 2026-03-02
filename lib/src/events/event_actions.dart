/// Event action models used to carry side-channel run instructions.
library;

import '../types/content.dart';

/// Compaction summary metadata attached to an event.
class EventCompaction {
  /// Creates event compaction metadata.
  EventCompaction({
    required this.startTimestamp,
    required this.endTimestamp,
    required this.compactedContent,
  });

  /// Start timestamp of the compacted range.
  double startTimestamp;

  /// End timestamp of the compacted range.
  double endTimestamp;

  /// Compacted content payload.
  Content compactedContent;
}

/// Mutable action payload attached to one event.
class EventActions {
  /// Creates event actions.
  EventActions({
    this.skipSummarization,
    Map<String, Object?>? stateDelta,
    Map<String, int>? artifactDelta,
    this.transferToAgent,
    this.escalate,
    Map<String, Object>? requestedAuthConfigs,
    Map<String, Object>? requestedToolConfirmations,
    this.compaction,
    this.endOfAgent,
    this.agentState,
    this.rewindBeforeInvocationId,
  }) : stateDelta = stateDelta ?? <String, Object?>{},
       artifactDelta = artifactDelta ?? <String, int>{},
       requestedAuthConfigs = requestedAuthConfigs ?? <String, Object>{},
       requestedToolConfirmations =
           requestedToolConfirmations ?? <String, Object>{};

  /// Whether this event should be excluded from summarization.
  bool? skipSummarization;

  /// State updates produced by the event.
  Map<String, Object?> stateDelta;

  /// Artifact version deltas produced by the event.
  Map<String, int> artifactDelta;

  /// Optional target agent name for transfer.
  String? transferToAgent;

  /// Whether escalation was requested.
  bool? escalate;

  /// Requested auth configurations keyed by tool/operation.
  Map<String, Object> requestedAuthConfigs;

  /// Requested tool confirmations keyed by tool/operation.
  Map<String, Object> requestedToolConfirmations;

  /// Optional compaction metadata.
  EventCompaction? compaction;

  /// Whether this marks the end of the agent run.
  bool? endOfAgent;

  /// Optional serialized agent state snapshot.
  Map<String, Object?>? agentState;

  /// Optional invocation ID to rewind before replay.
  String? rewindBeforeInvocationId;

  /// Returns copied actions with optional overrides.
  EventActions copyWith({
    Object? skipSummarization = _sentinel,
    Map<String, Object?>? stateDelta,
    Map<String, int>? artifactDelta,
    Object? transferToAgent = _sentinel,
    Object? escalate = _sentinel,
    Map<String, Object>? requestedAuthConfigs,
    Map<String, Object>? requestedToolConfirmations,
    Object? compaction = _sentinel,
    Object? endOfAgent = _sentinel,
    Object? agentState = _sentinel,
    Object? rewindBeforeInvocationId = _sentinel,
  }) {
    return EventActions(
      skipSummarization: identical(skipSummarization, _sentinel)
          ? this.skipSummarization
          : skipSummarization as bool?,
      stateDelta: stateDelta ?? Map<String, Object?>.from(this.stateDelta),
      artifactDelta: artifactDelta ?? Map<String, int>.from(this.artifactDelta),
      transferToAgent: identical(transferToAgent, _sentinel)
          ? this.transferToAgent
          : transferToAgent as String?,
      escalate: identical(escalate, _sentinel)
          ? this.escalate
          : escalate as bool?,
      requestedAuthConfigs:
          requestedAuthConfigs ??
          Map<String, Object>.from(this.requestedAuthConfigs),
      requestedToolConfirmations:
          requestedToolConfirmations ??
          Map<String, Object>.from(this.requestedToolConfirmations),
      compaction: identical(compaction, _sentinel)
          ? this.compaction
          : compaction as EventCompaction?,
      endOfAgent: identical(endOfAgent, _sentinel)
          ? this.endOfAgent
          : endOfAgent as bool?,
      agentState: identical(agentState, _sentinel)
          ? (this.agentState == null
                ? null
                : Map<String, Object?>.from(this.agentState!))
          : agentState as Map<String, Object?>?,
      rewindBeforeInvocationId: identical(rewindBeforeInvocationId, _sentinel)
          ? this.rewindBeforeInvocationId
          : rewindBeforeInvocationId as String?,
    );
  }
}

const Object _sentinel = Object();
