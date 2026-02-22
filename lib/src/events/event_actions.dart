import '../types/content.dart';

class EventCompaction {
  EventCompaction({
    required this.startTimestamp,
    required this.endTimestamp,
    required this.compactedContent,
  });

  double startTimestamp;
  double endTimestamp;
  Content compactedContent;
}

class EventActions {
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

  bool? skipSummarization;
  Map<String, Object?> stateDelta;
  Map<String, int> artifactDelta;
  String? transferToAgent;
  bool? escalate;
  Map<String, Object> requestedAuthConfigs;
  Map<String, Object> requestedToolConfirmations;
  EventCompaction? compaction;
  bool? endOfAgent;
  Map<String, Object?>? agentState;
  String? rewindBeforeInvocationId;

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
