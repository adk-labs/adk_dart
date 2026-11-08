import '../agents/base_agent.dart';
import '../agents/context.dart';
import '../events/event.dart';
import '../events/node_path_builder.dart';
import '../events/request_input.dart';
import '../types/content.dart';
import 'workflow.dart';

/// ReplayManager - unified orchestrator for event rehydration, interception, and sequence barriers.
class ReplayManager {
  /// Creates a replay manager.
  ReplayManager();

  final Map<String, ReplaySequenceBarrier> _parentSequenceBarriers =
      <String, ReplaySequenceBarrier>{};
  final Map<String, List<Event>> _eventsByParent = <String, List<Event>>{};
  final Map<String, List<Event>> _transitiveEventsByParent =
      <String, List<Event>>{};
  int _indexedEventCount = -1;
  String? _indexedInvocationId;

  void _ensureIndex(Context ctx) {
    final List<Event> events = ctx.invocationContext.session.events;
    final String invocationId = ctx.invocationContext.invocationId;
    if (_indexedEventCount != events.length ||
        _indexedInvocationId != invocationId) {
      _buildEventIndex(events, invocationId);
      _indexedEventCount = events.length;
      _indexedInvocationId = invocationId;
    }
  }

  /// Returns indexed events for the active invocation, if any.
  List<Event>? indexedInvocationEvents(Context ctx) {
    _ensureIndex(ctx);
    return _transitiveEventsByParent[''];
  }

  void _buildEventIndex(List<Event> events, String invocationId) {
    _eventsByParent.clear();
    _transitiveEventsByParent.clear();
    final Map<String, String> fcToParent = <String, String>{};

    for (final Event event in events) {
      final bool isActiveInvocation =
          invocationId.isEmpty || event.invocationId == invocationId;
      if (event.author == 'user') {
        if (isActiveInvocation) {
          _indexUserEvent(event, fcToParent);
        }
        continue;
      }

      final String path = event.nodeInfo.path;
      if (path.isEmpty) {
        continue;
      }

      final String parentPath = parentNodePath(path);

      if (isActiveInvocation) {
        _addEventToIndex(parentPath, event);
      }

      // Track interrupts to route future user responses
      final Set<String> interruptIds = <String>{
        ...?event.longRunningToolIds,
        ...event.actions.requestedToolConfirmations.keys,
      };
      for (final String fid in interruptIds) {
        fcToParent[fid] = parentPath;
      }
    }
  }

  void _indexUserEvent(Event event, Map<String, String> fcToParent) {
    final Content? content = event.content;
    if (content == null || content.parts.isEmpty) {
      return;
    }
    bool matched = false;
    final Set<String> addedParents = <String>{};
    for (final Part part in content.parts) {
      final String? frId = part.functionResponse?.id;
      if (frId != null && frId.isNotEmpty && fcToParent.containsKey(frId)) {
        final String parent = fcToParent[frId]!;
        if (!addedParents.contains(parent)) {
          _addEventToIndex(parent, event);
          addedParents.add(parent);
          matched = true;
        }
      }
    }

    if (!matched) {
      // General user prompt event: add to root ("")
      _eventsByParent.putIfAbsent('', () => <Event>[]).add(event);
      _transitiveEventsByParent.putIfAbsent('', () => <Event>[]).add(event);
    }
  }

  void _addEventToIndex(String parentPath, Event event) {
    _eventsByParent.putIfAbsent(parentPath, () => <Event>[]).add(event);

    String curr = parentPath;
    while (curr.isNotEmpty) {
      _transitiveEventsByParent.putIfAbsent(curr, () => <Event>[]).add(event);
      curr = parentNodePath(curr);
    }

    _transitiveEventsByParent.putIfAbsent('', () => <Event>[]).add(event);
  }

  /// Retrieves pre-filtered session events relevant to rehydrating a node path.
  List<Event> getEventsForRehydration(Context ctx, String nodePath) {
    if (nodePath.isEmpty) {
      return <Event>[];
    }

    _ensureIndex(ctx);
    final String parentPath = parentNodePath(nodePath);
    if (parentPath.isEmpty) {
      return ctx.invocationContext.session.events;
    }

    final List<Event> nodeEvents =
        _transitiveEventsByParent[parentPath] ?? <Event>[];
    if (nodeEvents.isEmpty) {
      return ctx.invocationContext.session.events;
    }

    // Top-level user text prompts live under root key ("").
    final List<Event> rootEvents = _eventsByParent[''] ?? <Event>[];
    final List<Event> userPrompts = rootEvents
        .where((Event e) => e.author == 'user' && !nodeEvents.contains(e))
        .toList();

    if (userPrompts.isEmpty) {
      return nodeEvents;
    }

    final List<Event> sessionEvents = ctx.invocationContext.session.events;
    final Set<Event> eventSet = <Event>{...nodeEvents, ...userPrompts};
    return sessionEvents.where(eventSet.contains).toList();
  }

  /// Ensure a sequence barrier is set up for dynamic nodes under parentPath.
  ReplaySequenceBarrier prepareParentSequenceBarrier(
    Context ctx,
    String parentPath,
  ) {
    return _parentSequenceBarriers.putIfAbsent(parentPath, () {
      _ensureIndex(ctx);
      final List<Event> events = _eventsByParent[parentPath] ?? <Event>[];
      final (List<String> seq, Set<String> completed) = _scanSequence(
        events,
        ctx,
        parentPath,
        strictDirectChild: true,
      );
      return ReplaySequenceBarrier(
        seq,
        pending: seq.toSet().difference(completed),
      );
    });
  }

  /// Releases a pending (interrupted) replay barrier key so replayed siblings
  /// do not time out waiting for a slow resumed node.
  Future<void> releasePendingSequence(String parentPath, String key) async {
    final ReplaySequenceBarrier? barrier = _parentSequenceBarriers[parentPath];
    if (barrier != null && barrier.pending.contains(key)) {
      barrier.checkAndAdvance(key);
    }
  }

  (List<String>, Set<String>) _scanSequence(
    List<Event> events,
    Context ctx,
    String basePath, {
    required bool strictDirectChild,
  }) {
    final NodePathBuilder basePathBuilder = NodePathBuilder.fromString(
      basePath,
    );
    final List<String> sequence = <String>[];
    final Set<String> completed = <String>{};

    for (final Event event in events) {
      final String eventNodePath = event.nodeInfo.path;
      final NodePathBuilder eventPathBuilder = NodePathBuilder.fromString(
        eventNodePath,
      );

      if (!eventPathBuilder.isDescendantOf(basePathBuilder)) {
        continue;
      }

      final NodePathBuilder childPath = basePathBuilder.getDirectChild(
        eventPathBuilder,
      );
      if (strictDirectChild && eventPathBuilder != childPath) {
        continue;
      }

      final String segment = childPath.leafSegment;

      if (_isTerminalEvent(event)) {
        final bool hasResult = _eventHasResult(event);
        final bool isInterrupt = _isInterruptEvent(event);
        if (event.errorCode != null && !hasResult && !isInterrupt) {
          if (sequence.contains(segment) && !completed.contains(segment)) {
            sequence.remove(segment);
          }
          continue;
        }
        if (completed.contains(segment)) {
          continue;
        }
        if (sequence.contains(segment)) {
          sequence.remove(segment);
        }
        sequence.add(segment);
        if (!isInterrupt && hasResult) {
          completed.add(segment);
        }
      }
    }

    return (sequence, completed);
  }

  bool _eventHasResult(Event event) {
    return (event.hasOutput && event.output != null) ||
        ((event.nodeInfo.messageAsOutput ?? false) && event.content != null) ||
        event.actions.route != null ||
        event.actions.transferToAgent != null;
  }

  bool _isInterruptEvent(Event event) {
    return (event.longRunningToolIds?.isNotEmpty == true) ||
        event.actions.requestedToolConfirmations.isNotEmpty ||
        getRequestInputInterruptIds(event).isNotEmpty;
  }

  bool _isTerminalEvent(Event event) {
    return event.isFinalResponse() ||
        event.hasOutput ||
        event.actions.route != null ||
        event.errorCode != null ||
        _isInterruptEvent(event);
  }

  /// Advance sequence barrier if initialized for parentPath.
  void advanceSequence(String parentPath, String key) {
    _parentSequenceBarriers[parentPath]?.checkAndAdvance(key);
  }

  /// Wait for sequence barrier if initialized for parentPath.
  Future<void> waitSequence(String parentPath, String key) async {
    await _parentSequenceBarriers[parentPath]?.wait(key);
  }
}

/// Recovered child scan state from event history for replay interception.
class ChildScanState {
  /// Creates a recovered child scan state.
  ChildScanState({
    this.runId = '1',
    this.output,
    this.hasOutput = false,
    this.route,
    Set<String>? interruptIds,
    Set<String>? resolvedIds,
    Map<String, Object?>? resolvedResponses,
    this.errorCode,
    this.transferToAgent,
    this.finishedAfterResume = false,
  }) : interruptIds = interruptIds ?? <String>{},
       resolvedIds = resolvedIds ?? <String>{},
       resolvedResponses = resolvedResponses ?? <String, Object?>{};

  /// Run identifier for this node run.
  final String runId;

  /// Recovered node output, if any.
  final Object? output;

  /// Whether [output] was explicitly recorded.
  final bool hasOutput;

  /// Recovered route, if any.
  final Object? route;

  /// Interrupt IDs emitted by this run.
  final Set<String> interruptIds;

  /// Interrupt IDs resolved by user responses.
  final Set<String> resolvedIds;

  /// Resolved user responses keyed by interrupt ID.
  final Map<String, Object?> resolvedResponses;

  /// Error code if the run failed in a prior turn.
  final String? errorCode;

  /// Target agent name if a transfer was emitted.
  final String? transferToAgent;

  /// Whether the node already reran after resume and finished.
  final bool finishedAfterResume;
}

/// Current in-memory state of a dynamic or static node run.
class DynamicNodeRun {
  /// Creates a dynamic node run state.
  DynamicNodeRun({
    NodeState? state,
    this.recoveredState,
    this.isStatic = false,
    this.output,
    this.route,
    this.transferToAgent,
  }) : state = state ?? NodeState();

  /// Node execution state.
  final NodeState state;

  /// Recovered state from event history, if any.
  final ChildScanState? recoveredState;

  /// Whether this run represents a static graph node.
  final bool isStatic;

  /// Cached output of the run.
  Object? output;

  /// Cached route of the run.
  Object? route;

  /// Cached transfer target of the run.
  String? transferToAgent;
}

/// Decision returned by [checkInterception].
class InterceptionResult {
  /// Creates an interception result.
  InterceptionResult({
    required this.shouldRun,
    this.output,
    this.route,
    Set<String>? interrupts,
    this.resumeInputs,
    this.transferToAgent,
  }) : interrupts = interrupts ?? <String>{};

  /// Whether the node should be executed natively.
  final bool shouldRun;

  /// Whether live node execution should be skipped.
  bool get shouldSkipExecution => !shouldRun;

  /// The cached output to fast-forward or auto-complete with.
  final Object? output;

  /// The cached route to fast-forward with.
  final Object? route;

  /// Unresolved interrupts if the node should stay WAITING.
  final Set<String> interrupts;

  /// Resolved responses to feed into the node if it is rerun.
  final Map<String, Object?>? resumeInputs;

  /// Target agent name if fast-forwarding same-turn transfer.
  final String? transferToAgent;
}

/// Whether a `waitForOutput` node with no recorded outcome runs again.
///
/// Mirrors `_reruns_while_waiting` in Python ADK `_replay_interceptor.py`:
/// only nodes with `rerunOnResume == true` or agent nodes (`BaseAgent` /
/// [AgentNode]) rerun while waiting without an outcome; plain nodes with
/// `waitForOutput == true` stay waiting until a predecessor triggers them.
bool rerunsWhileWaiting(Object node) {
  if (node is BaseAgent) {
    return true;
  }
  if (node is AgentNode) {
    return node.rerunOnResume || true;
  }
  if (node is BaseNode) {
    return node.rerunOnResume;
  }
  final dynamic dyn = node;
  try {
    final Object? v = dyn.rerunOnResume ?? dyn.rerun_on_resume;
    if (v is bool) {
      return v;
    }
  } catch (_) {}
  return false;
}

bool _nodeRerunOnResume(Object node) {
  if (node is BaseNode) {
    return node.rerunOnResume;
  }
  if (node is BaseAgent) {
    return true;
  }
  final dynamic dyn = node;
  try {
    final Object? v = dyn.rerunOnResume ?? dyn.rerun_on_resume;
    if (v is bool) {
      return v;
    }
  } catch (_) {}
  return false;
}

bool _nodeWaitForOutput(Object node) {
  if (node is BaseNode) {
    return node.waitForOutput;
  }
  final dynamic dyn = node;
  try {
    final Object? v = dyn.waitForOutput ?? dyn.wait_for_output;
    if (v is bool) {
      return v;
    }
  } catch (_) {}
  return false;
}

/// Evaluates whether a node's execution should be intercepted based on history.
///
/// Mirrors `check_interception` in Python ADK
/// `src/google/adk/workflow/utils/_replay_interceptor.py`.
InterceptionResult checkInterception({
  required Object node,
  ChildScanState? recovered,
  DynamicNodeRun? currentRun,
}) {
  // Case 1: Same-turn completed, failed, or waiting interception.
  if (currentRun != null && !currentRun.isStatic) {
    if (currentRun.state.status == NodeStatus.completed ||
        currentRun.state.status == NodeStatus.succeeded) {
      return InterceptionResult(
        shouldRun: false,
        output: currentRun.output,
        route: currentRun.route,
        transferToAgent: currentRun.transferToAgent,
      );
    }
    if (currentRun.state.status == NodeStatus.failed) {
      return InterceptionResult(
        shouldRun: true,
        resumeInputs: recovered?.resolvedResponses,
      );
    }
    if (currentRun.state.status == NodeStatus.waiting &&
        currentRun.state.interrupts.isNotEmpty) {
      return InterceptionResult(
        shouldRun: false,
        interrupts: currentRun.state.interrupts.toSet(),
      );
    }
  }

  if (recovered == null) {
    return InterceptionResult(shouldRun: true);
  }

  if (node is Workflow) {
    return InterceptionResult(
      shouldRun: true,
      resumeInputs: recovered.resolvedResponses,
    );
  }

  final bool rerunOnResume = _nodeRerunOnResume(node);
  final bool waitForOutput = _nodeWaitForOutput(node);
  final Set<String> unresolved = recovered.interruptIds.difference(
    recovered.resolvedIds,
  );

  bool shouldRun = false;
  Object? output;
  Object? route;
  Set<String> interrupts = <String>{};
  Map<String, Object?>? resumeInputs;

  if (unresolved.isNotEmpty) {
    // Case 2: Cross-turn unresolved interrupts remain.
    if (rerunOnResume && recovered.resolvedIds.isNotEmpty) {
      final bool hasResult =
          recovered.output != null ||
          recovered.hasOutput ||
          recovered.route != null ||
          recovered.transferToAgent != null;
      if (recovered.finishedAfterResume && (hasResult || !waitForOutput)) {
        output = recovered.output;
        route = recovered.route;
      } else {
        shouldRun = true;
        resumeInputs = recovered.resolvedResponses;
      }
    } else {
      interrupts = unresolved;
    }
  } else if (recovered.errorCode != null) {
    // Case 3: Cross-turn failed in a prior turn.
    shouldRun = true;
    resumeInputs = recovered.resolvedResponses;
  } else if (recovered.route != null ||
      recovered.output != null ||
      recovered.hasOutput ||
      recovered.transferToAgent != null) {
    // Case 4: Cross-turn successfully completed in a prior turn (fast-forward).
    output = recovered.output;
    route = recovered.route;
  } else if (recovered.interruptIds.isNotEmpty) {
    // Case 5: Cross-turn all prior interrupts are resolved, but no output yet.
    if (!rerunOnResume) {
      final Map<String, Object?> childResumeInputs =
          recovered.resolvedResponses;
      if (childResumeInputs.length == 1) {
        output = childResumeInputs.values.first;
      } else {
        output = Map<String, Object?>.from(childResumeInputs);
      }
    } else if (recovered.finishedAfterResume && !waitForOutput) {
      shouldRun = false;
    } else {
      shouldRun = true;
      resumeInputs = recovered.resolvedResponses;
    }
  } else {
    // Case 6: Cross-turn no events, or events contain no output, route, or interrupts.
    if (waitForOutput && rerunsWhileWaiting(node)) {
      shouldRun = true;
      resumeInputs = recovered.resolvedResponses;
    } else if (rerunOnResume) {
      if (recovered.finishedAfterResume) {
        shouldRun = false;
      } else {
        shouldRun = true;
        resumeInputs = recovered.resolvedResponses;
      }
    } else {
      shouldRun = currentRun != null && !currentRun.isStatic;
    }
  }

  return InterceptionResult(
    shouldRun: shouldRun,
    output: output,
    route: route,
    interrupts: interrupts,
    resumeInputs: resumeInputs,
    transferToAgent: recovered.transferToAgent,
  );
}
